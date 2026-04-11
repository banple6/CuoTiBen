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
    "输出字段必须固定为：original_sentence、natural_chinese_meaning、sentence_core、chunk_breakdown、grammar_points、vocabulary_in_context、misread_points、exam_rewrite_points、simplified_english、mini_exercise、hierarchy_rebuild、syntactic_variation。",
    "original_sentence 必须回填原句。",
    "chunk_breakdown 必须是数组，每项是自然断开的语块，不要机械逐词切。",
    "grammar_points 必须是数组，每项字段固定为 name、explanation。",
    "vocabulary_in_context 必须是数组，每项字段固定为 term、meaning，强调本句义，不要词典式堆砌。",
    "misread_points 必须指出学生最容易误判主干、修饰范围、指代、否定或逻辑关系的地方。",
    "exam_rewrite_points 必须指出该句可能如何在阅读理解题中被改写、偷换或设陷阱。",
    "hierarchy_rebuild 用于长难句，按层级重组；简单句返回空数组。",
    "syntactic_variation 用更易懂的句法把原句重写；简单句也尽量给出。",
    "mini_exercise 给一个非常短的小练习；如果不适合，返回空字符串。",
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
    "1. 自然中文义必须是自然汉语，不要逐词对译。",
    "2. sentence_core 必须直接说清主句主干，不要只说'本句讲了什么'。",
    "3. grammar_points 只保留最关键的 1-3 个语法点。",
    "4. exam_rewrite_points 要贴近阅读理解命题，如同义替换、因果偷换、范围缩放、态度弱化。",
    "5. 整体口吻必须像严谨但易懂的英语教授。"
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

function ensureExplainResultShape(raw) {
  const requiredKeys = [
    "original_sentence",
    "natural_chinese_meaning",
    "sentence_core",
    "chunk_breakdown",
    "grammar_points",
    "vocabulary_in_context",
    "misread_points",
    "exam_rewrite_points",
    "simplified_english",
    "mini_exercise",
    "hierarchy_rebuild",
    "syntactic_variation"
  ];

  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new AppError("模型返回格式异常，JSON 顶层不是对象。", {
      statusCode: 502,
      code: "MODEL_INVALID_JSON"
    });
  }

  for (const key of requiredKeys) {
    const aliases = {
      vocabulary_in_context: ["vocabulary_in_context", "contextual_vocabulary"],
      misread_points: ["misread_points", "common_misreadings"],
      exam_rewrite_points: ["exam_rewrite_points", "exam_paraphrase_points"],
      simplified_english: ["simplified_english", "simpler_rewrite"]
    };
    const lookupKeys = aliases[key] || [key];
    const hasKey = lookupKeys.some((lookupKey) => lookupKey in raw);

    if (!hasKey) {
      throw new AppError(`模型返回格式异常，缺少字段 ${key}。`, {
        statusCode: 502,
        code: "MODEL_INVALID_SCHEMA"
      });
    }
  }
}

function normalizeExplainResult(raw, sourceSentence) {
  ensureExplainResultShape(raw);

  const rawVocabulary = firstDefined(raw, ["vocabulary_in_context", "contextual_vocabulary"]);
  const rawMisread = firstDefined(raw, ["misread_points", "common_misreadings"]);
  const rawRewritePoints = firstDefined(raw, ["exam_rewrite_points", "exam_paraphrase_points"]);
  const rawSimplerRewrite = firstDefined(raw, ["simplified_english", "simpler_rewrite"]);

  return {
    original_sentence: typeof raw.original_sentence === "string" && raw.original_sentence.trim()
      ? raw.original_sentence.trim()
      : sourceSentence.trim(),
    natural_chinese_meaning: typeof raw.natural_chinese_meaning === "string" ? raw.natural_chinese_meaning.trim() : "",
    sentence_core: typeof raw.sentence_core === "string" ? raw.sentence_core.trim() : "",
    chunk_breakdown: normalizeArray(raw.chunk_breakdown)
      .map((item) => typeof item === "string" ? item.trim() : "")
      .filter(Boolean),
    grammar_points: normalizeArray(raw.grammar_points)
      .map((item) => ({
        name: typeof item?.name === "string" ? item.name.trim() : "",
        explanation: typeof item?.explanation === "string" ? item.explanation.trim() : ""
      }))
      .filter((item) => item.name || item.explanation),
    vocabulary_in_context: normalizeArray(rawVocabulary)
      .map((item) => ({
        term: typeof item?.term === "string" ? item.term.trim() : "",
        meaning: typeof item?.meaning === "string" ? item.meaning.trim() : ""
      }))
      .filter((item) => item.term || item.meaning),
    misread_points: normalizeArray(rawMisread)
      .map((item) => typeof item === "string" ? item.trim() : "")
      .filter(Boolean),
    exam_rewrite_points: normalizeArray(rawRewritePoints)
      .map((item) => typeof item === "string" ? item.trim() : "")
      .filter(Boolean),
    simplified_english: typeof rawSimplerRewrite === "string" ? rawSimplerRewrite.trim() : "",
    mini_exercise: typeof raw.mini_exercise === "string" ? raw.mini_exercise.trim() : "",
    hierarchy_rebuild: normalizeArray(raw.hierarchy_rebuild)
      .map((item) => typeof item === "string" ? item.trim() : "")
      .filter(Boolean),
    syntactic_variation: typeof raw.syntactic_variation === "string" ? raw.syntactic_variation.trim() : "",
    translation: typeof raw.natural_chinese_meaning === "string" ? raw.natural_chinese_meaning.trim() : "",
    main_structure: typeof raw.sentence_core === "string" ? raw.sentence_core.trim() : "",
    key_terms: normalizeArray(rawVocabulary)
      .map((item) => ({
        term: typeof item?.term === "string" ? item.term.trim() : "",
        meaning: typeof item?.meaning === "string" ? item.meaning.trim() : ""
      }))
      .filter((item) => item.term || item.meaning),
    rewrite_example: typeof rawSimplerRewrite === "string" ? rawSimplerRewrite.trim() : ""
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
      return `主语是 ${components.subject}，谓语核心是 ${components.predicate}，后面的 ${components.complement} 是主句要成立的核心补足信息。`;
    }
    return `主语是 ${components.subject}，谓语核心是 ${components.predicate}。先把这层主干读稳，再补其余修饰。`;
  }

  return `主句最核心的判断落在“${coreClause}”这一块，先把这层主干读清，再回头处理其余修饰。`;
}

