# Document-Level AI Explain Prewarm Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build document-level background AI sentence explanation prewarming with persistent backend cache while keeping imported materials immediately openable.

**Architecture:** The backend gains a small SQLite-backed cache/job store and two prewarm endpoints. The existing `/ai/explain-sentence` route keeps its public contract but checks persistent cache before model calls. iOS starts a prewarm job after structured source loading and uses job progress only for status display and click behavior, while existing sentence explain cache remains the first read layer.

**Tech Stack:** Node 20, Express 5, `node:test`, SQLite through `better-sqlite3`, SwiftUI, existing iOS services and `AppViewModel`.

---

## Scope Guard

- Do not modify the existing `/ai/explain-sentence` response contract.
- Do not modify `/ai/analyze-passage`.
- Do not modify document parsing algorithms.
- Do not modify notes, notebooks, or canvas files.
- Do not add real API keys or secrets to code, tests, logs, or docs.
- Do not commit `.env` files.
- Do not log or persist Authorization headers.
- Do not block document import while AI explanations are generated.

## Deployment Gate for SQLite Cache

`better-sqlite3` is a native dependency and must be treated as a deployment gate, not a transparent JavaScript-only package.

Before enabling this on the server:

- Confirm production uses Node 20.
- Confirm native dependency compilation succeeds during install or image build.
- Confirm the backend process can write to `.data` or the directory pointed at by `AI_CACHE_DB_PATH`.
- Set `AI_CACHE_DB_PATH` explicitly in production if the app working directory is not stable.
- Run a server deployment smoke test that starts the backend, creates the cache file, writes a ready row, reads it back, and restarts the process to verify persistence.

## File Structure

Backend files:

- Modify: `backend/package.json`
- Modify: `backend/package-lock.json`
- Modify: `backend/src/config/env.js`
- Create: `backend/src/services/AIPersistentCacheStore.js`
- Create: `backend/src/services/DocumentExplainPrewarmQueue.js`
- Create: `backend/src/validators/prewarmDocument.js`
- Modify: `backend/src/services/explainSentenceService.js`
- Modify: `backend/src/routes/ai.js`
- Create: `backend/tests/aiPersistentCacheStore.test.js`
- Create: `backend/tests/prewarmDocumentValidator.test.js`
- Create: `backend/tests/documentExplainPrewarmQueue.test.js`
- Modify: `backend/tests/explainSentenceService.test.js`
- Modify: `backend/tests/validators.test.js`

iOS files:

- Create: `CuoTiBen/Sources/HuiLu/Services/DocumentExplainPrewarmService.swift`
- Modify: `CuoTiBen/Sources/HuiLu/ViewModels/AppViewModel.swift`
- Modify: `CuoTiBen/Sources/HuiLu/Views/HomeView.swift`
- Modify: `CuoTiBen/Sources/HuiLu/Views/SourceDetailSheets.swift`
- Modify: `CuoTiBen/Sources/HuiLu/Views/ReviewWorkbenchView.swift`
- Modify only if project membership is not automatic: `CuoTiBen.xcodeproj/project.pbxproj`

## Task 1: Add Backend Persistent Cache Store

**Files:**
- Modify: `backend/package.json`
- Modify: `backend/package-lock.json`
- Modify: `backend/src/config/env.js`
- Create: `backend/src/services/AIPersistentCacheStore.js`
- Create: `backend/tests/aiPersistentCacheStore.test.js`

- [ ] **Step 1: Add SQLite dependency**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/backend"
npm install better-sqlite3
```

Expected:

```text
package.json and package-lock.json update with better-sqlite3.
```

- [ ] **Step 2: Add cache env config**

In `backend/src/config/env.js`, export these values from the existing env config module:

```js
export const AI_CACHE_DB_PATH = process.env.AI_CACHE_DB_PATH || ".data/ai-cache.sqlite3";
export const AI_PREWARM_CONCURRENCY = Number(process.env.AI_PREWARM_CONCURRENCY || 2);
export const AI_PREWARM_MAX_SENTENCES_PER_DOCUMENT = Number(
  process.env.AI_PREWARM_MAX_SENTENCES_PER_DOCUMENT || 200
);
```

If the file already exports an object instead of named constants, add these fields to the existing exported object and update imports in later tasks to match the actual pattern.

Model name lookup for prewarm must use the current AI Gateway configuration layer, such as `getAIConfig()` or `modelRegistry`. Do not introduce provider-specific config names in new route or queue code.

- [ ] **Step 3: Write failing persistent cache tests**

Create `backend/tests/aiPersistentCacheStore.test.js`:

```js
import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import {
  getAIPersistentCacheStore,
  resetAIPersistentCacheStoreForTests,
  buildSentenceExplainCacheKey
} from "../src/services/AIPersistentCacheStore.js";

test("buildSentenceExplainCacheKey is stable and includes required identity parts", () => {
  const first = buildSentenceExplainCacheKey({
    document_id: "doc-1",
    sentence_id: "sen_3",
    sentence_text_hash: "hash-3",
    prompt_version: "sentence-explain.v2",
    model_name: "model-a"
  });
  const second = buildSentenceExplainCacheKey({
    document_id: "doc-1",
    sentence_id: "sen_3",
    sentence_text_hash: "hash-3",
    prompt_version: "sentence-explain.v2",
    model_name: "model-a"
  });
  const differentModel = buildSentenceExplainCacheKey({
    document_id: "doc-1",
    sentence_id: "sen_3",
    sentence_text_hash: "hash-3",
    prompt_version: "sentence-explain.v2",
    model_name: "model-b"
  });

  assert.equal(first, second);
  assert.notEqual(first, differentModel);
});

