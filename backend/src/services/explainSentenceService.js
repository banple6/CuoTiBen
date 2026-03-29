import { getDashScopeConfig } from "../config/env.js";
import { AppError } from "../lib/appError.js";
import { getDashScopeClient } from "../lib/dashscope.js";

export function buildExplainSentencePrompt({ title, sentence, context }) {
  const safeTitle = title?.trim() || "未提供";
  const safeContext = context?.trim() || "未提供";

  return [
    "你是英语句子讲解助手。",
    "你必须只输出一个合法 JSON 对象。",
    "不要输出 Markdown。",
    "不要输出 ```json 代码块。",
    "不要输出任何额外解释、前后缀、标题或自然语言。",
    "请使用中文讲解，但保留必要的英语原句片段。",
    "JSON 顶层必须是对象。",
    "输出字段必须固定为：translation、main_structure、grammar_points、key_terms、rewrite_example。",
    "grammar_points 必须是数组，每项字段固定为 name、explanation。",
    "key_terms 必须是数组，每项字段固定为 term、meaning。",
    "如果信息不足，也必须返回空字符串或空数组，不能缺字段。",
    "",
    `资料标题: ${safeTitle}`,
    `句子: ${sentence.trim()}`,
    `上下文: ${safeContext}`
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
    "translation",
    "main_structure",
    "grammar_points",
    "key_terms",
    "rewrite_example"
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

function normalizeExplainResult(raw) {
  ensureExplainResultShape(raw);

  return {
    translation: typeof raw.translation === "string" ? raw.translation.trim() : "",
    main_structure: typeof raw.main_structure === "string" ? raw.main_structure.trim() : "",
    grammar_points: normalizeArray(raw.grammar_points)
      .map((item) => ({
        name: typeof item?.name === "string" ? item.name.trim() : "",
        explanation: typeof item?.explanation === "string" ? item.explanation.trim() : ""
      }))
      .filter((item) => item.name || item.explanation),
    key_terms: normalizeArray(raw.key_terms)
      .map((item) => ({
        term: typeof item?.term === "string" ? item.term.trim() : "",
        meaning: typeof item?.meaning === "string" ? item.meaning.trim() : ""
      }))
      .filter((item) => item.term || item.meaning),
    rewrite_example: typeof raw.rewrite_example === "string" ? raw.rewrite_example.trim() : ""
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

export async function explainSentence({ title = "", sentence, context = "" }) {
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
          content: buildExplainSentencePrompt({ title, sentence, context })
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

  return normalizeExplainResult(parsed);
}
