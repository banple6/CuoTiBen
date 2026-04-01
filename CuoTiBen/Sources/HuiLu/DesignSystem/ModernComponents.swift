import SwiftUI

// MARK: - Modern UI Components 2026
// Professional, Polished, Accessible

// MARK: - ModernCard
/// Versatile card component with multiple variants
struct ModernCard: View {
  enum Variant {
    case elevated, outlined, filled, gradient
  }
  
  let variant: Variant
  let content: () -> AnyView
  let onTap: (() -> Void)?
  
  @State private var isPressed = false
  @State private var isHovered = false
  
  init(variant: Variant = .elevated, onTap: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> some View) {
    self.variant = variant
    self.onTap = onTap
    self.content = { AnyView(content()) }
  }
  
  var body: some View {
    Button(action: {
      if onTap != nil {
        withAnimation(ModernAnimations.springSnappy) {
          isPressed = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          withAnimation(ModernAnimations.springSnappy) {
            isPressed = false
          }
        }
        onTap?()
      }
    }) {
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ModernSpacing.cardPadding)
        .background(backgroundView)
        .overlay(overlayView)
        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: isPressed ? 2 : 4)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .cornerRadius(ModernCornerRadius.lg)
    }
    .buttonStyle(.plain)
  }
  
  @ViewBuilder
  private var backgroundView: some View {
    switch variant {
    case .elevated:
      ModernColors.surface
    case .outlined:
      ModernColors.surface
    case .filled:
      ModernColors.surfaceVariant
    case .gradient:
      ModernColors.warmGradient
    }
  }
  
  @ViewBuilder
  private var overlayView: some View {
    switch variant {
    case .outlined:
      RoundedRectangle(cornerRadius: ModernCornerRadius.lg)
        .stroke(ModernColors.outline, lineWidth: 1)
    default:
      EmptyView()
    }
  }
  
  private var shadowColor: Color {
    if isPressed {
      return ModernColors.shadowLight
    } else if isHovered {
      return ModernColors.shadowMedium
    } else {
      return ModernColors.shadowLight
    }
  }
  
  private var shadowRadius: CGFloat {
    if isPressed {
      return 8
    } else if isHovered {
      return 16
    } else {
      return 12
    }
  }
}

// MARK: - StatCard
/// Statistics display card with icon, value, and label
struct StatCard: View {
  let icon: String
  let value: String
  let label: String
  let accentColor: Color
  let trend: String?
  let onTap: (() -> Void)?
  
  init(
    icon: String,
    value: String,
    label: String,
    accentColor: Color = ModernColors.primary,
    trend: String? = nil,
    onTap: (() -> Void)? = nil
  ) {
    self.icon = icon
    self.value = value
    self.label = label
    self.accentColor = accentColor
    self.trend = trend
    self.onTap = onTap
  }
  
  var body: some View {
    ModernCard(variant: .elevated, onTap: onTap) {
      VStack(alignment: .leading, spacing: ModernSpacing.md) {
        // Icon
        HStack {
          Image(systemName: icon)
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(accentColor)
            .frame(width: 44, height: 44)
            .background(
              RoundedRectangle(cornerRadius: ModernCornerRadius.md)
                .fill(accentColor.opacity(0.1))
            )
          
          if let trend = trend {
            Spacer()
            Text(trend)
              .font(ModernTypography.labelSmall)
              .foregroundColor(ModernColors.success)
              .fontWeight(.semibold)
          }
        }
        
        // Value
        Text(value)
          .font(ModernTypography.displaySmall)
          .foregroundColor(ModernColors.textPrimary)
          .fontWeight(.bold)
        
        // Label
        Text(label)
          .font(ModernTypography.label)
          .foregroundColor(ModernColors.textSecondary)
      }
    }
  }
}

// MARK: - ActionCard
/// Quick action card with icon and label
struct ActionCard: View {
  let icon: String
  let label: String
  let color: Color
  let action: () -> Void
  
