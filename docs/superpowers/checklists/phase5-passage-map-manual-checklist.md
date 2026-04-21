# Phase 5 Passage Map Manual Checklist

日期：2026-04-21
阶段：Phase 5
目标：确认 `PassageMap + MindMap admission` 的准入逻辑已经稳定，主导图不再直接吃污染节点。

## 主准入检查

- [ ] 主导图只吃 `admission = mainline`
- [ ] `auxiliary` 节点默认折叠，不进入主导图主线
- [ ] `rejected` 节点只进入 diagnostics，不进入主导图
- [ ] `consistencyScore < 0.75` 的节点不进入 mainline
- [ ] `hygieneScore < 0.6` 的节点不进入 mainline
- [ ] `sourceKind != passageBody` 的节点不进入 mainline

## sourceKind 分类检查

- [ ] `question` 进入 auxiliary
- [ ] `answerKey` 进入 auxiliary
- [ ] `vocabularySupport` 进入 auxiliary
- [ ] `chineseInstruction` 不进入 mainline
- [ ] `bilingualNote` 不进入 mainline
- [ ] `noise` 进入 rejected

## 一致性检查

- [ ] title 与 source paragraph overlap 足够时，才允许 mainline
- [ ] summary 与 source paragraph overlap 足够时，才允许 mainline
- [ ] anchor sentence 必须属于 `sourceSegmentID`
- [ ] `coreSentenceID` 必须属于当前段
- [ ] `coreSentenceID` 不属于当前段时，节点被降级或拒绝
- [ ] sentence analysis 的 `originalSentence` 与真实 sentence text 高重叠

## diagnostics 检查

- [ ] 每个 `rejected` 节点都有 `rejectedReason`
- [ ] diagnostics 包含 `nodeID`
- [ ] diagnostics 包含 `nodeType`
- [ ] diagnostics 包含 `sourceSegmentID`
- [ ] diagnostics 包含 `sourceSentenceID`
- [ ] diagnostics 包含 `sourceKind`
- [ ] diagnostics 包含 `hygieneScore`
- [ ] diagnostics 包含 `consistencyScore`
- [ ] diagnostics 包含 `admission`

## 结构边界检查

- [ ] `PassageMap` 只承载地图级信息
- [ ] `PassageMap` 不承载 `grammarFocus`
- [ ] `PassageMap` 不承载 `faithfulTranslation`
- [ ] `PassageMap` 不承载 `teachingInterpretation`
- [ ] `PassageMap` 不承载 `coreSkeleton`
- [ ] `PassageMap` 不承载 `chunkLayers`
- [ ] `ParagraphMap` 是 paragraph mainline 的唯一来源
- [ ] `questionLinks` 只作为辅助信息

## 诊断面板检查

- [ ] DEBUG 下可看到 `mainline count`
- [ ] DEBUG 下可看到 `auxiliary count`
- [ ] DEBUG 下可看到 `rejected count`
- [ ] DEBUG 下可看到 `average hygiene score`
- [ ] DEBUG 下可看到 `average consistency score`
- [ ] DEBUG 下可看到 `top rejected reasons`

## 验证命令检查

- [ ] `backend npm test` 通过
- [ ] iOS `xcodebuild build` 通过
- [ ] `grep -R "struct PassageMap"` 有命中
- [ ] `grep -R "struct ParagraphMap"` 有命中
- [ ] `grep -R "struct MindMapNode"` 有命中
- [ ] `grep -R "struct MindMapAdmissionResult"` 有命中
- [ ] `grep -R "struct NodeProvenance"` 有命中
- [ ] `grep -R "MindMapAdmissionService"` 有命中
- [ ] `grep -R "consistencyScore"` 有命中
- [ ] `grep -R "rejectedReason"` 有命中
- [ ] `grep -R "sourceKind"` 有命中

## 最终通过标准

通过 Phase 5 前，必须满足：
- 主导图主线不再直接吃 `question / answer / vocabulary / chineseInstruction`
- `PassageMap` 和 `MindMap admission` 已形成独立域层
- diagnostics 能解释每个 `rejected`
- 旧 `OutlineNode` 不再是新主导图的唯一数据入口
