import { AppError } from "../lib/appError.js";
import { createAIClient } from "../models/aiClient.js";
import { createModelRegistry } from "../models/modelRegistry.js";
import { createAIError, ERROR_CODES } from "../models/errors.js";

const defaultExplainSentenceAIClient = createAIClient({
  registry: createModelRegistry()
});

const TRANSLATION_TEACHING_TONE_PATTERNS = [
  "学生容易误读",
  "做题时要注意",
  "作者真正强调",
  "本句承担",
  "先抓主句",
  "不要把",
  "命题人",
  "真正判断"
];

export function buildExplainSentencePrompt({ title, sentence, context, paragraph_theme, paragraph_role, question_prompt }) {
  const safeTitle = title?.trim() || "未提供";
  const safeContext = context?.trim() || "未提供";
  const safeParagraphTheme = paragraph_theme?.trim() || "未提供";
  const safeParagraphRole = paragraph_role?.trim() || "未提供";
  const safeQuestionPrompt = question_prompt?.trim() || "未提供";

  return [
    "你是一位顶级英语教授，专门把英语阅读材料讲成教授级课堂。",
    "你必须只输出一个合法 JSON 对象。",
    "不要输出 Markdown。",
    "不要输出 ```json 代码块。",
    "不要输出任何额外解释、前后缀、标题或自然语言。",
    "请使用中文讲解，但必要时保留关键英语术语或英语原句片段。",
    "JSON 顶层必须是对象。",
    "你不是摘要器，你是在教学生如何真正读懂句子、识别主干、修饰语、逻辑关系和出题改写。",
    "输出字段必须固定为：original_sentence、evidence_type、sentence_function、core_skeleton、chunk_layers、grammar_focus、faithful_translation、teaching_interpretation、natural_chinese_meaning、contextual_vocabulary、misreading_traps、exam_paraphrase_routes、simpler_rewrite、simpler_rewrite_translation、mini_check、hierarchy_rebuild、syntactic_variation。",
    "original_sentence 必须回填原句。",
    "evidence_type 必须只能是：background_info / transition_signal / core_claim / supporting_evidence / counter_argument / conclusion_marker 之一。",
    "sentence_function 必须直接说明这句在论证里在做什么，如“核心判断句：作者真正要成立的判断在这里”。",
    "core_skeleton 必须是对象，字段固定为 subject、predicate、complement_or_object。内容必须明确，不允许空泛总结。字段值里不允许再出现 [subject: ...] 这类 bracket 标记，只能保留真实成分内容。",
    "chunk_layers 必须是数组，每项都是对象，字段固定为 text、role、attaches_to、gloss。role 要说明它是核心信息、前置框架、后置修饰、补充说明还是让步/条件框架。",
    "grammar_focus 必须是数组，每项都是对象，字段固定为 phenomenon、function、why_it_matters、title_zh、explanation_zh、why_it_matters_zh、example_en。function 必须写“这个结构在本句起什么作用”；explanation_zh 必须写“它是什么”；why_it_matters_zh 必须写“为什么重要”。只保留最关键的 1-3 个。",
    "faithful_translation 必须是忠实翻译：中文自然，但要尽量贴住原句真实意思，不要偷换成教学评论。",
    "teaching_interpretation 必须是教学解读：说明这句话真正承担什么功能、该先抓哪一层、为什么容易读错。不能只是把 faithful_translation 换个说法重复一遍。",
    "natural_chinese_meaning 用于兼容旧字段，内容与 teaching_interpretation 保持一致。",
    "contextual_vocabulary 必须是数组，每项字段固定为 term、meaning，meaning 必须是本句义。",
    "misreading_traps 必须指出学生最容易误判主干、修饰范围、指代、否定或逻辑关系的地方。",
    "exam_paraphrase_routes 必须指出该句可能如何在阅读理解题中被改写、偷换或设陷阱。",
    "simpler_rewrite 用更简单的英语重写这句话，保持原意。",
    "simpler_rewrite_translation 必须用中文说明这个英文简化改写在说什么，以及它是怎样在保留原意的前提下把结构简化的。",
    "mini_check 给一个非常短、非常精确的小检验；如果不适合，返回空字符串。",
    "hierarchy_rebuild 用于长难句，按层级重组；简单句返回空数组。",
    "syntactic_variation 用更易懂的句法把原句重写；简单句也尽量给出。",
    "如果信息不足，也必须返回空字符串或空数组，不能缺字段。",
    "",
    `资料标题: ${safeTitle}`,
    `句子: ${sentence.trim()}`,
    `上下文: ${safeContext}`,
    `段落主旨: ${safeParagraphTheme}`,
    `段落角色: ${safeParagraphRole}`,
    `相关题目: ${safeQuestionPrompt}`,
    "",
    "输出标准：",
    "1. 输出优先级必须体现：句子定位 → 句子主干 → 语块切分 → 关键语法点 → 学生易错点 → 出题改写点 → 简化英文改写 → 微练习。",
    "2. faithful_translation 必须是忠实翻译；teaching_interpretation 才负责老师口吻的解释，两者不能混写，也不能互相抄写。",
    "2.1 faithful_translation 和 teaching_interpretation 都必须以中文为主；除专门术语、原句片段、语法标签外，不允许出现整段英文说明。",
    "3. core_skeleton 必须直接说清主句主干，不能写成“本句讲了什么”或“先抓主干”。",
    "4. chunk_layers 不是机械切分，必须说明每一块的功能和挂接对象。",
    "5. grammar_focus 只保留最关键的 1-3 个语法点。title_zh、explanation_zh、why_it_matters_zh 必须中文主导；function 也必须用中文说明它在本句里的作用。phenomenon/function/why_it_matters 只作为兼容字段。",
    "6. misreading_traps 必须明确学生最可能把哪一层挂错、读错或范围看错。",
    "7. exam_paraphrase_routes 要贴近阅读理解命题，如同义替换、因果偷换、范围缩放、态度弱化，并尽量给出具体改写路线。",
    "8. mini_check 必须是一个可立即检验理解的小问题，不要空泛提问。",
    "9. 整体口吻必须像严谨但易懂的英语教授。"
  ].join("\n");
}

function buildProfessorSentencePrompt({ title, sentence, context, paragraph_theme, paragraph_role, question_prompt }) {
  const safeTitle = title?.trim() || "未提供";
  const safeContext = context?.trim() || "未提供";
  const safeParagraphTheme = paragraph_theme?.trim() || "未提供";
  const safeParagraphRole = paragraph_role?.trim() || "未提供";
  const safeQuestionPrompt = question_prompt?.trim() || "未提供";

  return [
    "你是一位严谨的英语句法教授，只能输出一个合法 JSON 对象。",
    "不要输出 Markdown，不要输出代码块，不要输出额外自然语言。",
    "请围绕 Professor Sentence Workflow 输出：破除误读、句法手术、边界测试、阅读题映射。",
    "JSON 只服务于英语句子解析，不要输出与句法无关的摘要或作文式评论。",
    "",
    "只输出以下字段：",
    "original_sentence",
    "sentence_function",
    "core_skeleton",
    "faithful_translation",
    "teaching_interpretation",
    "chunk_layers",
    "grammar_focus",
    "misreading_traps",
    "exam_paraphrase_routes",
    "simpler_rewrite",
    "simpler_rewrite_translation",
    "mini_check",
    "",
    "字段要求：",
    "1. original_sentence 必须回填原句。",
    "2. sentence_function 必须是对象，字段固定为 title_zh、explanation_zh。title_zh 一律写“句子定位”。",
    "3. core_skeleton 必须是对象，字段固定为 subject、predicate、complement_or_object、explanation_zh。",
    "4. faithful_translation 只能做忠实翻译，不得写老师讲解口吻，不得出现“学生容易误读 / 做题时要注意 / 作者真正强调 / 本句承担”等表达。",
    "5. teaching_interpretation 必须是教学解读，不能和 faithful_translation 相同，也不能只是翻译的简单改写。",
    "6. chunk_layers 必须是数组，每项字段固定为 text、role_zh、attaches_to、gloss_zh。",
    "7. grammar_focus 必须是数组，每项字段固定为 title_zh、explanation_zh、why_it_matters_zh、example_en。中文字段必须中文主导。",
    "8. misreading_traps 必须写清学生最容易读错的层级、修饰关系或逻辑点。",
    "9. exam_paraphrase_routes 必须写清阅读题可能怎样改写。",
    "10. simpler_rewrite_translation 必须用中文解释简化改写在保留原意的前提下做了什么。",
    "11. 不允许在任何字段里输出 [subject: ...] / [predicate: ...] / [object clause: ...] / [complement: ...] 这类 bracket 标记。",
    "",
    "阶段一：破除误读",
    "指出学生最容易把哪一层读错，不要泛泛而谈。",
    "阶段二：句法手术",
    "交代主语、谓语、核心补足、语块层级、修饰对象。",
    "阶段三：边界测试",
    "检查否定范围、指代范围、转折/让步和修饰误挂。",
    "阶段四：阅读题映射",
    "指出这句在阅读题里可能如何被改写、偷换或设陷阱。",
    "",
    `资料标题: ${safeTitle}`,
    `句子: ${sentence.trim()}`,
    `上下文: ${safeContext}`,
    `段落主旨: ${safeParagraphTheme}`,
    `段落角色: ${safeParagraphRole}`,
    `相关题目: ${safeQuestionPrompt}`
  ].join("\n");
}