test("AIPersistentCacheStore writes and reads ready sentence explanations", () => {
  const dir = mkdtempSync(join(tmpdir(), "cuotiben-ai-cache-"));
  try {
    resetAIPersistentCacheStoreForTests({ dbPath: join(dir, "cache.sqlite3") });
    const store = getAIPersistentCacheStore();
    const identity = {
      document_id: "doc-1",
      sentence_id: "sen_3",
      sentence_text_hash: "hash-3",
      prompt_version: "sentence-explain.v2",
      model_name: "model-a"
    };
    const cacheKey = buildSentenceExplainCacheKey(identity);
    const result = {
      original_sentence: "This is a sentence.",
      faithful_translation: "这是一个句子。",
      used_cache: false,
      used_fallback: false
    };

    store.markProcessing({ ...identity, cache_key: cacheKey, request_id: "req-1" });
    store.storeReady({ ...identity, cache_key: cacheKey, request_id: "req-2", result });

    const cached = store.getReady(cacheKey);
    assert.equal(cached.request_id, "req-2");
    assert.deepEqual(cached.result, result);
    resetAIPersistentCacheStoreForTests();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("AIPersistentCacheStore records failed sentence status without ready result", () => {
  const dir = mkdtempSync(join(tmpdir(), "cuotiben-ai-cache-"));
  try {
    resetAIPersistentCacheStoreForTests({ dbPath: join(dir, "cache.sqlite3") });
    const store = getAIPersistentCacheStore();
    const identity = {
      document_id: "doc-1",
      sentence_id: "sen_4",
      sentence_text_hash: "hash-4",
      prompt_version: "sentence-explain.v2",
      model_name: "model-a"
    };
    const cacheKey = buildSentenceExplainCacheKey(identity);

    store.storeFailed({
      ...identity,
      cache_key: cacheKey,
      request_id: "req-3",
      error_code: "GEMINI_UPSTREAM_503"
    });

    assert.equal(store.getReady(cacheKey), null);
    const row = store.getSentenceStatus({
      document_id: "doc-1",
      sentence_id: "sen_4",
      sentence_text_hash: "hash-4"
    });
    assert.equal(row.status, "failed");
    assert.equal(row.error_code, "GEMINI_UPSTREAM_503");
    resetAIPersistentCacheStoreForTests();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
```

- [ ] **Step 4: Run cache tests to verify they fail**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/backend"
node --test tests/aiPersistentCacheStore.test.js
```

Expected:

```text
FAIL because backend/src/services/AIPersistentCacheStore.js does not exist.
```

- [ ] **Step 5: Implement `AIPersistentCacheStore`**

Create `backend/src/services/AIPersistentCacheStore.js`:

```js
import Database from "better-sqlite3";
import { dirname, resolve } from "node:path";
import { mkdirSync } from "node:fs";
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

export class AIPersistentCacheStore {
  constructor({ dbPath = ".data/ai-cache.sqlite3" } = {}) {
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
      SELECT result_json, request_id
      FROM ai_sentence_explain_cache
      WHERE cache_key = ? AND status = 'ready' AND result_json IS NOT NULL
    `).get(cacheKey);
    if (!row) return null;
    return {
      result: JSON.parse(row.result_json),
      request_id: row.request_id || null
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
    this.upsert({
      ...identity,
      status: "ready",
      result_json: JSON.stringify(result),
      error_code: null
    });
  }

  storeFailed(identity) {
    this.upsert({
      ...identity,
      status: "failed",
      result_json: null
    });
  }

  upsert(row) {
    this.db.prepare(`
      INSERT INTO ai_sentence_explain_cache (
        cache_key, document_id, sentence_id, sentence_text_hash, prompt_version,
        model_name, status, result_json, error_code, request_id, updated_at
      ) VALUES (
        @cache_key, @document_id, @sentence_id, @sentence_text_hash, @prompt_version,
        @model_name, @status, @result_json, @error_code, @request_id, @updated_at
      )
      ON CONFLICT(cache_key) DO UPDATE SET
        status = excluded.status,
        result_json = excluded.result_json,
        error_code = excluded.error_code,
        request_id = excluded.request_id,
        updated_at = excluded.updated_at
    `).run({
      ...row,
      result_json: row.result_json ?? null,
      error_code: row.error_code ?? null,
      request_id: row.request_id ?? null,
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
```

- [ ] **Step 6: Run cache tests to verify they pass**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/backend"
node --test tests/aiPersistentCacheStore.test.js
```

Expected:

```text
PASS 3 tests.
```

- [ ] **Step 7: Commit backend cache store**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen"
git add backend/package.json backend/package-lock.json backend/src/config/env.js backend/src/services/AIPersistentCacheStore.js backend/tests/aiPersistentCacheStore.test.js
git commit -m "feat: add persistent AI sentence cache"
```

Expected:

```text
Commit created.
```

## Task 2: Add Prewarm Request Validator

**Files:**
- Create: `backend/src/validators/prewarmDocument.js`
- Create: `backend/tests/prewarmDocumentValidator.test.js`
- Modify: `backend/tests/validators.test.js`

- [ ] **Step 1: Write failing validator tests**

Create `backend/tests/prewarmDocumentValidator.test.js`:

```js
import test from "node:test";
import assert from "node:assert/strict";

import { validatePrewarmDocumentRequest } from "../src/validators/prewarmDocument.js";

test("validatePrewarmDocumentRequest keeps passage sentences and removes duplicates", () => {
  const payload = validatePrewarmDocumentRequest({
    document_id: "doc-1",
    title: "Demo",
    sentences: [
      {
        sentence_id: "sen_1",
        sentence_text_hash: "hash-1",
        text: "This is the first sentence.",
        page_index: 1,
        kind: "passageSentence",
        paragraph_role: "passageBody",
        is_current_page: true,
        is_key_sentence: false,
        is_passage_sentence: true
      },
      {
        sentence_id: "sen_1",
        sentence_text_hash: "hash-1",
        text: "This is the first sentence.",
        page_index: 1,
        kind: "passageSentence",
        paragraph_role: "passageBody",
        is_current_page: true,
        is_key_sentence: false,
        is_passage_sentence: true
      },
      {
        sentence_id: "heading_1",
        sentence_text_hash: "hash-heading",
        text: "Passage",
        kind: "heading",
        paragraph_role: "heading",
        is_passage_sentence: false
      }
    ]
  });

  assert.equal(payload.document_id, "doc-1");
  assert.equal(payload.sentences.length, 1);
  assert.equal(payload.sentences[0].sentence_id, "sen_1");
});

test("validatePrewarmDocumentRequest rejects missing document id", () => {
  assert.throws(() => validatePrewarmDocumentRequest({
    title: "Demo",
    sentences: []
  }), /document_id/);
});

test("validatePrewarmDocumentRequest rejects empty eligible sentences", () => {
  assert.throws(() => validatePrewarmDocumentRequest({
    document_id: "doc-1",
    title: "Demo",
    sentences: [
      {
        sentence_id: "heading_1",
        sentence_text_hash: "hash-heading",
        text: "Passage",
        kind: "heading",
        paragraph_role: "heading",
        is_passage_sentence: false
      }
    ]
  }), /sentences/);
});
```

- [ ] **Step 2: Run validator tests to verify they fail**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/backend"
node --test tests/prewarmDocumentValidator.test.js
```

Expected:

```text
FAIL because backend/src/validators/prewarmDocument.js does not exist.
```

- [ ] **Step 3: Implement validator**

Create `backend/src/validators/prewarmDocument.js`:

```js
import { AppError } from "../lib/appError.js";

function requireString(value, field) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new AppError(`${field} 不能为空。`, {
      statusCode: 400,
      code: "INVALID_PREWARM_DOCUMENT_REQUEST"
    });
  }
  return value.trim();
}

function optionalString(value) {
  return typeof value === "string" ? value.trim() : "";
}

const EXCLUDED_KINDS = new Set([
  "heading",
  "question",
  "option",
  "vocabulary",
  "chineseInstruction",
  "bilingualNote",
  "answerKey",
  "pageHeader",
  "pageFooter"
]);

function isEligiblePassageBody(raw) {
  if (raw?.is_passage_sentence !== true) return false;
  const kind = optionalString(raw?.kind || raw?.sentence_kind || raw?.paragraph_kind);
  if (EXCLUDED_KINDS.has(kind)) return false;
  if (kind && kind !== "passageSentence" && kind !== "passageBody") return false;

  const role = optionalString(raw?.paragraph_role || raw?.role);
  if (!kind && !role) return false;
  if (role && role !== "body" && role !== "passageBody") return false;
  return true;
}

export function validatePrewarmDocumentRequest(body = {}) {
  const document_id = requireString(body.document_id, "document_id");
  const title = optionalString(body.title);
  const client_request_id = optionalString(body.client_request_id);
  const rawSentences = Array.isArray(body.sentences) ? body.sentences : [];
  const seen = new Set();
  const sentences = [];

  for (const raw of rawSentences) {
    if (!isEligiblePassageBody(raw)) continue;

    const sentence_id = optionalString(raw?.sentence_id);
    const sentence_text_hash = optionalString(raw?.sentence_text_hash);
    const text = optionalString(raw?.text);
    if (!sentence_id || !sentence_text_hash || !text) continue;

    const identity = `${sentence_id}\u001e${sentence_text_hash}`;
    if (seen.has(identity)) continue;
    seen.add(identity);

    sentences.push({
      sentence_id,
      sentence_text_hash,
      text,
      kind: optionalString(raw.kind || "passageSentence"),
      context: optionalString(raw.context),
      anchor_label: optionalString(raw.anchor_label),
      segment_id: optionalString(raw.segment_id),
      page_index: Number.isFinite(raw.page_index) ? Number(raw.page_index) : 0,
      paragraph_role: optionalString(raw.paragraph_role),
      paragraph_theme: optionalString(raw.paragraph_theme),
      question_prompt: optionalString(raw.question_prompt),
      is_current_page: Boolean(raw.is_current_page),
      is_key_sentence: Boolean(raw.is_key_sentence),
      is_passage_sentence: true
    });
  }

  if (sentences.length === 0) {
    throw new AppError("sentences 至少需要一个正文句。", {
      statusCode: 400,
      code: "INVALID_PREWARM_DOCUMENT_REQUEST"
    });
  }

  return {
    document_id,
    title,
    client_request_id,
    sentences
  };
}
```

- [ ] **Step 4: Run validator tests**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/backend"
node --test tests/prewarmDocumentValidator.test.js
```

Expected:

```text
PASS 3 tests.
```

- [ ] **Step 5: Add validator test to aggregate coverage**

If `backend/tests/validators.test.js` imports all validators, add a focused import assertion:

```js
import { validatePrewarmDocumentRequest } from "../src/validators/prewarmDocument.js";

test("prewarm document validator is available", () => {
  const payload = validatePrewarmDocumentRequest({
    document_id: "doc-1",
    sentences: [
      {
        sentence_id: "sen_1",
        sentence_text_hash: "hash-1",
        text: "This sentence is eligible.",
        kind: "passageSentence",
        paragraph_role: "passageBody",
        is_passage_sentence: true
      }
    ]
  });
  assert.equal(payload.sentences.length, 1);
});
```

- [ ] **Step 6: Commit validator**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen"
git add backend/src/validators/prewarmDocument.js backend/tests/prewarmDocumentValidator.test.js backend/tests/validators.test.js
git commit -m "feat: validate document prewarm requests"
```

Expected:

```text
Commit created.
```

## Task 3: Add Backend Document Prewarm Queue

**Files:**
- Create: `backend/src/services/DocumentExplainPrewarmQueue.js`
- Create: `backend/tests/documentExplainPrewarmQueue.test.js`
- Modify: `backend/src/services/AIPersistentCacheStore.js`

- [ ] **Step 1: Extend persistent store with job tables**

Update `AIPersistentCacheStore.migrate()` to include the job tables from the design:

```js
this.db.exec(`
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
  CREATE INDEX IF NOT EXISTS idx_ai_document_prewarm_jobs_document
    ON ai_document_prewarm_jobs(document_id);
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
    updated_at TEXT NOT NULL,
    PRIMARY KEY (job_id, sentence_id, sentence_text_hash)
  );
  CREATE INDEX IF NOT EXISTS idx_ai_sentence_prewarm_jobs_status
    ON ai_sentence_prewarm_jobs(job_id, status, priority);
`);
```

- [ ] **Step 2: Write failing queue tests**

Create `backend/tests/documentExplainPrewarmQueue.test.js`:

```js
import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import {
  getAIPersistentCacheStore,
  resetAIPersistentCacheStoreForTests
} from "../src/services/AIPersistentCacheStore.js";
import {
  DocumentExplainPrewarmQueue,
  rankPrewarmSentence
} from "../src/services/DocumentExplainPrewarmQueue.js";

test("rankPrewarmSentence prioritizes current page, early body sentences, key sentences, then remaining", () => {
  assert.equal(rankPrewarmSentence({ is_current_page: true }, 50), 0);
  assert.equal(rankPrewarmSentence({ is_key_sentence: false }, 3), 1003);
  assert.equal(rankPrewarmSentence({ is_key_sentence: true }, 50), 2050);
  assert.equal(rankPrewarmSentence({ is_key_sentence: false }, 50), 3050);
});

test("DocumentExplainPrewarmQueue creates job and reports aggregate counts", async () => {
  const dir = mkdtempSync(join(tmpdir(), "cuotiben-prewarm-"));
  try {
    resetAIPersistentCacheStoreForTests({ dbPath: join(dir, "cache.sqlite3") });
    const store = getAIPersistentCacheStore();
    const queue = new DocumentExplainPrewarmQueue({
      store,
      modelName: "model-a",
      concurrency: 1,
      autoStart: false,
      maxSentencesPerDocument: 10,
      explainSentence: async () => ({
        original_sentence: "This is a sentence.",
        faithful_translation: "这是一个句子。",
        used_fallback: false,
        current_result_source: "remoteAI"
      })
    });

    const job = queue.enqueueDocument({
      document_id: "doc-1",
      title: "Demo",
      sentences: [
        {
          sentence_id: "sen_1",
          sentence_text_hash: "hash-1",
          text: "This is the first sentence.",
          is_current_page: true,
          is_key_sentence: false
        }
      ]
    });

    assert.equal(job.document_id, "doc-1");
    assert.equal(job.total_count, 1);
    const status = queue.getJobStatus(job.job_id);
    assert.equal(status.total_count, 1);
    assert.equal(status.queued_count, 1);
    resetAIPersistentCacheStoreForTests();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("DocumentExplainPrewarmQueue records failed sentence without failing entire document", async () => {
  const dir = mkdtempSync(join(tmpdir(), "cuotiben-prewarm-"));
  try {
    resetAIPersistentCacheStoreForTests({ dbPath: join(dir, "cache.sqlite3") });
    const store = getAIPersistentCacheStore();
    const queue = new DocumentExplainPrewarmQueue({
      store,
      modelName: "model-a",
      concurrency: 1,
      maxSentencesPerDocument: 10,
      explainSentence: async ({ sentence_id }) => {
        if (sentence_id === "sen_2") {
          const error = new Error("upstream");
          error.code = "GEMINI_UPSTREAM_503";
          throw error;
        }
        return {
          original_sentence: "This is a sentence.",
          faithful_translation: "这是一个句子。",
          used_fallback: false,
          current_result_source: "remoteAI"
        };
      }
    });

    const job = queue.enqueueDocument({
      document_id: "doc-1",
      title: "Demo",
      sentences: [
        { sentence_id: "sen_1", sentence_text_hash: "hash-1", text: "One.", is_current_page: true },
        { sentence_id: "sen_2", sentence_text_hash: "hash-2", text: "Two.", is_current_page: true }
      ]
    });

    await queue.drainForTests();

    const status = queue.getJobStatus(job.job_id);
    assert.equal(status.status, "completed_with_errors");
    assert.equal(status.ready_count, 1);
    assert.equal(status.failed_count, 1);
    resetAIPersistentCacheStoreForTests();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("DocumentExplainPrewarmQueue recovers abandoned processing work on startup", async () => {
  const dir = mkdtempSync(join(tmpdir(), "cuotiben-prewarm-"));
  try {
    resetAIPersistentCacheStoreForTests({ dbPath: join(dir, "cache.sqlite3") });
    const store = getAIPersistentCacheStore();
    const queue = new DocumentExplainPrewarmQueue({
      store,
      modelName: "model-a",
      concurrency: 1,
      autoStart: false,
      maxSentencesPerDocument: 10,
      explainSentence: async () => ({
        original_sentence: "Recovered.",
        faithful_translation: "已恢复。",
        used_fallback: false,
        current_result_source: "remoteAI"
      })
    });

    const job = queue.enqueueDocument({
      document_id: "doc-recover",
      title: "Recover Demo",
      sentences: [
        { sentence_id: "sen_1", sentence_text_hash: "hash-1", text: "One.", is_current_page: true }
      ]
    });
    store.markSentencePrewarmProcessing(store.claimNextQueuedSentence());
    queue.recoverAbandonedWork();

    const status = queue.getJobStatus(job.job_id);
    assert.equal(status.queued_count, 1);
    assert.equal(status.processing_count, 0);
    resetAIPersistentCacheStoreForTests();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
```

- [ ] **Step 3: Run queue tests to verify they fail**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/backend"
node --test tests/documentExplainPrewarmQueue.test.js
```

Expected:

```text
FAIL because backend/src/services/DocumentExplainPrewarmQueue.js does not exist.
```

- [ ] **Step 4: Implement queue skeleton and job persistence**

Create `backend/src/services/DocumentExplainPrewarmQueue.js`:

```js
import { randomUUID } from "node:crypto";
import {
  SENTENCE_EXPLAIN_PROMPT_VERSION,
  buildSentenceExplainCacheKey
} from "./AIPersistentCacheStore.js";

export function rankPrewarmSentence(sentence, index) {
  if (sentence.is_current_page) return index;
  if (index < 20) return 1000 + index;
  if (sentence.is_key_sentence) return 2000 + index;
  return 3000 + index;
}

function nowIso() {
  return new Date().toISOString();
}

function errorCodeFrom(error) {
  return error?.code || error?.error_code || "PREWARM_SENTENCE_FAILED";
}

export class DocumentExplainPrewarmQueue {
  constructor({
    store,
    modelName,
    explainSentence,
    concurrency = 2,
    maxSentencesPerDocument = 200,
    autoStart = true
  }) {
    this.store = store;
    this.modelName = modelName;
    this.explainSentence = explainSentence;
    this.concurrency = Math.max(1, Number(concurrency || 1));
    this.maxSentencesPerDocument = Math.max(1, Number(maxSentencesPerDocument || 200));
    this.autoStart = Boolean(autoStart);
    this.running = 0;
    this.pendingPromiseResolvers = [];
    this.recoverAbandonedWork();
  }

  recoverAbandonedWork() {
    this.store.requeueAbandonedProcessingSentences();
    this.store.recalculateRunningPrewarmJobs();
  }

  enqueueDocument({ document_id, title = "", sentences }) {
    const job_id = `prewarm_${document_id}_${randomUUID()}`;
    const selected = sentences
      .map((sentence, index) => ({
        ...sentence,
        priority: rankPrewarmSentence(sentence, index)
      }))
      .sort((a, b) => a.priority - b.priority)
      .slice(0, this.maxSentencesPerDocument);

    this.store.createPrewarmJob({
      job_id,
      document_id,
      title,
      total_count: selected.length,
      created_at: nowIso(),
      updated_at: nowIso()
    });

    for (const sentence of selected) {
      const identity = {
        document_id,
        sentence_id: sentence.sentence_id,
        sentence_text_hash: sentence.sentence_text_hash,
        prompt_version: SENTENCE_EXPLAIN_PROMPT_VERSION,
        model_name: this.modelName
      };
      const cache_key = buildSentenceExplainCacheKey(identity);
      this.store.createSentencePrewarmJob({
        job_id,
        document_id,
        sentence_id: sentence.sentence_id,
        sentence_text_hash: sentence.sentence_text_hash,
        cache_key,
        model_name: this.modelName,
        priority: sentence.priority,
        status: "queued",
        updated_at: nowIso(),
        payload: sentence
      });
    }

    if (this.autoStart) {
      this.pump();
    }
    return this.getJobStatus(job_id);
  }

  getJobStatus(job_id) {
    return this.store.getPrewarmJobStatus(job_id);
  }

  pump() {
    while (this.running < this.concurrency) {
      const next = this.store.claimNextQueuedSentence();
      if (!next) break;
      this.running += 1;
      this.processSentence(next)
        .finally(() => {
          this.running -= 1;
          this.pump();
          this.resolveDrainIfIdle();
        });
    }
  }

  async processSentence(jobRow) {
    const payload = JSON.parse(jobRow.payload_json);
    this.store.markSentencePrewarmProcessing(jobRow);
    try {
      const result = await this.explainSentence({
        ...payload,
        document_id: jobRow.document_id,
        sentence: payload.text,
        sentence_id: jobRow.sentence_id,
        sentence_text_hash: jobRow.sentence_text_hash
      });
      if (result?.used_fallback || result?.current_result_source !== "remoteAI") {
        throw Object.assign(new Error("fallback result is not cached as AI ready"), {
          code: "PREWARM_USED_FALLBACK"
        });
      }
      this.store.markSentencePrewarmReady(jobRow, result);
    } catch (error) {
      this.store.markSentencePrewarmFailed(jobRow, {
        error_code: errorCodeFrom(error),
        request_id: error?.requestID || error?.request_id || null
      });
    }
  }

  async drainForTests() {
    if (this.running === 0 && !this.store.hasQueuedSentences()) return;
    await new Promise((resolve) => this.pendingPromiseResolvers.push(resolve));
  }

  resolveDrainIfIdle() {
    if (this.running > 0 || this.store.hasQueuedSentences()) return;
    const resolvers = this.pendingPromiseResolvers.splice(0);
    for (const resolve of resolvers) resolve();
  }
}
```

- [ ] **Step 5: Implement store job methods**

Add these methods to `AIPersistentCacheStore`:

```js
createPrewarmJob(job) {
  this.db.prepare(`
    INSERT INTO ai_document_prewarm_jobs (
      job_id, document_id, title, status, total_count,
      ready_count, failed_count, queued_count, processing_count,
      created_at, updated_at
    ) VALUES (
      @job_id, @document_id, @title, 'queued', @total_count,
      0, 0, @total_count, 0, @created_at, @updated_at
    )
  `).run(job);
}

createSentencePrewarmJob(job) {
  this.db.prepare(`
    INSERT INTO ai_sentence_prewarm_jobs (
      job_id, document_id, sentence_id, sentence_text_hash, cache_key, model_name,
      priority, status, error_code, request_id, updated_at, payload_json
    ) VALUES (
      @job_id, @document_id, @sentence_id, @sentence_text_hash, @cache_key, @model_name,
      @priority, @status, NULL, NULL, @updated_at, @payload_json
    )
  `).run({
    ...job,
    payload_json: JSON.stringify(job.payload)
  });
}

getPrewarmJobStatus(job_id) {
  const job = this.db.prepare(`
    SELECT * FROM ai_document_prewarm_jobs WHERE job_id = ?
  `).get(job_id);
  if (!job) return null;
  const sentences = this.db.prepare(`
    SELECT sentence_id, sentence_text_hash, status, error_code, request_id
    FROM ai_sentence_prewarm_jobs
    WHERE job_id = ?
    ORDER BY priority ASC
  `).all(job_id);
  return { ...job, sentences };
}

getLatestPrewarmJobByDocumentID(document_id) {
  const job = this.db.prepare(`
    SELECT *
    FROM ai_document_prewarm_jobs
    WHERE document_id = ?
    ORDER BY created_at DESC
    LIMIT 1
  `).get(document_id);
  if (!job) return null;
  return this.getPrewarmJobStatus(job.job_id);
}

hasQueuedSentences() {
  const row = this.db.prepare(`
    SELECT COUNT(*) AS count FROM ai_sentence_prewarm_jobs WHERE status = 'queued'
  `).get();
  return Number(row?.count || 0) > 0;
}
```

Also add `payload_json TEXT` to `ai_sentence_prewarm_jobs` migration.

- [ ] **Step 6: Implement crash recovery methods**

Add these methods to `AIPersistentCacheStore`:

```js
requeueAbandonedProcessingSentences({ staleAfterMs = 10 * 60 * 1000 } = {}) {
  const staleCutoff = new Date(Date.now() - staleAfterMs).toISOString();
  this.db.prepare(`
    UPDATE ai_sentence_prewarm_jobs
    SET status = 'queued', updated_at = ?
    WHERE status = 'processing'
       OR (status = 'processing' AND updated_at <= ?)
  `).run(nowIso(), staleCutoff);
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
```

This intentionally requeues all persisted `processing` rows on process startup because the previous in-process worker died. The stale cutoff remains useful for future periodic recovery calls while startup recovery stays conservative.

- [ ] **Step 7: Implement claim and transition methods**

Add methods:

```js
claimNextQueuedSentence() {
  const row = this.db.prepare(`
    SELECT * FROM ai_sentence_prewarm_jobs
    WHERE status = 'queued'
    ORDER BY priority ASC
    LIMIT 1
  `).get();
  return row || null;
}

markSentencePrewarmProcessing(row) {
  this.db.prepare(`
    UPDATE ai_sentence_prewarm_jobs
    SET status = 'processing', updated_at = ?
    WHERE job_id = ? AND sentence_id = ? AND sentence_text_hash = ?
  `).run(nowIso(), row.job_id, row.sentence_id, row.sentence_text_hash);
  this.recalculatePrewarmJob(row.job_id);
}

markSentencePrewarmReady(row, result) {
  this.storeReady({
    cache_key: row.cache_key,
    document_id: row.document_id,
    sentence_id: row.sentence_id,
    sentence_text_hash: row.sentence_text_hash,
    prompt_version: SENTENCE_EXPLAIN_PROMPT_VERSION,
    model_name: row.model_name || "",
    request_id: result?.request_id || null,
    result
  });
  this.db.prepare(`
    UPDATE ai_sentence_prewarm_jobs
    SET status = 'ready', error_code = NULL, request_id = ?, updated_at = ?
    WHERE job_id = ? AND sentence_id = ? AND sentence_text_hash = ?
  `).run(result?.request_id || null, nowIso(), row.job_id, row.sentence_id, row.sentence_text_hash);
  this.recalculatePrewarmJob(row.job_id);
}

markSentencePrewarmFailed(row, { error_code, request_id }) {
  this.storeFailed({
    cache_key: row.cache_key,
    document_id: row.document_id,
    sentence_id: row.sentence_id,
    sentence_text_hash: row.sentence_text_hash,
    prompt_version: SENTENCE_EXPLAIN_PROMPT_VERSION,
    model_name: row.model_name || "",
    request_id,
    error_code
  });
  this.db.prepare(`
    UPDATE ai_sentence_prewarm_jobs
    SET status = 'failed', error_code = ?, request_id = ?, updated_at = ?
    WHERE job_id = ? AND sentence_id = ? AND sentence_text_hash = ?
  `).run(error_code, request_id, nowIso(), row.job_id, row.sentence_id, row.sentence_text_hash);
  this.recalculatePrewarmJob(row.job_id);
}
```

- [ ] **Step 8: Implement aggregate recalculation**

Add:

```js
recalculatePrewarmJob(job_id) {
  const counts = this.db.prepare(`
    SELECT status, COUNT(*) AS count
    FROM ai_sentence_prewarm_jobs
    WHERE job_id = ?
    GROUP BY status
  `).all(job_id);
  const byStatus = Object.fromEntries(counts.map((row) => [row.status, Number(row.count)]));
  const ready = byStatus.ready || 0;
  const failed = byStatus.failed || 0;
  const queued = byStatus.queued || 0;
  const processing = byStatus.processing || 0;
  const total = ready + failed + queued + processing + (byStatus.skipped || 0);
  let status = "running";
  if (queued === 0 && processing === 0 && failed === 0) status = "completed";
  if (queued === 0 && processing === 0 && failed > 0) status = "completed_with_errors";
  if (total > 0 && ready === 0 && queued === 0 && processing === 0 && failed === total) status = "failed";

  this.db.prepare(`
    UPDATE ai_document_prewarm_jobs
    SET status = ?, ready_count = ?, failed_count = ?, queued_count = ?,
        processing_count = ?, updated_at = ?
    WHERE job_id = ?
  `).run(status, ready, failed, queued, processing, nowIso(), job_id);
}
```

- [ ] **Step 9: Run queue tests**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/backend"
node --test tests/documentExplainPrewarmQueue.test.js
```

Expected:

```text
PASS 4 tests.
```

- [ ] **Step 10: Commit queue**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen"
git add backend/src/services/AIPersistentCacheStore.js backend/src/services/DocumentExplainPrewarmQueue.js backend/tests/documentExplainPrewarmQueue.test.js
git commit -m "feat: add document explain prewarm queue"
```

Expected:

```text
Commit created.
```

## Task 4: Wire Persistent Cache Into Existing Explain Service

**Files:**
- Modify: `backend/src/services/explainSentenceService.js`
- Modify: `backend/tests/explainSentenceService.test.js`

- [ ] **Step 1: Export testable cache-key helper**

In `backend/src/services/explainSentenceService.js`, import:

```js
import {
  getAIPersistentCacheStore,
  SENTENCE_EXPLAIN_PROMPT_VERSION,
  buildSentenceExplainCacheKey
} from "./AIPersistentCacheStore.js";
```

Create a module-level reference through the shared store singleton:

```js
const persistentCacheStore = getAIPersistentCacheStore();
```

Do not instantiate `AIPersistentCacheStore` directly in this service. The route layer, prewarm queue, and explain service must share the singleton returned by `getAIPersistentCacheStore()`.

Create helper:

```js
export function makePersistentExplainCacheIdentity({
  document_id,
  sentence_id,
  sentence_text_hash,
  modelName
}) {
  return {
    document_id: document_id || "unknown-document",
    sentence_id: sentence_id || "unknown-sentence",
    sentence_text_hash: sentence_text_hash || "",
    prompt_version: SENTENCE_EXPLAIN_PROMPT_VERSION,
    model_name: modelName || "unknown-model"
  };
}
```

- [ ] **Step 2: Write failing test for persistent cache identity**

Add to `backend/tests/explainSentenceService.test.js`:

```js
import { makePersistentExplainCacheIdentity } from "../src/services/explainSentenceService.js";

test("makePersistentExplainCacheIdentity includes document, sentence hash, prompt version, and model", () => {
  const identity = makePersistentExplainCacheIdentity({
    document_id: "doc-1",
    sentence_id: "sen_3",
    sentence_text_hash: "hash-3",
    modelName: "model-a"
  });

  assert.equal(identity.document_id, "doc-1");
  assert.equal(identity.sentence_id, "sen_3");
  assert.equal(identity.sentence_text_hash, "hash-3");
  assert.equal(identity.prompt_version, "sentence-explain.v2");
  assert.equal(identity.model_name, "model-a");
});
```

- [ ] **Step 3: Run explain service tests**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/backend"
node --test tests/explainSentenceService.test.js
```

Expected:

```text
PASS including the new persistent identity test.
```

- [ ] **Step 4: Add persistent cache lookup before model call**

Inside `explainSentence`, after `modelName` is known and before the in-memory cache lookup returns to model call, add:

```js
const persistentIdentity = makePersistentExplainCacheIdentity({
  document_id,
  sentence_id,
  sentence_text_hash,
  modelName
});
const persistentCacheKey = buildSentenceExplainCacheKey(persistentIdentity);
const persistentHit = persistentCacheStore.getReady(persistentCacheKey);
if (persistentHit) {
  return {
    ...persistentHit.result,
    request_id: requestID,
    used_cache: true,
    used_fallback: false,
    retry_count: 0
  };
}
```

Keep the existing in-memory cache lookup as an additional fast path. Do not remove `AIResponseCache` in this phase.

- [ ] **Step 5: Store successful remote AI results persistently**

After `const response = { ... }` and before `return response`, add:

```js
if (response.current_result_source === "remoteAI" && response.used_fallback !== true) {
  persistentCacheStore.storeReady({
    ...persistentIdentity,
    cache_key: persistentCacheKey,
    request_id: requestID,
    result: response
  });
}
```

Do not write local skeleton or fallback responses as `ready` cache rows. If the single-sentence path returns `used_fallback=true`, leave the existing fallback behavior unchanged but do not persist it as a successful AI explanation.

In the `catch` block, before rethrowing and when there is no cache hit, add:

```js
persistentCacheStore.storeFailed({
  ...persistentIdentity,
  cache_key: persistentCacheKey,
  request_id: requestID,
  error_code: error?.code || error?.error_code || "EXPLAIN_SENTENCE_FAILED"
});
```

- [ ] **Step 6: Run backend tests**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/backend"
npm test
```

Expected:

```text
All backend tests pass.
```

- [ ] **Step 7: Commit explain persistent cache integration**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen"
git add backend/src/services/explainSentenceService.js backend/tests/explainSentenceService.test.js
git commit -m "feat: persist sentence explain cache"
```

Expected:

```text
Commit created.
```

## Task 5: Add Prewarm API Routes

**Files:**
- Modify: `backend/src/routes/ai.js`
- Modify: `backend/src/services/DocumentExplainPrewarmQueue.js`
- Create: `backend/tests/prewarmDocumentRoutes.test.js`

- [ ] **Step 1: Write route tests**

Create `backend/tests/prewarmDocumentRoutes.test.js`:

```js
import test from "node:test";
import assert from "node:assert/strict";

import app from "../src/app.js";

test("POST /ai/prewarm-document creates a prewarm job", async () => {
  const server = app.listen(0);
  try {
    const { port } = server.address();
    const response = await fetch(`http://127.0.0.1:${port}/ai/prewarm-document`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        document_id: "doc-route-1",
        title: "Route Demo",
        sentences: [
          {
            sentence_id: "sen_1",
            sentence_text_hash: "hash-1",
            text: "This is eligible.",
            kind: "passageSentence",
            paragraph_role: "passageBody",
            is_passage_sentence: true,
            is_current_page: true
          }
        ]
      })
    });
    const json = await response.json();
    assert.equal(response.status, 200);
    assert.equal(json.success, true);
    assert.equal(json.data.document_id, "doc-route-1");
    assert.equal(json.data.total_count, 1);
    assert.match(json.data.job_id, /^prewarm_/);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("GET /ai/prewarm-document/:job_id returns job status", async () => {
  const server = app.listen(0);
  try {
    const { port } = server.address();
    const create = await fetch(`http://127.0.0.1:${port}/ai/prewarm-document`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        document_id: "doc-route-2",
        title: "Route Demo",
        sentences: [
          {
            sentence_id: "sen_1",
            sentence_text_hash: "hash-1",
            text: "This is eligible.",
            kind: "passageSentence",
            paragraph_role: "passageBody",
            is_passage_sentence: true
          }
        ]
      })
    });
    const created = await create.json();
    const response = await fetch(`http://127.0.0.1:${port}/ai/prewarm-document/${created.data.job_id}`);
    const json = await response.json();
    assert.equal(response.status, 200);
    assert.equal(json.success, true);
    assert.equal(json.data.job_id, created.data.job_id);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("GET /ai/prewarm-document/latest returns newest job for document", async () => {
  const server = app.listen(0);
  try {
    const { port } = server.address();
    await fetch(`http://127.0.0.1:${port}/ai/prewarm-document`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        document_id: "doc-route-latest",
        title: "Route Demo",
        sentences: [
          {
            sentence_id: "sen_1",
            sentence_text_hash: "hash-1",
            text: "This is eligible.",
            kind: "passageSentence",
            paragraph_role: "passageBody",
            is_passage_sentence: true
          }
        ]
      })
    });

    const response = await fetch(
      `http://127.0.0.1:${port}/ai/prewarm-document/latest?document_id=doc-route-latest`
    );
    const json = await response.json();
    assert.equal(response.status, 200);
    assert.equal(json.success, true);
    assert.equal(json.data.document_id, "doc-route-latest");
    assert.match(json.data.job_id, /^prewarm_/);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
```

- [ ] **Step 2: Run route tests to verify they fail**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/backend"
node --test tests/prewarmDocumentRoutes.test.js
```

Expected:

```text
FAIL with 404 for /ai/prewarm-document.
```

- [ ] **Step 3: Create route-level queue singleton**

In `backend/src/routes/ai.js`, import:

```js
import { getAIConfig } from "../config/aiConfig.js";
import { getAIPersistentCacheStore } from "../services/AIPersistentCacheStore.js";
import { DocumentExplainPrewarmQueue } from "../services/DocumentExplainPrewarmQueue.js";
import { validatePrewarmDocumentRequest } from "../validators/prewarmDocument.js";
import { AI_PREWARM_CONCURRENCY, AI_PREWARM_MAX_SENTENCES_PER_DOCUMENT } from "../config/env.js";
```

If this repository exposes model names through `modelRegistry` instead of `getAIConfig()`, import that existing registry and read the configured explain model from it. New prewarm code must not introduce provider-specific config names.

Create:

```js
const persistentCacheStore = getAIPersistentCacheStore();
const aiConfig = getAIConfig();
const prewarmQueue = new DocumentExplainPrewarmQueue({
  store: persistentCacheStore,
  modelName: aiConfig.modelName,
  concurrency: AI_PREWARM_CONCURRENCY,
  maxSentencesPerDocument: AI_PREWARM_MAX_SENTENCES_PER_DOCUMENT,
  explainSentence
});
```

Routes and services must not instantiate `AIPersistentCacheStore` directly. The route-level queue receives the shared singleton and the explain service reads from the same singleton.

- [ ] **Step 4: Add POST route**

Add to `backend/src/routes/ai.js`:

```js
router.post("/prewarm-document", async (req, res) => {
  const payload = validatePrewarmDocumentRequest(req.body);
  const requestID = resolveRequestID(
    payload.client_request_id || req.headers["x-client-request-id"]
  );
  req.requestID = requestID;

  const data = prewarmQueue.enqueueDocument(payload);

  return res.json({
    success: true,
    data,
    request_id: requestID,
    used_cache: false,
    used_fallback: false
  });
});
```

- [ ] **Step 5: Add latest-job recovery route**

Add this route before the parameterized `/:job_id` route so Express does not treat `latest` as a job id:

```js
router.get("/prewarm-document/latest", async (req, res) => {
  const requestID = resolveRequestID(req.headers["x-client-request-id"]);
  req.requestID = requestID;
  const documentID = String(req.query.document_id || "").trim();

  if (!documentID) {
    return res.status(400).json({
      success: false,
      error_code: "MISSING_DOCUMENT_ID",
      message: "缺少 document_id。",
      request_id: requestID,
      retryable: false,
      fallback_available: false
    });
  }

  const data = prewarmQueue.getLatestJobForDocument(documentID);

  if (!data) {
    return res.status(404).json({
      success: false,
      error_code: "PREWARM_JOB_NOT_FOUND",
      message: "该资料暂无 AI 精讲预生成任务。",
      request_id: requestID,
      retryable: false,
      fallback_available: false
    });
  }

  return res.json({
    success: true,
    data,
    request_id: requestID
  });
});
```

- [ ] **Step 6: Add GET route by job id**

Add:

```js
router.get("/prewarm-document/:job_id", async (req, res) => {
  const requestID = resolveRequestID(req.headers["x-client-request-id"]);
  req.requestID = requestID;
  const jobID = String(req.params.job_id || "").trim();
  const data = prewarmQueue.getJobStatus(jobID);

  if (!data) {
    return res.status(404).json({
      success: false,
      error_code: "PREWARM_JOB_NOT_FOUND",
      message: "预生成任务不存在。",
      request_id: requestID,
      retryable: false,
      fallback_available: false
    });
  }

  return res.json({
    success: true,
    data,
    request_id: requestID
  });
});
```

In `DocumentExplainPrewarmQueue`, add:

```js
getLatestJobForDocument(documentID) {
  return this.store.getLatestPrewarmJobByDocumentID(documentID);
}
```

In `AIPersistentCacheStore`, add `getLatestPrewarmJobByDocumentID(document_id)` by selecting the newest row from `ai_document_prewarm_jobs` ordered by `created_at DESC`.

- [ ] **Step 7: Run route tests**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/backend"
node --test tests/prewarmDocumentRoutes.test.js
```

Expected:

```text
PASS 3 tests.
```

- [ ] **Step 8: Run full backend tests**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/backend"
npm test
```

Expected:

```text
All backend tests pass.
```

- [ ] **Step 9: Commit prewarm routes**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen"
git add backend/src/routes/ai.js backend/src/services/DocumentExplainPrewarmQueue.js backend/tests/prewarmDocumentRoutes.test.js
git commit -m "feat: add document explain prewarm API"
```

Expected:

```text
Commit created.
```

## Task 6: Add iOS Prewarm Client Service

**Files:**
- Create: `CuoTiBen/Sources/HuiLu/Services/DocumentExplainPrewarmService.swift`
- Modify only if needed: `CuoTiBen.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create prewarm models and service**

Create `CuoTiBen/Sources/HuiLu/Services/DocumentExplainPrewarmService.swift`:

```swift
import Foundation

struct DocumentExplainPrewarmSentencePayload: Codable, Equatable {
    let sentenceID: String
    let sentenceTextHash: String
    let text: String
    let context: String
    let anchorLabel: String
    let segmentID: String
    let pageIndex: Int
    let paragraphRole: String
    let paragraphTheme: String
    let questionPrompt: String
    let isCurrentPage: Bool
    let isKeySentence: Bool
    let isPassageSentence: Bool

    enum CodingKeys: String, CodingKey {
        case sentenceID = "sentence_id"
        case sentenceTextHash = "sentence_text_hash"
        case text
        case context
        case anchorLabel = "anchor_label"
        case segmentID = "segment_id"
        case pageIndex = "page_index"
        case paragraphRole = "paragraph_role"
        case paragraphTheme = "paragraph_theme"
        case questionPrompt = "question_prompt"
        case isCurrentPage = "is_current_page"
        case isKeySentence = "is_key_sentence"
        case isPassageSentence = "is_passage_sentence"
    }
}

struct DocumentExplainPrewarmStatus: Codable, Equatable {
    let jobID: String
    let documentID: String
    let status: String
    let totalCount: Int
    let readyCount: Int
    let failedCount: Int
    let processingCount: Int
    let queuedCount: Int

    var progressText: String {
        "AI 精讲生成中 \(readyCount) / \(max(totalCount, 1))"
    }

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case documentID = "document_id"
        case status
        case totalCount = "total_count"
        case readyCount = "ready_count"
        case failedCount = "failed_count"
        case processingCount = "processing_count"
        case queuedCount = "queued_count"
    }
}

struct DocumentExplainPrewarmEnvelope: Decodable {
    let success: Bool
    let data: DocumentExplainPrewarmStatus
    let requestID: String?

    enum CodingKeys: String, CodingKey {
        case success
        case data
        case requestID = "request_id"
    }
}

enum DocumentExplainPrewarmService {
    static func start(
        documentID: UUID,
        title: String,
        sentences: [DocumentExplainPrewarmSentencePayload],
        baseURL overrideBaseURL: String? = nil
    ) async throws -> DocumentExplainPrewarmStatus {
        let endpoint = try endpointURL(path: "ai/prewarm-document", overrideBaseURL: overrideBaseURL)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "document_id": documentID.uuidString,
            "title": title,
            "sentences": sentences
        ] as EncodableDictionary)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)
        return try JSONDecoder().decode(DocumentExplainPrewarmEnvelope.self, from: data).data
    }

    static func status(
        jobID: String,
        baseURL overrideBaseURL: String? = nil
    ) async throws -> DocumentExplainPrewarmStatus {
        let endpoint = try endpointURL(path: "ai/prewarm-document/\(jobID)", overrideBaseURL: overrideBaseURL)
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        try validateHTTP(response)
        return try JSONDecoder().decode(DocumentExplainPrewarmEnvelope.self, from: data).data
    }

    static func latest(
        documentID: UUID,
        baseURL overrideBaseURL: String? = nil
    ) async throws -> DocumentExplainPrewarmStatus {
        let path = "ai/prewarm-document/latest?document_id=\(documentID.uuidString)"
        let endpoint = try endpointURL(path: path, overrideBaseURL: overrideBaseURL)
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        try validateHTTP(response)
        return try JSONDecoder().decode(DocumentExplainPrewarmEnvelope.self, from: data).data
    }

    private static func endpointURL(path: String, overrideBaseURL: String?) throws -> URL {
        guard let url = AIBackendConfig.endpointURL(path: path, overrideBaseURL: overrideBaseURL) else {
            throw URLError(.badURL)
        }
        return url
    }

    private static func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
```

If `EncodableDictionary` does not exist, replace the encoded dictionary with a dedicated request struct:

```swift
private struct DocumentExplainPrewarmStartRequest: Encodable {
    let documentID: String
    let title: String
    let sentences: [DocumentExplainPrewarmSentencePayload]

    enum CodingKeys: String, CodingKey {
        case documentID = "document_id"
        case title
        case sentences
    }
}
```

Then encode `DocumentExplainPrewarmStartRequest(documentID: documentID.uuidString, title: title, sentences: sentences)`.

- [ ] **Step 2: Build to catch service compile issues**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen"
xcodebuild -quiet \
  -project "/Volumes/T7/IOS app develop/CuoTiBen/CuoTiBen.xcodeproj" \
  -scheme "CuoTiBen" \
  -configuration Debug \
  -sdk iphonesimulator \
  -arch arm64 \
  ONLY_ACTIVE_ARCH=YES \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

Expected:

```text
Build passes.
```

- [ ] **Step 3: Commit iOS service**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen"
git add CuoTiBen/Sources/HuiLu/Services/DocumentExplainPrewarmService.swift CuoTiBen.xcodeproj/project.pbxproj
git commit -m "feat: add iOS document prewarm client"
```

Expected:

```text
Commit created.
```

## Task 7: Start Prewarm From AppViewModel After Structured Source Loads

**Files:**
- Modify: `CuoTiBen/Sources/HuiLu/ViewModels/AppViewModel.swift`

- [ ] **Step 1: Add view model state**

In `AppViewModel`, add:

```swift
@Published private(set) var documentExplainPrewarmStatuses: [UUID: DocumentExplainPrewarmStatus] = [:]
private var documentExplainPrewarmTasks: [UUID: Task<Void, Never>] = [:]
private var documentExplainPrewarmJobIDs: [UUID: String] = [:]
```

- [ ] **Step 2: Add payload builder**

Add:

```swift
private func makePrewarmPayload(
    for document: SourceDocument,
    structuredSource: StructuredSource
) -> [DocumentExplainPrewarmSentencePayload] {
    structuredSource.sentences.enumerated().compactMap { index, sentence in
        guard sentence.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8 else { return nil }
        guard sentence.kind == .passageSentence, sentence.role == .body else { return nil }
        guard ![
            "heading",
            "question",
            "option",
            "vocabulary",
            "chineseInstruction",
            "bilingualNote"
        ].contains(sentence.kind.rawValue) else { return nil }

        return DocumentExplainPrewarmSentencePayload(
            sentenceID: sentence.id,
            sentenceTextHash: sentence.text.stableTextHash,
            text: sentence.text,
            context: nearbyContext(for: sentence, in: structuredSource),
            anchorLabel: sentence.anchorLabel,
            segmentID: sentence.segmentID,
            pageIndex: sentence.pageIndex,
            paragraphRole: sentence.role.rawValue,
            paragraphTheme: sentence.paragraphTheme,
            questionPrompt: "",
            isCurrentPage: index < 6,
            isKeySentence: sentence.isKeySentence,
            isPassageSentence: true
        )
    }
}
```

If `Sentence` does not expose these exact properties, map to the closest existing fields from `StructuredSource` and keep the outgoing JSON keys unchanged. The invariant is stricter than the concrete property names: only正文句 (`passageSentence` / `passageBody`) may enter the payload. Headings, questions, options, vocabulary notes, Chinese instructions, and bilingual notes must be excluded before the network request is built.

- [ ] **Step 3: Add start function**

Add:

```swift
private func startDocumentExplainPrewarmIfNeeded(
    for document: SourceDocument,
    structuredSource: StructuredSource
) {
    guard documentExplainPrewarmTasks[document.id] == nil else { return }
    let payload = makePrewarmPayload(for: document, structuredSource: structuredSource)
    guard !payload.isEmpty else { return }

    documentExplainPrewarmTasks[document.id] = Task { [weak self] in
        do {
            let status = try await DocumentExplainPrewarmService.start(
                documentID: document.id,
                title: document.title,
                sentences: payload
            )
            await MainActor.run {
                self?.documentExplainPrewarmStatuses[document.id] = status
                self?.documentExplainPrewarmJobIDs[document.id] = status.jobID
            }
            await self?.pollDocumentExplainPrewarmStatus(documentID: document.id, jobID: status.jobID)
        } catch {
            TextPipelineDiagnostics.log(
                "AI",
                "[AI][Prewarm] start failed doc=\(document.id) error=\(error.localizedDescription)",
                severity: .warning
            )
            await MainActor.run {
                self?.documentExplainPrewarmTasks[document.id] = nil
            }
        }
    }
}
```

- [ ] **Step 4: Add latest-job recovery**

Add:

```swift
private func recoverDocumentExplainPrewarmIfNeeded(for document: SourceDocument) {
    guard documentExplainPrewarmTasks[document.id] == nil else { return }
    guard documentExplainPrewarmStatuses[document.id] == nil else { return }

    documentExplainPrewarmTasks[document.id] = Task { [weak self] in
        do {
            let status = try await DocumentExplainPrewarmService.latest(documentID: document.id)
            await MainActor.run {
                self?.documentExplainPrewarmStatuses[document.id] = status
                self?.documentExplainPrewarmJobIDs[document.id] = status.jobID
            }
            await self?.pollDocumentExplainPrewarmStatus(documentID: document.id, jobID: status.jobID)
        } catch {
            await MainActor.run {
                self?.documentExplainPrewarmTasks[document.id] = nil
            }
        }
    }
}
```

Call this when recent documents are restored or when opening a document whose local `job_id` state is missing. A `404 PREWARM_JOB_NOT_FOUND` is not a document failure; it means the app may start a new prewarm job after structured sentences are available.

- [ ] **Step 5: Add polling**

Add:

```swift
private func pollDocumentExplainPrewarmStatus(documentID: UUID, jobID: String) async {
    for _ in 0..<60 {
        if Task.isCancelled { return }
        do {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            let status = try await DocumentExplainPrewarmService.status(jobID: jobID)
            await MainActor.run {
                documentExplainPrewarmStatuses[documentID] = status
            }
            if ["completed", "completed_with_errors", "failed"].contains(status.status) {
                break
            }
        } catch {
            TextPipelineDiagnostics.log(
                "AI",
                "[AI][Prewarm] poll failed doc=\(documentID) job_id=\(jobID) error=\(error.localizedDescription)",
                severity: .warning
            )
            break
        }
    }
    await MainActor.run {
        documentExplainPrewarmTasks[documentID] = nil
    }
}
```

- [ ] **Step 6: Call start function after structured source is ready**

In the `loadStructuredSource` success path where `structuredSources[document.id]` is assigned and document `processingStatus` becomes `.ready`, call:

```swift
startDocumentExplainPrewarmIfNeeded(for: updatedDocument, structuredSource: structuredSource)
```

Use the actual local variable names in that function. Do not call it before sentences are available.

- [ ] **Step 7: Build**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen"
xcodebuild -quiet \
  -project "/Volumes/T7/IOS app develop/CuoTiBen/CuoTiBen.xcodeproj" \
  -scheme "CuoTiBen" \
  -configuration Debug \
  -sdk iphonesimulator \
  -arch arm64 \
  ONLY_ACTIVE_ARCH=YES \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

Expected:

```text
Build passes.
```

- [ ] **Step 8: Commit AppViewModel prewarm orchestration**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen"
git add CuoTiBen/Sources/HuiLu/ViewModels/AppViewModel.swift
git commit -m "feat: start AI explain prewarm after import"
```

Expected:

```text
Commit created.
```

## Task 8: Surface Prewarm Status in Home and Detail Views

**Files:**
- Modify: `CuoTiBen/Sources/HuiLu/Views/HomeView.swift`
- Modify: `CuoTiBen/Sources/HuiLu/Views/SourceDetailSheets.swift`
- Modify: `CuoTiBen/Sources/HuiLu/Views/ReviewWorkbenchView.swift`

- [ ] **Step 1: Add Home card status copy**

In `HomeView.swift`, where recent material cards compute status text, add:

```swift
if let prewarmStatus = viewModel.documentExplainPrewarmStatuses[document.id],
   prewarmStatus.status == "queued" || prewarmStatus.status == "running" {
    Text(prewarmStatus.progressText)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AppPalette.primary)
}

Text("本地结构可用，可立即学习")
    .font(.footnote)
    .foregroundStyle(AppPalette.ink.opacity(0.68))
```

Keep existing card badges. Do not introduce raw enum strings into normal UI.
The document card must remain visible before prewarm starts, while prewarm is running, when some sentence jobs fail, and when the backend falls back to local structure.

- [ ] **Step 2: Add detail sheet status copy**

In `SourceDetailSheets.swift`, near the sentence explanation loading/fallback area, add:

```swift
if let prewarmStatus = viewModel.documentExplainPrewarmStatuses[document.id],
   prewarmStatus.status == "queued" || prewarmStatus.status == "running" {
    Text(prewarmStatus.progressText)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(AppPalette.primary)
}
```

If this file does not have direct access to `AppViewModel`, pass the status through the existing view initializer rather than using a global.
If a single sentence has `failed` status, show the local sentence context plus the existing retry entry. Do not mark the whole document as failed.

- [ ] **Step 3: Add review workbench status copy**

In `ReviewWorkbenchView.swift`, near the existing local fallback / sentence analysis state, add:

```swift
if let prewarmStatus = viewModel.documentExplainPrewarmStatuses[document.id],
   prewarmStatus.status == "queued" || prewarmStatus.status == "running" {
    Text(prewarmStatus.progressText)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(AppPalette.primary)
}
```

Keep the review flow usable when prewarm has only partial results. A failed sentence should only affect that sentence's AI explanation area.

- [ ] **Step 4: Build**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen"
xcodebuild -quiet \
  -project "/Volumes/T7/IOS app develop/CuoTiBen/CuoTiBen.xcodeproj" \
  -scheme "CuoTiBen" \
  -configuration Debug \
  -sdk iphonesimulator \
  -arch arm64 \
  ONLY_ACTIVE_ARCH=YES \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

Expected:

```text
Build passes.
```

- [ ] **Step 5: Static raw-debug check**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen"
grep -R "materialMode=pending" -n CuoTiBen/Sources/HuiLu/Views || true
grep -R "progress=" -n CuoTiBen/Sources/HuiLu/Views || true
grep -R "rawText=" -n CuoTiBen/Sources/HuiLu/Views || true
grep -R "sentenceDrafts=" -n CuoTiBen/Sources/HuiLu/Views || true
```

Expected:

```text
No matches in normal Home/detail UI. Existing diagnostic-only matches are acceptable if they are inside TextPipelineDiagnosticsView or a diagnostics sheet.
```

- [ ] **Step 6: Commit UI status**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen"
git add CuoTiBen/Sources/HuiLu/Views/HomeView.swift CuoTiBen/Sources/HuiLu/Views/SourceDetailSheets.swift CuoTiBen/Sources/HuiLu/Views/ReviewWorkbenchView.swift
git commit -m "feat: show AI explain prewarm progress"
```

Expected:

```text
Commit created.
```

## Task 9: Final Verification

**Files:**
- Verify all changed files from previous tasks.

- [ ] **Step 1: Run backend tests**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/backend"
npm test
```

Expected:

```text
All backend tests pass.
```

- [ ] **Step 2: Run iOS headless build**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen"
xcodebuild -quiet \
  -project "/Volumes/T7/IOS app develop/CuoTiBen/CuoTiBen.xcodeproj" \
  -scheme "CuoTiBen" \
  -configuration Debug \
  -sdk iphonesimulator \
  -arch arm64 \
  ONLY_ACTIVE_ARCH=YES \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

Expected:

```text
Build passes. Do not run xcodebuild test. Do not start simulator.
```

- [ ] **Step 3: Run static checks**

Run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen"
grep -R "prewarm-document" -n backend CuoTiBen/Sources/HuiLu
grep -R "AI_PREWARM" -n backend
grep -R "API key\\|Authorization" -n backend/src CuoTiBen/Sources/HuiLu || true
grep -R "materialMode=pending" -n CuoTiBen/Sources/HuiLu/Views || true
grep -R "progress=" -n CuoTiBen/Sources/HuiLu/Views || true
```

Expected:

```text
prewarm-document and AI_PREWARM references exist.
No API key or Authorization values appear in changed source files.
No raw materialMode/progress debug copy appears in normal views.
```

- [ ] **Step 4: Manual device acceptance**

On iPad device:

```text
1. Import an English PDF with at least 20 body sentences.
2. Confirm the document card appears immediately.
3. Confirm card or detail copy says 本地结构可用，可立即学习.
4. Confirm card or detail copy says AI 精讲生成中 x / n.
5. Tap a sentence that has generated and confirm AI 精讲 opens quickly.
6. Tap a sentence that is still processing and confirm local skeleton remains usable.
7. Confirm a failed sentence can be retried without hiding the document.
```

- [ ] **Step 5: Final commit if verification-only edits were needed**

If Task 9 required additional code edits, run:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen"
git status --short
git add <files changed by Task 9>
git commit -m "fix: stabilize document explain prewarm cache"
```

Expected:

```text
Commit created only if Task 9 changed files.
```

## Self-Review

- Spec coverage: The plan covers immediate open, backend prewarm jobs, persistent cache, cache key identity, click read order, prioritization, low concurrency, unchanged `/ai/explain-sentence`, new prewarm endpoints, UI progress copy, single-sentence failure isolation, no secrets, no canvas work, and verification.
- Placeholder scan: The plan has concrete paths, code blocks, commands, and expected outputs. No implementation step depends on an unspecified file.
- Type consistency: Backend status strings match the design. iOS status fields match JSON coding keys. `DocumentExplainPrewarmStatus.progressText` is the shared UI display entry.
