import { AppError, isAppError } from "../lib/appError.js";

export const ERROR_CODES = {
  MODEL_CONFIG_MISSING: "MODEL_CONFIG_MISSING",
  UPSTREAM_401: "UPSTREAM_401",
  UPSTREAM_403: "UPSTREAM_403",
  UPSTREAM_429: "UPSTREAM_429",
  UPSTREAM_500: "UPSTREAM_500",
  UPSTREAM_502: "UPSTREAM_502",
  UPSTREAM_503: "UPSTREAM_503",
  UPSTREAM_504: "UPSTREAM_504",
  UPSTREAM_TIMEOUT: "UPSTREAM_TIMEOUT",
  INVALID_MODEL_RESPONSE: "INVALID_MODEL_RESPONSE",
  PAYLOAD_TOO_LARGE: "PAYLOAD_TOO_LARGE"
};

const DEFAULT_MESSAGES = {
  [ERROR_CODES.MODEL_CONFIG_MISSING]: "AI 配置缺失，无法请求模型。",
  [ERROR_CODES.UPSTREAM_401]: "AI 上游鉴权失败。",
  [ERROR_CODES.UPSTREAM_403]: "AI 上游拒绝访问。",
  [ERROR_CODES.UPSTREAM_429]: "AI 上游限流，请稍后重试。",
  [ERROR_CODES.UPSTREAM_500]: "AI 上游服务异常。",
  [ERROR_CODES.UPSTREAM_502]: "AI 上游网关异常。",
  [ERROR_CODES.UPSTREAM_503]: "AI 服务暂时繁忙。",
  [ERROR_CODES.UPSTREAM_504]: "AI 上游响应超时。",
  [ERROR_CODES.UPSTREAM_TIMEOUT]: "AI 上游请求超时。",
  [ERROR_CODES.INVALID_MODEL_RESPONSE]: "模型返回格式异常。",
  [ERROR_CODES.PAYLOAD_TOO_LARGE]: "请求内容过大，无法发送给模型。"
};

const DEFAULT_STATUS_CODES = {
  [ERROR_CODES.MODEL_CONFIG_MISSING]: 503,
  [ERROR_CODES.UPSTREAM_401]: 401,
  [ERROR_CODES.UPSTREAM_403]: 403,
  [ERROR_CODES.UPSTREAM_429]: 429,
  [ERROR_CODES.UPSTREAM_500]: 500,
  [ERROR_CODES.UPSTREAM_502]: 502,
  [ERROR_CODES.UPSTREAM_503]: 503,
  [ERROR_CODES.UPSTREAM_504]: 504,
  [ERROR_CODES.UPSTREAM_TIMEOUT]: 504,
  [ERROR_CODES.INVALID_MODEL_RESPONSE]: 502,
  [ERROR_CODES.PAYLOAD_TOO_LARGE]: 413
};

export const RETRYABLE_ERROR_CODES = new Set([
  ERROR_CODES.UPSTREAM_429,
  ERROR_CODES.UPSTREAM_500,
  ERROR_CODES.UPSTREAM_502,
  ERROR_CODES.UPSTREAM_503,
  ERROR_CODES.UPSTREAM_504,
  ERROR_CODES.UPSTREAM_TIMEOUT
]);

export const CIRCUIT_BREAKER_ERROR_CODES = new Set([
  ERROR_CODES.UPSTREAM_503,
  ERROR_CODES.UPSTREAM_TIMEOUT
]);

export function mapUpstreamStatusToErrorCode(statusCode) {
  switch (Number(statusCode)) {
    case 401:
      return ERROR_CODES.UPSTREAM_401;
    case 403:
      return ERROR_CODES.UPSTREAM_403;
    case 413:
      return ERROR_CODES.PAYLOAD_TOO_LARGE;
    case 429:
      return ERROR_CODES.UPSTREAM_429;
    case 500:
      return ERROR_CODES.UPSTREAM_500;
    case 502:
      return ERROR_CODES.UPSTREAM_502;
    case 503:
      return ERROR_CODES.UPSTREAM_503;
    case 504:
      return ERROR_CODES.UPSTREAM_504;
    default:
      return ERROR_CODES.UPSTREAM_500;
  }
}

export function isRetryableErrorCode(code) {
  return RETRYABLE_ERROR_CODES.has(code);
}

export function isCircuitBreakerErrorCode(code) {
  return CIRCUIT_BREAKER_ERROR_CODES.has(code);
}

export function createAIError(code, options = {}) {
  const {
    message,
    statusCode,
    details,
    requestId,
    retryable,
    fallbackAvailable,
    provider,
    model,
    routeName,
    retryCount,
    usedCache,
    usedFallback,
    circuitState,
    payloadHash
  } = options;

  return new AppError(message || DEFAULT_MESSAGES[code] || "AI 请求失败。", {
    statusCode: statusCode || DEFAULT_STATUS_CODES[code] || 500,
    code,
    details,
    requestId,
    retryable: retryable ?? isRetryableErrorCode(code),
    fallbackAvailable: fallbackAvailable ?? (code === ERROR_CODES.MODEL_CONFIG_MISSING || isRetryableErrorCode(code)),
    provider,
    model,
    routeName,
    retryCount: retryCount ?? 0,
    usedCache: usedCache ?? false,
    usedFallback: usedFallback ?? false,
    circuitState: circuitState ?? null,
    payloadHash: payloadHash ?? null
  });
}

export function attachAIErrorMetadata(error, metadata = {}) {
  if (!isAppError(error)) {
    return createAIError(ERROR_CODES.UPSTREAM_500, {
      message: error?.message || DEFAULT_MESSAGES[ERROR_CODES.UPSTREAM_500],
      ...metadata
    });
  }

  if (metadata.requestId !== undefined) {
    error.requestId = metadata.requestId;
  }
  if (metadata.retryable !== undefined) {
    error.retryable = metadata.retryable;
  }
  if (metadata.fallbackAvailable !== undefined) {
    error.fallbackAvailable = metadata.fallbackAvailable;
  }
  if (metadata.provider !== undefined) {
    error.provider = metadata.provider;
  }
  if (metadata.model !== undefined) {
    error.model = metadata.model;
  }
  if (metadata.routeName !== undefined) {
    error.routeName = metadata.routeName;
  }
  if (metadata.retryCount !== undefined) {
    error.retryCount = metadata.retryCount;
  }
  if (metadata.usedCache !== undefined) {
    error.usedCache = metadata.usedCache;
  }
  if (metadata.usedFallback !== undefined) {
    error.usedFallback = metadata.usedFallback;
  }
  if (metadata.circuitState !== undefined) {
    error.circuitState = metadata.circuitState;
  }
  if (metadata.payloadHash !== undefined) {
    error.payloadHash = metadata.payloadHash;
  }

  return error;
}
