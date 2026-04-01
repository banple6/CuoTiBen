# 🎨 快速参考卡 - 错题本新 UI 系统

## 📦 核心组件速查

### 背景
```swift
AuroraBackground(mode: .dark)  // 深色动态背景
AuroraBackground(mode: .light) // 浅色动态背景
```

### 面板
```swift
PremiumGlassPanel(tone: .dark, cornerRadius: 32, padding: 24) {
    // 内容
}
```

### 按钮
```swift
// 主按钮
ElegantButton(title: "开始", icon: "play.fill", style: .primary) { }

// 次要按钮
ElegantButton(title: "取消", icon: nil, style: .secondary) { }

// 悬浮按钮
FloatingActionButton(icon: "plus", backgroundColor: .electricBlue) { }
```

### 卡片
```swift
// 悬浮卡片
ModernCard(style: .elevated, accentColor: .electricBlue) { }

// 平面卡片
ModernCard(style: .flat) { }

// 高亮卡片
ModernCard(style: .highlighted, accentColor: .auroraGreen) { }
```

### 标签
```swift
ModernChip(text: "标签", icon: "tag", accentColor: .electricBlue)
InfoChip(icon: "clock", text: "5 分钟")
MetaBadge(icon: "doc", text: "12 页")
```

### 标题
```swift
ElegantSectionHeader(
    title: "学习统计",
    subtitle: "每天进步一点点",
    icon: "chart.bar.fill",
    accentColor: .electricBlue
)
```

---

## 🎨 配色方案

### 深色模式强调色
```swift
Electric Blue:   Color(red: 0.0, green: 0.48, blue: 1.0)    // 主色调
Aurora Green:    Color(red: 0.2, green: 0.85, blue: 0.65)   // 成功/积极
Sunset Orange:   Color(red: 1.0, green: 0.55, blue: 0.2)    // 警告/注意
Magenta Dream:   Color(red: 0.95, green: 0.3, blue: 0.7)    // 特殊/亮点
Cyan Glow:       Color(red: 0.0, green: 0.85, blue: 0.95)   // 辅助色
```

### 文字颜色
```swift
// 深色模式
.primaryTextDark    // 95% 白 - 主要文字
.secondaryTextDark  // 75% 白 - 次要文字
.tertiaryTextDark   // 55% 白 - 提示文字

// 浅色模式
.primaryTextLight   // 85% 黑
.secondaryTextLight // 60% 黑
.tertiaryTextLight  // 40% 黑
```

---

## 📐 常用间距

```swift
spacing: 6   // 极小间距（徽章内）
spacing: 10  // 小间距（芯片内）
spacing: 14  // 中小间距
spacing: 16  // 标准间距（卡片内）
spacing: 18  // 中大间距
spacing: 20  // 大间距（区块内）
spacing: 24  // 标准大间距
spacing: 28  // 超大间距
spacing: 32  // 极大间距
```

---

## 🔠 字体大小

```swift
// 标题
Font.system(size: 34, weight: .bold, design: .rounded)    // 超大标题
Font.system(size: 24, weight: .bold, design: .rounded)    // 大标题
Font.system(size: 20, weight: .bold, design: .rounded)    // 中标题
Font.system(size: 16, weight: .semibold)                  // 小标题

// 正文
Font.system(size: 15, weight: .medium)                    // 大正文
Font.system(size: 14, weight: .medium)                    // 标准正文
Font.system(size: 13, weight: .medium)                    // 小说文
Font.system(size: 11, weight: .medium)                    // 微小文字
```

---

## 🎭 常用动画

```swift
// 标准弹簧动画
withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { }

// 快速响应
withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) { }

// 平滑过渡
withAnimation(.easeInOut(duration: 0.3)) { }

// 按钮按压动画
withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
    scaleEffect(0.96)
}
```

---

## 📱 页面模板

### 标准页面结构
```swift
ZStack {
    AuroraBackground(mode: .dark)
    
    ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 32) {
            // 1. 头部（58px top padding）
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("标题")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("副标题")
                        .font(.system(size: 14, weight: .medium))
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 58)
            .padding(.bottom: 24)
            
            // 2. 主要内容
            // ...
            
            Spacer(minLength: 140) // 为标签栏留空间
        }
    }
}
```

