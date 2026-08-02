# Math workbook storage

Run schema migration explicitly before enabling the math APIs:

`python -m app.math_workbook.migrations.runner --database .data/math_workbook/math_workbook.sqlite3`

The service never creates or alters business tables. An older phase-one database is detected as version 1 and upgraded in place by migration 2; no evidence tables are dropped.

SQLite job claiming uses `BEGIN IMMEDIATE`, a five-second SQLite busy timeout, and a lease timestamp. It safely serializes competing local processes on one SQLite database, but is not a distributed queue and must not be used across independently replicated database files.

`Idempotency-Key` is optional for the import endpoint. When supplied it is scoped by user and operation and is persisted with a hash of source type, original filename, and file SHA-256. A reused key with a different request is rejected.

第五阶段 A 的教学讲解只接受当前 `verified` VerificationReport。数据库迁移至 9 后启用：

`POST /api/v1/math-problems/{id}/explanation`

`GET /api/v1/math-problems/{id}/explanation`

默认 `MATH_EXPLANATION_PROVIDER=mock`，显式设置为 `deepseek` 才会走后端 DeepSeek 适配器。模型输入只含确认题干、ProblemIR、verified_result、确定性 trace、通过的 checks 和教学档案；服务端会校验结构化 JSON，并拒绝任何修改最终答案或引入未授权规则的输出。`math_explanations` 为追加不可变工件，同一验证报告、输入、模型、Prompt、Schema 和教学配置复用已有结果。
