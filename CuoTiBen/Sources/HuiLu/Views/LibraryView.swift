import SwiftUI

#if os(iOS)
import UIKit
#endif

struct LibraryView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var searchText = ""
    @State private var selectedFilter: LibraryFilter = .recent
    @State private var selectedDocument: SourceDocument?
    @State private var showingImport = false

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    enum LibraryFilter: String, CaseIterable {
        case recent = "最近"
        case weak = "薄弱"
        case subjects = "学科"
    }

    private var filteredDocuments: [SourceDocument] {
        let documents = viewModel.sourceDocuments.filter {
            searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText)
        }

        switch selectedFilter {
        case .recent:
            return documents.sorted { $0.importDate > $1.importDate }
        case .weak:
            return documents.sorted { lhs, rhs in
                lhs.generatedCardCount > rhs.generatedCardCount
            }
        case .subjects:
            return documents.sorted { $0.title < $1.title }
        }
    }

    var body: some View {
        ZStack {
            if isPad {
                archivistPadBody
            } else {
                phoneLibraryBody
            }

            if let selectedDocument {
                Color.black.opacity(isPad ? 0.28 : 0.22)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            self.selectedDocument = nil
                        }
                    }

                SourceDetailView(document: selectedDocument) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        self.selectedDocument = nil
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $showingImport) {
            ImportMaterialView()
                .environmentObject(viewModel)
        }
        .onAppear {
            presentPendingPreviewIfNeeded()
        }
        .onChange(of: viewModel.pendingPreviewDocumentID) { _ in
            presentPendingPreviewIfNeeded()
        }
    }

    private func presentPendingPreviewIfNeeded() {
        guard let pendingID = viewModel.pendingPreviewDocumentID,
              let document = viewModel.sourceDocuments.first(where: { $0.id == pendingID }) else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
            selectedDocument = document
        }
        viewModel.pendingPreviewDocumentID = nil
    }
}

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppPalette.paperMuted)

            TextField("搜索知识库", text: $text)
                .font(.system(size: 16, weight: .medium, design: .serif))
                .textInputAutocapitalization(.never)

            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppPalette.paperMuted)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
    }
}

struct SegmentedGlassControl<T: Hashable>: View {
    let items: [T]
    @Binding var selected: T
    let label: KeyPath<T, String>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        selected = item
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: iconName(for: item))
                            .font(.system(size: 18, weight: .medium))
                        Text(item[keyPath: label])
                            .font(.system(size: 16, weight: selected == item ? .bold : .medium, design: .serif))
                    }
                    .foregroundStyle(selected == item ? AppPalette.paperInk : AppPalette.paperMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selected == item ? Color.white.opacity(0.88) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.94), lineWidth: 1)
        )
    }

    private func iconName(for item: T) -> String {
        guard let filter = item as? LibraryView.LibraryFilter else { return "circle" }
        switch filter {
        case .recent:
            return "clock"
        case .weak:
            return "doc.text"
        case .subjects:
            return "shippingbox"
        }
    }
}

