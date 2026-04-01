# 现代 UI 系统快速参考

## 🎨 设计令牌速查

### 颜色
```swift
ModernColors.primary          // #476BE0 - 主色 (活力蓝)
ModernColors.secondary        // #EB617A - 辅助色 (珊瑚红)
ModernColors.accent           // #52C7B8 - 强调色 (青)
ModernColors.background       // #F7F9FB - 背景
ModernColors.surface          // #FFFFFF - 表面
ModernColors.surfaceVariant   // #F0F2F5 - 表面变体
ModernColors.textPrimary      // #1F2638 - 主文本
ModernColors.textSecondary    // #5C6B7F - 次要文本
ModernColors.textTertiary     // #9AA5B1 - 第三级文本
ModernColors.textPlaceholder  // #CFD8E3 - 占位符
ModernColors.textInverse      // #FFFFFF - 反色文本
ModernColors.primaryContainer // #E8EFFD - 主色容器
ModernColors.outline          // #E0E4E8 - 轮廓
ModernColors.outlineVariant   // #F0F2F5 - 轮廓变体
ModernColors.error            // #D93025 - 错误
ModernColors.success          // #34A853 - 成功
ModernColors.warning          // #FBBC04 - 警告
ModernColors.shadowLight      // 黑色透明度 0.04
ModernColors.shadowMedium     // 黑色透明度 0.08
```

### 字体
```swift
ModernTypography.displayLarge   // 32pt Bold - 大展示
ModernTypography.displaySmall   // 24pt Bold - 小展示
ModernTypography.headlineLarge  // 24pt Semibold - 大标题
ModernTypography.headlineMedium // 20pt Semibold - 中标题
ModernTypography.titleLarge     // 22pt Medium - 大标题
ModernTypography.titleMedium    // 18pt Medium - 中标题
ModernTypography.titleSmall     // 16pt Medium - 小标题
ModernTypography.bodyLarge      // 17pt Regular - 大正文
ModernTypography.body           // 15pt Regular (lineSpacing: 5) - 正文
ModernTypography.caption        // 13pt Regular - 说明
ModernTypography.label          // 14pt Medium - 标签
```

### 间距
```swift
ModernSpacing.xs    // 4pt
ModernSpacing.sm    // 8pt
ModernSpacing.md    // 12pt
ModernSpacing.lg    // 16pt
ModernSpacing.xl    // 20pt
ModernSpacing.xxl   // 24pt
ModernSpacing.xxxl  // 32pt
```

### 圆角
```swift
ModernCornerRadius.xs   // 8pt
ModernCornerRadius.md   // 12pt
ModernCornerRadius.lg   // 16pt
ModernCornerRadius.xl   // 20pt
ModernCornerRadius.xxl  // 28pt
```

### 阴影
```swift
ModernShadows.card      // (color: 0.04, radius: 12, y: 4)
ModernShadows.floating  // (color: 0.08, radius: 20, y: 8)
```

### 动画
```swift
ModernAnimations.springDefault  // spring(response: 0.25, dampingFraction: 0.82)
ModernAnimations.enter          // spring(response: 0.3, dampingFraction: 0.85)
ModernAnimations.subtle         // easeInOut(duration: 0.2)
ModernAnimations.scaleIn        // easeOut(duration: 0.3)
```

### 布局
```swift
ModernLayout.sidebarWidth      // 320pt
ModernLayout.detailMinWidth    // 500pt
ModernLayout.gridColumns2      // 2 列网格
ModernLayout.gridColumns3      // 3 列网格
ModernLayout.gridColumns4      // 4 列网格
```

---

## 🧩 组件速查

### 卡片组件

#### ModernCard (4 种变体)
```swift
ModernCard(variant: .elevated) { content }      // 悬浮阴影
ModernCard(variant: .outlined) { content }      // 描边边框
ModernCard(variant: .filled) { content }        // 填充背景
ModernCard(variant: .gradient) { content }      // 渐变背景
```

#### StatCard
```swift
StatCard(
  icon: "clock",
  value: "45",
  label: "今日学习",
  trend: "+12%",
  color: ModernColors.primary
)
```

#### ActionCard
```swift
ActionCard(
  icon: "play.circle",
  title: "开始复习",
  subtitle: "12 张卡片待复习",
  color: ModernColors.primary
) {
  // 点击动作
}
```

### 按钮组件

#### PrimaryButton
```swift
PrimaryButton(
  title: "开始学习",
  icon: "play.circle",
  action: { }
)
```

#### SecondaryButton
```swift
SecondaryButton(
  title: "稍后再说",
  action: { }
)
```

#### IconButton
```swift
IconButton(
  icon: "plus",
  color: ModernColors.primary,
  backgroundColor: ModernColors.surface
) {
  // 点击动作
}
```

### 信息组件

#### Chip
```swift
Chip(
  label: "数学",
  icon: "function",
  isSelected: true,
  color: ModernColors.primary
) {
  // 选择动作
}
```

#### Badge
```swift
Badge(value: 5)                    // 显示数字
Badge(value: 99, isDot: true)      // 显示红点
```

#### ProgressBar
```swift
ProgressBar(progress: 0.75, color: ModernColors.primary)
```

#### CircularProgress
```swift
CircularProgress(progress: 0.6, size: 60)
```

### 状态组件

#### EmptyState
```swift
EmptyState(
  icon: "note.text",
  title: "暂无笔记",
  subtitle: "创建你的第一条笔记",
  actionTitle: "新建笔记",
  action: { }
)
```

