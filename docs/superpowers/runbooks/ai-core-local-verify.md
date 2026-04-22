# AI Core 本地验收 Runbook

## 范围

本 runbook 只覆盖 Phase 7 本地验收，不引入新功能，不依赖真实上游密钥。

## 安全要求

- 不要把真实 `NOVAI_API_KEY` 写进仓库、文档、截图或命令历史。
- 真实 key 只放本地 shell 环境或服务器 `.env`。
- 如果没有 fake upstream，可先跑本地测试；真实上游 curl 验证应跳过。

## 推荐先跑自动化

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/backend"
find src -name "*.js" -print0 | xargs -0 -n1 node --check
npm test
npm test -- tests/integration/localCurlSmoke.test.js
```

## 启动本地服务

先准备一个本地 fake upstream 监听 `127.0.0.1:3199`。如果没有 fake upstream，不要把下面命令改成真实 key 版本写进文档或终端历史。

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/backend"

PORT=3100 \
AI_PROVIDER=claude \
AI_MODEL=claude-opus-4-6 \
AI_BASE_URL=http://127.0.0.1:3199 \
AI_API_KIND=anthropic-messages \
AI_TIMEOUT_MS=30000 \
AI_MAX_RETRIES=3 \
AI_CIRCUIT_BREAKER_ENABLED=true \
NOVAI_API_KEY=test-token \
node server.js
```

## 验证 health

```bash
curl http://127.0.0.1:3100/health
```

期望返回 `ai_gateway` 摘要，且不包含 `NOVAI_API_KEY` 或 `Authorization`。

## 验证 explain-sentence

```bash
curl -X POST http://127.0.0.1:3100/ai/explain-sentence \
  -H 'Content-Type: application/json' \
  -d '{
    "client_request_id":"local-check-1",
    "document_id":"doc-1",
    "sentence_id":"s-1",
    "segment_id":"seg-1",
    "sentence_text_hash":"abc",
    "anchor_label":"P1-S1",
    "title":"Demo",
    "sentence":"This is a sentence.",
    "context":"This is a sentence."
  }'
```

期望：

- 返回 `request_id`
- `meta.used_fallback` 可见
- fake upstream 正常时返回结构化 `data`

## 验证 analyze-passage

```bash
curl -X POST http://127.0.0.1:3100/ai/analyze-passage \
  -H 'Content-Type: application/json' \
  -d '{
    "client_request_id":"local-check-2",
    "document_id":"doc-1",
    "content_hash":"content-abc",
    "title":"Demo",
    "paragraphs":[
      {
        "segment_id":"seg-1",
        "index":0,
        "anchor_label":"P1",
        "text":"This is paragraph one.",
        "source_kind":"passage_body",
        "hygiene_score":0.9
      }
    ]
  }'
```

期望：

- 返回 `request_id`
- `meta.used_fallback` 可见
- `paragraph_cards` / `key_sentence_ids` 存在

## MODEL_CONFIG_MISSING 验证

不要写真实 key。新开一个 shell，故意不传 `NOVAI_API_KEY` 启动服务，再调用：

```bash
curl -X POST http://127.0.0.1:3100/ai/explain-sentence \
  -H 'Content-Type: application/json' \
  -d '{
    "client_request_id":"local-check-missing",
    "document_id":"doc-1",
    "sentence_id":"s-missing",
    "segment_id":"seg-1",
    "sentence_text_hash":"missing-abc",
    "anchor_label":"P1-S1",
    "title":"Demo",
    "sentence":"This is a sentence.",
    "context":"This is a sentence."
  }'
```

期望：

- HTTP `503`
- `error_code=MODEL_CONFIG_MISSING`
- `fallback_available=true`
- 服务仍能访问 `/health`

## fake 503 / fallback 验证

让 fake upstream 连续返回 `503`，再调用 `/ai/explain-sentence`。期望：

- HTTP `200`
- 返回 `request_id`
- `meta.used_fallback=true`
- `meta.circuit_state=open`
- 随后 `curl http://127.0.0.1:3100/health` 可见 `ai_gateway.circuit_state=open`

## iOS 本地构建

```bash
cd "/Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild"

xcodebuild -quiet \
  -project "/Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/CuoTiBen.xcodeproj" \
  -scheme "CuoTiBen" \
  -configuration Debug \
  -sdk iphonesimulator \
  -arch arm64 \
  ONLY_ACTIVE_ARCH=YES \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

## 本地最终验收清单

1. `backend npm test` 通过
2. `node --check` 通过
3. `localCurlSmoke` 通过
4. `/health` 有 `ai_gateway`
5. `/ai/explain-sentence` 返回 `request_id`
6. `/ai/analyze-passage` 返回 `request_id`
7. `MODEL_CONFIG_MISSING` 返回 `fallback_available=true`
8. fake `503` 会 fallback
9. iOS headless build 通过
10. iOS 静态检查通过
11. 不存在 `XCTest target`
12. 不存在真实 key 泄露
