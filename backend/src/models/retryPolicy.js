import { isRetryableErrorCode } from "./errors.js";

function defaultWait(delayMs) {
  return new Promise((resolve) => {
    setTimeout(resolve, delayMs);
  });
}

function defaultJitter(delayMs) {
  return Math.floor(Math.random() * Math.max(1, Math.floor(delayMs * 0.2)));
}

export async function executeWithRetry(operation, options = {}) {
  const {
    requestId,
    maxAttempts = 3,
    baseDelayMs = 50,
    wait = defaultWait,
    jitter = defaultJitter,
    shouldRetry = (error) => isRetryableErrorCode(error?.code),
    onFailedAttempt
  } = options;

  let attempts = 0;

  while (attempts < maxAttempts) {
    try {
      const value = await operation({
        attempt: attempts + 1,
        requestId
      });

      return {
        value,
        retryCount: attempts
      };
    } catch (error) {
      attempts += 1;
      const retryCount = Math.max(0, attempts - 1);
      error.retryCount = retryCount;

      const canRetry = attempts < maxAttempts && shouldRetry(error);

      if (typeof onFailedAttempt === "function") {
        await onFailedAttempt({
          error,
          attempt: attempts,
          requestId,
          willRetry: canRetry
        });
      }

      if (!canRetry) {
        throw error;
      }

      const delayMs = (baseDelayMs * (2 ** retryCount)) + jitter(baseDelayMs * (2 ** retryCount));
      await wait(delayMs);
    }
  }

  throw new Error("Retry policy exhausted unexpectedly.");
}
