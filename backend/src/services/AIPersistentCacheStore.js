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

function parsePayload(row) {
  if (!row?.payload_json) return row;
  return {
    ...row,
    payload: JSON.parse(row.payload_json)
  };
}

function errorCodeFrom(error, fallback = "PREWARM_SENTENCE_FAILED") {
  return error?.code || error?.error_code || fallback;
}

function requestIDFrom(error) {
  return error?.requestID || error?.request_id || null;
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

      CREATE TABLE IF NOT EXISTS ai_document_prewarm_jobs (
        job_id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        title TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('queued', 'running', 'completed', 'completed_with_errors', 'failed')),
        total_count INTEGER NOT NULL,
        ready_count INTEGER NOT NULL DEFAULT 0,
        failed_count INTEGER NOT NULL DEFAULT 0,
        queued_count INTEGER NOT NULL DEFAULT 0,
        processing_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS ai_sentence_prewarm_jobs (
        job_id TEXT NOT NULL,
        document_id TEXT NOT NULL,
        sentence_id TEXT NOT NULL,
        sentence_text_hash TEXT NOT NULL,
        cache_key TEXT NOT NULL,
        model_name TEXT NOT NULL,
        priority INTEGER NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('queued', 'processing', 'ready', 'failed', 'skipped')),
        error_code TEXT,
        request_id TEXT,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (job_id, sentence_id, sentence_text_hash)
      );

      CREATE INDEX IF NOT EXISTS idx_ai_document_prewarm_jobs_document
        ON ai_document_prewarm_jobs(document_id);

      CREATE INDEX IF NOT EXISTS idx_ai_sentence_prewarm_jobs_status
        ON ai_sentence_prewarm_jobs(status);
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

  createPrewarmJob(job) {
    const now = nowIso();
    this.db.prepare(`
      INSERT INTO ai_document_prewarm_jobs (
        job_id,
        document_id,
        title,
        status,
        total_count,
        ready_count,
        failed_count,
        queued_count,
        processing_count,
        created_at,
        updated_at
      ) VALUES (
        @job_id,
        @document_id,
        @title,
        @status,
        @total_count,
        @ready_count,
        @failed_count,
        @queued_count,
        @processing_count,
        @created_at,
        @updated_at
      )
    `).run({
      job_id: job.job_id,
      document_id: job.document_id,
      title: job.title || "",
      status: job.status || "queued",
      total_count: job.total_count,
      ready_count: job.ready_count ?? 0,
      failed_count: job.failed_count ?? 0,
      queued_count: job.queued_count ?? job.total_count,
      processing_count: job.processing_count ?? 0,
      created_at: job.created_at || now,
      updated_at: job.updated_at || now
    });
  }

  createSentencePrewarmJob(job) {
    this.db.prepare(`
      INSERT INTO ai_sentence_prewarm_jobs (
        job_id,
        document_id,
        sentence_id,
        sentence_text_hash,
        cache_key,
        model_name,
        priority,
        status,
        error_code,
        request_id,
        payload_json,
        updated_at
      ) VALUES (
        @job_id,
        @document_id,
        @sentence_id,
        @sentence_text_hash,
        @cache_key,
        @model_name,
        @priority,
        @status,
        @error_code,
        @request_id,
        @payload_json,
        @updated_at
      )
    `).run({
      job_id: job.job_id,
      document_id: job.document_id,
      sentence_id: job.sentence_id,
      sentence_text_hash: job.sentence_text_hash,
      cache_key: job.cache_key,
      model_name: job.model_name,
      priority: job.priority,
      status: job.status || "queued",
      error_code: job.error_code || null,
      request_id: job.request_id || null,
      payload_json: JSON.stringify(job.payload || {}),
      updated_at: job.updated_at || nowIso()
    });
  }

  getPrewarmJobStatus(jobID) {
    return this.db.prepare(`
      SELECT *
      FROM ai_document_prewarm_jobs
      WHERE job_id = ?
      LIMIT 1
    `).get(jobID) || null;
  }

  getLatestPrewarmJobByDocumentID(documentID) {
    return this.db.prepare(`
      SELECT *
      FROM ai_document_prewarm_jobs
      WHERE document_id = ?
      ORDER BY created_at DESC
      LIMIT 1
    `).get(documentID) || null;
  }

  hasQueuedSentences() {
    const row = this.db.prepare(`
      SELECT 1 AS found
      FROM ai_sentence_prewarm_jobs
      WHERE status = 'queued'
      LIMIT 1
    `).get();
    return Boolean(row);
  }

  claimNextQueuedSentence() {
    const row = this.db.prepare(`
      SELECT *
      FROM ai_sentence_prewarm_jobs
      WHERE status = 'queued'
      ORDER BY priority ASC, updated_at ASC
      LIMIT 1
    `).get();
    return parsePayload(row) || null;
  }

  markSentencePrewarmProcessing(row) {
    this.db.prepare(`
      UPDATE ai_sentence_prewarm_jobs
      SET status = 'processing',
          error_code = NULL,
          request_id = @request_id,
          updated_at = @updated_at
      WHERE job_id = @job_id
        AND sentence_id = @sentence_id
        AND sentence_text_hash = @sentence_text_hash
    `).run({
      job_id: row.job_id,
      sentence_id: row.sentence_id,
      sentence_text_hash: row.sentence_text_hash,
      request_id: row.request_id || null,
      updated_at: nowIso()
    });

    this.markProcessing({
      document_id: row.document_id,
      sentence_id: row.sentence_id,
      sentence_text_hash: row.sentence_text_hash,
      prompt_version: row.prompt_version || SENTENCE_EXPLAIN_PROMPT_VERSION,
      model_name: row.model_name,
      cache_key: row.cache_key,
      request_id: row.request_id || null
    });

    this.recalculatePrewarmJob(row.job_id);
  }

  markSentencePrewarmReady(row, result) {
    const wroteReady = this.storeReady({
      document_id: row.document_id,
      sentence_id: row.sentence_id,
      sentence_text_hash: row.sentence_text_hash,
      prompt_version: row.prompt_version || SENTENCE_EXPLAIN_PROMPT_VERSION,
      model_name: row.model_name,
      cache_key: row.cache_key,
      request_id: result?.request_id || result?.requestID || row.request_id || null,
      result
    });

    if (!wroteReady) {
      this.markSentencePrewarmFailed(row, {
        code: "PREWARM_USED_FALLBACK",
        requestID: result?.request_id || result?.requestID || row.request_id || null
      });
      return false;
    }

    this.db.prepare(`
      UPDATE ai_sentence_prewarm_jobs
      SET status = 'ready',
          error_code = NULL,
          request_id = @request_id,
          updated_at = @updated_at
      WHERE job_id = @job_id
        AND sentence_id = @sentence_id
        AND sentence_text_hash = @sentence_text_hash
    `).run({
      job_id: row.job_id,
      sentence_id: row.sentence_id,
      sentence_text_hash: row.sentence_text_hash,
      request_id: result?.request_id || result?.requestID || row.request_id || null,
      updated_at: nowIso()
    });

    this.recalculatePrewarmJob(row.job_id);
    return true;
  }

  markSentencePrewarmFailed(row, error) {
    const error_code = errorCodeFrom(error);
    const request_id = requestIDFrom(error) || row.request_id || null;

    this.db.prepare(`
      UPDATE ai_sentence_prewarm_jobs
      SET status = 'failed',
          error_code = @error_code,
          request_id = @request_id,
          updated_at = @updated_at
      WHERE job_id = @job_id
        AND sentence_id = @sentence_id
        AND sentence_text_hash = @sentence_text_hash
    `).run({
      job_id: row.job_id,
      sentence_id: row.sentence_id,
      sentence_text_hash: row.sentence_text_hash,
      error_code,
      request_id,
      updated_at: nowIso()
    });

    this.storeFailed({
      document_id: row.document_id,
      sentence_id: row.sentence_id,
      sentence_text_hash: row.sentence_text_hash,
      prompt_version: row.prompt_version || SENTENCE_EXPLAIN_PROMPT_VERSION,
      model_name: row.model_name,
      cache_key: row.cache_key,
      error_code,
      request_id
    });

    this.recalculatePrewarmJob(row.job_id);
  }

  requeueAbandonedProcessingSentences() {
    const result = this.db.prepare(`
      UPDATE ai_sentence_prewarm_jobs
      SET status = 'queued',
          error_code = NULL,
          request_id = NULL,
          updated_at = @updated_at
      WHERE status = 'processing'
    `).run({ updated_at: nowIso() });

    this.recalculateRunningPrewarmJobs();
    return result.changes;
  }

  recalculateRunningPrewarmJobs() {
    const rows = this.db.prepare(`
      SELECT job_id
      FROM ai_document_prewarm_jobs
      WHERE status IN ('queued', 'running')
    `).all();
    for (const row of rows) {
      this.recalculatePrewarmJob(row.job_id);
    }
  }

  recalculatePrewarmJob(jobID) {
    const counts = this.db.prepare(`
      SELECT
        COUNT(*) AS total_count,
        SUM(CASE WHEN status = 'queued' THEN 1 ELSE 0 END) AS queued_count,
        SUM(CASE WHEN status = 'processing' THEN 1 ELSE 0 END) AS processing_count,
        SUM(CASE WHEN status = 'ready' THEN 1 ELSE 0 END) AS ready_count,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_count,
        SUM(CASE WHEN status = 'skipped' THEN 1 ELSE 0 END) AS skipped_count
      FROM ai_sentence_prewarm_jobs
      WHERE job_id = ?
    `).get(jobID);

    if (!counts) return null;

    const total = Number(counts.total_count || 0);
    const queued = Number(counts.queued_count || 0);
    const processing = Number(counts.processing_count || 0);
    const ready = Number(counts.ready_count || 0);
    const failed = Number(counts.failed_count || 0);
    const skipped = Number(counts.skipped_count || 0);
    const finished = ready + failed + skipped;

    let status = "failed";
    if (processing > 0) {
      status = "running";
    } else if (queued > 0) {
      status = "queued";
    } else if (total > 0 && finished >= total) {
      if (failed === 0) {
        status = "completed";
      } else if (ready > 0 || skipped > 0) {
        status = "completed_with_errors";
      } else {
        status = "failed";
      }
    }

    this.db.prepare(`
      UPDATE ai_document_prewarm_jobs
      SET status = @status,
          total_count = @total_count,
          ready_count = @ready_count,
          failed_count = @failed_count,
          queued_count = @queued_count,
          processing_count = @processing_count,
          updated_at = @updated_at
      WHERE job_id = @job_id
    `).run({
      job_id: jobID,
      status,
      total_count: total,
      ready_count: ready,
      failed_count: failed,
      queued_count: queued,
      processing_count: processing,
      updated_at: nowIso()
    });

    return this.getPrewarmJobStatus(jobID);
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
