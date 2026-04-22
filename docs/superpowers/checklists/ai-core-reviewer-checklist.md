# AI Core Reviewer Checklist

本清单用于 AI Core Rebuild 的最终人工审阅入口，覆盖 backend、iOS、MindMap、安全和生产发布记录。

## A. Backend AI Gateway

- [ ] modelRegistry 只从环境变量读取 provider 配置
- [ ] claudeProvider 不打印、不暴露 API key
- [ ] aiClient 带 request_id / retry_count / used_cache / used_fallback
- [ ] retryPolicy 覆盖 429 / 500 / 502 / 503 / 504
- [ ] circuitBreaker 在连续 503 / timeout 后 open
- [ ] responseCache 按 sentenceID+hash / documentID+hash 缓存
- [ ] /health 返回 ai_gateway 摘要但不泄露 key
- [ ] MODEL_CONFIG_MISSING 返回 fallback_available=true
- [ ] fake 503 能进入 retry -> breaker -> fallback

## B. explain-sentence contract

- [ ] 公共响应使用 professor-style 新 contract
- [ ] response 带 request_id
- [ ] data.identity 原样回填
- [ ] original_sentence 固定为请求句子
- [ ] faithful_translation 与 teaching_interpretation 分开
- [ ] core_skeleton 不暴露 [subject:] / [predicate:] bracket
- [ ] grammar_focus 主字段中文化
- [ ] 503 / timeout / invalid model response 有 fallback skeleton
- [ ] 旧 translation / main_structure / rewrite_example 不作为公共主 contract

## C. analyze-passage contract

- [ ] analyze-passage 只返回地图级 contract
- [ ] 包含 passage_overview / paragraph_cards / key_sentence_ids / question_links
- [ ] 不返回 grammar_focus
- [ ] 不返回 faithful_translation
- [ ] 不返回 teaching_interpretation
- [ ] 不返回 core_skeleton
- [ ] 不返回 chunk_layers
- [ ] 每次最多 4 段
- [ ] 每段最多 700 字符
- [ ] key_sentence_ids 最多 6
- [ ] paragraph_cards 带 provenance

## D. iOS identity loop

- [ ] 请求包含 client_request_id
- [ ] 请求包含 document_id
- [ ] 请求包含 sentence_id
- [ ] 请求包含 segment_id
- [ ] 请求包含 sentence_text_hash
- [ ] 请求包含 anchor_label
- [ ] 响应落地前经过 AIResponseIdentityGuard
- [ ] mismatch 响应会丢弃
- [ ] 切换句子时旧 result 会清空
- [ ] 503 / timeout / config missing 时句子页有本地骨架
- [ ] DEBUG 日志包含 request_id / error_code / used_fallback
- [ ] 不打印 API key / Authorization

## E. PassageMap and MindMap

- [ ] PassageMap 存在并进入真实路径
- [ ] NodeProvenance 存在
- [ ] SourceHygieneScorer 存在
- [ ] AnchorConsistencyValidator 输出可解释结果
- [ ] MindMapAdmissionResult 区分 mainline / auxiliary / rejected
- [ ] mainline 只包含 admission 通过节点
- [ ] auxiliary 默认不进主画布
- [ ] rejected 只进 diagnostics
- [ ] SourceOutlineTab 接入 MindMapWorkspaceView
- [ ] SourceDetailView 主导航为“思维导图”
- [ ] MindMapWorkspaceView 不直接以旧 OutlineNode 作为主图数据源

## F. Security

- [ ] 仓库无真实 API key
- [ ] 无 tracked .env
- [ ] 无 Authorization: Bearer 泄露
- [ ] NOVAI_API_KEY 只在 .env.example / runbook 示例中以占位出现
- [ ] Swift 源码不硬编码 47.94.227.58
- [ ] 生产 IP 只出现在 deploy/runbook/production record/checklist 中
- [ ] 日志和文档不回显服务器私钥

## G. Deploy record and production smoke

- [ ] production deploy record 存在
- [ ] 记录了部署时间
- [ ] 记录了服务名 cuotiben-backend.service
- [ ] 记录了备份目录
- [ ] 记录了部署目录
- [ ] 记录了 systemd 状态
- [ ] 记录了 /health smoke
- [ ] 记录了 /ai/explain-sentence smoke request_id
- [ ] 记录了 /ai/analyze-passage smoke request_id
- [ ] 记录了回滚路径
- [ ] 没有写真实 key

## H. Merge readiness

- [ ] backend npm test 48/48 通过
- [ ] localCurlSmoke 3/3 通过
- [ ] iOS headless build exit 0
- [ ] PR 描述包含 verification 与 production smoke
- [ ] PR 仍标注 Full device regression pending
- [ ] 没有未提交文件
- [ ] Draft 转 Ready 前已完成本 checklist 人工 review
