import SwiftUI

// MARK: - Modern Notes Split View
// iPad: Dual-pane layout | iPhone: Single-pane navigation

struct ModernNotesSplitView: View {
  @EnvironmentObject var viewModel: AppViewModel
  @Environment(\.horizontalSizeClass) var horizontalSizeClass
  
  @State private var selectedNote: Note?
  @State private var showingNoteWorkspace = false
  @State private var searchText = ""
  @State private var selectedFilter: NoteFilter = .all
  
  private var isiPad: Bool {
    horizontalSizeClass == .regular
  }
  
  enum NoteFilter: String, CaseIterable {
    case all = "全部"
    case today = "今天"
    case week = "本周"
    case month = "本月"
  }
  
  var body: some View {
    Group {
      if isiPad {
        // iPad: Dual-pane layout
        iPadDualPaneView
      } else {
        // iPhone: Navigation layout
        iPhoneNavigationView
      }
    }
    .background(ModernColors.background)
  }
  
  // MARK: - iPad Dual Pane View
  
  private var iPadDualPaneView: some View {
    HStack(spacing: 0) {
      // Left pane: Notes list
      NotesListPane(
        selectedNote: $selectedNote,
        searchText: $searchText,
        selectedFilter: $selectedFilter,
        onCreateNote: {
          showingNoteWorkspace = true
        }
      )
      .frame(width: ModernLayout.sidebarWidth)
      .overlay(
        Rectangle()
          .fill(ModernColors.outlineVariant)
          .frame(width: 1),
        alignment: .trailing
      )
      
      // Right pane: Note detail or empty state
      if let note = selectedNote {
        NoteDetailPane(note: note)
          .frame(minWidth: ModernLayout.detailMinWidth)
      } else {
        EmptyState(
          icon: "note.text",
          title: "选择笔记",
          subtitle: "从列表中选择一个笔记查看详情",
          actionTitle: nil,
          action: nil
        )
      }
    }
    .sheet(isPresented: $showingNoteWorkspace) {
      NoteWorkspaceView()
        .environmentObject(viewModel)
    }
  }
  
  // MARK: - iPhone Navigation View
  
  private var iPhoneNavigationView: some View {
    NavigationView {
      NotesListPane(
        selectedNote: $selectedNote,
        searchText: $searchText,
        selectedFilter: $selectedFilter,
        onCreateNote: {
          showingNoteWorkspace = true
        }
      )
      .navigationTitle("我的笔记")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(action: { showingNoteWorkspace = true }) {
            Image(systemName: "plus")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(ModernColors.primary)
          }
        }
      }
      .sheet(isPresented: $showingNoteWorkspace) {
        NoteWorkspaceView()
          .environmentObject(viewModel)
      }
    }
  }
}

// MARK: - Notes List Pane

struct NotesListPane: View {
  @Binding var selectedNote: Note?
  @Binding var searchText: String
  @Binding var selectedFilter: ModernNotesSplitView.NoteFilter
  let onCreateNote: () -> Void
  
  @EnvironmentObject var viewModel: AppViewModel
  @State private var notes: [Note] = []
  
  var body: some View {
    VStack(spacing: 0) {
      // Header with search and filter
      headerSection
      
      // Notes list
      if filteredNotes.isEmpty {
        EmptyState(
          icon: "note.text",
          title: "暂无笔记",
          subtitle: "创建你的第一条笔记",
          actionTitle: "新建笔记",
          action: onCreateNote
        )
        .padding()
      } else {
        ScrollView(showsIndicators: false) {
          VStack(spacing: ModernSpacing.sm) {
            ForEach(filteredNotes, id: \.id) { note in
              NoteListItem(
                note: note,
                isSelected: selectedNote?.id == note.id
              ) {
                selectedNote = note
              }
            }
          }
          .padding(.horizontal, ModernSpacing.lg)
          .padding(.vertical, ModernSpacing.md)
        }
      }
    }
    .background(ModernColors.surface)
  }
  
  // MARK: - Header Section
  
