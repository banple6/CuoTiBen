# AI Core Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重做 AI 请求网关、教授式单句解析、地图级全文分析、iOS identity loop、PassageMap 导图准入和思维导图工作台，并把 503/fallback/部署阻塞纳入完整验收。

**Architecture:** 先重做后端 AI Gateway，再重写 `explain-sentence` 和 `analyze-passage` contract，随后在 iOS 端建立 identity loop 与 fallback，再引入 `PassageMap + MindMap admission` 作为导图新数据核心，最后替换旧结构树工作台。旧 `legacyRemote / legacyLocal / fallbackLegacy / StructureTreePreview*` 不再作为主路径继续扩展。

**Tech Stack:** Node.js 20 + Express 5 + node:test + OpenAI-compatible HTTP client/provider abstraction + SwiftUI + Xcodebuild headless build verification

---

## 执行规则

- 每个 Phase 必须单独提交，不允许跨 Phase 混改
- 每个 Phase 完成后必须暂停汇报，等待确认，不自动进入下一 Phase
- 所有实现都必须遵守 TDD：先写失败测试，再写最小实现，再验证通过
- 在完成 `PassageMap + admission` 之前，不允许继续扩展旧结构树主路径
- 在未获得 SSH 权限之前，不允许声称线上部署完成
- 当前本机无法稳定运行 iOS Simulator；iOS 阶段不新增 XCTest target，不执行 `xcodebuild test`，统一通过 headless build、静态检查和真实活跃路径人工回归清单验收

## 全局不可跳过验收门

以下 8 条是全计划不可跳过的验收门，任何阶段完成都不能绕开它们：

1. **先建 AI Gateway，再重写业务 service**
   - 在 Phase 1 完成 `backend/src/models/*` 全套网关层后，才允许进入 `explainSentenceService.js` / `analyzePassageService.js` 的重写。
2. **`explain-sentence` 必须先写 contract test**
   - 在 Phase 2 先固定新返回结构测试，再改实现。
3. **`analyze-passage` 必须瘦到地图级**
   - 在 Phase 3 明确禁止返回句子级深讲字段。
4. **`PassageMap` 先落模型，再接 UI**
   - 在 Phase 5 完成域模型和 admission 之后，Phase 6 才能接 UI。
5. **`AnchorConsistencyValidator` 必须有可解释日志**
   - 在 Phase 5 输出节点级 admission 日志，并按阈值裁剪主导图。
6. **iOS identity loop 必须先做丢弃逻辑**
   - 在 Phase 4 先做 mismatch discard，再谈 UI 展示。
7. **503 不能只当错误，要当产品状态**
   - 在 Phase 4 和 Phase 6 都必须保证页面不空白、有骨架、有 retry、有 request_id。
8. **服务器部署放在最后一阶段**
   - 在 Phase 7 之前不执行线上部署；没有 SSH 权限时，最终报告只能写“本地验证通过，线上部署受 SSH 权限阻塞”。

## 当前前置阻塞

- 本地环境变量缺失：`NOVAI_API_KEY`、`AI_PROVIDER`、`AI_MODEL`、`AI_BASE_URL`、`AI_API_KIND`、`AI_TIMEOUT_MS`、`AI_MAX_RETRIES`、`AI_CIRCUIT_BREAKER_ENABLED`
- 生产服务器当前无法通过现有 SSH key/配置登录，具体地址见 deploy gate runbook

这些阻塞项不会阻止前 6 个阶段的本地实现与本地验证，但会阻止线上部署收口。

## 基线命令

在进入任何阶段前，先确认基线：

- 后端测试：
  - `cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/backend && npm test`
  - 期望：`8/8` 通过
- iOS 构建：
  - `cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild && xcodebuild -quiet -project '/Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/CuoTiBen.xcodeproj' -scheme 'CuoTiBen' -configuration Debug -sdk iphonesimulator -arch arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO build`
  - 期望：exit `0`，允许保留当前已知 warning，不能引入新编译错误

---

### Phase 0: Security cleanup gate

**目标：** 在任何功能实现前先完成安全清理门，确认仓库不再包含真实 key，`.env` 不进入 git，README/文档不保留明文凭证。

**真实文件：**
- Modify:
  - `.gitignore`
  - `CuoTiBen/README_zh.md`
  - 任何经 `git grep` 识别出包含真实 key/token 的 tracked 文档或代码文件
- Inspect only:
  - `backend/.env.example`
  - `README.md`
  - `docs/**/*`

- [ ] **Step 1: 扫描仓库中的敏感串**

Run:
```bash
cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild
git grep -n "sk-" .
git grep -n "apiKey" .
git grep -n "NOVAI_API_KEY" .
```

Expected: 允许命中变量名、接口字段名和 provider 配置字段；任何真实 key、token、`newapi_channel_conn` 凭证片段都必须进入清理清单。

- [ ] **Step 2: 清理 README / 文档 / 代码中的真实 key**

实现：
- 删除或脱敏 README/文档中的真实 key
- 保留 `.env.example`，但只保留变量名与占位说明
- 不提交 `.env`
- 不在日志、文档、示例请求里打印真实 key

- [ ] **Step 3: 强化 `.env` 忽略规则**

实现：
- 根级 `.gitignore` 覆盖通用 `.env` / `.env.*`
- 保留 `*.example` 和 `.env.example`
- 确认没有 tracked `.env`

- [ ] **Step 4: 跑 Phase 0 验证命令**

