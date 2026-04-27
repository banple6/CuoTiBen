# Phase 11: Document-Level AI Explain Prewarm Cache Design

## Scope

This phase designs document-level AI sentence explanation prewarming. The product rule is:

> Imported material opens immediately. AI sentence explanations are generated in the background and filled into cache over time.

This design does not modify the existing `/ai/explain-sentence` response contract, the `/ai/analyze-passage` contract, the document parsing algorithm, the AI Gateway contract, or the notes/canvas workspace.

## Goals

- A document becomes usable as soon as local or remote document parsing produces structured sentences.
- The backend creates a document-level prewarm job after import.
- The backend stores sentence explanations in persistent cache, not only the current in-memory `AIResponseCache`.
- A sentence click reads from cache before making a live model request.
- Prewarm runs with low concurrency and priority ordering to avoid model gateway overload, upstream 503s, and user-visible timeouts.
- Single sentence failures are isolated to that sentence and never fail the whole imported document.
- Home and detail surfaces expose clear user-facing progress: `AI 精讲生成中 x / n` and `本地结构可用，可立即学习`.

## Non-Goals

- No UI restyle or visual redesign.
- No note canvas changes.
- No prompt tuning beyond using the existing sentence explain request path.
- No real API keys, Authorization headers, or secrets in logs, docs, tests, or fixtures.
- No `.env` files committed to git.
- No blocking import flow that waits for all AI explanations to finish.

## Current Context

The backend currently has:

- `backend/src/services/AIResponseCache.js`: in-memory cache with a 12-hour TTL.
- `backend/src/services/explainSentenceService.js`: existing single-sentence explain implementation, cache lookup, model call, and response normalization.
- `backend/src/routes/ai.js`: existing `/ai/explain-sentence`, `/ai/parse-source`, and `/ai/analyze-passage` routes.

The iOS app currently has:

- `CuoTiBen/Sources/HuiLu/Services/SentenceAnalysisCacheStore.swift`: memory and disk cache for sentence explanations.
- `CuoTiBen/Sources/HuiLu/Services/AIExplainSentenceService.swift`: `fetchExplanationWithCache` and single-flight behavior for per-sentence requests.
- `CuoTiBen/Sources/HuiLu/ViewModels/AppViewModel.swift`: document import, structured source storage, recent documents, and cached sentence lookup.
- `CuoTiBen/Sources/HuiLu/Views/HomeView.swift`: resource workbench card display and AI status display.
- `CuoTiBen/Sources/HuiLu/Views/SourceDetailSheets.swift` and `CuoTiBen/Sources/HuiLu/Views/ReviewWorkbenchView.swift`: sentence click/explain surfaces.

The gap is that cache warming only happens after a user requests a sentence. A slow model or upstream 503 then affects the interaction directly.

## Backend Persistent Cache

Use SQLite for the first persistent backend cache. The repository has no database layer today, so the implementation should create a small focused persistence module rather than introducing a broad ORM.

Recommended file:

- `backend/src/services/AIPersistentCacheStore.js`

Recommended dependency:

- `better-sqlite3`

Recommended environment variable:

- `AI_CACHE_DB_PATH`, defaulting to `backend/.data/ai-cache.sqlite3`

The persistent store must be accessed through a single backend singleton:

- `getAIPersistentCacheStore()`
- `resetAIPersistentCacheStoreForTests()`

Routes, queue services, and explain services must not each instantiate their own store. The singleton prevents route-level and service-level cache divergence and gives tests a controlled reset hook.

The prewarm model name must come from the current AI Gateway configuration layer, such as `getAIConfig()` or `modelRegistry`. New code must not introduce provider-specific naming in route or queue modules.

### Cache Key

The persistent sentence explain cache key must be derived from:

```text
document_id + sentence_id + sentence_text_hash + prompt_version + model_name
```

The generated stable hash is the primary lookup key. `document_id`, `sentence_id`, and `sentence_text_hash` remain separate columns for debugging, query, and job progress.

`prompt_version` must be explicit. The first backend prompt/cache version should be:

```text
sentence-explain.v2
```

If the prompt contract or normalization semantics change later, bump the version and leave old cache rows untouched.

### Tables

```sql
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
```

`ready_count + failed_count + queued_count + processing_count` is recalculated from `ai_sentence_prewarm_jobs` after each state transition.

### Cache Write Rules

The cache stores only successful remote AI results that match the current `/ai/explain-sentence` contract data shape.

- `used_fallback=true` is never written as `ready`.
- Local skeleton or fallback content is never stored as a successful AI explanation.
- Failed prewarm attempts only write `status='failed'`, `error_code`, `request_id`, and `updated_at`.
- A later successful foreground or background request may overwrite the failed status with `ready`.

### Queue Crash Recovery