private extension LibraryView {
    var phoneLibraryBody: some View {
        ZStack {
            PaperCanvasBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("活跃知识库")
                            .font(.system(size: 32, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.paperInk)

                        Text("把导入资料整理成可随时检索、回看的知识地图。")
                            .font(.system(size: 15, weight: .medium, design: .serif))
                            .foregroundStyle(AppPalette.paperMuted)
                    }

                    HStack(spacing: 12) {
                        SearchBar(text: $searchText)

                        Button {
                            showingImport = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(AppPalette.paperInk.opacity(0.75))
                                .frame(width: 48, height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.white.opacity(0.78))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.94), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    SegmentedGlassControl(
                        items: LibraryFilter.allCases,
                        selected: $selectedFilter,
                        label: \.rawValue
                    )

                    HStack(spacing: 14) {
                        LibraryToolbarChip(icon: "slider.horizontal.3", title: "筛选")
                        LibraryToolbarChip(icon: "arrow.up.arrow.down", title: "排序")
                        LibraryToolbarChip(icon: "tag", title: "标签")
                    }

                    ForEach(Array(filteredDocuments.enumerated()), id: \.element.id) { index, document in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                                selectedDocument = document
                            }
                        } label: {
                            LibraryDocumentCard(document: document, paletteIndex: index)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 150)
                }
                .padding(.horizontal, 24)
                .padding(.top, 52)
            }
        }
    }

    var archivistPadBody: some View {
        ZStack {
            LinearGradient(
                colors: [ArchivistColors.deskMatStart, ArchivistColors.deskMatEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                NotebookGrid(spacing: 20)
                    .opacity(0.04)
            }
            .ignoresSafeArea()

            HStack(spacing: 0) {
                ArchivistLibrarySideRail(onImport: {
                    showingImport = true
                })

                VStack(spacing: 0) {
                    ArchivistLibraryTopBar(
                        searchText: $searchText,
                        selectedFilter: $selectedFilter,
                        onImport: { showingImport = true }
                    )
                    .padding(.horizontal, 28)
                    .padding(.top, 20)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Academic Semester 2026")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .textCase(.uppercase)
                                    .tracking(4)
                                    .foregroundStyle(Color.white.opacity(0.52))

                                Capsule()
                                    .fill(ArchivistColors.blueWash.opacity(0.8))
                                    .frame(width: 58, height: 3)
                            }

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 248), spacing: 22)],
                                spacing: 26
                            ) {
                                ForEach(Array(filteredDocuments.enumerated()), id: \.element.id) { index, document in
                                    Button {
                                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                            selectedDocument = document
                                        }
                                    } label: {
                                        ArchivistLibraryFolderCard(
                                            document: document,
                                            paletteIndex: index
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }

                                ArchivistAddArchiveCard {
                                    showingImport = true
                                }
                            }

                            VStack(alignment: .leading, spacing: 18) {
                                Text("Active Notebooks")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .textCase(.uppercase)
                                    .tracking(4)
                                    .foregroundStyle(Color.white.opacity(0.46))

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 22) {
                                        ForEach(Array(filteredDocuments.prefix(8).enumerated()), id: \.element.id) { index, document in
                                            ArchivistNotebookSpine(document: document, paletteIndex: index)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 34)
                        .padding(.bottom, 54)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct ArchivistLibrarySideRail: View {
    let onImport: () -> Void

    private let items: [(String, String, Bool)] = [
        ("Notebooks", "books.vertical", false),
        ("Library", "archivebox", true),
        ("Research", "chart.bar", false),
        ("Favorites", "star", false),
        ("Trash", "trash", false)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(ArchivistColors.primaryInk)
                    Text("The Archivist")
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(ArchivistColors.primaryInk)
                }

                Text("Digital Archivist")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(1.6)
                    .foregroundStyle(ArchivistColors.softInk)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(items, id: \.0) { item in
                    HStack(spacing: 14) {
                        Image(systemName: item.1)
                            .font(.system(size: 18, weight: item.2 ? .bold : .medium))
                        Text(item.0)
                            .font(.system(size: 14, weight: item.2 ? .semibold : .medium))
                    }
                    .foregroundStyle(item.2 ? ArchivistColors.primaryInk : ArchivistColors.mutedInk.opacity(0.84))
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(item.2 ? ArchivistColors.blueWash.opacity(0.9) : Color.clear)
                    )
                }
            }

            Spacer()

            Button(action: onImport) {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                    Text("New Document")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ArchivistColors.primaryInk)
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                railFooterItem(icon: "gearshape", title: "Settings")
                railFooterItem(icon: "questionmark.circle", title: "Support")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
        .frame(width: 272, alignment: .topLeading)
        .background(ArchivistColors.railFill)
        .shadow(color: ArchivistColors.paperShadow, radius: 24, x: 8, y: 0)
    }

    private func railFooterItem(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
            Text(title)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(ArchivistColors.mutedInk.opacity(0.84))
        .padding(.horizontal, 10)
        .frame(height: 38)
    }
}

