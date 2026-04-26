import { getDashScopeConfig } from "../config/env.js";
import { AppError } from "../lib/appError.js";
import { getDashScopeClient } from "../lib/dashscope.js";
import { aiResponseCache } from "./AIResponseCache.js";
import { requestGeminiCompletion } from "./GeminiRetryClient.js";

// ─────────────────────────────────────────────
// 教授级全文教学分析服务
// 一次 LLM 调用：文章总览 + 段落教学卡 + 关键句引用
// ─────────────────────────────────────────────

const MAX_PARAGRAPHS = 4;
const MAX_KEY_SENTENCES = 6;
const MAX_PARAGRAPH_CHARS = 700;
const COMMON_ENGLISH_LEXICON = new Set([
  "allow", "balance", "contact", "corporation", "cultural", "debate", "evidence", "growth",
  "heading", "logical", "museum", "peaceful", "prosperity", "question", "reading", "sustainable",
  "tourism", "visitor", "quantity", "archaeology", "community", "economic", "environmental"
]);

function buildAnalyzePassagePrompt({ title, paragraphs, keySentences }) {
  const safeParagraphs = paragraphs.slice(0, MAX_PARAGRAPHS);
  const safeSentences = keySentences.slice(0, MAX_KEY_SENTENCES);

  const paragraphBlock = safeParagraphs
    .map((p) => `[P${typeof p.index === "number" ? p.index : 0}] ${p.text.slice(0, MAX_PARAGRAPH_CHARS)}`)
    .join("\n\n");

  const sentenceBlock = safeSentences
    .map((s) => `[${s.ref}] (来自段落 P${typeof s.paragraphIndex === "number" ? s.paragraphIndex : 0}) ${s.text}`)
    .join("\n");

  return [
    "你是一位顶级英语教授，正在为一个重要学生逐段逐句拆解一篇英语阅读材料。",
    "你不是摘要器或翻译器。",
    "你的目标是：先产出可靠的全文教学地图，而不是逐句深讲。",
    "你必须只输出一个合法 JSON 对象。不要输出 Markdown、注释或额外文字。",
    "",
    "═══════════════════════",
    "资料标题：" + (title || "未提供"),
    "═══════════════════════",
    "",
    "正文段落：",
    paragraphBlock,
    "",
    "关键句子（仅用于标记后续深讲入口）：",
    sentenceBlock,
    "",
    "═══════════════════════",
    "输出规则（严格执行）：",
    "═══════════════════════",
    "",
    "JSON 必须包含三个顶层字段：passage_overview、paragraph_cards、key_sentence_refs。",
    "",
    "一、passage_overview 对象：",
    "  article_theme：像课堂讲义里的总标题说明，用中文一段话点明文章真正讨论的问题，不要写成'文章主要讲了什么'。",
    "  author_core_question：用中文一句话说清作者真正追问的问题，要像老师在黑板上写出的核心问题。",
    "  progression_path：用中文描述从第1段到最后一段，作者怎样一步步推进判断。推荐使用“先……→再……→最后……”这种讲义式表达。",
    "  syntax_highlights：字符串数组，最值得关注的 3-5 个句法结构。每项都要写出“结构｜为什么值得学｜最容易挂错哪里”。",
    "  likely_question_types：字符串数组，最容易出的 3-5 类题。每项必须像“主旨题：最后一段如何收束前文判断”这种具体表达。",
    "  logic_pitfalls：字符串数组，学生最容易错的 3-5 个逻辑点。要写清是范围、让步、因果、指代还是态度读偏，并指出会错在哪里。",
    "  paragraph_function_map：字符串数组，每项 '第X段｜角色｜一句话功能'。语气要像老师带着学生看结构图。",
    "  reading_traps：字符串数组，学生最容易误读的 3-5 个点。",
    "  vocabulary_highlights：字符串数组，最值得学习的 5-8 个词汇/搭配。",
    "",
    "二、paragraph_cards 数组（每段一项）：",
    "  paragraph_index：段落编号，必须对应输入里的 [Pindex] 原始编号，不要重排。",
    "  theme：中文，本段真正要立住的判断或说明点。不能是'本段主要讲了...'式的废话，要像讲义里的段落主旨，而且必须只根据本段内容生成，不能揉入别段信息。",
    "  argument_role：必须为以下之一：background / support / objection / transition / evidence / conclusion。",
    "  core_sentence_local_index：段内最关键的一句话的序号（从0开始）。",
    "  keywords：5个本段最重要的英语关键词或短语。",
    "  relation_to_previous：中文，本段和上一段之间的逻辑关系，不要说'承接上文'这类空话，要写清上一段做了什么、这一段怎么接或怎么转。",
    "  exam_value：中文，说清这段内容在阅读理解考试中最可能对应什么题型、命题人会抓哪层信息、学生最容易掉进什么陷阱。",
    "  teaching_focuses：字符串数组，2-3个具体教学动作。每条都必须体现“先读哪层 / 为什么重要 / 学生会怎么错”，像老师课堂提示，而且必须能在本段文本里找到支点。",
    "  student_blind_spot：中文一句话，学生最容易在本段读偏的点。要写成能直接提醒学生的讲义批注。",
    "",
    "三、key_sentence_refs 数组：",
    "  每项必须直接复用输入里的 [S_X_Y] 编号。",
    "  这里不要返回任何句子级 core_skeleton / chunk_layers / grammar_focus / faithful_translation / teaching_interpretation。",
    "",
    "═══════════════════════",
    "质量底线（违反任何一条都视为失败）：",
    "═══════════════════════",
    "1. 全文阶段只做粗粒度教学地图，不做逐句句法精析。",
    "2. teaching_focuses 不能是抽象建议（如'注意语法'），必须是具体的教学行动。",
    "3. passage_overview 和 paragraph_cards 的口吻必须像课堂讲义，不像摘要器或题解答案。",
    "4. 所有中文解释口吻：严谨但平易的英语教授。",
    "5. 如果信息不足，返回空字符串或空数组，不能删字段。"
  ].join("\n");
}

