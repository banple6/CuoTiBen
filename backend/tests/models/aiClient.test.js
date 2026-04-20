import test from "node:test";
import assert from "node:assert/strict";

import { createAIError } from "../../src/models/errors.js";
import { createAIClient } from "../../src/models/aiClient.js";
import { createCircuitBreaker } from "../../src/models/circuitBreaker.js";
import { createResponseCache } from "../../src/models/responseCache.js";
import { createMockAIProvider } from "../fixtures/mockAIProvider.js";

function createRegistry(providerClient, overrides = {}) {
  return {
    preflight() {
      return {
        provider: "claude",
        model: "claude-opus-4-6",
        apiKey: "test-token",
        baseUrl: "https://example.invalid",
        apiKind: "anthropic-messages",
        timeoutMs: 1500,
        maxRetries: 3,
        circuitBreakerEnabled: true,
        providerClient,
        ...overrides
      };
    }
  };
}

test("aiClient wraps successful responses with fixed meta fields", async () => {
  const provider = createMockAIProvider([
    {
      text: "provider result",
      data: {
        answer: "provider result"
      }
    }
  ]);
  const client = createAIClient({
    registry: createRegistry(provider),
    cache: createResponseCache(),
    breaker: createCircuitBreaker(),
    wait: async () => {}
  });

  const result = await client.request({
    requestId: "req-success-1",
    routeName: "ai/explain-sentence",
    cacheScope: "sentence",
    identity: {
      sentenceID: "sentence-1",
      sentenceTextHash: "hash-1"
    },
    payload: {
      prompt: "hello"
    },
    fallbackFactory: async () => ({
      answer: "fallback"
    })
  });

  assert.equal(result.success, true);
  assert.deepEqual(result.data, {
    answer: "provider result"
  });
  assert.equal(result.meta.request_id, "req-success-1");
  assert.equal(result.meta.retry_count, 0);
  assert.equal(result.meta.used_cache, false);
  assert.equal(result.meta.used_fallback, false);
  assert.equal(result.meta.circuit_state, "closed");
  assert.equal(result.meta.provider, "claude");
  assert.equal(result.meta.model, "claude-opus-4-6");
  assert.equal(result.meta.route_name, "ai/explain-sentence");
  assert.equal(result.meta.timeout_ms, 1500);
  assert.match(result.meta.payload_hash, /^[a-f0-9]{64}$/);
});

test("aiClient prefers cache over fallback after retryable 503 failures", async () => {
  const provider = createMockAIProvider([
    {
      type: "throw",
      error: createAIError("UPSTREAM_503", { message: "busy" })
    }
  ]);
  const cache = createResponseCache();
  cache.setSentence(
    {
      sentenceID: "sentence-2",
      sentenceTextHash: "hash-2"
    },
    {
      answer: "cached"
    }
  );
  const client = createAIClient({
    registry: createRegistry(provider),
    cache,
    breaker: createCircuitBreaker(),
    wait: async () => {}
  });

  const result = await client.request({
    requestId: "req-cache-1",
    routeName: "ai/explain-sentence",
    cacheScope: "sentence",
    identity: {
      sentenceID: "sentence-2",
      sentenceTextHash: "hash-2"
    },
    payload: {
      prompt: "hello"
    },
    fallbackFactory: async () => ({
      answer: "fallback"
    })
  });

  assert.equal(result.success, true);
  assert.deepEqual(result.data, {
    answer: "cached"
  });
  assert.equal(result.meta.used_cache, true);
  assert.equal(result.meta.used_fallback, false);
  assert.equal(result.meta.retry_count, 2);
});

test("aiClient wraps fallback results with the fixed meta fields", async () => {
  const provider = createMockAIProvider([
    {
      type: "throw",
      error: createAIError("UPSTREAM_503", { message: "busy" })
    }
  ]);
  const client = createAIClient({
    registry: createRegistry(provider),
    cache: createResponseCache(),
    breaker: createCircuitBreaker(),
    wait: async () => {}
  });

  const result = await client.request({
    requestId: "req-fallback-1",
    routeName: "ai/analyze-passage",
    cacheScope: "passage",
    identity: {
      documentID: "document-1",
      contentHash: "content-1"
    },
    payload: {
      prompt: "hello"
    },
    fallbackFactory: async () => ({
      answer: "fallback"
    })
  });

  assert.equal(result.success, true);
  assert.deepEqual(result.data, {
    answer: "fallback"
  });
  assert.equal(result.meta.request_id, "req-fallback-1");
  assert.equal(result.meta.retry_count, 2);
  assert.equal(result.meta.used_cache, false);
  assert.equal(result.meta.used_fallback, true);
  assert.equal(result.meta.circuit_state, "open");
  assert.match(result.meta.payload_hash, /^[a-f0-9]{64}$/);
});
