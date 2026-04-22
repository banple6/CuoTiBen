# AI Core 生产回归检查清单

## 范围

本清单用于 AI Core Rebuild 生产发布后的最小回归，不扩展为产品验收或 UI 走查。

## 发布基础

1. SSH 能登录 `root@47.94.227.58`
2. `systemctl is-active cuotiben-backend.service` 返回 `active`
3. 部署目录为 `/root/CuoTiBen/backend`
4. 备份目录存在且可回滚：`/www/backup/backend-<timestamp>`

## 健康检查

1. 服务器本机执行 `curl http://127.0.0.1/health`
2. 公网执行 `curl http://47.94.227.58/health`
3. 两次返回都满足：
   - `ok=true`
   - `ai_gateway.configured=true`
   - `ai_gateway.provider=claude`
   - `ai_gateway.model=claude-opus-4-6`
   - `ai_gateway.api_kind=anthropic-messages`
   - `ai_gateway.circuit_state=closed`

## explain-sentence smoke

请求：

```bash
curl -X POST http://47.94.227.58/ai/explain-sentence \
  -H 'Content-Type: application/json' \
  -d '{
    "client_request_id":"prod-regression-explain-1",
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

验收：

1. `success=true`
2. 返回 `request_id`
3. `meta.used_fallback=false`
4. `meta.provider=claude`
5. `meta.model=claude-opus-4-6`
6. `meta.circuit_state=closed`

## analyze-passage smoke

请求：

```bash
curl -X POST http://47.94.227.58/ai/analyze-passage \
  -H 'Content-Type: application/json' \
  -d '{
    "client_request_id":"prod-regression-analyze-1",
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

验收：

1. `success=true`
2. 返回 `request_id`
3. `meta.used_fallback=false`
4. `meta.provider=claude`
5. `meta.model=claude-opus-4-6`
6. `data.paragraph_cards` 非空

## 日志核对

1. `journalctl -u cuotiben-backend.service -n 100 --no-pager`
2. 可看到：
   - 服务启动日志
   - `/health` 命中
   - explain / analyze 请求日志
   - 成功 `request_id`
3. 不应看到：
   - `MODEL_CONFIG_MISSING`
   - `INVALID_MODEL_RESPONSE`
   - 服务启动崩溃或重启风暴

## 回滚条件

满足任一条即进入回滚判断：

1. `/health` 不返回 `configured=true`
2. explain-sentence 或 analyze-passage 连续失败
3. `meta.used_fallback=true` 且不是预期演练
4. `journalctl` 出现持续 5xx 或服务反复重启

## 回滚动作

1. `systemctl stop cuotiben-backend.service`
2. 恢复 `/www/backup/backend-<timestamp>` 到 `/root/CuoTiBen/backend`
3. `systemctl restart cuotiben-backend.service`
4. 重跑健康检查和两条 AI smoke
