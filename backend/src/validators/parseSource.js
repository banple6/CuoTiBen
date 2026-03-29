import { AppError } from "../lib/appError.js";

const MAX_TITLE_LENGTH = 300;
const MAX_SOURCE_TYPE_LENGTH = 32;
const MAX_RAW_TEXT_LENGTH = 300000;
const MAX_ANCHORS = 400;
const MAX_ANCHOR_TEXT_LENGTH = 40000;

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

function normalizeOptionalInteger(value, fieldName) {
  if (value === undefined || value === null) {
    return null;
  }

  if (!Number.isInteger(value) || value < 0) {
    throw new AppError(`${fieldName} 必须是非负整数。`, {
      statusCode: 400,
      code: "INVALID_REQUEST_BODY"
    });
  }

  return value;
}

function normalizeAnchors(value) {
  if (value === undefined || value === null) {
    return [];
  }

  if (!Array.isArray(value)) {
    throw new AppError("anchors 必须是数组。", {
      statusCode: 400,
      code: "INVALID_REQUEST_BODY"
    });
  }

  if (value.length > MAX_ANCHORS) {
    throw new AppError(`anchors 数量不能超过 ${MAX_ANCHORS}。`, {
      statusCode: 400,
      code: "INVALID_REQUEST_BODY"
    });
  }

  return value.map((anchor, index) => {
    if (!ensureObject(anchor)) {
      throw new AppError(`anchors[${index}] 必须是对象。`, {
        statusCode: 400,
        code: "INVALID_REQUEST_BODY"
      });
    }

    return {
      anchor_id:
        normalizeOptionalString(anchor.anchor_id, `anchors[${index}].anchor_id`, 120) ||
        `anchor_${index + 1}`,
      page: normalizeOptionalInteger(anchor.page, `anchors[${index}].page`),
      label: normalizeOptionalString(anchor.label, `anchors[${index}].label`, 120),
      text: normalizeOptionalString(anchor.text, `anchors[${index}].text`, MAX_ANCHOR_TEXT_LENGTH)
    };
  });
}

export function validateParseSourceRequest(body) {
  if (!ensureObject(body)) {
    throw new AppError("请求体必须是 JSON 对象。", {
      statusCode: 400,
      code: "INVALID_REQUEST_BODY"
    });
  }

  const source_id = normalizeOptionalString(body.source_id, "source_id", 120);
  const title = normalizeOptionalString(body.title, "title", MAX_TITLE_LENGTH);
  const source_type = normalizeOptionalString(body.source_type, "source_type", MAX_SOURCE_TYPE_LENGTH);
  const raw_text = normalizeOptionalString(body.raw_text, "raw_text", MAX_RAW_TEXT_LENGTH);
  const page_count = normalizeOptionalInteger(body.page_count, "page_count");
  const anchors = normalizeAnchors(body.anchors);

  if (!raw_text) {
    throw new AppError("raw_text 不能为空。", {
      statusCode: 400,
      code: "INVALID_REQUEST_BODY"
    });
  }

  return {
    source_id,
    title,
    source_type,
    raw_text,
    page_count,
    anchors
  };
}
