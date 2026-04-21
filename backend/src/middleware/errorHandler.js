import { AppError, isAppError } from "../lib/appError.js";

function buildErrorPayload(error) {
  if (isAppError(error)) {
    return {
      statusCode: error.statusCode,
      body: {
        success: false,
        error_code: error.code,
        message: error.message,
        request_id: error.requestID,
        retryable: Boolean(error.retryable),
        fallback_available: Boolean(error.fallbackAvailable),
        used_cache: Boolean(error.usedCache),
        used_fallback: Boolean(error.usedFallback),
        retry_count: Number(error.retryCount || 0)
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
        request_id: undefined,
        retryable: false,
        fallback_available: false,
        used_cache: false,
        used_fallback: false,
        retry_count: 0
      }
    };
  }

  console.error("[backend] unhandled error", error);

  return {
    statusCode: 500,
    body: {
      success: false,
      error_code: "BACKEND_ROUTE_ERROR",
      message: "服务器内部错误。",
      request_id: error?.requestID,
      retryable: false,
      fallback_available: false,
      used_cache: false,
      used_fallback: false,
      retry_count: 0
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

  if (isAppError(error) && !error.requestID && req.requestID) {
    error.requestID = req.requestID;
  }

  if (isAppError(error)) {
    console.warn("[backend] request failed", {
      method: req.method,
      url: req.originalUrl,
      statusCode: error.statusCode,
      message: error.message,
      errorCode: error.code,
      requestID: error.requestID ?? req.requestID
    });
  }

  const { statusCode, body } = buildErrorPayload(error);
  return res.status(statusCode).json(body);
}
