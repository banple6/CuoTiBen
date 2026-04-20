import { AppError, isAppError } from "../lib/appError.js";

function buildErrorPayload(error, requestId) {
  if (isAppError(error)) {
    return {
      statusCode: error.statusCode,
      body: {
        success: false,
        error_code: error.code,
        message: error.message,
        request_id: error.requestId || requestId || null,
        retryable: Boolean(error.retryable),
        fallback_available: Boolean(error.fallbackAvailable)
      }
    };
  }

  if (error instanceof SyntaxError && "body" in error) {
    return {
      statusCode: 400,
      body: {
        success: false,
        error_code: "INVALID_JSON_BODY",
        message: "请求体不是合法 JSON。",
        request_id: requestId || null,
        retryable: false,
        fallback_available: false
      }
    };
  }

  console.error("[backend] unhandled error", error);

  return {
    statusCode: 500,
    body: {
      success: false,
      error_code: "INTERNAL_ERROR",
      message: "服务器内部错误。",
      request_id: requestId || null,
      retryable: false,
      fallback_available: false
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
      message: error.message,
      requestId: error.requestId || req.requestId || null,
      errorCode: error.code,
      retryCount: error.retryCount || 0,
      usedCache: Boolean(error.usedCache),
      usedFallback: Boolean(error.usedFallback),
      circuitState: error.circuitState || null
    });
  }

  const { statusCode, body } = buildErrorPayload(error, req.requestId);
  return res.status(statusCode).json(body);
}
