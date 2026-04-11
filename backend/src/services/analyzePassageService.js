import { getDashScopeConfig } from "../config/env.js";
import { AppError } from "../lib/appError.js";
import { getDashScopeClient } from "../lib/dashscope.js";

// ─────────────────────────────────────────────
// 教授级全文教学分析服务
// 一次 LLM 调用：文章总览 + 段落教学卡 + 关键句详析
// ─────────────────────────────────────────────

const MAX_PARAGRAPHS = 20;
const MAX_KEY_SENTENCES = 12;
const MAX_PARAGRAPH_CHARS = 1200;

function buildAnalyzePassagePrompt({ title, paragraphs, keySentences }) {
  const safeParagraphs = paragraphs.slice(0, MAX_PARAGRAPHS);
  const safeSentences = keySentences.slice(0, MAX_KEY_SENTENCES);

  const paragraphBlock = safeParagraphs
    .map((p, i) => `[P${i + 1}] ${p.text.slice(0, MAX_PARAGRAPH_CHARS)}`)
    .join("\n\n");

  const sentenceBlock = safeSentences
    .map((s) => `[${s.ref}] (来自第${s.paragraphIndex + 1}段) ${s.text}`)
    .join("\n");

  return [
    "你是一位顶级英语教授，正在为一个重要学生逐段逐句拆解一篇英语阅读材料。",
    "你不是摘要器或翻译器。",
    "你的目标是：让学生看完你的分析后，能真正读懂每一句。",
    "你必须只输出一个合法 JSON 对象。不要输出 Markdown、注释或额外文字。",
    "",
    "═══════════════════════",
    "资料标题：" + (title || "未提供"),
    "═══════════════════════",
    "",
    "正文段落：",
    paragraphBlock,
    "",
    "关键句子（需逐句精析）：",
    sentenceBlock,
    "",
    "═══════════════════════",
    "输出规则（严格执行）：",
    "═══════════════════════",
    "",
    "JSON 必须包含三个顶层字段：passage_overview、paragraph_cards、sentence_analyses。",
    "",
    "一、passage_overview 对象：",
    "  article_theme：用中文一段话概括文章真正在谈什么，不要描述格式。",
    "  author_core_question：用中文一句话说清作者真正在回答什么问题。",
    "  progression_path：用中文描述从第1段到最后一段，作者的论证推进路线。",
    "  paragraph_function_map：字符串数组，每项 '第X段｜角色｜一句话功能'。",
    "  syntax_highlights：字符串数组，最值得关注的 3-5 个句法结构。",
    "  reading_traps：字符串数组，学生最容易误读的 3-5 个点。",
    "  vocabulary_highlights：字符串数组，最值得学习的 5-8 个词汇/搭配。",
    "",
    "二、paragraph_cards 数组（每段一项）：",
    "  paragraph_index：段落编号（从0开始）。",
    "  theme：中文，本段到底在说什么（不能是'本段主要讲了...'式的废话）。",
    "  argument_role：必须为以下之一：background / support / objection / transition / evidence / conclusion。",
    "  core_sentence_local_index：段内最关键的一句话的序号（从0开始）。",
    "  keywords：5个本段最重要的英语关键词或短语。",
    "  relation_to_previous：中文，本段和上一段之间的逻辑关系，不要说'承接上文'这类空话。",
    "  exam_value：中文，说清这段内容在阅读理解考试中最可能对应什么题型和什么陷阱。",
    "  teaching_focuses：字符串数组，2-3个具体的教学要点。每一条必须说清'为什么这个点重要'+'学生通常怎么错'。",
    "  student_blind_spot：中文一句话，学生最容易在本段读偏的点。",
    "",
    "三、sentence_analyses 数组（每个关键句一项）：",
    "  sentence_ref：对应输入的 [S_X_Y] 编号。",
    "  natural_chinese_meaning：自然中文义，不要逐词对译，要还原原句的语气和重心。",
    "  sentence_core：直接写清“主语 + 谓语 + 核心宾语/补语”是什么。例：'主语是 a debate, 谓语是 has emerged'。不要说'本句主要讲了...'。",
    "  chunk_breakdown：字符串数组，把句子按自然语义块断开，不是逐词切。",
    "  grammar_points：数组，每项包含 name 和 explanation。只保留真正帮助理解的 1-3 个语法点。explanation 必须说清'它在这句里到底起什么作用'，不要贴标签。",
    "  vocabulary_in_context：数组，每项包含 term 和 meaning。meaning 是本句中的具体含义，不要给通用词典义。",
    "  misread_points：字符串数组，学生最容易在这句话上犯的 1-3 个错误。必须具体，例如'容易把 once known mainly for 误读为主句而忽略真正主干 a debate has emerged'。",
    "  exam_rewrite_points：字符串数组，1-3 条，这句话在阅读理解题中可能怎么被改写出题。必须给出具体改写示例。",
    "  simplified_english：用更简单的英语重写这句话，保持原意。",
    "  mini_exercise：一个针对性微练习，测试学生是否真的理解了本句。",
    "  hierarchy_rebuild：字符串数组（长难句才用）。按'先看主干 → 再加第一层修饰 → 再加第二层修饰'的顺序拆解。短句返回空数组。",
    "  syntactic_variation：用不同句式重写这句话。",
    "  evidence_type：本句在论证中是什么角色：core_claim / supporting_evidence / background_info / counter_argument / transition_signal / conclusion_marker。",
    "",
    "═══════════════════════",
    "质量底线（违反任何一条都视为失败）：",
    "═══════════════════════",
    "1. sentence_core 绝不能是'本句主要讲了...'或'本句说的是...'，必须指出具体的主语+谓语+宾语。",
    "2. natural_chinese_meaning 绝不能是逐词翻译。",
    "3. misread_points 绝不能是泛泛的'注意理解'，必须说清学生具体会怎么误读。",
    "4. exam_rewrite_points 绝不能只说'可能考同义替换'，必须给出具体的替换示例。",
    "5. chunk_breakdown 不能只按逗号切，要按语义关系切。",
    "6. grammar_points 的 explanation 不能只给术语名称，必须说清在本句中的具体作用。",
    "7. teaching_focuses 不能是抽象建议（如'注意语法'），必须是具体的教学行动。",
    "8. 所有中文解释口吻：严谨但平易的英语教授。",
    "9. 如果信息不足，返回空字符串或空数组，不能删字段。"
  ].join("\n");
}

