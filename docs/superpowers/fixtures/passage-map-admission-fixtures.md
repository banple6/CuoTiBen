# Passage Map Admission Fixtures

日期：2026-04-21
阶段：Phase 5
目的：在实现 `PassageMap + MindMap admission` 之前，先固定 mainline / auxiliary / rejected 的准入边界，避免继续把旧 `OutlineNode` 或污染块混进主导图。

## Fixture A: 正常正文段落

输入：
- `sourceKind = passageBody`
- `hygieneScore = 0.84`
- `consistencyScore = 0.88`
- `segmentID = seg-01`
- `coreSentenceID` 属于 `seg-01`

节点示例：
- paragraph title: `工业扩张改写了城市边界`
- paragraph summary: `本段先交代城市扩张的历史背景，再为后文治理问题铺垫。`

预期：
- `admission = mainline`
- 进入主导图一级段落分支
- `rejectedReason = nil`

## Fixture B: 题目块

输入：
- `sourceKind = question`
- `hygieneScore = 0.82`
- `consistencyScore = 0.66`

节点示例：
- title: `题目：作者态度`
- summary: `Which of the following best describes the author’s attitude?`

预期：
- `admission = auxiliary`
- 不进入主导图主分支
- 只允许进入题目辅助层
- `rejectedReason = nil`

## Fixture C: 答案区

输入：
- `sourceKind = answerKey`
- `hygieneScore = 0.79`
- `consistencyScore = 0.58`

节点示例：
- title: `答案：C`
- summary: `答案区提供选项结论，但不属于正文论证。`

预期：
- `admission = auxiliary`
- 不进入 mainline
- 可作为辅助诊断信息

## Fixture D: 词汇区

输入：
- `sourceKind = vocabularySupport`
- `hygieneScore = 0.77`
- `consistencyScore = 0.61`

节点示例：
- title: `词汇：sustainable`
- summary: `解释重点词义，但不承担段落推进角色。`

预期：
- `admission = auxiliary`
- 只允许进入词汇辅助层
- 不得成为 paragraph mainline 标题

## Fixture E: 中文说明

输入：
- `sourceKind = chineseInstruction`
- `hygieneScore = 0.69`
- `consistencyScore = 0.43`

节点示例：
- title: `中文导学`
- summary: `先看第三段转折，再看第五段结论。`

预期：
- `admission = auxiliary` 或 `rejected`
- 不能进入 mainline
- 若进入 `rejected`，必须给出明确 `rejectedReason`

## Fixture F: 污染 / 反转 / 混合块

输入：
- `sourceKind = noise` 或 `bilingualNote`
- `hygieneScore = 0.42`
- `consistencyScore = 0.31`
- 文本存在反转、乱码、答题提示混杂正文

节点示例：
- title: `NOITCURTSNI / 阅读提示`
- summary: `混合块包含反转英文与答题话术。`

预期：
- `admission = rejected`
- 不进入 mainline
- `rejectedReason` 必须非空，且能解释是 hygiene 还是 consistency 失败

## Fixture G: coreSentenceID 串段

输入：
- `sourceKind = passageBody`
- `hygieneScore = 0.83`
- `consistencyScore = 0.71`
- `segmentID = seg-03`
- `coreSentenceID = sentence-from-seg-04`

预期：
- 不得进入 `mainline`
- 至少降级为 `auxiliary`
- 诊断里必须包含：
  - `coreSentenceBelongsToParagraph = false`
  - `rejectedReason` 或降级原因说明

## Fixture H: summary 与来源重叠过低

输入：
- `sourceKind = passageBody`
- `hygieneScore = 0.81`
- `titleOverlapScore = 0.52`
- `summaryOverlapScore = 0.14`

预期：
- `consistencyScore < 0.75`
- 不得进入 `mainline`
- 若保留，最多 `auxiliary`

## Admission 决策边界

固定规则：
- `sourceKind == passageBody`
- `hygieneScore >= 0.6`
- `consistencyScore >= 0.75`
- `coreSentenceID` 属于当前段
- `anchor sentence` 属于 `sourceSegmentID`

全部满足时：
- `admission = mainline`

以下情况一律不能进入 mainline：
- `sourceKind != passageBody`
- `hygieneScore < 0.6`
- `consistencyScore < 0.75`
- `coreSentenceID` 不属于当前段
- `title/summary` 与来源文本 overlap 过低

## Diagnostics 最小字段

每个 candidate 都必须能产出：
- `nodeID`
- `nodeType`
- `sourceSegmentID`
- `sourceSentenceID`
- `sourceKind`
- `hygieneScore`
- `consistencyScore`
- `admission`
- `rejectedReason`

## 手工比对重点

实现完成后，必须能用上面的 fixture 逐条解释：
- 为什么进 `mainline`
- 为什么只进 `auxiliary`
- 为什么被 `rejected`
- 为什么 `question / answer / vocabulary / chineseInstruction` 不进主线
