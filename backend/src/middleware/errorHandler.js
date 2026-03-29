import { AppError, isAppError } from "../lib/appError.js";

function buildErrorPayload(error) {
  if (isAppError(error)) {
    return {
      statusCode: error.statusCode,
      body: {
        success: false,
        error: error.message
      }
    };
  }

  if (error instanceof SyntaxError && "body" in error) {
    return {
      statusCode: 400,
      body: {
        success: false,
        error: "请求体不是合法 JSON。"
      }
    };
  }

  console.error("[backend] unhandled error", error);

  return {
    statusCode: 500,
    body: {
      success: false,
      error: "服务器内部错误。"
    }
  };
}

export function notFoundHandler(_req, _res, next) {
  next(new AppError("接口不存在。", { statusCode: 404, code: "NOT_FOUND" }));
}

export function errorHandler(error, req, res, next) {
  if (res.headersSent) {
    return next(error);
  }

  if (isAppError(error)) {
    console.warn("[backend] request failed", {
      method: req.method,
      url: req.originalUrl,
      statusCode: error.statusCode,
      message: error.message
    });
  }

  const { statusCode, body } = buildErrorPayload(error);
  return res.status(statusCode).json(body);
}