function buildProfessorSentenceRepairPrompt({ payload, previousText, reasons }) {
  return [
    buildProfessorSentencePrompt(payload),
    "",
    "上一次输出已经可以解析为 JSON，但不满足契约，请只修复失败字段，并继续只输出一个合法 JSON 对象。",
    `失败原因：${reasons.join("；")}`,
    "必须修复：",
    "1. public contract 必须完整。",
    "2. faithful_translation 只能做中文翻译，不能写老师点评。",
    "3. teaching_interpretation 必须是教学解读，不能重复 faithful_translation。",
    "4. grammar_focus 必须变成中文主字段。",
    "5. 全部字段禁止 bracket 标记泄露。",
    "",
    "上一版输出为：",
    previousText
  ].join("\n");
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

function normalizeArray(value) {
  return Array.isArray(value) ? value : [];
}

function firstDefined(raw, keys) {
  for (const key of keys) {
    if (raw[key] !== undefined) {
      return raw[key];
    }
  }
  return undefined;
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

function inferEvidenceTypeFromParagraphRole(role = "") {
  switch (String(role || "").trim().toLowerCase()) {
    case "background":
      return "background_info";
    case "transition":
      return "transition_signal";
    case "objection":
      return "counter_argument";
    case "conclusion":
      return "conclusion_marker";
    case "evidence":
      return "supporting_evidence";
    case "support":
    default:
      return "core_claim";
  }
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

function hasExplicitSentenceCore(core) {
  const normalized = typeof core === "string" ? core.trim() : "";
  if (!normalized) return false;
  const hasSubject = normalized.includes("主语");
  const hasPredicate = normalized.includes("谓语");
  const hasComplement = normalized.includes("核心补足") || normalized.includes("宾语") || normalized.includes("补语") || normalized.includes("表语");
  return (hasSubject && hasPredicate) || normalized.startsWith("主干判断：");
}

function labelChunkBreakdown(chunks, coreClause) {
  if (!Array.isArray(chunks) || chunks.length === 0) {
    return [];
  }

  const coreTrimmed = (coreClause || "").trim();
  const subordinateLeads = [
    ["although", "框架让步"],
    ["though", "框架让步"],
    ["while", "框架对比"],
    ["if", "条件框架"],
    ["when", "时间框架"],
    ["because", "因果前提"],
    ["since", "因果前提"],
    ["as", "框架说明"],
    ["despite", "让步背景"],
    ["in order to", "目的框架"],
    ["after", "时间框架"],
    ["before", "时间框架"],
    ["once", "时间框架"]
  ];

  return chunks.map((chunk, index) => {
    const trimmed = String(chunk || "").trim();
    if (!trimmed) return "";
    const lower = trimmed.toLowerCase();

    if (trimmed === coreTrimmed) {
      return `核心信息：${trimmed}`;
    }
    if (/\b(which|that|who|whom|whose|where|when)\b/.test(lower) && index > 0) {
      return `后置修饰：${trimmed}`;
    }
    const lead = subordinateLeads.find(([marker]) => lower.startsWith(marker));
    if (lead) {
      return `${lead[1]}：${trimmed}`;
    }
    if (index === 0 && coreTrimmed && trimmed !== coreTrimmed) {
      return `前置框架：${trimmed}`;
    }
    return `补充说明：${trimmed}`;
  }).filter(Boolean);
}

function ensureExplainResultShape(raw) {
  const requiredKeyGroups = [
    ["original_sentence"],
    ["evidence_type", "sentence_role"],
    ["sentence_function", "evidence_type", "sentence_role"],
    ["core_skeleton", "sentence_core"],
    ["chunk_layers", "chunk_breakdown"],
    ["grammar_focus", "grammar_points"],
    ["faithful_translation"],
    ["teaching_interpretation", "natural_chinese_meaning"],
    ["contextual_vocabulary", "vocabulary_in_context"],
    ["misreading_traps", "misread_points", "common_misreadings"],
    ["exam_paraphrase_routes", "exam_rewrite_points", "exam_paraphrase_points"],
    ["simpler_rewrite", "simplified_english"],
    ["simpler_rewrite_translation", "rewrite_translation"],
    ["mini_check", "mini_exercise"],
    ["hierarchy_rebuild"],
    ["syntactic_variation"]
  ];

  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new AppError("模型返回格式异常，JSON 顶层不是对象。", {
      statusCode: 502,
      code: "MODEL_INVALID_JSON"
    });
  }

  for (const group of requiredKeyGroups) {
    const hasKey = group.some((lookupKey) => lookupKey in raw);

    if (!hasKey) {
      throw new AppError(`模型返回格式异常，缺少字段 ${group[0]}。`, {
        statusCode: 502,
        code: "MODEL_INVALID_SCHEMA"
      });
    }
  }
}

function normalizeExplainResult(raw, sourceSentence, paragraph_role = "") {
  ensureExplainResultShape(raw);

  const rawVocabulary = firstDefined(raw, ["vocabulary_in_context", "contextual_vocabulary"]);
  const rawMisread = firstDefined(raw, ["misreading_traps", "misread_points", "common_misreadings"]);
  const rawRewritePoints = firstDefined(raw, ["exam_paraphrase_routes", "exam_rewrite_points", "exam_paraphrase_points"]);
  const rawSimplerRewrite = firstDefined(raw, ["simpler_rewrite", "simplified_english"]);
  const rawSimplerRewriteTranslation = firstDefined(raw, ["simpler_rewrite_translation", "rewrite_translation"]);
  const rawEvidenceType = firstDefined(raw, ["evidence_type", "sentence_role"]);
  const rawFaithfulTranslation = firstDefined(raw, ["faithful_translation"]);
  const rawTeachingInterpretation = firstDefined(raw, ["teaching_interpretation"]);
  const rawNaturalChineseMeaning = firstDefined(raw, ["natural_chinese_meaning"]);
  const evidenceType = normalizeEvidenceType(rawEvidenceType, inferEvidenceTypeFromParagraphRole(paragraph_role));
  const sentenceFunction = purifyChineseDisplayText(raw.sentence_function)
    || buildSentenceFunctionFromEvidenceType(evidenceType);
  const coreSkeleton = normalizeCoreSkeleton(firstDefined(raw, ["core_skeleton"]), sourceSentence);
  const chunkLayers = normalizeChunkLayers(firstDefined(raw, ["chunk_layers"]), sourceSentence);
  const grammarFocus = normalizeGrammarFocus(firstDefined(raw, ["grammar_focus"]), sourceSentence);
  const renderedCoreSkeleton = renderCoreSkeleton(coreSkeleton);
  const sentenceCore = typeof raw.sentence_core === "string" && raw.sentence_core.trim()
    ? (containsLegacyBracketCoreMarkup(raw.sentence_core) || (!hasExplicitSentenceCore(raw.sentence_core) && renderedCoreSkeleton)
      ? renderedCoreSkeleton || buildFallbackSentenceCore(sourceSentence)
      : raw.sentence_core.trim())
    : renderedCoreSkeleton || buildFallbackSentenceCore(sourceSentence);
  const chunkBreakdown = normalizeArray(raw.chunk_breakdown)
    .map((item) => typeof item === "string" ? item.trim() : "")
    .filter(Boolean);
  const effectiveChunkBreakdown = chunkBreakdown.length > 0
    ? chunkBreakdown
    : chunkLayers.map((item) => {
      const role = item.role || "语块";
      const text = item.text || "";
      return `${role}：${text}`.trim();
    }).filter(Boolean);
  const rawGrammarPoints = normalizeArray(raw.grammar_points)
    .map((item) => ({
      name: typeof item?.name === "string" ? item.name.trim() : "",
      explanation: typeof item?.explanation === "string" ? item.explanation.trim() : ""
    }))
    .filter((item) => item.name || item.explanation);
  const grammarPoints = rawGrammarPoints.length > 0
    ? rawGrammarPoints
    : grammarFocus.map((item) => ({
      name: item.title_zh || item.phenomenon,
      explanation: [
        item.explanation_zh || item.function,
        item.why_it_matters_zh || item.why_it_matters ? `为什么重要：${item.why_it_matters_zh || item.why_it_matters}` : ""
      ].filter(Boolean).join("｜")
    }));
  const vocabularyInContext = normalizeArray(rawVocabulary)
    .map((item) => ({
      term: typeof item?.term === "string" ? item.term.trim() : "",
      meaning: purifyChineseExplanation(typeof item?.meaning === "string" ? item.meaning.trim() : "")
    }))
    .filter((item) => item.term || item.meaning);
  const rawMisreadingTraps = normalizeArray(rawMisread)
    .map((item) => typeof item === "string" ? item.trim() : "")
    .filter(Boolean);
  const rawExamParaphraseRoutes = normalizeArray(rawRewritePoints)
    .map((item) => typeof item === "string" ? item.trim() : "")
    .filter(Boolean);
  const misreadingTraps = purifyChineseList(rawMisreadingTraps, 4);
  const examParaphraseRoutes = purifyChineseList(rawExamParaphraseRoutes, 4);
  const faithfulTranslation = purifyChineseExplanation(rawFaithfulTranslation);
  const teachingInterpretation = resolveTeachingInterpretation({
    teachingInterpretation: rawTeachingInterpretation,
    naturalChineseMeaning: rawNaturalChineseMeaning,
    faithfulTranslation,
    sentenceFunction,
    coreSkeleton,
    chunkLayers
  });
  const simplerRewrite = typeof rawSimplerRewrite === "string" ? rawSimplerRewrite.trim() : "";
  const simplerRewriteTranslation = (function resolveRewriteTranslation() {
    const explicit = purifyChineseExplanation(rawSimplerRewriteTranslation);
    if (explicit && normalizedChineseComparisonKey(explicit) !== normalizedChineseComparisonKey(faithfulTranslation)) {
      return explicit;
    }
    return buildRewriteTranslationExplanation({
      simplerRewrite,
      faithfulTranslation,
      coreSkeleton,
      chunkLayers
    });
  })();
  const miniCheck = typeof firstDefined(raw, ["mini_check", "mini_exercise"]) === "string"
    ? firstDefined(raw, ["mini_check", "mini_exercise"]).trim()
    : "";

  return {
    original_sentence: typeof raw.original_sentence === "string" && raw.original_sentence.trim()
      ? raw.original_sentence.trim()
      : sourceSentence.trim(),
    sentence_function: sentenceFunction,
    core_skeleton: coreSkeleton,
    chunk_layers: chunkLayers,
    grammar_focus: grammarFocus,
    faithful_translation: faithfulTranslation,
    teaching_interpretation: teachingInterpretation,
    natural_chinese_meaning: teachingInterpretation,
    sentence_core: sentenceCore,
    evidence_type: evidenceType,
    chunk_breakdown: effectiveChunkBreakdown,
    grammar_points: grammarPoints,
    vocabulary_in_context: vocabularyInContext,
    contextual_vocabulary: vocabularyInContext,
    misread_points: misreadingTraps,
    misreading_traps: misreadingTraps,
    exam_rewrite_points: examParaphraseRoutes,
    exam_paraphrase_routes: examParaphraseRoutes,
    simplified_english: simplerRewrite,
    simpler_rewrite: simplerRewrite,
    simpler_rewrite_translation: simplerRewriteTranslation,
    mini_exercise: miniCheck,
    mini_check: miniCheck,
    hierarchy_rebuild: normalizeArray(raw.hierarchy_rebuild)
      .map((item) => typeof item === "string" ? item.trim() : "")
      .filter(Boolean),
    syntactic_variation: typeof raw.syntactic_variation === "string" ? raw.syntactic_variation.trim() : "",
    translation: faithfulTranslation,
    main_structure: sentenceCore,
    key_terms: vocabularyInContext,
    rewrite_example: simplerRewrite
  };
}

function tokenizeEnglishWords(text) {
  return (text.match(/[A-Za-z][A-Za-z'-]*/g) || []).map((token) => token.trim()).filter(Boolean);
}

function buildRewriteTranslationExplanation({ simplerRewrite, faithfulTranslation, coreSkeleton, chunkLayers }) {
  const rewrite = typeof simplerRewrite === "string" ? simplerRewrite.trim() : "";
  if (!rewrite) return "";

  const parts = [];
  const faithful = typeof faithfulTranslation === "string" ? faithfulTranslation.trim() : "";
  if (faithful) {
    parts.push(`这条改写仍在说：${faithful}`);
  }

  const layeredRoles = Array.isArray(chunkLayers) ? chunkLayers.map((item) => String(item?.role || "").trim()) : [];
  if (layeredRoles.some((role) => /前置框架|条件|让步|后置修饰/.test(role))) {
    parts.push("它保留了原句主干判断，把外围框架和修饰层压缩成更直接的主句表达。");
  } else {
    parts.push("它保留原意，只把句法改成更直接的主谓表达。");
  }

  if (coreSkeleton?.subject || coreSkeleton?.predicate) {
    const subject = typeof coreSkeleton.subject === "string" ? coreSkeleton.subject.trim() : "";
    const predicate = typeof coreSkeleton.predicate === "string" ? coreSkeleton.predicate.trim() : "";
    const complement = typeof coreSkeleton.complement_or_object === "string"
      ? coreSkeleton.complement_or_object.trim()
      : (typeof coreSkeleton.complementOrObject === "string" ? coreSkeleton.complementOrObject.trim() : "");
    const stableCore = [
      subject ? `主语：${subject}` : "",
      predicate ? `谓语：${predicate}` : "",
      complement ? `核心补足：${complement}` : ""
    ].filter(Boolean).join("｜");
    if (stableCore) {
      parts.push(`主干没有变，抓住“${stableCore}”就能看出改写没有换义。`);
    }
  }

  return parts.join(" ");
}

function normalizedChineseComparisonKey(text) {
  return purifyChineseExplanation(text)
    .toLowerCase()
    .replace(/[^\p{sc=Han}a-z0-9]+/gu, "");
}

function buildTeachingInterpretationFallback({ sentenceFunction, coreSkeleton, chunkLayers, faithfulTranslation }) {
  const parts = [];
  const localizedFunction = purifyChineseDisplayText(sentenceFunction);
  if (localizedFunction) {
    parts.push(`老师先会把这句当成“${localizedFunction}”来看。`);
  }

  if (coreSkeleton?.subject || coreSkeleton?.predicate || coreSkeleton?.complement_or_object || coreSkeleton?.complementOrObject) {
    const subject = typeof coreSkeleton.subject === "string" ? coreSkeleton.subject.trim() : "";
    const predicate = typeof coreSkeleton.predicate === "string" ? coreSkeleton.predicate.trim() : "";
    const complement = typeof coreSkeleton.complement_or_object === "string"
      ? coreSkeleton.complement_or_object.trim()
      : (typeof coreSkeleton.complementOrObject === "string" ? coreSkeleton.complementOrObject.trim() : "");
    const stableCore = [
      subject ? `主语“${subject}”` : "",
      predicate ? `谓语“${predicate}”` : "",
      complement ? `核心补足“${complement}”` : ""
    ].filter(Boolean).join("、");
    if (stableCore) {
      parts.push(`板书时先锁定 ${stableCore}，其余信息都往这个主干上挂。`);
    }
  }

  const layeredRoles = Array.isArray(chunkLayers) ? chunkLayers.map((item) => String(item?.role || "").trim()) : [];
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

function resolveTeachingInterpretation({ teachingInterpretation, naturalChineseMeaning, faithfulTranslation, sentenceFunction, coreSkeleton, chunkLayers }) {
  const faithfulKey = normalizedChineseComparisonKey(faithfulTranslation);
  const explicit = purifyChineseExplanation(teachingInterpretation);
  if (explicit && normalizedChineseComparisonKey(explicit) !== faithfulKey) {
    return explicit;
  }

  const legacy = purifyChineseExplanation(naturalChineseMeaning);
  if (legacy && normalizedChineseComparisonKey(legacy) !== faithfulKey) {
    return legacy;
  }

  return buildTeachingInterpretationFallback({
    sentenceFunction,
    coreSkeleton,
    chunkLayers,
    faithfulTranslation
  });
}

function isChineseDominantText(text) {
  const normalized = typeof text === "string" ? text.trim() : "";
  if (!normalized) return false;

  const chineseCount = (normalized.match(/[\u4e00-\u9fff]/g) || []).length;
  const latinCount = (normalized.match(/[A-Za-z]/g) || []).length;

  if (chineseCount === 0) return false;
  return chineseCount >= Math.max(8, latinCount * 2);
}

function extractChineseDominantClauses(text) {
  const normalized = typeof text === "string" ? text.trim() : "";
  if (!normalized) return [];

  return normalized
    .split(/\n+/)
    .flatMap((line) => line.split(/[。！？；]/))
    .map((item) => item.trim())
    .filter((item) => {
      if (!item) return false;
      const chineseCount = (item.match(/[\u4e00-\u9fff]/g) || []).length;
      const latinCount = (item.match(/[A-Za-z]/g) || []).length;
      return chineseCount >= 8 && chineseCount > latinCount;
    });
}

function purifyChineseExplanation(text) {
  const normalized = typeof text === "string" ? text.trim() : "";
  if (!normalized) return "";
  const sanitized = sanitizePedagogicalChinese(normalized);
  if (isChineseDominantText(sanitized) && !containsPedagogicalEnglishLeakage(sanitized)) return sanitized;

  const recovered = extractChineseDominantClauses(sanitized);
  return recovered.length > 0 ? recovered.join("。") : "";
}

function purifyChineseDisplayText(text) {
  const normalized = typeof text === "string" ? text.trim() : "";
  if (!normalized) return "";

  const rangeIndex = normalized.indexOf("：") >= 0
    ? normalized.indexOf("：")
    : normalized.indexOf(":");

  if (rangeIndex > 0) {
    const head = normalized.slice(0, rangeIndex).trim();
    const body = purifyChineseExplanation(normalized.slice(rangeIndex + 1));
    if (body) {
      return `${head}：${body}`;
    }
  }

  return purifyChineseExplanation(normalized);
}

function purifyChineseList(values, limit = 4) {
  const ordered = [];
  const seen = new Set();

  for (const value of Array.isArray(values) ? values : []) {
    const normalized = purifyChineseDisplayText(String(value || ""));
    if (!normalized) continue;
    const key = normalized.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    ordered.push(normalized);
    if (ordered.length >= limit) break;
  }

  return ordered;
}

function grammarFocusTemplate(raw) {
  const normalized = typeof raw === "string" ? raw.trim() : "";
  const lower = normalized.toLowerCase();

  if (normalized.includes("时间状语从句") || lower.includes("temporal clause") || lower.includes("adverbial clause") || lower.includes("after") || lower.includes("before") || lower.includes("when ") || lower.includes("once")) {
    return {
      title: "时间状语从句",
      explanation: "这是用来交代时间背景的状语从句，说明事情在什么时间条件下发生。",
      function: "它在这句里先搭时间背景，再把真正要成立的判断交给主句。",
      why: "时间框架一旦错挂，背景信息就会被错读成核心判断。"
    };
  }
  if (normalized.includes("压缩定语从句") || normalized.includes("省略关系从句") || lower.includes("reduced relative clause")) {
    return {
      title: "压缩定语从句",
      explanation: "这是把完整关系从句压缩成更短修饰块的写法，本质上仍在补前面名词的信息。",
      function: "它在这里负责压缩对前面名词的限定说明，不是在另起一个主句。",
      why: "如果把这层误当成主干谓语，整句结构就会被拆坏。"
    };
  }
  if (normalized.includes("宾语从句") || lower.includes("object clause")) {
    return {
      title: "宾语从句",
      explanation: "这是跟在谓语后面、充当核心内容的从句，常回答“认为什么”“说明什么”。",
      function: "它在这句里承接前面的谓语，真正承载作者要表达的内容对象。",
      why: "宾语从句一旦挂错，学生会把说法来源和作者判断混在一起。"
    };
  }
  if (normalized.includes("情态动词") || lower.includes("modal verb") || lower.includes("might") || lower.includes("may ") || lower.includes("could") || lower.includes("would") || lower.includes("should")) {
    return {
      title: "情态动词",
      explanation: "情态动词本身不增加新事实，而是在调节语气强弱，表示可能、推测、限制或建议。",
      function: "它在这句里控制作者判断的把握程度，不让语气走成绝对断言。",
      why: "情态一旦忽略，题目里的态度强弱和作者把握程度就会读偏。"
    };
  }
  if (normalized.includes("后置修饰") || lower.includes("postpositive modifier")) {
    return {
      title: "后置修饰",
      explanation: "后置修饰是放在中心名词后面补信息的结构，读的时候要先找清楚它修饰谁。",
      function: "它在这里负责给前面的名词补限定范围，不是在推进新的主句判断。",
      why: "后置修饰挂错对象，是长难句里最常见的误读来源。"
    };
  }
  if (normalized.includes("定语从句") || lower.includes("relative clause")) {
    return {
      title: "定语从句",
      explanation: "定语从句是在给前面的名词补限定信息，告诉你“哪一个”“什么样的”。",
      function: "它在这里继续限定前面的名词，不是作者另起一层新的判断。",
      why: "修饰对象一旦看错，枝叶就会被误当成主干。"
    };
  }
  if (normalized.includes("非谓语") || lower.includes("non-finite") || lower.includes("participle") || lower.includes("infinitive")) {
    return {
      title: "非谓语结构",
      explanation: "非谓语是把完整动作压缩成信息块的写法，常用来补目的、原因、伴随或修饰关系。",
      function: "它在这句里负责压缩附加信息，不能被当成新的完整谓语。",
      why: "把非谓语误判成主句谓语，会直接拆错主干。"
    };
  }
  if (normalized.includes("被动") || lower.includes("passive voice")) {
    return {
      title: "被动结构",
      explanation: "被动结构会把动作承受者顶到前面，真正的施动者则可能后移甚至省略。",
      function: "它在这句里改变了信息出场顺序，强调的是谁被作用而不是谁发出动作。",
      why: "如果被动方向没看清，因果和细节关系很容易整体反过来。"
    };
  }
  if (normalized.includes("否定") || lower.includes("negation")) {
    return {
      title: "否定范围",
      explanation: "否定范围指的是否定词到底压在哪一层信息上，而不是看到 not 就结束。",
      function: "它在这句里限制判断成立的范围，决定作者否定的是动作、比较项还是限定条件。",
      why: "否定范围错一层，题目选项往往会整句反向。"
    };
  }
  if (normalized.includes("让步框架") || lower.includes("concessive frame")) {
    return {
      title: "让步框架",
      explanation: "让步框架会先承认一个条件、反方声音或看似成立的情况，再回到自己的真正判断。",
      function: "它在这里先让一步，真正想成立的判断通常落在后面的主句。",
      why: "学生最容易把让步内容错当成作者最终立场。"
    };
  }
  if (normalized.includes("前置框架") || lower.includes("framing phrase")) {
    return {
      title: "前置框架",
      explanation: "前置框架是先放在句首的背景交代层，用来限定主句判断成立的场景、时间或角度。",
      function: "它在这里先定阅读坐标，再把真正判断交给后面的主句。",
      why: "如果把前置框架误读成主干，整句重点就会跑偏。"
    };
  }

  return null;
}

function normalizeMixedGrammarChinese(text) {
  let normalized = typeof text === "string" ? text.trim() : "";
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

  normalized = normalized.replace(/([A-Za-z]+)\s*引导的/g, "由原句里的“$1 …”引出的");
  return normalized;
}

function sanitizePedagogicalChinese(text) {
  return normalizeMixedGrammarChinese(text)
    .replace(/\[[A-Za-z_\s-]+:\s*[^\]]+\]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function containsPedagogicalEnglishLeakage(text) {
  const normalized = typeof text === "string" ? text.trim() : "";
  if (!normalized) return false;
  if (/\[[A-Za-z_\s-]+:\s*[^\]]+\]/.test(normalized)) return true;
  if (/[A-Za-z]{2,}\s*引导/.test(normalized)) return true;
  return /[A-Za-z]{8,}(?:\s+[A-Za-z]{2,})+/.test(normalized);
}

function looksLikeGrammarRoleDescription(text) {
  const normalized = typeof text === "string" ? text.trim() : "";
  if (!normalized) return false;
  return normalized.includes("本句")
    || normalized.includes("在这句")
    || normalized.includes("先抓")
    || normalized.includes("不要把")
    || normalized.includes("阅读时");
}

function localizeGrammarFocusItem(item) {
  const template = grammarFocusTemplate(item.phenomenon || "");
  const titleZh = purifyChineseDisplayText(item.title_zh) || template?.title || purifyChineseDisplayText(sanitizePedagogicalChinese(item.phenomenon));
  const explicitExplanationZh = purifyChineseExplanation(item.explanation_zh);
  const explanationZh = (!looksLikeGrammarRoleDescription(explicitExplanationZh) && explicitExplanationZh)
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
    ...item,
    phenomenon: item.phenomenon || titleZh,
    function: functionZh,
    why_it_matters: whyZh,
    title_zh: titleZh,
    explanation_zh: explanationZh,
    why_it_matters_zh: whyZh,
    example_en: typeof item.example_en === "string" ? item.example_en.trim() : ""
  };
}

const explainStopwords = new Set([
  "the", "and", "for", "with", "that", "this", "from", "into", "their", "there",
  "have", "been", "being", "which", "while", "about", "would", "could", "should",
  "because", "through", "after", "before", "where", "when", "they", "them", "were",
  "your", "than", "then", "such", "very", "more", "most"
]);

function splitSentenceIntoChunks(sentence) {
  const normalized = sentence
    .replace(/\u2014/g, ", ")
    .replace(/;/g, ", ")
    .replace(/\s+/g, " ")
    .trim();

  const baseChunks = normalized
    .split(",")
    .map((chunk) => chunk.trim())
    .filter(Boolean);

  if (baseChunks.length === 0) {
    return [sentence.trim()];
  }

  const subordinateMarkers = [" because ", " although ", " while ", " when ", " if ", " unless ", " whereas ", " since ", " as long as ", " provided that "];
  const relativeMarkers = [" which ", " who ", " that ", " whom ", " whose ", " where "];
  const prepMarkers = [" by ", " with ", " through ", " despite ", " in order to ", " according to ", " rather than ", " instead of "];

  const splitByMarker = (chunks, markers, minLength) => {
    const results = [];
    for (const chunk of chunks) {
      const lower = ` ${chunk.toLowerCase()} `;
      const marker = markers.find((item) => lower.includes(item));
      if (chunk.length > minLength && marker) {
        const needle = marker.trim();
        const index = chunk.toLowerCase().indexOf(needle);
        if (index > 0) {
          const head = chunk.slice(0, index).trim();
          const tail = chunk.slice(index).trim();
          if (head) results.push(head);
          if (tail) results.push(tail);
          continue;
        }
      }
      results.push(chunk);
    }
    return results;
  };

  return splitByMarker(
    splitByMarker(
      splitByMarker(baseChunks, subordinateMarkers, 32),
      relativeMarkers,
      50
    ),
    prepMarkers,
    60
  );
}

function extractCoreClause(sentence, chunks) {
  if (!chunks.length) return sentence.trim();
  const subordinateLeads = [
    "although", "while", "when", "if", "because", "since",
    "as", "to ", "by ", "despite", "given that", "in order to",
    "whereas", "unless", "after", "before", "once"
  ];

  let mainIndex = 0;
  for (const [index, chunk] of chunks.entries()) {
    const lower = chunk.toLowerCase().trim();
    const isSubordinate = subordinateLeads.some((lead) => lower.startsWith(lead));
    if (isSubordinate && index < chunks.length - 1) {
      mainIndex = index + 1;
      continue;
    }
    break;
  }

  return chunks[mainIndex] || chunks.sort((lhs, rhs) => rhs.length - lhs.length)[0] || sentence.trim();
}

function extractCoreComponents(coreClause) {
  const rawTokens = coreClause
    .replace(/[—–]/g, " ")
    .split(/\s+/)
    .map((token) => token.replace(/^[^A-Za-z]+|[^A-Za-z]+$/g, ""))
    .filter(Boolean);

  if (rawTokens.length < 2) {
    return { subject: "", predicate: "", complement: "" };
  }

  const auxiliaries = new Set([
    "am", "is", "are", "was", "were", "be", "been", "being",
    "do", "does", "did", "have", "has", "had",
    "can", "could", "may", "might", "must", "shall",
    "should", "will", "would", "seem", "seems", "appear", "appears",
    "remain", "remains", "became", "become", "becomes", "means", "mean",
    "suggests", "suggest", "shows", "show", "argues", "argue",
    "indicates", "indicate", "helps", "help", "leads", "lead", "allows", "allow"
  ]);

  const predicateIndex = rawTokens.findIndex((token, index) => {
    if (index === 0) return false;
    const lower = token.toLowerCase();
    return auxiliaries.has(lower) || lower.endsWith("ed") || lower.endsWith("ing");
  });

  if (predicateIndex <= 0) {
    return { subject: "", predicate: "", complement: "" };
  }

  return {
    subject: rawTokens.slice(0, predicateIndex).join(" "),
    predicate: rawTokens[predicateIndex],
    complement: rawTokens.slice(predicateIndex + 1, predicateIndex + 9).join(" ")
  };
}

function buildFallbackSentenceCore(sentence) {
  const chunks = splitSentenceIntoChunks(sentence);
  const coreClause = extractCoreClause(sentence, chunks);
  const components = extractCoreComponents(coreClause);

  if (components.subject && components.predicate) {
    if (components.complement) {
      return `主语：${components.subject}｜谓语：${components.predicate}｜核心补足：${components.complement}`;
    }
    return `主语：${components.subject}｜谓语：${components.predicate}｜核心补足：无明显宾补，句意主要靠主谓关系成立`;
  }

  return `主干判断：${coreClause}`;
}

function buildFallbackCoreSkeleton(sentence) {
  const chunks = splitSentenceIntoChunks(sentence);
  const coreClause = extractCoreClause(sentence, chunks);
  const components = extractCoreComponents(coreClause);

  if (components.subject && components.predicate) {
    return {
      subject: components.subject,
      predicate: components.predicate,
      complement_or_object: components.complement || ""
    };
  }

  return {
    subject: "",
    predicate: "",
    complement_or_object: coreClause
  };
}

function renderCoreSkeleton(coreSkeleton) {
  if (!coreSkeleton || typeof coreSkeleton !== "object") {
    return "";
  }

  const subject = sanitizeCoreSkeletonField(typeof coreSkeleton.subject === "string" ? coreSkeleton.subject : "");
  const predicate = sanitizeCoreSkeletonField(typeof coreSkeleton.predicate === "string" ? coreSkeleton.predicate : "");
  const complement = typeof coreSkeleton.complement_or_object === "string"
    ? sanitizeCoreSkeletonField(coreSkeleton.complement_or_object)
    : typeof coreSkeleton.complementOrObject === "string"
      ? sanitizeCoreSkeletonField(coreSkeleton.complementOrObject)
      : "";

  const parts = [];
  if (subject) parts.push(`主语：${subject}`);
  if (predicate) parts.push(`谓语：${predicate}`);
  if (complement) parts.push(`核心补足：${complement}`);
  return parts.join("｜");
}

function containsLegacyBracketCoreMarkup(value) {
  const normalized = typeof value === "string" ? value.trim() : "";
  return /\[[A-Za-z_\s-]+:\s*[^\]]+\]/.test(normalized);
}

function normalizeCoreSkeleton(raw, fallbackSentence) {
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    const subject = sanitizeCoreSkeletonField(typeof raw.subject === "string" ? raw.subject : "");
    const predicate = sanitizeCoreSkeletonField(typeof raw.predicate === "string" ? raw.predicate : "");
    const complement = typeof raw.complement_or_object === "string"
      ? sanitizeCoreSkeletonField(raw.complement_or_object)
      : typeof raw.complementOrObject === "string"
        ? sanitizeCoreSkeletonField(raw.complementOrObject)
        : typeof raw.object === "string"
          ? sanitizeCoreSkeletonField(raw.object)
          : "";
    const compatible = parseCompatibleCoreSkeleton([subject, predicate, complement].join(" "));
    if (compatible) {
      return compatible;
    }
    if (subject || predicate || complement) {
      return { subject, predicate, complement_or_object: complement };
    }
  }

  return parseCompatibleCoreSkeleton(fallbackSentence) || buildFallbackCoreSkeleton(fallbackSentence);
}

function sanitizeCoreSkeletonField(value) {
  const normalized = typeof value === "string" ? value.trim() : "";
  if (!normalized) return "";
  return normalized
    .replace(/\[[A-Za-z_\s-]+:\s*([^\]]+)\]/g, "$1")
    .replace(/^(主语|谓语|核心补足|宾语|补语|表语|subject|predicate|object|complement)\s*[：:]\s*/gi, "")
    .replace(/\s+/g, " ")
    .trim();
}

function parseCompatibleCoreSkeleton(text) {
  const rawNormalized = typeof text === "string" ? text.trim() : "";
  if (!rawNormalized) return null;

  if (containsLegacyBracketCoreMarkup(rawNormalized)) {
    const bracketSkeleton = parseBracketCoreSkeleton(rawNormalized);
    if (bracketSkeleton) {
      return {
        subject: sanitizeCoreSkeletonField(bracketSkeleton.subject),
        predicate: sanitizeCoreSkeletonField(bracketSkeleton.predicate),
        complement_or_object: sanitizeCoreSkeletonField(bracketSkeleton.complementOrObject || bracketSkeleton.complement_or_object || "")
      };
    }
  }

  const normalized = sanitizeCoreSkeletonField(rawNormalized);
  if (!normalized) return null;

  const segments = normalized
    .replace(/\n/g, "｜")
    .replace(/／/g, "｜")
    .replace(/\//g, "｜")
    .split("｜")
    .map((item) => item.trim())
    .filter(Boolean);

  let subject = "";
  let predicate = "";
  let complement = "";

  for (const segment of segments) {
    if (segment.includes("主语：") || segment.includes("主语:")) {
      subject = sanitizeCoreSkeletonField(segment.replace(/主语[：:]/, ""));
    } else if (segment.includes("谓语：") || segment.includes("谓语:")) {
      predicate = sanitizeCoreSkeletonField(segment.replace(/谓语[：:]/, ""));
    } else if (segment.includes("核心补足：") || segment.includes("核心补足:") || segment.includes("宾语：") || segment.includes("宾语:") || segment.includes("补语：") || segment.includes("表语：")) {
      complement = sanitizeCoreSkeletonField(
        segment
          .replace(/核心补足[：:]/, "")
          .replace(/宾语[：:]/, "")
          .replace(/补语[：:]/, "")
          .replace(/表语[：:]/, "")
      );
    }
  }

  if (subject || predicate || complement) {
    return { subject, predicate, complement_or_object: complement };
  }

  return null;
}

function buildFallbackChunkLayers(sentence) {
  const chunks = splitSentenceIntoChunks(sentence);
  const coreClause = extractCoreClause(sentence, chunks);

  return labelChunkBreakdown(chunks, coreClause).map((item) => {
    const [rawRole, rawText = ""] = String(item).split(/[:：]/, 2);
    const role = (rawRole || "").trim();
    const text = (rawText || item).trim();

    if (role === "核心信息") {
      return {
        text,
        role,
        attaches_to: "主句主干",
        gloss: "这一块先读稳，再把其他修饰信息补回去。"
      };
    }
    if (role.includes("框架") || role.includes("让步") || role.includes("条件") || role.includes("时间")) {
      return {
        text,
        role,
        attaches_to: "核心信息",
        gloss: "先把它当阅读框架，不要把它误当主句判断。"
      };
    }
    if (role === "后置修饰") {
      return {
        text,
        role,
        attaches_to: "前面名词或主句主干",
        gloss: "回头确认它到底修饰谁。"
      };
    }
    return {
      text,
      role: role || "补充说明",
      attaches_to: "核心信息",
      gloss: "它主要在补范围、条件或细节。"
    };
  });
}

function normalizeChunkLayers(raw, fallbackSentence) {
  if (Array.isArray(raw)) {
    const items = raw
      .map((item) => ({
        text: typeof item?.text === "string" ? item.text.trim() : "",
        role: typeof item?.role === "string" ? item.role.trim() : "",
        attaches_to: typeof item?.attaches_to === "string"
          ? item.attaches_to.trim()
          : typeof item?.attachesTo === "string"
            ? item.attachesTo.trim()
            : "",
        gloss: typeof item?.gloss === "string" ? item.gloss.trim() : ""
      }))
      .filter((item) => item.text || item.role || item.attaches_to || item.gloss);
    if (items.length > 0) {
      return items;
    }
  }

  return buildFallbackChunkLayers(fallbackSentence);
}

function buildFallbackGrammarFocus(sentence) {
  const coreClause = extractCoreClause(sentence, splitSentenceIntoChunks(sentence));
  const lower = sentence.toLowerCase();
  const items = [];

  if (/\b(which|that|who|whom|whose|where|when)\b/.test(lower)) {
    items.push({
      phenomenon: "定语从句 / 后置修饰",
      function: `本句含有后置修饰，阅读时先抓“${coreClause}”这一主干，再回头判断从句到底修饰谁。`,
      why_it_matters: "修饰对象一旦挂错，学生就会把枝叶误当成主干判断。",
      title_zh: "定语从句 / 后置修饰",
      explanation_zh: `本句含有后置修饰，阅读时先抓“${coreClause}”这一主干，再回头判断从句到底修饰谁。`,
      why_it_matters_zh: "修饰对象一旦挂错，学生就会把枝叶误当成主干判断。",
      example_en: ""
    });
  }

  if (/\bto\s+[a-z]+|\b[a-z]+ing\b/.test(lower)) {
    items.push({
      phenomenon: "非谓语结构",
      function: "这里的 to do / doing 更像压缩信息块，不是另起一个完整谓语。",
      why_it_matters: "如果把非谓语误判成完整谓语，整句主干会被拆坏。",
      title_zh: "非谓语结构",
      explanation_zh: "这里的 to do / doing 更像压缩信息块，不是另起一个完整谓语。",
      why_it_matters_zh: "如果把非谓语误判成完整谓语，整句主干会被拆坏。",
      example_en: ""
    });
  }

  if (/\b(am|is|are|was|were|be|been|being)\s+\w+ed\b/.test(lower)) {
    items.push({
      phenomenon: "被动结构",
      function: "被动语态会把真正施动者后移或省略，阅读时要分清动作发出者和承受者。",
      why_it_matters: "如果忽略被动方向，细节题和因果题很容易读反。",
      title_zh: "被动结构",
      explanation_zh: "被动语态会把真正施动者后移或省略，阅读时要分清动作发出者和承受者。",
      why_it_matters_zh: "如果忽略被动方向，细节题和因果题很容易读反。",
      example_en: ""
    });
  }

  if (lower.includes("not") || lower.includes("never") || lower.includes("no ")) {
    items.push({
      phenomenon: "否定范围",
      function: "本句带否定色彩，要看清否定落在谓语、比较项还是限定范围上。",
      why_it_matters: "否定范围一旦看错，选项的态度和细节判断会整体反向。",
      title_zh: "否定范围",
      explanation_zh: "本句带否定色彩，要看清否定落在谓语、比较项还是限定范围上。",
      why_it_matters_zh: "否定范围一旦看错，选项的态度和细节判断会整体反向。",
      example_en: ""
    });
  }

  if (items.length === 0) {
    items.push({
      phenomenon: "主干优先",
      function: `先把“${coreClause}”这一主句读稳，再回头处理其余修饰层。`,
      why_it_matters: "先主干后修饰，才能避免平均翻译。",
      title_zh: "主干优先",
      explanation_zh: `先把“${coreClause}”这一主句读稳，再回头处理其余修饰层。`,
      why_it_matters_zh: "先主干后修饰，才能避免平均翻译。",
      example_en: ""
    });
  }

  return items.slice(0, 3).map(localizeGrammarFocusItem);
}

function normalizeGrammarFocus(raw, fallbackSentence) {
  if (Array.isArray(raw)) {
    const items = raw
      .map((item) => localizeGrammarFocusItem({
        phenomenon: typeof item?.phenomenon === "string" ? item.phenomenon.trim() : "",
        function: typeof item?.function === "string" ? item.function.trim() : "",
        why_it_matters: typeof item?.why_it_matters === "string"
          ? item.why_it_matters.trim()
          : typeof item?.whyItMatters === "string"
            ? item.whyItMatters.trim()
            : ""
        ,
        title_zh: typeof item?.title_zh === "string"
          ? item.title_zh.trim()
          : typeof item?.titleZh === "string"
            ? item.titleZh.trim()
            : "",
        explanation_zh: typeof item?.explanation_zh === "string"
          ? item.explanation_zh.trim()
          : typeof item?.explanationZh === "string"
            ? item.explanationZh.trim()
            : "",
        why_it_matters_zh: typeof item?.why_it_matters_zh === "string"
          ? item.why_it_matters_zh.trim()
          : typeof item?.whyItMattersZh === "string"
            ? item.whyItMattersZh.trim()
            : "",
        example_en: typeof item?.example_en === "string"
          ? item.example_en.trim()
          : typeof item?.exampleEn === "string"
            ? item.exampleEn.trim()
            : ""
      }))
      .filter((item) => item.phenomenon || item.function || item.why_it_matters || item.title_zh || item.explanation_zh || item.why_it_matters_zh);
    if (items.length > 0) {
      return items.slice(0, 3);
    }
  }

  return buildFallbackGrammarFocus(fallbackSentence);
}

function buildFallbackFaithfulTranslation() {
  return "";
}

function buildFallbackTeachingInterpretation({ sentence, paragraph_theme = "", paragraph_role = "" }) {
  const chunks = splitSentenceIntoChunks(sentence);
  const coreClause = extractCoreClause(sentence, chunks);
  const lower = sentence.toLowerCase();

  if (lower.startsWith("although") || lower.startsWith("though") || lower.includes(" even though ")) {
    return `这句话真正的意思是：前面先让步，真正要成立的判断落在“${coreClause}”这一层。`;
  }
  if (lower.includes("however") || lower.includes(" but ") || lower.includes(" yet ")) {
    return `这句话自然读成中文时，要把转折后的“${coreClause}”当成真正重点，前面的内容更多是在铺垫或对比。`;
  }
  if (lower.includes("because") || lower.includes("therefore") || lower.includes("thus")) {
    return `这句话是在说明因果链条：核心判断落在“${coreClause}”这一块，其余语块是在交代原因、结果或推导依据。`;
  }
  if (chunks.length >= 3) {
    return `这句话的自然意思不是逐词平移，而是先成立主句“${coreClause}”，再把其余语块当成条件、限定或补充说明依次加回去。`;
  }
  if (paragraph_theme.trim()) {
    return `这句话真正在替本段说明的是：${paragraph_theme.trim()}；其中最该先抓住的判断落在“${coreClause}”这一层。`;
  }
  if (paragraph_role.trim()) {
    return `这句话真正想表达的是“${coreClause}”；它在本段里承担的是 ${paragraph_role.trim()} 这一层功能。`;
  }
  return `这句话真正想说的是“${coreClause}”，其余成分只是帮助你把范围、条件和修饰关系补全。`;
}

function buildFallbackMisreadPoints({ sentence, chunks, coreClause }) {
  const lower = sentence.toLowerCase();
  const points = [];

  if (chunks.length >= 3) {
    points.push(`这句信息层次较多，最容易从左到右平均翻译；应先锁定主干“${coreClause}”，再补修饰信息。`);
  }
  if (lower.startsWith("although") || lower.startsWith("while") || lower.startsWith("though")) {
    points.push(`句首让步/从属成分不是主句，真正判断落在后面的“${coreClause}”，不要把前半句误读成作者立场。`);
  }
  if (lower.includes("not") || lower.includes("never")) {
    points.push("本句带否定色彩，要看清 not / never 到底否定的是谓语、比较项还是限定范围。");
  }
  if (lower.includes("which") || lower.includes("that") || lower.includes("who")) {
    points.push("这句带后置修饰，学生常把从句错挂到错误名词上，导致主干关系读偏。");
  }
  if (points.length === 0) {
    points.push("先找主句主语和谓语，再依次判断其余部分在补什么信息，不要逐词平推。");
  }

  return points.slice(0, 3);
}

function buildFallbackExamRewritePoints({ sentence, paragraph_role = "" }) {
  const lower = sentence.toLowerCase();
  const points = [];

  if (lower.includes("however") || lower.includes("but") || lower.includes("yet")) {
    points.push("命题人常把转折前内容包装成正确选项；真正可选的意思通常落在转折后。");
  }
  if (lower.includes("not") || lower.includes("never") || lower.includes("hardly")) {
    points.push("常见陷阱是把原文的否定或部分否定偷换成全称肯定。");
  }
  if (lower.includes("which") || lower.includes("that")) {
    points.push("后置修饰常被拆开重写；选项会保留主干不变，只把修饰结构换皮。");
  }
  if (paragraph_role === "evidence") {
    points.push("例证句常被改写成“这个例子证明了什么”，答案不在细节本身，而在它支撑的判断。");
  }
  if (paragraph_role === "objection") {
    points.push("让步句最常见的陷阱，是把作者承认的对方观点误写成作者自己的最终立场。");
  }
  if (points.length === 0) {
    points.push("常见改写方式包括同义替换、主被动改写，以及把抽象名词还原成动词表达。");
  }

  return points.slice(0, 3);
}

function buildFallbackVocabularyInContext(sentence) {
  const tokens = tokenizeEnglishWords(sentence)
    .map((token) => token.toLowerCase())
    .filter((token) => token.length >= 4 && !explainStopwords.has(token));
  const uniqueTokens = [...new Set(tokens)].slice(0, 4);

  return uniqueTokens.map((term) => ({
    term,
    meaning: "需结合本句主干和上下文判断其具体指向，不要只套词典义。"
  }));
}

function buildFallbackHierarchyRebuild(chunks, coreClause) {
  if (chunks.length < 3) return [];
  const extraChunks = chunks.filter((chunk) => chunk !== coreClause);
  return [`先只看主干：${coreClause}`, ...extraChunks.map((chunk) => `再补一层信息：${chunk}`)].slice(0, 4);
}

function buildFallbackSyntacticVariation(sentence) {
  const chunks = splitSentenceIntoChunks(sentence);
  const coreClause = extractCoreClause(sentence, chunks);
  const extraChunks = chunks.filter((chunk) => chunk !== coreClause);
  if (extraChunks.length === 0) {
    return coreClause;
  }
  return `In simpler syntax: ${coreClause}, and the rest of the sentence mainly adds ${extraChunks.slice(0, 2).join(" / ")}.`;
}

function buildFallbackMiniExercise(result) {
  if (result.grammar_points.some((item) => item?.name?.includes("定语从句"))) {
    return "微练习：先只划出主句主语和谓语，再指出从句到底修饰哪个名词。";
  }
  if (result.chunk_breakdown.length >= 3) {
    return "微练习：请把这句话按“主干 / 条件或让步 / 补充解释”三层重新编号。";
  }
  return "微练习：先口头复述主句，再说明其余成分是在补什么信息。";
}

function isShallowText(text, patterns = []) {
  const normalized = typeof text === "string" ? text.trim() : "";
  if (!normalized) return true;
  return patterns.some((pattern) => normalized.includes(pattern));
}

function validateExplainResultQuality(result, sourceSentence) {
  const warnings = [];

  if (isShallowText(result.faithful_translation, ["这句话服务于本段", "真正要", "重点在"])) {
    warnings.push("faithful_translation 仍然混入教学评论");
  }
  if (isShallowText(result.teaching_interpretation, ["直译", "逐词对译"]) || result.teaching_interpretation.length < 10) {
    warnings.push("teaching_interpretation 太弱");
  }
  if (isShallowText(result.sentence_function, ["这句话", "本句", "用于说明"]) || result.sentence_function.length < 10) {
    warnings.push("sentence_function 太弱");
  }
  if (!result.core_skeleton || !hasExplicitSentenceCore(result.sentence_core)) {
    warnings.push("core_skeleton / sentence_core 仍然不够像主干解析");
  }
  if (!result.evidence_type) {
    warnings.push("evidence_type 缺失");
  }
  if ((result.chunk_layers?.length || 0) <= 1 && sourceSentence.trim().length > 40) {
    warnings.push("chunk_layers 不足");
  }
  if ((result.chunk_layers || []).length > 0 && !(result.chunk_layers || []).some((item) => item.role === "核心信息")) {
    warnings.push("chunk_layers 缺少核心信息标记");
  }
  if ((result.grammar_focus?.length || 0) === 0 && sourceSentence.trim().length > 35) {
    warnings.push("grammar_focus 缺失");
  }
  if ((result.vocabulary_in_context?.length || 0) === 0 && sourceSentence.trim().length > 30) {
    warnings.push("vocabulary_in_context 缺失");
  }
  if ((result.misreading_traps || []).every((item) => isShallowText(item, ["注意理解", "注意语法", "需要注意"]))) {
    warnings.push("misreading_traps 太泛");
  }
  if ((result.exam_paraphrase_routes || []).every((item) => isShallowText(item, ["可能考同义替换", "常见同义替换"]))) {
    warnings.push("exam_paraphrase_routes 太泛");
  }
  if (result.faithful_translation && !isChineseDominantText(result.faithful_translation)) {
    warnings.push("faithful_translation 中文纯度不足");
  }
  if (result.teaching_interpretation && !isChineseDominantText(result.teaching_interpretation)) {
    warnings.push("teaching_interpretation 中文纯度不足");
  }

  return warnings;
}

function extractAnalysisKeywords(result) {
  const pieces = [
    result.original_sentence,
    result.sentence_core,
    result.core_skeleton?.subject,
    result.core_skeleton?.predicate,
    result.core_skeleton?.complement_or_object,
    ...(result.chunk_layers || []).map((item) => item?.text || ""),
    ...(result.vocabulary_in_context || []).map((item) => item?.term || "")
  ];

  const keywords = pieces
    .flatMap((piece) => tokenizeEnglishWords(piece || ""))
    .map((token) => token.toLowerCase())
    .filter((token) => token.length >= 3 && !explainStopwords.has(token));

  return [...new Set(keywords)];
}

function keywordOverlapScore(sourceSentence, result) {
  const sourceTokens = [...new Set(
    tokenizeEnglishWords(sourceSentence)
      .map((token) => token.toLowerCase())
      .filter((token) => token.length >= 3 && !explainStopwords.has(token))
  )];

  if (sourceTokens.length === 0) return 1;

  const analysisTokens = extractAnalysisKeywords(result);
  if (analysisTokens.length === 0) return 0;

  const sourceSet = new Set(sourceTokens);
  const overlapCount = analysisTokens.filter((token) => sourceSet.has(token)).length;
  return overlapCount / sourceTokens.length;
}

function grammarFocusLooksMismatched(item, sentence) {
  const phenomenon = String(item?.phenomenon || "").trim();
  const lower = sentence.toLowerCase();

  if (!phenomenon) return false;
  if (phenomenon.includes("被动") && !/\b(am|is|are|was|were|be|been|being)\s+\w+ed\b/.test(lower)) {
    return true;
  }
  if ((phenomenon.includes("定语从句") || phenomenon.includes("后置修饰")) && !/\b(which|that|who|whom|whose|where|when)\b/.test(lower)) {
    return true;
  }
  if (phenomenon.includes("非谓语") && !(/\bto\s+[a-z]+\b/.test(lower) || /\b[a-z]+ing\b/.test(lower))) {
    return true;
  }
  if (phenomenon.includes("否定") && !(lower.includes(" not ") || lower.includes("never") || lower.includes("hardly") || lower.includes("no "))) {
    return true;
  }
  return false;
}

function validateExplainResultConsistency(result, sourceSentence) {
  const warnings = [];
  let critical = false;

  const normalizedSource = sourceSentence.replace(/\s+/g, " ").trim().toLowerCase();
  const normalizedReturned = String(result.original_sentence || "").replace(/\s+/g, " ").trim().toLowerCase();
  if (normalizedReturned && normalizedReturned !== normalizedSource) {
    warnings.push("original_sentence 与源句不一致");
    critical = true;
  }

  const overlap = keywordOverlapScore(sourceSentence, result);
  if (overlap < 0.12) {
    warnings.push(`关键词重叠过低(${overlap.toFixed(2)})`);
    if (overlap < 0.08) {
      critical = true;
    }
  }

  const mismatchedGrammarCount = (result.grammar_focus || []).filter((item) => grammarFocusLooksMismatched(item, sourceSentence)).length;
  if (mismatchedGrammarCount >= 2 || ((result.grammar_focus || []).length > 0 && mismatchedGrammarCount === result.grammar_focus.length)) {
    warnings.push("grammar_focus 与源句结构不符");
    critical = true;
  }

  return { warnings, critical };
}

function buildExplainSentenceRepairPrompt({
  title,
  sentence,
  context,
  paragraph_theme,
  paragraph_role,
  question_prompt,
  previousResult,
  warnings
}) {
  return [
    buildExplainSentencePrompt({ title, sentence, context, paragraph_theme, paragraph_role, question_prompt }),
    "",
    "上一次输出质量不够，请你只修复薄弱字段，并继续只输出合法 JSON 对象。",
    `薄弱点：${warnings.join("；")}`,
    "特别要求：",
    "1. sentence_function 必须先判清这句是背景、推进、核心判断、证据、让步还是结论，并直接说清它在论证中做什么。",
    "2. faithful_translation 只负责忠实翻译，不能混入“真正要你抓”“这句在本段里”这类教学评论。",
    "3. teaching_interpretation 才负责老师口吻的解释，要直接说清学生该先抓哪一层、最容易把哪层挂错。",
    "4. core_skeleton 必须明确 subject、predicate、complement_or_object，不能再写空泛总结，字段值里也不能带 [subject: ...] 这种 bracket 标记。",
    "5. chunk_layers 每一项都要标明 role、attaches_to、gloss，至少要有一项 role 是“核心信息”。",
    "6. grammar_focus 必须说清结构功能和为什么重要，不能只贴标签；function 必须用中文说明它在本句里的作用，title_zh、explanation_zh、why_it_matters_zh 必须是中文主导的 UI 友好表述。",
    "7. misreading_traps 必须写清学生会把哪一层读错。",
    "8. exam_paraphrase_routes 必须写出命题人会怎么偷换。",
    "",
    "你上一次的 JSON 为：",
    JSON.stringify(previousResult)
  ].join("\n");
}

function enrichExplainResult(result, {
  sentence,
  paragraph_theme,
  paragraph_role
}) {
  const rawChunkTexts = Array.isArray(result.chunk_layers) && result.chunk_layers.length > 0
    ? result.chunk_layers.map((item) => item.text || "").filter(Boolean)
    : result.chunk_breakdown;
  const rawChunks = rawChunkTexts.length > 0 ? rawChunkTexts : splitSentenceIntoChunks(sentence);
  const plainChunks = rawChunks.map((item) => String(item).replace(/^[^：:]+[:：]/, "").trim()).filter(Boolean);
  const chunks = plainChunks.length > 0 ? plainChunks : splitSentenceIntoChunks(sentence);
  const coreClause = extractCoreClause(sentence, chunks);
  const labeledChunks = labelChunkBreakdown(chunks, coreClause);
  const evidenceType = normalizeEvidenceType(result.evidence_type, inferEvidenceTypeFromParagraphRole(paragraph_role));
  const coreSkeleton = result.core_skeleton && typeof result.core_skeleton === "object"
    ? result.core_skeleton
    : buildFallbackCoreSkeleton(sentence);
  const chunkLayers = Array.isArray(result.chunk_layers) && result.chunk_layers.length > 0
    ? result.chunk_layers
    : buildFallbackChunkLayers(sentence);
  const grammarFocus = Array.isArray(result.grammar_focus) && result.grammar_focus.length > 0
    ? result.grammar_focus
    : buildFallbackGrammarFocus(sentence);
  const sentenceFunction = typeof result.sentence_function === "string" && result.sentence_function.trim()
    ? result.sentence_function.trim()
    : buildSentenceFunctionFromEvidenceType(evidenceType);
  const misreadingTraps = result.misreading_traps?.length > 0 ? result.misreading_traps : buildFallbackMisreadPoints({
    sentence,
    chunks,
    coreClause
  });
  const examParaphraseRoutes = result.exam_paraphrase_routes?.length > 0 ? result.exam_paraphrase_routes : buildFallbackExamRewritePoints({
    sentence,
    paragraph_role
  });
  const simplerRewrite = result.simpler_rewrite || result.simplified_english || `${coreClause}.`;
  const faithfulTranslation = result.faithful_translation || buildFallbackFaithfulTranslation({
    sentence,
    paragraph_theme
  });
  const teachingInterpretation = resolveTeachingInterpretation({
    teachingInterpretation: result.teaching_interpretation,
    naturalChineseMeaning: result.natural_chinese_meaning || buildFallbackTeachingInterpretation({
      sentence,
      paragraph_theme,
      paragraph_role
    }),
    faithfulTranslation,
    sentenceFunction,
    coreSkeleton,
    chunkLayers
  });
  const miniCheck = result.mini_check || result.mini_exercise || buildFallbackMiniExercise({
    ...result,
    chunk_breakdown: labeledChunks,
    grammar_points: result.grammar_points.length > 0 ? result.grammar_points : grammarFocus.map((item) => ({
      name: item.phenomenon,
      explanation: [item.function, item.why_it_matters ? `为什么重要：${item.why_it_matters}` : ""].filter(Boolean).join("｜")
    }))
  });

  return {
    ...result,
    evidence_type: evidenceType,
    sentence_function: sentenceFunction,
    core_skeleton: coreSkeleton,
    chunk_layers: chunkLayers,
    grammar_focus: grammarFocus,
    faithful_translation: faithfulTranslation,
    teaching_interpretation: teachingInterpretation,
    natural_chinese_meaning: teachingInterpretation,
    sentence_core: result.sentence_core || renderCoreSkeleton(coreSkeleton) || buildFallbackSentenceCore(sentence),
    chunk_breakdown: labeledChunks,
    grammar_points: result.grammar_points.length > 0 ? result.grammar_points : grammarFocus.map((item) => ({
      name: item.title_zh || item.phenomenon,
      explanation: [
        item.explanation_zh || item.function,
        item.why_it_matters_zh || item.why_it_matters ? `为什么重要：${item.why_it_matters_zh || item.why_it_matters}` : ""
      ].filter(Boolean).join("｜")
    })),
    vocabulary_in_context: result.vocabulary_in_context.length > 0
      ? result.vocabulary_in_context
      : buildFallbackVocabularyInContext(sentence),
    contextual_vocabulary: result.vocabulary_in_context.length > 0
      ? result.vocabulary_in_context
      : buildFallbackVocabularyInContext(sentence),
    misread_points: misreadingTraps,
    misreading_traps: misreadingTraps,
    exam_rewrite_points: examParaphraseRoutes,
    exam_paraphrase_routes: examParaphraseRoutes,
    simplified_english: simplerRewrite,
    simpler_rewrite: simplerRewrite,
    mini_exercise: miniCheck,
    mini_check: miniCheck,
    hierarchy_rebuild: result.hierarchy_rebuild.length > 0 ? result.hierarchy_rebuild : buildFallbackHierarchyRebuild(chunks, coreClause),
    syntactic_variation: result.syntactic_variation || buildFallbackSyntacticVariation(sentence),
    translation: faithfulTranslation,
    main_structure: result.sentence_core || renderCoreSkeleton(coreSkeleton) || buildFallbackSentenceCore(sentence),
    key_terms: result.vocabulary_in_context.length > 0 ? result.vocabulary_in_context : buildFallbackVocabularyInContext(sentence),
    rewrite_example: simplerRewrite
  };
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
    console.warn("[ai/explain-sentence] recovered JSON from wrapped response");
    return fallbackResult;
  }

  console.error("[ai/explain-sentence] model returned invalid JSON", text.slice(0, 200));

  throw new AppError("模型返回格式异常，无法解析为 JSON。", {
    statusCode: 502,
    code: "MODEL_INVALID_JSON"
  });
}

function buildExplainSentenceCacheIdentity(identity = {}) {
  return {
    sentenceID: identity.sentence_id,
    sentenceTextHash: identity.sentence_text_hash
  };
}

function toExplainSentencePublicMeta(meta = {}, overrides = {}) {
  return {
    provider: String(overrides.provider ?? meta.provider ?? ""),
    model: String(overrides.model ?? meta.model ?? ""),
    retry_count: Number(overrides.retry_count ?? meta.retry_count ?? 0),
    used_cache: Boolean(overrides.used_cache ?? meta.used_cache),
    used_fallback: Boolean(overrides.used_fallback ?? meta.used_fallback),
    circuit_state: String(overrides.circuit_state ?? meta.circuit_state ?? "closed")
  };
}

function stripBracketMarkup(value) {
  if (typeof value !== "string") {
    return value;
  }

  return value
    .replace(/\[[A-Za-z_\s-]+:\s*([^\]]+)\]/g, "$1")
    .replace(/\s+/g, " ")
    .trim();
}

function recursivelyStripBracketMarkup(value) {
  if (typeof value === "string") {
    return stripBracketMarkup(value);
  }

  if (Array.isArray(value)) {
    return value.map((item) => recursivelyStripBracketMarkup(item));
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, recursivelyStripBracketMarkup(item)])
    );
  }

  return value;
}

