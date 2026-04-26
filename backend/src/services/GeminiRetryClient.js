import { AppError } from "../lib/appError.js";
import { geminiCircuitBreaker } from "./GeminiCircuitBreaker.js";

const RETRYABLE_STATUS = new Set([429, 500, 502, 503, 504]);
const INVALID_RESPONSE_PATTERNS = [
  /invalid response/i,
  /invalid response body/i,
  /unexpected token/i,
  /failed to parse/i,
  /malformed/i,
  /choices/i,
  /completion/i
];

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function withTimeout(promiseFactory, timeoutMs) {
  let timer;
  const timeoutPromise = new Promise((_, reject) => {
    timer = setTimeout(() => {
      reject(new AppError("AI 服务暂时繁忙，已展示本地解析骨架，可稍后重试。", {
        statusCode: 504,
        code: "GEMINI_TIMEOUT",
        retryable: true,
        fallbackAvailable: true
      }));
    }, timeoutMs);
  });

  return Promise.race([
    promiseFactory().finally(() => clearTimeout(timer)),
    timeoutPromise
  ]);
}

function classifyError(error) {
  if (error instanceof AppError) {
    return {
      statusCode: error.statusCode,
      code: error.code,
      message: error.message,
      retryable: Boolean(error.retryable)
    };
  }

  const status = typeof error?.status === "number" ? error.status : 502;
  if (status === 429) {
    return {
      statusCode: 429,
      code: "GEMINI_RATE_LIMIT",
      message: "AI 服务暂时繁忙，已展示本地解析骨架，可稍后重试。",
      retryable: true
    };
  }
  if (status === 503) {
    return {
      statusCode: 503,
      code: "GEMINI_UPSTREAM_503",
      message: "AI 服务暂时繁忙，已展示本地解析骨架，可稍后重试。",
      retryable: true
    };
  }
  if (RETRYABLE_STATUS.has(status)) {
    return {
      statusCode: status,
      code: "GEMINI_UPSTREAM_503",
      message: "AI 服务暂时繁忙，已展示本地解析骨架，可稍后重试。",
      retryable: true
    };
  }
  const message = typeof error?.message === "string" ? error.message.trim() : "";
  const looksLikeInvalidProviderResponse = status === 200
    || INVALID_RESPONSE_PATTERNS.some((pattern) => pattern.test(message));
  if (looksLikeInvalidProviderResponse) {
    return {
      statusCode: 502,
      code: "GEMINI_INVALID_RESPONSE",
      message: message || "AI 返回异常响应。",
      retryable: true
    };
  }
  return {
    statusCode: 502,
    code: "GEMINI_INVALID_RESPONSE",
    message: message || "AI 返回异常响应。",
    retryable: false
  };
}

function backoffMs(attempt) {
  const base = 450 * (2 ** attempt);
  const jitter = Math.floor(Math.random() * 220);
  return base + jitter;
}

export async function requestGeminiCompletion({
  requestID,
  breakerKey,
  timeoutMs,
  invoke
}) {
  const breaker = geminiCircuitBreaker.beforeRequest(breakerKey);
  if (!breaker.allowed) {
    throw new AppError("AI 服务暂时繁忙，已展示本地解析骨架，可稍后重试。", {
      statusCode: 503,
      code: "GEMINI_UPSTREAM_503",
      retryable: true,
      fallbackAvailable: true,
      requestID,
      retryCount: 0
    });
  }

  let lastClassified = null;

  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      const completion = await withTimeout(() => invoke(), timeoutMs);
      geminiCircuitBreaker.recordSuccess(breakerKey);
      return {
        completion,
        retryCount: attempt
      };
    } catch (error) {
      const classified = classifyError(error);
      lastClassified = classified;
      geminiCircuitBreaker.recordFailure(breakerKey);

      if (classified.retryable && attempt < 2) {
        await sleep(backoffMs(attempt));
        continue;
      }

      throw new AppError(classified.message, {
        statusCode: classified.statusCode,
        code: classified.code,
        retryable: classified.retryable,
        fallbackAvailable: true,
        requestID,
        retryCount: attempt + 1
      });
    }
  }

  throw new AppError(lastClassified?.message || "AI 服务暂时不可用。", {
    statusCode: lastClassified?.statusCode || 503,
    code: lastClassified?.code || "GEMINI_UPSTREAM_503",
    retryable: Boolean(lastClassified?.retryable),
    fallbackAvailable: true,
    requestID,
    retryCount: 3
  });
}
