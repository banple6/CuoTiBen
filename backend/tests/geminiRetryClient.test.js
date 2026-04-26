import test from "node:test";
import assert from "node:assert/strict";

import { requestGeminiCompletion } from "../src/services/GeminiRetryClient.js";

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