function collectBracketLeaks(value, bucket = []) {
  if (typeof value === "string") {
    if (/\[(subject|predicate|object clause|complement)\s*:/i.test(value)) {
      bucket.push(value);
    }
    return bucket;
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      collectBracketLeaks(item, bucket);
    }
    return bucket;
  }

  if (value && typeof value === "object") {
    for (const item of Object.values(value)) {
      collectBracketLeaks(item, bucket);
    }
  }

  return bucket;
}

function containsTeachingTone(text) {
  const normalized = typeof text === "string" ? text.trim() : "";
  if (!normalized) {
    return false;
  }

  return TRANSLATION_TEACHING_TONE_PATTERNS.some((pattern) => normalized.includes(pattern));
}

function isInterpretationTooSimilar(translation, interpretation) {
  const lhs = normalizedChineseComparisonKey(translation);
  const rhs = normalizedChineseComparisonKey(interpretation);

  if (!lhs || !rhs) {
    return false;
  }

  if (lhs === rhs) {
    return true;
  }

  const minLength = Math.min(lhs.length, rhs.length);
  const maxLength = Math.max(lhs.length, rhs.length);
  if (maxLength === 0) {
    return false;
  }

  if ((lhs.includes(rhs) || rhs.includes(lhs)) && (minLength / maxLength) >= 0.8) {
    return true;
  }

  return false;
}

