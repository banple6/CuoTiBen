import SwiftUI

// MARK: - Workspace Core Components
// 统一组件语言：温和玻璃感 + 明确层级 + 克制交互

// MARK: - AppPageHeader
/// 页面头部：标题 + 副标题 + 可选操作
public struct AppPageHeader: View {
  let title: String
  let subtitle: String?
  let leadingAction: (() -> Void)?
  let trailingActions: [(() -> Void, String, Image)?]
  
  public init(
    title: String,
    subtitle: String? = nil,
    leadingAction: (() -> Void)? = nil,
    trailingActions: [(() -> Void, String, Image)?] = []
  ) {
    self.title = title
    self.subtitle = subtitle
    self.leadingAction = leadingAction
    self.trailingActions = trailingActions
  }
  
  public var body: some View {
    VStack(alignment: .leading, spacing: WorkspaceSpacing.sm) {
      // Top row: leading action + title + trailing actions
      HStack(spacing: WorkspaceSpacing.lg) {
        // Leading action
        if let leadingAction = leadingAction {
          Button(action: leadingAction) {
            Image(systemName: "chevron.left")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(WorkspaceColors.textPrimary)
              .frame(width: 40, height: 40)
              .background(WorkspaceColors.glassSurface)
              .clipShape(Circle())
          }
        }
        
        // Title
        Text(title)
          .font(WorkspaceTypography.displaySmall)
          .foregroundColor(WorkspaceColors.textPrimary)
          .fontWeight(.bold)
        
        Spacer()
        
        // Trailing actions
        HStack(spacing: WorkspaceSpacing.md) {
          ForEach(trailingActions.indices, id: \.self) { index in
            if let (action, label, icon) = trailingActions[index] {
              Button(action: action) {
                VStack(spacing: 2) {
                  icon
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(WorkspaceColors.accentIndigo)
                  Text(label)
                    .font(WorkspaceTypography.labelSmall)
                    .foregroundColor(WorkspaceColors.accentIndigo)
                }
              }
            }
          }
        }
      }
      
      // Subtitle
      if let subtitle = subtitle {
        Text(subtitle)
          .font(WorkspaceTypography.body)
          .foregroundColor(WorkspaceColors.textSecondary)
          .padding(.top, 2)
      }
    }
    .padding(.horizontal, WorkspaceLayout.cardHorizontalMarginiPhone)
    .padding(.top, WorkspaceSpacing.xxl)
    .padding(.bottom, WorkspaceSpacing.lg)
  }
}

// MARK: - SectionHeader
/// 区块头部：图标 + 标题 + 可选操作
public struct SectionHeader: View {
  let icon: String
  let title: String
  let actionTitle: String?
  let action: (() -> Void)?
  let showDivider: Bool
  
  public init(
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
  
  public var body: some View {
    VStack(spacing: WorkspaceSpacing.sm) {
      HStack(spacing: WorkspaceSpacing.md) {
        // Icon
        Image(systemName: icon)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(WorkspaceColors.accentIndigo)
          .frame(width: 28, height: 28)
          .background(
            RoundedRectangle(cornerRadius: WorkspaceCornerRadius.sm)
              .fill(WorkspaceColors.accentIndigo.opacity(0.08))
          )
        
        // Title
        Text(title)
          .font(WorkspaceTypography.headlineMedium)
          .foregroundColor(WorkspaceColors.textPrimary)
          .fontWeight(.semibold)
        
        Spacer()
        
        // Action
        if let actionTitle = actionTitle, let action = action {
          Button(action: action) {
            Text(actionTitle)
              .font(WorkspaceTypography.label)
              .foregroundColor(WorkspaceColors.accentIndigo)
              .padding(.horizontal, WorkspaceSpacing.md)
              .padding(.vertical, WorkspaceSpacing.xs)
              .background(
                Capsule()
                  .stroke(WorkspaceColors.accentIndigo.opacity(0.3), lineWidth: 1)
              )
          }
        }
      }
      
      // Optional divider
      if showDivider {
        Rectangle()
          .fill(WorkspaceColors.divider)
          .frame(height: 1)
          .padding(.top, WorkspaceSpacing.xs)
      }
    }
    .padding(.horizontal, WorkspaceSpacing.lg)
    .padding(.top, WorkspaceSpacing.xl)
    .padding(.bottom, WorkspaceSpacing.sm)
  }
}

// MARK: - SegmentedSwitch
/// 分段切换器：无闪烁平滑过渡
public struct SegmentedSwitch<T: Hashable>: View {
  @Binding var selection: T
  let options: [(id: T, label: String, icon: String?)]
  let showIcons: Bool
  let compact: Bool
  
