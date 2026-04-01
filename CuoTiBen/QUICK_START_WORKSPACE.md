# 工作台区件系统快速上手指南

## 🚀 5 分钟快速开始

### 1. 导入设计系统

```swift
import SwiftUI

// 所有 Token 和组件已自动可用，无需额外导入
```

### 2. 使用颜色 Token

```swift
struct MyView: View {
  var body: some View {
    VStack {
      Text("主标题")
        .foregroundColor(WorkspaceColors.textPrimary)
      
      Text("正文内容")
        .foregroundColor(WorkspaceColors.textSecondary)
      
      Button("点击我") {
        print("Tapped")
      }
      .foregroundColor(WorkspaceColors.accentIndigo)
    }
    .background(WorkspaceColors.backgroundPrimary)
  }
}
```

### 3. 使用字体 Token

```swift
Text("超大标题")
  .font(WorkspaceTypography.displayLarge)

Text("章节标题")
  .font(WorkspaceTypography.headlineMedium)

Text("正文内容")
  .font(WorkspaceTypography.body)

Text("辅助说明")
  .font(WorkspaceTypography.caption)
```

### 4. 使用间距 Token

```swift
VStack(spacing: WorkspaceSpacing.lg) {
  Text("标题")
    .padding(.bottom, WorkspaceSpacing.md)
  
  Text("内容")
    .padding(.horizontal, WorkspaceSpacing.lg)
}
.padding(WorkspaceSpacing.xxl)
```

### 5. 使用核心组件

#### AppPageHeader (页面头部)

```swift
AppPageHeader(
  title: "我的页面",
  subtitle: "副标题或描述",
  leadingAction: {
    print("返回")
  },
  trailingActions: [
    ({ print("搜索") }, "搜索", Image(systemName: "magnifyingglass")),
    ({ print("设置") }, "设置", Image(systemName: "gearshape"))
  ]
)
```

#### SectionHeader (区块头部)

```swift
SectionHeader(
  icon: "chart.bar",
  title: "学习统计",
  actionTitle: "查看全部",
  action: { print("View all") },
  showDivider: true
)
```

#### SegmentedSwitch (分段切换)

```swift
@State private var selectedTab = 0

SegmentedSwitch(
  selection: $selectedTab,
  options: [
    (0, "全部", "square.grid.2x2"),
    (1, "进行中", "clock"),
    (2, "已完成", "checkmark.circle")
  ],
  showIcons: true,
  compact: false
)
```

#### ContextCard (上下文卡片)

```swift
ContextCard(
  icon: "book.open",
  iconColor: WorkspaceColors.accentIndigo,
  title: "正在阅读",
  subtitle: "《深度学习》第 3 章",
  metadata: [
    ("进度", "67%"),
    ("剩余", "45 分钟")
  ],
  onTap: {
    print("打开材料")
  }
)
```

#### QuoteBlockCard (引用块)

```swift
QuoteBlockCard(
  quote: "神经网络是由大量的简单处理单元组成的并行分布式处理器。",
  sourceTitle: "深度学习",
  sourcePosition: "P.87",
  knowledgePointCount: 3,
  onTap: {
    print("查看原文")
  }
)
```

#### KnowledgeChip (知识点芯片)

```swift
KnowledgeChip(
  title: "反向传播算法",
  subject: "机器学习",
  isLinked: true,
  onTap: {
    print("打开知识点")
  },
  onLink: {
    print("关联知识点")
  }
)
```

#### FloatingNavigatorPanel (浮动导航)

```swift
@State private var selectedSection = 1
@State private var isPanelExpanded = true

FloatingNavigatorPanel(
  title: "文档结构",
  sections: [
    ("doc.text", "引言", 3),
    ("brain", "核心概念", 8),
    ("gear", "实践应用", 5),
    ("flag.checkered", "总结", 2)
  ],
  selectedIndex: selectedSection,
  onSelect: { index in
    selectedSection = index
    // 跳转到对应章节
  },
  onClose: {
    isPanelExpanded = false
  },
  isExpanded: isPanelExpanded
)
.frame(width: isPanelExpanded ? 400 : 56)
```

---

## 🎨 完整页面示例

