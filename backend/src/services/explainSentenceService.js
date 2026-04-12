import { getDashScopeConfig } from "../config/env.js";
import { AppError } from "../lib/appError.js";
import { getDashScopeClient } from "../lib/dashscope.js";

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
    "输出字段必须固定为：original_sentence、evidence_type、sentence_function、core_skeleton、chunk_layers、grammar_focus、faithful_translation、teaching_interpretation、natural_chinese_meaning、contextual_vocabulary、misreading_traps、exam_paraphrase_routes、simpler_rewrite、mini_check、hierarchy_rebuild、syntactic_variation。",
    "original_sentence 必须回填原句。",
    "evidence_type 必须只能是：background_info / transition_signal / core_claim / supporting_evidence / counter_argument / conclusion_marker 之一。",
    "sentence_function 必须直接说明这句在论证里在做什么，如“核心判断句：作者真正要成立的判断在这里”。",
    "core_skeleton 必须是对象，字段固定为 subject、predicate、complement_or_object。内容必须明确，不允许空泛总结。",
    "chunk_layers 必须是数组，每项都是对象，字段固定为 text、role、attaches_to、gloss。role 要说明它是核心信息、前置框架、后置修饰、补充说明还是让步/条件框架。",
    "grammar_focus 必须是数组，每项都是对象，字段固定为 phenomenon、function、why_it_matters。只保留最关键的 1-3 个。",
    "faithful_translation 必须是忠实翻译：中文自然，但要尽量贴住原句真实意思，不要偷换成教学评论。",
    "teaching_interpretation 必须是教学解读：说明这句话真正承担什么功能、该先抓哪一层、为什么容易读错。",
    "natural_chinese_meaning 用于兼容旧字段，内容与 teaching_interpretation 保持一致。",
    "contextual_vocabulary 必须是数组，每项字段固定为 term、meaning，meaning 必须是本句义。",
    "misreading_traps 必须指出学生最容易误判主干、修饰范围、指代、否定或逻辑关系的地方。",
    "exam_paraphrase_routes 必须指出该句可能如何在阅读理解题中被改写、偷换或设陷阱。",
    "simpler_rewrite 用更简单的英语重写这句话，保持原意。",
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
    "2. faithful_translation 必须是忠实翻译；teaching_interpretation 才负责老师口吻的解释，两者不能混写。",
    "3. core_skeleton 必须直接说清主句主干，不能写成“本句讲了什么”或“先抓主干”。",
    "4. chunk_layers 不是机械切分，必须说明每一块的功能和挂接对象。",
    "5. grammar_focus 只保留最关键的 1-3 个语法点，而且必须说明它在这句里具体起什么作用，以及为什么做题时重要。",
    "6. misreading_traps 必须明确学生最可能把哪一层挂错、读错或范围看错。",
    "7. exam_paraphrase_routes 要贴近阅读理解命题，如同义替换、因果偷换、范围缩放、态度弱化，并尽量给出具体改写路线。",
    "8. mini_check 必须是一个可立即检验理解的小问题，不要空泛提问。",
    "9. 整体口吻必须像严谨但易懂的英语教授。"
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
    ["faithful_translation", "translation", "natural_chinese_meaning"],
    ["teaching_interpretation", "natural_chinese_meaning"],
    ["contextual_vocabulary", "vocabulary_in_context"],
    ["misreading_traps", "misread_points", "common_misreadings"],
    ["exam_paraphrase_routes", "exam_rewrite_points", "exam_paraphrase_points"],
    ["simpler_rewrite", "simplified_english"],
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
  const rawEvidenceType = firstDefined(raw, ["evidence_type", "sentence_role"]);
  const rawFaithfulTranslation = firstDefined(raw, ["faithful_translation", "translation", "natural_chinese_meaning"]);
  const rawTeachingInterpretation = firstDefined(raw, ["teaching_interpretation", "natural_chinese_meaning", "translation"]);
  const evidenceType = normalizeEvidenceType(rawEvidenceType, inferEvidenceTypeFromParagraphRole(paragraph_role));
  const sentenceFunction = typeof raw.sentence_function === "string" && raw.sentence_function.trim()
    ? raw.sentence_function.trim()
    : buildSentenceFunctionFromEvidenceType(evidenceType);
  const coreSkeleton = normalizeCoreSkeleton(firstDefined(raw, ["core_skeleton"]), sourceSentence);
  const chunkLayers = normalizeChunkLayers(firstDefined(raw, ["chunk_layers"]), sourceSentence);
  const grammarFocus = normalizeGrammarFocus(firstDefined(raw, ["grammar_focus"]), sourceSentence);
  const sentenceCore = typeof raw.sentence_core === "string" && raw.sentence_core.trim()
    ? raw.sentence_core.trim()
    : renderCoreSkeleton(coreSkeleton) || buildFallbackSentenceCore(sourceSentence);
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
      name: item.phenomenon,
      explanation: [item.function, item.why_it_matters ? `为什么重要：${item.why_it_matters}` : ""].filter(Boolean).join("｜")
    }));
  const vocabularyInContext = normalizeArray(rawVocabulary)
    .map((item) => ({
      term: typeof item?.term === "string" ? item.term.trim() : "",
      meaning: typeof item?.meaning === "string" ? item.meaning.trim() : ""
    }))
    .filter((item) => item.term || item.meaning);
  const misreadingTraps = normalizeArray(rawMisread)
    .map((item) => typeof item === "string" ? item.trim() : "")
    .filter(Boolean);
  const examParaphraseRoutes = normalizeArray(rawRewritePoints)
    .map((item) => typeof item === "string" ? item.trim() : "")
    .filter(Boolean);
  const simplerRewrite = typeof rawSimplerRewrite === "string" ? rawSimplerRewrite.trim() : "";
  const faithfulTranslation = typeof rawFaithfulTranslation === "string" ? rawFaithfulTranslation.trim() : "";
  const teachingInterpretation = typeof rawTeachingInterpretation === "string" ? rawTeachingInterpretation.trim() : "";
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
    teaching_interpretation: teachingInterpretation || faithfulTranslation,
    natural_chinese_meaning: teachingInterpretation || faithfulTranslation,
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

  const subject = typeof coreSkeleton.subject === "string" ? coreSkeleton.subject.trim() : "";
  const predicate = typeof coreSkeleton.predicate === "string" ? coreSkeleton.predicate.trim() : "";
  const complement = typeof coreSkeleton.complement_or_object === "string"
    ? coreSkeleton.complement_or_object.trim()
    : typeof coreSkeleton.complementOrObject === "string"
      ? coreSkeleton.complementOrObject.trim()
      : "";

  const parts = [];
  if (subject) parts.push(`主语：${subject}`);
  if (predicate) parts.push(`谓语：${predicate}`);
  if (complement) parts.push(`核心补足：${complement}`);
  return parts.join("｜");
}

