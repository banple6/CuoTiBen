import { createAIClient } from "../models/aiClient.js";
import { attachAIErrorMetadata, createAIError, ERROR_CODES } from "../models/errors.js";
import { createModelRegistry } from "../models/modelRegistry.js";

const MAX_PARAGRAPHS = 4;
const MAX_KEY_SENTENCE_IDS = 6;
const MAX_THEME_LENGTH = 50;
const MAX_RELATION_LENGTH = 60;
const MAX_EXAM_VALUE_LENGTH = 60;
const MAX_BLIND_SPOT_LENGTH = 50;
const MAX_OVERVIEW_LENGTH = 90;
const ARGUMENT_ROLES = new Set([
  "background",
  "support",
  "objection",
  "transition",
  "evidence",
  "conclusion"
]);
const AUXILIARY_SOURCE_KINDS = new Set([
  "question",
  "answer_key",
  "vocabulary_support",
  "chinese_instruction"
]);
const FORBIDDEN_FIELDS = new Set([
  "grammar_focus",
  "faithful_translation",
  "teaching_interpretation",
  "core_skeleton",
  "chunk_layers",
  "sentence_function",
  "simpler_rewrite",
  "simpler_rewrite_translation",
  "mini_check",
  "sentence_core",
  "translation",
  "main_structure",
  "rewrite_example"
]);

const defaultAnalyzePassageAIClient = createAIClient({
  registry: createModelRegistry()
});