```swift
import SwiftUI

struct MyWorkspacePage: View {
  @State private var selectedFilter = 0
  
  var body: some View {
    ZStack {
      // 背景
      WorkspaceColors.backgroundPrimary
        .ignoresSafeArea()
      
      ScrollView {
        VStack(alignment: .leading, spacing: WorkspaceSpacing.xxl) {
          
          // 页面头部
          AppPageHeader(
            title: "学习空间",
            subtitle: "下午好，继续加油",
            trailingActions: [
              ({ print("设置") }, "设置", Image(systemName: "gearshape"))
            ]
          )
          .padding(.horizontal, WorkspaceLayout.cardHorizontalMarginiPhone)
          
          // 区块 1: 统计
          SectionHeader(
            icon: "chart.line.uptrend.xyaxis",
            title: "今日学习",
            showDivider: false
          )
          
          LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
          ], spacing: WorkspaceSpacing.md) {
            StatCard(
              icon: "timer",
              iconColor: WorkspaceColors.accentIndigo,
              value: "2 小时",
              label: "学习时长"
            )
            
            StatCard(
              icon: "book.fill",
              iconColor: WorkspaceColors.accentTeal,
              value: "3 本",
              label: "阅读材料"
            )
          }
          .padding(.horizontal, WorkspaceLayout.cardHorizontalMarginiPhone)
          
          // 区块 2: 快速操作
          SectionHeader(
            icon: "bolt.fill",
            title: "快速开始",
            showDivider: false
          )
          
          HStack(spacing: WorkspaceSpacing.md) {
            QuickActionButton(
              icon: "plus.app",
              label: "新建笔记",
              color: WorkspaceColors.accentIndigo
            )
            
            QuickActionButton(
              icon: "book.badge.plus",
              label: "导入资料",
              color: WorkspaceColors.accentTeal
            )
          }
          .padding(.horizontal, WorkspaceLayout.cardHorizontalMarginiPhone)
          
          // 区块 3: 内容列表
          SectionHeader(
            icon: "note.text",
            title: "最近笔记",
            actionTitle: "全部",
            action: { print("查看全部") }
          )
          
          VStack(spacing: WorkspaceSpacing.sm) {
            // 笔记列表项...
          }
          .padding(.horizontal, WorkspaceLayout.cardHorizontalMarginiPhone)
          
        }
      }
    }
  }
}

// 支持组件
struct StatCard: View {
  let icon: String
  let iconColor: Color
  let value: String
  let label: String
  
  var body: some View {
    VStack(alignment: .leading, spacing: WorkspaceSpacing.md) {
      Image(systemName: icon)
        .font(.system(size: 20, weight: .semibold))
        .foregroundColor(iconColor)
        .frame(width: 44, height: 44)
        .background(
          RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
            .fill(iconColor.opacity(0.1))
        )
      
      Text(value)
        .font(WorkspaceTypography.displayMedium)
        .foregroundColor(WorkspaceColors.textPrimary)
        .fontWeight(.bold)
      
      Text(label)
        .font(WorkspaceTypography.label)
        .foregroundColor(WorkspaceColors.textSecondary)
    }
    .padding(WorkspaceSpacing.lg)
    .background(
      RoundedRectangle(cornerRadius: WorkspaceCornerRadius.xl)
        .fill(WorkspaceColors.cardBackground)
    )
    .shadow(color: WorkspaceColors.shadowLight, radius: 10, x: 0, y: 4)
  }
}

struct QuickActionButton: View {
  let icon: String
  let label: String
  let color: Color
  
  var body: some View {
    Button(action: {}) {
      VStack(spacing: WorkspaceSpacing.sm) {
        Image(systemName: icon)
          .font(.system(size: 22, weight: .semibold))
          .foregroundColor(color)
          .frame(width: 56, height: 56)
          .background(
            Circle()
              .fill(color.opacity(0.1))
          )
        
        Text(label)
          .font(WorkspaceTypography.labelSmall)
          .foregroundColor(WorkspaceColors.textSecondary)
      }
    }
    .buttonStyle(.plain)
  }
}
```

---

## 📱 iPad vs iPhone 适配

### iPad 双栏布局

```swift
struct NotesSplitView: View {
  @State private var selectedNote: Note?
  
  var body: some View {
    HStack(spacing: 18) {
      // 左栏：列表
      NotesListPane(selectedNote: $selectedNote)
        .frame(width: WorkspaceLayout.notesListWidthiPad)
      
      // 右栏：详情
      if let note = selectedNote {
        NoteDetailPane(note: note)
          .frame(minWidth: WorkspaceLayout.noteDetailMinWidthiPad)
      } else {
        Text("选择一篇笔记")
          .foregroundColor(WorkspaceColors.textTertiary)
      }
    }
    .padding(WorkspaceSpacing.xxl)
    .background(WorkspaceColors.backgroundPrimary)
  }
}
```

### iPhone 单栏布局