private struct ArchivistLibraryTopBar: View {
    @Binding var searchText: String
    @Binding var selectedFilter: LibraryView.LibraryFilter
    let onImport: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 12) {
                Text("Resources Library")
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.9))

                HStack(spacing: 10) {
                    topLink("Tools", active: false)
                    topLink("Library", active: true)
                    topLink("Export", active: false)
                }
                .padding(.leading, 12)
            }

            Spacer()

            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.white.opacity(0.45))

                    TextField("Search archives...", text: $searchText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 16)
                .frame(width: 280, height: 42)
                .background(Color.white.opacity(0.1), in: Capsule())

                Button(action: onImport) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(ArchivistColors.primaryInk, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func topLink(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 14, weight: active ? .semibold : .medium))
            .foregroundStyle(active ? Color.white : Color.white.opacity(0.58))
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                if active {
                    Capsule()
                        .fill(ArchivistColors.blueWash)
                        .frame(height: 2)
                }
            }
    }
}

private struct ArchivistLibraryFolderCard: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let document: SourceDocument
    let paletteIndex: Int

    private var palette: (folder: Color, tab: Color, stamp: String) {
        switch paletteIndex % 3 {
        case 0:
            return (ArchivistColors.tanFolder, ArchivistColors.folderTabTan, "READING")
        case 1:
            return (ArchivistColors.blueFolder, ArchivistColors.folderTabBlue, "RESEARCH")
        default:
            return (ArchivistColors.roseFolder, ArchivistColors.folderTabRose, "NOTES")
        }
    }

    private var progress: CGFloat {
        if viewModel.parseSessionInfo(for: document)?.fallbackUsed == true || viewModel.structuredSource(for: document) != nil {
            return 1
        }
        switch document.processingStatus {
        case .ready:
            return 1
        case .parsing:
            return 0.42
        case .failed:
            return 0.12
        case .imported:
            return 0.2
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.folder)

            VStack(alignment: .leading, spacing: 14) {
                Capsule()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 42, height: 4)

                Text(document.title)
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.black.opacity(0.78))
                    .lineLimit(3)

                Text(document.documentType.displayName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(1.6)
                    .foregroundStyle(Color.black.opacity(0.42))

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 8) {
                    Capsule()
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 6)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(ArchivistColors.primaryInk)
                                .frame(width: max(progress * 210, 24), height: 6)
                        }

                    HStack {
                        Text(progressLabel)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.42))

                        Spacer()

                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.78))
                    }
                }
            }
            .padding(24)

            HStack(spacing: 8) {
                Spacer()
                Text(palette.stamp)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.42))
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(palette.tab)
                    )
            }
            .offset(x: -20, y: -10)
        }
        .frame(height: 316)
        .overlay(alignment: .bottomTrailing) {
            if document.processingStatus == .ready {
                Text("Archived")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(ArchivistColors.primaryInk.opacity(0.45))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(ArchivistColors.primaryInk.opacity(0.25), lineWidth: 1.5)
                    )
                    .rotationEffect(.degrees(-11))
                    .padding(18)
            }
        }
        .shadow(color: Color.black.opacity(0.14), radius: 24, y: 14)
    }

    private var progressLabel: String {
        if let info = viewModel.parseSessionInfo(for: document), info.skippedBecauseUnconfigured {
            return "LOCAL SKELETON"
        }
        if viewModel.parseSessionInfo(for: document)?.fallbackUsed == true {
            return "LOCAL SKELETON"
        }
        switch document.processingStatus {
        case .ready: return "ARCHIVED"
        case .parsing: return "PARSING"
        case .failed: return "FAILED"
        case .imported: return "IMPORTED"
        }
    }
}

