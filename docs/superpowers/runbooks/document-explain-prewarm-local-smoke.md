# Document Explain Prewarm Local Smoke

本 runbook 用于本地验证文档级 AI 精讲预热接口、SQLite 持久缓存文件，以及 explain-sentence persistent cache 命中路径。该流程不需要真实密钥；模型上游故意指向不可用的本地端口，避免触发真实模型调用。

## 启动后端

在隔离 worktree 后端目录运行：

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/.worktrees/phase11b-persistent-cache/backend"

AI_CACHE_DB_PATH=".data/local-smoke-ai-cache.sqlite3" \
PORT=3100 \
AI_PROVIDER=claude \
AI_MODEL=claude-opus-4-6 \
MODEL_NAME=claude-opus-4-6 \
AI_BASE_URL="http://127.0.0.1:3999" \
AI_API_KIND=anthropic-messages \
AI_TIMEOUT_MS=3000 \
AI_MAX_RETRIES=1 \
AI_CIRCUIT_BREAKER_ENABLED=true \
npm start
```

`MODEL_NAME` 仍是 explain-sentence cache key 的优先模型名，`AI_MODEL` 是兼容 AI Gateway 风格配置的后备模型名。为了让 HTTP cache-hit smoke 的 seed cache 和 `/ai/explain-sentence` lookup 使用同一个 `model_name`，本地 smoke 建议同时设置两者。`AI_API_KIND=anthropic-messages` 时，后端会按 Anthropic Messages 形态调用模型上游；本地 smoke 仍故意把上游指向不可用端口，避免真实模型调用。

期望：

- 服务监听 `http://0.0.0.0:3100`。
- `.data/local-smoke-ai-cache.sqlite3` 可被创建。
- 不需要配置真实模型密钥。

## Health

```bash
curl -s http://127.0.0.1:3100/health | python3 -m json.tool
```

期望：

- `ok=true`
- `service=cuotiben-backend`
- 响应不包含敏感鉴权信息。

## 创建预热任务

```bash
curl -s -X POST http://127.0.0.1:3100/ai/prewarm-document \
  -H "Content-Type: application/json" \
  -d '{
    "document_id": "doc-smoke-prewarm",
    "title": "Prewarm Smoke",
    "client_request_id": "smoke-prewarm-001",
    "sentences": [
      {
        "sentence_id": "s-1",
        "sentence_text_hash": "hash-s-1",
        "text": "This is the first eligible body sentence.",
        "context": "This is the first eligible body sentence.",
        "anchor_label": "P1-S1",
        "segment_id": "seg-1",
        "page_index": 1,
        "paragraph_role": "passageBody",
        "paragraph_theme": "smoke",
        "question_prompt": "",
        "is_current_page": true,
        "is_key_sentence": true,
        "is_passage_sentence": true,
        "kind": "passageSentence"
      },
      {
        "sentence_id": "heading-1",
        "sentence_text_hash": "hash-heading-1",
        "text": "A Heading That Must Be Filtered",
        "anchor_label": "Heading",
        "segment_id": "seg-title",
        "page_index": 1,
        "paragraph_role": "heading",
        "is_current_page": false,
        "is_key_sentence": false,
        "is_passage_sentence": false,
        "kind": "heading"
      }
    ]
  }' | python3 -m json.tool
```

期望：

- `success=true`
- `request_id=smoke-prewarm-001`
- `data.job_id` 存在
- `data.total_count=1`
- heading 被 validator 过滤，不进入预热任务。
- 如果模型上游不可用，任务后续可以变为 `failed`，但创建和查询接口必须可用。

## 查询最新任务

```bash
curl -s "http://127.0.0.1:3100/ai/prewarm-document/latest?document_id=doc-smoke-prewarm" \
  | python3 -m json.tool
```

期望：

- `success=true`
- `data.document_id=doc-smoke-prewarm`
- `data.job_id` 存在
- `request_id` 存在

## 查询指定任务

把创建任务响应中的 `data.job_id` 填入：

```bash
curl -s "http://127.0.0.1:3100/ai/prewarm-document/<JOB_ID>" \
  | python3 -m json.tool
```

期望：

- `success=true`
- `data.job_id` 与请求一致
- 响应包含 `total_count`、`ready_count`、`failed_count`、`queued_count`、`processing_count`

## 非正文句拒绝

```bash
curl -s -X POST http://127.0.0.1:3100/ai/prewarm-document \
  -H "Content-Type: application/json" \
  -d '{
    "document_id": "doc-smoke-invalid",
    "title": "Invalid Prewarm",
    "sentences": [
      {
        "sentence_id": "heading-1",
        "sentence_text_hash": "hash-heading-1",
        "text": "Heading only",
        "kind": "heading",
        "paragraph_role": "heading",
        "is_passage_sentence": false
      }
    ]
  }' | python3 -m json.tool
```

期望：

- `success=false`
- `error_code=INVALID_PREWARM_DOCUMENT_REQUEST`
- `request_id` 存在

## SQLite 文件检查

```bash
ls -l .data/local-smoke-ai-cache.sqlite3*

node --input-type=module -e "import Database from 'better-sqlite3'; const db=new Database('.data/local-smoke-ai-cache.sqlite3', { readonly: true }); const tables=db.prepare('select name from sqlite_master where type=\\'table\\' order by name').all(); const documentJobs=db.prepare('select count(*) as count from ai_document_prewarm_jobs').get(); const sentenceJobs=db.prepare('select count(*) as count from ai_sentence_prewarm_jobs').get(); console.log(JSON.stringify({ tables: tables.map(row => row.name), document_jobs: documentJobs.count, sentence_jobs: sentenceJobs.count })); db.close();"
```

期望：

- SQLite 主文件和 WAL/SHM 文件可见。
- 表包含 `ai_document_prewarm_jobs`、`ai_sentence_explain_cache`、`ai_sentence_prewarm_jobs`。
- 创建过 smoke 任务后，document job 与 sentence job 数量大于 0。

## explain-sentence 持久缓存命中

HTTP 级命中验证需要先用 Store 写入一条 ready cache，再用同一组 `document_id + sentence_id + sentence_text_hash + prompt_version + model_name` 调用 `/ai/explain-sentence`。

期望：

- `/ai/explain-sentence` 返回 `success=true`
- route envelope 中 `used_cache=true`
- data 中 `used_cache=true`
- `request_id` 使用本次请求 ID，而不是写入缓存时的旧 ID。
- 后端日志不出现模型调用日志。

单元与集成测试也覆盖了该路径：

```bash
node --test tests/explainSentenceService.test.js tests/contracts/explainSentence.contract.test.js tests/integration/explainSentence.route.test.js
```

期望：全部通过。