function normalizeSentenceFunctionObject(rawSentenceFunction, evidenceType) {
  if (rawSentenceFunction && typeof rawSentenceFunction === "object" && !Array.isArray(rawSentenceFunction)) {
    const explanation = purifyChineseDisplayText(
      rawSentenceFunction.explanation_zh || rawSentenceFunction.explanationZh || rawSentenceFunction.title_zh || rawSentenceFunction.titleZh || ""
    );
    if (explanation) {
      return {
        title_zh: "句子定位",
        explanation_zh: explanation
      };
    }
  }

  const explanation = purifyChineseDisplayText(
    typeof rawSentenceFunction === "string"
      ? rawSentenceFunction
      : buildSentenceFunctionFromEvidenceType(evidenceType)
  ) || buildSentenceFunctionFromEvidenceType(evidenceType);

  return {
    title_zh: "句子定位",
    explanation_zh: explanation
  };
}

function buildCoreSkeletonExplanation(coreSkeleton) {
  const rendered = renderCoreSkeleton(coreSkeleton);
  if (rendered) {
    return `先锁定“${rendered}”这一层，全句真正成立的判断就是围绕这条主干展开的。`;
  }

  return "先锁定主语、谓语和核心补足，这一层决定了全句真正成立的判断。";
}

function normalizeChunkRoleZh(role, text) {
  const normalizedRole = String(role || "").trim();
  const lowerRole = normalizedRole.toLowerCase();
  const lowerText = String(text || "").trim().toLowerCase();

  if (normalizedRole.includes("核心") || lowerRole.includes("core")) {
    return "核心信息";
  }
  if (normalizedRole.includes("后置") || lowerRole.includes("post")) {
    return "后置修饰";
  }
  if (normalizedRole.includes("条件") || lowerRole.includes("condition") || lowerText.startsWith("if ")) {
    return "条件框架";
  }
  if (normalizedRole.includes("让步") || lowerRole.includes("concession") || lowerText.startsWith("although ") || lowerText.startsWith("though ")) {
    return "让步框架";
  }
  if (normalizedRole.includes("前置") || normalizedRole.includes("时间") || normalizedRole.includes("框架") || lowerRole.includes("frame") || lowerRole.includes("time")) {
    return "前置框架";
  }

  return "核心信息";
}