Run:
```bash
cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild
git grep -n "sk-" .
git ls-files '*.env'
git status --short
```

**测试命令：**
- 上述 `git grep`
- 上述 `git ls-files`

**验收标准：**
- 仓库中没有真实 key
- `.env` 不进 git
- README 不含真实 key
- `.env.example` 只保留变量名或占位说明

**回滚方式：**
- 提交后：`git revert <phase0_commit>`
- 未提交：
```bash
git restore .gitignore CuoTiBen/README_zh.md README.md
```

**我确认的下一步指令：**
- 只有在展示清理前后 `git grep` 结果摘要并确认仓库无真实 key 后，才允许进入 Phase 1。

---

### Phase 1: Backend AI Gateway

**目标：** 在不碰 UI 的前提下，先建立 provider-based AI Gateway，让所有后续业务 service 都只依赖统一入口、统一错误和统一 request metadata。

**真实文件：**
- Create:
  - `backend/src/models/modelRegistry.js`
  - `backend/src/models/providers/claudeProvider.js`
  - `backend/src/models/aiClient.js`
  - `backend/src/models/retryPolicy.js`
  - `backend/src/models/circuitBreaker.js`
  - `backend/src/models/responseCache.js`
  - `backend/src/models/errors.js`
  - `backend/tests/models/modelRegistry.test.js`
  - `backend/tests/models/aiClient.test.js`
  - `backend/tests/models/retryPolicy.test.js`
  - `backend/tests/models/circuitBreaker.test.js`
  - `backend/tests/models/responseCache.test.js`
  - `backend/tests/integration/aiGateway.preflight.test.js`
  - `backend/tests/integration/aiGateway.retry503.test.js`
  - `backend/tests/fixtures/mockAIProvider.js`
  - `backend/tests/fixtures/fakeTransport.js`
- Modify:
  - `backend/src/config/env.js`
  - `backend/src/lib/appError.js`
  - `backend/src/middleware/errorHandler.js`
  - `backend/src/routes/ai.js`
  - `backend/src/routes/health.js`
  - `backend/package.json`
- Test:
  - `backend/tests/models/*.test.js`
  - `backend/tests/integration/aiGateway.preflight.test.js`
  - `backend/tests/integration/aiGateway.retry503.test.js`

- [ ] **Step 1: 先写失败测试，固定网关行为**

测试覆盖：
- provider registry 查找
- 缺少 `NOVAI_API_KEY` 时 preflight 失败
- 503 时触发 retry
- 熔断打开后直接 fallback
- 响应包含 `request_id / retryable / fallback_available`
- 所有 retry / circuit breaker / cache 测试都使用 mock provider 或 fake transport，不依赖真实外部模型服务

Run:
```bash
cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/backend
npm test -- \
  tests/models/modelRegistry.test.js \
  tests/models/aiClient.test.js \
  tests/models/retryPolicy.test.js \
  tests/models/circuitBreaker.test.js \
  tests/models/responseCache.test.js \
  tests/integration/aiGateway.preflight.test.js \
  tests/integration/aiGateway.retry503.test.js
```

Expected: FAIL，原因应是新模块尚不存在或行为未实现。

- [ ] **Step 2: 重写环境配置与错误基类**

实现：
- `env.js` 只读取新环境变量：
  - `NOVAI_API_KEY`
  - `AI_PROVIDER`
  - `AI_MODEL`
  - `AI_BASE_URL`
  - `AI_API_KIND`
  - `AI_TIMEOUT_MS`
  - `AI_MAX_RETRIES`
  - `AI_CIRCUIT_BREAKER_ENABLED`
- `errors.js` 定义标准错误码与 503 结构化错误工厂
- `appError.js` 与 `errorHandler.js` 接入新的 metadata 字段

- [ ] **Step 3: 实现 provider 注册与 Claude provider**

实现：
- `modelRegistry.js` 注册 provider、model、api kind
- `providers/claudeProvider.js` 封装 `anthropic-messages`
- `aiClient.js` 提供统一请求入口：
  - `request_id`
  - `route_name`
  - `provider`
  - `model`
  - `payload_hash`
  - `timeout_ms`
  - `retry_count`

- [ ] **Step 4: 实现 retry / circuit breaker / cache**

实现：
- `retryPolicy.js`：429/500/502/503/504，最多 3 次，exponential backoff + jitter
- `circuitBreaker.js`：连续 3 次 503/timeout 后 open 30 秒，之后 half-open
- `responseCache.js`：统一缓存接口，支持 sentence/passage key 模式

- [ ] **Step 5: 接到路由与 health**

实现：
- `routes/ai.js` 只做 request validation + request_id 注入 + service 调用
- `routes/health.js` 返回网关健康概况，不泄露敏感信息

- [ ] **Step 6: 跑 Phase 1 验证命令**

Run:
```bash
cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/backend
node --check src/models/modelRegistry.js src/models/providers/claudeProvider.js src/models/aiClient.js src/models/retryPolicy.js src/models/circuitBreaker.js src/models/responseCache.js src/models/errors.js src/routes/ai.js src/middleware/errorHandler.js src/config/env.js
npm test -- \
  tests/models/modelRegistry.test.js \
  tests/models/aiClient.test.js \
  tests/models/retryPolicy.test.js \
  tests/models/circuitBreaker.test.js \
  tests/models/responseCache.test.js \
  tests/integration/aiGateway.preflight.test.js \
  tests/integration/aiGateway.retry503.test.js
```

