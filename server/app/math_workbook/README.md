# Math workbook storage

## 身份边界

临时开发身份默认关闭（fail-closed）。未设置 `APP_ENV` 时按 `production` 处理；只有 `APP_ENV=development` 或 `APP_ENV=test`，并且显式设置 `MATH_ALLOW_DEV_USER_HEADER=true` 时，数学接口才接受 `X-User-Id`。`production`、`staging` 等环境即使开关为 `true` 也不会启用。正式认证适配器尚未接入，因此未满足上述开发条件时接口返回 `MATH_AUTH_REQUIRED`。

Run schema migration explicitly before enabling the math APIs:

`python -m app.math_workbook.migrations.runner --database .data/math_workbook/math_workbook.sqlite3`

The service never creates or alters business tables. An older phase-one database is detected as version 1 and upgraded in place by migration 2; no evidence tables are dropped.

SQLite job claiming uses `BEGIN IMMEDIATE`, a five-second SQLite busy timeout, and a lease timestamp. It safely serializes competing local processes on one SQLite database, but is not a distributed queue and must not be used across independently replicated database files.

`Idempotency-Key` is optional for the import endpoint. When supplied it is scoped by user and operation and is persisted with a hash of source type, original filename, and file SHA-256. A reused key with a different request is rejected.

Import reservations use `processing`, `completed`, and `failed` states. A failed
reservation or an expired `processing` reservation can be atomically reclaimed
by the same user, operation, key, and request hash; each attempt is counted.
The importer removes its committed file/row graph when preprocessing or the
upstream parser fails. Decoded math images are checked before conversion with
`MATH_MAX_IMAGE_WIDTH`, `MATH_MAX_IMAGE_HEIGHT`, and `MATH_MAX_IMAGE_PIXELS`.

第五阶段 A.5 的教学讲解只接受当前 `verified` VerificationReport。数据库迁移至 11 后启用：

`POST /api/v1/math-problems/{id}/explanation`

`GET /api/v1/math-problems/{id}/explanation`

默认 `MATH_EXPLANATION_PROVIDER=mock`，显式设置为 `deepseek` 才会走后端 DeepSeek 适配器。Prompt/Schema 为 v2：模型只负责 prose，答案、AST、LaTeX、步骤、规则、checks 和质量状态全部由服务端拥有。`math_explanations` 的 UPDATE 仍被触发器拒绝；迁移 0010 为三个父工件增加受控级联 DELETE，业务删除只能通过 `DELETE /api/v1/math-problems/{id}`、`DELETE /api/v1/math-imports/{id}` 或 `DELETE /api/v1/math-account`，并在提交事务后清理存储根目录内的文件。

服务端确定性 trace 使用固定白名单规则和稳定 AST LaTeX renderer v1，并绑定 problem/source revision/candidate/verification/input hash。DeepSeek 只在 `MATH_EXPLANATION_LIVE_TEST=1`、provider 为 deepseek 且配置了 key 时执行七样本 canary：

`cd server && MATH_EXPLANATION_PROVIDER=deepseek MATH_EXPLANATION_LIVE_TEST=1 DEEPSEEK_API_KEY="..." .venv313/bin/python -m tests.live_test_deepseek_explanation`
