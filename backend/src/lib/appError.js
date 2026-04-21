export class AppError extends Error {
  constructor(
    message,
    {
      statusCode = 500,
      code = "INTERNAL_ERROR",
      details,
      retryable = false,
      fallbackAvailable = false,
      requestID,
      usedCache = false,
      usedFallback = false,
      retryCount = 0
    } = {}
  ) {
    super(message);
    this.name = "AppError";
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
    this.retryable = retryable;
    this.fallbackAvailable = fallbackAvailable;
    this.requestID = requestID;
    this.usedCache = usedCache;
    this.usedFallback = usedFallback;
    this.retryCount = retryCount;
  }
}

export function isAppError(error) {
  return error instanceof AppError;
}
