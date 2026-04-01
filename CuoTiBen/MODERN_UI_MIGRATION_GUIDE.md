# 从旧 UI 迁移到现代 UI 系统指南

## 📋 概述

本文档提供从原有 UI 组件和视图迁移到新现代 UI 系统的详细步骤和对照表。

---

## 🎨 设计令牌迁移

### 颜色映射

| 旧用法 | 新令牌 | 说明 |
|--------|--------|------|
| `.blue` | `ModernColors.primary` | 主色调 (#476BE0) |
| `.red` | `ModernColors.secondary` | 辅助色 (#EB617A) |
| `.green` | `ModernColors.accent` | 强调色 (#52C7B8) |
| `.gray.opacity(0.1)` | `ModernColors.surfaceVariant` | 浅灰背景 |
| `.black.opacity(0.8)` | `ModernColors.textPrimary` | 主文本 |
| `.black.opacity(0.6)` | `ModernColors.textSecondary` | 次要文本 |

### 字体映射

| 旧用法 | 新令牌 | 说明 |
|--------|--------|------|
| `.font(.title)` | `ModernTypography.titleLarge` | 大标题 |
| `.font(.headline)` | `ModernTypography.headlineMedium` | 标题 |
| `.font(.body)` | `ModernTypography.body` | 正文 |
| `.font(.caption)` | `ModernTypography.caption` | 说明文字 |
| `.font(.footnote)` | `ModernTypography.caption` | 脚注 |

### 间距映射

| 旧用法 | 新令牌 | 说明 |
|--------|--------|------|
| `.padding(4)` | `.padding(ModernSpacing.xs)` | 极小间距 |
| `.padding(8)` | `.padding(ModernSpacing.sm)` | 小间距 |
| `.padding(12)` | `.padding(ModernSpacing.md)` | 中间距 |
| `.padding(16)` | `.padding(ModernSpacing.lg)` | 大间距 |
| `.padding(20)` | `.padding(ModernSpacing.xl)` | 加大间距 |
| `.padding(24)` | `.padding(ModernSpacing.xxl)` | 特大间距 |
| `.padding(32)` | `.padding(ModernSpacing.xxxl)` | 超大间距 |

---

## 🧩 组件迁移对照表

### 卡片组件

#### 旧代码
```swift
VStack(alignment: .leading, spacing: 12) {
  content
}
.padding(16)
.background(Color.white)
.cornerRadius(12)
.shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
```

#### 新代码
```swift
ModernCard(variant: .elevated) {
  content
}
```

### 按钮组件

#### 旧代码
```swift
Button(action: action) {
  HStack {
    Image(systemName: "plus")
    Text("新建")
  }
  .font(.system(size: 16, weight: .semibold))
  .foregroundColor(.white)
  .padding()
  .background(
    RoundedRectangle(cornerRadius: 12)
      .fill(Color.blue)
  )
}
```

#### 新代码
```swift
PrimaryButton(
  title: "新建",
  icon: "plus"
) {
  action
}
```

### 统计卡片

#### 旧代码
```swift
VStack(alignment: .leading, spacing: 8) {
  Image(systemName: "clock")
    .font(.system(size: 24))
    .foregroundColor(.blue)
  
  Text("45")
    .font(.system(size: 32, weight: .bold))
  
  Text("今日学习")
    .font(.caption)
    .foregroundColor(.gray)
}
.padding()
.background(Color.white)
.cornerRadius(12)
```

#### 新代码
```swift
StatCard(
  icon: "clock",
  value: "45",
  label: "今日学习",
  color: ModernColors.primary
)
```

### 搜索栏

#### 旧代码
```swift
HStack {
  Image(systemName: "magnifyingglass")
    .foregroundColor(.gray)
  
  TextField("搜索...", text: $searchText)
    .textFieldStyle(.plain)
}
.padding()
.background(Color.gray.opacity(0.1))
.cornerRadius(10)
```

#### 新代码
```swift
HStack(spacing: ModernSpacing.sm) {
  Image(systemName: "magnifyingglass")
    .foregroundColor(ModernColors.textTertiary)
  
  TextField("搜索...", text: $searchText)
    .textFieldStyle(.plain)
}
.padding(ModernSpacing.md)
.background(ModernColors.surface)
.cornerRadius(ModernCornerRadius.md)
.overlay(
  RoundedRectangle(cornerRadius: ModernCornerRadius.md)
    .stroke(ModernColors.outline, lineWidth: 1)
)
```

---

## 📱 页面迁移指南

### HomeView 迁移

#### 步骤 1: 替换 imports
```swift
// 删除
import GlassKit

// 添加
import DesignSystem  // 如果 ModernComponents 在单独模块
```

#### 步骤 2: 替换视图
```swift
// 旧
struct HomeView: View {
  var body: some View {
    GlassNavigationView {
      // 内容
    }
  }
}

// 新
struct ModernHomeView: View {
  var body: some View {
    Group {
      if isiPad {
        iPadView
      } else {
        iPhoneView
      }
    }
    .background(ModernColors.background)
  }
}
```

#### 步骤 3: 迁移统计数据
```swift
// 旧
@State private var studyTime = 45

// 新
private var studyTime: Int {
  viewModel.todayStudyDuration / 60
}
```

### NotesView 迁移

#### 步骤 1: 采用双窗格布局
```swift
// iPad
NavigationSplitView {
  NotesListPane(/* ... */)
    .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 360)
} detail: {
  NoteDetailPane(/* ... */)
}

// iPhone
NavigationView {
  NotesListPane(/* ... */)
}
```

#### 步骤 2: 替换列表项
```swift
// 旧
List {
  ForEach(notes) { note in
    NoteRow(note: note)
  }
}

// 新
ScrollView {
  VStack(spacing: ModernSpacing.sm) {
    ForEach(notes, id: \.id) { note in
      NoteListItem(note: note, isSelected: selectedNote?.id == note.id) {
        selectedNote = note
      }
    }
  }
  .padding(.horizontal, ModernSpacing.lg)
}
```

### LibraryView 迁移

#### 步骤 1: 添加学科筛选
```swift
@State private var selectedSubject: Subject?

// 在侧边栏或顶部添加学科选择器
```

#### 步骤 2: 网格/列表切换
```swift
@State private var viewMode: ViewMode = .grid

// 根据 viewMode 渲染不同布局
```

### ReviewView 迁移

#### 步骤 1: 添加统计概览
```swift
// 使用 StatCard 组件展示学习数据
HStack {
  StatCard(icon: "clock", value: "45", label: "今日学习")
  StatCard(icon: "checkmark", value: "28", label: "已完成")
}
```

#### 步骤 2: 快捷操作
```swift
// 使用 ActionCard 或 PrimaryButton
PrimaryButton(
  title: "开始复习 (\(dueCount))",
  icon: "play.circle"
) {
  showingReviewSession = true
}
```

---

## 🔧 ViewModel 集成步骤

### 步骤 1: 识别数据需求

为每个页面列出所需数据：

#### ModernHomeView
```swift
- todayStudyDuration: Int
- todayMaterialsCount: Int
- dueCardsCount: Int
- recentMaterials: [SourceDocument]
- recentNotes: [Note]
- dueCards: [Card]
```

#### ModernNotesSplitView
```swift
- allNotes: [Note]
- filteredNotes(filter: NoteFilter) -> [Note]
- searchNotes(query: String) -> [Note]
```

#### ModernLibraryView
```swift
- sourceDocuments: [SourceDocument]
- subjects: [Subject]
- filteredMaterials(subject: Subject?, search: String) -> [SourceDocument]
```

#### ModernReviewView
```swift
- dueCards: [Card]
- masteredCardsCount: Int
- streakDays: Int
- subjectProgress: [(Subject, Double)]
```

### 步骤 2: 添加计算属性

```swift
struct ModernHomeView: View {
  @EnvironmentObject var viewModel: AppViewModel
  
  private var stats: TodayLearningStats {
    TodayLearningStats(
      studyDuration: viewModel.todayStudyDuration / 60,
      materialsRead: viewModel.todayMaterialsCount,
      cardsReviewed: viewModel.todayCardsReviewed,
      newKnowledgePoints: viewModel.todayNewKnowledgePoints
    )
  }
  
  private var recentMaterials: [SourceDocument] {
    Array(viewModel.sourceDocuments.prefix(3))
  }
  
  // ... 其他计算属性
}
```

### 步骤 3: 处理异步加载

```swift
@State private var isLoading = true

var body: some View {
  Group {
    if isLoading {
      LoadingState(message: "加载中...")
    } else if hasData {
      contentView
    } else {
      EmptyState(/* ... */)
    }
  }
  .onAppear {
    loadData()
  }
}

private func loadData() {
  isLoading = true
  Task {
    await viewModel.fetchDashboardData()
    isLoading = false
  }
}
```

---

## 🎯 渐进式迁移策略

### 阶段 1: 并行运行
1. 保留所有旧视图
2. 创建新的 Modern* 视图
3. 通过开关或配置切换

```swift
enum AppMode {
  case legacy
  case modern
}

@State private var appMode: AppMode = .legacy

var body: some View {
  Group {
    switch appMode {
    case .legacy:
      HomeView()
    case .modern:
      ModernHomeView()
    }
  }
}
```

### 阶段 2: 逐页替换
1. 从 HomeView 开始
2. 测试稳定后迁移 LibraryView
3. 然后 NotesView
4. 最后 ReviewView

### 阶段 3: 完全切换
1. 将所有 Tab 指向新视图
2. 观察用户反馈
3. 修复问题
4. 删除旧代码

---

## ⚠️ 注意事项

### 不兼容的更改

1. **移除的玻璃效果**
   - 原有的 GlassKit 效果不再使用
   - 改用纯色背景和阴影

2. **字体变化**
   - 从系统字体改为圆角字体
   - 可能需要调整字号

3. **间距系统**
   - 从随意间距改为 4pt 网格
   - 需要全面检查对齐

### 性能考虑

1. **卡片数量**
   - ModernCard 使用复杂阴影
   - 列表中使用 `.outlined` 变体性能更好

2. **动画使用**
   - 避免同时触发多个动画
   - 使用 `ModernAnimations.subtle` 进行微交互

3. **图片加载**
   - 使用 AsyncImage 替代同步加载
   - 添加占位符和缓存

---

## 📊 迁移检查清单

### 设计令牌
- [ ] 所有颜色替换为 ModernColors
- [ ] 所有字体替换为 ModernTypography
- [ ] 所有间距替换为 ModernSpacing
- [ ] 所有圆角替换为 ModernCornerRadius
- [ ] 所有阴影替换为 ModernShadows

### 组件
- [ ] 所有卡片使用 ModernCard
- [ ] 所有按钮使用 PrimaryButton/SecondaryButton/IconButton
- [ ] 所有统计使用 StatCard
- [ ] 所有芯片使用 Chip
- [ ] 所有进度条使用 ProgressBar

### 页面
- [ ] HomeView 完成迁移
- [ ] LibraryView 完成迁移
- [ ] NotesView 完成迁移
- [ ] ReviewView 完成迁移
- [ ] 所有页面支持 iPhone/iPad

### 数据
- [ ] ViewModel 集成完成
- [ ] 异步加载处理正确
- [ ] 空状态已实现
- [ ] 错误状态已实现

### 测试
- [ ] iPhone 测试通过
- [ ] iPad 测试通过
- [ ] 横屏模式测试通过
- [ ] 深色模式测试通过 (如需要)

---

## 🆘 常见问题

### Q: 旧组件还能用吗？
A: 可以，但不推荐。建议逐步替换为新组件以保持一致性。

### Q: 可以混用新旧系统吗？
A: 技术上可行，但会导致视觉不一致。建议尽快完成迁移。

### Q: 如何处理自定义组件？
A: 使用 ModernDesignTokens 重构自定义组件，保持设计一致性。

### Q: 深色模式支持吗？
A: 当前版本专注于浅色模式。深色模式可在后续添加。

---

## 📞 获取帮助

如遇到迁移问题，请参考：
1. `MODERN_UI_DELIVERY_SUMMARY.md` - 完整交付文档
2. `MODERN_UI_QUICK_REFERENCE.md` - 快速参考
3. Xcode Preview - 实时预览组件

---

*迁移指南 | 现代 UI 系统 | 2026*
