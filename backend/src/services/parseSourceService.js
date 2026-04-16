import crypto from "crypto";
import { getDashScopeConfig } from "../config/env.js";
import { AppError } from "../lib/appError.js";
import { getDashScopeClient } from "../lib/dashscope.js";

const ENGLISH_STOPWORDS = new Set([
  "a", "an", "and", "are", "as", "at", "be", "been", "being", "by", "for", "from", "had",
  "has", "have", "he", "her", "his", "in", "into", "is", "it", "its", "of", "on", "or",
  "that", "the", "their", "there", "they", "this", "to", "was", "were", "which", "with",
  "would", "should", "could", "can", "may", "might", "will", "not", "we", "our", "you",
  "your", "them", "these", "those", "than", "then", "after", "before", "during", "about"
]);
const COMMON_ENGLISH_LEXICON = new Set([
  "allow", "balance", "contact", "corporation", "cultural", "evidence", "growth", "heading",
  "logical", "museum", "peaceful", "prosperity", "question", "reading", "sustainable",
  "tourism", "visitor", "quantity", "community", "economic", "environmental"
]);

const MAX_SEGMENTS_FOR_MODEL = 36;
const MAX_SENTENCES_PER_SEGMENT_FOR_MODEL = 6;
const MAX_SEGMENT_TEXT_FOR_MODEL = 520;
const MAX_SENTENCE_TEXT_FOR_MODEL = 220;
const MAX_SECTION_TITLES = 8;
const MAX_TOPIC_TAGS = 8;
const MAX_CANDIDATE_KNOWLEDGE_POINTS = 12;
const MAX_OUTLINE_DEPTH = 2;

const GENERIC_NODE_TITLE_PATTERNS = [
  /^section\b/i,
  /^part\b/i,
  /^chapter\b/i,
  /^paragraph\b/i,
  /^node\b/i,
  /^资料(总览|节点|结构)?$/,
  /^正文$/,
  /^引言$/,
  /^结论$/,
  /^背景$/,
  /^分析$/,
  /^总结$/
];

function normalizeWhitespace(value) {
  return value
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/[ \t]+/g, " ")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function cleanParagraph(value) {
  return normalizeWhitespace(value)
    .replace(/\s+/g, " ")
    .trim();
}

function truncate(value, maxLength) {
  if (!value || value.length <= maxLength) {
    return value;
  }

  return `${value.slice(0, maxLength - 1).trim()}…`;
}

function uniqueStrings(values) {
  return [...new Set(values.filter((value) => typeof value === "string" && value.trim()))];
}

function normalizedComparableText(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[\u2018\u2019]/g, "'")
    .replace(/[\u201c\u201d]/g, "\"")
    .replace(/[^a-z0-9\u4e00-\u9fff]+/g, " ")
    .replace(/\b(the|a|an)\b/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function singularizeToken(token) {
  if (token.length <= 4) {
    return token;
  }

  if (token.endsWith("ies")) {
    return `${token.slice(0, -3)}y`;
  }

  if (token.endsWith("sses") || token.endsWith("ss")) {
    return token;
  }

  if (token.endsWith("s")) {
    return token.slice(0, -1);
  }

  return token;
}

function normalizedTermKey(value) {
  return normalizedComparableText(value)
    .split(" ")
    .filter(Boolean)
    .map(singularizeToken)
    .join(" ");
}

function tokenSet(value) {
  return new Set(normalizedTermKey(value).split(" ").filter((item) => item.length >= 2));
}

function tokenJaccard(lhs, rhs) {
  const lhsSet = tokenSet(lhs);
  const rhsSet = tokenSet(rhs);

  if (lhsSet.size === 0 || rhsSet.size === 0) {
    return 0;
  }

  let intersection = 0;
  for (const item of lhsSet) {
    if (rhsSet.has(item)) {
      intersection += 1;
    }
  }

  const union = new Set([...lhsSet, ...rhsSet]).size;
  return union === 0 ? 0 : intersection / union;
}

function cleanNodeLabel(value) {
  return String(value || "")
    .replace(/^[\s\dIVXivx一二三四五六七八九十]+[.、):：\-]?\s*/u, "")
    .replace(/^(section|part|chapter|paragraph)\s+\d+[:：\-]?\s*/i, "")
    .replace(/\s+/g, " ")
    .trim();
}

function isGenericNodeTitle(value) {
  const cleaned = cleanNodeLabel(value);
  if (!cleaned) {
    return true;
  }

  return GENERIC_NODE_TITLE_PATTERNS.some((pattern) => pattern.test(cleaned));
}

function stableNodeTitle(rawTitle, fallbackSegment, fallbackSentence, depth) {
  const rawCandidate = cleanNodeLabel(rawTitle);
  const fallbackCandidate = cleanNodeLabel(
    fallbackSegment?.text ? sentenceTitle(fallbackSegment.text) : fallbackSentence?.text || ""
  );
  const preferred = rawCandidate && !isGenericNodeTitle(rawCandidate)
    ? rawCandidate
    : (fallbackCandidate || rawCandidate || (depth === 0 ? "资料总览" : "资料节点"));

  return truncate(preferred, depth === 0 ? 28 : 24);
}

