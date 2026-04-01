import SwiftUI

// MARK: - Learning Workspace Design System
// 温和玻璃感 + 低饱和蓝灰 + 少量高亮强调色
// iPad 优先优化，iPhone 保持简洁可用

// MARK: - Color Tokens

enum WorkspaceColors {
  // MARK: - Base Neutrals (低饱和蓝灰基调)
  
  /// 主背景：温和的浅蓝灰色
  static let backgroundPrimary = Color(red: 0.965, green: 0.970, blue: 0.980)
  
  /// 次要背景：略深的蓝灰，用于分区
  static let backgroundSecondary = Color(red: 0.940, green: 0.945, blue: 0.960)
  
  /// 卡片背景：半透明白色，轻微蓝调
  static let cardBackground = Color.white.opacity(0.92)
  
  /// 玻璃表面：轻度磨砂效果
  static let glassSurface = Color.white.opacity(0.75)
  
  // MARK: - Text Colors (文本层级)
  
  /// 主标题：深灰蓝，非纯黑
  static let textPrimary = Color(red: 0.180, green: 0.200, blue: 0.240)
  
  /// 正文：中等灰蓝
  static let textSecondary = Color(red: 0.320, green: 0.340, blue: 0.380)
  
  /// 辅助文字：浅灰蓝
  static let textTertiary = Color(red: 0.480, green: 0.500, blue: 0.540)
  
  /// 占位文字：更浅的灰
  static let textPlaceholder = Color(red: 0.640, green: 0.660, blue: 0.700)
  
  // MARK: - Accent Colors (强调色 - 克制使用)
  
  /// 主强调色：克制的靛蓝色 (用于关键操作、重点标记)
  static let accentIndigo = Color(red: 0.280, green: 0.360, blue: 0.620)
  
  /// 次要强调：柔和的青色 (用于知识点、链接)
  static let accentTeal = Color(red: 0.220, green: 0.520, blue: 0.560)
  
  /// 提醒色：温暖的珊瑚色 (非正红，更温和)
  static let accentCoral = Color(red: 0.920, green: 0.420, blue: 0.400)
  
  /// 成功色：沉静的松石绿
  static let accentTurquoise = Color(red: 0.240, green: 0.640, blue: 0.560)
  
  /// 警告色：柔和的琥珀色
  static let accentAmber = Color(red: 0.920, green: 0.680, blue: 0.280)
  
  // MARK: - Border & Divider (边框与分割线)
  
  /// 细边框：极淡的蓝灰
  static let borderLight = Color(red: 0.820, green: 0.840, blue: 0.880)
  
  /// 中等边框：用于选中状态
  static let borderMedium = Color(red: 0.680, green: 0.700, blue: 0.760)
  
  /// 分割线：半透明
  static let divider = Color(red: 0.720, green: 0.740, blue: 0.780).opacity(0.4)
  
  // MARK: - Semantic Colors (语义色)
  
  /// 引用块背景：极淡的靛蓝
  static let quoteBackground = Color(red: 0.920, green: 0.930, blue: 0.960)
  
  /// 引用块左边框：靛蓝色
  static let quoteBorder = WorkspaceColors.accentIndigo.opacity(0.4)
  
  /// 手写墨水背景：暖白色
  static let inkBackground = Color(red: 0.985, green: 0.980, blue: 0.970)
  
  /// 知识点芯片背景：淡青色
  static let knowledgePointBackground = Color(red: 0.900, green: 0.960, blue: 0.960)
  
  /// 知识点芯片边框：青绿色
  static let knowledgePointBorder = WorkspaceColors.accentTeal.opacity(0.5)
  
  // MARK: - Shadow Colors (阴影色 - 多层柔和)
  
  /// 轻阴影：用于卡片悬浮
  static let shadowLight = Color(red: 0.600, green: 0.640, blue: 0.700).opacity(0.12)
  
  /// 中阴影：用于悬浮面板
  static let shadowMedium = Color(red: 0.600, green: 0.640, blue: 0.700).opacity(0.18)
  
