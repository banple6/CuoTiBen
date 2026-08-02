# Phase 10: Home Resource Workbench Redesign

## 真实文件清单

- `CuoTiBen/Sources/HuiLu/Views/HomeView.swift`
- `CuoTiBen/Sources/HuiLu/Views/ContentView.swift`
- `CuoTiBen/Sources/HuiLu/ViewModels/AppViewModel.swift`
- `CuoTiBen/Sources/HuiLu/Models/SourceDocument.swift`
- 只读参考：`CuoTiBen/Sources/HuiLu/Views/LibraryView.swift`
- 只读参考：`CuoTiBen/Sources/HuiLu/Views/TextPipelineDiagnosticsView.swift`
- 设计参考：`/Users/tianboyu/Downloads/stitch_minimalist_logic_tree_view.zip`

## 首页新信息架构

iPad:

- 左侧 Sidebar：首页、资料库、笔记、复习、设置
- 中间工作区：顶部搜索/导入、最近导入资料、正在处理资料、继续学习
- 右侧状态栏：AI 服务状态、今日复习、薄弱点、学习统计

iPhone:

- 顶部搜索/导入
- 最近导入资料
- 正在处理资料
- 继续学习
- 今日复习
- AI 状态
- 底部 TabBar

## iPad / iPhone 布局差异

- iPad 使用 `HomeDashboardView` 三栏工作台，不显示底部 TabBar。
- iPhone 使用纵向流式首页，保留底部 TabBar。
- `ContentView` 通过 `UIDevice.current.userInterfaceIdiom` 决定根导航 chrome。

## 状态映射表

materialMode:

- `passageReading` -> 英文正文
- `learningMaterial` -> 学习讲义
- `vocabularyNotes` -> 词汇注释
- `questionSheet` -> 题目练习
- `auxiliaryOnlyMap` -> 辅助资料
- `insufficientText` -> 正文不足
- `pending` -> 等待识别
- `unknown` -> 未识别资料

parseStatus:

- `remoteAI` -> AI 已分析
- `remoteParsed` -> 云端解析完成
- `localSkeleton` -> 本地骨架
- `requestFailed` -> 请求失败
- `parsing` -> 解析中
- `unconfigured` -> 文档解析未配置
- `failed` -> 解析失败
- `imported` -> 已导入
- `pending` -> 等待处理

## 执行步骤

1. 在 `AppViewModel` 增加首页只读数据入口：最近导入、处理中、继续学习资料。
2. 在 `HomeView` 中重构为 Resource Workbench，并新增组件：`HomeDashboardView`、`HomeWorkbenchHeader`、`RecentMaterialsSection`、`RecentMaterialCard`、`ImportProcessingQueueView`、`AIServiceStatusCard`、`MaterialParseStatusBadge`、`MaterialModeBadge`、`HomeStudySummaryCard`、`HomeSidebarView`、`HomeDashboardLayout`、`MaterialDisplayMapper`。
3. 在 `ContentView` 中隐藏 iPad 底部 TabBar，仅 iPhone 保留。
4. 用用户可读状态替代 raw enum/debug 字段。
5. 资料卡点击进入 `SourceDetailView`，诊断入口打开轻量 sheet。

## 验证命令

- `cd "/Volumes/T7/IOS app develop/CuoTiBen/backend" && npm test`
- `cd "/Volumes/T7/IOS app develop/CuoTiBen" && xcodebuild -quiet -project "/Volumes/T7/IOS app develop/CuoTiBen/CuoTiBen.xcodeproj" -scheme "CuoTiBen" -configuration Debug -sdk iphonesimulator -arch arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO build`
- `grep -R "HomeDashboardView" -n CuoTiBen/Sources/HuiLu`
- `grep -R "RecentMaterialsSection" -n CuoTiBen/Sources/HuiLu`
- `grep -R "RecentMaterialCard" -n CuoTiBen/Sources/HuiLu`
- `grep -R "ImportProcessingQueueView" -n CuoTiBen/Sources/HuiLu`
- `grep -R "AIServiceStatusCard" -n CuoTiBen/Sources/HuiLu`
- `grep -R "MaterialParseStatusBadge" -n CuoTiBen/Sources/HuiLu`
- `grep -R "MaterialDisplayMapper" -n CuoTiBen/Sources/HuiLu`
- `grep -R "materialMode=pending" -n CuoTiBen/Sources/HuiLu/Views || true`
- `grep -R "progress=" -n CuoTiBen/Sources/HuiLu/Views || true`

## 回滚方式

- 回滚本轮修改文件：`HomeView.swift`、`ContentView.swift`、`AppViewModel.swift`、本计划文档。
- 不需要回滚后端、AI Gateway、AI contract 或笔记画布，因为本轮不修改这些区域。