```swift
struct NotesNavigationView: View {
  @State private var selectedNote: Note?
  
  var body: some View {
    NavigationView {
      NotesListPane(selectedNote: $selectedNote)
        .listStyle(.plain)
        .navigationTitle("我的笔记")
      
      if let note = selectedNote {
        NoteDetailPane(note: note)
          .navigationTitle(note.title ?? "未命名")
      }
    }
  }
}
```

---

## 🎬 动画与交互

### 卡片压缩反馈

```swift
struct PressableCard: View {
  @State private var isPressed = false
  
  var body: some View {
    Button(action: {
      withAnimation(WorkspaceAnimations.springStandard) {
        isPressed = true
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        withAnimation(WorkspaceAnimations.springStandard) {
          isPressed = false
        }
      }
    }) {
      Text("点击我")
        .padding()
        .background(
          RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
            .fill(WorkspaceColors.cardBackground)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
    }
    .buttonStyle(.plain)
  }
}
```

### 内容切换过渡

```swift
@State private var selectedTab = 0

var body: some View {
  Group {
    if selectedTab == 0 {
      TabOneView()
        .transition(WorkspaceAnimations.fadeInSlideUp)
    } else {
      TabTwoView()
        .transition(WorkspaceAnimations.fadeInSlideUp)
    }
  }
  .animation(WorkspaceAnimations.smooth, value: selectedTab)
}
```

### 分段切换无闪烁

```swift
SegmentedSwitch(
  selection: $selectedFilter,
  options: [
    (0, "全部", "square.grid.2x2"),
    (1, "进行中", "clock"),
    (2, "已完成", "checkmark.circle")
  ]
)
// 内部已实现无闪烁逻辑，无需额外配置
```

---

## 🎯 最佳实践

### ✅ 推荐做法

1. **始终使用 Token**
```swift
// ✅ 好
.foregroundColor(WorkspaceColors.textPrimary)

// ❌ 差
.foregroundColor(.black)
```

2. **保持间距一致**
```swift
// ✅ 好
VStack(spacing: WorkspaceSpacing.lg)

// ❌ 差
VStack(spacing: 17) // 不规范的间距
```

3. **使用组件而非重复代码**
```swift
// ✅ 好
AppPageHeader(title: "标题")

// ❌ 差
HStack {
  Text("标题")
  // ... 重复的布局代码
}
```

4. **遵循字体层级**
```swift
// ✅ 好
Text("标题").font(WorkspaceTypography.headlineMedium)
Text("正文").font(WorkspaceTypography.body)

// ❌ 差
Text("标题").font(.system(size: 20)) // 硬编码
```

### ⚠️ 常见错误

1. **混用设计系统**
```swift
// ❌ 不要混用新旧系统
AuroraBackground() // 旧系统
  .background(WorkspaceColors.backgroundPrimary) // 新系统
```

2. **过度使用强调色**
```swift
// ❌ 到处都是强调色
.foregroundColor(WorkspaceColors.accentIndigo) // 滥用

// ✅ 仅在关键操作使用
Button("主要操作") { }
  .foregroundColor(WorkspaceColors.accentIndigo) // 克制
```

3. **忽略无障碍访问**
```swift
// ❌ 对比度不足
Text("次要信息")
  .foregroundColor(WorkspaceColors.textPlaceholder) // 太浅

// ✅ 确保可读性
Text("次要信息")
  .foregroundColor(WorkspaceColors.textTertiary) // 合适
```

---

## 📚 进一步阅读

- [`REDESIGN_PLAN_WORKSPACE.md`](REDESIGN_PLAN_WORKSPACE.md) - 完整设计文档
- [`WorkspaceDesignTokens.swift`](Sources/HuiLu/DesignSystem/WorkspaceDesignTokens.swift) - Token 源码
- [`WorkspaceComponents.swift`](Sources/HuiLu/DesignSystem/WorkspaceComponents.swift) - 组件源码
- [`WorkspaceHomeView.swift`](Sources/HuiLu/Views/WorkspaceHomeView.swift) - 首页示例

---

## 🆘 常见问题

**Q: 如何自定义组件样式？**
A: 大多数组件支持参数定制，如 `iconColor`、`cornerRadius` 等。如需深度定制，建议复制组件代码后修改。

**Q: 深色模式支持吗？**
A: 当前版本专注于浅色模式优化。深色模式 Token 已在 `WorkspaceDesignTokens.swift` 中定义，可在后续版本中启用。

**Q: 如何在现有页面中使用新组件？**
A: 逐步替换。先从一个页面开始（如首页），验证效果后再推广到其他页面。

**Q: 组件性能如何？**
A: 所有组件都经过优化，使用 `@State` 和 `@Binding` 管理状态，避免不必要的重绘。

---

**版本**: 1.0  
**最后更新**: 2025
