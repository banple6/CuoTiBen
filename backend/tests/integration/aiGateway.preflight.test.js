import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";

import { createApp } from "../../src/app.js";

const ENV_KEYS = [
  "NOVAI_API_KEY",
  "AI_PROVIDER",
  "AI_MODEL",
  "AI_BASE_URL",
  "AI_API_KIND",
  "AI_TIMEOUT_MS",
  "AI_MAX_RETRIES",
  "AI_CIRCUIT_BREAKER_ENABLED",
  "DASHSCOPE_API_KEY",
  "DASHSCOPE_BASE_URL",
  "MODEL_NAME"
];

async function withEnv(patch, callback) {
  const snapshot = new Map(ENV_KEYS.map((key) => [key, process.env[key]]));

  for (const key of ENV_KEYS) {
    const value = patch[key];
    if (value === undefined) {
      delete process.env[key];
      continue;
    }

    process.env[key] = value;
  }

  try {
    return await callback();
  } finally {
    for (const [key, value] of snapshot) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
}

async function withServer(callback) {
  const app = createApp();
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");

  try {
    const address = server.address();
    return await callback(address.port);
  } finally {
    server.close();
    await once(server, "close");
  }
}

test("POST /ai/explain-sentence returns MODEL_CONFIG_MISSING with request_id when AI config is missing", async () => {
  await withEnv({
    NOVAI_API_KEY: "",
    AI_PROVIDER: "claude",
    AI_MODEL: "claude-opus-4-6",
    AI_BASE_URL: "https://example.invalid",
    AI_API_KIND: "anthropic-messages",
    AI_TIMEOUT_MS: "30000",
    AI_MAX_RETRIES: "3",
    AI_CIRCUIT_BREAKER_ENABLED: "true",
    DASHSCOPE_API_KEY: "",
    DASHSCOPE_BASE_URL: "",
    MODEL_NAME: ""
  }, async () => {
    await withServer(async (port) => {
      const response = await fetch(`http://127.0.0.1:${port}/ai/explain-sentence`, {
        method: "POST",
        headers: {
          "content-type": "application/json"
        },
        body: JSON.stringify({
          client_request_id: "client-preflight-1",
          document_id: "document-1",
          sentence_id: "sentence-1",
          segment_id: "segment-1",
          sentence_text_hash: "hash-1",
          anchor_label: "Anchor 1",
          title: "Lesson Title",
          sentence: "This is the target sentence.",
          context: "This is the context."
        })
      });

      assert.equal(response.status, 503);

      const body = await response.json();
      assert.equal(body.success, false);
      assert.equal(body.error_code, "MODEL_CONFIG_MISSING");
      assert.equal(body.retryable, false);
      assert.equal(body.fallback_available, true);
      assert.equal(typeof body.request_id, "string");
      assert.ok(body.request_id.length > 0);
    });
  });
});