function normalizePublicChunkLayers(rawChunkLayers, sentence) {
  return normalizeChunkLayers(rawChunkLayers, sentence).map((item) => {
    const roleZh = normalizeChunkRoleZh(item.role || item.role_zh, item.text);
    const gloss = purifyChineseExplanation(item.gloss_zh || item.gloss)
      || (roleZh === "前置框架"
        ? "这一块先交代阅读框架，不要把它误当成主句判断。"
        : roleZh === "后置修饰"
          ? "这一块回头确认它到底修饰谁。"
          : roleZh === "条件框架"
            ? "这一块在限定判断成立的条件范围。"
            : roleZh === "让步框架"
              ? "这一块先让一步，真正判断通常落在后面的主句。"
              : "这一块承载了句子的核心判断或核心信息。");

    return {
      text: stripBracketMarkup(String(item.text || "")),
      role_zh: roleZh,
      attaches_to: stripBracketMarkup(String(item.attaches_to || "核心信息")),
      gloss_zh: gloss
    };
  });
}

function normalizePublicGrammarFocus(rawGrammarFocus, sentence) {
  return normalizeGrammarFocus(rawGrammarFocus, sentence).map((item) => ({
    title_zh: purifyChineseDisplayText(item.title_zh || item.phenomenon) || "关键语法点",
    explanation_zh: purifyChineseExplanation(item.explanation_zh || item.function) || "这是本句最值得先抓的一层结构。",
    why_it_matters_zh: purifyChineseExplanation(item.why_it_matters_zh || item.why_it_matters) || "如果把这一层挂错，主干和修饰关系就会一起读偏。",
    example_en: typeof item.example_en === "string" ? item.example_en.trim() : ""
  })).slice(0, 3);
}