### 卡片网格布局
```swift
GeometryReader { geometry in
    let columns = geometry.size.width > 1000 ? 3 : 
                 (geometry.size.width > 700 ? 2 : 1)
    
    ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 16) {
            ForEach(items) { item in
                ModernCard(style: .elevated) { }
            }
        }
        .padding(.horizontal, 24)
    }
}
```

---

## 🔍 常用 SF Symbols

### 学习相关
```
book.fill, character.book.closed.fill
note.text, graduationcap.fill
pencil.and.outline, sparkles
```

### 统计相关
```
chart.bar.fill, chart.line.uptrend.xyaxis
flame.fill, bolt.fill, clock.fill
target, gauge.medium
```

### 状态相关
```
checkmark.circle.fill, exclamationmark.triangle.fill
info.circle.fill, xmark.circle.fill
bell.fill, star.fill
```

### 导航相关
```
house.fill, books.vertical.fill
note.text, checklist
gearshape.fill, person.fill
```

---

## 🎯 快速渐变

```swift
// 蓝色系（首页/英语）
LinearGradient(colors: [.electricBlue, .cyanGlow], 
               startPoint: .leading, endPoint: .trailing)

// 绿色系（成功/完成）
LinearGradient(colors: [.auroraGreen, .cyanGlow], 
               startPoint: .leading, endPoint: .trailing)

// 橙色系（警告/复习）
LinearGradient(colors: [.sunsetOrange, .magentaDream], 
               startPoint: .leading, endPoint: .trailing)

// 粉色系（笔记/特殊）
LinearGradient(colors: [.magentaDream, .sunsetOrange], 
               startPoint: .leading, endPoint: .trailing)
```

---

## 💡 实用技巧

### 1. 创建光泽效果
```swift
.overlay(
    LinearGradient(colors: [.white.opacity(0.2), .clear],
                   startPoint: .top, endPoint: .bottom)
)
```

### 2. 创建发光效果
```swift
.shadow(color: .electricBlue.opacity(0.4), radius: 12, y: 6)
```

### 3. 创建玻璃边框
```swift
.overlay(
    RoundedRectangle(cornerRadius: 24)
        .stroke(EnhancedPalette.glassBorder, lineWidth: 1.2)
)
```

### 4. 检测性能模式
```swift
if !AppPerformance.prefersReducedEffects {
    // 展示复杂动画
}
```

---

## ⚡ 性能提示

```swift
// ✅ 推荐：缓存复杂背景
.background(complexGradient, shouldRasterize: true)

// ✅ 推荐：条件渲染动画
if !AppPerformance.prefersReducedEffects {
    // 动画代码
}

// ✅ 推荐：延迟加载非关键内容
Task { @MainActor in
    try? await Task.sleep(nanoseconds: 180_000_000)
    // 加载次要内容
}

// ❌ 避免：过度的模糊效果
.blur(radius: 100) // 太费性能

// ❌ 避免：过多的嵌套 ZStack
ZStack {
    ZStack {
        ZStack { // 不要超过 3 层
        }
    }
}
```

---

## 🎪 完整示例

### 统计卡片
```swift
struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let gradient: LinearGradient
    
    var body: some View {
        PremiumGlassPanel(tone: .dark, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(gradient)
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.tertiaryTextDark)
                
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(width: 156, alignment: .leading)
        }
    }
}
```

---

## 📞 快速链接

- **完整设计指南**: `UI_DESIGN_GUIDE.md`
- **迁移指南**: `MIGRATION_GUIDE.md`
- **新增文件**:
  - `EnhancedUIComponents.swift` - 基础组件
  - `EnhancedTabBar.swift` - 标签栏
  - `EnhancedHomeView.swift` - 首页
  - `EnhancedLibraryView.swift` - 知识库
  - `EnhancedReviewListView.swift` - 复习列表

---

**版本**: v2.0  
**更新日期**: 2026 年 3 月 29 日
