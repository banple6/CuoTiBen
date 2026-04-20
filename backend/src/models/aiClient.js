import crypto from "crypto";

import { createCircuitBreaker } from "./circuitBreaker.js";
import { createAIError, attachAIErrorMetadata, isRetryableErrorCode } from "./errors.js";
import { createResponseCache } from "./responseCache.js";
import { executeWithRetry } from "./retryPolicy.js";

function stableSerialize(value) {
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableSerialize(item)).join(",")}]`;
  }

  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableSerialize(value[key])}`).join(",")}}`;
  }

  return JSON.stringify(value);
}

function createPayloadHash(payload) {
  return crypto
    .createHash("sha256")
    .update(stableSerialize(payload))
    .digest("hex");
}

function buildMeta(baseMeta, overrides = {}) {
  return {
    request_id: baseMeta.requestId,
    retry_count: overrides.retryCount ?? 0,
    used_cache: overrides.usedCache ?? false,
    used_fallback: overrides.usedFallback ?? false,
    circuit_state: overrides.circuitState ?? "closed",
    payload_hash: baseMeta.payloadHash,
    provider: baseMeta.provider,
    model: baseMeta.model,
    route_name: baseMeta.routeName,
    timeout_ms: baseMeta.timeoutMs
  };
}

function readCachedValue(cache, cacheScope, identity) {
  if (cacheScope === "sentence") {
    return cache.getSentence(identity);
  }

  if (cacheScope === "passage") {
    return cache.getPassage(identity);
  }

  return null;
}

function writeCachedValue(cache, cacheScope, identity, value) {
  if (cacheScope === "sentence") {
    cache.setSentence(identity, value);
    return;
  }

  if (cacheScope === "passage") {
    cache.setPassage(identity, value);
  }
}

async function buildFallback(fallbackFactory, context) {
  if (typeof fallbackFactory !== "function") {
    return null;
  }

  return fallbackFactory(context);
}

export function createAIClient({
  registry,
  cache = createResponseCache(),
  breaker = createCircuitBreaker(),
  wait
} = {}) {
  if (!registry || typeof registry.preflight !== "function") {
    throw new Error("AI client requires a registry with preflight().");
  }

  return {
    async request({
      requestId,
      routeName,
      cacheScope = "none",
      identity = {},
      payload = {},
      fallbackFactory
    }) {
      const activeModel = registry.preflight();
      const payloadHash = createPayloadHash(payload);
      const circuitKey = `${activeModel.provider}:${activeModel.model}`;
      const baseMeta = {
        requestId,
        provider: activeModel.provider,
        model: activeModel.model,
        routeName,
        timeoutMs: activeModel.timeoutMs,
        payloadHash
      };

      if (activeModel.circuitBreakerEnabled !== false) {
        const gate = breaker.allowRequest(circuitKey);
        if (!gate.allowed) {
          const cached = readCachedValue(cache, cacheScope, identity);
          if (cached !== null) {
            return {
              success: true,
              data: cached,
              meta: buildMeta(baseMeta, {
                usedCache: true,
                circuitState: gate.state
              })
            };
          }

          const fallback = await buildFallback(fallbackFactory, {
            requestId,
            routeName,
            payloadHash,
            circuitState: gate.state
          });
          if (fallback !== null) {
            return {
              success: true,
              data: fallback,
              meta: buildMeta(baseMeta, {
                usedFallback: true,
                circuitState: gate.state
              })
            };
          }
        }
      }

      let retryCount = 0;

      try {
        const result = await executeWithRetry(
          async ({ requestId: currentRequestId }) => activeModel.providerClient.request({
            requestId: currentRequestId,
            routeName,
            provider: activeModel.provider,
            model: activeModel.model,
            baseUrl: activeModel.baseUrl,
            apiKind: activeModel.apiKind,
            timeoutMs: activeModel.timeoutMs,
            payload
          }),
          {
            requestId,
            maxAttempts: activeModel.maxRetries,
            wait,
            onFailedAttempt: async ({ error }) => {
              if (activeModel.circuitBreakerEnabled !== false) {
                breaker.recordFailure(circuitKey, error?.code);
              }
            },
            shouldRetry: (error) => isRetryableErrorCode(error?.code)
          }
        );

        retryCount = result.retryCount;

        if (activeModel.circuitBreakerEnabled !== false) {
          breaker.recordSuccess(circuitKey);
        }

        const data = result.value?.data ?? { text: result.value?.text || "" };
        writeCachedValue(cache, cacheScope, identity, data);

        return {
          success: true,
          data,
          meta: buildMeta(baseMeta, {
            retryCount,
            circuitState: activeModel.circuitBreakerEnabled === false ? "disabled" : breaker.getState(circuitKey)
          })
        };
      } catch (error) {
        retryCount = Number(error?.retryCount ?? retryCount);
        const circuitState = activeModel.circuitBreakerEnabled === false ? "disabled" : breaker.getState(circuitKey);

        if (isRetryableErrorCode(error?.code)) {
          const cached = readCachedValue(cache, cacheScope, identity);
          if (cached !== null) {
            return {
              success: true,
              data: cached,
              meta: buildMeta(baseMeta, {
                retryCount,
                usedCache: true,
                circuitState
              })
            };
          }
        }

        const fallback = await buildFallback(fallbackFactory, {
          error,
          requestId,
          routeName,
          payloadHash,
          circuitState
        });
        if (fallback !== null) {
          return {
            success: true,
            data: fallback,
            meta: buildMeta(baseMeta, {
              retryCount,
              usedFallback: true,
              circuitState
            })
          };
        }

        throw attachAIErrorMetadata(error, {
          requestId,
          provider: activeModel.provider,
          model: activeModel.model,
          routeName,
          retryCount,
          circuitState,
          payloadHash,
          fallbackAvailable: typeof fallbackFactory === "function"
        });
      }
    }
  };
}