function normalizePublicExplainSentenceContract(raw, payload) {
  const evidenceType = normalizeEvidenceType(
    firstDefined(raw, ["evidence_type", "sentence_role"]),
    inferEvidenceTypeFromParagraphRole(payload.paragraph_role)
  );
  const coreSkeleton = normalizeCoreSkeleton(firstDefined(raw, ["core_skeleton", "sentence_core"]), payload.sentence);
  const chunkLayers = normalizePublicChunkLayers(firstDefined(raw, ["chunk_layers"]), payload.sentence);
  const grammarFocus = normalizePublicGrammarFocus(firstDefined(raw, ["grammar_focus"]), payload.sentence);
  let faithfulTranslation = purifyChineseExplanation(firstDefined(raw, ["faithful_translation", "translation"]));
  if (!faithfulTranslation || containsTeachingTone(faithfulTranslation) || !isChineseDominantText(faithfulTranslation)) {
    faithfulTranslation = "AI 翻译暂不可用，可稍后重试。";
  }

  let teachingInterpretation = resolveTeachingInterpretation({
    teachingInterpretation: firstDefined(raw, ["teaching_interpretation"]),
    naturalChineseMeaning: firstDefined(raw, ["natural_chinese_meaning"]),
    faithfulTranslation,
    sentenceFunction: typeof raw?.sentence_function === "string" ? raw.sentence_function : "",
    coreSkeleton,
    chunkLayers
  });
  if (!teachingInterpretation || !isChineseDominantText(teachingInterpretation) || isInterpretationTooSimilar(faithfulTranslation, teachingInterpretation)) {
    teachingInterpretation = buildTeachingInterpretationFallback({
      sentenceFunction: typeof raw?.sentence_function === "string" ? raw.sentence_function : buildSentenceFunctionFromEvidenceType(evidenceType),
      coreSkeleton,
      chunkLayers,
      faithfulTranslation
    }) || "AI 精讲暂不可用，当前展示本地解析骨架。";
  }

  const contract = {
    identity: {
      client_request_id: payload.identity.client_request_id,
      document_id: payload.identity.document_id,
      sentence_id: payload.identity.sentence_id,
      segment_id: payload.identity.segment_id,
      sentence_text_hash: payload.identity.sentence_text_hash,
      anchor_label: payload.identity.anchor_label
    },
    original_sentence: payload.sentence.trim(),
    sentence_function: normalizeSentenceFunctionObject(firstDefined(raw, ["sentence_function"]), evidenceType),
    core_skeleton: {
      subject: coreSkeleton.subject || "",
      predicate: coreSkeleton.predicate || "",
      complement_or_object: coreSkeleton.complement_or_object || "",
      explanation_zh: purifyChineseExplanation(raw?.core_skeleton?.explanation_zh) || buildCoreSkeletonExplanation(coreSkeleton)
    },
    faithful_translation: faithfulTranslation,
    teaching_interpretation: teachingInterpretation,
    chunk_layers: chunkLayers,
    grammar_focus: grammarFocus,
    misreading_traps: purifyChineseList(
      firstDefined(raw, ["misreading_traps", "misread_points", "common_misreadings"]),
      4
    ).length > 0
      ? purifyChineseList(firstDefined(raw, ["misreading_traps", "misread_points", "common_misreadings"]), 4)
      : buildFallbackMisreadPoints({
        sentence: payload.sentence,
        chunks: splitSentenceIntoChunks(payload.sentence),
        coreClause: extractCoreClause(payload.sentence, splitSentenceIntoChunks(payload.sentence))
      }),
    exam_paraphrase_routes: purifyChineseList(
      firstDefined(raw, ["exam_paraphrase_routes", "exam_rewrite_points", "exam_paraphrase_points"]),
      4
    ).length > 0
      ? purifyChineseList(firstDefined(raw, ["exam_paraphrase_routes", "exam_rewrite_points", "exam_paraphrase_points"]), 4)
      : buildFallbackExamRewritePoints({
        sentence: payload.sentence,
        paragraph_role: payload.paragraph_role
      }),
    simpler_rewrite: typeof firstDefined(raw, ["simpler_rewrite", "simplified_english", "syntactic_variation"]) === "string"
      ? firstDefined(raw, ["simpler_rewrite", "simplified_english", "syntactic_variation"]).trim()
      : buildFallbackSyntacticVariation(payload.sentence),
    simpler_rewrite_translation: purifyChineseExplanation(firstDefined(raw, ["simpler_rewrite_translation", "rewrite_translation"]))
      || buildRewriteTranslationExplanation({
        simplerRewrite: typeof firstDefined(raw, ["simpler_rewrite", "simplified_english", "syntactic_variation"]) === "string"
          ? firstDefined(raw, ["simpler_rewrite", "simplified_english", "syntactic_variation"]).trim()
          : buildFallbackSyntacticVariation(payload.sentence),
        faithfulTranslation,
        coreSkeleton,
        chunkLayers
      }) || "当前展示的是本地简化改写说明，可在 AI 精讲恢复后查看更完整解释。",
    mini_check: typeof firstDefined(raw, ["mini_check", "mini_exercise"]) === "string"
      ? firstDefined(raw, ["mini_check", "mini_exercise"]).trim()
      : buildFallbackMiniExercise({
        chunk_breakdown: chunkLayers.map((item) => `${item.role_zh}：${item.text}`),
        grammar_points: grammarFocus.map((item) => ({
          name: item.title_zh,
          explanation: `${item.explanation_zh}｜为什么重要：${item.why_it_matters_zh}`
        }))
      })
  };

  return recursivelyStripBracketMarkup(contract);
}

