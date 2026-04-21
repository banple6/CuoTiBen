import { AppError } from "../lib/appError.js";

const MAX_IDENTITY_LENGTH = 200;
const MAX_TITLE_LENGTH = 300;
const MAX_SENTENCE_LENGTH = 2000;
const MAX_CONTEXT_LENGTH = 12000;
const MAX_PARAGRAPH_THEME_LENGTH = 800;
const MAX_PARAGRAPH_ROLE_LENGTH = 120;
const MAX_QUESTION_PROMPT_LENGTH = 1200;

function ensureObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function buildInvalidRequestError(message) {
  return new AppError(message, {
    statusCode: 400,
    code: "INVALID_REQUEST",
    fallbackAvailable: true
  });
}

function normalizeString(value, fieldName, maxLength, { required = false } = {}) {
  if (value === undefined || value === null) {
    if (required) {
      throw buildInvalidRequestError("缺少 sentence identity 字段。");
    }
    return "";
  }

  if (typeof value !== "string") {
    throw buildInvalidRequestError(`${fieldName} 必须是字符串。`);
  }

  const trimmed = value.trim();
  if (required && !trimmed) {
    throw buildInvalidRequestError("缺少 sentence identity 字段。");
  }
  if (trimmed.length > maxLength) {
    throw buildInvalidRequestError(`${fieldName} 长度不能超过 ${maxLength} 个字符。`);
  }

  return trimmed;
}

export function validateExplainSentenceRequest(body) {
  if (!ensureObject(body)) {
    throw buildInvalidRequestError("请求体必须是 JSON 对象。");
  }

  const title = normalizeString(body.title, "title", MAX_TITLE_LENGTH);
  const sentence = normalizeString(body.sentence, "sentence", MAX_SENTENCE_LENGTH);
  const context = normalizeString(body.context, "context", MAX_CONTEXT_LENGTH);
  const paragraphTheme = normalizeString(body.paragraph_theme, "paragraph_theme", MAX_PARAGRAPH_THEME_LENGTH);
  const paragraphRole = normalizeString(body.paragraph_role, "paragraph_role", MAX_PARAGRAPH_ROLE_LENGTH);
  const questionPrompt = normalizeString(body.question_prompt, "question_prompt", MAX_QUESTION_PROMPT_LENGTH);

  if (!sentence) {
    throw buildInvalidRequestError("sentence 不能为空。");
  }

  return {
    identity: {
      client_request_id: normalizeString(body.client_request_id, "client_request_id", MAX_IDENTITY_LENGTH, { required: true }),
      document_id: normalizeString(body.document_id, "document_id", MAX_IDENTITY_LENGTH, { required: true }),
      sentence_id: normalizeString(body.sentence_id, "sentence_id", MAX_IDENTITY_LENGTH, { required: true }),
      segment_id: normalizeString(body.segment_id, "segment_id", MAX_IDENTITY_LENGTH, { required: true }),
      sentence_text_hash: normalizeString(body.sentence_text_hash, "sentence_text_hash", MAX_IDENTITY_LENGTH, { required: true }),
      anchor_label: normalizeString(body.anchor_label, "anchor_label", MAX_IDENTITY_LENGTH, { required: true })
    },
    title,
    sentence,
    context,
    paragraph_theme: paragraphTheme,
    paragraph_role: paragraphRole,
    question_prompt: questionPrompt
  };
}