On backend startup, the prewarm queue must repair persisted state before accepting new jobs:

- Any `ai_sentence_prewarm_jobs.status='processing'` row from a previous process is moved back to `queued`.
- Any stale `processing` row older than the configured timeout is moved back to `queued`.
- Any `ai_document_prewarm_jobs.status='running'` job is recalculated from sentence rows.
- Jobs with queued work become `queued` or `running` when the worker restarts.
- Jobs with no queued or processing rows become `completed`, `completed_with_errors`, or `failed` based on row counts.

## Backend API Contract

The existing endpoint remains unchanged:

```text
POST /ai/explain-sentence
```

It should be enhanced internally to read/write the persistent cache before/after the existing in-memory cache. The response shape remains unchanged.

### POST /ai/prewarm-document

Creates or resumes a document-level prewarm job.

Request:

```json
{
  "document_id": "FB864042-2933-4FE6-AED4-2FAFDFD5BB19",
  "title": "2002考研英语真题",
  "client_request_id": "optional-client-request-id",
  "sentences": [
    {
      "sentence_id": "sen_3",
      "sentence_text_hash": "a5d3f15b3c500c9e",
      "text": "If you intend using humor in your talk to make people smile...",
      "context": "Optional local context around the sentence.",
      "anchor_label": "第 1 页 第 3 句",
      "segment_id": "seg_1",
      "page_index": 1,
      "paragraph_role": "support",
      "paragraph_theme": "humor in public speaking",
      "question_prompt": "",
      "is_current_page": true,
      "is_key_sentence": false,
      "is_passage_sentence": true
    }
  ]
}
```

Response:

```json
{
  "success": true,
  "data": {
    "job_id": "prewarm_48712EB8_20260427T040614Z",
    "document_id": "FB864042-2933-4FE6-AED4-2FAFDFD5BB19",
    "status": "queued",
    "total_count": 117,
    "ready_count": 0,
    "failed_count": 0,
    "processing_count": 0,
    "queued_count": 117
  },
  "request_id": "server-request-id",
  "used_cache": false,
  "used_fallback": false
}
```

Validation:

- `document_id` is required.
- `sentences` must be non-empty after filtering.
- Each sentence must include `sentence_id`, `sentence_text_hash`, and `text`.
- Non-passage rows are skipped, not failed.
- Duplicate sentence identities are collapsed by `sentence_id + sentence_text_hash`.

### GET /ai/prewarm-document/:job_id

Returns aggregate job status plus optional sentence-level statuses.

Response:

```json
{
  "success": true,
  "data": {
    "job_id": "prewarm_48712EB8_20260427T040614Z",
    "document_id": "FB864042-2933-4FE6-AED4-2FAFDFD5BB19",
    "status": "running",
    "total_count": 117,
    "ready_count": 12,
    "failed_count": 1,
    "processing_count": 2,
    "queued_count": 102,
    "sentences": [
      {
        "sentence_id": "sen_3",
        "sentence_text_hash": "a5d3f15b3c500c9e",
        "status": "ready",
        "error_code": null,
        "request_id": "sentence-request-id"
      }
    ]
  },
  "request_id": "server-request-id"
}
```

### GET /ai/prewarm-document/latest?document_id=...

Returns the newest prewarm job for a document. iOS uses this after app restart or memory eviction to recover the current job id and progress.

Request:

```text
GET /ai/prewarm-document/latest?document_id=FB864042-2933-4FE6-AED4-2FAFDFD5BB19
```

Response:

```json
{
  "success": true,
  "data": {
    "job_id": "prewarm_48712EB8_20260427T040614Z",
    "document_id": "FB864042-2933-4FE6-AED4-2FAFDFD5BB19",
    "status": "running",
    "total_count": 117,
    "ready_count": 12,
    "failed_count": 1,
    "processing_count": 2,
    "queued_count": 102
  },
  "request_id": "server-request-id"
}
```

If no job exists, return `404 PREWARM_JOB_NOT_FOUND`. This is not a document failure; iOS can start a new prewarm job for that document.

## Prewarm Prioritization

The queue should only prewarm eligible passage sentences. iOS payload creation and backend validation must allow only `passageSentence` / `passageBody` rows into the queue.

The following kinds are excluded:

- heading
- question
- option
- vocabulary
- chineseInstruction
- bilingualNote
- answer key
- page header/footer
- local skeleton-only node

Priority order:

1. Current page sentences.
2. First 10-20 body sentences.
3. Key sentences provided by passage analysis or local structural heuristics.
4. Remaining body sentences in document order.

Concurrency defaults:

- `AI_PREWARM_CONCURRENCY=2`
- `AI_PREWARM_MAX_SENTENCES_PER_DOCUMENT=200`