#### LoadingState
```swift
LoadingState(message: "加载中...")
```

#### ErrorState
```swift
ErrorState(
  message: "加载失败",
  retryAction: { }
)
```

### 其他组件

#### SectionHeader
```swift
SectionHeader(
  icon: "book",
  title: "学习资料",
  actionTitle: "查看全部",
  showDivider: true
) {
  // 操作动作
}
```

#### Avatar
```swift
Avatar(
  imageURL: "https://...",
  name: "张三",
  size: 40
)
```

#### InfoRow
```swift
InfoRow(
  icon: "calendar",
  title: "创建时间",
  value: "2024-01-01",
  color: ModernColors.primary
)
```

---

## 📱 页面模板

### 自适应布局模式

#### 检测设备类型
```swift
@Environment(\.horizontalSizeClass) var horizontalSizeClass

private var isiPad: Bool {
  horizontalSizeClass == .regular
}
```

#### iPhone 布局
```swift
ScrollView(.horizontal, showsIndicators: false) {
  HStack(spacing: ModernSpacing.lg) {
    // 卡片内容
  }
}
```

#### iPad 布局
```swift
LazyVGrid(columns: ModernLayout.gridColumns2, spacing: ModernSpacing.lg) {
  // 卡片内容
}
```

### 双窗格布局 (iPad)
```swift
NavigationSplitView {
  // 侧边栏
  ListPane()
    .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 320)
} detail: {
  // 详情区
  DetailPane()
}
```

### 标准页面结构
```swift
struct ModernPageView: View {
  @EnvironmentObject var viewModel: AppViewModel
  @Environment(\.horizontalSizeClass) var horizontalSizeClass
  
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
  
  private var isiPad: Bool {
    horizontalSizeClass == .regular
  }
}
```

---

## 🔧 常用代码片段

### 创建卡片
```swift
ModernCard(variant: .elevated) {
  VStack(alignment: .leading, spacing: ModernSpacing.md) {
    Text("标题")
      .font(ModernTypography.titleMedium)
      .foregroundColor(ModernColors.textPrimary)
    
    Text("内容")
      .font(ModernTypography.body)
      .foregroundColor(ModernColors.textSecondary)
  }
}
```

### 创建按钮行
```swift
HStack(spacing: ModernSpacing.md) {
  PrimaryButton(title: "主要") { }
  SecondaryButton(title: "次要") { }
}
```

### 创建统计网格
```swift
LazyVGrid(columns: ModernLayout.gridColumns2, spacing: ModernSpacing.lg) {
  StatCard(/* ... */)
  StatCard(/* ... */)
  StatCard(/* ... */)
  StatCard(/* ... */)
}
```

### 创建搜索栏
```swift
HStack(spacing: ModernSpacing.sm) {
  Image(systemName: "magnifyingglass")
    .foregroundColor(ModernColors.textTertiary)
  
  TextField("搜索...", text: $searchText)
    .textFieldStyle(.plain)
  
  if !searchText.isEmpty {
    Button(action: { searchText = "" }) {
      Image(systemName: "xmark.circle.fill")
        .foregroundColor(ModernColors.textTertiary)
    }
  }
}
.padding(ModernSpacing.md)
.background(ModernColors.surface)
.cornerRadius(ModernCornerRadius.md)
```

### 创建筛选芯片组
```swift
ScrollView(.horizontal, showsIndicators: false) {
  HStack(spacing: ModernSpacing.sm) {
    ForEach(options, id: \.self) { option in
      Chip(
        label: option,
        isSelected: selectedOption == option,
        color: ModernColors.primary
      ) {
        selectedOption = option
      }
    }
  }
}
```

---

## 🎯 最佳实践

### 1. 始终使用设计令牌
❌ 不要硬编码颜色和数值
```swift
.foregroundColor(.blue)
.padding(15)
.cornerRadius(10)
```

✅ 使用设计令牌
```swift
.foregroundColor(ModernColors.primary)
.padding(ModernSpacing.lg)
.cornerRadius(ModernCornerRadius.lg)
```

### 2. 保持一致性
- 所有卡片使用相同的圆角
- 所有间距遵循 4pt 网格
- 所有文本使用预定义字体样式

### 3. 适配优先
- 先设计 iPad 布局
- 降级适配 iPhone
- 使用 `horizontalSizeClass` 检测

### 4. 状态处理
- 始终考虑空状态
- 添加加载状态
- 提供错误恢复

### 5. 可访问性
```swift
.accessibilityLabel("开始复习")
.accessibilityHint("点击开始今天的复习")
```

---

## 📦 文件结构
```
Sources/HuiLu/
├── DesignSystem/
│   ├── ModernDesignTokens.swift    # 设计令牌
│   └── ModernComponents.swift      # 组件库
└── Views/
    ├── ModernHomeView.swift        # 首页
    ├── ModernLibraryView.swift     # 资料库
    ├── ModernNotesSplitView.swift  # 笔记浏览
    └── ModernReviewView.swift      # 复习
```

---

## 🚀 下一步

1. **ViewModel 集成** - 替换模拟数据
2. **创建 NoteWorkspaceView** - 笔记编辑器
3. **创建 KnowledgePointView** - 知识点视图
4. **更新导航** - 集成到 ContentView

---

*快速参考 | 现代 UI 系统 | 2026*