  @State private var previousSelection: T
  
  public init(
    selection: Binding<T>,
    options: [(id: T, label: String, icon: String?)],
    showIcons: Bool = true,
    compact: Bool = false
  ) where T: Hashable {
    self._selection = selection
    self.options = options
    self.showIcons = showIcons
    self.compact = compact
    self._previousSelection = State(initialValue: selection.wrappedValue)
  }
  
  public var body: some View {
    HStack(spacing: WorkspaceSpacing.xs) {
      ForEach(options, id: \.id) { option in
        SegmentButton(
          label: option.label,
          icon: option.icon,
          isSelected: selection == option.id,
          showIcons: showIcons,
          compact: compact,
          action: {
            withAnimation(WorkspaceAnimations.springLight) {
              previousSelection = selection
              selection = option.id
            }
          }
        )
      }
    }
    .padding(WorkspaceSpacing.xs)
    .background(
      RoundedRectangle(cornerRadius: WorkspaceCornerRadius.md)
        .fill(WorkspaceColors.backgroundSecondary)
    )
  }
  
  private struct SegmentButton: View {
    let label: String
    let icon: String?
    let isSelected: Bool
    let showIcons: Bool
    let compact: Bool
    let action: () -> Void
    
    var body: some View {
      Button(action: action) {
        HStack(spacing: showIcons ? WorkspaceSpacing.sm : 0) {
          if showIcons, let iconName = icon {
            Image(systemName: iconName)
              .font(.system(size: compact ? 14 : 16, weight: .medium))
          }
          
          Text(label)
            .font(compact ? WorkspaceTypography.label : WorkspaceTypography.button)
        }
        .foregroundColor(isSelected ? WorkspaceColors.textPrimary : WorkspaceColors.textSecondary)
        .padding(.horizontal, compact ? WorkspaceSpacing.md : WorkspaceSpacing.lg)
        .padding(.vertical, compact ? WorkspaceSpacing.sm : WorkspaceSpacing.md)
        .background(
          Group {
            if isSelected {
              RoundedRectangle(cornerRadius: WorkspaceCornerRadius.sm)
                .fill(WorkspaceColors.cardBackground)
                .shadow(color: WorkspaceColors.shadowLight, radius: 6, x: 0, y: 2)
            }
          }
        )
        .animation(nil, value: isSelected) // 避免闪烁
      }
      .buttonStyle(.plain)
    }
  }
}

// MARK: - ContextCard
/// 上下文信息卡片
public struct ContextCard: View {
  let icon: String
  let iconColor: Color
  let title: String
  let subtitle: String?
  let metadata: [(label: String, value: String)]?
  let onTap: (() -> Void)?
  let isPressed: Bool
  
  @State private var scale: CGFloat = 1.0
  
  public init(
    icon: String,
    iconColor: Color = WorkspaceColors.accentIndigo,
    title: String,
    subtitle: String? = nil,
    metadata: [(label: String, value: String)]? = nil,
    onTap: (() -> Void)? = nil,
    isPressed: Bool = false
  ) {
    self.icon = icon
    self.iconColor = iconColor
    self.title = title
    self.subtitle = subtitle
    self.metadata = metadata
    self.onTap = onTap
    self._isPressed = State(initialValue: isPressed)
  }
  
