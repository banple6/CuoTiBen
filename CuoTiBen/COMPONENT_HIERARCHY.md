# 🏗️ UI 组件层级结构图

## 应用架构

```
App
└── ContentView
    ├── EnhancedTabBar (底部标签栏)
    └── Tab Views
        ├── EnhancedHomeView (首页)
        ├── EnhancedLibraryView (知识库)
        ├── NotesHomeView (笔记 - 待更新)
        └── EnhancedReviewListView (复习列表)
```

---

## 组件层级树

### 基础组件层 (Foundation)

```
EnhancedUIComponents.swift
│
├── AuroraBackground (背景)
│   ├── AuroraOrb (光晕球体)
│   └── 动态动画系统
│
├── PremiumGlassPanel (玻璃面板)
│   ├── glassBackground (背景材质)
│   ├── borderGradient (边框渐变)
│   ├── shimmerOverlay (光泽覆盖)
│   └── shadowSystem (阴影系统)
│
├── ElegantButton (按钮)
│   ├── 样式: Primary / Secondary / Ghost / Glass
│   ├── 尺寸：Small / Medium / Large
│   └── 动画系统
│
├── FloatingActionButton (悬浮按钮)
│
├── ModernCard (卡片)
│   ├── Elevated (悬浮式)
│   ├── Flat (平面式)
│   └── Highlighted (高亮式)
│
├── Chip Components (标签芯片)
│   ├── ModernChip
│   ├── InfoChip
│   └── MetaBadge
│
├── ElegantSectionHeader (章节标题)
│
├── ElegantLoadingIndicator (加载指示器)
│
└── ElegantEmptyState (空状态)
```

### 导航组件层 (Navigation)

```
EnhancedTabBar.swift
│
├── EnhancedTabBar (主标签栏)
│   ├── EnhancedGlassBackground
│   ├── AnimatedShine
│   └── EnhancedTabBarItem (×4)
│       ├── 图标渐变
│       ├── 标签文字
│       └── 选中状态背景
│
├── EnhancedSidebar (iPad 侧边栏 - 可选)
│   └── EnhancedSidebarItem
│
└── MainTab Extension
    ├── gradient (各标签渐变色)
    └── accentColor (各标签强调色)
```

### 页面组件层 (Pages)

```
EnhancedHomeView.swift
│
├── AuroraBackground(mode: .dark)
│
├── enhancedHeader (头部)
│   ├── greeting (时间问候)
│   ├── userName (用户名)
│   ├── encouragementMessage (鼓励文案)
│   ├── HeaderActionButton (×2)
│   └── enhancedMasteryRing (掌握度圆环)
│
├── enhancedStartReviewButton (开始复习按钮)
│   └── PremiumGlassPanel + ElegantButton
│
├── statsOverviewSection (统计概览)
│   └── StatCard (×4)
│       ├── 渐变图标
│       ├── 标题
│       └── 数值
│
├── workbenchSection (学习工作台)
│   └── EnhancedWorkbenchCard (×3)
│       ├── 类型图标
│       ├── 状态徽章
│       ├── 标题
│       ├── 元数据
│       └── 进度条
│
├── weakPointsSection (薄弱点)
│   └── EnhancedWeakPointCard (×5)
│       ├── 渐变图标
│       ├── 标题
│       └── 错误频率条
│
└── dailyFocusCard (每日专注)
    ├── ModernChip
    └── InfoChip (×3)
```

```
EnhancedLibraryView.swift
│
├── AuroraBackground(mode: .light)
│
├── enhancedHeader (头部)
│   ├── 标题 + 副标题
│   └── FloatingActionButton
│
├── filterSection (筛选区)
│   └── FilterChip (×5)
│       ├── 全部 / 英语 / 语文 / 数学 / 已就绪
│       └── 计数徽章
│
├── documentGrid (文档网格)
│   └── EnhancedDocumentCard (动态列数)
│       ├── 类型图标（渐变）
│       ├── 状态徽章
│       ├── 标题
│       ├── MetaBadge (×N)
│       └── 进度条
│
└── emptyState (空状态)
    └── ElegantEmptyState
```

```
EnhancedReviewListView.swift
│
├── AuroraBackground(mode: .dark)
│
├── enhancedHeader (头部)
│   ├── 标题 + 副标题
│   └── 动态图标
│
├── todayProgressCard (今日进度)
│   ├── 大数字展示
│   ├── 说明文字
│   └── ElegantButton
│
├── queuePreviewSection (队列预览)
│   └── EnhancedReviewCard (×3)
│       ├── 优先级标识
│       ├── 卡片内容
│       ├── ErrorCountBadge
│       └── DifficultyBadge
│
├── focusSignalsCard (专注信号)
│   └── FocusSignalTile (×3)
│       ├── 渐变图标
│       ├── 数值
│       └── 标签
│
└── studyStatisticsCard (学习统计)
    └── StatMiniCard (×2)
```

---

## 组件复用关系图

