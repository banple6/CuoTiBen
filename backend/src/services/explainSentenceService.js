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
    if (!(key in raw)) {
      throw new AppError(`模型返回格式异常，缺少字段 ${key}。`, {
        statusCode: 502,
        code: "MODEL_INVALID_SCHEMA"
      });
    }
  }
}

function normalizeExplainResult(raw, sourceSentence) {
  ensureExplainResultShape(raw);

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
    vocabulary_in_context: normalizeArray(raw.vocabulary_in_context)
      .map((item) => ({
        term: typeof item?.term === "string" ? item.term.trim() : "",
        meaning: typeof item?.meaning === "string" ? item.meaning.trim() : ""
      }))
      .filter((item) => item.term || item.meaning),
    misread_points: normalizeArray(raw.misread_points)
      .map((item) => typeof item === "string" ? item.trim() : "")
      .filter(Boolean),
    exam_rewrite_points: normalizeArray(raw.exam_rewrite_points)
      .map((item) => typeof item === "string" ? item.trim() : "")
      .filter(Boolean),
    simplified_english: typeof raw.simplified_english === "string" ? raw.simplified_english.trim() : "",
    mini_exercise: typeof raw.mini_exercise === "string" ? raw.mini_exercise.trim() : "",
    hierarchy_rebuild: normalizeArray(raw.hierarchy_rebuild)
      .map((item) => typeof item === "string" ? item.trim() : "")
      .filter(Boolean),
    syntactic_variation: typeof raw.syntactic_variation === "string" ? raw.syntactic_variation.trim() : "",
    translation: typeof raw.natural_chinese_meaning === "string" ? raw.natural_chinese_meaning.trim() : "",
    main_structure: typeof raw.sentence_core === "string" ? raw.sentence_core.trim() : "",
    key_terms: normalizeArray(raw.vocabulary_in_context)
      .map((item) => ({
        term: typeof item?.term === "string" ? item.term.trim() : "",
        meaning: typeof item?.meaning === "string" ? item.meaning.trim() : ""
      }))
      .filter((item) => item.term || item.meaning),
    rewrite_example: typeof raw.simplified_english === "string" ? raw.simplified_english.trim() : ""
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
          content: "你是严格输出 JSON 的英语句子讲解助手。无论任何情况都只返回 JSON 对象。"
        },
        {
          role: "user",
          content: buildExplainSentencePrompt({
            title,
            sentence,
            context,
            paragraph_theme,
            paragraph_role,
            question_prompt
          })
        }
      ]
    });
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
  const parsed = parseModelJson(content);

  return normalizeExplainResult(parsed, sentence);
}