  public var body: some View {
    Button(action: {
      if onTap != nil {
        withAnimation(WorkspaceAnimations.springStandard) {
          scale = 0.98
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          withAnimation(WorkspaceAnimations.springStandard) {
            scale = 1.0
          }
        }
        onTap?()
      }
    }) {
      VStack(alignment: .leading, spacing: WorkspaceSpacing.md) {
        // Header: icon + title
        HStack(spacing: WorkspaceSpacing.md) {
          Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(iconColor)
            .frame(width: 36, height: 36)
            .background(
              RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
                .fill(iconColor.opacity(0.1))
            )
          
          Text(title)
            .font(WorkspaceTypography.headlineSmall)
            .foregroundColor(WorkspaceColors.textPrimary)
            .fontWeight(.semibold)
          
          Spacer()
        }
        
        // Subtitle
        if let subtitle = subtitle {
          Text(subtitle)
            .font(WorkspaceTypography.body)
            .foregroundColor(WorkspaceColors.textSecondary)
            .lineLimit(2)
        }
        
        // Metadata
        if let metadata = metadata {
          VStack(alignment: .leading, spacing: WorkspaceSpacing.xs) {
            ForEach(metadata, id: \.label) { item in
              HStack(spacing: WorkspaceSpacing.xs) {
                Text(item.label)
                  .font(WorkspaceTypography.caption)
                  .foregroundColor(WorkspaceColors.textTertiary)
                Text(":")
                  .font(WorkspaceTypography.caption)
                  .foregroundColor(WorkspaceColors.textPlaceholder)
                Text(item.value)
                  .font(WorkspaceTypography.caption)
                  .foregroundColor(WorkspaceColors.textSecondary)
                  .fontWeight(.medium)
              }
            }
          }
          .padding(.top, WorkspaceSpacing.xs)
        }
      }
      .padding(WorkspaceSpacing.lg)
      .background(
        RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
          .fill(WorkspaceColors.cardBackground)
      )
      .overlay(
        RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
          .stroke(
            isPressed ? WorkspaceColors.borderMedium : WorkspaceColors.borderLight,
            lineWidth: isPressed ? 2 : 1
          )
      )
      .scaleEffect(scale)
      .shadow(color: WorkspaceColors.shadowLight, radius: 10, x: 0, y: 3)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - QuoteBlockCard
/// 引用块卡片：来源引用显示
public struct QuoteBlockCard: View {
  let quote: String
  let sourceTitle: String
  let sourcePosition: String?
  let knowledgePointCount: Int
  onTap: (() -> Void)?
  
  public init(
    quote: String,
    sourceTitle: String,
    sourcePosition: String? = nil,
    knowledgePointCount: Int = 0,
    onTap: (() -> Void)? = nil
  ) {
    self.quote = quote
    self.sourceTitle = sourceTitle
    self.sourcePosition = sourcePosition
    self.knowledgePointCount = knowledgePointCount
    self.onTap = onTap
  }
  
  public var body: some View {
    Button(action: { onTap?() }) {
      VStack(alignment: .leading, spacing: WorkspaceSpacing.md) {
        // Quote content
        Text(quote)
          .font(WorkspaceTypography.bodyLarge)
          .foregroundColor(WorkspaceColors.textPrimary)
          .lineSpacing(6)
          .padding(.bottom, WorkspaceSpacing.sm)
        
        // Divider
        Rectangle()
          .fill(WorkspaceColors.quoteBorder)
          .frame(height: 2)
          .frame(maxWidth: 60)
        
        // Source info
        HStack(spacing: WorkspaceSpacing.md) {
          // Source title
          HStack(spacing: WorkspaceSpacing.xs) {
            Image(systemName: "doc.text")
              .font(.system(size: 14, weight: .medium))
            Text(sourceTitle)
              .font(WorkspaceTypography.label)
          }
          .foregroundColor(WorkspaceColors.textSecondary)
          
          // Position
          if let position = sourcePosition {
            Text("·")
              .font(WorkspaceTypography.label)
              .foregroundColor(WorkspaceColors.textPlaceholder)
            
            Text(position)
              .font(WorkspaceTypography.label)
              .foregroundColor(WorkspaceColors.textTertiary)
          }
          
          Spacer()
          
          // Knowledge point count
          if knowledgePointCount > 0 {
            HStack(spacing: WorkspaceSpacing.xs) {
              Image(systemName: "lightbulb")
                .font(.system(size: 12, weight: .medium))
              Text("\(knowledgePointCount)")
                .font(WorkspaceTypography.labelSmall)
            }
            .foregroundColor(WorkspaceColors.accentTeal)
            .padding(.horizontal, WorkspaceSpacing.sm)
            .padding(.vertical, WorkspaceSpacing.xs)
            .background(
              Capsule()
                .fill(WorkspaceColors.knowledgePointBackground)
            )
          }
        }
        .font(WorkspaceTypography.caption)
      }
      .padding(WorkspaceSpacing.lg)
      .padding(.leading, WorkspaceSpacing.lg)
      .background(
        RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
          .fill(WorkspaceColors.quoteBackground)
          .overlay(
            RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
              .stroke(WorkspaceColors.quoteBorder.opacity(0.3), lineWidth: 1)
          )
      )
      .overlay(
        Rectangle()
          .fill(WorkspaceColors.quoteBorder)
          .frame(width: 4)
          .cornerRadius(2),
        alignment: .leading
      )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - TextBlockEditorCard
/// 文本块编辑卡片
public struct TextBlockEditorCard: View {
  @Binding var text: String
  let placeholder: String
  let isFocused: Bool
  let onFocus: () -> Void
  let onBlur: () -> Void
  let onDelete: () -> Void
  
  public init(
    text: Binding<String>,
    placeholder: String = "添加你的想法...",
    isFocused: Bool = false,
    onFocus: @escaping () -> Void = {},
    onBlur: @escaping () -> Void = {},
    onDelete: @escaping () -> Void = {}
  ) {
    self._text = text
    self.placeholder = placeholder
    self.isFocused = isFocused
    self.onFocus = onFocus
    self.onBlur = onBlur
    self.onDelete = onDelete
  }
  
  public var body: some View {
    VStack(alignment: .leading, spacing: WorkspaceSpacing.sm) {
      // Toolbar
      HStack {
        Image(systemName: "text.alignleft")
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(WorkspaceColors.textTertiary)
        
        Spacer()
        
        // Delete button
        Button(action: onDelete) {
          Image(systemName: "trash")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(WorkspaceColors.textPlaceholder)
        }
        .opacity(text.isEmpty ? 0 : 1)
      }
      
      // Text editor
      TextEditor(text: $text)
        .font(WorkspaceTypography.bodyLarge)
        .foregroundColor(WorkspaceColors.textPrimary)
        .accentColor(WorkspaceColors.accentIndigo)
        .frame(minHeight: 60)
        .onChange(of: text) { _ in
          if !text.isEmpty && !isFocused {
            onFocus()
          } else if text.isEmpty && isFocused {
            onBlur()
          }
        }
    }
    .padding(WorkspaceSpacing.lg)
    .background(
      RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
        .fill(WorkspaceColors.cardBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
        .stroke(
          isFocused ? WorkspaceColors.accentIndigo.opacity(0.4) : WorkspaceColors.borderLight,
          lineWidth: isFocused ? 2 : 1
        )
    )
    .shadow(color: WorkspaceColors.shadowLight, radius: 8, x: 0, y: 2)
  }
}

// MARK: - InkBlockCard
/// 手写墨水块卡片
public struct InkBlockCard: View {
  let canvasColor: Color
  let onTap: () -> Void
  let onEdit: () -> Void
  let onDelete: () -> Void
  
  public init(
    canvasColor: Color = WorkspaceColors.inkBackground,
    onTap: @escaping () -> Void = {},
    onEdit: @escaping () -> Void = {},
    onDelete: @escaping () -> Void = {}
  ) {
    self.canvasColor = canvasColor
    self.onTap = onTap
    self.onEdit = onEdit
    self.onDelete = onDelete
  }
  
  public var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: WorkspaceSpacing.sm) {
        // Canvas placeholder
        RoundedRectangle(cornerRadius: WorkspaceCornerRadius.md)
          .fill(canvasColor)
          .frame(height: 180)
          .overlay(
            VStack(spacing: WorkspaceSpacing.sm) {
              Image(systemName: "pencil.tip.crop.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(WorkspaceColors.textPlaceholder)
              
              Text("点击编辑手写内容")
                .font(WorkspaceTypography.body)
                .foregroundColor(WorkspaceColors.textTertiary)
            }
          )
        
        // Actions
        HStack(spacing: WorkspaceSpacing.md) {
          Button(action: onEdit) {
            Label("编辑", systemImage: "pencil")
              .font(WorkspaceTypography.label)
              .foregroundColor(WorkspaceColors.accentIndigo)
          }
          
          Button(action: onDelete) {
            Label("删除", systemImage: "trash")
              .font(WorkspaceTypography.label)
              .foregroundColor(WorkspaceColors.textPlaceholder)
          }
          
          Spacer()
        }
      }
      .padding(WorkspaceSpacing.lg)
      .background(
        RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
          .fill(WorkspaceColors.cardBackground)
      )
      .shadow(color: WorkspaceColors.shadowLight, radius: 10, x: 0, y: 3)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - KnowledgeChip
/// 知识点芯片：可点击的知识标签
public struct KnowledgeChip: View {
  let title: String
  let subject: String?
  let isLinked: Bool
  let onTap: () -> Void
  let onLink: () -> Void
  
  @State private var isPressed: Bool = false
  @State private var showLinkFeedback: Bool = false
  
  public init(
    title: String,
    subject: String? = nil,
    isLinked: Bool = false,
    onTap: @escaping () -> Void = {},
    onLink: @escaping () -> Void = {}
  ) {
    self.title = title
    self.subject = subject
    self.isLinked = isLinked
    self.onTap = onTap
    self.onLink = onLink
  }
  
  public var body: some View {
    HStack(spacing: WorkspaceSpacing.sm) {
      // Main chip
      Button(action: {
        withAnimation(WorkspaceAnimations.springLight) {
          isPressed = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          withAnimation(WorkspaceAnimations.springLight) {
            isPressed = false
          }
        }
        onTap()
      }) {
        HStack(spacing: WorkspaceSpacing.xs) {
          Image(systemName: "lightbulb")
            .font(.system(size: 12, weight: .medium))
          
          Text(title)
            .font(WorkspaceTypography.label)
            .fontWeight(.medium)
          
          if let subject = subject {
            Text("·")
              .font(WorkspaceTypography.labelSmall)
            Text(subject)
              .font(WorkspaceTypography.labelSmall)
          }
        }
        .foregroundColor(WorkspaceColors.accentTeal)
        .padding(.horizontal, WorkspaceSpacing.md)
        .padding(.vertical, WorkspaceSpacing.sm)
        .background(
          Capsule()
            .fill(WorkspaceColors.knowledgePointBackground)
            .overlay(
              Capsule()
                .stroke(WorkspaceColors.knowledgePointBorder, lineWidth: 1)
            )
        )
        .scaleEffect(isPressed ? 0.96 : 1.0)
      }
      .buttonStyle(.plain)
      
      // Link button (if not linked)
      if !isLinked {
        Button(action: {
          withAnimation(WorkspaceAnimations.springLight) {
            showLinkFeedback = true
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(WorkspaceAnimations.springLight) {
              showLinkFeedback = false
            }
          }
          onLink()
        }) {
          Image(systemName: "link")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(WorkspaceColors.accentIndigo)
            .frame(width: 28, height: 28)
            .background(
              Circle()
                .fill(showLinkFeedback ? WorkspaceColors.accentIndigo.opacity(0.2) : Color.clear)
            )
        }
        .buttonStyle(.plain)
      }
    }
  }
}

// MARK: - RelatedContextPanel
/// 关联上下文面板：相关笔记/知识点
public struct RelatedContextPanel: View {
  let title: String
  let items: [(icon: String, title: String, subtitle: String)]
  let onSelect: (Int) -> Void
  
  public init(
    title: String,
    items: [(icon: String, title: String, subtitle: String)],
    onSelect: @escaping (Int) -> Void = { _ in }
  ) {
    self.title = title
    self.items = items
    self.onSelect = onSelect
  }
  
  public var body: some View {
    VStack(alignment: .leading, spacing: WorkspaceSpacing.md) {
      // Header
      HStack {
        Text(title)
          .font(WorkspaceTypography.headlineSmall)
          .foregroundColor(WorkspaceColors.textPrimary)
          .fontWeight(.semibold)
        
        Spacer()
        
        Text("\(items.count) 项")
          .font(WorkspaceTypography.caption)
          .foregroundColor(WorkspaceColors.textTertiary)
      }
      
      // Items list
      VStack(spacing: WorkspaceSpacing.sm) {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
          Button(action: { onSelect(index) }) {
            HStack(spacing: WorkspaceSpacing.md) {
              Image(systemName: item.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(WorkspaceColors.accentIndigo)
                .frame(width: 32, height: 32)
                .background(
                  RoundedRectangle(cornerRadius: WorkspaceCornerRadius.sm)
                    .fill(WorkspaceColors.accentIndigo.opacity(0.08))
                )
              
              VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                  .font(WorkspaceTypography.body)
                  .foregroundColor(WorkspaceColors.textPrimary)
                  .fontWeight(.medium)
                  .lineLimit(1)
                
                Text(item.subtitle)
                  .font(WorkspaceTypography.caption)
                  .foregroundColor(WorkspaceColors.textTertiary)
                  .lineLimit(1)
              }
              
              Spacer()
              
              Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(WorkspaceColors.textPlaceholder)
            }
            .padding(.horizontal, WorkspaceSpacing.md)
            .padding(.vertical, WorkspaceSpacing.sm)
            .background(
              RoundedRectangle(cornerRadius: WorkspaceCornerRadius.md)
                .fill(WorkspaceColors.backgroundSecondary.opacity(0.5))
            )
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(WorkspaceSpacing.lg)
    .background(
      RoundedRectangle(cornerRadius: WorkspaceCornerRadius.xl)
        .fill(WorkspaceColors.cardBackground)
    )
    .shadow(color: WorkspaceColors.shadowLight, radius: 12, x: 0, y: 4)
  }
}

// MARK: - FloatingNavigatorPanel
/// 浮动导航面板：结构树/大纲导航
public struct FloatingNavigatorPanel: View {
  let title: String
  let sections: [(icon: String, title: String, count: Int)]
  let selectedIndex: Int?
  let onSelect: (Int) -> Void
  let onClose: () -> Void
  let isExpanded: Bool
  
  @State private var hoveredIndex: Int? = nil
  
  public init(
    title: String,
    sections: [(icon: String, title: String, count: Int)],
    selectedIndex: Int? = nil,
    onSelect: @escaping (Int) -> Void = { _ in },
    onClose: @escaping () -> Void = {},
    isExpanded: Bool = true
  ) {
    self.title = title
    self.sections = sections
    self.selectedIndex = selectedIndex
    self.onSelect = onSelect
    self.onClose = onClose
    self.isExpanded = isExpanded
  }
  
  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack {
        Text(title)
          .font(WorkspaceTypography.headlineSmall)
          .foregroundColor(WorkspaceColors.textPrimary)
          .fontWeight(.semibold)
        
        Spacer()
        
        Button(action: onClose) {
          Image(systemName: "chevron.right")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(WorkspaceColors.textSecondary)
        }
      }
      .padding(WorkspaceSpacing.lg)
      .background(
        RoundedRectangle(cornerRadius: isExpanded ? WorkspaceCornerRadius.xl : 0)
          .fill(WorkspaceColors.glassSurface)
      )
      
      // Sections list (when expanded)
      if isExpanded {
        VStack(spacing: WorkspaceSpacing.xs) {
          ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
            Button(action: { onSelect(index) }) {
              HStack(spacing: WorkspaceSpacing.md) {
                Image(systemName: section.icon)
                  .font(.system(size: 14, weight: .medium))
                  .foregroundColor(
                    selectedIndex == index
                      ? WorkspaceColors.accentIndigo
                      : WorkspaceColors.textTertiary
                  )
                  .frame(width: 28, height: 28)
                
                Text(section.title)
                  .font(WorkspaceTypography.body)
                  .foregroundColor(
                    selectedIndex == index
                      ? WorkspaceColors.textPrimary
                      : WorkspaceColors.textSecondary
                  )
                  .fontWeight(selectedIndex == index ? .semibold : .regular)
                
                Spacer()
                
                Text("\(section.count)")
                  .font(WorkspaceTypography.caption)
                  .foregroundColor(WorkspaceColors.textPlaceholder)
                  .padding(.horizontal, WorkspaceSpacing.sm)
                  .padding(.vertical, WorkspaceSpacing.xs)
                  .background(
                    Capsule()
                      .fill(WorkspaceColors.backgroundSecondary)
                  )
              }
              .padding(.horizontal, WorkspaceSpacing.lg)
              .padding(.vertical, WorkspaceSpacing.sm)
              .background(
                RoundedRectangle(cornerRadius: WorkspaceCornerRadius.md)
                  .fill(
                    selectedIndex == index
                      ? WorkspaceColors.accentIndigo.opacity(0.06)
                      : Color.clear
                  )
              )
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
              hoveredIndex = hovering ? index : nil
            }
          }
        }
        .padding(.vertical, WorkspaceSpacing.sm)
      }
    }
    .background(
      RoundedRectangle(cornerRadius: isExpanded ? WorkspaceCornerRadius.xl : 0)
        .fill(WorkspaceColors.glassSurface)
    )
    .overlay(
      RoundedRectangle(cornerRadius: isExpanded ? WorkspaceCornerRadius.xl : 0)
        .stroke(WorkspaceColors.borderLight, lineWidth: 1)
    )
    .shadow(color: WorkspaceColors.shadowMedium, radius: 16, x: 0, y: 6)
    .frame(width: isExpanded ? WorkspaceLayout.floatingPanelMaxWidthiPad : 56)
  }
}

// MARK: - Preview

#Preview {
  ScrollView {
    VStack(spacing: WorkspaceSpacing.xxl) {
      AppPageHeader(
        title: "首页",
        subtitle: "今日学习概览",
        trailingActions: [({ print("Settings") }, "设置", Image(systemName: "gear"))]
      )
      
      SectionHeader(
        icon: "chart.bar",
        title: "学习进度",
        actionTitle: "查看全部",
        action: { print("View all") }
      )
      
      SegmentedSwitch(
        selection: .constant(0),
        options: [
          (0, "全部", "square.grid.2x2"),
          (1, "进行中", "clock"),
          (2, "已完成", "checkmark.circle")
        ],
        showIcons: true,
        compact: false
      )
      
      ContextCard(
        icon: "book.open",
        title: "正在阅读",
        subtitle: "《深度学习》第 3 章",
        metadata: [("进度", "67%"), ("剩余", "45 分钟")]
      )
      
      QuoteBlockCard(
        quote: "神经网络是由大量的简单处理单元组成的并行分布式处理器。",
        sourceTitle: "深度学习",
        sourcePosition: "P.87",
        knowledgePointCount: 3
      )
      
      TextBlockEditorCard(
        text: .constant("这是我的想法和总结..."),
        isFocused: true
      )
      
      KnowledgeChip(
        title: "反向传播算法",
        subject: "机器学习",
        isLinked: true
      )
      
      RelatedContextPanel(
        title: "相关笔记",
        items: [
          ("note.text", "神经网络基础", "创建于 2 小时前"),
          ("lightbulb", "激活函数详解", "创建于昨天"),
          ("chart.line", "损失函数分析", "创建于 3 天前")
        ]
      )
      
      FloatingNavigatorPanel(
        title: "文档结构",
        sections: [
          ("doc.text", "引言", 3),
          ("brain", "核心概念", 8),
          ("gear", "实践应用", 5),
          ("flag.checkered", "总结", 2)
        ],
        selectedIndex: 1
      )
    }
    .padding(.horizontal, WorkspaceSpacing.lg)
    .padding(.vertical, WorkspaceSpacing.xxl)
  }
  .background(WorkspaceColors.backgroundPrimary)
}
