import SwiftUI

// MARK: - Modern Library View
// iPad: Grid layout with sidebar | iPhone: List layout with search

struct ModernLibraryView: View {
  @EnvironmentObject var viewModel: AppViewModel
  @Environment(\.horizontalSizeClass) var horizontalSizeClass
  
  @State private var searchText = ""
  @State private var selectedSubject: Subject?
  @State private var viewMode: ViewMode = .grid
  @State private var showingImportSheet = false
  
  private var isiPad: Bool {
    horizontalSizeClass == .regular
  }
  
  enum ViewMode {
    case grid
    case list
  }
  
  var body: some View {
    Group {
      if isiPad {
        iPadGridView
      } else {
        iPhoneListView
      }
    }
    .background(ModernColors.background)
    .sheet(isPresented: $showingImportSheet) {
      ImportMaterialView()
        .environmentObject(viewModel)
    }
  }
  
  // MARK: - iPad Grid View
  
  private var iPadGridView: some View {
    NavigationSplitView {
      // Sidebar with subjects
      VStack(spacing: 0) {
        sidebarHeader
        
        ScrollView(showsIndicators: false) {
          VStack(spacing: ModernSpacing.sm) {
            ForEach(mockSubjects, id: \.id) { subject in
              SubjectSidebarRow(
                subject: subject,
                isSelected: selectedSubject?.id == subject.id
              ) {
                selectedSubject = subject
              }
            }
          }
          .padding(.horizontal, ModernSpacing.md)
          .padding(.vertical, ModernSpacing.lg)
        }
      }
      .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 320)
    } detail: {
      // Main content with materials grid
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: ModernSpacing.xxl) {
          // Section header
          headerSection
          
          // Materials grid
          if filteredMaterials.isEmpty {
            EmptyState(
              icon: "book",
              title: "暂无资料",
              subtitle: "导入教材或资料开始学习",
              actionTitle: "导入资料",
              action: { showingImportSheet = true }
            )
            .padding(.top, 100)
          } else {
            LazyVGrid(columns: ModernLayout.gridColumns3, spacing: ModernSpacing.lg) {
              ForEach(filteredMaterials, id: \.id) { material in
                MaterialGridCard(material: material)
              }
            }
            .padding(.horizontal, ModernSpacing.xxl)
          }
        }
        .padding(.top, ModernSpacing.lg)
        .padding(.bottom, ModernSpacing.xxxl)
      }
    }
  }
  
  // MARK: - iPhone List View
  
  private var iPhoneListView: some View {
    NavigationView {
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: ModernSpacing.xxl) {
          // Search and filter
          searchSection
          
          // Subjects section
          subjectsSection
          
          // Materials section
          materialsSection
        }
        .padding(.horizontal, ModernSpacing.lg)
        .padding(.top, ModernSpacing.lg)
        .padding(.bottom, ModernSpacing.xxxl)
      }
      .background(ModernColors.background)
      .navigationTitle("学习资料")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          HStack(spacing: ModernSpacing.sm) {
            Button(action: { viewMode.toggle() }) {
              Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ModernColors.primary)
            }
            
            Button(action: { showingImportSheet = true }) {
              Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ModernColors.primary)
            }
          }
        }
      }
      .sheet(isPresented: $showingImportSheet) {
        ImportMaterialView()
          .environmentObject(viewModel)
      }
    }
  }
  
  // MARK: - Sidebar Header
  
  private var sidebarHeader: some View {
    HStack {
      Text("学科")
        .font(ModernTypography.titleMedium)
        .foregroundColor(ModernColors.textPrimary)
        .fontWeight(.bold)
      
      Spacer()
      
      Button(action: { }) {
        Image(systemName: "plus")
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(ModernColors.primary)
      }
    }
    .padding(.horizontal, ModernSpacing.lg)
    .padding(.vertical, ModernSpacing.md)
  }
  
  // MARK: - Search Section
  
  private var searchSection: some View {
    VStack(spacing: ModernSpacing.lg) {
      // Search bar
      HStack(spacing: ModernSpacing.sm) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(ModernColors.textTertiary)
        
        TextField("搜索资料...", text: $searchText)
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
    }
  }
  
  // MARK: - Subjects Section
  
  private var subjectsSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "rectangle.3.group",
        title: "学科分类",
        showDivider: true
      )
      
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: ModernSpacing.sm) {
          ForEach(mockSubjects, id: \.id) { subject in
            SubjectChip(
              subject: subject,
              isSelected: selectedSubject?.id == subject.id
            ) {
              selectedSubject = subject
            }
          }
        }
      }
    }
  }
  
  // MARK: - Materials Section
  
  private var materialsSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "book",
        title: "学习资料",
        actionTitle: "查看全部",
        showDivider: true
      ) {
        print("View all materials")
      }
      
      if viewMode == .grid {
        // Grid view
        LazyVGrid(columns: ModernLayout.gridColumns2, spacing: ModernSpacing.lg) {
          ForEach(filteredMaterials, id: \.id) { material in
            MaterialGridCard(material: material)
          }
        }
      } else {
        // List view
        VStack(spacing: ModernSpacing.sm) {
          ForEach(filteredMaterials, id: \.id) { material in
            MaterialListRow(material: material)
          }
        }
      }
    }
  }
  
  // MARK: - Header Section
  
  private var headerSection: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(selectedSubject?.name ?? "全部资料")
          .font(ModernTypography.displaySmall)
          .foregroundColor(ModernColors.textPrimary)
          .fontWeight(.bold)
        
        Text("\(filteredMaterials.count) 份资料")
          .font(ModernTypography.body)
          .foregroundColor(ModernColors.textTertiary)
      }
      
      Spacer()
      
      Button(action: { viewMode.toggle() }) {
        Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
          .font(.system(size: 20, weight: .semibold))
          .foregroundColor(ModernColors.primary)
          .padding(ModernSpacing.md)
          .background(ModernColors.surface)
          .cornerRadius(ModernCornerRadius.md)
      }
    }
    .padding(.horizontal, ModernSpacing.xxl)
  }
  
  // MARK: - Filtered Materials
  
  private var filteredMaterials: [SourceDocument] {
    var materials = mockMaterials // Replace with viewModel.sourceDocuments
    
    if let subject = selectedSubject {
      materials = materials.filter { $0.subject == subject }
    }
    
    if !searchText.isEmpty {
      materials = materials.filter {
        ($0.title ?? "").localizedCaseInsensitiveContains(searchText)
      }
    }
    
    return materials
  }
  
  // MARK: - Mock Data
  
  private var mockSubjects: [Subject] {
    [
      Subject(id: UUID(), name: "数学", icon: "function", color: "#476BE0"),
      Subject(id: UUID(), name: "物理", icon: "atom", color: "#EB617A"),
      Subject(id: UUID(), name: "化学", icon: "testtube.2", color: "#52C7B8"),
      Subject(id: UUID(), name: "生物", icon: "leaf", color: "#34A853"),
      Subject(id: UUID(), name: "英语", icon: "bubble.left.and.bubble.right", color: "#EA4335")
    ]
  }
  
  private var mockMaterials: [SourceDocument] {
    [] // Replace with viewModel.sourceDocuments
  }
}