**测试命令：**
- 上述 `node --check`
- 上述 `npm test`

**验收标准：**
- `npm test` 通过
- `node --check` 通过
- 缺少 `NOVAI_API_KEY` 时 `/ai/explain-sentence` 返回 `MODEL_CONFIG_MISSING`
- 503 mock 能触发 `retry -> circuit breaker -> fallback`
- 所有响应带 `request_id`
- 所有 retry / circuit breaker / cache 测试不得依赖真实外部模型服务
- 本阶段不改 `explainSentenceService.js` / `analyzePassageService.js` 的业务 contract

**回滚方式：**
- 如果本阶段已单独提交，执行 `git revert <phase1_commit>`
- 如果还未提交，执行：
```bash
git restore backend/src/config/env.js backend/src/lib/appError.js backend/src/middleware/errorHandler.js backend/src/routes/ai.js backend/src/routes/health.js backend/package.json
git clean -fd backend/src/models backend/tests/models backend/tests/integration
```

**我确认的下一步指令：**
- 只有在展示 `node --check`、`npm test` 和 preflight/503 mock 通过摘要后，才允许进入 Phase 2。

---

### Phase 2: explain-sentence contract rewrite

**目标：** 先用 contract test 固定教授式单句解析新结构，再重写 `explain-sentence` service，彻底退出旧松散字段主契约。

**真实文件：**
- Create:
  - `backend/tests/contracts/explainSentence.contract.test.js`
  - `backend/tests/integration/explainSentence.route.test.js`
- Modify:
  - `backend/src/services/explainSentenceService.js`
  - `backend/src/validators/explainSentence.js`
  - `backend/src/routes/ai.js`
  - `backend/tests/explainSentenceService.test.js`

- [ ] **Step 1: 先写 contract test**

固定返回字段：
- `identity`
- `original_sentence`
- `sentence_function`
- `core_skeleton`
- `faithful_translation`
- `teaching_interpretation`
- `chunk_layers`
- `grammar_focus`
- `misreading_traps`
- `exam_paraphrase_routes`
- `simpler_rewrite`
- `simpler_rewrite_translation`
- `mini_check`

并明确以下负例：
- 不允许只返回 `translation / main_structure / rewrite_example`
- 不允许返回 `[subject: ...]` 作为 UI 可见字段
- `grammar_focus` 主字段必须是中文字段

Run:
```bash
cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/backend
npm test -- tests/contracts/explainSentence.contract.test.js tests/integration/explainSentence.route.test.js
```

Expected: FAIL，因为 service 仍在输出旧 contract。

- [ ] **Step 2: 重写 explain-sentence validator**

实现：
- validator 强制接收 identity 输入：
  - `client_request_id`
  - `document_id`
  - `sentence_id`
  - `segment_id`
  - `sentence_text_hash`
  - `anchor_label`
- 如果缺少必填 identity 字段，返回结构化请求错误

- [ ] **Step 3: 重写 explainSentenceService**

实现：
- service 只通过 `aiClient.js` 调 provider
- prompt 输出围绕教授式讲解四阶段组织
- service 对模型响应做结构化压缩和中文主导净化
- service 回填 `identity`
- service 返回标准 route envelope 所需 metadata

- [ ] **Step 4: 接 explain-sentence 503/cache/fallback**

实现：
- sentence cache key 改为 `sentenceID + textHash`
- 503 时优先缓存
- 无缓存时返回结构化错误，由客户端展示本地骨架

- [ ] **Step 5: 跑 Phase 2 验证命令**

Run:
```bash
cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/backend
node --check src/services/explainSentenceService.js src/validators/explainSentence.js src/routes/ai.js
npm test -- \
  tests/explainSentenceService.test.js \
  tests/contracts/explainSentence.contract.test.js \
  tests/integration/explainSentence.route.test.js
```

**测试命令：**
- 上述 `node --check`
- 上述 `npm test`

**验收标准：**
- contract test 通过
- 不允许 response 只返回旧三件套
- 不允许返回 `[subject: ...]` 作为 UI 可见字段
- `grammar_focus` 主字段必须是中文字段
- 结构化响应中带 `request_id`
- `identity` 被原样回填

**回滚方式：**
- 提交后：`git revert <phase2_commit>`
- 未提交：
```bash
git restore backend/src/services/explainSentenceService.js backend/src/validators/explainSentence.js backend/src/routes/ai.js backend/tests/explainSentenceService.test.js
git clean -fd backend/tests/contracts backend/tests/integration
```

**我确认的下一步指令：**
- 只有在展示 `explain-sentence` contract 测试通过摘要后，才允许进入 Phase 3。

---

### Phase 3: analyze-passage map-level rewrite

**目标：** 把 `analyze-passage` 瘦身为地图级分析，与 `explain-sentence` 做硬边界切割。

**真实文件：**
- Create:
  - `backend/src/validators/analyzePassage.js`
  - `backend/tests/contracts/analyzePassage.contract.test.js`
  - `backend/tests/integration/analyzePassage.route.test.js`
- Modify:
  - `backend/src/services/analyzePassageService.js`
  - `backend/src/routes/ai.js`

- [ ] **Step 1: 先写 analyze-passage contract test**

固定允许字段：
- `passage_overview`
- `paragraph_cards`
- `key_sentence_ids`
- `question_links`

固定禁止字段：
- `grammar_focus`
- `faithful_translation`
- `teaching_interpretation`
- `core_skeleton`