  /// 重阴影：用于模态层
  static let shadowHeavy = Color(red: 0.600, green: 0.640, blue: 0.700).opacity(0.28)
  
  // MARK: - Dark Mode Support (深色模式 - 可选)
  
  static let backgroundPrimaryDark = Color(red: 0.120, green: 0.140, blue: 0.180)
  static let backgroundSecondaryDark = Color(red: 0.160, green: 0.180, blue: 0.220)
  static let cardBackgroundDark = Color(red: 0.200, green: 0.220, blue: 0.260)
  static let textPrimaryDark = Color(red: 0.920, green: 0.930, blue: 0.950)
  static let textSecondaryDark = Color(red: 0.760, green: 0.780, blue: 0.820)
  static let textTertiaryDark = Color(red: 0.580, green: 0.600, blue: 0.640)
}

// MARK: - Typography Tokens

enum WorkspaceTypography {
  // MARK: - Font Families
  
  private static let primaryFont = Font.SystemFontType.rounded
  private static let monoFont = Font.SystemFontType.monospaced
  
  // MARK: - Display (超大标题 - 页面级)
  
  static let displayLarge = Font.system(size: 34, weight: .bold, design: primaryFont)
  static let displayMedium = Font.system(size: 28, weight: .bold, design: primaryFont)
  static let displaySmall = Font.system(size: 24, weight: .bold, design: primaryFont)
  
  // MARK: - Headline (章节标题)
  
  static let headlineLarge = Font.system(size: 22, weight: .semibold, design: primaryFont)
  static let headlineMedium = Font.system(size: 20, weight: .semibold, design: primaryFont)
  static let headlineSmall = Font.system(size: 18, weight: .semibold, design: primaryFont)
  
  // MARK: - Body (正文)
  
  /// 大正文：用于重要段落
  static let bodyLarge = Font.system(size: 17, weight: .regular, design: primaryFont)
  .lineSpacing(6)
  
  /// 标准正文：主要内容
  static let body = Font.system(size: 15, weight: .regular, design: primaryFont)
  .lineSpacing(5)
  
  /// 小正文：次要信息
  static let bodySmall = Font.system(size: 14, weight: .regular, design: primaryFont)
  .lineSpacing(4)
  
  // MARK: - Label (标签/说明)
  
  static let labelLarge = Font.system(size: 14, weight: .medium, design: primaryFont)
  static let label = Font.system(size: 13, weight: .medium, design: primaryFont)
  static let labelSmall = Font.system(size: 12, weight: .medium, design: primaryFont)
  
  // MARK: - Caption (图注/脚注)
  
  static let caption = Font.system(size: 12, weight: .regular, design: primaryFont)
  static let captionSmall = Font.system(size: 11, weight: .regular, design: primaryFont)
  
  // MARK: - Button (按钮文字)
  
  static let buttonLarge = Font.system(size: 17, weight: .semibold, design: primaryFont)
  static let button = Font.system(size: 15, weight: .semibold, design: primaryFont)
  static let buttonSmall = Font.system(size: 14, weight: .semibold, design: primaryFont)
  
  // MARK: - Code/Mono (代码/等宽)
  
  static let mono = Font.system(size: 14, weight: .regular, design: monoFont)
  .lineSpacing(4)
}

// MARK: - Spacing Tokens

enum WorkspaceSpacing {
  /// 极小间距：4pt
  static let xs: CGFloat = 4
  
  /// 小间距：8pt
  static let sm: CGFloat = 8
  
  /// 中小间距：12pt
  static let md: CGFloat = 12
  
  /// 标准间距：16pt
  static let lg: CGFloat = 16
  
  /// 大间距：20pt
  static let xl: CGFloat = 20
  
  /// 超大间距：24pt
  static let xxl: CGFloat = 24
  
  /// 极大间距：32pt
  static let xxxl: CGFloat = 32
  
  /// 页面边距 (iPad)
  static let pageMarginiPad: CGFloat = 32
  