function normalizeArray(value) {
  return Array.isArray(value) ? value : [];
}

function normalizeString(value, fallback = "") {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function firstDefined(raw, keys) {
  for (const key of keys) {
    if (raw?.[key] !== undefined) {
      return raw[key];
    }
  }
  return undefined;
}

function normalizePassageOverview(raw) {
  if (!raw || typeof raw !== "object") {
    return {
      article_theme: "",
      author_core_question: "",
      progression_path: "",
      paragraph_function_map: [],
      syntax_highlights: [],
      reading_traps: [],
      vocabulary_highlights: []
    };
  }
  return {
    article_theme: normalizeString(raw.article_theme),
    author_core_question: normalizeString(raw.author_core_question),
    progression_path: normalizeString(raw.progression_path),
    paragraph_function_map: normalizeArray(raw.paragraph_function_map).map(String),
    syntax_highlights: normalizeArray(raw.syntax_highlights).map(String),
    reading_traps: normalizeArray(raw.reading_traps).map(String),
    vocabulary_highlights: normalizeArray(raw.vocabulary_highlights).map(String)
  };
}

function normalizeParagraphCard(raw) {
  if (!raw || typeof raw !== "object") return null;
  const validRoles = ["background", "support", "objection", "transition", "evidence", "conclusion"];
  const role = validRoles.includes(raw.argument_role) ? raw.argument_role : "support";
  return {
    paragraph_index: typeof raw.paragraph_index === "number" ? raw.paragraph_index : 0,
    theme: normalizeString(raw.theme),
    argument_role: role,
    core_sentence_local_index: typeof raw.core_sentence_local_index === "number" ? raw.core_sentence_local_index : 0,
    keywords: normalizeArray(raw.keywords).map(String).filter(Boolean).slice(0, 8),
    relation_to_previous: normalizeString(raw.relation_to_previous),
    exam_value: normalizeString(raw.exam_value),
    teaching_focuses: normalizeArray(raw.teaching_focuses).map(String).filter(Boolean).slice(0, 4),
    student_blind_spot: normalizeString(raw.student_blind_spot)
  };
}

function normalizeSentenceAnalysis(raw, sourceSentence) {
  if (!raw || typeof raw !== "object") return null;

  const validEvidenceTypes = [
    "core_claim", "supporting_evidence", "background_info",
    "counter_argument", "transition_signal", "conclusion_marker"
  ];
  const evidenceType = validEvidenceTypes.includes(raw.evidence_type)
    ? raw.evidence_type
    : "supporting_evidence";
  const rawVocabulary = firstDefined(raw, ["vocabulary_in_context", "contextual_vocabulary"]);
  const rawMisread = firstDefined(raw, ["misread_points", "common_misreadings"]);
  const rawRewrite = firstDefined(raw, ["exam_rewrite_points", "exam_paraphrase_points"]);
  const rawSimplerRewrite = firstDefined(raw, ["simplified_english", "simpler_rewrite"]);

  return {
    sentence_ref: normalizeString(raw.sentence_ref),
    original_sentence: sourceSentence || normalizeString(raw.original_sentence),
    natural_chinese_meaning: normalizeString(raw.natural_chinese_meaning),
    sentence_core: normalizeString(raw.sentence_core),
    chunk_breakdown: normalizeArray(raw.chunk_breakdown).map(String).filter(Boolean),
    grammar_points: normalizeArray(raw.grammar_points)
      .map((item) => ({
        name: normalizeString(item?.name),
        explanation: normalizeString(item?.explanation)
      }))
      .filter((item) => item.name || item.explanation)
      .slice(0, 3),
    vocabulary_in_context: normalizeArray(rawVocabulary)
      .map((item) => ({
        term: normalizeString(item?.term),
        meaning: normalizeString(item?.meaning)
      }))
      .filter((item) => item.term)
      .slice(0, 6),
    misread_points: normalizeArray(rawMisread).map(String).filter(Boolean).slice(0, 3),
    exam_rewrite_points: normalizeArray(rawRewrite).map(String).filter(Boolean).slice(0, 3),
    simplified_english: normalizeString(rawSimplerRewrite),
    mini_exercise: normalizeString(raw.mini_exercise),
    hierarchy_rebuild: normalizeArray(raw.hierarchy_rebuild).map(String).filter(Boolean),
    syntactic_variation: normalizeString(raw.syntactic_variation),
    evidence_type: evidenceType
  };
}

// ─── 质量门控 ───

function isShallowSentenceCore(core) {
  if (!core) return true;
  const shallowPrefixes = ["本句主要讲", "本句说的是", "这句话主要", "这句讲的", "本句讲了", "this sentence"];
  return shallowPrefixes.some((p) => core.toLowerCase().startsWith(p));
}

function isShallowMisreadPoint(point) {
  if (!point) return true;
  const shallowPatterns = ["注意理解", "注意语法", "注意翻译", "需要注意", "仔细阅读"];
  return shallowPatterns.some((p) => point.includes(p)) && point.length < 15;
}

function validateAnalysisQuality(result) {
  const warnings = [];

  if (!result.passage_overview?.article_theme || result.passage_overview.article_theme.includes("文章主要讲了")) {
    warnings.push("passage_overview.article_theme 太空");
  }
  if (!result.passage_overview?.author_core_question || result.passage_overview.author_core_question.includes("作者真正要回答的问题可以概括为")) {
    warnings.push("passage_overview.author_core_question 太模板化");
  }
  if (!result.passage_overview?.progression_path || result.passage_overview.progression_path.length < 12) {
    warnings.push("passage_overview.progression_path 不够具体");
  }

  if (result.paragraph_cards) {
    for (const card of result.paragraph_cards) {
      if (!card.theme || card.theme.includes("本段主要讲") || card.theme.includes("承担")) {
        warnings.push(`[P${card.paragraph_index}] theme 太空`);
      }
      if ((card.teaching_focuses || []).length === 0) {
        warnings.push(`[P${card.paragraph_index}] teaching_focuses 缺失`);
      }
      if (!card.student_blind_spot || card.student_blind_spot.length < 10) {
        warnings.push(`[P${card.paragraph_index}] student_blind_spot 太弱`);
      }
    }
  }

  if (result.sentence_analyses) {
    for (const sa of result.sentence_analyses) {
      if (isShallowSentenceCore(sa.sentence_core)) {
        warnings.push(`[${sa.sentence_ref}] sentence_core 太浅: "${sa.sentence_core?.slice(0, 40)}"`);
      }
      if (sa.misread_points?.every(isShallowMisreadPoint)) {
        warnings.push(`[${sa.sentence_ref}] misread_points 全部太泛`);
      }
      if (sa.chunk_breakdown?.length <= 1 && sa.original_sentence?.length > 40) {
        warnings.push(`[${sa.sentence_ref}] chunk_breakdown 不足`);
      }
    }
  }

  return warnings;
}

function buildAnalyzePassageRepairPrompt({ title, paragraphs, keySentences, previousResult, warnings }) {
  return [
    buildAnalyzePassagePrompt({ title, paragraphs, keySentences }),
    "",
    "上一次输出质量不够，请你在保持 JSON 结构不变的前提下，重点修复这些问题：",
    warnings.join("；"),
    "",
    "额外要求：",
    "1. paragraph_cards.theme 不要写成“本段主要讲了什么”或“第X段承担什么作用”。",
    "2. teaching_focuses 必须写成具体教学动作，而不是抽象建议。",
    "3. passage_overview 必须像老师带读整篇文章，而不是做摘要。",
    "4. sentence_core 必须指出主语、谓语、核心宾补，不允许再写空泛总结。",
    "",
    "你上一次的 JSON 为：",
    JSON.stringify(previousResult)
  ].join("\n");
}

// ─── JSON 解析 ───

function extractTextContent(content) {
  if (typeof content === "string") return content.trim();
  if (Array.isArray(content)) {
    return content
      .filter((item) => item?.type === "text" && typeof item.text === "string")
      .map((item) => item.text.trim())
      .join("")
      .trim();
  }
  return "";
}

function tryParseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function extractJsonCandidate(text) {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start >= 0 && end > start) return text.slice(start, end + 1);
  return text;
}

