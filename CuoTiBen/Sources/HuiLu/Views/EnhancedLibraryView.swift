import SwiftUI

struct EnhancedLibraryView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var selectedDocument: SourceDocument?
    @State private var showsImportSheet = false
    @State private var searchText = ""
    @State private var selectedFilter: LibraryFilter = .all
    
    enum LibraryFilter: String, CaseIterable {
        case all = "全部"
        case english = "英语"
        case chinese = "语文"
        case math = "数学"
        case ready = "已就绪"
    }
    
    private var filteredDocuments: [SourceDocument] {
        var docs = viewModel.sourceDocuments
        
        // Apply filter
        switch selectedFilter {
        case .english:
            docs = docs.filter { $0.documentType == .english }
        case .chinese:
            docs = docs.filter { $0.documentType == .chinese }
        case .math:
            docs = docs.filter { $0.documentType == .math }
        case .ready:
            docs = docs.filter { $0.processingStatus == .ready }
        case .all:
            break
        }
        
        // Apply search
        if !searchText.isEmpty {
            docs = docs.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        
        return docs.sorted { $0.createdAt > $1.createdAt }
    }
    
    var body: some View {
        ZStack {
            AuroraBackground(mode: .light)
            
            VStack(spacing: 0) {
                // Enhanced header
                enhancedHeader
                
                // Filter chips
                filterSection
                
                // Document grid
                documentGrid
                
                // Empty state if needed
                if filteredDocuments.isEmpty {
                    emptyState
                }
            }
        }
        .sheet(isPresented: $showsImportSheet) {
            ImportMaterialView()
                .environmentObject(viewModel)
        }
        .sheet(item: $selectedDocument) { document in
            SourceDetailView(document: document) {
                selectedDocument = nil
            }
            .environmentObject(viewModel)
        }
    }
    
    // MARK: - Enhanced Header
    
    private var enhancedHeader: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("知识库")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [EnhancedPalette.primaryTextLight, EnhancedPalette.electricBlue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("管理你的学习资料，支持 PDF 和图片导入")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(EnhancedPalette.secondaryTextLight)
            }
            
            Spacer()
            
            // Import button
            FloatingActionButton(
                icon: "plus",
                backgroundColor: EnhancedPalette.electricBlue
            ) {
                showsImportSheet = true
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 58)
        .padding(.bottom, 24)
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(LibraryFilter.allCases, id: \.rawValue) { filter in
                    FilterChip(
                        title: filter.rawValue,
                        isSelected: selectedFilter == filter,
                        count: filterCount(for: filter)
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 16)
    }
    
    private func filterCount(for filter: LibraryFilter) -> Int {
        switch filter {
        case .all:
            return viewModel.sourceDocuments.count
        case .english:
            return viewModel.sourceDocuments.filter { $0.documentType == .english }.count
        case .chinese:
            return viewModel.sourceDocuments.filter { $0.documentType == .chinese }.count
        case .math:
            return viewModel.sourceDocuments.filter { $0.documentType == .math }.count
        case .ready:
            return viewModel.sourceDocuments.filter { $0.processingStatus == .ready }.count
        }
    }
    
    // MARK: - Document Grid
    
    private var documentGrid: some View {
        GeometryReader { geometry in
            let columns = calculateColumns(for: geometry.size.width)
            
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 16) {
                    ForEach(filteredDocuments) { document in
                        EnhancedDocumentCard(document: document) {
                            selectedDocument = document
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 140)
            }
        }
    }
    
    private func calculateColumns(for width: CGFloat) -> Int {
        if width > 1000 { return 3 }
        if width > 700 { return 2 }
        return 1
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(EnhancedPalette.electricBlue.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(EnhancedPalette.electricBlue)
            }
            
            VStack(spacing: 12) {
                Text("暂无资料")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(EnhancedPalette.primaryTextLight)
                
                Text("点击右上角按钮导入学习资料\n支持 PDF、图片等多种格式")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(EnhancedPalette.secondaryTextLight)
                    .multilineTextAlignment(.center)
            }
            
            ElegantButton(
                title: "立即导入",
                icon: "plus",
                style: .primary,
                size: .large
            ) {
                showsImportSheet = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuroraBackground(mode: .light))
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                
                if count > 0 {
                    Text("(\(count))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isSelected ? EnhancedPalette.primaryTextDark.opacity(0.7) : EnhancedPalette.tertiaryTextLight)
                }
            }
            .foregroundColor(isSelected ? .white : EnhancedPalette.primaryTextLight)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? EnhancedPalette.electricBlue : EnhancedPalette.glassLight)
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? Color.clear : EnhancedPalette.glassBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Enhanced Document Card

struct EnhancedDocumentCard: View {
    let document: SourceDocument
    let action: () -> Void
    
    private var statusConfig: (label: String, icon: String, gradient: LinearGradient) {
        switch document.processingStatus {
        case .imported:
            return ("已导入", "tray.full.fill", LinearGradient(colors: [EnhancedPalette.electricBlue, EnhancedPalette.cyanGlow], startPoint: .leading, endPoint: .trailing))
        case .parsing:
            return ("解析中", "sparkles", LinearGradient(colors: [EnhancedPalette.sunsetOrange, EnhancedPalette.magentaDream], startPoint: .leading, endPoint: .trailing))
        case .ready:
            return ("已就绪", "checkmark.circle.fill", LinearGradient(colors: [EnhancedPalette.auroraGreen, EnhancedPalette.cyanGlow], startPoint: .leading, endPoint: .trailing))
        case .failed:
            return ("失败", "exclamationmark.triangle.fill", LinearGradient(colors: [EnhancedPalette.sunsetOrange, EnhancedPalette.magentaDream], startPoint: .leading, endPoint: .trailing))
        }
    }
    
    private var typeGradient: LinearGradient {
        switch document.documentType {
        case .english:
            return LinearGradient(colors: [EnhancedPalette.electricBlue, EnhancedPalette.cyanGlow], startPoint: .leading, endPoint: .trailing)
        case .chinese:
            return LinearGradient(colors: [EnhancedPalette.magentaDream, EnhancedPalette.sunsetOrange], startPoint: .leading, endPoint: .trailing)
        case .math:
            return LinearGradient(colors: [EnhancedPalette.auroraGreen, EnhancedPalette.cyanGlow], startPoint: .leading, endPoint: .trailing)
        case .politics:
            return LinearGradient(colors: [EnhancedPalette.sunsetOrange, EnhancedPalette.magentaDream], startPoint: .leading, endPoint: .trailing)
        }
    }
    
    var body: some View {
        PremiumGlassPanel(tone: .ultraLight, cornerRadius: 28, padding: 20) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 16) {
                    // Header with icon and status
                    HStack(alignment: .top, spacing: 14) {
                        // Type icon
                        ZStack {
                            Circle()
                                .fill(typeGradient)
                                .frame(width: 52, height: 52)
                            
                            Image(systemName: typeIcon)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .shadow(color: typeGradient.colors[0].opacity(0.3), radius: 8, y: 4)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            // Status badge
                            HStack(spacing: 6) {
                                Image(systemName: statusConfig.icon)
                                    .font(.system(size: 11, weight: .bold))
                                Text(statusConfig.label)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(statusConfig.gradient)
                            )
                            
                            // Document type
                            Text(document.documentType.displayName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(EnhancedPalette.tertiaryTextLight)
                        }
                        
                        Spacer()
                        
                        // Chevron
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(EnhancedPalette.tertiaryTextLight)
                    }
                    
                    // Title
                    Text(document.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(EnhancedPalette.primaryTextLight)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    // Metadata
                    HStack(spacing: 12) {
                        if document.chunkCount > 0 {
                            MetaBadge(icon: "square.grid.2x2", text: "\(document.chunkCount) 知识块")
                        }
                        
                        if document.generatedCardCount > 0 {
                            MetaBadge(icon: "note.text", text: "\(document.generatedCardCount) 卡片")
                        }
                        
                        if document.pageCount > 0 && document.chunkCount == 0 {
                            MetaBadge(icon: "doc.on.doc", text: "\(document.pageCount) 页")
                        }
                    }
                    
                    // Progress bar if has chunks
                    if document.chunkCount > 0 {
                        VStack(spacing: 8) {
                            HStack {
                                Text("学习进度")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(EnhancedPalette.tertiaryTextLight)
                                
                                Spacer()
                                
                                Text("\(Int(Double(document.learnedSentenceCount) / max(Double(document.chunkCount * 5), 1) * 100))%")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(EnhancedPalette.secondaryTextLight)
                            }
                            
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(EnhancedPalette.glassLight)
                                        .frame(height: 6)
                                    
                                    Capsule()
                                        .fill(typeGradient)
                                        .frame(width: min(geo.size.width * progressPercentage, geo.size.width), height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
    
    private var typeIcon: String {
        switch document.documentType {
        case .english: return "character.book.closed.fill"
        case .chinese: return "book.fill"
        case .math: return "function"
        case .politics: return "flag.fill"
        }
    }
    
    private var progressPercentage: CGFloat {
        guard document.chunkCount > 0 else { return 0 }
        return Double(document.learnedSentenceCount) / Double(document.chunkCount * 5)
    }
}

// MARK: - Meta Badge

struct MetaBadge: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(EnhancedPalette.secondaryTextLight)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(EnhancedPalette.glassLight)
                .overlay(
                    Capsule()
                        .stroke(EnhancedPalette.glassBorder, lineWidth: 0.8)
                )
        )
    }
}

#if DEBUG
struct EnhancedLibraryView_Previews: PreviewProvider {
    static var previews: some View {
        EnhancedLibraryView()
            .environmentObject(AppViewModel())
    }
}
#endif