function normalizeString(value, fallback = "") {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function normalizeArray(value) {
  return Array.isArray(value) ? value : [];
}

function clipText(value, maxLength) {
  const normalized = normalizeString(value);
  if (!normalized) {
    return "";
  }

  return normalized.length > maxLength ? `${normalized.slice(0, maxLength - 1).trim()}…` : normalized;
}

function chineseCount(text) {
  return (normalizeString(text).match(/[\u4e00-\u9fff]/g) || []).length;
}

function latinCount(text) {
  return (normalizeString(text).match(/[A-Za-z]/g) || []).length;
}

function isChineseDominant(text) {
  const normalized = normalizeString(text);
  if (!normalized) {
    return false;
  }

  const zh = chineseCount(normalized);
  const latin = latinCount(normalized);
  return zh >= Math.max(4, latin * 0.55);
}

function normalizeChineseSummary(value, fallback, maxLength) {
  const clipped = clipText(value, maxLength);
  if (isChineseDominant(clipped)) {
    return clipped;
  }

  return clipText(fallback, maxLength);
}

function normalizeChineseList(values, maxItems = 4, maxLength = 48) {
  return normalizeArray(values)
    .map((item) => clipText(String(item), maxLength))
    .filter((item) => item && isChineseDominant(item))
    .slice(0, maxItems);
}

function normalizeScore(value, fallback = 0.88) {
  const score = Number(value);
  if (!Number.isFinite(score)) {
    return fallback;
  }

  return Math.max(0, Math.min(1, score));
}

function splitIntoSentences(text) {
  const normalized = normalizeString(text);
  if (!normalized) {
    return [];
  }

  const sentences = normalized
    .split(/(?<=[.!?])\s+|(?<=[。！？])\s*/u)
    .map((item) => item.trim())
    .filter(Boolean);

  if (sentences.length > 0) {
    return sentences;
  }

  return [normalized];
}

function buildSentenceCandidates(paragraph) {
  return splitIntoSentences(paragraph.text).map((sentence, index) => ({
    id: `${paragraph.segment_id}::s${index + 1}`,
    text: sentence
  }));
}

function inferArgumentRole(text, index, total) {
  const lower = normalizeString(text).toLowerCase();

  if (index === 0) {
    return "background";
  }
  if (/(however|but|yet|still|nevertheless|nonetheless)/.test(lower)) {
    return "transition";
  }
  if (/(critics?|opponents?|some argue|objection)/.test(lower)) {
    return "objection";
  }
  if (index === total - 1 && /(therefore|thus|overall|in conclusion|as a result)/.test(lower)) {
    return "conclusion";
  }
  if (/(for example|for instance|according to|evidence|data|because)/.test(lower)) {
    return "evidence";
  }

  return "support";
}

function normalizeArgumentRole(value, fallback) {
  const normalized = normalizeString(value).toLowerCase();
  const aliases = {
    background: "background",
    support: "support",
    supporting: "support",
    objection: "objection",
    counter_argument: "objection",
    transition: "transition",
    evidence: "evidence",
    support_evidence: "evidence",
    conclusion: "conclusion"
  };

  return aliases[normalized] || fallback;
}

function buildPassageContext(payload) {
  const passageParagraphs = normalizeArray(payload?.paragraphs)
    .filter((item) => item?.source_kind === "passage_body")
    .slice(0, MAX_PARAGRAPHS)
    .map((item, index) => ({
      segment_id: normalizeString(item.segment_id),
      index: Number.isInteger(item.index) ? item.index : index,
      anchor_label: normalizeString(item.anchor_label) || `P${index + 1}`,
      text: normalizeString(item.text),
      source_kind: "passage_body",
      hygiene_score: normalizeScore(item.hygiene_score)
    }));

  const sentenceCandidatesBySegment = new Map();
  const validSentenceIds = new Set();
  const paragraphBySegmentId = new Map();

  for (const paragraph of passageParagraphs) {
    const candidates = buildSentenceCandidates(paragraph);
    sentenceCandidatesBySegment.set(paragraph.segment_id, candidates);
    paragraphBySegmentId.set(paragraph.segment_id, paragraph);

    for (const candidate of candidates) {
      validSentenceIds.add(candidate.id);
    }
  }

  const auxiliaryBlocks = [
    ...normalizeArray(payload?.question_blocks),
    ...normalizeArray(payload?.answer_blocks),
    ...normalizeArray(payload?.vocabulary_blocks)
  ]
    .filter((item) => AUXILIARY_SOURCE_KINDS.has(item?.source_kind))
    .map((item) => ({
      block_id: normalizeString(item.block_id),
      source_kind: normalizeString(item.source_kind),
      anchor_label: normalizeString(item.anchor_label),
      text: normalizeString(item.text)
    }));

  return {
    passageParagraphs,
    paragraphBySegmentId,
    sentenceCandidatesBySegment,
    validSentenceIds,
    auxiliaryBlocks
  };
}

function buildPassageMapPrompt(payload) {
  const context = buildPassageContext(payload);

  const paragraphBlock = context.passageParagraphs
    .map((paragraph) => {
      const candidates = context.sentenceCandidatesBySegment.get(paragraph.segment_id) || [];
      const sentenceList = candidates
        .map((candidate) => `${candidate.id}: ${candidate.text}`)
        .join("\n");

      return [
        `[${paragraph.segment_id}] 段落序号=${paragraph.index} 锚点=${paragraph.anchor_label}`,
        paragraph.text,
        "本段可选核心句：",
        sentenceList
      ].join("\n");
    })
    .join("\n\n");

  const auxiliaryBlock = context.auxiliaryBlocks.length > 0
    ? context.auxiliaryBlocks.map((block) => `[${block.source_kind}] ${block.text}`).join("\n")
    : "无";

  return [
    "你是一名严格的英语阅读地图级分析引擎。",
    "你只输出一个合法 JSON 对象，不要输出 Markdown、解释或额外文字。",
    "你当前只做全文地图级分析，不做单句深讲。",
    "",
    "你必须只输出这些顶层字段：passage_overview、paragraph_cards、key_sentence_ids、question_links。",
    "严禁输出：grammar_focus、faithful_translation、teaching_interpretation、core_skeleton、chunk_layers、sentence_function、simpler_rewrite、simpler_rewrite_translation、mini_check、sentence_core、translation、main_structure、rewrite_example。",
    "",
    "passage_overview 字段固定为：",
    "- article_theme：中文，点明全文真正讨论什么。",
    "- author_core_question：中文，作者真正追问什么。",
    "- progression_path：中文，说明全文如何推进。",
    "- likely_question_types：中文数组。",
    "- logic_pitfalls：中文数组。",
    "",
    "paragraph_cards 规则：",
    "- 只为 source_kind=passage_body 的段落生成卡片。",
    "- 每段 1 张卡，字段固定为 segment_id、paragraph_index、anchor_label、theme、argument_role、core_sentence_id、relation_to_previous、exam_value、teaching_focuses、student_blind_spot、provenance。",
    "- argument_role 只能是 background/support/objection/transition/evidence/conclusion。",
    "- core_sentence_id 必须从给定候选句 id 中选择。",
    "- provenance 必须包含 source_segment_id、source_sentence_id、source_kind、generated_from、hygiene_score、consistency_score。",
    "",
    "key_sentence_ids 规则：",
    "- 只保留最值得后续 explain-sentence 深讲的句子 id。",
    "- 最多 6 个。",
    "",
    "question_links 规则：",
    "- 只能放 question / answer_key / vocabulary_support / chinese_instruction 这类辅助层线索。",
    "- 不能把这些内容塞进 paragraph_cards。",
    "",
    `标题：${normalizeString(payload?.title) || "未提供"}`,
    "",
    "正文段落：",
    paragraphBlock,
    "",
    "辅助块：",
    auxiliaryBlock
  ].join("\n");
}

function extractJsonObject(text) {
  const normalized = normalizeString(text);
  if (!normalized) {
    return null;
  }

  try {
    return JSON.parse(normalized);
  } catch {
    const start = normalized.indexOf("{");
    const end = normalized.lastIndexOf("}");
    if (start >= 0 && end > start) {
      try {
        return JSON.parse(normalized.slice(start, end + 1));
      } catch {
        return null;
      }
    }
  }

  return null;
}

function normalizePassageOverview(raw) {
  return {
    article_theme: clipText(raw?.article_theme, MAX_OVERVIEW_LENGTH),
    author_core_question: clipText(raw?.author_core_question, MAX_OVERVIEW_LENGTH),
    progression_path: clipText(raw?.progression_path, MAX_OVERVIEW_LENGTH),
    likely_question_types: normalizeChineseList(raw?.likely_question_types, 5, 50),
    logic_pitfalls: normalizeChineseList(raw?.logic_pitfalls, 5, 50)
  };
}

function normalizeCoreSentenceId(rawValue, candidates) {
  const candidateIds = candidates.map((item) => item.id);
  const normalized = normalizeString(rawValue);
  if (candidateIds.includes(normalized)) {
    return normalized;
  }

  const match = normalized.match(/s(\d+)$/i);
  if (match) {
    const candidate = candidateIds[Number(match[1]) - 1];
    if (candidate) {
      return candidate;
    }
  }

  return candidateIds[0] || "";
}

function normalizeProvenance(raw, paragraph, coreSentenceId) {
  return {
    source_segment_id: paragraph.segment_id,
    source_sentence_id: coreSentenceId,
    source_kind: "passage_body",
    generated_from: "ai_passage_analysis",
    hygiene_score: normalizeScore(raw?.hygiene_score, paragraph.hygiene_score),
    consistency_score: normalizeScore(raw?.consistency_score, 0.88)
  };
}

function normalizeParagraphCard(raw, context) {
  const segmentId = normalizeString(raw?.segment_id) || normalizeString(raw?.provenance?.source_segment_id);
  const paragraph = context.paragraphBySegmentId.get(segmentId);
  if (!paragraph || paragraph.source_kind !== "passage_body") {
    return null;
  }

  const candidates = context.sentenceCandidatesBySegment.get(segmentId) || [];
  const fallbackRole = inferArgumentRole(paragraph.text, paragraph.index, context.passageParagraphs.length);
  const coreSentenceId = normalizeCoreSentenceId(raw?.core_sentence_id, candidates);

  return {
    segment_id: paragraph.segment_id,
    paragraph_index: paragraph.index,
    anchor_label: paragraph.anchor_label,
    theme: clipText(raw?.theme, MAX_THEME_LENGTH),
    argument_role: normalizeArgumentRole(raw?.argument_role, fallbackRole),
    core_sentence_id: coreSentenceId,
    relation_to_previous: clipText(raw?.relation_to_previous, MAX_RELATION_LENGTH),
    exam_value: clipText(raw?.exam_value, MAX_EXAM_VALUE_LENGTH),
    teaching_focuses: normalizeChineseList(raw?.teaching_focuses, 3, 40),
    student_blind_spot: clipText(raw?.student_blind_spot, MAX_BLIND_SPOT_LENGTH),
    provenance: normalizeProvenance(raw?.provenance, paragraph, coreSentenceId)
  };
}

function buildAuxiliaryQuestionLinks(payload, context) {
  const linkedSegmentId = context.passageParagraphs.at(-1)?.segment_id || context.passageParagraphs[0]?.segment_id || "";

  return context.auxiliaryBlocks.slice(0, 8).map((block) => ({
    source_kind: block.source_kind,
    block_id: block.block_id,
    linked_segment_id: linkedSegmentId,
    summary: normalizeChineseSummary(
      block.text,
      block.source_kind === "question"
        ? "该题目线索只进入辅助层，不进入正文主导图。"
        : (block.source_kind === "answer_key"
          ? "该答案线索只作为辅助核对信息，不进入正文主导图。"
          : "该词汇或中文说明只作为辅助支持，不进入正文主导图。"),
      60
    )
  }));
}

function normalizeQuestionLinks(raw, payload, context) {
  const direct = normalizeArray(raw)
    .map((item) => ({
      source_kind: normalizeString(item?.source_kind),
      block_id: normalizeString(item?.block_id),
      linked_segment_id: normalizeString(item?.linked_segment_id) || context.passageParagraphs.at(-1)?.segment_id || "",
      summary: clipText(item?.summary, 60)
    }))
    .filter((item) => AUXILIARY_SOURCE_KINDS.has(item.source_kind) && item.summary);

  if (direct.length > 0) {
    return direct.slice(0, 8);
  }

  return buildAuxiliaryQuestionLinks(payload, context);
}

function normalizeAnalyzePassageContract(rawJson, payload) {
  const context = buildPassageContext(payload);
  const paragraphCards = normalizeArray(rawJson?.paragraph_cards)
    .map((item) => normalizeParagraphCard(item, context))
    .filter(Boolean);
  const keySentenceIds = normalizeArray(rawJson?.key_sentence_ids)
    .map((item) => normalizeString(item))
    .filter((item, index, array) => context.validSentenceIds.has(item) && array.indexOf(item) === index)
    .slice(0, MAX_KEY_SENTENCE_IDS);

  return {
    passage_overview: normalizePassageOverview(rawJson?.passage_overview),
    paragraph_cards: paragraphCards,
    key_sentence_ids: keySentenceIds,
    question_links: normalizeQuestionLinks(rawJson?.question_links, payload, context)
  };
}

function collectForbiddenFields(value, bucket = []) {
  if (Array.isArray(value)) {
    for (const item of value) {
      collectForbiddenFields(item, bucket);
    }
    return bucket;
  }

  if (value && typeof value === "object") {
    for (const [key, nested] of Object.entries(value)) {
      if (FORBIDDEN_FIELDS.has(key)) {
        bucket.push(key);
      }
      collectForbiddenFields(nested, bucket);
    }
  }

  return bucket;
}

function validateAnalyzePassageContract(data, payload) {
  const reasons = [];
  const context = buildPassageContext(payload);
  const expectedSegments = new Set(context.passageParagraphs.map((item) => item.segment_id));
  const seenSegments = new Set();

  if (!isChineseDominant(data?.passage_overview?.article_theme)) {
    reasons.push("overview.article_theme");
  }
  if (!isChineseDominant(data?.passage_overview?.author_core_question)) {
    reasons.push("overview.author_core_question");
  }
  if (!isChineseDominant(data?.passage_overview?.progression_path)) {
    reasons.push("overview.progression_path");
  }

  const forbiddenFields = collectForbiddenFields(data);
  if (forbiddenFields.length > 0) {
    reasons.push(`forbidden:${forbiddenFields.join(",")}`);
  }

  for (const card of normalizeArray(data?.paragraph_cards)) {
    if (!expectedSegments.has(card.segment_id)) {
      reasons.push(`unknown_segment:${card.segment_id}`);
      continue;
    }

    const paragraph = context.paragraphBySegmentId.get(card.segment_id);
    const candidates = context.sentenceCandidatesBySegment.get(card.segment_id) || [];
    const candidateIds = new Set(candidates.map((item) => item.id));

    seenSegments.add(card.segment_id);

    if (!ARGUMENT_ROLES.has(card.argument_role)) {
      reasons.push(`invalid_argument_role:${card.segment_id}`);
    }
    if (!candidateIds.has(card.core_sentence_id)) {
      reasons.push(`invalid_core_sentence:${card.segment_id}`);
    }
    if (card.provenance?.source_kind !== "passage_body") {
      reasons.push(`invalid_source_kind:${card.segment_id}`);
    }
    if (card.provenance?.source_segment_id !== paragraph.segment_id) {
      reasons.push(`invalid_provenance_segment:${card.segment_id}`);
    }
    if (card.provenance?.source_sentence_id !== card.core_sentence_id) {
      reasons.push(`invalid_provenance_sentence:${card.segment_id}`);
    }
    if (!isChineseDominant(card.theme)) {
      reasons.push(`theme_not_chinese:${card.segment_id}`);
    }
    if (!isChineseDominant(card.relation_to_previous)) {
      reasons.push(`relation_not_chinese:${card.segment_id}`);
    }
    if (!isChineseDominant(card.exam_value)) {
      reasons.push(`exam_value_not_chinese:${card.segment_id}`);
    }
    if (!isChineseDominant(card.student_blind_spot)) {
      reasons.push(`blind_spot_not_chinese:${card.segment_id}`);
    }
    if (!normalizeArray(card.teaching_focuses).every((item) => isChineseDominant(item))) {
      reasons.push(`teaching_focus_not_chinese:${card.segment_id}`);
    }
  }

  if (seenSegments.size !== context.passageParagraphs.length) {
    reasons.push("missing_paragraph_cards");
  }
  if (normalizeArray(data?.key_sentence_ids).length > MAX_KEY_SENTENCE_IDS) {
    reasons.push("too_many_key_sentence_ids");
  }
  if (!normalizeArray(data?.key_sentence_ids).every((item) => context.validSentenceIds.has(item))) {
    reasons.push("invalid_key_sentence_id");
  }

  return reasons;
}

function buildFallbackOverview(payload, context) {
  const title = normalizeString(payload?.title);
  const paragraphCount = context.passageParagraphs.length;

  return {
    article_theme: normalizeChineseSummary(
      "",
      title
        ? `这篇文章围绕“${title}”展开，重点是先看背景，再看作者把判断推进到哪里。`
        : "这篇文章先交代背景，再推进作者真正关心的判断方向。",
      MAX_OVERVIEW_LENGTH
    ),
    author_core_question: "作者真正关心的是背景信息如何推进成全文的核心判断。",
    progression_path: paragraphCount <= 1
      ? "先建立段落主题，再定位最值得后续深讲的核心句。"
      : "先交代背景或起点，再推进关键转折，最后收束成全文判断。",
    likely_question_types: [
      "主旨题：全文真正关心的问题是什么",
      "段落功能题：各段在推进链路里承担什么角色"
    ],
    logic_pitfalls: [
      "容易把背景段误当成结论段",
      "容易把辅助信息误塞进正文主线"
    ]
  };
}

function buildFallbackTheme(paragraph, role, order) {
  const mapping = {
    background: `第${order}段先交代背景或讨论起点。`,
    support: `第${order}段继续补充支撑作者判断的信息。`,
    objection: `第${order}段提出需要辨认的反向声音或限制条件。`,
    transition: `第${order}段承担推进结构转换的作用。`,
    evidence: `第${order}段提供支撑判断的例证或依据。`,
    conclusion: `第${order}段收束前文并靠近全文结论。`
  };

  return mapping[role] || mapping.support;
}

function buildFallbackRelation(role, index) {
  if (index === 0) {
    return "首段先建立阅读背景，后文都在这个起点上推进。";
  }

  const mapping = {
    transition: "这一段相对前一段完成视角切换或推进换挡。",
    objection: "这一段相对前一段引入需要辨认的反向声音。",
    evidence: "这一段相对前一段补上更具体的证据支撑。",
    conclusion: "这一段相对前一段开始收束并靠近全文判断。"
  };

  return mapping[role] || "这一段相对前一段继续把论证向前推进。";
}

function buildFallbackExamValue(role) {
  const mapping = {
    background: "做题时先把它当背景定位，不要抢成结论。",
    support: "常见于段落功能题或细节支撑题。",
    objection: "要分清这是反方声音还是作者最后立场。",
    transition: "适合抓结构转折与作者思路变化。",
    evidence: "适合定位支撑信息与证据作用。",
    conclusion: "要重点回看它如何收束全文判断。"
  };

  return mapping[role] || mapping.support;
}

function buildFallbackTeachingFocuses(role) {
  const mapping = {
    background: ["先把本段当背景，不要提前替作者下结论。"],
    support: ["先看它支撑的是哪一层判断，再记细节。"],
    objection: ["先辨认这是不是作者真正站队的句子。"],
    transition: ["先盯结构转折词，判断作者论证怎样换挡。"],
    evidence: ["先看证据服务哪层观点，不要只背例子。"],
    conclusion: ["先回收前文信息，再判断它怎样收束全文。"]
  };

  return mapping[role] || mapping.support;
}

function buildFallbackBlindSpot(role) {
  const mapping = {
    background: "最容易把背景说明直接看成作者最后判断。",
    support: "最容易只记细节，却忘了它支撑哪层观点。",
    objection: "最容易把让步或反向声音误判成作者立场。",
    transition: "最容易忽略结构换挡，导致段落关系读散。",
    evidence: "最容易把例证本身当成全文主旨。",
    conclusion: "最容易只看句尾信息，却忘了它是在回收前文。"
  };

  return mapping[role] || mapping.support;
}

function buildParagraphFallbackCard(paragraph, context, order) {
  const role = inferArgumentRole(paragraph.text, order - 1, context.passageParagraphs.length);
  const coreSentenceId = context.sentenceCandidatesBySegment.get(paragraph.segment_id)?.[0]?.id || `${paragraph.segment_id}::s1`;

  return {
    segment_id: paragraph.segment_id,
    paragraph_index: paragraph.index,
    anchor_label: paragraph.anchor_label,
    theme: buildFallbackTheme(paragraph, role, order),
    argument_role: role,
    core_sentence_id: coreSentenceId,
    relation_to_previous: buildFallbackRelation(role, order - 1),
    exam_value: buildFallbackExamValue(role),
    teaching_focuses: buildFallbackTeachingFocuses(role),
    student_blind_spot: buildFallbackBlindSpot(role),
    provenance: {
      source_segment_id: paragraph.segment_id,
      source_sentence_id: coreSentenceId,
      source_kind: "passage_body",
      generated_from: "ai_passage_analysis",
      hygiene_score: normalizeScore(paragraph.hygiene_score, 0.85),
      consistency_score: 0.78
    }
  };
}

function buildAnalyzePassageFallbackSkeleton(payload) {
  const context = buildPassageContext(payload);
  const paragraphCards = context.passageParagraphs.map((paragraph, index) => buildParagraphFallbackCard(paragraph, context, index + 1));

  return {
    passage_overview: buildFallbackOverview(payload, context),
    paragraph_cards: paragraphCards,
    key_sentence_ids: paragraphCards
      .map((card) => card.core_sentence_id)
      .filter((item, index, array) => item && array.indexOf(item) === index)
      .slice(0, MAX_KEY_SENTENCE_IDS),
    question_links: buildAuxiliaryQuestionLinks(payload, context)
  };
}

function toPublicMeta(meta, overrides = {}) {
  return {
    provider: normalizeString(meta?.provider),
    model: normalizeString(meta?.model),
    retry_count: Number(overrides.retry_count ?? meta?.retry_count ?? 0),
    used_cache: Boolean(overrides.used_cache ?? meta?.used_cache),
    used_fallback: Boolean(overrides.used_fallback ?? meta?.used_fallback),
    circuit_state: normalizeString(overrides.circuit_state ?? meta?.circuit_state, "closed")
  };
}

async function requestPassageAnalysis(aiClient, payload, requestId) {
  return aiClient.request({
    requestId,
    routeName: "ai/analyze-passage",
    cacheScope: "passage",
    identity: {
      documentID: payload.identity.document_id,
      contentHash: payload.identity.content_hash
    },
    payload: {
      system: "你是严格输出 JSON 的地图级阅读分析引擎。无论任何情况都只返回 JSON 对象。",
      messages: [
        {
          role: "user",
          content: buildPassageMapPrompt(payload)
        }
      ],
      maxTokens: 8192
    },
    fallbackFactory: async () => buildAnalyzePassageFallbackSkeleton(payload)
  });
}

async function requestPassageRepair(aiClient, payload, previousResult, reasons, requestId) {
  return aiClient.request({
    requestId,
    routeName: "ai/analyze-passage/repair",
    cacheScope: "none",
    payload: {
      system: "你是严格输出 JSON 的地图级阅读分析修复引擎。只能修补给定 JSON，不能扩展成单句精讲。",
      messages: [
        {
          role: "user",
          content: [
            "请修复下面这个地图级全文分析 JSON。",
            "只允许输出顶层字段：passage_overview、paragraph_cards、key_sentence_ids、question_links。",
            "禁止输出任何 sentence-level 深讲字段。",
            `修复原因：${reasons.join(" | ")}`,
            "",
            "输入段落：",
            buildPassageMapPrompt(payload),
            "",
            "上一次结果：",
            JSON.stringify(previousResult)
          ].join("\n")
        }
      ],
      maxTokens: 8192
    }
  });
}

function parseAnalyzePassageText(text) {
  const parsed = extractJsonObject(text);
  if (!parsed || typeof parsed !== "object") {
    return {
      kind: "unparseable_json",
      value: null
    };
  }

  return {
    kind: "ok",
    value: parsed
  };
}

async function repairAnalyzePassageContract(payload, previousResult, reasons, options = {}) {
  const {
    aiClient,
    requestId
  } = options;

  try {
    const repairedResult = await requestPassageRepair(aiClient, payload, previousResult, reasons, requestId);
    const parsed = parseAnalyzePassageText(repairedResult?.data?.text);
    if (parsed.kind !== "ok") {
      return null;
    }

    const normalized = normalizeAnalyzePassageContract(parsed.value, payload);
    const validationReasons = validateAnalyzePassageContract(normalized, payload);
    if (validationReasons.length > 0) {
      return null;
    }

    return {
      data: normalized,
      meta: toPublicMeta(repairedResult.meta)
    };
  } catch {
    return null;
  }
}

export async function analyzePassage(payload, options = {}) {
  const requestId = normalizeString(options.requestId);
  const aiClient = options.aiClient || defaultAnalyzePassageAIClient;

  console.log("[ai/analyze-passage] calling model", {
    requestId,
    paragraphCount: normalizeArray(payload?.paragraphs).length,
    titleLength: normalizeString(payload?.title).length
  });

  let result;
  try {
    result = await requestPassageAnalysis(aiClient, payload, requestId);
  } catch (error) {
    if (error?.code === ERROR_CODES.MODEL_CONFIG_MISSING) {
      throw error;
    }

    throw attachAIErrorMetadata(
      error?.code
        ? error
        : createAIError(ERROR_CODES.INVALID_MODEL_RESPONSE, {
          requestId,
          fallbackAvailable: true
        }),
      {
        requestId,
        routeName: "ai/analyze-passage",
        fallbackAvailable: true
      }
    );
  }

  if (result?.meta?.used_fallback) {
    return {
      data: result.data,
      meta: toPublicMeta(result.meta, { used_fallback: true })
    };
  }

  const parsed = parseAnalyzePassageText(result?.data?.text);
  if (parsed.kind === "unparseable_json") {
    return {
      data: buildAnalyzePassageFallbackSkeleton(payload),
      meta: toPublicMeta(result.meta, { used_fallback: true })
    };
  }

  const normalized = normalizeAnalyzePassageContract(parsed.value, payload);
  const reasons = validateAnalyzePassageContract(normalized, payload);

  if (reasons.length === 0) {
    return {
      data: normalized,
      meta: toPublicMeta(result.meta)
    };
  }

  const repaired = await repairAnalyzePassageContract(payload, parsed.value, reasons, {
    aiClient,
    requestId
  });
  if (repaired) {
    return repaired;
  }

  return {
    data: buildAnalyzePassageFallbackSkeleton(payload),
    meta: toPublicMeta(result.meta, { used_fallback: true })
  };
}

export const __testables = {
  buildPassageMapPrompt,
  normalizeAnalyzePassageContract,
  validateAnalyzePassageContract,
  buildAnalyzePassageFallbackSkeleton,
  splitIntoSentences,
  inferArgumentRole
};
