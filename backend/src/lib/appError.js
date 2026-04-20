export class AppError extends Error {
  constructor(message, {
    statusCode = 500,
    code = "INTERNAL_ERROR",
    details,
    requestId = null,
    retryable = false,
    fallbackAvailable = false,
    provider = null,
    model = null,
    routeName = null,
    retryCount = 0,
    usedCache = false,
    usedFallback = false,
    circuitState = null,
    payloadHash = null
  } = {}) {
    super(message);
    this.name = "AppError";
    this.statusCode = statusCode;
    this.code = code;
    this.errorCode = code;
    this.details = details;
    this.requestId = requestId;
    this.retryable = retryable;
    this.fallbackAvailable = fallbackAvailable;
    this.provider = provider;
    this.model = model;
    this.routeName = routeName;
    this.retryCount = retryCount;
    this.usedCache = usedCache;
    this.usedFallback = usedFallback;
    this.circuitState = circuitState;
    this.payloadHash = payloadHash;
  }
}

export function isAppError(error) {
  return error instanceof AppError;
}