  var body: some View {
    Button(action: action) {
      VStack(spacing: ModernSpacing.sm) {
        Image(systemName: icon)
          .font(.system(size: 24, weight: .semibold))
          .foregroundColor(color)
          .frame(width: 64, height: 64)
          .background(
            Circle()
              .fill(color.opacity(0.1))
          )
        
        Text(label)
          .font(ModernTypography.label)
          .foregroundColor(ModernColors.textSecondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(ModernSpacing.xl)
      .background(ModernColors.surface)
      .cornerRadius(ModernCornerRadius.xl)
      .shadow(color: ModernColors.shadowLight, radius: 12, x: 0, y: 4)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - SectionHeader
/// Section header with icon, title, and optional action
struct SectionHeader: View {
  let icon: String
  let title: String
  let actionTitle: String?
  let action: (() -> Void)?
  let showDivider: Bool
  
  init(
    icon: String,
    title: String,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil,
    showDivider: Bool = true
  ) {
    self.icon = icon
    self.title = title
    self.actionTitle = actionTitle
    self.action = action
    self.showDivider = showDivider
  }
  
  var body: some View {
    VStack(spacing: ModernSpacing.sm) {
      HStack(spacing: ModernSpacing.md) {
        // Icon container
        Image(systemName: icon)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(ModernColors.primary)
          .frame(width: 32, height: 32)
          .background(
            RoundedRectangle(cornerRadius: ModernCornerRadius.sm)
              .fill(ModernColors.primary.opacity(0.1))
          )
        
        // Title
        Text(title)
          .font(ModernTypography.headlineMedium)
          .foregroundColor(ModernColors.textPrimary)
          .fontWeight(.semibold)
        
        Spacer()
        
        // Action
        if let actionTitle = actionTitle, let action = action {
          Button(action: action) {
            Text(actionTitle)
              .font(ModernTypography.label)
              .foregroundColor(ModernColors.primary)
              .fontWeight(.medium)
          }
        }
      }
      
      // Divider
      if showDivider {
        Rectangle()
          .fill(ModernColors.outlineVariant)
          .frame(height: 1)
      }
    }
    .padding(.bottom, ModernSpacing.lg)
  }
}

// MARK: - PrimaryButton
/// Primary action button with gradient background
struct PrimaryButton: View {
  let title: String
  let icon: String?
  let action: () -> Void
  let isLoading: Bool
  let disabled: Bool
  
  @State private var isPressed = false
  
  init(
    title: String,
    icon: String? = nil,
    isLoading: Bool = false,
    disabled: Bool = false,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.icon = icon
    self.isLoading = isLoading
    self.disabled = disabled
    self.action = action
  }
  
  var body: some View {
    Button(action: {
      if !disabled && !isLoading {
        withAnimation(ModernAnimations.springSnappy) {
          isPressed = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          withAnimation(ModernAnimations.springSnappy) {
            isPressed = false
          }
        }
        action()
      }
    }) {
      HStack(spacing: ModernSpacing.md) {
        if isLoading {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: ModernColors.textInverse))
        }
        
        Text(title)
          .font(ModernTypography.labelLarge)
          .fontWeight(.semibold)
        
        if let icon = icon {
          Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
        }
      }
      .foregroundColor(ModernColors.textInverse)
      .frame(maxWidth: .infinity)
      .frame(height: 52)
      .background(buttonBackground)
      .cornerRadius(ModernCornerRadius.md)
      .shadow(color: ModernColors.coloredShadow.opacity(isPressed ? 0.15 : 0.2), radius: isPressed ? 8 : 12, x: 0, y: isPressed ? 2 : 4)
      .scaleEffect(isPressed ? 0.98 : 1.0)
      .opacity(disabled ? 0.6 : 1.0)
    }
    .buttonStyle(.plain)
  }
  
  private var buttonBackground: some View {
    Group {
      if disabled || isLoading {
        Color.gray.opacity(0.3)
      } else {
        ModernColors.primaryGradient
      }
    }
  }
}

// MARK: - SecondaryButton
/// Secondary button with outline style
struct SecondaryButton: View {
  let title: String
  let icon: String?
  let action: () -> Void
  let disabled: Bool
  
  @State private var isPressed = false
  
  init(
    title: String,
    icon: String? = nil,
    disabled: Bool = false,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.icon = icon
    self.disabled = disabled
    self.action = action
  }
  
  var body: some View {
    Button(action: {
      if !disabled {
        withAnimation(ModernAnimations.springSnappy) {
          isPressed = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          withAnimation(ModernAnimations.springSnappy) {
            isPressed = false
          }
        }
        action()
      }
    }) {
      HStack(spacing: ModernSpacing.md) {
        if let icon = icon {
          Image(systemName: icon)
            .font(.system(size: 16, weight: .medium))
        }
        
        Text(title)
          .font(ModernTypography.labelLarge)
          .fontWeight(.semibold)
      }
      .foregroundColor(ModernColors.primary)
      .frame(maxWidth: .infinity)
      .frame(height: 52)
      .background(ModernColors.surface)
      .overlay(
        RoundedRectangle(cornerRadius: ModernCornerRadius.md)
          .stroke(ModernColors.primary.opacity(0.3), lineWidth: 1.5)
      )
      .cornerRadius(ModernCornerRadius.md)
      .scaleEffect(isPressed ? 0.98 : 1.0)
      .opacity(disabled ? 0.6 : 1.0)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - IconButton
/// Icon-only button for toolbars and actions
struct IconButton: View {
  let icon: String
  let label: String?
  let color: Color
  let backgroundColor: Color
  let action: () -> Void
  
  @State private var isPressed = false
  
  init(
    icon: String,
    label: String? = nil,
    color: Color = ModernColors.primary,
    backgroundColor: Color = ModernColors.surfaceVariant,
    action: @escaping () -> Void
  ) {
    self.icon = icon
    self.label = label
    self.color = color
    self.backgroundColor = backgroundColor
    self.action = action
  }
  
  var body: some View {
    Button(action: {
      withAnimation(ModernAnimations.springSnappy) {
        isPressed = true
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        withAnimation(ModernAnimations.springSnappy) {
          isPressed = false
        }
      }
      action()
    }) {
      VStack(spacing: ModernSpacing.xs) {
        Image(systemName: icon)
          .font(.system(size: label == nil ? 20 : 18, weight: .semibold))
          .foregroundColor(color)
          .frame(width: label == nil ? 48 : 44, height: label == nil ? 48 : 44)
          .background(
            Circle()
              .fill(backgroundColor)
          )
        
        if let label = label {
          Text(label)
            .font(ModernTypography.captionSmall)
            .foregroundColor(ModernColors.textSecondary)
        }
      }
      .scaleEffect(isPressed ? 0.92 : 1.0)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Chip
/// Selectable chip/tag component
struct Chip: View {
  let label: String
  let icon: String?
  let isSelected: Bool
  let color: Color
  let action: () -> Void
  
  @State private var isPressed = false
  
  init(
    label: String,
    icon: String? = nil,
    isSelected: Bool = false,
    color: Color = ModernColors.primary,
    action: @escaping () -> Void
  ) {
    self.label = label
    self.icon = icon
    self.isSelected = isSelected
    self.color = color
    self.action = action
  }
  
  var body: some View {
    Button(action: {
      withAnimation(ModernAnimations.springSnappy) {
        isPressed = true
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        withAnimation(ModernAnimations.springSnappy) {
          isPressed = false
        }
      }
      action()
    }) {
      HStack(spacing: ModernSpacing.xs) {
        if let icon = icon {
          Image(systemName: icon)
            .font(.system(size: 12, weight: .medium))
        }
        
        Text(label)
          .font(ModernTypography.label)
          .fontWeight(.medium)
      }
      .foregroundColor(isSelected ? ModernColors.textInverse : color)
      .padding(.horizontal, ModernSpacing.md)
      .padding(.vertical, ModernSpacing.sm)
      .background(
        Capsule()
          .fill(isSelected ? color : color.opacity(0.1))
      )
      .scaleEffect(isPressed ? 0.95 : 1.0)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - ProgressBar
/// Linear progress indicator
struct ProgressBar: View {
  let progress: Double
  let showLabel: Bool
  let height: CGFloat
  let color: Color
  
  init(
    progress: Double,
    showLabel: Bool = true,
    height: CGFloat = 8,
    color: Color = ModernColors.primary
  ) {
    self.progress = min(max(progress, 0), 1)
    self.showLabel = showLabel
    self.height = height
    self.color = color
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.xs) {
      if showLabel {
        HStack {
          Text("\(Int(progress * 100))%")
            .font(ModernTypography.caption)
            .foregroundColor(ModernColors.textSecondary)
          
          Spacer()
        }
      }
      
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          // Background track
          RoundedRectangle(cornerRadius: height / 2)
            .fill(ModernColors.outlineVariant)
            .frame(height: height)
          
          // Progress fill
          RoundedRectangle(cornerRadius: height / 2)
            .fill(color)
            .frame(width: geometry.size.width * progress, height: height)
            .animation(.easeInOut(duration: 0.3), value: progress)
        }
      }
      .frame(height: height)
    }
  }
}

// MARK: - CircularProgress
/// Circular progress indicator
struct CircularProgress: View {
  let progress: Double
  let size: CGFloat
  let lineWidth: CGFloat
  let color: Color
  let backgroundColor: Color
  let showPercentage: Bool
  
  init(
    progress: Double,
    size: CGFloat = 120,
    lineWidth: CGFloat = 12,
    color: Color = ModernColors.primary,
    backgroundColor: Color = ModernColors.outlineVariant,
    showPercentage: Bool = true
  ) {
    self.progress = min(max(progress, 0), 1)
    self.size = size
    self.lineWidth = lineWidth
    self.color = color
    self.backgroundColor = backgroundColor
    self.showPercentage = showPercentage
  }
  
  var body: some View {
    ZStack {
      // Background circle
      Circle()
        .stroke(backgroundColor, lineWidth: lineWidth)
        .frame(width: size, height: size)
      
      // Progress circle
      Circle()
        .trim(from: 0, to: progress)
        .stroke(
          color,
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-90))
        .animation(.easeInOut(duration: 0.5), value: progress)
      
      // Percentage text
      if showPercentage {
        VStack(spacing: 2) {
          Text("\(Int(progress * 100))%")
            .font(ModernTypography.headlineLarge)
            .fontWeight(.bold)
            .foregroundColor(ModernColors.textPrimary)
          
          Text("完成度")
            .font(ModernTypography.caption)
            .foregroundColor(ModernColors.textTertiary)
        }
      }
    }
  }
}

// MARK: - EmptyState
/// Empty state component for lists and content areas
struct EmptyState: View {
  let icon: String
  let title: String
  let subtitle: String
  let actionTitle: String?
  let action: (() -> Void)?
  
  init(
    icon: String,
    title: String,
    subtitle: String,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.icon = icon
    self.title = title
    self.subtitle = subtitle
    self.actionTitle = actionTitle
    self.action = action
  }
  
  var body: some View {
    VStack(spacing: ModernSpacing.lg) {
      Image(systemName: icon)
        .font(.system(size: 64, weight: .light))
        .foregroundColor(ModernColors.textTertiary)
        .frame(width: 100, height: 100)
        .background(
          Circle()
            .fill(ModernColors.surfaceVariant)
        )
      
      VStack(spacing: ModernSpacing.sm) {
        Text(title)
          .font(ModernTypography.headlineSmall)
          .foregroundColor(ModernColors.textPrimary)
          .fontWeight(.semibold)
        
        Text(subtitle)
          .font(ModernTypography.body)
          .foregroundColor(ModernColors.textTertiary)
          .multilineTextAlignment(.center)
      }
      
      if let actionTitle = actionTitle, let action = action {
        PrimaryButton(title: actionTitle, action: action)
          .frame(width: 200)
      }
    }
    .padding(ModernSpacing.xxl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - LoadingState
/// Loading state component
struct LoadingState: View {
  let message: String
  
  var body: some View {
    VStack(spacing: ModernSpacing.lg) {
      ProgressView()
        .scaleEffect(1.5)
        .progressViewStyle(CircularProgressViewStyle(tint: ModernColors.primary))
      
      Text(message)
        .font(ModernTypography.body)
        .foregroundColor(ModernColors.textTertiary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - ErrorState
/// Error state component
struct ErrorState: View {
  let message: String
  let retryAction: () -> Void
  
  var body: some View {
    VStack(spacing: ModernSpacing.lg) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 48, weight: .medium))
        .foregroundColor(ModernColors.error)
      
      Text(message)
        .font(ModernTypography.body)
        .foregroundColor(ModernColors.textSecondary)
        .multilineTextAlignment(.center)
      
      PrimaryButton(title: "重试", icon: "arrow.clockwise", action: retryAction)
        .frame(width: 150)
    }
    .padding(ModernSpacing.xxl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Badge
/// Notification badge component
struct Badge: View {
  let count: Int?
  let color: Color
  
  init(count: Int?, color: Color = ModernColors.error) {
    self.count = count
    self.color = color
  }
  
  var body: some View {
    Group {
      if let count = count, count > 0 {
        Text(count > 99 ? "99+" : "\(count)")
          .font(ModernTypography.captionSmall)
          .fontWeight(.bold)
          .foregroundColor(ModernColors.textInverse)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(color)
          .cornerRadius(ModernCornerRadius.circle)
      } else if count == nil {
        Circle()
          .fill(color)
          .frame(width: 8, height: 8)
      }
    }
  }
}

// MARK: - Avatar
/// User avatar component
struct Avatar: View {
  let name: String
  let imageURL: String?
  let size: CGFloat
  
  init(name: String, imageURL: String? = nil, size: CGFloat = 40) {
    self.name = name
    self.imageURL = imageURL
    self.size = size
  }
  
  var body: some View {
    ZStack {
      Circle()
        .fill(ModernColors.primary.opacity(0.1))
        .frame(width: size, height: size)
      
      if let imageURL = imageURL {
        AsyncImage(url: URL(string: imageURL)) { image in
          image.resizable()
            .aspectRatio(contentMode: .fill)
        } placeholder: {
          initials
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
      } else {
        initials
      }
    }
  }
  
  private var initials: some View {
    Text(String(name.prefix(2)).uppercased())
      .font(.system(size: size * 0.4, weight: .semibold))
      .foregroundColor(ModernColors.primary)
  }
}

// MARK: - Preview

#Preview {
  ScrollView {
    VStack(spacing: ModernSpacing.xxl) {
      // Section Header
      SectionHeader(
        icon: "chart.bar",
        title: "学习统计",
        actionTitle: "查看全部",
        action: {}
      )
      
      // Stat Cards
      LazyVGrid(columns: ModernLayout.gridColumns2, spacing: ModernSpacing.md) {
        StatCard(
          icon: "timer",
          value: "2h 15m",
          label: "学习时长",
          accentColor: ModernColors.primary,
          trend: "+12%"
        )
        
        StatCard(
          icon: "book.fill",
          value: "3",
          label: "阅读材料",
          accentColor: ModernColors.accent
        )
      }
      
      // Action Cards
      HStack(spacing: ModernSpacing.md) {
        ActionCard(
          icon: "plus.app",
          label: "新建笔记",
          color: ModernColors.primary,
          action: {}
        )
        
        ActionCard(
          icon: "book.badge.plus",
          label: "导入资料",
          color: ModernColors.accent,
          action: {}
        )
      }
      
      // Buttons
      PrimaryButton(title: "开始学习", icon: "play.fill", action: {})
      SecondaryButton(title: "稍后提醒", icon: "clock", action: {})
      
      // Chips
      HStack(spacing: ModernSpacing.sm) {
        Chip(label: "全部", isSelected: true, action: {})
        Chip(label: "进行中", icon: "clock", action: {})
        Chip(label: "已完成", icon: "checkmark.circle", action: {})
      }
      
      // Progress
      ProgressBar(progress: 0.67, showLabel: true)
      
      CircularProgress(progress: 0.75, size: 100)
      
      // States
      EmptyState(
        icon: "note.text",
        title: "暂无笔记",
        subtitle: "开始阅读材料或手动创建第一条笔记",
        actionTitle: "新建笔记",
        action: {}
      )
    }
    .padding(ModernSpacing.xxl)
  }
  .background(ModernColors.background)
}
