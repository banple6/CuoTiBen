import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import {
  AIPersistentCacheStore,
  SENTENCE_EXPLAIN_PROMPT_VERSION,
  buildSentenceExplainCacheKey,
  getAIPersistentCacheStore,
  resetAIPersistentCacheStoreForTests
} from "../src/services/AIPersistentCacheStore.js";

function withTempDir(fn) {
  const dir = mkdtempSync(join(tmpdir(), "cuotiben-ai-cache-"));
  try {
    return fn(dir);
  } finally {
    resetAIPersistentCacheStoreForTests();
    rmSync(dir, { recursive: true, force: true });
  }
}

function identity(overrides = {}) {
  return {
    document_id: "doc-1",
    sentence_id: "sen_3",
    sentence_text_hash: "hash-3",
    prompt_version: SENTENCE_EXPLAIN_PROMPT_VERSION,
    model_name: "model-a",
    ...overrides
  };
}

test("buildSentenceExplainCacheKey is stable and includes required identity parts", () => {
  const first = buildSentenceExplainCacheKey(identity());
  const second = buildSentenceExplainCacheKey(identity());
  const differentModel = buildSentenceExplainCacheKey(identity({ model_name: "model-b" }));
  const differentPrompt = buildSentenceExplainCacheKey(identity({ prompt_version: "sentence-explain.v3" }));

  assert.equal(first, second);
  assert.notEqual(first, differentModel);
  assert.notEqual(first, differentPrompt);
});

test("AIPersistentCacheStore writes and reads ready sentence explanations", () => withTempDir((dir) => {
  const store = new AIPersistentCacheStore({ dbPath: join(dir, "cache.sqlite3") });
  const cache_key = buildSentenceExplainCacheKey(identity());
  const result = {
    original_sentence: "This is a sentence.",
    faithful_translation: "这是一个句子。",
    grammar: [],
    used_cache: false,
    used_fallback: false,
    current_result_source: "remoteAI"
  };

  store.markProcessing({ ...identity(), cache_key, request_id: "req-1" });
  store.storeReady({ ...identity(), cache_key, request_id: "req-2", result });

  const cached = store.getReady(cache_key);
  assert.equal(cached.request_id, "req-2");
  assert.deepEqual(cached.result, result);
  store.close();
}));

test("AIPersistentCacheStore can derive cache key from sentence identity", () => withTempDir((dir) => {
  const store = new AIPersistentCacheStore({ dbPath: join(dir, "cache.sqlite3") });
  const cache_key = buildSentenceExplainCacheKey(identity());

  store.storeReady({
    ...identity(),
    request_id: "req-derived-key",
    result: {
      original_sentence: "Derived cache key.",
      used_fallback: false,
      current_result_source: "remoteAI"
    }
  });

  assert.equal(store.getReady(cache_key).request_id, "req-derived-key");
  store.close();
}));

test("AIPersistentCacheStore does not write fallback result as ready cache", () => withTempDir((dir) => {
  const store = new AIPersistentCacheStore({ dbPath: join(dir, "cache.sqlite3") });
  const cache_key = buildSentenceExplainCacheKey(identity());

  const written = store.storeReady({
    ...identity(),
    cache_key,
    request_id: "req-fallback",
    result: {
      original_sentence: "This is a fallback.",
      used_fallback: true,
      current_result_source: "localSkeleton"
    }
  });

  assert.equal(written, false);
  assert.equal(store.getReady(cache_key), null);
  store.close();
}));

test("AIPersistentCacheStore records failed sentence status without ready result", () => withTempDir((dir) => {
  const store = new AIPersistentCacheStore({ dbPath: join(dir, "cache.sqlite3") });
  const failedIdentity = identity({
    sentence_id: "sen_4",
    sentence_text_hash: "hash-4"
  });
  const cache_key = buildSentenceExplainCacheKey(failedIdentity);

  store.storeFailed({
    ...failedIdentity,
    cache_key,
    request_id: "req-3",
    error_code: "GEMINI_UPSTREAM_503"
  });

  assert.equal(store.getReady(cache_key), null);
  const row = store.getSentenceStatus({
    document_id: "doc-1",
    sentence_id: "sen_4",
    sentence_text_hash: "hash-4"
  });
  assert.equal(row.status, "failed");
  assert.equal(row.error_code, "GEMINI_UPSTREAM_503");
  assert.equal(row.request_id, "req-3");
  store.close();
}));

test("resetAIPersistentCacheStoreForTests replaces singleton store and isolates db paths", () => withTempDir((dir) => {
  const firstPath = join(dir, "first.sqlite3");
  const secondPath = join(dir, "second.sqlite3");
  const cache_key = buildSentenceExplainCacheKey(identity());

  resetAIPersistentCacheStoreForTests({ dbPath: firstPath });
  const firstStore = getAIPersistentCacheStore();
  firstStore.storeReady({
    ...identity(),
    cache_key,
    request_id: "req-first",
    result: {
      original_sentence: "First database.",
      used_fallback: false,
      current_result_source: "remoteAI"
    }
  });
  assert.equal(firstStore.getReady(cache_key).request_id, "req-first");

  resetAIPersistentCacheStoreForTests({ dbPath: secondPath });
  const secondStore = getAIPersistentCacheStore();
  assert.notEqual(firstStore, secondStore);
  assert.equal(secondStore.getReady(cache_key), null);
}));