function buildFallbackNaturalMeaning({ sentence, paragraph_theme = "", paragraph_role = "" }) {
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

  if (isShallowText(result.natural_chinese_meaning, ["这句话服务于本段", "不要平均翻译", "先抓主干"])) {
    warnings.push("natural_chinese_meaning 仍然像教学提示，不像自然释义");
  }
  if (isShallowText(result.sentence_core, ["本句主要讲", "本句说的是", "这句话主要", "先抓主干"])) {
    warnings.push("sentence_core 仍然不够像主干解析");
  }
  if ((result.chunk_breakdown?.length || 0) <= 1 && sourceSentence.trim().length > 40) {
    warnings.push("chunk_breakdown 不足");
  }
  if ((result.grammar_points?.length || 0) === 0 && sourceSentence.trim().length > 35) {
    warnings.push("grammar_points 缺失");
  }
  if ((result.vocabulary_in_context?.length || 0) === 0 && sourceSentence.trim().length > 30) {
    warnings.push("vocabulary_in_context 缺失");
  }
  if ((result.misread_points || []).every((item) => isShallowText(item, ["注意理解", "注意语法", "需要注意"]))) {
    warnings.push("misread_points 太泛");
  }
  if ((result.exam_rewrite_points || []).every((item) => isShallowText(item, ["可能考同义替换", "常见同义替换"]))) {
    warnings.push("exam_rewrite_points 太泛");
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
    "1. natural_chinese_meaning 要像老师口头解释句意，而不是写成“这句话服务于本段”。",
    "2. sentence_core 必须明确主语、谓语、核心宾补，不能写成“先抓主干”或“本句主要讲”。",
    "3. misread_points 必须写清学生会把哪一层读错。",
    "4. exam_rewrite_points 必须写出命题人会怎么偷换。",
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
  const chunks = result.chunk_breakdown.length > 0 ? result.chunk_breakdown : splitSentenceIntoChunks(sentence);
  const coreClause = extractCoreClause(sentence, chunks);

  return {
    ...result,
    natural_chinese_meaning: result.natural_chinese_meaning || buildFallbackNaturalMeaning({
      sentence,
      paragraph_theme,
      paragraph_role
    }),
    sentence_core: result.sentence_core || buildFallbackSentenceCore(sentence),
    chunk_breakdown: chunks,
    grammar_points: result.grammar_points.length > 0 ? result.grammar_points : [{
      name: "主干优先",
      explanation: `先把“${coreClause}”这一主句读稳，再回头处理其余修饰。`
    }],
    vocabulary_in_context: result.vocabulary_in_context.length > 0
      ? result.vocabulary_in_context
      : buildFallbackVocabularyInContext(sentence),
    misread_points: result.misread_points.length > 0 ? result.misread_points : buildFallbackMisreadPoints({
      sentence,
      chunks,
      coreClause
    }),
    exam_rewrite_points: result.exam_rewrite_points.length > 0 ? result.exam_rewrite_points : buildFallbackExamRewritePoints({
      sentence,
      paragraph_role
    }),
    simplified_english: result.simplified_english || `${coreClause}.`,
    mini_exercise: result.mini_exercise || buildFallbackMiniExercise(result),
    hierarchy_rebuild: result.hierarchy_rebuild.length > 0 ? result.hierarchy_rebuild : buildFallbackHierarchyRebuild(chunks, coreClause),
    syntactic_variation: result.syntactic_variation || buildFallbackSyntacticVariation(sentence),
    translation: result.natural_chinese_meaning || buildFallbackNaturalMeaning({ sentence, paragraph_theme, paragraph_role }),
    main_structure: result.sentence_core || buildFallbackSentenceCore(sentence),
    key_terms: result.vocabulary_in_context,
    rewrite_example: result.simplified_english || `${coreClause}.`
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
  let normalized = normalizeExplainResult(parseModelJson(content), sentence);
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
      const repairedNormalized = normalizeExplainResult(parseModelJson(repairedContent), sentence);
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