Run:
```bash
cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/backend
npm test -- tests/contracts/analyzePassage.contract.test.js tests/integration/analyzePassage.route.test.js
```

Expected: FAIL，因为现有 service 仍然过胖、字段命名不完全匹配。

- [ ] **Step 2: 新增 analyze-passage validator**

实现：
- 最多 4 段
- 每段最多 700 字符
- `key_sentence_ids` 最多 6
- 非法输入直接返回结构化错误

- [ ] **Step 3: 重写 analyzePassageService**

实现：
- 只通过 `aiClient.js` 请求模型
- 输出 `PassageMap` 所需 DTO
- 不产出句子级深讲字段
- `key_sentence_ids` 用于后续按需触发 `explain-sentence`

- [ ] **Step 4: 跑 Phase 3 验证命令**

Run:
```bash
cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/backend
node --check src/services/analyzePassageService.js src/validators/analyzePassage.js src/routes/ai.js
npm test -- tests/contracts/analyzePassage.contract.test.js tests/integration/analyzePassage.route.test.js
```

**测试命令：**
- 上述 `node --check`
- 上述 `npm test`

**验收标准：**
- `analyze-passage` 不返回 `grammar_focus`
- `analyze-passage` 不返回 `faithful_translation`
- `analyze-passage` 不返回 `teaching_interpretation`
- 每次最多 4 段
- 每段最多 700 字符
- `key_sentence_ids` 最多 6
- route 响应带 `request_id`

**回滚方式：**
- 提交后：`git revert <phase3_commit>`
- 未提交：
```bash
git restore backend/src/services/analyzePassageService.js backend/src/routes/ai.js
git clean -fd backend/src/validators/analyzePassage.js backend/tests/contracts/analyzePassage.contract.test.js backend/tests/integration/analyzePassage.route.test.js
```

**我确认的下一步指令：**
- 只有在 `analyze-passage` 通过合同测试并证明“地图级、非句子级”后，才允许进入 Phase 4。

---

### Phase 4: iOS request identity loop + fallback skeleton with headless build verification

**目标：** 先把客户端请求身份闭环与 mismatch discard 做稳，再建立单句与全文的本地骨架 fallback，保证 503 是产品状态而不是空白错误。当前机器环境不依赖 iOS Simulator，只做活跃路径改造与 headless build 验证。

**真实文件：**
- Create:
  - `CuoTiBen/Sources/HuiLu/Services/AIRequestIdentity.swift`
  - `CuoTiBen/Sources/HuiLu/Services/AIResponseIdentityGuard.swift`
  - `CuoTiBen/Sources/HuiLu/Services/AIStructuredError.swift`
  - `CuoTiBen/Sources/HuiLu/Services/LocalSentenceFallbackBuilder.swift`
  - `CuoTiBen/Sources/HuiLu/Services/LocalPassageFallbackBuilder.swift`
- Modify:
  - `CuoTiBen/Sources/HuiLu/Services/AIExplainSentenceService.swift`
  - `CuoTiBen/Sources/HuiLu/Services/ProfessorAnalysisService.swift`
  - `CuoTiBen/Sources/HuiLu/ViewModels/AppViewModel.swift`
  - `CuoTiBen/Sources/HuiLu/ViewModels/ArchivistWorkspaceViewModel.swift`
  - `CuoTiBen/Sources/HuiLu/Views/SourceDetailSheets.swift`
  - `CuoTiBen/Sources/HuiLu/Views/ReviewWorkbenchView.swift`
  - `CuoTiBen/Sources/HuiLu/Views/ReviewSessionView.swift`

- [ ] **Step 1: 先建立 headless build gate**

Run:
```bash
cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild
xcodebuild -quiet \
  -project '/Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/CuoTiBen.xcodeproj' \
  -scheme 'CuoTiBen' \
  -configuration Debug \
  -sdk iphonesimulator \
  -arch arm64 \
  ONLY_ACTIVE_ARCH=YES \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

Expected: 必须能完成 headless build。若 build 本身不稳定，则停止本 Phase，不继续写业务实现。

- [ ] **Step 2: 先建立失败场景清单，并按活跃路径接线**

覆盖清单：
- `sentenceID` 不同，丢弃
- `textHash` 不同，丢弃
- `segmentID` 不同，丢弃
- `anchorLabel` 不同，丢弃
- 切换句子时旧 result 立即清空
- 503 时生成 sentence fallback skeleton
- 503 时生成 passage map fallback skeleton

Expected: 这些场景都必须在真实 ViewModel / Service 活跃路径里有对应实现和日志，不允许做死代码。

- [ ] **Step 3: 重写 explain 请求 DTO 与 identity 比对逻辑**

实现：
- 单句请求必须带：
  - `client_request_id`
  - `documentID`
  - `sentenceID`
  - `segmentID`
  - `sentenceTextHash`
  - `anchorLabel`
- 响应落地前做严格校验
- mismatch 一律丢弃

- [ ] **Step 4: 在 ViewModel 中先做旧结果清空**

实现：
- 切换句子时清空旧远端结果
- 正在加载状态与当前选中句强绑定
- 过期结果不能回填到当前 UI

- [ ] **Step 5: 补齐 sentence / passage fallback skeleton**

实现：
- 单句 fallback：原句、粗主干、翻译暂不可用提示、教学解读暂不可用提示、基础语块、基础易错点、重新获取按钮
- 全文 fallback：原文段落列表、基础段落角色、PassageMap 骨架

- [ ] **Step 6: 补齐 debug 日志**

实现：
- `request_id`
- `provider`
- `model`
- `error_code`
- `retry_count`
- `used_cache`
- `used_fallback`

- [ ] **Step 7: 跑 Phase 4 headless 验证命令**

Run:
```bash
cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild
xcodebuild -quiet \
  -project '/Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/CuoTiBen.xcodeproj' \
  -scheme 'CuoTiBen' \
  -configuration Debug \
  -sdk iphonesimulator \
  -arch arm64 \
  ONLY_ACTIVE_ARCH=YES \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