function normalizeCoreSkeleton(raw, fallbackSentence) {
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    const subject = typeof raw.subject === "string" ? raw.subject.trim() : "";
    const predicate = typeof raw.predicate === "string" ? raw.predicate.trim() : "";
    const complement = typeof raw.complement_or_object === "string"
      ? raw.complement_or_object.trim()
      : typeof raw.complementOrObject === "string"
        ? raw.complementOrObject.trim()
        : typeof raw.object === "string"
          ? raw.object.trim()
          : "";
    if (subject || predicate || complement) {
      return { subject, predicate, complement_or_object: complement };
    }
  }

  return buildFallbackCoreSkeleton(fallbackSentence);
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
      why_it_matters: "修饰对象一旦挂错，学生就会把枝叶误当成主干判断。"
    });
  }

  if (/\bto\s+[a-z]+|\b[a-z]+ing\b/.test(lower)) {
    items.push({
      phenomenon: "非谓语结构",
      function: "这里的 to do / doing 更像压缩信息块，不是另起一个完整谓语。",
      why_it_matters: "如果把非谓语误判成完整谓语，整句主干会被拆坏。"
    });
  }

  if (/\b(am|is|are|was|were|be|been|being)\s+\w+ed\b/.test(lower)) {
    items.push({
      phenomenon: "被动结构",
      function: "被动语态会把真正施动者后移或省略，阅读时要分清动作发出者和承受者。",
      why_it_matters: "如果忽略被动方向，细节题和因果题很容易读反。"
    });
  }

  if (lower.includes("not") || lower.includes("never") || lower.includes("no ")) {
    items.push({
      phenomenon: "否定范围",
      function: "本句带否定色彩，要看清否定落在谓语、比较项还是限定范围上。",
      why_it_matters: "否定范围一旦看错，选项的态度和细节判断会整体反向。"
    });
  }

  if (items.length === 0) {
    items.push({
      phenomenon: "主干优先",
      function: `先把“${coreClause}”这一主句读稳，再回头处理其余修饰层。`,
      why_it_matters: "先主干后修饰，才能避免平均翻译。"
    });
  }

  return items.slice(0, 3);
}

function normalizeGrammarFocus(raw, fallbackSentence) {
  if (Array.isArray(raw)) {
    const items = raw
      .map((item) => ({
        phenomenon: typeof item?.phenomenon === "string" ? item.phenomenon.trim() : "",
        function: typeof item?.function === "string" ? item.function.trim() : "",
        why_it_matters: typeof item?.why_it_matters === "string"
          ? item.why_it_matters.trim()
          : typeof item?.whyItMatters === "string"
            ? item.whyItMatters.trim()
            : ""
      }))
      .filter((item) => item.phenomenon || item.function || item.why_it_matters);
    if (items.length > 0) {
      return items.slice(0, 3);
    }
  }

  return buildFallbackGrammarFocus(fallbackSentence);
}