private struct ArchivistAddArchiveCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 14) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.34))

                Text("Add New Archive")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.42))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 316)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ArchivistNotebookSpine: View {
    let document: SourceDocument
    let paletteIndex: Int

    private var color: Color {
        switch paletteIndex % 4 {
        case 0: return ArchivistColors.primaryInk
        case 1: return ArchivistColors.tertiaryContainerFallback
        case 2: return ArchivistColors.secondarySpine
        default: return Color(red: 193 / 255, green: 188 / 255, blue: 181 / 255)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color)
            .frame(width: 62, height: 244)
            .overlay(alignment: .center) {
                Text(document.title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .rotationEffect(.degrees(90))
                    .lineLimit(1)
                    .frame(width: 200)
            }
            .shadow(color: Color.black.opacity(0.2), radius: 16, y: 10)
    }
}

struct LibraryToolbarChip: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))

            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .serif))
        }
        .foregroundStyle(AppPalette.paperInk.opacity(0.72))
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

struct LibraryDocumentCard: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let document: SourceDocument
    let paletteIndex: Int

    private var palette: [Color] {
        switch paletteIndex % 4 {
        case 0:
            return [AppPalette.paperFolderBlue, AppPalette.paperTape]
        case 1:
            return [AppPalette.paperFolderOrange, AppPalette.paperTapeBlue]
        case 2:
            return [AppPalette.paperFolderLavender, AppPalette.paperHighlight]
        default:
            return [Color(red: 125 / 255, green: 191 / 255, blue: 149 / 255), AppPalette.paperTape]
        }
    }

    private var status: (label: String, icon: String, color: Color) {
        if parseInfo?.skippedBecauseUnconfigured == true {
            return ("文档解析接口未配置", "point.3.connected.trianglepath.dotted", Color.blue.opacity(0.85))
        }
        if parseInfo?.fallbackUsed == true {
            return ("本地骨架", "square.stack.3d.up", Color.blue.opacity(0.85))
        }
        switch document.processingStatus {
        case .imported:
            return ("已导入", "tray.full.fill", Color.blue.opacity(0.85))
        case .parsing:
            return ("云端解析中", "sparkles", Color.orange.opacity(0.9))
        case .ready:
            return ("AI 已分析", "checkmark.circle.fill", Color.green.opacity(0.85))
        case .failed:
            return ("请求失败，可重试", "exclamationmark.triangle.fill", Color.red.opacity(0.82))
        }
    }

    private var liveDocument: SourceDocument {
        viewModel.sourceDocuments.first(where: { $0.id == document.id }) ?? document
    }

    private var parseInfo: ParseSessionInfo? {
        viewModel.parseSessionInfo(for: liveDocument)
    }

    private var structuredSource: StructuredSourceBundle? {
        viewModel.structuredSource(for: liveDocument)
    }

    private var materialModeLabel: String {
        structuredSource?.passageAnalysisDiagnostics?.materialMode.rawValue ?? "pending"
    }

    private var parseStatusText: String {
        if let info = parseInfo {
            if info.skippedBecauseUnconfigured {
                return "文档解析云接口未配置，已使用本地解析。"
            }
            if info.fallbackUsed {
                return info.fallbackReason.map { "本地骨架：\($0)" } ?? "本地骨架"
            }
            if info.ppSucceeded {
                return "云端成功"
            }
            return info.documentParseRemoteStatus ?? liveDocument.processingStatus.displayName
        }
        return liveDocument.lastProcessingError ?? liveDocument.processingStatus.displayName
    }

    private var progressText: String {
        if parseInfo?.fallbackUsed == true || structuredSource != nil {
            return "100%"
        }
        switch liveDocument.processingStatus {
        case .ready: return "100%"
        case .parsing: return "42%"
        case .imported: return "20%"
        case .failed: return "12%"
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(palette[0].opacity(0.95))
                .offset(x: -8, y: 8)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppPalette.paperCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AppPalette.paperInk.opacity(0.68), lineWidth: 1.4)
                )
                .overlay(alignment: .topTrailing) {
                    PaperTapeAccent(color: palette[1], width: 76, height: 20)
                        .offset(x: 12, y: -8)
                }

            VStack(alignment: .leading, spacing: 18) {
                Text(liveDocument.title)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(AppPalette.paperInk)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    documentLine(icon: "doc", text: "\(liveDocument.documentType.displayName) · \(liveDocument.pageCount) 页")
                    documentLine(icon: "shippingbox", text: "materialMode=\(materialModeLabel)")
                    documentLine(icon: "rectangle.text.magnifyingglass", text: parseStatusText)
                    documentLine(icon: "clock", text: "最近导入 \(formattedImportDate)")
                    documentLine(icon: "chart.line.uptrend.xyaxis", text: "progress=\(progressText)")
                }

                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: status.icon)
                            .font(.system(size: 15, weight: .semibold))
                        Text(status.label)
                            .font(.system(size: 15, weight: .bold, design: .serif))
                    }
                    .foregroundStyle(status.color)

                    Spacer()

                    HStack(spacing: 8) {
                        Text("候选点 \(liveDocument.candidateKnowledgePoints.count)")
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(AppPalette.paperInk.opacity(0.84))
                        Image(systemName: liveDocument.processingStatus.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.24))
                    }
                }
            }
            .padding(30)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .shadow(color: palette[0].opacity(0.16), radius: 18, y: 10)
    }

    private func documentLine(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
            Text(text)
                .font(.system(size: 16, weight: .medium, design: .serif))
        }
        .foregroundStyle(AppPalette.paperInk.opacity(0.86))
    }

    private var formattedImportDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: liveDocument.importDate)
    }
}