```
┌─────────────────────────────────────────────────────┐
│           基础组件 (可复用在多个页面)                 │
├─────────────────────────────────────────────────────┤
│                                                     │
│  AuroraBackground                                   │
│    ↳ EnhancedHomeView (dark)                        │
│    ↳ EnhancedLibraryView (light)                    │
│    ↳ EnhancedReviewListView (dark)                  │
│                                                     │
│  PremiumGlassPanel                                  │
│    ↳ 所有卡片组件                                   │
│    ↳ 所有面板组件                                   │
│    ↳ 按钮容器                                       │
│                                                     │
│  ElegantButton                                      │
│    ↳ EnhancedHomeView (开始复习)                    │
│    ↳ EnhancedLibraryView (导入按钮)                 │
│    ↳ EnhancedReviewListView (开始复习)              │
│    ↳ 各种操作按钮                                   │
│                                                     │
│  ModernCard                                         │
│    ↳ StatCard                                       │
│    ↳ EnhancedWorkbenchCard                          │
│    ↳ EnhancedDocumentCard                           │
│                                                     │
│  ModernChip / InfoChip / MetaBadge                  │
│    ↳ 所有标签和徽章                                 │
│                                                     │
│  ElegantSectionHeader                               │
│    ↳ 所有章节标题                                   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## 数据流向图

```
AppViewModel (环境对象)
    │
    ├─→ EnhancedHomeView
    │   ├─ viewModel.progressPercentage
    │   ├─ viewModel.dailyProgress
    │   ├─ viewModel.totalCardsLearned
    │   ├─ viewModel.englishDocumentsForWorkbench()
    │   └─ viewModel.dailyProgress.highErrorChunks
    │
    ├─→ EnhancedLibraryView
    │   ├─ viewModel.sourceDocuments
    │   └─ 筛选和排序逻辑
    │
    ├─→ EnhancedReviewListView
    │   ├─ viewModel.reviewQueue
    │   ├─ viewModel.dailyProgress
    │   ├─ viewModel.totalCardsLearned
    │   └─ viewModel.dailyProgress.highErrorChunks
    │
    └─→ NotesHomeView (未更新)
```

---

## 状态管理图

```
@StateObject
└── viewModel: AppViewModel (共享状态)

@State (各页面私有)
├── EnhancedHomeView
│   ├── showingReview: Bool
│   ├── selectedWorkbenchDocument: SourceDocument?
│   ├── selectedWorkbenchAnchor: SourceAnchor?
│   ├── showsSettings: Bool
│   └── showsNotesHome: Bool
│
├── EnhancedLibraryView
│   ├── selectedDocument: SourceDocument?
│   ├── showsImportSheet: Bool
│   ├── searchText: String
│   └── selectedFilter: LibraryFilter
│
├── EnhancedReviewListView
│   └── showingSession: Bool
│
└── EnhancedTabBar
    └── selectedTab: MainTab (绑定)

@Binding (跨组件传递)
├── selectedTab: MainTab
│   └── ContentView ↔ EnhancedTabBar
│
└── isPresented: Bool
    └── 各种 Sheet 和 Cover
```

---

## 动画层级

```
Level 0: 静态元素
├── 背景渐变
├── 文字内容
└── 图标

Level 1: 微动画
├── 悬停效果 (0.2s ease-in-out)
├── 按钮按压 (0.15s spring)
└── 光泽扫过 (3s repeat)

Level 2: 中等动画
├── 标签切换 (0.35s spring)
├── 卡片出现 (0.3s spring)
└── 筛选切换 (0.25s spring)

Level 3: 大动画
├── 页面转场 (0.5s spring)
├── FullScreenCover (0.4s spring)
└── 背景光晕浮动 (8-10s repeat)

性能优化:
└── AppPerformance.prefersReducedEffects
    ├─ true: 简化或禁用动画
    └─ false: 完整动画效果
```

---

## 颜色应用层级

```
背景层
├── AuroraBackground
│   ├─ 主渐变 (深空/晨空)
│   └─ 光晕球体 (强调色 15% 透明度)
│
表面层
├── PremiumGlassPanel
│   ├─ 玻璃底色 (8-72% 透明度)
│   ├─ 渐变叠加
│   └─ 材质模糊
│
强调层
├── 按钮 (渐变填充)
├── 图标 (渐变填充)
├── 进度条 (渐变填充)
└── 徽章 (强调色填充)

文字层
├── Primary (95% 白/85% 黑)
├── Secondary (75% 白/60% 黑)
└── Tertiary (55% 白/40% 黑)
```

---

## 响应式断点

```
iPhone SE (375pt)
└── 单列布局
    ├── 卡片宽度：~327pt (减去 padding)
    └── 标签栏：紧凑模式

iPhone Standard (390-428pt)
└── 单列布局
    ├── 卡片宽度：~342-380pt
    └── 标签栏：标准模式

iPad Compact (600-800pt)
└── 双列布局
    ├── 卡片宽度：~260-360pt
    └── 可使用侧边栏

iPad Regular (834-1024pt)
└── 三列布局
    ├── 卡片宽度：~240-300pt
    └── 推荐使用侧边栏
```

---

## 性能关键路径

```
渲染性能
│
├─→ 关键优化点
│   ├─ shouldRasterize: true (缓存复杂背景)
│   ├─ 条件动画 (检测低功耗模式)
│   ├─ 延迟加载 (非关键内容)
│   └─ 懒加载 (LazyVGrid)
│
├─→ 避免的性能陷阱
│   ├─ 过度模糊 (blur radius > 50)
│   ├─ 深层 ZStack 嵌套 (>3 层)
│   ├─ 频繁的状态更新
│   └─ 大量同时动画
│
└─→ 目标性能指标
    ├─ 动画帧率：60fps
    ├─ 页面加载：< 400ms
    ├─ 内存占用：< 150MB
    └─ 电池消耗：优化 8%
```

---

## 组件依赖关系

```
EnhancedUIComponents.swift
    ↓ (被依赖)
EnhancedTabBar.swift
EnhancedHomeView.swift
EnhancedLibraryView.swift
EnhancedReviewListView.swift
    ↓ (被依赖)
ContentView.swift
    ↓ (被依赖)
App Entry Point
```

---

**最后更新**: 2026 年 3 月 29 日  
**版本**: v2.0
