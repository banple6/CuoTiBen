# Phase 6 MindMap Workspace Manual Checklist

## 入口与导航

- 资料详情页主导航文案是“思维导图”
- 工作台结构入口文案是“思维导图”
- `SourceOutlineTab` 只是 `MindMapWorkspaceView` 的薄适配层
- 主路径不再直接用 `OutlineNode` 作为主图数据源
- 主路径不再直接调用 `StructureTreePreviewView` 承担主图逻辑

## 主图数据准入

- 主画布只消费 `MindMapAdmissionResult.mainlineNodes`
- `auxiliaryNodes` 默认折叠或进入辅助面板
- `rejectedNodes` 不进入主图
- `diagnostics` 可见 rejected reason
- `sourceKind != passageBody` 的节点不进入主图
- `consistencyScore < 0.75` 的节点不进入主图

## 画布交互

- `fitToContent` 可用
- `focusCurrentNode` 可用
- 缩放有上下限
- 平移有边界限制
- minimap 与主视口同步
- `compact / detailed` 切换有效
- iPhone 存在简化导图模式

## 层级与显示

- 中心节点是文章主题
- 第一层分支是段落主题
- 第二层分支是教学重点 / 核心句 / 证据
- auxiliary 默认不进主线画布
- rejected 不显示在主图
- fallback 时仍显示本地 PassageMap 骨架

## 诊断与可解释性

- diagnostics 显示 `mainline / auxiliary / rejected` 数量
- diagnostics 显示平均 `hygiene` 与 `consistency`
- diagnostics 显示 top rejected reasons
- fallback 状态可见 `usingFallback`
- 不显示敏感信息

## 真实活跃路径

- `SourceDetailView` 的思维导图 tab 接到新工作台
- `ReviewWorkbenchView` 的结构入口接到新工作台
- `ArchivistWorkspaceView` 的导航区不再以旧 outline 作为主图入口
- 旧 `StructureTreePreview*` 只作为兼容包装或迁移辅助
