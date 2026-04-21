# Phase 6 MindMap Workspace Fixtures

## Fixture A: 正常 Mainline

- 输入：
  - `root` 1 个
  - `paragraph` 3 个
  - 每个 paragraph 最多挂 1 个 `teachingFocus`
  - 每个 paragraph 最多挂 1 个 `anchorSentence`
  - 全部节点 `admission = mainline`
- 预期：
  - 主图完整显示中心主题与 3 个一级段落分支
  - 二级节点显示教学重点/核心句
  - auxiliary/rejected 面板为空或未展开

## Fixture B: Auxiliary

- 输入：
  - `question`
  - `answerKey`
  - `vocabularySupport`
  - `admission = auxiliary`
- 预期：
  - 默认不进入主线画布
  - 只在辅助面板中显示
  - 默认折叠，需要用户主动展开

## Fixture C: Rejected

- 输入：
  - `consistencyScore < 0.75`
  - 或 `sourceKind != passageBody`
  - 或 `rejectedReason != nil`
- 预期：
  - 不进入主图
  - 只进入 diagnostics
  - diagnostics 可显示 `nodeID / sourceKind / rejectedReason`

## Fixture D: Fallback

- 输入：
  - `meta.used_fallback = true`
  - `PassageMap` 来自 `LocalPassageFallbackBuilder`
- 预期：
  - 主图不空白
  - 显示 “本地结构骨架” 提示
  - 仍能显示 root、一级段落分支与最小化 diagnostics

## Fixture E: 大图

- 输入：
  - `paragraph` 12 个
  - 每个 paragraph 最多 2 个二级节点
- 预期：
  - `fitToContent` 能看到完整全图
  - `minimap` 可用并同步主视口
  - `visibleNodeIDs(in:)` 只渲染可见节点或轻量占位
  - 大图不退化成竖排长树

## Fixture F: iPhone 简化模式

- 输入：
  - `compact`
  - `horizontalSizeClass = compact`
- 预期：
  - 只显示中心主题 + 一级段落分支
  - 二级节点按点击展开
  - minimap 可隐藏或缩小，但布局仍来自同一 `layoutSnapshot`

## Fixture G: Auxiliary 与 Mainline 混合

- 输入：
  - `mainline` 3 个 paragraph
  - `auxiliary` 4 个 question/vocabulary 节点
- 预期：
  - 主画布只展示 `mainline`
  - 辅助面板单独显示 question / vocabulary
  - 不出现 auxiliary 节点串入主分支

## Fixture H: Fallback + Rejected 混合

- 输入：
  - `isUsingFallback = true`
  - admission diagnostics 中仍有 rejected 节点
- 预期：
  - fallback banner 可见
  - diagnostics 仍能查看 rejected reason
  - rejected 不因 fallback 状态重新回流到主图
