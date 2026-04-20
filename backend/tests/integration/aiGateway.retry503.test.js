import test from "node:test";
import assert from "node:assert/strict";

import { createAIClient } from "../../src/models/aiClient.js";
import { createCircuitBreaker } from "../../src/models/circuitBreaker.js";
import { createModelRegistry } from "../../src/models/modelRegistry.js";
import { createResponseCache } from "../../src/models/responseCache.js";
import { createFakeTransport } from "../fixtures/fakeTransport.js";

function createRegistryWithTransport(transport) {
  return createModelRegistry({
    getConfig: () => ({
      apiKey: "test-token",
      provider: "claude",
      model: "claude-opus-4-6",
      baseUrl: "https://example.invalid",
      apiKind: "anthropic-messages",
      timeoutMs: 1500,
      maxRetries: 3,
      circuitBreakerEnabled: true
    }),
    transport
  });
}

test("aiClient retries 503 responses and eventually succeeds", async () => {
  const transport = createFakeTransport([
    {
      status: 503,
      body: {
        error: {
          message: "busy"
        }
      }
    },
    {
      status: 503,
      body: {
        error: {
          message: "busy"
        }
      }
    },
    {
      status: 200,
      body: {
        id: "msg_1",
        content: [
          {
            type: "text",
            text: "provider success"
          }
        ],
        usage: {
          input_tokens: 10,
          output_tokens: 12
        }
      }
    }
  ]);
  const client = createAIClient({
    registry: createRegistryWithTransport(transport),
    cache: createResponseCache(),
    breaker: createCircuitBreaker(),
    wait: async () => {}
  });

  const result = await client.request({
    requestId: "req-retry-success",
    routeName: "ai/explain-sentence",
    cacheScope: "sentence",
    identity: {
      sentenceID: "sentence-3",
      sentenceTextHash: "hash-3"
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
    text: "provider success"
  });
  assert.equal(result.meta.retry_count, 2);
  assert.equal(result.meta.used_fallback, false);
  assert.equal(transport.calls.length, 3);
});

test("aiClient opens the circuit breaker after repeated 503 failures and falls back on later calls", async () => {
  const transport = createFakeTransport([
    {
      status: 503,
      body: {
        error: {
          message: "busy"
        }
      }
    },
    {
      status: 503,
      body: {
        error: {
          message: "busy"
        }
      }
    },
    {
      status: 503,
      body: {
        error: {
          message: "busy"
        }
      }
    },
    {
      status: 200,
      body: {
        id: "msg_2",
        content: [
          {
            type: "text",
            text: "should not be reached"
          }
        ]
      }
    }
  ]);
  const breaker = createCircuitBreaker();
  const client = createAIClient({
    registry: createRegistryWithTransport(transport),
    cache: createResponseCache(),
    breaker,
    wait: async () => {}
  });

  const firstResult = await client.request({
    requestId: "req-breaker-open",
    routeName: "ai/analyze-passage",
    cacheScope: "passage",
    identity: {
      documentID: "document-2",
      contentHash: "content-2"
    },
    payload: {
      prompt: "hello"
    },
    fallbackFactory: async () => ({
      answer: "fallback"
    })
  });

  assert.equal(firstResult.success, true);
  assert.equal(firstResult.meta.used_fallback, true);
  assert.equal(firstResult.meta.circuit_state, "open");
  assert.equal(transport.calls.length, 3);

  const secondResult = await client.request({
    requestId: "req-breaker-short-circuit",
    routeName: "ai/analyze-passage",
    cacheScope: "passage",
    identity: {
      documentID: "document-3",
      contentHash: "content-3"
    },
    payload: {
      prompt: "hello again"
    },
    fallbackFactory: async () => ({
      answer: "fallback"
    })
  });

  assert.equal(secondResult.success, true);
  assert.equal(secondResult.meta.used_fallback, true);
  assert.equal(secondResult.meta.circuit_state, "open");
  assert.equal(transport.calls.length, 3);
});