**测试命令：**
- `cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/backend && npm test`
- 上述 `xcodebuild build`
- `grep -nE 'client_request_id|sentence_id|segment_id|sentence_text_hash|anchor_label|request_id|used_fallback|used_cache|error_code' CuoTiBen/Sources/HuiLu/Services/AIExplainSentenceService.swift CuoTiBen/Sources/HuiLu/Services/ProfessorAnalysisService.swift CuoTiBen/Sources/HuiLu/ViewModels/AppViewModel.swift CuoTiBen/Sources/HuiLu/ViewModels/ArchivistWorkspaceViewModel.swift CuoTiBen/Sources/HuiLu/Views/SourceDetailSheets.swift CuoTiBen/Sources/HuiLu/Views/ReviewWorkbenchView.swift CuoTiBen/Sources/HuiLu/Views/ReviewSessionView.swift`
- `git diff -- CuoTiBen/Sources/HuiLu/Services/AIExplainSentenceService.swift CuoTiBen/Sources/HuiLu/Services/ProfessorAnalysisService.swift CuoTiBen/Sources/HuiLu/ViewModels/AppViewModel.swift CuoTiBen/Sources/HuiLu/ViewModels/ArchivistWorkspaceViewModel.swift CuoTiBen/Sources/HuiLu/Views/SourceDetailSheets.swift CuoTiBen/Sources/HuiLu/Views/ReviewWorkbenchView.swift CuoTiBen/Sources/HuiLu/Views/ReviewSessionView.swift`
- 人工回归清单：
  - 快速连续切换 3 个句子，只允许最后一句保留结果
  - 模拟后端返回 identity mismatch，确认 UI 丢弃且不污染当前句
  - 模拟 `MODEL_CONFIG_MISSING / UPSTREAM_503 / UPSTREAM_TIMEOUT / INVALID_MODEL_RESPONSE`，确认句子页和全文页都显示本地骨架且不空白
  - DEBUG 模式确认日志包含 `request_id / error_code / used_fallback`

**验收标准：**
- `sentenceID` 不同，丢弃
- `textHash` 不同，丢弃
- `segmentID` 不同，丢弃
- `anchorLabel` 不同，丢弃
- 切换句子时旧 result 立即清空
- 503 时解析页不空白
- 503 时有本地 sentence fallback
- 503 时有 passage map fallback

**回滚方式：**
- 提交后：`git revert <phase4_commit>`
- 未提交：
```bash
git restore CuoTiBen/Sources/HuiLu/Services/AIExplainSentenceService.swift \
  CuoTiBen/Sources/HuiLu/Services/ProfessorAnalysisService.swift \
  CuoTiBen/Sources/HuiLu/ViewModels/AppViewModel.swift \
  CuoTiBen/Sources/HuiLu/ViewModels/ArchivistWorkspaceViewModel.swift \
  CuoTiBen/Sources/HuiLu/Views/SourceDetailSheets.swift \
  CuoTiBen/Sources/HuiLu/Views/ReviewWorkbenchView.swift \
  CuoTiBen/Sources/HuiLu/Views/ReviewSessionView.swift
git clean -fd \
  CuoTiBen/Sources/HuiLu/Services/AIRequestIdentity.swift \
  CuoTiBen/Sources/HuiLu/Services/AIResponseIdentityGuard.swift \
  CuoTiBen/Sources/HuiLu/Services/AIStructuredError.swift \
  CuoTiBen/Sources/HuiLu/Services/LocalSentenceFallbackBuilder.swift \
  CuoTiBen/Sources/HuiLu/Services/LocalPassageFallbackBuilder.swift
```

**我确认的下一步指令：**
- 只有在 mismatch discard 和 fallback skeleton 通过 headless 验证与人工回归清单后，才允许进入 Phase 5。

---

### Phase 5: PassageMap + MindMap admission

**目标：** 先落地 `PassageMap` 域模型和 `MindMap admission`，让主导图数据入口与旧 `OutlineNode` 脱钩。

**真实文件：**
- Create:
  - `CuoTiBen/Sources/HuiLu/Models/PassageMap.swift`
  - `CuoTiBen/Sources/HuiLu/Models/ParagraphMap.swift`
  - `CuoTiBen/Sources/HuiLu/Models/MindMapNode.swift`
  - `CuoTiBen/Sources/HuiLu/Models/MindMapAdmissionResult.swift`
  - `CuoTiBen/Sources/HuiLu/Services/MindMapAdmissionService.swift`
  - `docs/superpowers/fixtures/passage-map-admission-fixtures.md`
  - `docs/superpowers/checklists/phase5-passage-map-manual-checklist.md`