struct KnowledgeDetailOverlay: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let document: SourceDocument
    let onClose: () -> Void
    @State private var isGeneratingDrafts = false
    @State private var generationNote: String?
    @State private var isExpanded = false
    @State private var dragOffset: CGFloat = 0

    private var liveDocument: SourceDocument {
        viewModel.sourceDocuments.first(where: { $0.id == document.id }) ?? document
    }

    private var previewChunks: [KnowledgeChunk] {
        viewModel.chunks(for: liveDocument)
    }

    private var conceptTags: [String] {
        let fallback = [liveDocument.documentType.displayName, "重点整理", "深度复习"]
        return Array((liveDocument.topicTags + fallback).prefix(6))
    }

    private var sectionTitles: [String] {
        Array((liveDocument.sectionTitles.isEmpty ? ["等待解析章节输出"] : liveDocument.sectionTitles).prefix(6))
    }

    private var candidatePoints: [String] {
        Array((liveDocument.candidateKnowledgePoints.isEmpty ? ["等待候选知识点输出"] : liveDocument.candidateKnowledgePoints).prefix(6))
    }

    private var generatedDraftCount: Int {
        max(liveDocument.generatedCardCount, viewModel.generatedCards(for: liveDocument).count)
    }

    private var detailPrimaryTitle: String {
        if isGeneratingDrafts {
            return "生成中..."
        }
        if generatedDraftCount > 0 {
            return "开始复习"
        }
        return "生成卡片"
    }

    private var detailPrimaryIcon: String {
        if isGeneratingDrafts {
            return "hourglass"
        }
        if generatedDraftCount > 0 {
            return "play.fill"
        }
        return "rectangle.stack.fill"
    }

    private var canGenerateDrafts: Bool {
        liveDocument.processingStatus == .ready && liveDocument.chunkCount > 0 && !isGeneratingDrafts
    }

    private var dismissProgress: CGFloat {
        min(max(dragOffset / 220, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let safeBottom = max(proxy.safeAreaInsets.bottom, 14)
            let collapsedHeight = min(max(proxy.size.height * 0.72, 560), proxy.size.height * 0.84)
            let expandedHeight = proxy.size.height * 0.93
            let baseHeight = isExpanded ? expandedHeight : collapsedHeight
            let liveHeight = min(max(baseHeight - dragOffset, collapsedHeight), expandedHeight)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                GlassPanel(tone: .light, cornerRadius: 34, padding: 0) {
                    VStack(spacing: 0) {
                        overlayHeader
                            .padding(.horizontal, 24)
                            .padding(.top, 14)
                            .padding(.bottom, 18)
                            .contentShape(Rectangle())
                            .gesture(sheetDragGesture(collapsedHeight: collapsedHeight, expandedHeight: expandedHeight))

                        ScrollView(showsIndicators: false) {
                            overlayBody
                            .padding(.horizontal, 24)
                            .padding(.bottom, safeBottom + 118)
                        }

                        overlayActionBar(safeBottom: safeBottom)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(height: liveHeight)
            }
        }
        .ignoresSafeArea()
    }

    private var overlayHeader: some View {
        HStack(alignment: .center) {
            Capsule()
                .fill(Color.black.opacity(0.14))
                .frame(width: 66, height: 6)

            Spacer()

            Text(isExpanded ? "下拉收起" : "上拉展开")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.38))

            Spacer()

            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                    Text("关闭")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.48))
            }
            .buttonStyle(.plain)
        }
    }

    private var overlayBody: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("资料详情")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.82))

            VStack(alignment: .leading, spacing: 10) {
                Text("资料来源")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.74))

                HStack(alignment: .top, spacing: 12) {
                    FrostedOrb(icon: liveDocument.documentType.icon, size: 42, tone: .light)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(liveDocument.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.82))

                        Text("\(liveDocument.pageCount) 页 • 导入于 \(formattedDate)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.48))
                    }
                }
            }

            HStack(spacing: 10) {
                LibraryMetaPill(title: liveDocument.processingStatus.displayName)
                if liveDocument.chunkCount > 0 {
                    LibraryMetaPill(title: "\(liveDocument.chunkCount) 个知识块")
                }
                if generatedDraftCount > 0 {
                    LibraryMetaPill(title: "\(generatedDraftCount) 张草稿")
                } else if liveDocument.chunkCount > 0 {
                    LibraryMetaPill(title: "结构化预览")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("结构化预览")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.74))

                if previewChunks.isEmpty {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(Color.blue.opacity(0.65))

                                Text("解析完成后，这里会展示知识块预览。")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.5))
                            }
                            .padding(18)
                        }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(previewChunks) { chunk in
                            StructuredPreviewCard(
                                title: displayTitle(for: chunk),
                                locator: displayLocator(for: chunk),
                                content: displaySnippet(for: chunk),
                                tags: Array(chunk.candidateKnowledgePoints.prefix(3))
                            )
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("主题标签")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.74))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    ForEach(conceptTags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.55), Color.purple.opacity(0.55)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("解析章节")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.74))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    ForEach(sectionTitles, id: \.self) { section in
                        Text(section)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.72))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.52))
                            )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("候选知识点")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.74))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    ForEach(candidatePoints, id: \.self) { point in
                        Text(point)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.75))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.blue.opacity(0.08))
                            )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("解析说明")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.74))

                Text(detailDescription)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .lineSpacing(6)
            }
        }
    }

    private func overlayActionBar(safeBottom: CGFloat) -> some View {
        VStack(spacing: 12) {
            if let generationNote {
                Text(generationNote)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.blue.opacity(0.72))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                DetailActionButton(title: "分享", icon: "square.and.arrow.up") {}
                DetailActionButton(
                    title: detailPrimaryTitle,
                    icon: detailPrimaryIcon,
                    isDisabled: !canGenerateDrafts && generatedDraftCount == 0
                ) {
                    handlePrimaryAction()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, safeBottom)
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.78))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(height: 1)
                }
        )
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: liveDocument.importDate)
    }

    private func displayTitle(for chunk: KnowledgeChunk) -> String {
        let trimmed = chunk.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名知识块" : trimmed
    }

    private func displayLocator(for chunk: KnowledgeChunk) -> String {
        if let locator = chunk.sourceLocator?.trimmingCharacters(in: .whitespacesAndNewlines), !locator.isEmpty {
            return locator
        }
        if let startPosition = chunk.startPosition {
            return "原文第 \(startPosition) 页"
        }
        return "原文定位待补充"
    }

    private func displaySnippet(for chunk: KnowledgeChunk) -> String {
        let normalized = chunk.content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return "当前知识块暂时没有正文摘要。"
        }

        if normalized.count > 120 {
            return String(normalized.prefix(120)) + "…"
        }
        return normalized
    }

    private var detailDescription: String {
        switch liveDocument.processingStatus {
        case .imported:
            return "资料记录已经创建，但还没有进入完整解析。下一步会抽取正文、章节定位、标签和候选知识点。"
        case .parsing:
            return "系统正在异步抽取正文文本，并把内容整理成带来源定位的结构化预览。解析完成后你可以在确认预览后，再手动生成问答卡、填空卡和判断/选择卡草稿。"
        case .ready:
            if generatedDraftCount > 0 {
                return "这份资料已经完成结构化预览，并已生成 \(generatedDraftCount) 张卡片草稿。你可以直接进入复习，也可以继续检查章节、标签和候选知识点。"
            }

            return "这份资料已经完成结构化预览，共输出 \(liveDocument.chunkCount) 个知识块、\(liveDocument.candidateKnowledgePoints.count) 个候选知识点。确认这些结果没有问题后，再手动生成卡片草稿。"
        case .failed:
            return liveDocument.lastProcessingError ?? "这份资料在解析阶段失败，需要重新导入或检查源文件格式。"
        }
    }

    private func handlePrimaryAction() {
        if generatedDraftCount > 0 {
            NotificationCenter.default.post(name: .switchToReviewTab, object: nil)
            onClose()
            return
        }

        guard canGenerateDrafts else { return }

        generationNote = nil
        isGeneratingDrafts = true

        Task {
            do {
                let count = try await viewModel.generateDraftCards(for: liveDocument)
                await MainActor.run {
                    generationNote = "已生成 \(count) 张卡片草稿，现在可以开始复习。"
                    isGeneratingDrafts = false
                }
            } catch {
                await MainActor.run {
                    generationNote = error.localizedDescription
                    isGeneratingDrafts = false
                }
            }
        }
    }

    private func sheetDragGesture(collapsedHeight: CGFloat, expandedHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let predictedHeight = (isExpanded ? expandedHeight : collapsedHeight) - value.predictedEndTranslation.height

                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    if value.translation.height > 160 || value.predictedEndTranslation.height > 220 {
                        if isExpanded {
                            isExpanded = false
                        } else {
                            onClose()
                        }
                    } else if predictedHeight > (collapsedHeight + expandedHeight) * 0.5 || value.translation.height < -70 {
                        isExpanded = true
                    } else {
                        isExpanded = false
                    }

                    dragOffset = 0
                }
            }
    }
}

struct DetailActionButton: View {
    let title: String
    let icon: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(isDisabled ? Color.black.opacity(0.28) : Color.black.opacity(0.52))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isDisabled ? Color.white.opacity(0.24) : Color.white.opacity(0.42))
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct StructuredPreviewCard: View {
    let title: String
    let locator: String
    let content: String
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.82))
                        .multilineTextAlignment(.leading)

                    Text(locator)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.blue.opacity(0.7))
                }

                Spacer()

                FrostedOrb(icon: "text.alignleft", size: 34, tone: .light)
            }

            Text(content)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.68))
                .lineSpacing(4)

            if !tags.isEmpty {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.55))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.62))
                            )
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.82), lineWidth: 1)
                )
        )
    }
}