// MARK: - Subject Sidebar Row

struct SubjectSidebarRow: View {
  let subject: Subject
  let isSelected: Bool
  let onTap: () -> Void
  
  var body: some View {
    Button(action: onTap) {
      HStack(spacing: ModernSpacing.md) {
        Image(systemName: subject.icon)
          .font(.system(size: 18, weight: .medium))
          .foregroundColor(isSelected ? ModernColors.textInverse : Color(hex: subject.color))
          .frame(width: 40, height: 40)
          .background(
            RoundedRectangle(cornerRadius: ModernCornerRadius.md)
              .fill(isSelected ? Color(hex: subject.color) : Color(hex: subject.color).opacity(0.1))
          )
        
        Text(subject.name)
          .font(ModernTypography.body)
          .foregroundColor(isSelected ? ModernColors.textPrimary : ModernColors.textSecondary)
          .fontWeight(isSelected ? .semibold : .regular)
        
        Spacer()
        
        if isSelected {
          Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(ModernColors.textTertiary)
        }
      }
      .padding(.horizontal, ModernSpacing.md)
      .padding(.vertical, ModernSpacing.sm)
      .background(
        RoundedRectangle(cornerRadius: ModernCornerRadius.md)
          .fill(isSelected ? ModernColors.surfaceVariant : Color.clear)
      )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Subject Chip

struct SubjectChip: View {
  let subject: Subject
  let isSelected: Bool
  let onTap: () -> Void
  
  var body: some View {
    Button(action: onTap) {
      HStack(spacing: ModernSpacing.xs) {
        Image(systemName: subject.icon)
          .font(.system(size: 14, weight: .medium))
        
        Text(subject.name)
          .font(ModernTypography.body)
          .fontWeight(.medium)
      }
      .foregroundColor(isSelected ? ModernColors.textInverse : Color(hex: subject.color))
      .padding(.horizontal, ModernSpacing.lg)
      .padding(.vertical, ModernSpacing.sm)
      .background(
        Capsule()
          .fill(isSelected ? Color(hex: subject.color) : Color(hex: subject.color).opacity(0.1))
      )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Material Grid Card

struct MaterialGridCard: View {
  let material: SourceDocument
  
  @State private var isHovering = false
  
  var body: some View {
    ModernCard(variant: .elevated) {
      VStack(alignment: .leading, spacing: ModernSpacing.md) {
        // Icon
        ZStack {
          RoundedRectangle(cornerRadius: ModernCornerRadius.lg)
            .fill(MaterialTypeColor(material.type).opacity(0.1))
            .frame(height: 80)
          
          Image(systemName: MaterialTypeIcon(material.type))
            .font(.system(size: 40, weight: .medium))
            .foregroundColor(MaterialTypeColor(material.type))
        }
        
        // Title
        Text(material.title ?? "未命名资料")
          .font(ModernTypography.titleMedium)
          .foregroundColor(ModernColors.textPrimary)
          .fontWeight(.semibold)
          .lineLimit(2)
        
        // Metadata
        HStack(spacing: ModernSpacing.sm) {
          Text(material.subject?.name ?? "未分类")
            .font(ModernTypography.caption)
            .foregroundColor(ModernColors.textTertiary)
          
          Text("·")
            .font(ModernTypography.caption)
            .foregroundColor(ModernColors.textPlaceholder)
          
          Text("\(material.pageCount ?? 0) 页")
            .font(ModernTypography.caption)
            .foregroundColor(ModernColors.textTertiary)
        }
      }
    }
    .scaleEffect(isHovering ? 1.02 : 1.0)
    .animation(.easeInOut(duration: 0.2), value: isHovering)
    .onHover { hovering in
      isHovering = hovering
    }
  }
}

// MARK: - Material List Row

struct MaterialListRow: View {
  let material: SourceDocument
  
  var body: some View {
    HStack(spacing: ModernSpacing.md) {
      // Icon
      Image(systemName: MaterialTypeIcon(material.type))
        .font(.system(size: 24, weight: .medium))
        .foregroundColor(MaterialTypeColor(material.type))
        .frame(width: 48, height: 48)
        .background(
          RoundedRectangle(cornerRadius: ModernCornerRadius.md)
            .fill(MaterialTypeColor(material.type).opacity(0.1))
        )
      
      // Content
      VStack(alignment: .leading, spacing: 4) {
        Text(material.title ?? "未命名资料")
          .font(ModernTypography.titleSmall)
          .foregroundColor(ModernColors.textPrimary)
          .fontWeight(.semibold)
          .lineLimit(1)
        
        HStack(spacing: ModernSpacing.sm) {
          Text(material.subject?.name ?? "未分类")
            .font(ModernTypography.caption)
            .foregroundColor(ModernColors.textTertiary)
          
          Text("·")
            .font(ModernTypography.caption)
            .foregroundColor(ModernColors.textPlaceholder)
          
          Text("\(material.pageCount ?? 0) 页")
            .font(ModernTypography.caption)
            .foregroundColor(ModernColors.textTertiary)
        }
      }
      
      Spacer()
      
      Image(systemName: "chevron.right")
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(ModernColors.textTertiary)
    }
    .padding(ModernSpacing.md)
    .background(ModernColors.surfaceVariant)
    .cornerRadius(ModernCornerRadius.md)
  }
}

// MARK: - Helper Functions

private func MaterialTypeIcon(_ type: SourceDocument.SourceType) -> String {
  switch type {
  case .pdf:
    return "doc.fill"
  case .image:
    return "photo.fill"
  case .text:
    return "doc.text.fill"
  case .webClip:
    return "globe"
  @unknown default:
    return "doc.fill"
  }
}

private func MaterialTypeColor(_ type: SourceDocument.SourceType) -> Color {
  switch type {
  case .pdf:
    return ModernColors.primary
  case .image:
    return ModernColors.accent
  case .text:
    return ModernColors.secondary
  case .webClip:
    return Color.purple
  @unknown default:
    return ModernColors.primary
  }
}

// MARK: - Extensions

extension ViewMode {
  mutating func toggle() {
    self = self == .grid ? .list : .grid
  }
}

// MARK: - Preview

#Preview {
  ModernLibraryView()
    .environmentObject(AppViewModel())
}
