import test from "node:test";
import assert from "node:assert/strict";

import { createAIError } from "../../src/models/errors.js";
import { executeWithRetry } from "../../src/models/retryPolicy.js";

test("executeWithRetry retries 503 failures and preserves request_id", async () => {
  let attempts = 0;
  const requestIds = [];

  const result = await executeWithRetry(
    async ({ requestId }) => {
      attempts += 1;
      requestIds.push(requestId);

      if (attempts < 3) {
        throw createAIError("UPSTREAM_503", {
          message: "AI 服务暂时繁忙。",
          requestId
        });
      }

      return "success";
    },
    {
      requestId: "req-retry-1",
      maxAttempts: 3,
      wait: async () => {},
      jitter: () => 0
    }
  );

  assert.equal(result.value, "success");
  assert.equal(result.retryCount, 2);
  assert.deepEqual(requestIds, ["req-retry-1", "req-retry-1", "req-retry-1"]);
});

test("executeWithRetry does not retry non-retryable 401 errors", async () => {
  let attempts = 0;

  await assert.rejects(
    () => executeWithRetry(
      async ({ requestId }) => {
        attempts += 1;

        throw createAIError("UPSTREAM_401", {
          message: "鉴权失败。",
          requestId
        });
      },
      {
        requestId: "req-retry-401",
        maxAttempts: 3,
        wait: async () => {},
        jitter: () => 0
      }
    ),
    (error) => error.code === "UPSTREAM_401"
  );

  assert.equal(attempts, 1);
});
