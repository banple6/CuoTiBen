import { AppError } from "../lib/appError.js";

const MAX_TITLE_LENGTH = 300;
const MAX_SENTENCE_LENGTH = 2000;
const MAX_CONTEXT_LENGTH = 12000;

function ensureObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function normalizeOptionalString(value, fieldName, maxLength) {
  if (value === undefined || value === null) {
    return "";
  }

  if (typeof value !== "string") {
    throw new AppError(`${fieldName} 必须是字符串。`, {
      statusCode: 400,
      code: "INVALID_REQUEST_BODY"
    });
  }

  const trimmed = value.trim();
  if (trimmed.length > maxLength) {
    throw new AppError(`${fieldName} 长度不能超过 ${maxLength} 个字符。`, {
      statusCode: 400,
      code: "INVALID_REQUEST_BODY"
    });
  }

  return trimmed;
}

export function validateExplainSentenceRequest(body) {
  if (!ensureObject(body)) {
    throw new AppError("请求体必须是 JSON 对象。", {
      statusCode: 400,
      code: "INVALID_REQUEST_BODY"
    });
  }

  const title = normalizeOptionalString(body.title, "title", MAX_TITLE_LENGTH);
  const sentence = normalizeOptionalString(body.sentence, "sentence", MAX_SENTENCE_LENGTH);
  const context = normalizeOptionalString(body.context, "context", MAX_CONTEXT_LENGTH);

  if (!sentence) {
    throw new AppError("sentence 不能为空。", {
      statusCode: 400,
      code: "INVALID_REQUEST_BODY"
    });
  }

  return {
    title,
    sentence,
    context
  };
}