function validateExplainSentenceRawContract(raw) {
  const requiredKeys = [
    "original_sentence",
    "sentence_function",
    "core_skeleton",
    "faithful_translation",
    "teaching_interpretation",
    "chunk_layers",
    "grammar_focus",
    "misreading_traps",
    "exam_paraphrase_routes",
    "simpler_rewrite",
    "simpler_rewrite_translation",
    "mini_check"
  ];

  const reasons = [];
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    reasons.push("模型结果不是对象。");
    return reasons;
  }

  for (const key of requiredKeys) {
    if (!(key in raw)) {
      reasons.push(`缺少字段 ${key}`);
    }
  }

  return reasons;
}

function validateExplainSentencePublicContract(data, payload) {
  const reasons = [];

  const identityFields = [
    "client_request_id",
    "document_id",
    "sentence_id",
    "segment_id",
    "sentence_text_hash",
    "anchor_label"
  ];
  for (const key of identityFields) {
    if (data?.identity?.[key] !== payload.identity[key]) {
      reasons.push(`identity.${key} 未正确回填`);
    }
  }

  if (data?.original_sentence !== payload.sentence.trim()) {
    reasons.push("original_sentence 未固定回填请求句子");
  }

  if (!data?.core_skeleton || typeof data.core_skeleton.explanation_zh !== "string" || !data.core_skeleton.explanation_zh.trim()) {
    reasons.push("core_skeleton.explanation_zh 缺失");
  }

  if (!data?.faithful_translation || !isChineseDominantText(data.faithful_translation) || containsTeachingTone(data.faithful_translation)) {
    reasons.push("faithful_translation 不是合格的中文忠实翻译");
  }

  if (!data?.teaching_interpretation || !isChineseDominantText(data.teaching_interpretation) || isInterpretationTooSimilar(data.faithful_translation, data.teaching_interpretation)) {
    reasons.push("teaching_interpretation 不是合格的教学解读");
  }

  if (!Array.isArray(data?.chunk_layers) || data.chunk_layers.length === 0 || data.chunk_layers.some((item) => !item.text || !item.role_zh || !item.attaches_to || !item.gloss_zh)) {
    reasons.push("chunk_layers 不满足公共契约");
  }

  if (!Array.isArray(data?.grammar_focus) || data.grammar_focus.length === 0 || data.grammar_focus.some((item) => !item.title_zh || !item.explanation_zh || !item.why_it_matters_zh)) {
    reasons.push("grammar_focus 不满足中文主契约");
  }

  const bracketLeaks = collectBracketLeaks(data);
  if (bracketLeaks.length > 0) {
    reasons.push("公共 data 仍存在 bracket 泄露");
  }

  return reasons;
}

