import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import {
  AIPersistentCacheStore,
  SENTENCE_EXPLAIN_PROMPT_VERSION,
  buildSentenceExplainCacheKey
} from "../src/services/AIPersistentCacheStore.js";
import {
  DocumentExplainPrewarmQueue,
  rankPrewarmSentence
} from "../src/services/DocumentExplainPrewarmQueue.js";

async function withStore(fn) {
  const dir = mkdtempSync(join(tmpdir(), "cuotiben-prewarm-queue-"));
  const store = new AIPersistentCacheStore({ dbPath: join(dir, "cache.sqlite3") });
  try {
    return await fn(store);
  } finally {
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
}

function sentence(index, overrides = {}) {
  return {
    sentence_id: `sen_${index}`,
    sentence_text_hash: `hash_${index}`,
    text: `Sentence ${index}.`,
    context: `Context ${index}.`,
    anchor_label: `第1页 第${index}句`,
    segment_id: "seg_1",
    page_index: 0,
    paragraph_role: "passageBody",
    paragraph_theme: "theme",
    question_prompt: "",
    is_current_page: false,
    is_key_sentence: false,
    is_passage_sentence: true,
    ...overrides
  };
}

function remoteResult(row) {
  return {
    original_sentence: row.payload.text,
    faithful_translation: `翻译 ${row.sentence_id}`,
    grammar: [],
    used_cache: false,
    used_fallback: false,
    current_result_source: "remoteAI"
  };
}

test("rankPrewarmSentence prioritizes current page, first body sentences, key sentences, then remaining", () => {
  const currentPage = rankPrewarmSentence(sentence(50, { is_current_page: true }), 50);
  const earlyBody = rankPrewarmSentence(sentence(5), 5);
  const keySentence = rankPrewarmSentence(sentence(50, { is_key_sentence: true }), 50);
  const remaining = rankPrewarmSentence(sentence(50), 50);

  assert.ok(currentPage < earlyBody);
  assert.ok(earlyBody < keySentence);
  assert.ok(keySentence < remaining);
});

test("enqueueDocument creates document and sentence prewarm jobs", () => withStore((store) => {
  const queue = new DocumentExplainPrewarmQueue({
    store,
    modelName: "model-a",
    explainSentence: async (row) => remoteResult(row),
    autoStart: false
  });

  const job = queue.enqueueDocument({
    document_id: "doc-1",
    title: "Demo",
    sentences: [sentence(1), sentence(2)]
  });

  const status = store.getPrewarmJobStatus(job.job_id);
  assert.equal(status.document_id, "doc-1");
  assert.equal(status.status, "queued");
  assert.equal(status.total_count, 2);
  assert.equal(status.queued_count, 2);

  const rows = store.db.prepare(`
    SELECT sentence_id, status
    FROM ai_sentence_prewarm_jobs
    WHERE job_id = ?
    ORDER BY priority ASC
  `).all(job.job_id);
  assert.deepEqual(rows.map((row) => row.sentence_id), ["sen_1", "sen_2"]);
  assert.deepEqual(rows.map((row) => row.status), ["queued", "queued"]);
}));

test("queue processes successful remoteAI sentence jobs into ready cache and completed document job", async () => withStore(async (store) => {
  const queue = new DocumentExplainPrewarmQueue({
    store,
    modelName: "model-a",
    explainSentence: async (row) => ({
      ...remoteResult(row),
      request_id: `req-${row.sentence_id}`
    }),
    autoStart: false
  });

  const job = queue.enqueueDocument({
    document_id: "doc-1",
    title: "Demo",
    sentences: [sentence(1), sentence(2)]
  });

  await queue.drainForTests();

  const status = queue.getJobStatus(job.job_id);
  assert.equal(status.status, "completed");
  assert.equal(status.ready_count, 2);
  assert.equal(status.failed_count, 0);

  const row = store.db.prepare(`
    SELECT cache_key
    FROM ai_sentence_prewarm_jobs
    WHERE job_id = ? AND sentence_id = ?
  `).get(job.job_id, "sen_1");
  assert.equal(store.getReady(row.cache_key).result.current_result_source, "remoteAI");
}));

test("single sentence failure does not fail the whole document job", async () => withStore(async (store) => {
  const queue = new DocumentExplainPrewarmQueue({
    store,
    modelName: "model-a",
    explainSentence: async (row) => {
      if (row.sentence_id === "sen_2") {
        const error = new Error("provider busy");
        error.code = "GEMINI_UPSTREAM_503";
        error.requestID = "req-failed";
        throw error;
      }
      return remoteResult(row);
    },
    autoStart: false
  });

  const job = queue.enqueueDocument({
    document_id: "doc-1",
    title: "Demo",
    sentences: [sentence(1), sentence(2)]
  });

  await queue.drainForTests();

  const status = queue.getJobStatus(job.job_id);
  assert.equal(status.status, "completed_with_errors");
  assert.equal(status.ready_count, 1);
  assert.equal(status.failed_count, 1);

  const failed = store.db.prepare(`
    SELECT status, error_code, request_id
    FROM ai_sentence_prewarm_jobs
    WHERE job_id = ? AND sentence_id = ?
  `).get(job.job_id, "sen_2");
  assert.deepEqual(failed, {
    status: "failed",
    error_code: "GEMINI_UPSTREAM_503",
    request_id: "req-failed"
  });
}));

test("fallback explain result marks sentence failed and does not write ready cache", async () => withStore(async (store) => {
  const queue = new DocumentExplainPrewarmQueue({
    store,
    modelName: "model-a",
    explainSentence: async () => ({
      original_sentence: "Fallback.",
      used_fallback: true,
      current_result_source: "requestFailed"
    }),
    autoStart: false
  });

  const job = queue.enqueueDocument({
    document_id: "doc-1",
    title: "Demo",
    sentences: [sentence(1)]
  });

  await queue.drainForTests();

  const row = store.db.prepare(`
    SELECT cache_key, status, error_code
    FROM ai_sentence_prewarm_jobs
    WHERE job_id = ?
  `).get(job.job_id);
  assert.equal(row.status, "failed");
  assert.equal(row.error_code, "PREWARM_USED_FALLBACK");
  assert.equal(store.getReady(row.cache_key), null);
}));

test("recoverAbandonedWork requeues persisted processing sentences and recalculates running job", () => withStore((store) => {
  const modelName = "model-a";
  const payload = sentence(1);
  const cacheKey = buildSentenceExplainCacheKey({
    document_id: "doc-1",
    sentence_id: payload.sentence_id,
    sentence_text_hash: payload.sentence_text_hash,
    prompt_version: SENTENCE_EXPLAIN_PROMPT_VERSION,
    model_name: modelName
  });

  store.createPrewarmJob({
    job_id: "job-crash",
    document_id: "doc-1",
    title: "Demo",
    status: "running",
    total_count: 1,
    queued_count: 0,
    processing_count: 1,
    ready_count: 0,
    failed_count: 0
  });
  store.createSentencePrewarmJob({
    job_id: "job-crash",
    document_id: "doc-1",
    sentence_id: payload.sentence_id,
    sentence_text_hash: payload.sentence_text_hash,
    cache_key: cacheKey,
    model_name: modelName,
    priority: 10,
    status: "processing",
    payload
  });

  const queue = new DocumentExplainPrewarmQueue({
    store,
    modelName,
    explainSentence: async (row) => remoteResult(row),
    autoStart: false
  });

  queue.recoverAbandonedWork();

  const sentenceRow = store.db.prepare(`
    SELECT status
    FROM ai_sentence_prewarm_jobs
    WHERE job_id = ?
  `).get("job-crash");
  const job = store.getPrewarmJobStatus("job-crash");

  assert.equal(sentenceRow.status, "queued");
  assert.equal(job.status, "queued");
  assert.equal(job.queued_count, 1);
  assert.equal(job.processing_count, 0);
}));