  private var headerSection: some View {
    VStack(spacing: ModernSpacing.lg) {
      // Search bar
      HStack(spacing: ModernSpacing.sm) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(ModernColors.textTertiary)
        
        TextField("搜索笔记...", text: $searchText)
          .font(ModernTypography.body)
          .textFieldStyle(.plain)
        
        if !searchText.isEmpty {
          Button(action: { searchText = "" }) {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(ModernColors.textTertiary)
          }
        }
      }
      .padding(ModernSpacing.md)
      .background(ModernColors.surface)
      .cornerRadius(ModernCornerRadius.md)
      .overlay(
        RoundedRectangle(cornerRadius: ModernCornerRadius.md)
          .stroke(ModernColors.outline, lineWidth: 1)
      )
      
      // Filter chips
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: ModernSpacing.sm) {
          ForEach(ModernNotesSplitView.NoteFilter.allCases, id: \.rawValue) { filter in
            Chip(
              label: filter.rawValue,
              isSelected: selectedFilter == filter,
              color: ModernColors.primary
            ) {
              selectedFilter = filter
            }
          }
        }
        .padding(.horizontal, ModernSpacing.xs)
      }
    }
    .padding(ModernSpacing.lg)
    .padding(.top, ModernSpacing.lg)
  }
  
  // MARK: - Filtered Notes
  
  private var filteredNotes: [Note] {
    var notes = mockNotes // Replace with viewModel.notes
    
    // Apply search filter
    if !searchText.isEmpty {
      notes = notes.filter { note in
        (note.title ?? "").localizedCaseInsensitiveContains(searchText)
      }
    }
    
    // Apply time filter
    switch selectedFilter {
    case .today:
      notes = notes.filter { Calendar.current.isDateInToday($0.createdAt) }
    case .week:
      notes = notes.filter { Calendar.current.isDate($0.createdAt, inSameWeekAs: Date()) }
    case .month:
      notes = notes.filter { Calendar.current.isDate($0.createdAt, equalTo: Date(), toGranularity: .month) }
    case .all:
      break
    }
    
    return notes
  }
  
  // MARK: - Mock Data
  
  private var mockNotes: [Note] {
    [] // Replace with viewModel.notes
  }
}

// MARK: - Note List Item

struct NoteListItem: View {
  let note: Note
  let isSelected: Bool
  let onTap: () -> Void
  
  var body: some View {
    Button(action: onTap) {
      HStack(spacing: ModernSpacing.md) {
        // Icon
        Image(systemName: "note.text")
          .font(.system(size: 18, weight: .medium))
          .foregroundColor(isSelected ? ModernColors.textInverse : ModernColors.primary)
          .frame(width: 44, height: 44)
          .background(
            RoundedRectangle(cornerRadius: ModernCornerRadius.lg)
              .fill(isSelected ? ModernColors.primary : ModernColors.primary.opacity(0.1))
          )
        
        // Content
        VStack(alignment: .leading, spacing: 4) {
          Text(note.title ?? "未命名笔记")
            .font(ModernTypography.titleMedium)
            .foregroundColor(isSelected ? ModernColors.textInverse : ModernColors.textPrimary)
            .fontWeight(.medium)
            .lineLimit(1)
          
          HStack(spacing: ModernSpacing.sm) {
            Text(formatDate(note.createdAt))
              .font(ModernTypography.caption)
              .foregroundColor(isSelected ? ModernColors.textInverse.opacity(0.8) : ModernColors.textTertiary)
            
            Text("·")
              .font(ModernTypography.caption)
              .foregroundColor(isSelected ? ModernColors.textInverse.opacity(0.6) : ModernColors.textPlaceholder)
            
            Text("\(note.blocks.count) 块")
              .font(ModernTypography.caption)
              .foregroundColor(isSelected ? ModernColors.textInverse.opacity(0.8) : ModernColors.textTertiary)
          }
        }
        
        Spacer()
        
        // Chevron
        Image(systemName: "chevron.right")
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(isSelected ? ModernColors.textInverse.opacity(0.6) : ModernColors.textTertiary)
      }
      .padding(ModernSpacing.md)
      .background(
        RoundedRectangle(cornerRadius: ModernCornerRadius.lg)
          .fill(isSelected ? ModernColors.primary : ModernColors.surfaceVariant)
      )
      .overlay(
        RoundedRectangle(cornerRadius: ModernCornerRadius.lg)
          .stroke(isSelected ? ModernColors.primary : ModernColors.outline, lineWidth: isSelected ? 0 : 1)
      )
    }
    .buttonStyle(.plain)
  }
  
  private func formatDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}