If a document has more than the configured maximum, the queue prewarms the highest-priority subset and leaves the rest available for on-demand generation.

## Sentence Click Read Order

When a user taps a sentence:

1. iOS local memory/disk cache via `SentenceAnalysisCacheStore`.
2. Existing `/ai/explain-sentence` request, which now checks backend persistent cache before calling the model.
3. If iOS knows the sentence is queued or processing through prewarm job status, show `AI 精讲生成中` and keep local skeleton visible.
4. If the user explicitly requests refresh or the sentence is not queued, make the normal single-sentence request.

This preserves the existing single-sentence path while allowing cached backend results to return quickly.

## iOS Integration

Add a small client service:

- `CuoTiBen/Sources/HuiLu/Services/DocumentExplainPrewarmService.swift`

Responsibilities:

- Build `POST /ai/prewarm-document` payload from `StructuredSource`, `SourceDocument`, and sentence metadata.
- Filter only `passageSentence` / `passageBody` rows. Headings, questions, options, vocabulary notes, Chinese instructions, and bilingual notes must not enter the payload.
- Store returned `job_id` in `AppViewModel` state.
- Poll `GET /ai/prewarm-document/:job_id` while the document is visible or recently imported.
- Recover the latest job with `GET /ai/prewarm-document/latest?document_id=...` after app restart or when local `job_id` state is missing.
- Expose aggregate progress and sentence status to Home and detail views.

Update `AppViewModel` only as the orchestration owner:

- After `loadStructuredSource` finishes with usable sentences, start prewarm in the background.
- Do not block document readiness.
- Maintain `documentExplainPrewarmStatuses: [UUID: DocumentExplainPrewarmStatus]`.
- Continue to use `AIExplainSentenceService.fetchExplanationWithCache` for on-demand sentence taps.

Update Home and detail surfaces:

- Home card: `AI 精讲生成中 x / n` while running.
- Home card: `本地结构可用，可立即学习` whenever structured local content exists.
- Source detail: show a compact status near sentence explanation entry point.
- Failure: `部分句子精讲失败，可单句重试`.
- A document card is visible before prewarm starts, while prewarm runs, and after prewarm partially fails.

No UI styling overhaul is included.

## Failure Handling

- A failed sentence writes `status='failed'`, `error_code`, and `request_id` to `ai_sentence_prewarm_jobs`.
- The document job becomes `completed_with_errors` if at least one sentence failed but at least one sentence completed or all queued work is done.
- The existing `/ai/explain-sentence` fallback behavior remains unchanged for foreground single-sentence requests.
- Prewarm must not store local fallback skeleton as a successful AI result. Only successful `remoteAI` results with `used_fallback=false` become `ready`.
- Network/model failures are retryable per sentence, not per document.

## Security and Privacy

- Do not write API keys, Authorization headers, or raw provider credentials to persistent cache.
- Store model name, prompt version, request id, error code, and normalized AI result only.
- Logs must include document id, sentence id, status, request id, and error code, but not secrets.

## Testing Strategy

Backend:

- Unit-test persistent cache initialization, ready/failed writes, and cache key stability.
- Unit-test prewarm validator filtering and duplicate collapse.
- Unit-test `POST /ai/prewarm-document` job creation.
- Unit-test `GET /ai/prewarm-document/:job_id` aggregate counts.
- Unit-test `GET /ai/prewarm-document/latest?document_id=...` recovery.
- Unit-test crash recovery moves stale or abandoned processing rows back to queued and recalculates running jobs.
- Unit-test that existing `/ai/explain-sentence` returns persistent cache hits without invoking the model.
- Unit-test that failed prewarm sentence does not fail the job.

iOS:

- Unit-level tests are not added in this phase unless an existing test target already covers the service.
- Validate by headless build and static checks.
- Manual device validation confirms immediate document open and background progress copy.

## Verification Commands

Backend:

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/backend"
npm test
```

iOS build:

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

Static checks:

```bash
grep -R "prewarm-document" -n backend CuoTiBen/Sources/HuiLu
grep -R "AI_PREWARM" -n backend
grep -R "API key\\|Authorization" -n backend/src CuoTiBen/Sources/HuiLu || true
```

## Open Risks

- `better-sqlite3` is a native dependency. Server deployment must confirm install works on the production Node/runtime image.
- Server deployment must verify Node 20, native dependency compilation, writable `.data` directory, and configured `AI_CACHE_DB_PATH`.
- Model gateway latency can still make full-document prewarm slow. Low concurrency reduces failures but increases total completion time.
- Background jobs are in-process in the first design. If the backend runs multiple processes later, job claiming must be made process-safe through SQLite row locking or a separate worker service.
- iOS can lose in-memory `job_id` state after app termination; this is mitigated by the latest-job recovery endpoint.