function normalizeArray(value) {
  return Array.isArray(value) ? value : [];
}

function normalizeString(value, fallback = "") {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function isChineseDominantText(text) {
  if (!text || typeof text !== "string") return false;
  const chineseMatches = text.match(/[\u4e00-\u9fff]/g) || [];
  const latinMatches = text.match(/[A-Za-z]/g) || [];
  if (chineseMatches.length === 0) return false;
  return chineseMatches.length >= Math.max(3, latinMatches.length * 0.55);
}

function extractChineseDominantClauses(text) {
  if (!text || typeof text !== "string") return [];
  return text
    .split(/[；;。！？!?]\s*/g)
    .map((clause) => clause.trim())
    .filter((clause) => clause.length >= 4 && isChineseDominantText(clause));
}

function purifyChineseExplanation(text) {
  const normalized = normalizeString(text);
  if (!normalized) return "";
  if (isChineseDominantText(normalized)) return normalized;

  const clauses = extractChineseDominantClauses(normalized);
  if (clauses.length > 0) {
    return clauses.join("；");
  }

  return "";
}

function purifyChineseDisplayText(text) {
  return purifyChineseExplanation(text)
    .replace(/\s+/g, " ")
    .trim();
}

function purifyChineseList(values, limit = 4) {
  return normalizeArray(values)
    .map((item) => purifyChineseDisplayText(String(item)))
    .filter(Boolean)
    .slice(0, limit);
}

function firstDefined(raw, keys) {
  for (const key of keys) {
    if (raw?.[key] !== undefined) {
      return raw[key];
    }
  }
  return undefined;
}

function englishTokens(text) {
  return normalizeString(text)
    .match(/[A-Za-z]+(?:'[A-Za-z]+)?/g)
    ?.map((token) => token.toLowerCase()) ?? [];
}

function reverseString(value) {
  return String(value || "").split("").reverse().join("");
}

function textEnglishProfile(text) {
  const normalized = normalizeString(text);
  const englishLetters = (normalized.match(/[A-Za-z]/g) || []).length;
  const chineseCharacters = (normalized.match(/[\u4e00-\u9fff]/g) || []).length;
  const tokens = englishTokens(normalized);
  const ratioBase = englishLetters + chineseCharacters;
  return {
    englishLetters,
    chineseCharacters,
    englishRatio: ratioBase === 0 ? 0 : englishLetters / ratioBase,
    tokens
  };
}

function looksLikeInstructionOrQuestionParagraph(text) {
  const normalized = normalizeString(text);
  if (!normalized) return false;
  const lower = normalized.toLowerCase();

  if (/第[一二三四五六七八九十\d]+部分|说明|题干|答案|解析|配对|标题|选择|判断|先做|对照答案|把下列|请根据|阅读下面|题目/.test(normalized)) {
    return true;
  }

  if (/\bquestions?\b|\bheadings?\b|\bchoose\b|\bmatch(?:ing)?\b|\btrue\b|\bfalse\b|\bnot given\b|\banswer key\b/.test(lower)) {
    return true;
  }

  return false;
}

function looksLikeBilingualGlossaryParagraph(text) {
  const normalized = normalizeString(text);
  if (!normalized) return false;
  const profile = textEnglishProfile(normalized);

  if (profile.chineseCharacters < 4 || profile.tokens.length < 2) {
    return false;
  }

  return /(是|意为|意思是|译为|译作|mean(?:s|ing)?)/i.test(normalized)
    && /[“”"']/u.test(normalized);
}

function looksLikeReversedEnglishGarbage(text) {
  const tokens = englishTokens(text).filter((token) => token.length >= 4);
  if (tokens.length < 4) return false;

  const reversedHits = tokens.reduce((count, token) => {
    const reversed = reverseString(token);
    return COMMON_ENGLISH_LEXICON.has(reversed) ? count + 1 : count;
  }, 0);

  return reversedHits >= Math.max(3, Math.ceil(tokens.length * 0.35));
}

function looksLikeStrongPassageHeading(text) {
  const normalized = normalizeString(text);
  if (!normalized) return false;
  const profile = textEnglishProfile(normalized);
  return profile.englishRatio >= 0.72
    && profile.tokens.length >= 2
    && profile.tokens.length <= 12
    && normalized.length <= 96
    && !/[。！？]/.test(normalized);
}

function isPassageBodyText(text) {
  const normalized = normalizeString(text);
  if (!normalized) return false;
  if (looksLikeInstructionOrQuestionParagraph(normalized)) return false;
  if (looksLikeBilingualGlossaryParagraph(normalized)) return false;
  if (looksLikeReversedEnglishGarbage(normalized)) return false;

  const profile = textEnglishProfile(normalized);
  if (profile.chineseCharacters > profile.englishLetters * 1.15 && !looksLikeStrongPassageHeading(normalized)) {
    return false;
  }

  return profile.tokens.length >= 8 || looksLikeStrongPassageHeading(normalized);
}

function classifyPassageTextKind(text) {
  const normalized = normalizeString(text);
  if (!normalized) return "unknown";
  if (looksLikeInstructionOrQuestionParagraph(normalized)) return "polluted";
  if (looksLikeBilingualGlossaryParagraph(normalized)) return "bilingual_annotation";
  if (looksLikeReversedEnglishGarbage(normalized)) return "polluted";
  if (looksLikeStrongPassageHeading(normalized)) return "passage_heading";

  const profile = textEnglishProfile(normalized);
  if (profile.chineseCharacters > Math.max(8, profile.englishLetters * 0.9)) {
    return "polluted";
  }
  return "passage_body";
}

function scorePassageTextHygiene(text) {
  const normalized = normalizeString(text);
  if (!normalized) {
    return { score: 0, kind: "unknown", flags: ["empty"] };
  }

  const profile = textEnglishProfile(normalized);
  const kind = classifyPassageTextKind(normalized);
  const flags = [];
  let score = 1;

  if (kind === "bilingual_annotation") {
    score -= 0.28;
    flags.push("bilingual_annotation");
  }
  if (kind === "polluted") {
    score -= 0.34;
    flags.push("polluted");
  }
  if (profile.chineseCharacters > 0 && profile.englishRatio < 0.52) {
    score -= 0.2;
    flags.push("mixed_contamination");
  }
  if (profile.tokens.length < 6 && kind !== "passage_heading") {
    score -= 0.18;
    flags.push("too_short");
  }

  return {
    score: Math.max(0, Math.min(1, score)),
    kind,
    flags
  };
}

function sanitizePassageInputs(paragraphs, keySentences) {
  const safeParagraphs = normalizeArray(paragraphs)
    .filter((item) => typeof item?.text === "string")
    .map((item, idx) => ({
      index: typeof item.index === "number" ? item.index : idx,
      text: normalizeString(item.text)
    }));

  const filteredParagraphs = safeParagraphs.filter((item) => {
    const hygiene = scorePassageTextHygiene(item.text);
    if (hygiene.kind !== "passage_body" && hygiene.kind !== "passage_heading") {
      return false;
    }
    return isPassageBodyText(item.text) && hygiene.score >= 0.54;
  });
  const retainedParagraphs = filteredParagraphs.length > 0 ? filteredParagraphs : safeParagraphs;
  const retainedIndexSet = new Set(retainedParagraphs.map((item) => item.index));

  const safeKeySentences = normalizeArray(keySentences)
    .filter((item) => typeof item?.text === "string" && typeof item?.ref === "string")
    .map((item) => ({
      ref: normalizeString(item.ref),
      text: normalizeString(item.text),
      paragraphIndex: typeof item.paragraphIndex === "number"
        ? item.paragraphIndex
        : (typeof item.paragraph_index === "number" ? item.paragraph_index : 0)
    }));

  const filteredKeySentences = safeKeySentences.filter((item) => {
    if (!retainedIndexSet.has(item.paragraphIndex)) return false;
    const hygiene = scorePassageTextHygiene(item.text);
    if (hygiene.kind !== "passage_body") return false;
    return isPassageBodyText(item.text) && !looksLikeStrongPassageHeading(item.text) && hygiene.score >= 0.52;
  });

  return {
    paragraphs: retainedParagraphs,
    keySentences: filteredKeySentences.length > 0 ? filteredKeySentences : safeKeySentences.filter((item) => retainedIndexSet.has(item.paragraphIndex))
  };
}

function normalizeEvidenceType(value, fallback = "supporting_evidence") {
  if (typeof value !== "string") {
    return fallback;
  }

  const normalized = value.trim().toLowerCase();
  const aliases = {
    background: "background_info",
    background_info: "background_info",
    transition: "transition_signal",
    transition_signal: "transition_signal",
    core: "core_claim",
    core_claim: "core_claim",
    claim: "core_claim",
    support: "supporting_evidence",
    supporting_evidence: "supporting_evidence",
    evidence: "supporting_evidence",
    objection: "counter_argument",
    counter_argument: "counter_argument",
    rebuttal: "counter_argument",
    conclusion: "conclusion_marker",
    conclusion_marker: "conclusion_marker"
  };

  return aliases[normalized] || fallback;
}

function buildSentenceFunctionFromEvidenceType(evidenceType) {
  const normalized = normalizeEvidenceType(evidenceType, "supporting_evidence");
  const mapping = {
    core_claim: "核心判断句：这句承担作者真正要成立的判断，做题时先盯主干，再看其余修饰怎么限制这个判断。",
    supporting_evidence: "支撑证据句：这句在替上一层判断补事实、补例子或补论据，不能只记细节而忘了它服务的观点。",
    background_info: "背景信息句：这句主要交代场景、前提或历史背景，不是作者最后要你选的结论。",
    counter_argument: "让步/反方句：这句常先承认一种看法，真正立场多半落在它之后，最容易把让步内容错当答案。",
    transition_signal: "推进信号句：这句的价值在于提示作者怎样换挡，适合判断段落关系、论证方向和结构推进。",
    conclusion_marker: "结论收束句：这句在回收前文信息，常是主旨题、标题题和作者态度题最该回看的位置。"
  };
  return mapping[normalized] || mapping.supporting_evidence;
}

function renderCoreSkeleton(coreSkeleton) {
  if (!coreSkeleton || typeof coreSkeleton !== "object") {
    return "";
  }

  const subject = sanitizeCoreSkeletonField(normalizeString(firstDefined(coreSkeleton, ["subject"])));
  const predicate = sanitizeCoreSkeletonField(normalizeString(firstDefined(coreSkeleton, ["predicate"])));
  const complement = sanitizeCoreSkeletonField(normalizeString(firstDefined(coreSkeleton, ["complement_or_object", "complementOrObject", "object"])));
  return [
    subject ? `主语：${subject}` : "",
    predicate ? `谓语：${predicate}` : "",
    complement ? `核心补足：${complement}` : ""
  ].filter(Boolean).join("｜");
}

function sanitizeCoreSkeletonField(value) {
  const normalized = normalizeString(value);
  if (!normalized) return "";
  return normalized
    .replace(/\[[A-Za-z_\s-]+:\s*([^\]]+)\]/g, "$1")
    .replace(/^(主语|谓语|核心补足|宾语|补语|表语|subject|predicate|object|complement)\s*[：:]\s*/gi, "")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeCoreSkeleton(raw, fallbackCore) {
  const subject = sanitizeCoreSkeletonField(firstDefined(raw, ["subject"]));
  const predicate = sanitizeCoreSkeletonField(firstDefined(raw, ["predicate"]));
  const complement = sanitizeCoreSkeletonField(firstDefined(raw, ["complement_or_object", "complementOrObject", "object"]));

  if (subject || predicate || complement) {
    return {
      subject,
      predicate,
      complement_or_object: complement
    };
  }

  const segments = normalizeString(fallbackCore)
    .split("｜")
    .map((item) => item.trim())
    .filter(Boolean);
  const fallback = { subject: "", predicate: "", complement_or_object: "" };
  for (const segment of segments) {
    if (segment.startsWith("主语：")) fallback.subject = segment.replace("主语：", "").trim();
    if (segment.startsWith("谓语：")) fallback.predicate = segment.replace("谓语：", "").trim();
    if (segment.startsWith("核心补足：")) fallback.complement_or_object = segment.replace("核心补足：", "").trim();
  }
  return fallback.subject || fallback.predicate || fallback.complement_or_object ? fallback : null;
}

function normalizeChunkLayers(raw, fallbackBreakdown) {
  const direct = Array.isArray(raw)
    ? raw
      .map((item) => ({
        text: normalizeString(item?.text),
        role: normalizeString(item?.role),
        attaches_to: normalizeString(firstDefined(item, ["attaches_to", "attachesTo"])),
        gloss: normalizeString(item?.gloss)
      }))
      .filter((item) => item.text || item.role || item.attaches_to || item.gloss)
    : [];

  if (direct.length > 0) {
    return direct;
  }

  return normalizeArray(fallbackBreakdown)
    .map((item) => String(item).trim())
    .filter(Boolean)
    .map((item) => {
      const [rawRole, rawText = ""] = item.split(/[:：]/, 2);
      const role = (rawRole || "").trim();
      const text = (rawText || item).trim();
      return {
        text,
        role: role || "语块",
        attaches_to: role === "核心信息" ? "主句主干" : "核心信息",
        gloss: role === "后置修饰" ? "注意它修饰谁。" : ""
      };
    });
}

function normalizeMixedGrammarChinese(text) {
  let normalized = normalizeString(text);
  if (!normalized) return "";

  const replacements = [
    [/temporal clause/gi, "时间状语从句"],
    [/time clause/gi, "时间状语从句"],
    [/reduced relative clause/gi, "压缩定语从句"],
    [/relative clause/gi, "定语从句"],
    [/object clause/gi, "宾语从句"],
    [/modal verb/gi, "情态动词"],
    [/postpositive modifier/gi, "后置修饰"],
    [/passive voice/gi, "被动结构"],
    [/concessive frame/gi, "让步框架"],
    [/framing phrase/gi, "前置框架"],
    [/conditional frame/gi, "条件框架"],
    [/participle phrase/gi, "分词短语"],
    [/infinitive phrase/gi, "不定式短语"],
    [/non-finite/gi, "非谓语结构"],
    [/adverbial clause/gi, "状语从句"],
    [/subject clause/gi, "主语从句"],
    [/predicative clause/gi, "表语从句"],
    [/appositive clause/gi, "同位语从句"]
  ];

  for (const [pattern, replacement] of replacements) {
    normalized = normalized.replace(pattern, replacement);
  }

  return normalized.replace(/([A-Za-z]+)\s*引导的/g, "由原句里的“$1 …”引出的");
}

function sanitizePedagogicalChinese(text) {
  return normalizeMixedGrammarChinese(text)
    .replace(/\[[A-Za-z_\s-]+:\s*[^\]]+\]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function containsPedagogicalEnglishLeakage(text) {
  const normalized = normalizeString(text);
  if (!normalized) return false;
  if (/\[[A-Za-z_\s-]+:\s*[^\]]+\]/.test(normalized)) return true;
  if (/[A-Za-z]{2,}\s*引导/.test(normalized)) return true;
  return /[A-Za-z]{8,}(?:\s+[A-Za-z]{2,})+/.test(normalized);
}

function grammarFocusTemplate(raw) {
  const normalized = normalizeMixedGrammarChinese(raw);
  const lower = normalized.toLowerCase();

  if (normalized.includes("时间状语从句") || lower.includes("after") || lower.includes("before") || lower.includes("when ") || lower.includes("once")) {
    return {
      title: "时间状语从句",
      explanation: "这是用来交代时间背景的状语从句，说明事情在什么时间条件下发生。",
      function: "它在这句里先搭时间背景，再把真正要成立的判断交给主句。",
      why: "时间框架一旦错挂，背景信息就会被误读成核心判断。"
    };
  }
  if (normalized.includes("压缩定语从句")) {
    return {
      title: "压缩定语从句",
      explanation: "这是把完整关系从句压缩成更短修饰块的写法，本质上仍在补前面名词的信息。",
      function: "它在这里负责压缩对前面名词的限定说明，不是在另起一个主句。",
      why: "如果把这层误当成主干谓语，整句结构就会被拆坏。"
    };
  }
  if (normalized.includes("宾语从句")) {
    return {
      title: "宾语从句",
      explanation: "这是跟在谓语后面、充当核心内容的从句，常回答“认为什么”“说明什么”。",
      function: "它在这句里承接前面的谓语，真正承载作者要表达的内容对象。",
      why: "宾语从句一旦挂错，学生会把说法来源和作者判断混在一起。"
    };
  }
  if (normalized.includes("情态动词") || lower.includes("might") || lower.includes("could") || lower.includes("would") || lower.includes("should")) {
    return {
      title: "情态动词",
      explanation: "情态动词本身不增加新事实，而是在调节语气强弱，表示可能、推测、限制或建议。",
      function: "它在这句里控制作者判断的把握程度，不让语气走成绝对断言。",
      why: "情态一旦忽略，题目里的态度强弱和作者把握程度就会读偏。"
    };
  }
  if (normalized.includes("后置修饰") || normalized.includes("定语从句")) {
    return {
      title: normalized.includes("后置修饰") ? "后置修饰" : "定语从句",
      explanation: "这是补在中心名词后面的限定信息，读的时候要先找清楚它修饰谁。",
      function: "它在这里负责给前面的名词补限定范围，不是在推进新的主句判断。",
      why: "修饰对象一旦挂错，枝叶就会被误当成主干。"
    };
  }
  if (normalized.includes("非谓语") || lower.includes("participle") || lower.includes("infinitive")) {
    return {
      title: "非谓语结构",
      explanation: "这是把完整动作压缩成信息块的写法，常用来补目的、原因、伴随或修饰关系。",
      function: "它在这句里负责压缩附加信息，不能被当成新的完整谓语。",
      why: "如果把非谓语误判成主句谓语，整句主干会被直接拆坏。"
    };
  }
  if (normalized.includes("被动结构")) {
    return {
      title: "被动结构",
      explanation: "被动结构会把动作承受者顶到前面，真正的施动者可能后移甚至省略。",
      function: "它在这句里改变了信息出场顺序，强调的是谁被作用，而不是谁主动发出动作。",
      why: "如果被动方向没看清，因果和细节关系很容易整体读反。"
    };
  }
  if (normalized.includes("让步框架")) {
    return {
      title: "让步框架",
      explanation: "让步框架会先承认一个条件、反方声音或看似成立的情况，再回到自己的真正判断。",
      function: "它在这里先让一步，真正想成立的判断通常落在后面的主句。",
      why: "学生最容易把让步内容错当成作者最终立场。"
    };
  }

  return null;
}

function localizeGrammarFocusItem(item) {
  const template = grammarFocusTemplate(item.phenomenon || "");
  const titleZh = purifyChineseDisplayText(item.title_zh)
    || template?.title
    || purifyChineseDisplayText(sanitizePedagogicalChinese(item.phenomenon))
    || "关键语法点";
  const explanationZh = purifyChineseExplanation(item.explanation_zh)
    || template?.explanation
    || purifyChineseExplanation(sanitizePedagogicalChinese(item.phenomenon))
    || "这是本句里最值得先抓的一层结构。";
  const functionZh = purifyChineseExplanation(sanitizePedagogicalChinese(item.function))
    || template?.function
    || "它在这句里负责限定主干、补充范围或交代背景。";
  const whyZh = purifyChineseExplanation(item.why_it_matters_zh)
    || purifyChineseExplanation(sanitizePedagogicalChinese(item.why_it_matters))
    || template?.why
    || "这个结构一旦挂错，主干、修饰范围和命题改写都会跟着读偏。";

  return {
    phenomenon: item.phenomenon || titleZh,
    function: functionZh,
    why_it_matters: whyZh,
    title_zh: titleZh,
    explanation_zh: explanationZh,
    why_it_matters_zh: whyZh,
    example_en: normalizeString(item.example_en)
  };
}

function normalizeGrammarFocus(raw, fallbackPoints) {
  const direct = Array.isArray(raw)
    ? raw
      .map((item) => localizeGrammarFocusItem({
        phenomenon: normalizeString(item?.phenomenon),
        function: firstDefined(item, ["function"]),
        why_it_matters: firstDefined(item, ["why_it_matters", "whyItMatters"]),
        title_zh: normalizeString(item?.title_zh),
        explanation_zh: normalizeString(item?.explanation_zh),
        why_it_matters_zh: normalizeString(item?.why_it_matters_zh),
        example_en: normalizeString(item?.example_en)
      }))
      .filter((item) => item.phenomenon || item.function || item.why_it_matters || item.title_zh)
    : [];

  if (direct.length > 0) {
    return direct.slice(0, 3);
  }

  return normalizeArray(fallbackPoints)
    .map((item) => localizeGrammarFocusItem({
      phenomenon: normalizeString(item?.name),
      function: normalizeString(item?.explanation),
      why_it_matters: "这个结构一旦挂错范围或修饰对象，整句主干就会被带偏。",
      title_zh: "",
      explanation_zh: "",
      why_it_matters_zh: "",
      example_en: ""
    }))
    .filter((item) => item.phenomenon || item.function)
    .slice(0, 3);
}

function buildPassageRewriteTranslationExplanation({ simplerRewrite, faithfulTranslation, coreSkeleton, chunkLayers }) {
  const rewrite = normalizeString(simplerRewrite);
  if (!rewrite) return "";

  const parts = [];
  const faithful = normalizeString(faithfulTranslation);
  if (faithful) {
    parts.push(`这条改写仍在说：${faithful}`);
  }

  const layeredRoles = normalizeArray(chunkLayers).map((item) => normalizeString(item?.role));
  if (layeredRoles.some((role) => /前置框架|条件|让步|后置修饰/.test(role))) {
    parts.push("它保留了原句主干判断，把外围框架和修饰层压缩成更直接的主句表达。");
  } else {
    parts.push("它保留原意，只把句法改成更直接的主谓表达。");
  }

  const stableCore = renderCoreSkeleton(coreSkeleton);
  if (stableCore) {
    parts.push(`主干没有变，抓住“${stableCore}”就能看出改写没有换义。`);
  }

  return parts.join(" ");
}

function normalizedChineseComparisonKey(text) {
  return purifyChineseExplanation(text)
    .toLowerCase()
    .replace(/[^\p{sc=Han}a-z0-9]+/gu, "");
}

function buildPassageTeachingInterpretationFallback({ sentenceFunction, coreSkeleton, chunkLayers, faithfulTranslation }) {
  const parts = [];
  const localizedFunction = purifyChineseDisplayText(sentenceFunction);
  if (localizedFunction) {
    parts.push(`老师先会把这句当成“${localizedFunction}”来看。`);
  }

  const stableCore = renderCoreSkeleton(coreSkeleton);
  if (stableCore) {
    parts.push(`板书时先锁定“${stableCore}”，其余语块都往这个主干上挂。`);
  }

  const layeredRoles = normalizeArray(chunkLayers).map((item) => normalizeString(item?.role));
  if (layeredRoles.some((role) => /前置框架|条件|让步/.test(role))) {
    parts.push("读的时候不要被句首框架带走，真正判断一般落在后面的主句主干。");
  } else if (layeredRoles.some((role) => /后置修饰|补充说明/.test(role))) {
    parts.push("其余语块主要是在补限定范围和修饰关系，不要把枝叶误抬成主干。");
  }

  const faithful = purifyChineseExplanation(faithfulTranslation);
  if (faithful) {
    parts.push(`先把“${faithful}”这个基本意思抓稳，再回头分层看修饰关系。`);
  }

  return parts.join(" ");
}

function resolvePassageTeachingInterpretation({ teachingInterpretation, faithfulTranslation, sentenceFunction, coreSkeleton, chunkLayers }) {
  const faithfulKey = normalizedChineseComparisonKey(faithfulTranslation);
  const explicit = purifyChineseExplanation(teachingInterpretation);
  if (explicit && normalizedChineseComparisonKey(explicit) !== faithfulKey) {
    return explicit;
  }

  return buildPassageTeachingInterpretationFallback({
    sentenceFunction,
    coreSkeleton,
    chunkLayers,
    faithfulTranslation
  });
}

function normalizePassageOverview(raw) {
  if (!raw || typeof raw !== "object") {
    return {
      article_theme: "",
      author_core_question: "",
      progression_path: "",
      likely_question_types: [],
      logic_pitfalls: [],
      paragraph_function_map: [],
      syntax_highlights: [],
      reading_traps: [],
      vocabulary_highlights: []
    };
  }
  return {
    article_theme: purifyChineseExplanation(raw.article_theme),
    author_core_question: purifyChineseDisplayText(raw.author_core_question),
    progression_path: purifyChineseExplanation(raw.progression_path),
    likely_question_types: purifyChineseList(raw.likely_question_types, 5),
    logic_pitfalls: purifyChineseList(raw.logic_pitfalls, 5),
    paragraph_function_map: purifyChineseList(raw.paragraph_function_map, 8),
    syntax_highlights: purifyChineseList(raw.syntax_highlights, 5),
    reading_traps: purifyChineseList(raw.reading_traps, 5),
    vocabulary_highlights: normalizeArray(raw.vocabulary_highlights).map(String)
  };
}

function normalizeParagraphCard(raw) {
  if (!raw || typeof raw !== "object") return null;
  const validRoles = ["background", "support", "objection", "transition", "evidence", "conclusion"];
  const role = validRoles.includes(raw.argument_role) ? raw.argument_role : "support";
  return {
    paragraph_index: typeof raw.paragraph_index === "number" ? raw.paragraph_index : 0,
    theme: purifyChineseExplanation(raw.theme),
    argument_role: role,
    core_sentence_local_index: typeof raw.core_sentence_local_index === "number" ? raw.core_sentence_local_index : 0,
    keywords: normalizeArray(raw.keywords).map(String).filter(Boolean).slice(0, 8),
    relation_to_previous: purifyChineseDisplayText(raw.relation_to_previous),
    exam_value: purifyChineseExplanation(raw.exam_value),
    teaching_focuses: purifyChineseList(raw.teaching_focuses, 4),
    student_blind_spot: purifyChineseDisplayText(raw.student_blind_spot)
  };
}

function normalizeSentenceAnalysis(raw, sourceSentence) {
  if (!raw || typeof raw !== "object") return null;

  const evidenceType = normalizeEvidenceType(raw.evidence_type, "supporting_evidence");
  const rawVocabulary = firstDefined(raw, ["vocabulary_in_context", "contextual_vocabulary"]);
  const rawMisread = firstDefined(raw, ["misreading_traps", "misread_points", "common_misreadings"]);
  const rawRewrite = firstDefined(raw, ["exam_paraphrase_routes", "exam_rewrite_points", "exam_paraphrase_points"]);
  const rawSimplerRewrite = firstDefined(raw, ["simpler_rewrite", "simplified_english"]);
  const rawSimplerRewriteTranslation = firstDefined(raw, ["simpler_rewrite_translation", "rewrite_translation"]);
  const rawFaithfulTranslation = firstDefined(raw, ["faithful_translation"]);
  const rawTeachingInterpretation = firstDefined(raw, ["teaching_interpretation"]);
  const rawNaturalChineseMeaning = firstDefined(raw, ["natural_chinese_meaning"]);
  const rawChunkBreakdown = normalizeArray(raw.chunk_breakdown).map(String).filter(Boolean);
  const rawGrammarPoints = normalizeArray(raw.grammar_points)
    .map((item) => ({
      name: normalizeString(item?.name),
      explanation: normalizeString(item?.explanation)
    }))
    .filter((item) => item.name || item.explanation)
    .slice(0, 3);
  const coreSkeleton = normalizeCoreSkeleton(firstDefined(raw, ["core_skeleton"]), normalizeString(raw.sentence_core));
  const chunkLayers = normalizeChunkLayers(firstDefined(raw, ["chunk_layers"]), rawChunkBreakdown);
  const grammarFocus = normalizeGrammarFocus(firstDefined(raw, ["grammar_focus"]), rawGrammarPoints);
  const sentenceFunction = purifyChineseDisplayText(
    normalizeString(raw.sentence_function, buildSentenceFunctionFromEvidenceType(evidenceType))
  );
  const misreadingTraps = purifyChineseList(rawMisread, 3);
  const examParaphraseRoutes = purifyChineseList(rawRewrite, 3);
  const simplerRewrite = normalizeString(rawSimplerRewrite);
  const faithfulTranslation = purifyChineseExplanation(rawFaithfulTranslation);
  const simplerRewriteTranslation = (function resolveRewriteTranslation() {
    const explicit = purifyChineseExplanation(rawSimplerRewriteTranslation);
    if (explicit && normalizedChineseComparisonKey(explicit) !== normalizedChineseComparisonKey(faithfulTranslation)) {
      return explicit;
    }
    return buildPassageRewriteTranslationExplanation({
      simplerRewrite,
      faithfulTranslation,
      coreSkeleton,
      chunkLayers
    });
  })();
  const teachingInterpretation = resolvePassageTeachingInterpretation({
    teachingInterpretation: rawTeachingInterpretation || rawNaturalChineseMeaning,
    faithfulTranslation,
    sentenceFunction,
    coreSkeleton,
    chunkLayers
  });
  const miniCheck = purifyChineseDisplayText(firstDefined(raw, ["mini_check", "mini_exercise"]));
  const derivedChunkBreakdown = chunkLayers
    .map((item) => {
      const role = item.role || "语块";
      const text = item.text || "";
      return role && text ? `${role}：${text}` : text;
    })
    .filter(Boolean);

  return {
    sentence_ref: normalizeString(raw.sentence_ref),
    original_sentence: sourceSentence || normalizeString(raw.original_sentence),
    sentence_function: sentenceFunction,
    core_skeleton: coreSkeleton,
    chunk_layers: chunkLayers,
    grammar_focus: grammarFocus,
    faithful_translation: faithfulTranslation,
    teaching_interpretation: teachingInterpretation,
    natural_chinese_meaning: teachingInterpretation,
    sentence_core: normalizeString(raw.sentence_core, renderCoreSkeleton(coreSkeleton)),
    chunk_breakdown: rawChunkBreakdown.length > 0 ? rawChunkBreakdown : derivedChunkBreakdown,
    grammar_points: rawGrammarPoints.length > 0
      ? rawGrammarPoints
      : grammarFocus.map((item) => ({
        name: item.phenomenon,
        explanation: [item.function, item.why_it_matters ? `为什么重要：${item.why_it_matters}` : ""].filter(Boolean).join("｜")
      })),
    vocabulary_in_context: normalizeArray(rawVocabulary)
      .map((item) => ({
        term: normalizeString(item?.term),
        meaning: purifyChineseExplanation(item?.meaning)
      }))
      .filter((item) => item.term)
      .slice(0, 6),
    misread_points: misreadingTraps,
    misreading_traps: misreadingTraps,
    exam_rewrite_points: examParaphraseRoutes,
    exam_paraphrase_routes: examParaphraseRoutes,
    simplified_english: simplerRewrite,
    simpler_rewrite: simplerRewrite,
    simpler_rewrite_translation: simplerRewriteTranslation,
    mini_exercise: miniCheck,
    mini_check: miniCheck,
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
  if (result.passage_overview?.article_theme && !isChineseDominantText(result.passage_overview.article_theme)) {
    warnings.push("passage_overview.article_theme 中文纯度不足");
  }
  if (!result.passage_overview?.author_core_question || result.passage_overview.author_core_question.includes("作者真正要回答的问题可以概括为")) {
    warnings.push("passage_overview.author_core_question 太模板化");
  }
  if (!result.passage_overview?.progression_path || result.passage_overview.progression_path.length < 12) {
    warnings.push("passage_overview.progression_path 不够具体");
  }
  if (result.passage_overview?.progression_path && !result.passage_overview.progression_path.includes("→") && !(result.passage_overview.progression_path.includes("先") && result.passage_overview.progression_path.includes("再"))) {
    warnings.push("passage_overview.progression_path 不像讲义式推进路径");
  }
  if ((result.passage_overview?.likely_question_types || []).length < 2) {
    warnings.push("passage_overview.likely_question_types 太弱");
  }
  if ((result.passage_overview?.logic_pitfalls || []).length < 2) {
    warnings.push("passage_overview.logic_pitfalls 太弱");
  }

  if (result.paragraph_cards) {
    for (const card of result.paragraph_cards) {
      if (!card.theme || card.theme.includes("本段主要讲") || card.theme.includes("承担")) {
        warnings.push(`[P${card.paragraph_index}] theme 太空`);
      }
      if (card.theme && !isChineseDominantText(card.theme)) {
        warnings.push(`[P${card.paragraph_index}] theme 中文纯度不足`);
      }
      if (card.theme && !(card.theme.includes("真正") || card.theme.includes("关键") || card.theme.includes("核心") || card.theme.includes("要立住"))) {
        warnings.push(`[P${card.paragraph_index}] theme 讲义感不足`);
      }
      if (!card.relation_to_previous || card.relation_to_previous === "承接上文") {
        warnings.push(`[P${card.paragraph_index}] relation_to_previous 太空`);
      }
      if (!card.exam_value || (!card.exam_value.includes("题") && !card.exam_value.includes("陷阱"))) {
        warnings.push(`[P${card.paragraph_index}] exam_value 不像考试解法`);
      }
      if ((card.teaching_focuses || []).length === 0) {
        warnings.push(`[P${card.paragraph_index}] teaching_focuses 缺失`);
      }
      if ((card.teaching_focuses || []).some((item) => !item.includes("先") && !item.includes("别") && !item.includes("容易"))) {
        warnings.push(`[P${card.paragraph_index}] teaching_focuses 讲义感不足`);
      }
      if (!card.student_blind_spot || card.student_blind_spot.length < 10) {
        warnings.push(`[P${card.paragraph_index}] student_blind_spot 太弱`);
      }
    }
  }

  if (!Array.isArray(result.key_sentence_refs) || result.key_sentence_refs.length === 0) {
    warnings.push("key_sentence_refs 缺失");
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
    "2. relation_to_previous 和 exam_value 必须具体到逻辑推进和考试题型，不能只写泛泛判断。",
    "3. teaching_focuses 必须写成具体教学动作，而不是抽象建议。",
    "4. passage_overview 必须像老师带读整篇文章，而不是做摘要；progression_path 要像讲义里的推进图，likely_question_types 和 logic_pitfalls 不能空。",
    "5. key_sentence_refs 只保留最值得点开深讲的关键句编号，不要返回逐句解析字段。",
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

export async function analyzePassage({ requestID, title = "", paragraphs = [], keySentences = [] }) {
  const client = getDashScopeClient();
  const { modelName } = getDashScopeConfig();

  if (!client) {
    throw new AppError("DASHSCOPE_API_KEY 或 DASHSCOPE_BASE_URL 未配置。", {
      statusCode: 500,
      code: "MODEL_CONFIG_MISSING",
      requestID,
      fallbackAvailable: true
    });
  }

  const sanitizedInputs = sanitizePassageInputs(paragraphs, keySentences);
  const effectiveParagraphs = sanitizedInputs.paragraphs;
  const effectiveKeySentences = sanitizedInputs.keySentences;
  const cacheKey = aiResponseCache.makeKey([
    "analyze-passage.v2",
    title,
    ...effectiveParagraphs.map((item) => `${item.index}:${item.text}`),
    ...effectiveKeySentences.map((item) => item.ref)
  ]);
  const cached = aiResponseCache.get(cacheKey);
  if (cached) {
    return {
      ...cached,
      request_id: requestID,
      used_cache: true,
      used_fallback: false,
      retry_count: 0
    };
  }

  console.log("[ai/analyze-passage] calling model", {
    modelName,
    paragraphCount: effectiveParagraphs.length,
    keySentenceCount: effectiveKeySentences.length,
    titleLength: title.length,
    requestID
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
  let retryCount = 0;

  try {
    const response = await requestGeminiCompletion({
      requestID,
      breakerKey: "analyze-passage",
      timeoutMs: 120_000,
      invoke: () => requestModel(buildAnalyzePassagePrompt({
        title,
        paragraphs: effectiveParagraphs,
        keySentences: effectiveKeySentences
      }))
    });
    completion = response.completion;
    retryCount = response.retryCount;
  } catch (error) {
    if (cached) {
      return {
        ...cached,
        request_id: requestID,
        used_cache: true,
        used_fallback: false,
        retry_count: 0
      };
    }
    throw error;
  }

  const elapsed = Date.now() - startTime;
  const normalizeResult = (parsed) => {
    const overview = normalizePassageOverview(parsed.passage_overview);
    const paragraphCards = normalizeArray(parsed.paragraph_cards)
      .map(normalizeParagraphCard)
      .filter(Boolean);
    const keySentenceRefs = normalizeArray(parsed.key_sentence_refs)
      .map((item) => normalizeString(item))
      .filter(Boolean)
      .slice(0, MAX_KEY_SENTENCES);

    return {
      passage_overview: overview,
      paragraph_cards: paragraphCards,
      key_sentence_refs: keySentenceRefs
    };
  };

  let normalized = normalizeResult(parseModelJson(completion.choices?.[0]?.message?.content));
  let qualityWarnings = validateAnalysisQuality(normalized);

  if (
    qualityWarnings.length >= 2 ||
    normalized.paragraph_cards.length < Math.min(effectiveParagraphs.length, MAX_PARAGRAPHS)
  ) {
    console.warn("[ai/analyze-passage] quality warnings after first pass:", qualityWarnings);

    try {
      const repairedCompletion = await requestModel(buildAnalyzePassageRepairPrompt({
        title,
        paragraphs: effectiveParagraphs,
        keySentences: effectiveKeySentences,
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
    paragraphCards: normalized.paragraph_cards.length,
    keySentenceRefs: normalized.key_sentence_refs.length,
    qualityWarnings: qualityWarnings.length
  });

  const response = {
    passage_overview: normalized.passage_overview,
    paragraph_cards: normalized.paragraph_cards,
    key_sentence_refs: normalized.key_sentence_refs.length > 0
      ? normalized.key_sentence_refs
      : effectiveKeySentences.map((item) => item.ref).slice(0, MAX_KEY_SENTENCES),
    quality_warnings: qualityWarnings,
    model_name: modelName,
    elapsed_ms: elapsed,
    request_id: requestID,
    used_cache: false,
    used_fallback: false,
    retry_count: retryCount
  };
  aiResponseCache.set(cacheKey, response);
  return response;
}
