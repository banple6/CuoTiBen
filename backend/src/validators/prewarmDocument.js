import { AppError } from "../lib/appError.js";

const ERROR_CODE = "INVALID_PREWARM_DOCUMENT_REQUEST";
const ALLOWED_KINDS = new Set(["passageSentence"]);
const ALLOWED_PARAGRAPH_ROLES = new Set(["passageBody", "body"]);
const BLOCKED_KINDS = new Set([
  "heading",
  "question",
  "option",
  "vocabulary",
  "chineseInstruction",
  "bilingualNote",
  "answerKey",
  "pageHeader",
  "pageFooter"
]);

function fail(message) {
  throw new AppError(message, {
    statusCode: 400,
    code: ERROR_CODE
  });
}

function isObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function normalizeString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeBoolean(value) {
  return typeof value === "boolean" ? value : false;
}

function normalizePageIndex(value) {
  return Number.isInteger(value) && value >= 0 ? value : null;
}

function isEligiblePassageSentence(sentence) {
  const kind = normalizeString(sentence.kind);
  const paragraphRole = normalizeString(sentence.paragraph_role);

  if (sentence.is_passage_sentence === false) return false;
  if (BLOCKED_KINDS.has(kind)) return false;

  return sentence.is_passage_sentence === true
    || ALLOWED_KINDS.has(kind)
    || ALLOWED_PARAGRAPH_ROLES.has(paragraphRole);
}

function normalizeSentence(sentence) {
  if (!isObject(sentence) || !isEligiblePassageSentence(sentence)) return null;

  const sentence_id = normalizeString(sentence.sentence_id);
  const sentence_text_hash = normalizeString(sentence.sentence_text_hash);
  const text = normalizeString(sentence.text);

  if (!sentence_id || !sentence_text_hash || !text) return null;

  return {
    sentence_id,
    sentence_text_hash,
    text,
    context: normalizeString(sentence.context),
    anchor_label: normalizeString(sentence.anchor_label),
    segment_id: normalizeString(sentence.segment_id),
    page_index: normalizePageIndex(sentence.page_index),
    paragraph_role: normalizeString(sentence.paragraph_role),
    paragraph_theme: normalizeString(sentence.paragraph_theme),
    question_prompt: normalizeString(sentence.question_prompt),
    is_current_page: normalizeBoolean(sentence.is_current_page),
    is_key_sentence: normalizeBoolean(sentence.is_key_sentence),
    is_passage_sentence: true
  };
}

export function validatePrewarmDocumentRequest(body) {
  if (!isObject(body)) {
    fail("请求体必须是 JSON 对象。");
  }

  const document_id = normalizeString(body.document_id);
  if (!document_id) {
    fail("document_id 不能为空。");
  }

  const seen = new Set();
  const sentences = [];

  for (const sentence of Array.isArray(body.sentences) ? body.sentences : []) {
    const normalized = normalizeSentence(sentence);
    if (!normalized) continue;

    const dedupeKey = `${normalized.sentence_id}\u001e${normalized.sentence_text_hash}`;
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);
    sentences.push(normalized);
  }

  if (sentences.length === 0) {
    fail("没有可预热的正文句。");
  }

  return {
    document_id,
    title: normalizeString(body.title),
    client_request_id: normalizeString(body.client_request_id),
    sentences
  };
}
