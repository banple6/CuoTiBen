import { AppError } from "../lib/appError.js";

const MAX_TITLE_LENGTH = 300;
const MAX_SENTENCE_LENGTH = 2000;
const MAX_CONTEXT_LENGTH = 12000;
const MAX_PARAGRAPH_THEME_LENGTH = 800;
const MAX_PARAGRAPH_ROLE_LENGTH = 120;
const MAX_QUESTION_PROMPT_LENGTH = 1200;
const MAX_ID_LENGTH = 200;

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
  const paragraphTheme = normalizeOptionalString(body.paragraph_theme, "paragraph_theme", MAX_PARAGRAPH_THEME_LENGTH);
  const paragraphRole = normalizeOptionalString(body.paragraph_role, "paragraph_role", MAX_PARAGRAPH_ROLE_LENGTH);
  const questionPrompt = normalizeOptionalString(body.question_prompt, "question_prompt", MAX_QUESTION_PROMPT_LENGTH);
  const sentenceID = normalizeOptionalString(body.sentence_id, "sentence_id", MAX_ID_LENGTH);
  const sentenceTextHash = normalizeOptionalString(body.sentence_text_hash, "sentence_text_hash", MAX_ID_LENGTH);
  const anchorLabel = normalizeOptionalString(body.anchor_label, "anchor_label", MAX_ID_LENGTH);
  const segmentID = normalizeOptionalString(body.segment_id, "segment_id", MAX_ID_LENGTH);
  const documentID = normalizeOptionalString(body.document_id, "document_id", MAX_ID_LENGTH);
  const clientRequestID = normalizeOptionalString(body.client_request_id, "client_request_id", MAX_ID_LENGTH);

  if (!sentence) {
    throw new AppError("sentence 不能为空。", {
      statusCode: 400,
      code: "INVALID_REQUEST_BODY"
    });
  }

  return {
    title,
    sentence,
    context,
    paragraph_theme: paragraphTheme,
    paragraph_role: paragraphRole,
    question_prompt: questionPrompt,
    sentence_id: sentenceID,
    sentence_text_hash: sentenceTextHash,
    anchor_label: anchorLabel,
    segment_id: segmentID,
    document_id: documentID,
    client_request_id: clientRequestID
  };
}