function buildExplainSentenceFallbackSkeleton(payload) {
  const chunks = splitSentenceIntoChunks(payload.sentence);
  const coreClause = extractCoreClause(payload.sentence, chunks);
  const coreSkeleton = buildFallbackCoreSkeleton(payload.sentence);
  const chunkLayers = normalizePublicChunkLayers(null, payload.sentence);
  const grammarFocus = normalizePublicGrammarFocus(null, payload.sentence);

  return recursivelyStripBracketMarkup({
    identity: {
      client_request_id: payload.identity.client_request_id,
      document_id: payload.identity.document_id,
      sentence_id: payload.identity.sentence_id,
      segment_id: payload.identity.segment_id,
      sentence_text_hash: payload.identity.sentence_text_hash,
      anchor_label: payload.identity.anchor_label
    },
    original_sentence: payload.sentence.trim(),
    sentence_function: {
      title_zh: "句子定位",
      explanation_zh: buildSentenceFunctionFromEvidenceType(inferEvidenceTypeFromParagraphRole(payload.paragraph_role))
    },
    core_skeleton: {
      subject: coreSkeleton.subject || "",
      predicate: coreSkeleton.predicate || "",
      complement_or_object: coreSkeleton.complement_or_object || "",
      explanation_zh: buildCoreSkeletonExplanation(coreSkeleton)
    },
    faithful_translation: "AI 翻译暂不可用，可稍后重试。",
    teaching_interpretation: "AI 精讲暂不可用，当前展示本地解析骨架。",
    chunk_layers: chunkLayers,
    grammar_focus: grammarFocus,
    misreading_traps: buildFallbackMisreadPoints({
      sentence: payload.sentence,
      chunks,
      coreClause
    }),
    exam_paraphrase_routes: buildFallbackExamRewritePoints({
      sentence: payload.sentence,
      paragraph_role: payload.paragraph_role
    }),
    simpler_rewrite: buildFallbackSyntacticVariation(payload.sentence) || payload.sentence.trim(),
    simpler_rewrite_translation: "当前展示的是本地简化改写说明，可在 AI 精讲恢复后查看更完整解释。",
    mini_check: "重新获取 AI 精讲后可继续检查本句。"
  });
}

function parseExplainSentenceModelResult(aiResult) {
  const text = typeof aiResult?.data?.text === "string"
    ? aiResult.data.text
    : typeof aiResult?.data === "string"
      ? aiResult.data
      : "";

  if (!text) {
    return {
      ok: false,
      kind: "unparseable_json",
      reasons: ["模型没有返回可解析文本。"],
      rawText: ""
    };
  }

  try {
    const parsed = parseModelJson(text);
    return {
      ok: true,
      raw: parsed,
      rawText: text
    };
  } catch {
    return {
      ok: false,
      kind: "unparseable_json",
      reasons: ["模型返回文本无法恢复为 JSON。"],
      rawText: text
    };
  }
}

async function requestExplainSentenceModel(aiClient, payload, requestId) {
  return aiClient.request({
    requestId,
    routeName: "ai/explain-sentence",
    cacheScope: "sentence",
    identity: buildExplainSentenceCacheIdentity(payload.identity),
    payload: {
      prompt: buildProfessorSentencePrompt(payload)
    },
    fallbackFactory: async () => buildExplainSentenceFallbackSkeleton(payload)
  });
}

async function requestExplainSentenceRepair(aiClient, payload, requestId, previousText, reasons) {
  return aiClient.request({
    requestId,
    routeName: "ai/explain-sentence",
    cacheScope: "sentence",
    identity: buildExplainSentenceCacheIdentity(payload.identity),
    payload: {
      prompt: buildProfessorSentenceRepairPrompt({
        payload,
        previousText,
        reasons
      })
    },
    fallbackFactory: async () => buildExplainSentenceFallbackSkeleton(payload)
  });
}

export async function explainSentence(payload, options = {}) {
  const requestId = options.requestId || "";
  const aiClient = options.aiClient || defaultExplainSentenceAIClient;

  console.log("[ai/explain-sentence] calling model", {
    requestId,
    sentenceLength: payload.sentence.length,
    hasContext: Boolean(payload.context?.trim())
  });

  let aiResult;

  try {
    aiResult = await requestExplainSentenceModel(aiClient, payload, requestId);
  } catch (error) {
    if (error?.code === ERROR_CODES.MODEL_CONFIG_MISSING) {
      throw error;
    }

    throw createAIError(ERROR_CODES.INVALID_MODEL_RESPONSE, {
      message: "explain-sentence 模型请求失败。",
      requestId,
      fallbackAvailable: true
    });
  }

  if (aiResult.meta?.used_fallback) {
    return {
      data: recursivelyStripBracketMarkup(aiResult.data),
      meta: toExplainSentencePublicMeta(aiResult.meta)
    };
  }

  const parsedPrimary = parseExplainSentenceModelResult(aiResult);
  if (!parsedPrimary.ok) {
    return {
      data: buildExplainSentenceFallbackSkeleton(payload),
      meta: toExplainSentencePublicMeta(aiResult.meta, {
        used_fallback: true
      })
    };
  }

  let rawContractReasons = validateExplainSentenceRawContract(parsedPrimary.raw);
  let normalizedContract = normalizePublicExplainSentenceContract(parsedPrimary.raw, payload);
  let publicContractReasons = validateExplainSentencePublicContract(normalizedContract, payload);

  if (rawContractReasons.length > 0 || publicContractReasons.length > 0) {
    const repairReasons = [...rawContractReasons, ...publicContractReasons];
    console.warn("[ai/explain-sentence] contract requires repair", repairReasons);

    try {
      const repairedResult = await requestExplainSentenceRepair(
        aiClient,
        payload,
        requestId,
        parsedPrimary.rawText,
        repairReasons
      );

      if (repairedResult.meta?.used_fallback) {
        return {
          data: recursivelyStripBracketMarkup(repairedResult.data),
          meta: toExplainSentencePublicMeta(repairedResult.meta)
        };
      }

      const parsedRepair = parseExplainSentenceModelResult(repairedResult);
      if (!parsedRepair.ok) {
        return {
          data: buildExplainSentenceFallbackSkeleton(payload),
          meta: toExplainSentencePublicMeta(repairedResult.meta, {
            used_fallback: true
          })
        };
      }

      rawContractReasons = validateExplainSentenceRawContract(parsedRepair.raw);
      normalizedContract = normalizePublicExplainSentenceContract(parsedRepair.raw, payload);
      publicContractReasons = validateExplainSentencePublicContract(normalizedContract, payload);

      if (rawContractReasons.length === 0 && publicContractReasons.length === 0) {
        return {
          data: normalizedContract,
          meta: toExplainSentencePublicMeta(repairedResult.meta)
        };
      }
    } catch (error) {
      console.warn("[ai/explain-sentence] repair pass failed", error?.message || error);
    }

    return {
      data: buildExplainSentenceFallbackSkeleton(payload),
      meta: toExplainSentencePublicMeta(aiResult.meta, {
        used_fallback: true
      })
    };
  }

  return {
    data: normalizedContract,
    meta: toExplainSentencePublicMeta(aiResult.meta)
  };
}

export const __testables = {
  buildExplainSentenceFallbackSkeleton,
  normalizePublicExplainSentenceContract,
  validateExplainSentencePublicContract,
  collectBracketLeaks,
  containsTeachingTone,
  normalizeExplainResult,
  normalizeCoreSkeleton,
  normalizeGrammarFocus,
  renderCoreSkeleton,
  localizeGrammarFocusItem
};