function buildFallbackFaithfulTranslation({ sentence, paragraph_theme = "" }) {
  const chunks = splitSentenceIntoChunks(sentence);
  const coreClause = extractCoreClause(sentence, chunks);
  const focus = coreClause.replace(/\s+/g, " ").trim();

  if (paragraph_theme.trim()) {
    return `句子的基本意思是：围绕“${paragraph_theme.trim()}”这个话题，真正成立的内容落在“${focus}”这一层。`;
  }

  if (chunks.length >= 2) {
    const prefix = chunks[0] === coreClause ? "" : `前面先交代“${chunks[0]}”，`;
    return `句子的基本意思是：${prefix}真正要表达的是“${focus}”。`;
  }

  return `句子的基本意思是：${focus}。`;
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

  return warnings;
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
    "4. core_skeleton 必须明确 subject、predicate、complement_or_object，不能再写空泛总结。",
    "5. chunk_layers 每一项都要标明 role、attaches_to、gloss，至少要有一项 role 是“核心信息”。",
    "6. grammar_focus 必须说清结构功能和为什么重要，不能只贴标签。",
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
  const faithfulTranslation = result.faithful_translation || result.translation || buildFallbackFaithfulTranslation({
    sentence,
    paragraph_theme
  });
  const teachingInterpretation = result.teaching_interpretation || result.natural_chinese_meaning || buildFallbackTeachingInterpretation({
    sentence,
    paragraph_theme,
    paragraph_role
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
      name: item.phenomenon,
      explanation: [item.function, item.why_it_matters ? `为什么重要：${item.why_it_matters}` : ""].filter(Boolean).join("｜")
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

export async function explainSentence({
  title = "",
  sentence,
  context = "",
  paragraph_theme = "",
  paragraph_role = "",
  question_prompt = ""
}) {
  const client = getDashScopeClient();
  const { modelName } = getDashScopeConfig();

  if (!client) {
    throw new AppError("DASHSCOPE_API_KEY 或 DASHSCOPE_BASE_URL 未配置。", {
      statusCode: 500,
      code: "MODEL_CONFIG_MISSING"
    });
  }

  console.log("[ai/explain-sentence] calling model", {
    modelName,
    sentenceLength: sentence.length,
    hasContext: Boolean(context.trim())
  });

  const requestModel = async (prompt) => {
    return client.chat.completions.create({
      model: modelName,
      temperature: 0.2,
      response_format: {
        type: "json_object"
      },
      messages: [
        {
          role: "system",
          content: "你是严格输出 JSON 的英语句子讲解助手。无论任何情况都只返回 JSON 对象。"
        },
        {
          role: "user",
          content: prompt
        }
      ]
    });
  };

  let completion;

  try {
    completion = await requestModel(buildExplainSentencePrompt({
      title,
      sentence,
      context,
      paragraph_theme,
      paragraph_role,
      question_prompt
    }));
  } catch (error) {
    const status = typeof error?.status === "number" ? error.status : undefined;
    const upstreamMessage = typeof error?.message === "string" ? error.message : "";

    console.error("[ai/explain-sentence] model request failed", {
      status,
      upstreamMessage
    });

    throw new AppError("调用大模型接口失败。", {
      statusCode: 502,
      code: "MODEL_REQUEST_FAILED"
    });
  }

  const content = completion.choices?.[0]?.message?.content;
  let normalized = normalizeExplainResult(parseModelJson(content), sentence, paragraph_role);
  let qualityWarnings = validateExplainResultQuality(normalized, sentence);

  if (qualityWarnings.length >= 2) {
    console.warn("[ai/explain-sentence] quality warnings after first pass", qualityWarnings);

    try {
      const repairedCompletion = await requestModel(buildExplainSentenceRepairPrompt({
        title,
        sentence,
        context,
        paragraph_theme,
        paragraph_role,
        question_prompt,
        previousResult: normalized,
        warnings: qualityWarnings
      }));
      const repairedContent = repairedCompletion.choices?.[0]?.message?.content;
      const repairedNormalized = normalizeExplainResult(parseModelJson(repairedContent), sentence, paragraph_role);
      const repairedWarnings = validateExplainResultQuality(repairedNormalized, sentence);

      if (repairedWarnings.length <= qualityWarnings.length) {
        normalized = repairedNormalized;
        qualityWarnings = repairedWarnings;
      }
    } catch (error) {
      console.warn("[ai/explain-sentence] repair pass failed", error?.message || error);
    }
  }

  if (qualityWarnings.length > 0) {
    console.warn("[ai/explain-sentence] final quality warnings", qualityWarnings);
  }

  return enrichExplainResult(normalized, {
    sentence,
    paragraph_theme,
    paragraph_role
  });
}