- Modify:
  - `CuoTiBen/Sources/HuiLu/Models/StructuredSourceModels.swift`
  - `CuoTiBen/Sources/HuiLu/Services/AnchorConsistencyValidator.swift`
  - `CuoTiBen/Sources/HuiLu/Services/NormalizedDocumentConverter.swift`
  - `CuoTiBen/Sources/HuiLu/Services/ProfessorAnalysisService.swift`
  - `CuoTiBen/Sources/HuiLu/Views/TextPipelineDiagnosticsView.swift`

- [ ] **Step 1: 先写 PassageMap / admission fixture 与失败场景清单**

测试覆盖：
- 主导图只吃 `admission = mainline`
- `auxiliary` 默认折叠
- `rejected` 进入 diagnostics，不进主导图
- `consistencyScore < 0.75` 不进主导图
- `question / answer / vocabulary / chinese_instruction` 不进主线
- `coreSentenceID` 不属于当前段时，段落节点降级

Expected: 先用 fixture 固化 admission 输入/输出示例和 rejected reason；主导图、辅助层、拒绝层的边界必须在实现前写清楚。

- [ ] **Step 2: 创建 PassageMap 领域模型**

实现：
- `PassageMap`
- `ParagraphMap`
- `MindMapNode`
- `MindMapAdmissionResult`

- [ ] **Step 3: 重写 AnchorConsistencyValidator 输出可解释日志**

日志字段必须包含：
- `nodeID`
- `nodeType`
- `sourceSegmentID`
- `sourceSentenceID`
- `sourceKind`
- `hygieneScore`
- `consistencyScore`
- `admissionResult`
- `rejectedReason`

- [ ] **Step 4: 接 admission service**

实现：
- `PassageMap` -> candidate nodes -> admission -> mainline/auxiliary/rejected
- diagnostics 收集 rejected 原因

- [ ] **Step 5: 跑 Phase 5 headless 验证命令**

Run:
```bash
cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild
xcodebuild -quiet \
  -project '/Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/CuoTiBen.xcodeproj' \
  -scheme 'CuoTiBen' \
  -configuration Debug \
  -sdk iphonesimulator \
  -arch arm64 \
  ONLY_ACTIVE_ARCH=YES \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
grep -nE 'consistencyScore|admissionResult|rejectedReason|sourceSegmentID|sourceSentenceID|sourceKind|hygieneScore' \
  CuoTiBen/Sources/HuiLu/Services/AnchorConsistencyValidator.swift \
  CuoTiBen/Sources/HuiLu/Services/MindMapAdmissionService.swift \
  CuoTiBen/Sources/HuiLu/Models/MindMapAdmissionResult.swift
```

**测试命令：**
- 上述 `xcodebuild build`
- 上述 `grep`
- fixture/manual checklist：
  - `docs/superpowers/fixtures/passage-map-admission-fixtures.md`
  - `docs/superpowers/checklists/phase5-passage-map-manual-checklist.md`

**验收标准：**
- 主导图只吃 `admission = mainline`
- `auxiliary` 节点默认折叠
- `rejected` 节点进入 diagnostics，不进主导图
- `consistencyScore < 0.75` 的节点不进主导图
- `question / answer / vocabulary / chinese_instruction` 不进主线分支
- `coreSentenceID` 不属于当前段时，段落节点降级
- 每个 admission 决策都输出可解释日志

**回滚方式：**
- 提交后：`git revert <phase5_commit>`
- 未提交：
```bash
git restore \
  CuoTiBen/Sources/HuiLu/Models/StructuredSourceModels.swift \
  CuoTiBen/Sources/HuiLu/Services/AnchorConsistencyValidator.swift \
  CuoTiBen/Sources/HuiLu/Services/NormalizedDocumentConverter.swift \
  CuoTiBen/Sources/HuiLu/Services/ProfessorAnalysisService.swift \
  CuoTiBen/Sources/HuiLu/Views/TextPipelineDiagnosticsView.swift
git clean -fd \
  CuoTiBen/Sources/HuiLu/Models/PassageMap.swift \
  CuoTiBen/Sources/HuiLu/Models/ParagraphMap.swift \
  CuoTiBen/Sources/HuiLu/Models/MindMapNode.swift \
  CuoTiBen/Sources/HuiLu/Models/MindMapAdmissionResult.swift \
  CuoTiBen/Sources/HuiLu/Services/MindMapAdmissionService.swift \
  docs/superpowers/fixtures/passage-map-admission-fixtures.md \
  docs/superpowers/checklists/phase5-passage-map-manual-checklist.md
```

**我确认的下一步指令：**
- 只有在 `PassageMap` 与 admission 通过 headless 验证、fixture 校对和人工清单后，并且 diagnostics 能解释 rejected 原因后，才允许进入 Phase 6。

---

### Phase 6: MindMap workspace UI

**目标：** 用新的 `PassageMap + MindMap admission` 数据链替换旧结构树工作台，让思维导图 UI 不再直接依赖旧 `OutlineNode` 主链。

**真实文件：**
- Create:
  - `CuoTiBen/Sources/HuiLu/ViewModels/MindMapWorkspaceViewModel.swift`
  - `CuoTiBen/Sources/HuiLu/Views/MindMap/MindMapWorkspaceView.swift`
  - `CuoTiBen/Sources/HuiLu/Views/MindMap/MindMapCanvasView.swift`
  - `CuoTiBen/Sources/HuiLu/Views/MindMap/MindMapMiniMapView.swift`
  - `CuoTiBen/Sources/HuiLu/Views/MindMap/MindMapToolbar.swift`
  - `CuoTiBen/Sources/HuiLu/Views/MindMap/MindMapLayout.swift`
  - `docs/superpowers/fixtures/mindmap-workspace-fixtures.md`
  - `docs/superpowers/checklists/phase6-mindmap-workspace-manual-checklist.md`