function stableNodeSummary(rawSummary, fallbackSegment, fallbackSentence, fallbackTexts = [], depth = 0) {
  const rawCandidate = cleanParagraph(rawSummary || "");
  const fallbackSummary = cleanParagraph([
    ...fallbackTexts,
    fallbackSegment?.text || "",
    fallbackSentence?.text || ""
  ].filter(Boolean).join(" "));

  let summary = rawCandidate || sentenceSummary(fallbackSummary);
  if (!summary) {
    summary = depth === 0 ? "该资料的整体内容摘要。" : "该节点的核心内容概述。";
  }

  if (!/[。！？.!?]$/.test(summary)) {
    summary = `${summary}。`;
  }

  return truncate(summary, depth === 0 ? 240 : 140);
}

function preferredLabel(values) {
  const candidates = values
    .map((value) => String(value || "").trim())
    .filter(Boolean);

  if (candidates.length === 0) {
    return "";
  }

  return candidates.sort((lhs, rhs) => {
    const lhsIsChinese = /[\u4e00-\u9fff]/.test(lhs) ? 1 : 0;
    const rhsIsChinese = /[\u4e00-\u9fff]/.test(rhs) ? 1 : 0;
    if (lhsIsChinese !== rhsIsChinese) {
      return rhsIsChinese - lhsIsChinese;
    }

    const lhsPenalty = isGenericNodeTitle(lhs) ? 1 : 0;
    const rhsPenalty = isGenericNodeTitle(rhs) ? 1 : 0;
    if (lhsPenalty !== rhsPenalty) {
      return lhsPenalty - rhsPenalty;
    }

    if (lhs.length !== rhs.length) {
      return Math.abs(lhs.length - 10) - Math.abs(rhs.length - 10);
    }

    return lhs.localeCompare(rhs, "zh-Hans-CN");
  })[0];
}

function mergeSemanticTerms(values, limit = MAX_CANDIDATE_KNOWLEDGE_POINTS) {
  const groups = [];

  for (const rawValue of values) {
    const cleaned = cleanNodeLabel(rawValue);
    if (!cleaned || cleaned.length <= 1 || isGenericNodeTitle(cleaned)) {
      continue;
    }

    const key = normalizedTermKey(cleaned);
    if (!key) {
      continue;
    }

    const existing = groups.find((group) => {
      if (group.key === key) {
        return true;
      }

      if (group.key.includes(key) || key.includes(group.key)) {
        return true;
      }

      return tokenJaccard(group.label, cleaned) >= 0.74;
    });

    if (existing) {
      existing.values.push(cleaned);
      existing.label = preferredLabel(existing.values);
      if (cleaned.length > existing.longest.length) {
        existing.longest = cleaned;
      }
      continue;
    }

    groups.push({
      key,
      label: cleaned,
      longest: cleaned,
      values: [cleaned]
    });
  }

  return groups
    .map((group) => group.label)
    .filter(Boolean)
    .slice(0, limit);
}

function makeSourceId(requestedId) {
  return requestedId || `src_${crypto.randomUUID()}`;
}