function parseModelJson(content) {
  const text = extractTextContent(content);
  if (!text) {
    throw new AppError("模型没有返回可解析内容。", {
      statusCode: 502,
      code: "MODEL_EMPTY_RESPONSE"
    });
  }

  const directResult = tryParseJson(text);
  if (directResult) return directResult;

  const candidate = extractJsonCandidate(text);
  const fallbackResult = tryParseJson(candidate);
  if (fallbackResult) {
    console.warn("[ai/analyze-passage] recovered JSON from wrapped response");
    return fallbackResult;
  }

  console.error("[ai/analyze-passage] model returned invalid JSON:", text.slice(0, 300));
  throw new AppError("模型返回格式异常，无法解析为 JSON。", {
    statusCode: 502,
    code: "MODEL_INVALID_JSON"
  });
}

// ─── 主函数 ───

export async function analyzePassage({ title = "", paragraphs = [], keySentences = [] }) {
  const client = getDashScopeClient();
  const { modelName } = getDashScopeConfig();

  if (!client) {
    throw new AppError("DASHSCOPE_API_KEY 或 DASHSCOPE_BASE_URL 未配置。", {
      statusCode: 500,
      code: "MODEL_CONFIG_MISSING"
    });
  }

  const sentenceTextIndex = Object.fromEntries(
    keySentences.map((s) => [s.ref, s.text])
  );

  console.log("[ai/analyze-passage] calling model", {
    modelName,
    paragraphCount: paragraphs.length,
    keySentenceCount: keySentences.length,
    titleLength: title.length
  });

  const requestModel = async (prompt) => {
    return client.chat.completions.create({
      model: modelName,
      temperature: 0.15,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content: "你是严格输出 JSON 的英语阅读教学分析引擎。无论任何情况都只返回 JSON 对象。"
        },
        {
          role: "user",
          content: prompt
        }
      ]
    });
  };

  const startTime = Date.now();
  let completion;

  try {
    completion = await requestModel(buildAnalyzePassagePrompt({ title, paragraphs, keySentences }));
  } catch (error) {
    const status = typeof error?.status === "number" ? error.status : undefined;
    console.error("[ai/analyze-passage] model request failed", { status, message: error?.message });
    throw new AppError("调用大模型接口失败。", { statusCode: 502, code: "MODEL_REQUEST_FAILED" });
  }

  const elapsed = Date.now() - startTime;
  const normalizeResult = (parsed) => {
    const overview = normalizePassageOverview(parsed.passage_overview);
    const paragraphCards = normalizeArray(parsed.paragraph_cards)
      .map(normalizeParagraphCard)
      .filter(Boolean);
    const sentenceAnalyses = normalizeArray(parsed.sentence_analyses)
      .map((sa) => normalizeSentenceAnalysis(sa, sentenceTextIndex[sa?.sentence_ref]))
      .filter(Boolean);

    return {
      passage_overview: overview,
      paragraph_cards: paragraphCards,
      sentence_analyses: sentenceAnalyses
    };
  };

  let normalized = normalizeResult(parseModelJson(completion.choices?.[0]?.message?.content));
  let qualityWarnings = validateAnalysisQuality(normalized);

  if (
    qualityWarnings.length >= 2 ||
    normalized.paragraph_cards.length < Math.min(paragraphs.length, MAX_PARAGRAPHS) ||
    normalized.sentence_analyses.length < Math.min(keySentences.length, MAX_KEY_SENTENCES)
  ) {
    console.warn("[ai/analyze-passage] quality warnings after first pass:", qualityWarnings);

    try {
      const repairedCompletion = await requestModel(buildAnalyzePassageRepairPrompt({
        title,
        paragraphs,
        keySentences,
        previousResult: normalized,
        warnings: qualityWarnings
      }));
      const repaired = normalizeResult(parseModelJson(repairedCompletion.choices?.[0]?.message?.content));
      const repairedWarnings = validateAnalysisQuality(repaired);

      if (repairedWarnings.length <= qualityWarnings.length) {
        normalized = repaired;
        qualityWarnings = repairedWarnings;
      }
    } catch (error) {
      console.warn("[ai/analyze-passage] repair pass failed:", error?.message || error);
    }
  }

  if (qualityWarnings.length > 0) {
    console.warn("[ai/analyze-passage] quality warnings:", qualityWarnings);
  }

  console.log("[ai/analyze-passage] done", {
    elapsed: `${elapsed}ms`,
    paragraphCards: paragraphCards.length,
    sentenceAnalyses: sentenceAnalyses.length,
    qualityWarnings: qualityWarnings.length
  });

  return {
    passage_overview: normalized.passage_overview,
    paragraph_cards: normalized.paragraph_cards,
    sentence_analyses: normalized.sentence_analyses,
    quality_warnings: qualityWarnings,
    model_name: modelName,
    elapsed_ms: elapsed
  };
}