  /// 页面边距 (iPhone)
  static let pageMarginiPhone: CGFloat = 20
  
  /// 卡片内边距
  static let cardPadding: CGFloat = 20
  
  /// 面板内边距
  static let panelPadding: CGFloat = 24
  
  /// 内容区最大宽度 (可读性优化)
  static let contentMaxWidth: CGFloat = 720
}

// MARK: - Corner Radius Tokens

enum WorkspaceCornerRadius {
  /// 极小圆角：6pt (芯片、小按钮)
  static let sm: CGFloat = 6
  
  /// 小圆角：10pt (按钮、输入框)
  static let md: CGFloat = 10
  
  /// 中圆角：14pt (卡片)
  static let lg: CGFloat = 14
  
  /// 大圆角：20pt (大卡片、面板)
  static let xl: CGFloat = 20
  
  /// 超大圆角：28pt (大型容器)
  static let xxl: CGFloat = 28
  
  /// 完全圆角：胶囊形
  static let capsule: CGFloat = 999
}

// MARK: - Shadow System

enum WorkspaceShadows {
  /// 悬浮卡片：轻柔悬浮感
  static let cardFloating = ShadowConfig(
    color: WorkspaceColors.shadowLight,
    radius: 12,
    x: 0,
    y: 4
  )
  
  /// 悬浮面板：更明显的悬浮
  static let panelFloating = ShadowConfig(
    color: WorkspaceColors.shadowMedium,
    radius: 16,
    x: 0,
    y: 6
  )
  
  /// 悬浮按钮：强调的可点击性
  static let buttonFloating = ShadowConfig(
    color: WorkspaceColors.accentIndigo.opacity(0.3),
    radius: 10,
    x: 0,
    y: 4
  )
  
  /// 按下状态：阴影收缩
  static let pressed = ShadowConfig(
    color: WorkspaceColors.shadowLight,
    radius: 6,
    x: 0,
    y: 2
  )
  
  /// 模态层：深度隔离
  static let modal = ShadowConfig(
    color: WorkspaceColors.shadowHeavy,
    radius: 24,
    x: 0,
    y: 12
  )
  
  struct ShadowConfig {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
    
    func toViewModifier() -> some ViewModifier {
      ShadowModifier(color: color, radius: radius, x: x, y: y)
    }
  }
  
  private struct ShadowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
    
    func body(content: Content) -> some View {
      content.shadow(color: color, radius: radius, x: x, y: y)
    }
  }
}

// MARK: - Animation Tokens

enum WorkspaceAnimations {
  /// 快速反馈：100ms
  static let quick: Double = 0.1
  
  /// 标准过渡：200ms
  static let standard: Double = 0.2
  
  /// 平滑过渡：300ms
  static let smooth: Double = 0.3
  
  /// 优雅过渡：400ms
  static let elegant: Double = 0.4
  
  /// 缓慢过渡：500ms (用于大尺度变化)
  static let slow: Double = 0.5
  
  // MARK: - Spring Presets
  
  /// 轻快弹簧：用于小按钮、芯片
  static let springLight = Animation.spring(response: 0.15, dampingFraction: 0.85, blendDuration: 0.1)
  
  /// 标准弹簧：用于卡片、面板切换
  static let springStandard = Animation.spring(response: 0.25, dampingFraction: 0.82, blendDuration: 0.15)
  
  /// 柔和弹簧：用于页面过渡
  static let springSoft = Animation.spring(response: 0.35, dampingFraction: 0.80, blendDuration: 0.2)
  
  /// 弹性弹簧：用于强调反馈
  static let springBouncy = Animation.spring(response: 0.30, dampingFraction: 0.70, blendDuration: 0.15)
  
  // MARK: - Transition Presets
  
  /// 淡入上移：用于内容切换
  static let fadeInSlideUp = AnyTransition.asymmetric(
    insertion: .move(edge: .bottom).combined(with: .opacity),
    removal: .opacity
  )
  
  /// 缩放淡入：用于卡片展开
  static let scaleFadeIn = AnyTransition.scale.combined(with: .opacity)
  