- Modify:
  - `CuoTiBen/Sources/HuiLu/Views/SourceDetailView.swift`
  - `CuoTiBen/Sources/HuiLu/Views/SourceOutlineTab.swift`
  - `CuoTiBen/Sources/HuiLu/Views/ReviewWorkbenchView.swift`
  - `CuoTiBen/Sources/HuiLu/Views/Workspace/ArchivistWorkspaceView.swift`
  - `CuoTiBen/Sources/HuiLu/Views/StructureTreePreviewView.swift`
  - `CuoTiBen/Sources/HuiLu/Views/StructureTreePreviewCanvas.swift`
  - `CuoTiBen/Sources/HuiLu/Views/StructureTreePreviewLayout.swift`
  - `CuoTiBen/Sources/HuiLu/Views/StructureTreePreviewMiniMap.swift`
  - `CuoTiBen/Sources/HuiLu/Views/StructureTreePreviewToolbar.swift`

- [ ] **Step 1: 先写 ViewModel fixture 与失败场景清单**

测试覆盖：
- 只渲染 mainline 节点到主画布
- auxiliary 默认折叠
- rejected 不进入主图
- 503 时思维导图不空白，显示本地 passage map fallback

Expected: 先通过 fixture 固化主图、辅助层和 rejected 节点的展示预期，以及 503 fallback 时不空白的工作台状态。

- [ ] **Step 2: 创建新的 MindMap workspace 文件**

实现：
- 新建 `/Views/MindMap/*`
- 支持 `fitToContent`
- 支持 `focusCurrentNode`
- 支持 pinch zoom
- 支持 drag pan
- 支持 minimap
- 支持 compact / detailed
- 支持 lazy rendering / virtualization

- [ ] **Step 3: 把旧入口改接新工作台**

实现：
- `SourceDetailView` 主导航接新工作台
- `SourceOutlineTab` 成为薄适配层或直接转接
- `ReviewWorkbenchView` / `ArchivistWorkspaceView` 改吃 `PassageMap`
- 旧 `StructureTreePreview*` 只保留兼容包装，不再承载主逻辑

- [ ] **Step 4: 跑 Phase 6 headless 验证命令**

Run:
```bash
cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild
xcodebuild -quiet \
  -project '/Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/CuoTiBen.xcodeproj' \
  -scheme 'CuoTiBen' \
  -configuration Debug \
  -sdk iphonesimulator \
  -arch arm64 \
  ONLY_ACTIVE_ARCH=YES \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
grep -nE 'fitToContent|focusCurrentNode|minimap|compact|detailed|lazy|virtual' \
  CuoTiBen/Sources/HuiLu/ViewModels/MindMapWorkspaceViewModel.swift \
  CuoTiBen/Sources/HuiLu/Views/MindMap/MindMapWorkspaceView.swift \
  CuoTiBen/Sources/HuiLu/Views/MindMap/MindMapCanvasView.swift \
  CuoTiBen/Sources/HuiLu/Views/MindMap/MindMapMiniMapView.swift \
  CuoTiBen/Sources/HuiLu/Views/MindMap/MindMapToolbar.swift \
  CuoTiBen/Sources/HuiLu/Views/MindMap/MindMapLayout.swift
```

**测试命令：**
- 上述 `xcodebuild build`
- 上述 `grep`
- fixture/manual checklist：
  - `docs/superpowers/fixtures/mindmap-workspace-fixtures.md`
  - `docs/superpowers/checklists/phase6-mindmap-workspace-manual-checklist.md`

**验收标准：**
- 主导航叫“思维导图”
- 主导图只展示 mainline 节点
- auxiliary 默认折叠
- rejected 不进主导图
- 503 时思维导图不空白
- 503 时有 passage map fallback
- UI 不再继续用旧 `OutlineNode` 直接撑主思维导图

**回滚方式：**
- 提交后：`git revert <phase6_commit>`
- 未提交：
```bash
git restore \
  CuoTiBen/Sources/HuiLu/Views/SourceDetailView.swift \
  CuoTiBen/Sources/HuiLu/Views/SourceOutlineTab.swift \
  CuoTiBen/Sources/HuiLu/Views/ReviewWorkbenchView.swift \
  CuoTiBen/Sources/HuiLu/Views/Workspace/ArchivistWorkspaceView.swift \
  CuoTiBen/Sources/HuiLu/Views/StructureTreePreviewView.swift \
  CuoTiBen/Sources/HuiLu/Views/StructureTreePreviewCanvas.swift \
  CuoTiBen/Sources/HuiLu/Views/StructureTreePreviewLayout.swift \
  CuoTiBen/Sources/HuiLu/Views/StructureTreePreviewMiniMap.swift \
  CuoTiBen/Sources/HuiLu/Views/StructureTreePreviewToolbar.swift
git clean -fd \
  CuoTiBen/Sources/HuiLu/ViewModels/MindMapWorkspaceViewModel.swift \
  CuoTiBen/Sources/HuiLu/Views/MindMap \
  docs/superpowers/fixtures/mindmap-workspace-fixtures.md \
  docs/superpowers/checklists/phase6-mindmap-workspace-manual-checklist.md
```