// MARK: - Note Detail Pane

struct NoteDetailPane: View {
  let note: Note
  
  @State private var isEditing = false
  @State private var showingShareSheet = false
  
  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: ModernSpacing.xxl) {
        // Header
        headerSection
        
        // Quote blocks
        if !note.quoteBlocks.isEmpty {
          quoteBlocksSection
        }
        
        // Text blocks
        if !note.textBlocks.isEmpty {
          textBlocksSection
        }
        
        // Ink blocks
        if !note.inkBlocks.isEmpty {
          inkBlocksSection
        }
        
        // Knowledge points
        if !note.knowledgePoints.isEmpty {
          knowledgePointsSection
        }
        
        // Related notes
        relatedNotesSection
      }
      .padding(ModernSpacing.xxl)
    }
    .background(ModernColors.background)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        HStack(spacing: ModernSpacing.sm) {
          IconButton(
            icon: "square.and.arrow.up",
            color: ModernColors.primary,
            backgroundColor: ModernColors.surface,
            action: { showingShareSheet = true }
          )
          
          IconButton(
            icon: "pencil",
            color: ModernColors.primary,
            backgroundColor: ModernColors.surface,
            action: { isEditing = true }
          )
        }
      }
    }
    .sheet(isPresented: $isEditing) {
      NoteWorkspaceView()
        .environmentObject(AppViewModel())
    }
  }
  
  // MARK: - Header Section
  
  private var headerSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.md) {
      Text(note.title ?? "未命名笔记")
        .font(ModernTypography.displaySmall)
        .foregroundColor(ModernColors.textPrimary)
        .fontWeight(.bold)
      
      HStack(spacing: ModernSpacing.md) {
        Text(formatDate(note.createdAt))
          .font(ModernTypography.caption)
          .foregroundColor(ModernColors.textTertiary)
        
        Text("·")
          .font(ModernTypography.caption)
          .foregroundColor(ModernColors.textPlaceholder)
        
        Text("\(note.blocks.count) 个内容块")
          .font(ModernTypography.caption)
          .foregroundColor(ModernColors.textTertiary)
      }
      
      if let source = note.sourceAnchor {
        HStack(spacing: ModernSpacing.xs) {
          Image(systemName: "doc.text")
            .font(.system(size: 12, weight: .medium))
          Text(source.sourceTitle)
            .font(ModernTypography.caption)
            .foregroundColor(ModernColors.primary)
        }
        .padding(.horizontal, ModernSpacing.md)
        .padding(.vertical, ModernSpacing.xs)
        .background(
          Capsule()
            .fill(ModernColors.primary.opacity(0.1))
        )
      }
    }
  }
  
  // MARK: - Quote Blocks Section
  
  private var quoteBlocksSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "text.quote",
        title: "引用",
        showDivider: true
      )
      
      ForEach(note.quoteBlocks, id: \.id) { block in
        QuoteBlockView(block: block)
      }
    }
  }
  
  // MARK: - Text Blocks Section
  
  private var textBlocksSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "paragraph",
        title: "笔记",
        showDivider: true
      )
      
      ForEach(note.textBlocks, id: \.id) { block in
        TextBlockView(block: block)
      }
    }
  }
  
  // MARK: - Ink Blocks Section
  
  private var inkBlocksSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "pencil.tip",
        title: "手写",
        showDivider: true
      )
      
      ForEach(note.inkBlocks, id: \.id) { block in
        InkBlockPreview(block: block)
      }
    }
  }
  
  // MARK: - Knowledge Points Section
  
  private var knowledgePointsSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "lightbulb",
        title: "知识点",
        showDivider: true
      )
      
      FlowLayout(spacing: ModernSpacing.sm) {
        ForEach(note.knowledgePoints, id: \.id) { point in
          Chip(
            label: point.title,
            icon: "lightbulb",
            color: ModernColors.accent
          ) {
            print("Knowledge point tapped: \(point.title)")
          }
        }
      }
    }
  }
  
  // MARK: - Related Notes Section
  
  private var relatedNotesSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "link",
        title: "相关笔记",
        showDivider: true
      )
      
      VStack(spacing: ModernSpacing.sm) {
        ForEach(mockRelatedNotes, id: \.id) { relatedNote in
          RelatedNoteRow(note: relatedNote)
        }
      }
    }
  }
  
  // MARK: - Helper Methods
  
  private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
  
  private var mockRelatedNotes: [Note] {
    [] // Replace with actual related notes
  }
}