  /// 滑入：用于侧边面板
  static let slideIn = AnyTransition.move(edge: .trailing).combined(with: .opacity)
}

// MARK: - Layout Constants

enum WorkspaceLayout {
  // MARK: - iPad Layout
  
  /// iPad 笔记列表宽度
  static let notesListWidthiPad: CGFloat = 380
  
  /// iPad 笔记详情最小宽度
  static let noteDetailMinWidthiPad: CGFloat = 500
  
  /// iPad 侧边栏宽度
  static let sidebarWidthiPad: CGFloat = 320
  
  /// iPad 浮动面板最大宽度
  static let floatingPanelMaxWidthiPad: CGFloat = 400
  
  // MARK: - iPhone Layout
  
  /// iPhone 卡片水平间距
  static let cardHorizontalMarginiPhone: CGFloat = 20
  
  /// iPhone 全屏页边距
  static let fullScreenMarginiPhone: CGFloat = 16
  
  // MARK: - Responsive Breakpoints
  
  /// 紧凑布局断点
  static let compactWidth: CGFloat = 600
  
  /// 常规布局断点
  static let regularWidth: CGFloat = 900
  
  /// 宽敞布局断点
  static let expandedWidth: CGFloat = 1200
}

// MARK: - Z-Index Layers

enum WorkspaceLayers {
  static let background: Double = 0
  static let cards: Double = 10
  static let panels: Double = 20
  static let overlays: Double = 30
  static let floating: Double = 40
  static let modals: Double = 50
  static let popovers: Double = 60
}

// MARK: - Glass Material Presets

enum WorkspaceGlass {
  /// 轻度磨砂：用于卡片
  static let light = Material.ultraThinMaterial.opacity(0.7)
  
  /// 中度磨砂：用于面板
  static let medium = Material.thinMaterial.opacity(0.75)
  
  /// 重度磨砂：用于浮层
  static let heavy = Material.regularMaterial.opacity(0.8)
  
  /// 背景虚化：用于 backdrop
  static let backdrop = Material.ultraThinMaterial.opacity(0.5)
}

// MARK: - Divider Styles

enum WorkspaceDividerStyles {
  /// 细分割线：用于列表项之间
  static let thin = DividerStyleConfig(height: 0.5, opacity: 0.4)
  
  /// 标准分割线：用于区块之间
  static let standard = DividerStyleConfig(height: 1.0, opacity: 0.5)
  
  /// 粗分割线：用于重要分区
  static let thick = DividerStyleConfig(height: 2.0, opacity: 0.6)
  
  struct DividerStyleConfig {
    let height: CGFloat
    let opacity: Double
    
    func toView() -> some View {
      Rectangle()
        .fill(WorkspaceColors.divider.opacity(opacity))
        .frame(height: height)
    }
  }
}

// MARK: - Interactive States

enum WorkspaceInteractiveStates {
  /// 悬停放大：1.02x
  static let hoverScale: CGFloat = 1.02
  
  /// 按下缩小：0.98x
  static let pressScale: CGFloat = 0.98
  
  /// 选中边框宽度
  static let selectedBorderWidth: CGFloat = 2.5
  
  /// 焦点光环宽度
  static let focusRingWidth: CGFloat = 3
  
  /// 焦点光环颜色
  static let focusRingColor = WorkspaceColors.accentIndigo.opacity(0.4)
}

// MARK: - Accessibility

enum WorkspaceAccessibility {
  /// 最小点击区域
  static let minimumTapSize: CGFloat = 44
  
  /// 大字模式标题缩放
  static let largeTitleScale: CGFloat = 1.15
  
  /// 大字模式正文字缩放
  static let largeBodyScale: CGFloat = 1.10
  
  /// 减少动态效果检测
  static var prefersReducedMotion: Bool {
    UIAccessibility.isReduceMotionEnabled
  }
  
  /// 高对比度检测
  static var isHighContrast: Bool {
    UIAccessibility.isBoldTextEnabled
  }
}
