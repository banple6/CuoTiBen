import test from "node:test";
import assert from "node:assert/strict";

import { requestGeminiCompletion } from "../src/services/GeminiRetryClient.js";
import { AppError } from "../src/lib/appError.js";

test("requestGeminiCompletion retries provider invalid-response errors before falling back", async () => {
  let attempts = 0;
  const breakerKey = `test-invalid-response-${Date.now()}-${Math.random()}`;

  const result = await requestGeminiCompletion({
    requestID: "test-request",
    breakerKey,
    timeoutMs: 1_000,
    invoke: async () => {
      attempts += 1;
      if (attempts === 1) {
        const error = new Error("Invalid response body while trying to fetch completion");
        error.status = 200;
        throw error;
      }
      return { choices: [{ message: { content: "{}" } }] };
    }
  });

  assert.equal(attempts, 2);
  assert.equal(result.retryCount, 1);
  assert.deepEqual(result.completion, { choices: [{ message: { content: "{}" } }] });
});

test("requestGeminiCompletion classifies provider quota errors distinctly", async () => {
  const breakerKey = `test-quota-${Date.now()}-${Math.random()}`;

  await assert.rejects(
    requestGeminiCompletion({
      requestID: "test-quota-request",
      breakerKey,
      timeoutMs: 1_000,
      invoke: async () => {
        const error = new Error("403 用户额度不足, 剩余额度: ¥-0.091290");
        error.status = 403;
        throw error;
      }
    }),
    (error) => {
      assert.equal(error.code, "MODEL_QUOTA_EXHAUSTED");
      assert.equal(error.statusCode, 402);
      assert.equal(error.retryable, false);
      assert.equal(error.fallbackAvailable, true);
      return true;
    }
  );
});

test("requestGeminiCompletion classifies provider auth errors distinctly", async () => {
  const breakerKey = `test-auth-${Date.now()}-${Math.random()}`;

  await assert.rejects(
    requestGeminiCompletion({
      requestID: "test-auth-request",
      breakerKey,
      timeoutMs: 1_000,
      invoke: async () => {
        const error = new Error("401 invalid api key");
        error.status = 401;
        throw error;
      }
    }),
    (error) => {
      assert.equal(error.code, "MODEL_AUTH_FAILED");
      assert.equal(error.statusCode, 401);
      assert.equal(error.retryable, false);
      assert.equal(error.fallbackAvailable, true);
      return true;
    }
  );
});

test("requestGeminiCompletion honors maxAttempts for retryable upstream stalls", async () => {
  let attempts = 0;
  const breakerKey = `test-max-attempts-${Date.now()}-${Math.random()}`;

  await assert.rejects(
    requestGeminiCompletion({
      requestID: "test-max-attempts-request",
      breakerKey,
      timeoutMs: 1_000,
      maxAttempts: 1,
      invoke: async () => {
        attempts += 1;
        throw new AppError("AI 服务请求超时。", {
          statusCode: 504,
          code: "GEMINI_TIMEOUT",
          retryable: true,
          fallbackAvailable: true
        });
      }
    }),
    (error) => {
      assert.equal(error.code, "GEMINI_TIMEOUT");
      assert.equal(error.statusCode, 504);
      assert.equal(error.retryable, true);
      assert.equal(error.retryCount, 1);
      return true;
    }
  );
  assert.equal(attempts, 1);
});
