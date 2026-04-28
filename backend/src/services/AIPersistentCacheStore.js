import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";

import { AI_CACHE_DB_PATH } from "../config/env.js";
import { stableHash } from "../lib/requestId.js";

export const SENTENCE_EXPLAIN_PROMPT_VERSION = "sentence-explain.v2";

export function buildSentenceExplainCacheKey({
  document_id,
  sentence_id,
  sentence_text_hash,
  prompt_version,
  model_name
}) {
  return stableHash([
    document_id,
    sentence_id,
    sentence_text_hash,
    prompt_version,
    model_name
  ].join("\u001e"));
}

function nowIso() {
  return new Date().toISOString();
}

function isRemoteAIReadyResult(result) {
  if (!result || result.used_fallback === true) return false;
  const source = result.current_result_source || result.currentResultSource;
  return source === "remoteAI";
}

function withCacheKey(identity) {
  return {
    ...identity,
    cache_key: identity.cache_key || buildSentenceExplainCacheKey(identity)
  };
}

export class AIPersistentCacheStore {
  constructor({ dbPath = AI_CACHE_DB_PATH } = {}) {
    const resolvedPath = resolve(dbPath);
    mkdirSync(dirname(resolvedPath), { recursive: true });
    this.db = new Database(resolvedPath);
    this.db.pragma("journal_mode = WAL");
    this.db.pragma("busy_timeout = 5000");
    this.migrate();
  }

  migrate() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS ai_sentence_explain_cache (
        cache_key TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        sentence_id TEXT NOT NULL,
        sentence_text_hash TEXT NOT NULL,
        prompt_version TEXT NOT NULL,
        model_name TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('ready', 'processing', 'failed')),
        result_json TEXT,
        error_code TEXT,
        request_id TEXT,
        updated_at TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_ai_sentence_explain_cache_document
        ON ai_sentence_explain_cache(document_id);

      CREATE INDEX IF NOT EXISTS idx_ai_sentence_explain_cache_sentence
        ON ai_sentence_explain_cache(document_id, sentence_id, sentence_text_hash);
    `);
  }

  getReady(cacheKey) {
    const row = this.db.prepare(`
      SELECT result_json, request_id, updated_at
      FROM ai_sentence_explain_cache
      WHERE cache_key = ?
        AND status = 'ready'
        AND result_json IS NOT NULL
      LIMIT 1
    `).get(cacheKey);

    if (!row) return null;

    return {
      result: JSON.parse(row.result_json),
      request_id: row.request_id || null,
      updated_at: row.updated_at
    };
  }

  getSentenceStatus({ document_id, sentence_id, sentence_text_hash }) {
    return this.db.prepare(`
      SELECT status, error_code, request_id, updated_at
      FROM ai_sentence_explain_cache
      WHERE document_id = ?
        AND sentence_id = ?
        AND sentence_text_hash = ?
      ORDER BY updated_at DESC
      LIMIT 1
    `).get(document_id, sentence_id, sentence_text_hash) || null;
  }

  markProcessing(identity) {
    this.upsert({
      ...identity,
      status: "processing",
      result_json: null,
      error_code: null
    });
  }

  storeReady({ result, ...identity }) {
    if (!isRemoteAIReadyResult(result)) {
      return false;
    }

    this.upsert({
      ...identity,
      status: "ready",
      result_json: JSON.stringify(result),
      error_code: null
    });
    return true;
  }

  storeFailed(identity) {
    this.upsert({
      ...identity,
      status: "failed",
      result_json: null
    });
  }

  upsert(row) {
    const normalized = withCacheKey(row);
    this.db.prepare(`
      INSERT INTO ai_sentence_explain_cache (
        cache_key,
        document_id,
        sentence_id,
        sentence_text_hash,
        prompt_version,
        model_name,
        status,
        result_json,
        error_code,
        request_id,
        updated_at
      ) VALUES (
        @cache_key,
        @document_id,
        @sentence_id,
        @sentence_text_hash,
        @prompt_version,
        @model_name,
        @status,
        @result_json,
        @error_code,
        @request_id,
        @updated_at
      )
      ON CONFLICT(cache_key) DO UPDATE SET
        status = excluded.status,
        result_json = excluded.result_json,
        error_code = excluded.error_code,
        request_id = excluded.request_id,
        updated_at = excluded.updated_at
    `).run({
      ...normalized,
      result_json: normalized.result_json ?? null,
      error_code: normalized.error_code ?? null,
      request_id: normalized.request_id ?? null,
      updated_at: nowIso()
    });
  }

  close() {
    this.db.close();
  }
}

let singletonStore = null;

export function getAIPersistentCacheStore(options = {}) {
  if (!singletonStore) {
    singletonStore = new AIPersistentCacheStore(options);
  }
  return singletonStore;
}

export function resetAIPersistentCacheStoreForTests(options = null) {
  if (singletonStore) {
    singletonStore.close();
    singletonStore = null;
  }

  if (options) {
    singletonStore = new AIPersistentCacheStore(options);
  }

  return singletonStore;
}
