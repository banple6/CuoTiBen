import { AppError } from "../lib/appError.js";

const MAX_IDENTITY_LENGTH = 200;
const MAX_TITLE_LENGTH = 300;
const MAX_PARAGRAPHS = 4;
const MAX_PARAGRAPH_TEXT_LENGTH = 700;
const MAX_SEGMENT_ID_LENGTH = 120;
const MAX_ANCHOR_LABEL_LENGTH = 120;
const MAX_SOURCE_KIND_LENGTH = 40;
const MAX_BLOCK_ID_LENGTH = 120;
const MAX_BLOCK_TEXT_LENGTH = 2000;

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

function normalizeString(value, fieldName, maxLength, { required = false, missingMessage } = {}) {
  if (value === undefined || value === null) {
    if (required) {
      throw buildInvalidRequestError(missingMessage || `${fieldName} 不能为空。`);
    }
    return "";
  }

  if (typeof value !== "string") {
    throw buildInvalidRequestError(`${fieldName} 必须是字符串。`);
  }

  const trimmed = value.trim();
  if (required && !trimmed) {
    throw buildInvalidRequestError(missingMessage || `${fieldName} 不能为空。`);
  }
  if (trimmed.length > maxLength) {
    throw buildInvalidRequestError(`${fieldName} 长度不能超过 ${maxLength} 个字符。`);
  }

  return trimmed;
}

function normalizeScore(value, fieldName) {
  if (value === undefined || value === null || value === "") {
    return 0.9;
  }

  const score = Number(value);
  if (!Number.isFinite(score) || score < 0 || score > 1) {
    throw buildInvalidRequestError(`${fieldName} 必须是 0 到 1 之间的数字。`);
  }

  return score;
}

function normalizeParagraphs(value) {
  if (!Array.isArray(value)) {
    throw buildInvalidRequestError("paragraphs 必须是数组。");
  }

  if (value.length === 0) {
    throw buildInvalidRequestError("paragraphs 不能为空。");
  }

  if (value.length > MAX_PARAGRAPHS) {
    throw buildInvalidRequestError(`每次最多提交 ${MAX_PARAGRAPHS} 段。`);
  }

  const normalized = value.map((item, index) => {
    if (!ensureObject(item)) {
      throw buildInvalidRequestError(`paragraphs[${index}] 必须是对象。`);
    }

    const text = normalizeString(item.text, `paragraphs[${index}].text`, MAX_PARAGRAPH_TEXT_LENGTH, {
      required: true,
      missingMessage: `paragraphs[${index}].text 不能为空。`
    });

    return {
      segment_id: normalizeString(item.segment_id, `paragraphs[${index}].segment_id`, MAX_SEGMENT_ID_LENGTH, {
        required: true,
        missingMessage: `paragraphs[${index}].segment_id 不能为空。`
      }),
      index: Number.isInteger(item.index) && item.index >= 0 ? item.index : index,
      anchor_label: normalizeString(item.anchor_label, `paragraphs[${index}].anchor_label`, MAX_ANCHOR_LABEL_LENGTH),
      text,
      source_kind: normalizeString(item.source_kind, `paragraphs[${index}].source_kind`, MAX_SOURCE_KIND_LENGTH) || "passage_body",
      hygiene_score: normalizeScore(item.hygiene_score, `paragraphs[${index}].hygiene_score`)
    };
  });

  if (!normalized.some((item) => item.source_kind === "passage_body")) {
    throw buildInvalidRequestError("paragraphs 至少需要包含 1 个 passage_body 段落。");
  }

  return normalized;
}

function normalizeAuxiliaryBlocks(value, fieldName, fallbackSourceKind) {
  if (value === undefined || value === null) {
    return [];
  }

  if (!Array.isArray(value)) {
    throw buildInvalidRequestError(`${fieldName} 必须是数组。`);
  }

  return value.map((item, index) => {
    if (!ensureObject(item)) {
      throw buildInvalidRequestError(`${fieldName}[${index}] 必须是对象。`);
    }

    return {
      block_id: normalizeString(item.block_id, `${fieldName}[${index}].block_id`, MAX_BLOCK_ID_LENGTH) || `${fieldName}_${index + 1}`,
      source_kind: normalizeString(item.source_kind, `${fieldName}[${index}].source_kind`, MAX_SOURCE_KIND_LENGTH) || fallbackSourceKind,
      anchor_label: normalizeString(item.anchor_label, `${fieldName}[${index}].anchor_label`, MAX_ANCHOR_LABEL_LENGTH),
      text: normalizeString(item.text, `${fieldName}[${index}].text`, MAX_BLOCK_TEXT_LENGTH)
    };
  });
}

export function validateAnalyzePassageRequest(body) {
  if (!ensureObject(body)) {
    throw buildInvalidRequestError("请求体必须是 JSON 对象。");
  }

  return {
    identity: {
      client_request_id: normalizeString(body.client_request_id, "client_request_id", MAX_IDENTITY_LENGTH),
      document_id: normalizeString(body.document_id, "document_id", MAX_IDENTITY_LENGTH, {
        required: true,
        missingMessage: "缺少 passage identity 字段。"
      }),
      content_hash: normalizeString(body.content_hash, "content_hash", MAX_IDENTITY_LENGTH, {
        required: true,
        missingMessage: "缺少 passage identity 字段。"
      })
    },
    title: normalizeString(body.title, "title", MAX_TITLE_LENGTH),
    paragraphs: normalizeParagraphs(body.paragraphs),
    question_blocks: normalizeAuxiliaryBlocks(body.question_blocks, "question_blocks", "question"),
    answer_blocks: normalizeAuxiliaryBlocks(body.answer_blocks, "answer_blocks", "answer_key"),
    vocabulary_blocks: normalizeAuxiliaryBlocks(body.vocabulary_blocks, "vocabulary_blocks", "vocabulary_support")
  };
}