**我确认的下一步指令：**
- 只有在新工作台通过 headless build、静态检查和人工清单，且主图只吃 mainline 节点后，才允许进入 Phase 7。

---

### Phase 7: Local verification + server deployment gate

**目标：** 先完成本地后端、本地 iOS、本地 curl、环境变量 preflight 的收口验证；只有拿到 SSH 权限后，才进入服务器部署。

**真实文件：**
- Modify:
  - `backend/src/routes/health.js`
  - `backend/src/app.js`
  - `CuoTiBen/Sources/HuiLu/Views/TextPipelineDiagnosticsView.swift`
  - `CuoTiBen/README_zh.md`（移除明文 key 泄露）
  - `backend/.env.example`
- Create:
  - `backend/tests/integration/localCurlSmoke.test.js`
  - `docs/superpowers/runbooks/ai-core-local-verify.md`
  - `docs/superpowers/runbooks/ai-core-server-deploy-gate.md`

- [ ] **Step 1: 清理安全问题**

实现：
- 从 `README_zh.md` 移除明文 key
- `.env.example` 改为新环境变量名
- 文档中禁止任何明文密钥示例

- [ ] **Step 2: 写本地 smoke test 与 runbook**

验证：
- `/health`
- `/ai/explain-sentence`
- `/ai/analyze-passage`
- 缺环境变量 preflight
- 本地 503 mock 回退

- [ ] **Step 3: 跑本地验证命令**

Run:
```bash
cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/backend
node --check src/**/*.js
npm test

PORT=3100 AI_PROVIDER=claude AI_MODEL=claude-opus-4-6 AI_BASE_URL=http://127.0.0.1:3199 AI_API_KIND=anthropic-messages AI_TIMEOUT_MS=30000 AI_MAX_RETRIES=3 AI_CIRCUIT_BREAKER_ENABLED=true node server.js
```

在另一个终端运行：
```bash
curl http://127.0.0.1:3100/health

curl -X POST http://127.0.0.1:3100/ai/explain-sentence \
  -H 'Content-Type: application/json' \
  -d '{"client_request_id":"local-check-1","document_id":"doc-1","sentence_id":"s-1","segment_id":"seg-1","sentence_text_hash":"abc","anchor_label":"P1-S1","title":"Demo","sentence":"This is a sentence.","context":"This is a sentence."}'

curl -X POST http://127.0.0.1:3100/ai/analyze-passage \
  -H 'Content-Type: application/json' \
  -d '{"client_request_id":"local-check-2","document_id":"doc-1","title":"Demo","paragraphs":[{"index":0,"text":"This is paragraph one."}],"key_sentence_ids":["s-1"]}'
```

- [ ] **Step 4: 跑本地 iOS 验证命令**

Run:
```bash
cd /Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild
xcodebuild -quiet \
  -project '/Volumes/T7/IOS app develop/CuoTiBen/.worktrees/ai-core-rebuild/CuoTiBen.xcodeproj' \
  -scheme 'CuoTiBen' \
  -configuration Debug \
  -sdk iphonesimulator \
  -arch arm64 \
  ONLY_ACTIVE_ARCH=YES \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

- [ ] **Step 5: 服务器部署 gate**

只有在拿到 SSH 权限后，才执行：
```bash
ssh root@<PRODUCTION_SERVER_HOST>
```

后续动作：
- 找到真实部署目录
- 识别运行方式：`systemd / pm2 / docker / node`
- 备份当前版本
- 上传新版后端
- 配置 `.env`
- 重启服务
- curl 线上 `/health`、`/ai/explain-sentence`、`/ai/analyze-passage`

如果仍然无法 SSH：
- 停止部署
- 记录“线上部署受 SSH 权限阻塞”
- 不得写“线上已完成”

**测试命令：**
- `node --check src/**/*.js`
- `npm test`
- 本地 `curl`
- `xcodebuild build`
- 如果有 SSH 权限，再跑线上 `curl`

**验收标准：**
- 本地后端通过
- 本地 iOS 通过
- 本地 curl 通过
- 环境变量 preflight 通过
- 未拿到 SSH 权限时，最终报告只能写：
  - “本地验证通过”
  - “线上部署受 SSH 权限阻塞”
- 不能写“线上已完成”

**回滚方式：**
- 本地验证文件提交后：`git revert <phase7_commit>`
- 若上线后需要回滚，按运行方式执行：
  - `systemd`：切回旧 release 并 `systemctl restart`
  - `pm2`：切回旧目录并 `pm2 restart`
  - `docker`：回滚到旧 image/tag
  - `node`：切回备份目录并重启进程

**我确认的下一步指令：**
- 只有在本地验证全部通过且 SSH 权限明确时，才允许执行线上部署；没有 SSH 权限时，本计划在本地验证完成处收口。

---

## 计划自检清单

执行本计划前，必须确认：

- [ ] 已覆盖 AI Gateway
- [ ] 已覆盖 `explain-sentence` identity loop
- [ ] 已覆盖 `PassageMap`
- [ ] 已覆盖 `MindMap admission`
- [ ] 已覆盖 `Structured 503 Error`
- [ ] 已覆盖本地 fallback
- [ ] 已明确服务器 SSH 阻塞
- [ ] 每个阶段都包含测试命令和验收标准

## 备注

- 本计划明确禁止“先碰 UI 再补后端”的顺序
- 本计划明确禁止在未完成 `PassageMap + admission` 前继续扩展旧结构树
- 本计划明确禁止在未获得 SSH 权限前声称线上部署完成
