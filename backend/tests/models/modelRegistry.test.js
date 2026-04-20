import test from "node:test";
import assert from "node:assert/strict";

import { AppError } from "../../src/lib/appError.js";
import { createModelRegistry } from "../../src/models/modelRegistry.js";

const AI_ENV_KEYS = [
  "NOVAI_API_KEY",
  "AI_PROVIDER",
  "AI_MODEL",
  "AI_BASE_URL",
  "AI_API_KIND",
  "AI_TIMEOUT_MS",
  "AI_MAX_RETRIES",
  "AI_CIRCUIT_BREAKER_ENABLED"
];

async function withEnv(patch, callback) {
  const snapshot = new Map(AI_ENV_KEYS.map((key) => [key, process.env[key]]));

  for (const key of AI_ENV_KEYS) {
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

test("createModelRegistry preflight throws MODEL_CONFIG_MISSING when NOVAI_API_KEY is missing", async () => {
  await withEnv({
    NOVAI_API_KEY: "",
    AI_PROVIDER: "claude",
    AI_MODEL: "claude-opus-4-6",
    AI_BASE_URL: "https://example.invalid",
    AI_API_KIND: "anthropic-messages",
    AI_TIMEOUT_MS: "30000",
    AI_MAX_RETRIES: "3",
    AI_CIRCUIT_BREAKER_ENABLED: "true"
  }, async () => {
    const registry = createModelRegistry();

    assert.throws(
      () => registry.preflight(),
      (error) => error instanceof AppError && error.code === "MODEL_CONFIG_MISSING"
    );
  });
});

test("createModelRegistry resolves the active provider configuration", async () => {
  await withEnv({
    NOVAI_API_KEY: "test-token",
    AI_PROVIDER: "claude",
    AI_MODEL: "claude-opus-4-6",
    AI_BASE_URL: "https://example.invalid",
    AI_API_KIND: "anthropic-messages",
    AI_TIMEOUT_MS: "30000",
    AI_MAX_RETRIES: "3",
    AI_CIRCUIT_BREAKER_ENABLED: "true"
  }, async () => {
    const registry = createModelRegistry({
      providerFactories: {
        claude: ({ config }) => ({
          name: "claude",
          config,
          async request() {
            return {
              provider: "claude",
              model: config.model,
              text: "ok",
              raw: {},
              usage: null,
              data: { text: "ok" }
            };
          }
        })
      }
    });

    const activeModel = registry.resolveActiveModel();

    assert.equal(activeModel.provider, "claude");
    assert.equal(activeModel.model, "claude-opus-4-6");
    assert.equal(activeModel.apiKind, "anthropic-messages");
    assert.equal(activeModel.timeoutMs, 30000);
    assert.equal(activeModel.maxRetries, 3);
    assert.equal(activeModel.circuitBreakerEnabled, true);
    assert.equal(typeof activeModel.providerClient.request, "function");
  });
});