function englishProfile(text) {
  const englishLetters = (text.match(/[A-Za-z]/g) || []).length;
  const chineseCharacters = (text.match(/[\u4e00-\u9fff]/g) || []).length;
  const words = (text.match(/[A-Za-z]+(?:'[A-Za-z]+)?/g) || []).map((word) => word.toLowerCase());
  const contentWords = words.filter((word) => word.length >= 3 && !ENGLISH_STOPWORDS.has(word));
  const ratioBase = englishLetters + chineseCharacters;
  const englishRatio = ratioBase === 0 ? 0 : englishLetters / ratioBase;

  return {
    englishLetters,
    chineseCharacters,
    englishRatio,
    wordCount: words.length,
    contentWordCount: contentWords.length
  };
}

function isEnglishMaterial(text) {
  const profile = englishProfile(text);

  if (profile.wordCount < 8) {
    return false;
  }

  return profile.englishRatio >= 0.72 || (
    profile.englishRatio >= 0.55 &&
    profile.contentWordCount >= 8
  ) || (
    profile.englishRatio >= 0.26 &&
    profile.contentWordCount >= 18 &&
    profile.englishLetters >= 120
  ) || (
    profile.contentWordCount >= 30 &&
    profile.englishLetters >= 220
  );
}

function reverseString(value) {
  return String(value || "").split("").reverse().join("");
}

function looksLikeInstructionOrQuestionParagraph(text) {
  const normalized = cleanParagraph(text);
  const lower = normalized.toLowerCase();

  if (/第[一二三四五六七八九十\d]+部分|说明|题干|答案|解析|配对|标题|选择|判断|先做|对照答案|把下列|请根据|阅读下面|题目/.test(normalized)) {
    return true;
  }

  return /\bquestions?\b|\bheadings?\b|\bchoose\b|\bmatch(?:ing)?\b|\btrue\b|\bfalse\b|\bnot given\b|\banswer key\b/.test(lower);
}

function looksLikeBilingualGlossaryParagraph(text) {
  const normalized = cleanParagraph(text);
  if (!normalized) return false;
  const profile = englishProfile(normalized);
  if (profile.chineseCharacters < 4 || profile.wordCount < 2) return false;
  return /(是|意为|意思是|译为|译作|mean(?:s|ing)?)/i.test(normalized)
    && /[“”"']/u.test(normalized);
}

function looksLikeReversedEnglishGarbage(text) {
  const tokens = (cleanParagraph(text).match(/[A-Za-z]+(?:'[A-Za-z]+)?/g) || [])
    .map((token) => token.toLowerCase())
    .filter((token) => token.length >= 4);
  if (tokens.length < 4) return false;

  const reversedHits = tokens.reduce((count, token) => {
    const reversed = reverseString(token);
    return COMMON_ENGLISH_LEXICON.has(reversed) ? count + 1 : count;
  }, 0);

  return reversedHits >= Math.max(3, Math.ceil(tokens.length * 0.35));
}

function looksLikeStrongPassageHeading(text) {
  const normalized = cleanParagraph(text);
  if (!normalized) return false;
  const profile = englishProfile(normalized);
  return profile.englishRatio >= 0.72
    && profile.wordCount >= 2
    && profile.wordCount <= 12
    && normalized.length <= 96
    && !/[。！？]/.test(normalized);
}

function isPassageBodySegment(text) {
  const normalized = cleanParagraph(text);
  if (!normalized) return false;
  if (looksLikeInstructionOrQuestionParagraph(normalized)) return false;
  if (looksLikeBilingualGlossaryParagraph(normalized)) return false;
  if (looksLikeReversedEnglishGarbage(normalized)) return false;

  const profile = englishProfile(normalized);
  if (profile.chineseCharacters > profile.englishLetters * 1.15 && !looksLikeStrongPassageHeading(normalized)) {
    return false;
  }

  return isEnglishMaterial(normalized) || looksLikeStrongPassageHeading(normalized);
}

function filterPassageSegments(rawSegments) {
  const filtered = rawSegments.filter((segment) => isPassageBodySegment(segment.text));
  if (filtered.length === 0) {
    return rawSegments;
  }

  return filtered.map((segment, index) => ({
    ...segment,
    key: `seg_${String(index + 1).padStart(3, "0")}`,
    index
  }));
}

function detectedSourceLanguage(text) {
  const profile = englishProfile(text);

  if (profile.wordCount < 8) {
    return profile.chineseCharacters > 0 ? "zh" : "unknown";
  }

  if (profile.englishRatio >= 0.72) {
    return "en";
  }

  if (isEnglishMaterial(text)) {
    return "mixed";
  }

  return profile.chineseCharacters > profile.englishLetters ? "zh" : "unknown";
}

function splitParagraphs(text) {
  return normalizeWhitespace(text)
    .split(/\n{2,}/)
    .map(cleanParagraph)
    .filter(Boolean);
}

function buildRawSegments({ cleanedText, anchors }) {
  if (Array.isArray(anchors) && anchors.length > 0) {
    let index = 0;
    const results = [];

    for (const anchor of anchors) {
      const paragraphs = splitParagraphs(anchor.text);
      const baseLabel = anchor.label || (anchor.page ? `第${anchor.page}页` : anchor.anchor_id);
      let localParagraphIndex = 0;

      if (paragraphs.length === 0) {
        continue;
      }

      for (const paragraph of paragraphs) {
        localParagraphIndex += 1;
        results.push({
          key: `seg_${String(index + 1).padStart(3, "0")}`,
          index,
          text: paragraph,
          anchorLabel: paragraphs.length > 1 ? `${baseLabel} 第${localParagraphIndex}段` : baseLabel,
          page: anchor.page ?? null
        });
        index += 1;
      }
    }

    if (results.length > 0) {
      return results;
    }
  }

  return splitParagraphs(cleanedText).map((paragraph, index) => ({
    key: `seg_${String(index + 1).padStart(3, "0")}`,
    index,
    text: paragraph,
    anchorLabel: `第${index + 1}段`,
    page: null
  }));
}

function splitSentences(text) {
  if (typeof Intl !== "undefined" && typeof Intl.Segmenter === "function") {
    const segmenter = new Intl.Segmenter("en", { granularity: "sentence" });
    const sentences = [];

    for (const item of segmenter.segment(text)) {
      const sentence = cleanParagraph(item.segment);
      if (sentence) {
        sentences.push(sentence);
      }
    }

    if (sentences.length > 0) {
      return sentences;
    }
  }

  return text
    .split(/(?<=[.!?])\s+(?=[A-Z0-9“"'(])/)
    .map(cleanParagraph)
    .filter(Boolean);
}

function sentenceTitle(text) {
  const cleaned = cleanParagraph(text);
  const firstSentence = splitSentences(cleaned)[0] || cleaned;
  const firstLine = cleaned.split("\n")[0]?.trim() || "";

  if (firstLine && firstLine.length <= 72 && /^[A-Za-z0-9 ,:;'"()/-]+$/.test(firstLine)) {
    return truncate(firstLine, 72);
  }

  return truncate(firstSentence, 72);
}

function sentenceSummary(text) {
  const sentences = splitSentences(text).slice(0, 2);
  return truncate(sentences.join(" "), 220);
}

function buildSegmentsAndSentences(rawSegments, sourceId) {
  const segments = [];
  const sentences = [];
  let sentenceIndex = 0;

  for (const rawSegment of rawSegments) {
    const sentenceTexts = splitSentences(rawSegment.text);
    const sentenceIds = [];

    for (const [localIndex, sentenceText] of sentenceTexts.entries()) {
      const sentenceId = `sen_${String(sentenceIndex + 1).padStart(3, "0")}`;
      sentenceIds.push(sentenceId);

      sentences.push({
        id: sentenceId,
        source_id: sourceId,
        segment_id: rawSegment.key,
        index: sentenceIndex,
        local_index: localIndex,
        text: sentenceText,
        anchor_label: `${rawSegment.anchorLabel} 第${localIndex + 1}句`,
        page: rawSegment.page
      });
      sentenceIndex += 1;
    }

    segments.push({
      id: rawSegment.key,
      source_id: sourceId,
      index: rawSegment.index,
      text: rawSegment.text,
      anchor_label: rawSegment.anchorLabel,
      page: rawSegment.page,
      sentence_ids: sentenceIds
    });
  }

  return { segments, sentences };
}

function buildOutlineNode({
  id,
  sourceId,
  parentId,
  depth,
  order,
  title,
  summary,
  segment,
  sentenceId,
  sourceSegmentIDs = [],
  sourceSentenceIDs = [],
  children = []
}) {
  const normalizedSegmentIDs = uniqueStrings([
    ...sourceSegmentIDs,
    segment?.id || null
  ]);
  const normalizedSentenceIDs = uniqueStrings([
    ...sourceSentenceIDs,
    sentenceId || segment?.sentence_ids?.[0] || null
  ]);

  return {
    id,
    source_id: sourceId,
    parent_id: parentId,
    depth,
    order,
    title,
    summary,
    anchor: {
      segment_id: segment?.id || normalizedSegmentIDs[0] || null,
      sentence_id: sentenceId || normalizedSentenceIDs[0] || null,
      page: segment?.page ?? null,
      label: segment?.anchor_label || "资料锚点"
    },
    source_segment_ids: normalizedSegmentIDs,
    source_sentence_ids: normalizedSentenceIDs,
    children
  };
}

function makeRootSummary(title, segments) {
  const candidate = segments.slice(0, 2).map((segment) => sentenceSummary(segment.text)).join(" ");

  if (candidate) {
    return truncate(candidate, 240);
  }

  if (title) {
    return `${title} 的整体内容摘要。`;
  }

  return "该资料的整体内容摘要。";
}

function groupSegmentsForOutline(segments) {
  if (segments.length <= 2) {
    return [segments];
  }

  const groupCount = Math.min(6, Math.max(2, Math.ceil(segments.length / 2)));
  const groupSize = Math.max(1, Math.ceil(segments.length / groupCount));
  const groups = [];

  for (let index = 0; index < segments.length; index += groupSize) {
    groups.push(segments.slice(index, index + groupSize));
  }

  return groups;
}

function buildRuleBasedOutline(sourceId, title, segments) {
  if (segments.length === 0) {
    return [];
  }

  const rootSegment = segments[0];
  const rootId = "node_root";
  const groups = groupSegmentsForOutline(segments);

  const rootChildren = groups.map((group, groupIndex) => {
    const leadSegment = group[0];
    const childId = `node_${groupIndex + 1}`;
    const leafChildren = group.length > 1
      ? group.map((segment, segmentIndex) =>
        buildOutlineNode({
          id: `${childId}_${segmentIndex + 1}`,
          sourceId,
          parentId: childId,
          depth: 2,
          order: segmentIndex,
          title: sentenceTitle(segment.text),
          summary: sentenceSummary(segment.text),
          segment,
          sourceSegmentIDs: [segment.id],
          sourceSentenceIDs: segment.sentence_ids
        }))
      : [];

    return buildOutlineNode({
      id: childId,
      sourceId,
      parentId: rootId,
      depth: 1,
      order: groupIndex,
      title: sentenceTitle(leadSegment.text),
      summary: truncate(group.map((segment) => sentenceSummary(segment.text)).join(" "), 220),
      segment: leadSegment,
      sourceSegmentIDs: group.map((segment) => segment.id),
      sourceSentenceIDs: group.flatMap((segment) => segment.sentence_ids),
      children: leafChildren
    });
  });

  return [
    buildOutlineNode({
      id: rootId,
      sourceId,
      parentId: null,
      depth: 0,
      order: 0,
      title: title || "资料总览",
      summary: makeRootSummary(title, segments),
      segment: rootSegment,
      sourceSegmentIDs: segments.map((segment) => segment.id),
      sourceSentenceIDs: segments.flatMap((segment) => segment.sentence_ids),
      children: rootChildren
    })
  ];
}

function extractTextContent(content) {
  if (typeof content === "string") {
    return content.trim();
  }

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

  if (start >= 0 && end > start) {
    return text.slice(start, end + 1);
  }

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
  if (directResult) {
    return directResult;
  }

  const candidate = extractJsonCandidate(text);
  const fallbackResult = tryParseJson(candidate);
  if (fallbackResult) {
    console.warn("[ai/parse-source] recovered JSON from wrapped response");
    return fallbackResult;
  }

  console.error("[ai/parse-source] model returned invalid JSON", text.slice(0, 400));

  throw new AppError("模型返回格式异常，无法解析为 JSON。", {
    statusCode: 502,
    code: "MODEL_INVALID_JSON"
  });
}

function buildModelSegments(segments, sentences) {
  const sentenceMapBySegment = new Map();

  for (const sentence of sentences) {
    const existing = sentenceMapBySegment.get(sentence.segment_id) || [];
    existing.push(sentence);
    sentenceMapBySegment.set(sentence.segment_id, existing);
  }

  return segments.slice(0, MAX_SEGMENTS_FOR_MODEL).map((segment) => ({
    segment_id: segment.id,
    anchor_label: segment.anchor_label,
    page: segment.page,
    segment_text: truncate(segment.text, MAX_SEGMENT_TEXT_FOR_MODEL),
    sentences: (sentenceMapBySegment.get(segment.id) || [])
      .slice(0, MAX_SENTENCES_PER_SEGMENT_FOR_MODEL)
      .map((sentence) => ({
        sentence_id: sentence.id,
        anchor_label: sentence.anchor_label,
        text: truncate(sentence.text, MAX_SENTENCE_TEXT_FOR_MODEL)
      }))
  }));
}

function buildOutlinePrompt({ title, segments, sentences }) {
  const material = buildModelSegments(segments, sentences);
  const safeTitle = title?.trim() || "未命名资料";

  return [
    "你是英语资料结构化理解助手。",
    "你必须只输出一个合法 JSON 对象。",
    "不要输出 Markdown。",
    "不要输出 ```json 代码块。",
    "不要输出任何额外解释。",
    "请根据给定的英语资料切分结果，生成中文资料大纲树。",
    "资料中可能夹杂少量中文题干、注释、页眉页脚或批注；请聚焦真正的英文正文结构，不要被这些噪音带偏。",
    "你只能引用输入里已经存在的 segment_id 和 sentence_id，不能杜撰来源锚点。",
    "输出格式固定为：",
    "{\"outline\":[{\"title\":\"...\",\"summary\":\"...\",\"anchor\":{\"segment_id\":\"seg_001\",\"sentence_id\":\"sen_001\",\"page\":1,\"label\":\"第1页 第1段\"},\"source_segment_ids\":[\"seg_001\"],\"source_sentence_ids\":[\"sen_001\"],\"children\":[...]}],\"section_titles\":[\"...\"],\"topic_tags\":[\"...\"],\"candidate_knowledge_points\":[\"...\"]}",
    "要求：",
    "- 顶层只返回一个 root 节点，放在 outline 数组中。",
    "- title 和 summary 都必须用中文。",
    "- root 的 title 要概括整份资料。",
    "- 一级节点建议 3 到 8 个；只有确有必要时才增加二级节点。",
    "- 最大层级只允许 root -> 一级节点 -> 二级节点，不能继续向下嵌套。",
    "- 不要制造只有一个子节点的空壳节点；如果一个父节点只有一个孩子且语义重复，请直接合并。",
    "- 节点标题要短、稳定、可复用，避免“正文第一部分”“段落分析”“资料节点”这类空泛标题。",
    "- 每个节点 summary 控制在 1 到 2 句中文。",
    "- source_segment_ids 和 source_sentence_ids 必须覆盖该节点对应的原文来源。",
    "- anchor 必须指向该节点最代表性的段落和句子。",
    "- children 里节点格式与父节点相同。",
    "- section_titles 返回一级节点标题列表。",
    "- topic_tags 返回 4 到 8 个更宏观的主题标签。",
    "- candidate_knowledge_points 返回 5 到 12 个适合后续卡片生成的候选知识点，尽量做概念归并，不要碎片化。",
    "",
    `资料标题: ${safeTitle}`,
    "资料切分结果如下：",
    JSON.stringify(material)
  ].join("\n");
}

function buildNodeID(path) {
  if (path.length === 0) {
    return "node_root";
  }

  return `node_${path.join("_")}`;
}

function pickRepresentativeSegment(segmentMap, sentenceMap, sourceSegmentIDs, sourceSentenceIDs, rawAnchor) {
  const anchorSentence = rawAnchor?.sentence_id && sentenceMap.get(rawAnchor.sentence_id);
  if (anchorSentence) {
    return segmentMap.get(anchorSentence.segment_id) || null;
  }

  const anchorSegment = rawAnchor?.segment_id && segmentMap.get(rawAnchor.segment_id);
  if (anchorSegment) {
    return anchorSegment;
  }

  for (const sentenceID of sourceSentenceIDs) {
    const sentence = sentenceMap.get(sentenceID);
    if (sentence) {
      return segmentMap.get(sentence.segment_id) || null;
    }
  }

  for (const segmentID of sourceSegmentIDs) {
    const segment = segmentMap.get(segmentID);
    if (segment) {
      return segment;
    }
  }

  return null;
}

function scoreSentenceForNode(sentence, rawAnchor, nodeText) {
  let score = 0;

  if (!sentence) {
    return score;
  }

  if (rawAnchor?.sentence_id && rawAnchor.sentence_id === sentence.id) {
    score += 1.2;
  }

  if (rawAnchor?.page && sentence.page === rawAnchor.page) {
    score += 0.18;
  }

  if (nodeText) {
    if (sentence.text.includes(nodeText) || nodeText.includes(sentence.text)) {
      score += 0.88;
    }

    score += tokenJaccard(sentence.text, nodeText) * 0.82;
  }

  return score;
}

function pickRepresentativeSentence(
  sentenceMap,
  rawAnchor,
  sourceSentenceIDs,
  sourceSegmentIDs,
  segmentMap,
  nodeText = ""
) {
  const anchorSentence = rawAnchor?.sentence_id && sentenceMap.get(rawAnchor.sentence_id);
  if (anchorSentence) {
    return anchorSentence;
  }

  const candidates = sourceSentenceIDs
    .map((sentenceID) => sentenceMap.get(sentenceID))
    .filter(Boolean);

  if (candidates.length > 0) {
    return candidates
      .sort((lhs, rhs) => {
        const lhsScore = scoreSentenceForNode(lhs, rawAnchor, nodeText);
        const rhsScore = scoreSentenceForNode(rhs, rawAnchor, nodeText);
        if (lhsScore !== rhsScore) {
          return rhsScore - lhsScore;
        }
        return lhs.index - rhs.index;
      })[0];
  }

  for (const sentenceID of sourceSentenceIDs) {
    const sentence = sentenceMap.get(sentenceID);
    if (sentence) {
      return sentence;
    }
  }

  const anchorSegmentID = rawAnchor?.segment_id;
  const sourceSegmentID = sourceSegmentIDs[0] || anchorSegmentID;
  const segment = sourceSegmentID ? segmentMap.get(sourceSegmentID) : null;

  if (segment?.sentence_ids?.length) {
    return sentenceMap.get(segment.sentence_ids[0]) || null;
  }

  return null;
}

function shouldCollapseSingleChildNode(node, child) {
  if (!child || node.depth === 0) {
    return false;
  }

  if (isGenericNodeTitle(node.title)) {
    return true;
  }

  if (normalizedTermKey(node.title) === normalizedTermKey(child.title)) {
    return true;
  }

  const parentSegments = new Set(node.source_segment_ids || []);
  const childSegments = new Set(child.source_segment_ids || []);
  if (parentSegments.size > 0 && childSegments.size > 0) {
    const sameCoverage = parentSegments.size === childSegments.size &&
      [...parentSegments].every((segmentID) => childSegments.has(segmentID));
    if (sameCoverage) {
      return true;
    }
  }

  return false;
}

function collapseSingleChildNode(node) {
  if (!Array.isArray(node.children) || node.children.length !== 1) {
    return node;
  }

  const child = node.children[0];
  if (!shouldCollapseSingleChildNode(node, child)) {
    return node;
  }

  return {
    ...node,
    title: isGenericNodeTitle(node.title) ? child.title : node.title,
    summary: stableNodeSummary(
      [node.summary, child.summary].filter(Boolean).join(" "),
      null,
      null,
      [node.summary, child.summary],
      node.depth
    ),
    anchor: child.anchor,
    source_segment_ids: uniqueStrings([
      ...(node.source_segment_ids || []),
      ...(child.source_segment_ids || [])
    ]),
    source_sentence_ids: uniqueStrings([
      ...(node.source_sentence_ids || []),
      ...(child.source_sentence_ids || [])
    ]),
    children: child.children.map((grandChild, index) => ({
      ...grandChild,
      parent_id: node.id,
      depth: node.depth + 1,
      order: index
    }))
  };
}

function normalizeModelOutline(raw, sourceId, title, segments, sentences) {
  const rootCandidates = Array.isArray(raw?.outline)
    ? raw.outline
    : Array.isArray(raw)
      ? raw
      : raw?.root
        ? [raw.root]
        : [];

  if (rootCandidates.length === 0) {
    throw new AppError("模型返回格式异常，缺少 outline。", {
      statusCode: 502,
      code: "MODEL_INVALID_SCHEMA"
    });
  }

  const segmentMap = new Map(segments.map((segment) => [segment.id, segment]));
  const sentenceMap = new Map(sentences.map((sentence) => [sentence.id, sentence]));
  const firstSegment = segments[0] || null;
  const firstSentence = firstSegment?.sentence_ids?.[0]
    ? sentenceMap.get(firstSegment.sentence_ids[0]) || null
    : null;

  function normalizeNode(rawNode, { parentId = null, depth = 0, order = 0, path = [] }) {
    const childrenInput = Array.isArray(rawNode?.children) ? rawNode.children : [];
    const rawNodeText = [
      typeof rawNode?.title === "string" ? rawNode.title : "",
      typeof rawNode?.summary === "string" ? rawNode.summary : ""
    ].filter(Boolean).join(" ");

    const normalizedChildren = (depth >= MAX_OUTLINE_DEPTH
      ? []
      : childrenInput.map((child, childIndex) =>
        normalizeNode(child, {
        parentId: buildNodeID(path),
        depth: depth + 1,
        order: childIndex,
        path: [...path, childIndex + 1]
      })))
      .filter(Boolean);

    const sourceSegmentIDs = uniqueStrings([
      ...(Array.isArray(rawNode?.source_segment_ids) ? rawNode.source_segment_ids : []),
      ...normalizedChildren.flatMap((child) => child.source_segment_ids)
    ]).filter((segmentID) => segmentMap.has(segmentID));

    const sourceSentenceIDs = uniqueStrings([
      ...(Array.isArray(rawNode?.source_sentence_ids) ? rawNode.source_sentence_ids : []),
      ...normalizedChildren.flatMap((child) => child.source_sentence_ids)
    ]).filter((sentenceID) => sentenceMap.has(sentenceID));

    const rawAnchor = typeof rawNode?.anchor === "object" && rawNode.anchor !== null
      ? rawNode.anchor
      : {};
    const representativeSentence = pickRepresentativeSentence(
      sentenceMap,
      rawAnchor,
      sourceSentenceIDs,
      sourceSegmentIDs,
      segmentMap,
      rawNodeText
    ) || firstSentence;
    const representativeSegment = pickRepresentativeSegment(
      segmentMap,
      sentenceMap,
      sourceSegmentIDs,
      sourceSentenceIDs,
      rawAnchor
    ) || segmentMap.get(representativeSentence?.segment_id) || firstSegment;

    const finalSourceSentenceIDs = uniqueStrings([
      ...sourceSentenceIDs,
      representativeSentence?.id || null
    ]);
    const finalSourceSegmentIDs = uniqueStrings([
      ...sourceSegmentIDs,
      representativeSegment?.id || null
    ]);

    const normalizedNode = {
      id: buildNodeID(path),
      source_id: sourceId,
      parent_id: parentId,
      depth,
      order,
      title: stableNodeTitle(
        depth === 0 ? (rawNode?.title || title || "资料总览") : rawNode?.title,
        representativeSegment,
        representativeSentence,
        depth
      ),
      summary: stableNodeSummary(
        depth === 0 ? (rawNode?.summary || makeRootSummary(title, segments)) : rawNode?.summary,
        representativeSegment,
        representativeSentence,
        normalizedChildren.map((child) => child.summary),
        depth
      ),
      anchor: {
        segment_id: representativeSegment?.id || null,
        sentence_id: representativeSentence?.id || null,
        page: Number.isInteger(rawAnchor?.page)
          ? rawAnchor.page
          : representativeSentence?.page ?? representativeSegment?.page ?? null,
        label: typeof rawAnchor?.label === "string" && rawAnchor.label.trim()
          ? rawAnchor.label.trim()
          : representativeSegment?.anchor_label || "资料锚点"
      },
      source_segment_ids: finalSourceSegmentIDs,
      source_sentence_ids: finalSourceSentenceIDs,
      children: normalizedChildren
    };

    return collapseSingleChildNode(normalizedNode);
  }

  return [normalizeNode(rootCandidates[0], { parentId: null, depth: 0, order: 0, path: [] })];
}

function deriveSectionTitlesFromOutline(outline) {
  const root = outline[0];
  const candidates = Array.isArray(root?.children) && root.children.length > 0
    ? root.children.map((node) => node.title)
    : flattenOutline(outline).filter((node) => node.depth > 0).map((node) => node.title);

  return mergeSemanticTerms(candidates, MAX_SECTION_TITLES);
}

function deriveTopicTags({ title, outline, segments }) {
  const values = [
    title,
    ...flattenOutline(outline).filter((node) => node.depth <= 1).map((node) => node.title),
    ...segments.slice(0, 4).map((segment) => sentenceTitle(segment.text))
  ];

  return mergeSemanticTerms(values, MAX_TOPIC_TAGS);
}

function deriveCandidateKnowledgePoints({ title, outline, segments }) {
  const flattened = flattenOutline(outline).filter((node) => node.depth > 0);
  const nodeTitles = flattened.map((node) => node.title);
  const nodeHints = flattened.flatMap((node) => {
    const sentenceTokens = (node.summary || "")
      .split(/[，。；、,:;()（）\s]+/)
      .map((item) => cleanNodeLabel(item))
      .filter((item) => item.length >= 2 && item.length <= 16);
    return sentenceTokens.slice(0, 2);
  });
  const segmentHints = segments
    .slice(0, 6)
    .map((segment) => sentenceTitle(segment.text));

  return mergeSemanticTerms(
    [title, ...nodeTitles, ...nodeHints, ...segmentHints],
    MAX_CANDIDATE_KNOWLEDGE_POINTS
  );
}

function buildFallbackMetadata({ title, outline, segments }) {
  return {
    section_titles: deriveSectionTitlesFromOutline(outline),
    topic_tags: deriveTopicTags({ title, outline, segments }),
    candidate_knowledge_points: deriveCandidateKnowledgePoints({ title, outline, segments })
  };
}

function mergeMetadataValues(primary, fallback, limit) {
  return mergeSemanticTerms(
    [
      ...(Array.isArray(primary) ? primary : []),
      ...(Array.isArray(fallback) ? fallback : [])
    ],
    limit
  );
}

function normalizeModelParseResult(raw, sourceId, title, segments, sentences) {
  const outline = normalizeModelOutline(raw, sourceId, title, segments, sentences);
  const fallbackMetadata = buildFallbackMetadata({ title, outline, segments });

  return {
    outline,
    section_titles: mergeMetadataValues(raw?.section_titles, fallbackMetadata.section_titles, MAX_SECTION_TITLES),
    topic_tags: mergeMetadataValues(raw?.topic_tags, fallbackMetadata.topic_tags, MAX_TOPIC_TAGS),
    candidate_knowledge_points: mergeMetadataValues(
      raw?.candidate_knowledge_points,
      fallbackMetadata.candidate_knowledge_points,
      MAX_CANDIDATE_KNOWLEDGE_POINTS
    )
  };
}

async function buildModelOutline({ sourceId, title, segments, sentences }) {
  const client = getDashScopeClient();
  const { modelName } = getDashScopeConfig();

  if (!client) {
    throw new AppError("DASHSCOPE_API_KEY 或 DASHSCOPE_BASE_URL 未配置。", {
      statusCode: 500,
      code: "MODEL_CONFIG_MISSING"
    });
  }

  console.log("[ai/parse-source] calling model", {
    modelName,
    segmentCount: segments.length,
    sentenceCount: sentences.length
  });

  let completion;

  try {
    completion = await client.chat.completions.create({
      model: modelName,
      temperature: 0.2,
      response_format: {
        type: "json_object"
      },
      messages: [
        {
          role: "system",
          content: "你是严格输出 JSON 的英语资料结构化理解助手。无论任何情况都只返回 JSON 对象。"
        },
        {
          role: "user",
          content: buildOutlinePrompt({ title, segments, sentences })
        }
      ]
    });
  } catch (error) {
    const status = typeof error?.status === "number" ? error.status : undefined;
    const upstreamMessage = typeof error?.message === "string" ? error.message : "";

    console.error("[ai/parse-source] model request failed", {
      status,
      upstreamMessage
    });

    throw new AppError("调用大模型生成资料大纲失败。", {
      statusCode: 502,
      code: "MODEL_REQUEST_FAILED"
    });
  }

  const parsed = parseModelJson(completion.choices?.[0]?.message?.content);
  return normalizeModelParseResult(parsed, sourceId, title, segments, sentences);
}

function flattenOutline(nodes) {
  const result = [];

  for (const node of nodes) {
    result.push(node);
    if (Array.isArray(node.children) && node.children.length > 0) {
      result.push(...flattenOutline(node.children));
    }
  }

  return result;
}

export async function parseSource({
  source_id = "",
  title = "",
  source_type = "",
  raw_text,
  page_count = null,
  anchors = []
}) {
  const cleanedText = normalizeWhitespace(raw_text);
  const detectedLanguage = detectedSourceLanguage(cleanedText);

  if (!isEnglishMaterial(cleanedText)) {
    throw new AppError("当前资料未识别为英语资料，暂不进入英语结构化理解流程。", {
      statusCode: 422,
      code: "SOURCE_NOT_ENGLISH"
    });
  }

  const sourceId = makeSourceId(source_id);
  const rawSegments = filterPassageSegments(buildRawSegments({ cleanedText, anchors }));

  if (rawSegments.length === 0) {
    throw new AppError("资料清洗后没有可用段落。", {
      statusCode: 422,
      code: "SOURCE_EMPTY_AFTER_CLEAN"
    });
  }

  const { segments, sentences } = buildSegmentsAndSentences(rawSegments, sourceId);
  const fallbackOutline = buildRuleBasedOutline(sourceId, title, segments);
  const fallbackMetadata = buildFallbackMetadata({
    title,
    outline: fallbackOutline,
    segments
  });

  let outline;
  let sectionTitles = fallbackMetadata.section_titles;
  let topicTags = fallbackMetadata.topic_tags;
  let candidateKnowledgePoints = fallbackMetadata.candidate_knowledge_points;
  let outlineEngine = "model";

  try {
    const modelResult = await buildModelOutline({
      sourceId,
      title,
      segments,
      sentences
    });
    outline = modelResult.outline;
    sectionTitles = modelResult.section_titles;
    topicTags = modelResult.topic_tags;
    candidateKnowledgePoints = modelResult.candidate_knowledge_points;
  } catch (error) {
    outlineEngine = "fallback";
    console.warn("[ai/parse-source] outline model failed, falling back to rule tree", {
      message: error?.message || "unknown"
    });
    outline = fallbackOutline;
  }

  const flattenedOutline = flattenOutline(outline);
  const fallbackPageCount = anchors
    .map((anchor) => anchor.page)
    .filter((page) => page !== null).length;

  console.log("[ai/parse-source] parsed", {
    sourceId,
    segmentCount: segments.length,
    sentenceCount: sentences.length,
    outlineNodeCount: flattenedOutline.length,
    outlineEngine
  });

  return {
    source: {
      id: sourceId,
      title: title || "未命名资料",
      source_type: source_type || "text",
      language: detectedLanguage,
      is_english: true,
      cleaned_text: cleanedText,
      page_count: page_count ?? fallbackPageCount,
      segment_count: segments.length,
      sentence_count: sentences.length,
      outline_node_count: flattenedOutline.length
    },
    section_titles: sectionTitles,
    topic_tags: topicTags,
    candidate_knowledge_points: candidateKnowledgePoints,
    segments,
    sentences,
    outline
  };
}