// MARK: - Quote Block View

struct QuoteBlockView: View {
  let block: NoteBlock
  
  var body: some View {
    ModernCard(variant: .filled) {
      VStack(alignment: .leading, spacing: ModernSpacing.md) {
        Text(block.content ?? "")
          .font(ModernTypography.bodyLarge)
          .foregroundColor(ModernColors.textPrimary)
          .lineSpacing(6)
        
        if let sourcePosition = block.sourcePosition {
          HStack(spacing: ModernSpacing.xs) {
            Image(systemName: "bookmark")
              .font(.system(size: 12, weight: .medium))
            Text(sourcePosition)
              .font(ModernTypography.caption)
              .foregroundColor(ModernColors.primary)
          }
        }
      }
    }
    .overlay(
      Rectangle()
        .fill(ModernColors.primary)
        .frame(width: 4),
      alignment: .leading
    )
  }
}

// MARK: - Text Block View

struct TextBlockView: View {
  let block: NoteBlock
  
  var body: some View {
    ModernCard(variant: .outlined) {
      Text(block.content ?? "")
        .font(ModernTypography.body)
        .foregroundColor(ModernColors.textPrimary)
        .lineSpacing(5)
    }
  }
}

// MARK: - Ink Block Preview

struct InkBlockPreview: View {
  let block: NoteBlock
  
  var body: some View {
    ModernCard(variant: .outlined) {
      VStack(alignment: .leading, spacing: ModernSpacing.md) {
        // Ink canvas placeholder
        RoundedRectangle(cornerRadius: ModernCornerRadius.md)
          .fill(ModernColors.surfaceVariant)
          .frame(height: 180)
          .overlay(
            Image(systemName: "pencil.tip.crop.circle")
              .font(.system(size: 48, weight: .light))
              .foregroundColor(ModernColors.textTertiary)
          )
        
        Text("手写内容")
          .font(ModernTypography.caption)
          .foregroundColor(ModernColors.textTertiary)
      }
    }
  }
}

// MARK: - Related Note Row

struct RelatedNoteRow: View {
  let note: Note
  
  var body: some View {
    HStack(spacing: ModernSpacing.md) {
      Image(systemName: "note.text")
        .font(.system(size: 16, weight: .medium))
        .foregroundColor(ModernColors.primary)
        .frame(width: 36, height: 36)
        .background(
          RoundedRectangle(cornerRadius: ModernCornerRadius.md)
            .fill(ModernColors.primary.opacity(0.1))
        )
      
      Text(note.title ?? "未命名笔记")
        .font(ModernTypography.body)
        .foregroundColor(ModernColors.textPrimary)
        .fontWeight(.medium)
        .lineLimit(1)
      
      Spacer()
      
      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(ModernColors.textTertiary)
    }
    .padding(ModernSpacing.md)
    .background(ModernColors.surfaceVariant)
    .cornerRadius(ModernCornerRadius.md)
  }
}

// MARK: - Flow Layout (Simple Implementation)

struct FlowLayout: Layout {
  let spacing: CGFloat
  
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
    return result.size
  }
  
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
    
    for (index, subview) in subviews.enumerated() {
      let origin = CGPoint(
        x: bounds.minX + result.positions[index].x,
        y: bounds.minY + result.positions[index].y
      )
      subview.place(at: origin, proposal: .unspecified)
    }
  }
  
  struct FlowResult {
    var size: CGSize = .zero
    var positions: [CGPoint] = []
    
    init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
      var x: CGFloat = 0
      var y: CGFloat = 0
      var rowHeight: CGFloat = 0
      
      for subview in subviews {
        let size = subview.sizeThatFits(.unspecified)
        
        if x + size.width > maxWidth && x > 0 {
          x = 0
          y += rowHeight + spacing
          rowHeight = 0
        }
        
        positions.append(CGPoint(x: x, y: y))
        rowHeight = max(rowHeight, size.height)
        x += size.width + spacing
      }
      
      self.size = CGSize(width: maxWidth, height: y + rowHeight)
    }
  }
}

// MARK: - Preview

#Preview {
  ModernNotesSplitView()
    .environmentObject(AppViewModel())
}
