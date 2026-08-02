import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let showsEmbeddedSidebar: Bool

    @State private var showingReview = false
    @State private var selectedWorkbenchDocument: SourceDocument?
    @State private var selectedWorkbenchAnchor: SourceAnchor?
    @State private var selectedRecentDocument: SourceDocument?
    @State private var diagnosticDocument: SourceDocument?
    @State private var showsSettings = false
    @State private var showsNotesHome = false
    @State private var showingImport = false
    @State private var showingCloudDiagnostics = false

    init(showsEmbeddedSidebar: Bool = true) {
        self.showsEmbeddedSidebar = showsEmbeddedSidebar
    }

    private var masteryValue: Int {
        Int(viewModel.progressPercentage * 100)
    }

    private var statItems: [HomeStatItem] {
        [
            HomeStatItem(icon: "flame.fill", title: "连续学习", value: "\(viewModel.dailyProgress.streakDays) 天", tint: AppPalette.mint),
            HomeStatItem(icon: "bolt.fill", title: "累计经验", value: "\(viewModel.totalCardsLearned * 52)", tint: AppPalette.primary),
            HomeStatItem(icon: "clock.fill", title: "投入时长", value: "3小时20分", tint: AppPalette.cyan),
            HomeStatItem(icon: "chart.bar.fill", title: "本周正确率", value: "\(Int(viewModel.dailyProgress.weeklyAccuracy * 100))%", tint: AppPalette.amber)
        ]
    }

    private var workbenchDocuments: [SourceDocument] {
        viewModel.englishDocumentsForWorkbench()
    }

    private var primaryWorkbenchDocument: SourceDocument? {
        workbenchDocuments.first
    }

    private var recentImportedDocuments: [SourceDocument] {
        Array(viewModel.sourceDocuments.sorted { $0.importDate > $1.importDate }.prefix(4))
    }

    private var usesPadDashboard: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var homeQuote: String {
        "“Every step is progress.”"
    }

    private var todaysTasks: [String] {
        var items: [String] = []
        if let primaryWorkbenchDocument {
            let progress = viewModel.reviewWorkbenchProgress(for: primaryWorkbenchDocument)
            items.append("继续 \(primaryWorkbenchDocument.title) 的 \(progress.lastAnchorLabel)")
        }
        items.append("完成 \(viewModel.dailyProgress.pendingReviewsCount) 个待复习点")
        return items
    }

    var body: some View {
        GeometryReader { proxy in
            let usesWideWorkbench = usesPadDashboard && proxy.size.width >= 680

            ZStack {
                PaperCanvasBackground()
                HomeDashboardView(
                    isPad: usesWideWorkbench,
                    showsSidebar: showsEmbeddedSidebar && usesWideWorkbench,
                    availableWidth: proxy.size.width,
                    safeAreaInsets: proxy.safeAreaInsets,
                    onImport: { showingImport = true },
                    onCloudDiagnostics: { showingCloudDiagnostics = true },
                    onOpenDocument: { selectedRecentDocument = $0 },
                    onContinueDocument: { document in
                        selectedWorkbenchAnchor = nil
                        selectedWorkbenchDocument = document
                    },
                    onShowDiagnostics: { diagnosticDocument = $0 },
                    onOpenLibrary: {
                        NotificationCenter.default.post(name: .switchToLibraryTab, object: nil)
                    },
                    onOpenNotes: { showsNotesHome = true },
                    onOpenReview: {
                        if let document = viewModel.continueLearningDocument {
                            selectedWorkbenchDocument = document
                        } else {
                            showingReview = true
                        }
                    },
                    onOpenSettings: { showsSettings = true }
                )
                .environmentObject(viewModel)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showingReview) {
            ReviewSessionView()
                .environmentObject(viewModel)
        }
        .fullScreenCover(item: $selectedWorkbenchDocument) { document in
            ReviewWorkbenchView(document: document, initialAnchor: selectedWorkbenchAnchor) {
                selectedWorkbenchAnchor = nil
                selectedWorkbenchDocument = nil
            }
            .environmentObject(viewModel)
        }
        .fullScreenCover(item: $selectedRecentDocument) { document in
            SourceDetailView(document: document) {
                selectedRecentDocument = nil
            }
            .environmentObject(viewModel)
        }
        .fullScreenCover(isPresented: $showingImport) {
            ImportMaterialView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showsNotesHome) {
            NotesHomeView { anchor in
                showsNotesHome = false
                selectedWorkbenchAnchor = anchor
                if let document = viewModel.sourceDocument(for: anchor) {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 180_000_000)
                        selectedWorkbenchDocument = document
                    }
                }
            }
            .environmentObject(viewModel)
        }
        .sheet(isPresented: $showsSettings) {
            AppSettingsSheet()
                .environmentObject(viewModel)
        }
        .sheet(item: $diagnosticDocument) { document in
            HomeMaterialDiagnosticsSheet(document: document)
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showingCloudDiagnostics) {
            NavigationView {
                List {
                    Section("Build") {
                        HomeBuildFingerprintCard(fingerprint: RuntimeBuildFingerprint.current)
                    }
                    Section("Cloud request probe") {
                        CloudRequestDiagnosticsView()
                    }
                }
                .navigationTitle("云端检测")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") {
                            showingCloudDiagnostics = false
                        }
                    }
                }
            }
        }
    }

    private var dashboardSideRail: some View {
        DashboardCard(cornerRadius: 24, padding: 14, tint: AppPalette.paperBackgroundDeep) {
            VStack(spacing: 18) {
                DashboardRailItem(icon: "house", title: "首页", isSelected: true, action: {})
                DashboardRailItem(icon: "books.vertical", title: "知识库", isSelected: false) {
                    NotificationCenter.default.post(name: .switchToLibraryTab, object: nil)
                }
                DashboardRailItem(icon: "note.text", title: "笔记", isSelected: false) {
                    showsNotesHome = true
                }
                DashboardRailItem(icon: "arrow.triangle.2.circlepath", title: "复习", isSelected: false) {
                    if let primaryWorkbenchDocument {
                        selectedWorkbenchDocument = primaryWorkbenchDocument
                    } else {
                        showingReview = true
                    }
                }
                DashboardRailItem(icon: "gearshape", title: "设置", isSelected: false) {
                    showsSettings = true
                }
            }
        }
        .frame(width: 104)
        .padding(.vertical, 36)
    }

    private func dashboardHero(isPad: Bool) -> some View {
        HStack(alignment: .top, spacing: isPad ? 32 : 18) {
            VStack(alignment: .leading, spacing: isPad ? 18 : 12) {
                HStack(spacing: 10) {
                    Text("Welcome back,")
                        .font(.system(size: isPad ? 26 : 18, weight: .semibold, design: .serif))
                        .italic()
                        .foregroundStyle(AppPalette.paperInk.opacity(0.86))

                    Spacer(minLength: 0)

                    if !isPad {
                        HStack(spacing: 10) {
                            DashboardIconButton(icon: "gearshape") {
                                showsSettings = true
                            }

                            DashboardIconButton(icon: "note.text") {
                                showsNotesHome = true
                            }
                        }
                    }
                }

                Text("Boyu")
                    .font(.system(size: isPad ? 64 : 42, weight: .bold, design: .serif))
                    .foregroundStyle(AppPalette.paperInk)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily Goal:")
                        .font(.system(size: isPad ? 18 : 15, weight: .bold, design: .serif))
                        .italic()
                        .foregroundStyle(AppPalette.paperInk.opacity(0.88))

                    MarkerTitle(text: homeQuote, tint: AppPalette.paperHighlight)
                }
            }

            Spacer(minLength: 18)

            VStack(alignment: .trailing, spacing: 14) {
                if isPad {
                    HStack(spacing: 12) {
                        DashboardIconButton(icon: "gearshape") {
                            showsSettings = true
                        }

                        DashboardIconButton(icon: "note.text") {
                            showsNotesHome = true
                        }
                    }
                }

                MasteryRing(progress: viewModel.progressPercentage, size: isPad ? 210 : 126)
            }
        }
    }

    @ViewBuilder
    private func continueReviewPanel(isPad: Bool) -> some View {
        if let document = primaryWorkbenchDocument {
            let progress = viewModel.reviewWorkbenchProgress(for: document)
            let mastery = viewModel.workbenchMastery(for: document)
            let learnedSentenceCount = viewModel.workbenchStudiedSentenceCount(for: document)

            DashboardCard(cornerRadius: isPad ? 30 : 26, padding: isPad ? 28 : 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Continue Review")
                        .font(.system(size: isPad ? 24 : 18, weight: .bold, design: .serif))
                        .italic()
                        .foregroundStyle(AppPalette.paperInk)

                    Text(document.title)
                        .font(.system(size: isPad ? 17 : 15, weight: .medium, design: .serif))
                        .foregroundStyle(AppPalette.paperInk.opacity(0.88))
                        .lineLimit(2)

                    HStack(spacing: 28) {
                        reviewMetricColumn(title: "Mastery", value: "\(mastery)%")
                        reviewMetricColumn(title: "Last studied", value: relativeDateString(from: progress.lastVisitedAt))
                    }

                    HStack(spacing: 8) {
                        FocusPill(icon: "text.quote", text: "Learned \(learnedSentenceCount) sentences")
                        FocusPill(icon: "bookmark.fill", text: progress.lastAnchorLabel)
                    }

                    Button {
                        selectedWorkbenchDocument = document
                    } label: {
                        HStack {
                            Text("继续复盘")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RibbonButtonStyle())
                }
            }
        } else {
            DashboardCard(cornerRadius: isPad ? 30 : 26, padding: isPad ? 28 : 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Continue Review")
                        .font(.system(size: isPad ? 22 : 18, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.paperInk)

                    Text("导入英语资料后，这里会保留你的上次学习位置。")
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .foregroundStyle(AppPalette.paperMuted)
                }
            }
        }
    }

    private func todayTaskPanel(isPad: Bool) -> some View {
        DashboardCard(cornerRadius: isPad ? 30 : 26, padding: isPad ? 28 : 20) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Today's Tasks")
                    .font(.system(size: isPad ? 24 : 18, weight: .bold, design: .serif))
                    .italic()
                    .foregroundStyle(AppPalette.paperInk)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(todaysTasks, id: \.self) { task in
                        Text(task)
                            .font(.system(size: isPad ? 16 : 14, weight: .medium, design: .serif))
                            .foregroundStyle(AppPalette.paperInk.opacity(0.86))
                    }
                }

                Button {
                    if let primaryWorkbenchDocument {
                        selectedWorkbenchDocument = primaryWorkbenchDocument
                    } else {
                        showingReview = true
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("开始今日复盘")
                        Spacer()
                    }
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.white)
                }
                .buttonStyle(RibbonButtonStyle())
            }
        }
    }

    private func recentImportedMaterialsPanel(isPad: Bool) -> some View {
        DashboardCard(cornerRadius: isPad ? 28 : 24, padding: isPad ? 22 : 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("最近导入资料")
                    .font(.system(size: isPad ? 22 : 18, weight: .bold, design: .serif))
                    .foregroundStyle(AppPalette.paperInk)

                if recentImportedDocuments.isEmpty {
                    Text("导入资料后，即使远端解析失败或只生成本地骨架，也会显示在这里。")
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(AppPalette.paperMuted)
                } else {
                    VStack(spacing: 10) {
                        ForEach(recentImportedDocuments) { document in
                            Button {
                                selectedRecentDocument = document
                            } label: {
                                HomeRecentMaterialRow(document: document)
                                    .environmentObject(viewModel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var dashboardWeakPointsCard: some View {
        DashboardCard(cornerRadius: 26, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Weak Points:")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .italic()
                    .foregroundStyle(AppPalette.paperInk)

                if let chunk = viewModel.dailyProgress.highErrorChunks.first {
                    Text(chunk.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppPalette.paperInk)
                        .lineLimit(2)

                    Text(chunk.sourceTitle)
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .foregroundStyle(AppPalette.paperMuted)
                } else {
                    Text("暂时没有高错误率条目")
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(AppPalette.paperMuted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        }
    }

    private var dashboardStatisticsCard: some View {
        DashboardCard(cornerRadius: 26, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Study Statistics:")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .italic()
                    .foregroundStyle(AppPalette.paperInk)

                Text("本周学习 \(statItems[2].value)，正确率 \(statItems[3].value)")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(AppPalette.paperInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        }
    }

    private var dashboardCompactNotesCard: some View {
        DashboardCard(cornerRadius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("My Notes")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .italic()
                    .foregroundStyle(AppPalette.paperInk)

                Text("\(viewModel.notes.count)")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(AppPalette.paperInk)

                Button("打开笔记") {
                    showsNotesHome = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .foregroundStyle(Color(red: 161 / 255, green: 92 / 255, blue: 76 / 255))
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        }
    }

    private func reviewMetricColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .serif))
                .foregroundStyle(AppPalette.paperMuted)

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(AppPalette.paperInk)
        }
    }
}

private struct HomeDashboardView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let isPad: Bool
    let showsSidebar: Bool
    let availableWidth: CGFloat
    let safeAreaInsets: EdgeInsets
    let onImport: () -> Void
    let onCloudDiagnostics: () -> Void
    let onOpenDocument: (SourceDocument) -> Void
    let onContinueDocument: (SourceDocument) -> Void
    let onShowDiagnostics: (SourceDocument) -> Void
    let onOpenLibrary: () -> Void
    let onOpenNotes: () -> Void
    let onOpenReview: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HomeDashboardLayout(isPad: isPad, safeAreaInsets: safeAreaInsets) {
            if isPad {
                HStack(alignment: .top, spacing: 20) {
                    if showsSidebar {
                        HomeSidebarView(
                            onOpenLibrary: onOpenLibrary,
                            onOpenNotes: onOpenNotes,
                            onOpenReview: onOpenReview,
                            onOpenSettings: onOpenSettings
                        )
                        .frame(width: 184)
                    }

                    ScrollView(showsIndicators: false) {
                        mainColumn
                            .padding(.bottom, max(safeAreaInsets.bottom, 24))
                    }

                    ScrollView(showsIndicators: false) {
                        rightColumn
                            .padding(.bottom, max(safeAreaInsets.bottom, 24))
                    }
                    .frame(width: rightColumnWidth)
                }
                .padding(.horizontal, isCompactPadWorkbench ? 16 : 24)
                .padding(.top, max(safeAreaInsets.top, 20))
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        HomeWorkbenchHeader(
                            isPad: false,
                            onImport: onImport,
                            onCloudDiagnostics: onCloudDiagnostics
                        )
                        RecentMaterialsSection(
                            documents: Array(viewModel.recentImportedDocuments.prefix(6)),
                            isPad: false,
                            onOpenDocument: onOpenDocument,
                            onContinueDocument: onContinueDocument,
                            onShowDiagnostics: onShowDiagnostics,
                            onRetry: retry,
                            onShowAll: onOpenLibrary,
                            onImport: onImport
                        )
                        ImportProcessingQueueView(
                            documents: Array(viewModel.processingDocuments.prefix(3)),
                            onOpenDocument: onOpenDocument,
                            onRetry: retry
                        )
                        ContinueLearningSection(
                            document: viewModel.continueLearningDocument,
                            onContinue: onContinueDocument,
                            onImport: onImport
                        )
                        HomeStudySummaryCard()
                        AIServiceStatusCard(onCloudDiagnostics: onCloudDiagnostics)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, max(safeAreaInsets.top, 20))
                    .padding(.bottom, max(safeAreaInsets.bottom, 80))
                }
            }
        }
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            HomeWorkbenchHeader(
                isPad: true,
                onImport: onImport,
                onCloudDiagnostics: onCloudDiagnostics
            )
            RecentMaterialsSection(
                documents: Array(viewModel.recentImportedDocuments.prefix(8)),
                isPad: true,
                onOpenDocument: onOpenDocument,
                onContinueDocument: onContinueDocument,
                onShowDiagnostics: onShowDiagnostics,
                onRetry: retry,
                onShowAll: onOpenLibrary,
                onImport: onImport
            )
            ImportProcessingQueueView(
                documents: Array(viewModel.processingDocuments.prefix(4)),
                onOpenDocument: onOpenDocument,
                onRetry: retry
            )
            ContinueLearningSection(
                document: viewModel.continueLearningDocument,
                onContinue: onContinueDocument,
                onImport: onImport
            )
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            AIServiceStatusCard(onCloudDiagnostics: onCloudDiagnostics)
            HomeStudySummaryCard()
            HomeWeakPointsCard()
        }
    }

    private var isCompactPadWorkbench: Bool {
        availableWidth < 820
    }

    private var rightColumnWidth: CGFloat {
        isCompactPadWorkbench ? 252 : 304
    }

    private func retry(_ document: SourceDocument) {
        Task { @MainActor in
            await viewModel.retryMaterialProcessing(for: document)
        }
    }
}

private struct HomeDashboardLayout<Content: View>: View {
    let isPad: Bool
    let safeAreaInsets: EdgeInsets
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            ResourceWorkbenchBackground()
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ResourceWorkbenchBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 252 / 255, green: 248 / 255, blue: 251 / 255),
                    Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Rectangle()
                .fill(AppPalette.paperLine.opacity(0.08))
                .ignoresSafeArea()
        }
    }
}

private struct HomeSidebarView: View {
    let onOpenLibrary: () -> Void
    let onOpenNotes: () -> Void
    let onOpenReview: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        WorkbenchSurfaceCard(padding: 14) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Digital Archivist")
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.paperInk)

                    Text("资料工作台")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.paperMuted)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)

                sidebarItem(icon: "house.fill", title: "首页", selected: true, action: {})
                sidebarItem(icon: "books.vertical", title: "资料库", selected: false, action: onOpenLibrary)
                sidebarItem(icon: "note.text", title: "笔记", selected: false, action: onOpenNotes)
                sidebarItem(icon: "arrow.triangle.2.circlepath", title: "复习", selected: false, action: onOpenReview)

                Spacer(minLength: 20)

                sidebarItem(icon: "gearshape", title: "设置", selected: false, action: onOpenSettings)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func sidebarItem(
        icon: String,
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 15, weight: selected ? .bold : .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? AppPalette.primary : AppPalette.paperInk.opacity(0.78))
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? AppPalette.primary.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HomeWorkbenchHeader: View {
    @State private var searchText = ""

    let isPad: Bool
    let onImport: () -> Void
    let onCloudDiagnostics: () -> Void

    var body: some View {
        WorkbenchSurfaceCard(padding: isPad ? 22 : 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("资料工作台")
                            .font(.system(size: isPad ? 34 : 28, weight: .bold, design: .rounded))
                            .foregroundStyle(AppPalette.paperInk)

                        Text("整理、解析、复习你的英语学习资料")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppPalette.paperMuted)
                    }

                    Spacer(minLength: 12)

                    Button(action: onImport) {
                        Label("导入资料", systemImage: "plus")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .buttonStyle(WorkbenchPrimaryButtonStyle())
                }

                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppPalette.paperMuted)
                        TextField("搜索资料、笔记、生词", text: $searchText)
                            .font(.system(size: 15, weight: .medium))
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.76))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppPalette.paperLine.opacity(0.45), lineWidth: 1)
                            )
                    )

                    Button(action: onCloudDiagnostics) {
                        Label("云端检测", systemImage: "waveform.path.ecg")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(WorkbenchSecondaryButtonStyle())
                }
            }
        }
    }
}

private struct ImportProcessingQueueView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let documents: [SourceDocument]
    let onOpenDocument: (SourceDocument) -> Void
    let onRetry: (SourceDocument) -> Void

    var body: some View {
        if !documents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("正在处理")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.paperInk)

                VStack(spacing: 10) {
                    ForEach(documents) { document in
                        ImportProcessingCard(
                            document: document,
                            onOpen: { onOpenDocument(document) },
                            onRetry: { onRetry(document) }
                        )
                        .environmentObject(viewModel)
                    }
                }
            }
        }
    }
}

private struct ImportProcessingCard: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let document: SourceDocument
    let onOpen: () -> Void
    let onRetry: () -> Void

    private var liveDocument: SourceDocument {
        viewModel.sourceDocuments.first(where: { $0.id == document.id }) ?? document
    }

    private var stage: StructuredLoadingStage {
        viewModel.structuredSourceStage(for: liveDocument)
    }

    private var display: MaterialDisplayInfo {
        MaterialDisplayMapper.displayInfo(for: liveDocument, viewModel: viewModel)
    }

    var body: some View {
        WorkbenchSurfaceCard(padding: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: liveDocument.documentType.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(display.status.tint)
                    .frame(width: 36, height: 36)
                    .background(display.status.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(liveDocument.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppPalette.paperInk)
                        .lineLimit(1)

                    ProgressView(value: display.progress)
                        .tint(display.status.tint)

                    Text(stage.displayName == "等待中" ? display.description : stage.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppPalette.paperMuted)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button(display.status == .failed || display.status == .requestFailed ? "重试解析" : "打开") {
                    if display.status == .failed || display.status == .requestFailed {
                        onRetry()
                    } else {
                        onOpen()
                    }
                }
                .buttonStyle(WorkbenchSecondaryButtonStyle())
            }
        }
    }
}

private struct RecentMaterialsSection: View {
    let documents: [SourceDocument]
    let isPad: Bool
    let onOpenDocument: (SourceDocument) -> Void
    let onContinueDocument: (SourceDocument) -> Void
    let onShowDiagnostics: (SourceDocument) -> Void
    let onRetry: (SourceDocument) -> Void
    let onShowAll: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("最近导入资料")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.paperInk)

                Spacer()

                Button("查看全部", action: onShowAll)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppPalette.primary)
            }

            if documents.isEmpty {
                WorkbenchEmptyStateCard(onImport: onImport)
            } else if isPad {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 14
                ) {
                    cards
                }
            } else {
                VStack(spacing: 12) {
                    cards
                }
            }
        }
    }

    @ViewBuilder
    private var cards: some View {
        ForEach(documents) { document in
            RecentMaterialCard(
                document: document,
                onOpenDocument: { onOpenDocument(document) },
                onContinueDocument: { onContinueDocument(document) },
                onShowDiagnostics: { onShowDiagnostics(document) },
                onRetry: { onRetry(document) }
            )
        }
    }
}

private struct RecentMaterialCard: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let document: SourceDocument
    let onOpenDocument: () -> Void
    let onContinueDocument: () -> Void
    let onShowDiagnostics: () -> Void
    let onRetry: () -> Void

    private var liveDocument: SourceDocument {
        viewModel.sourceDocuments.first(where: { $0.id == document.id }) ?? document
    }

    private var display: MaterialDisplayInfo {
        MaterialDisplayMapper.displayInfo(for: liveDocument, viewModel: viewModel)
    }

    private var progress: ReviewWorkbenchProgress {
        viewModel.reviewWorkbenchProgress(for: liveDocument)
    }

    var body: some View {
        WorkbenchSurfaceCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: liveDocument.documentType.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(display.status.tint)
                        .frame(width: 40, height: 40)
                        .background(display.status.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 7) {
                        Text(liveDocument.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppPalette.paperInk)
                            .lineLimit(2)

                        Text(display.metadataLine)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppPalette.paperMuted)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)
                }

                HStack(spacing: 8) {
                    MaterialModeBadge(title: display.materialModeTitle)
                    MaterialParseStatusBadge(status: display.status)
                    if display.shouldShowDocumentParseBadge {
                        MaterialParseStatusBadge(status: display.documentParseStatus)
                    }
                }

                ProgressView(value: display.progress)
                    .tint(display.status.tint)

                Text(display.description)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppPalette.paperInk.opacity(0.74))
                    .lineLimit(3)

                if !progress.lastAnchorLabel.isEmpty {
                    Text("当前：\(progress.lastAnchorLabel)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.paperMuted)
                }

                HStack(spacing: 10) {
                    Button(display.primaryActionTitle) {
                        switch display.primaryAction {
                        case .open, .showStructure:
                            onOpenDocument()
                        case .continueLearning:
                            onContinueDocument()
                        case .retry:
                            onRetry()
                        }
                    }
                    .buttonStyle(WorkbenchPrimaryButtonStyle())

                    Button("查看诊断", action: onShowDiagnostics)
                        .buttonStyle(WorkbenchSecondaryButtonStyle())
                }
            }
        }
    }
}

private struct ContinueLearningSection: View {
    @EnvironmentObject private var viewModel: AppViewModel

    let document: SourceDocument?
    let onContinue: (SourceDocument) -> Void
    let onImport: () -> Void

    var body: some View {
        WorkbenchSurfaceCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("继续学习")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.paperInk)

                if let document {
                    let progress = viewModel.reviewWorkbenchProgress(for: document)
                    Text(document.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppPalette.paperInk)
                        .lineLimit(2)
                    Text("上次位置：\(progress.lastAnchorLabel)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppPalette.paperMuted)
                    Button("继续学习") {
                        onContinue(document)
                    }
                    .buttonStyle(WorkbenchPrimaryButtonStyle())
                } else {
                    Text("导入 PDF、图片或文本，开始建立你的英语学习资料库。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppPalette.paperMuted)
                    Button("导入资料", action: onImport)
                        .buttonStyle(WorkbenchPrimaryButtonStyle())
                }
            }
        }
    }
}

private struct AIServiceStatusCard: View {
    let onCloudDiagnostics: () -> Void

    private var summary: HomeAIServiceSummary {
        HomeAIServiceSummary.current()
    }

    var body: some View {
        WorkbenchSurfaceCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("AI 状态")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.paperInk)
                    Spacer()
                    Button("云端检测", action: onCloudDiagnostics)
                        .buttonStyle(WorkbenchSecondaryButtonStyle())
                }

                aiStatusRow(title: "句子精讲", status: summary.sentenceExplain)
                aiStatusRow(title: "全文分析", status: summary.passageAnalysis)
                aiStatusRow(title: "文档云解析", status: summary.documentParse)

                Text("当前模式：\(summary.modeText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppPalette.paperMuted)

                if let latestError = summary.latestError {
                    Text(latestError)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppPalette.amber)
                        .lineLimit(2)
                }
            }
        }
    }

    private func aiStatusRow(title: String, status: HomeServiceStatus) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(status.tint)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppPalette.paperInk)
            Spacer()
            Text(status.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(status.tint)
        }
    }
}

private struct HomeStudySummaryCard: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        WorkbenchSurfaceCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("今日复习")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.paperInk)

                HStack(spacing: 16) {
                    summaryMetric(title: "待复习", value: "\(viewModel.dailyProgress.pendingReviewsCount)")
                    summaryMetric(title: "已完成", value: "\(viewModel.dailyProgress.completedToday)")
                    summaryMetric(title: "正确率", value: "\(Int(viewModel.dailyProgress.weeklyAccuracy * 100))%")
                }
            }
        }
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.paperInk)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppPalette.paperMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeWeakPointsCard: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        WorkbenchSurfaceCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("薄弱点")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.paperInk)

                if let chunk = viewModel.dailyProgress.highErrorChunks.first {
                    Text(chunk.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppPalette.paperInk)
                        .lineLimit(2)
                    Text(chunk.sourceTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppPalette.paperMuted)
                } else {
                    Text("暂时没有高错误率条目")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppPalette.paperMuted)
                }
            }
        }
    }
}

private struct WorkbenchEmptyStateCard: View {
    let onImport: () -> Void

    var body: some View {
        WorkbenchSurfaceCard(padding: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("还没有导入资料")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppPalette.paperInk)
                Text("导入 PDF、图片或文本，开始建立你的英语学习资料库。")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppPalette.paperMuted)
                Button("导入资料", action: onImport)
                    .buttonStyle(WorkbenchPrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MaterialModeBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppPalette.paperInk.opacity(0.78))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                Capsule(style: .continuous)
                    .fill(AppPalette.paperLine.opacity(0.22))
            )
    }
}

private struct MaterialParseStatusBadge: View {
    let status: MaterialParseStatus

    var body: some View {
        Text(status.title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                Capsule(style: .continuous)
                    .fill(status.tint.opacity(0.12))
            )
    }
}

private struct WorkbenchSurfaceCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppPalette.paperLine.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
            )
    }
}

private struct WorkbenchPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppPalette.primary.opacity(configuration.isPressed ? 0.82 : 1))
            )
    }
}

private struct WorkbenchSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppPalette.primary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.54 : 0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppPalette.primary.opacity(0.16), lineWidth: 1)
                    )
            )
    }
}

private struct MaterialDisplayInfo {
    let materialModeTitle: String
    let metadataLine: String
    let status: MaterialParseStatus
    let documentParseStatus: MaterialParseStatus
    let shouldShowDocumentParseBadge: Bool
    let description: String
    let progress: Double
    let primaryAction: MaterialPrimaryAction

    var primaryActionTitle: String {
        switch primaryAction {
        case .continueLearning:
            return "继续学习"
        case .showStructure:
            return "查看结构"
        case .retry:
            return "重试解析"
        case .open:
            return "打开资料"
        }
    }
}

private enum MaterialPrimaryAction {
    case continueLearning
    case showStructure
    case retry
    case open
}

private enum MaterialParseStatus: Equatable {
    case remoteAI
    case remoteParsed
    case localSkeleton
    case cached
    case requestFailed
    case discardedMismatch
    case parsing
    case unconfigured
    case failed
    case imported
    case pending
    case insufficientText

    var title: String {
        switch self {
        case .remoteAI: return "AI 已分析"
        case .remoteParsed: return "云端解析完成"
        case .localSkeleton: return "本地骨架"
        case .cached: return "缓存结果"
        case .requestFailed: return "请求失败"
        case .discardedMismatch: return "已丢弃旧结果"
        case .parsing: return "解析中"
        case .unconfigured: return "文档解析未配置"
        case .failed: return "解析失败"
        case .imported: return "已导入"
        case .pending: return "等待处理"
        case .insufficientText: return "正文不足"
        }
    }

    var tint: Color {
        switch self {
        case .remoteAI, .remoteParsed, .cached:
            return AppPalette.primary
        case .localSkeleton, .unconfigured, .pending, .imported, .insufficientText:
            return AppPalette.amber
        case .requestFailed, .failed, .discardedMismatch:
            return Color(red: 180 / 255, green: 74 / 255, blue: 58 / 255)
        case .parsing:
            return AppPalette.cyan
        }
    }
}

private enum MaterialDisplayMapper {
    static func displayInfo(
        for document: SourceDocument,
        viewModel: AppViewModel
    ) -> MaterialDisplayInfo {
        let bundle = viewModel.structuredSource(for: document)
        let parseInfo = viewModel.parseSessionInfo(for: document)
        let stage = viewModel.structuredSourceStage(for: document)
        let mode = bundle?.passageAnalysisDiagnostics?.materialMode
        let status = parseStatus(document: document, bundle: bundle, parseInfo: parseInfo, stage: stage)
        let documentParseStatus = documentParseStatus(parseInfo: parseInfo)
        let shouldShowDocumentParseBadge = documentParseStatus == .unconfigured
            || (parseInfo?.ppAttempted == true && parseInfo?.ppSucceeded == false)
        let paragraphCount = parseInfo?.paragraphCount
            ?? bundle?.zoningSummary.passageParagraphCount
            ?? document.chunkCount
        let sentenceCount = parseInfo?.sentenceCount
            ?? bundle?.source.sentenceCount
            ?? 0
        let materialTitle = materialModeTitle(
            mode: mode,
            fallbackStatus: status,
            paragraphCount: paragraphCount,
            sentenceCount: sentenceCount
        )
        let typeAndCount = [
            materialTitle,
            "\(max(document.pageCount, 0)) 页",
            paragraphCount > 0 ? "\(paragraphCount) 段" : nil,
            sentenceCount > 0 ? "\(sentenceCount) 句" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        return MaterialDisplayInfo(
            materialModeTitle: materialTitle,
            metadataLine: typeAndCount,
            status: status,
            documentParseStatus: documentParseStatus,
            shouldShowDocumentParseBadge: shouldShowDocumentParseBadge,
            description: description(
                document: document,
                bundle: bundle,
                parseInfo: parseInfo,
                stage: stage,
                status: status,
                mode: mode
            ),
            progress: progress(document: document, bundle: bundle, status: status),
            primaryAction: primaryAction(document: document, bundle: bundle, status: status)
        )
    }

    static func materialModeTitle(
        mode: MaterialAnalysisMode?,
        fallbackStatus: MaterialParseStatus = .pending,
        paragraphCount: Int = 0,
        sentenceCount: Int = 0
    ) -> String {
        guard let mode else {
            if sentenceCount >= 5 {
                return "英文正文"
            }
            if paragraphCount > 0 && (fallbackStatus == .localSkeleton || fallbackStatus == .requestFailed) {
                return "学习资料"
            }
            switch fallbackStatus {
            case .failed:
                return "未识别资料"
            case .insufficientText:
                return "正文不足"
            default:
                return "等待识别"
            }
        }

        switch mode {
        case .passageReading:
            return "英文正文"
        case .learningMaterial:
            return "学习讲义"
        case .vocabularyNotes:
            return "词汇注释"
        case .questionSheet:
            return "题目练习"
        case .auxiliaryOnlyMap:
            return "辅助资料"
        case .insufficientText:
            return "正文不足"
        }
    }

    static func parseStatus(
        document: SourceDocument,
        bundle: StructuredSourceBundle?,
        parseInfo: ParseSessionInfo?,
        stage: StructuredLoadingStage
    ) -> MaterialParseStatus {
        if document.processingStatus == .parsing || stage == .extracting || stage == .uploading || stage == .parsing || stage == .normalizing || stage == .aiEnriching {
            return .parsing
        }

        if document.processingStatus == .imported {
            return .imported
        }

        if bundle?.passageAnalysisDiagnostics?.materialMode == .insufficientText {
            return .insufficientText
        }

        if parseInfo?.skippedBecauseUnconfigured == true {
            return .unconfigured
        }

        if document.processingStatus == .failed || stage == .failed || stage == .timedOut {
            return bundle == nil ? .failed : .requestFailed
        }

        if bundle?.hasProfessorAnalysis == true {
            return .remoteAI
        }

        if bundle != nil && parseInfo?.ppSucceeded == true {
            return .remoteParsed
        }

        if bundle != nil || parseInfo?.fallbackUsed == true || stage == .localFallbackReady || stage == .partialReady || stage == .fallbackLegacy {
            return .localSkeleton
        }

        return .pending
    }

    static func documentParseStatus(parseInfo: ParseSessionInfo?) -> MaterialParseStatus {
        guard let parseInfo else {
            return DocumentParseEndpointConfig.isConfigured ? .pending : .unconfigured
        }

        if parseInfo.skippedBecauseUnconfigured {
            return .unconfigured
        }
        if parseInfo.ppSucceeded {
            return .remoteParsed
        }
        if parseInfo.ppAttempted {
            return .requestFailed
        }
        return .pending
    }

    private static func description(
        document: SourceDocument,
        bundle: StructuredSourceBundle?,
        parseInfo: ParseSessionInfo?,
        stage: StructuredLoadingStage,
        status: MaterialParseStatus,
        mode: MaterialAnalysisMode?
    ) -> String {
        switch status {
        case .remoteAI:
            return "AI 结果已生成，可继续学习。"
        case .remoteParsed:
            return "文档云解析已完成，AI 全文分析可继续获取。"
        case .localSkeleton:
            if let mode, mode != .passageReading {
                return mode.fallbackMessage
            }
            return "远端 AI 分析尚未成功获取，当前保留本地结构骨架。"
        case .requestFailed:
            return document.lastProcessingError
                ?? parseInfo?.fallbackReason
                ?? "AI 请求失败，已保留本地结构。"
        case .unconfigured:
            return "文档解析云接口未配置，已使用本地解析。"
        case .failed:
            return document.lastProcessingError ?? "解析失败，可查看诊断后重试。"
        case .parsing:
            return stage.displayName
        case .imported:
            return "资料已导入，正在等待解析。"
        case .pending:
            return "等待识别资料结构。"
        case .insufficientText:
            return "正文不足，已生成学习资料结构。"
        case .cached:
            return "当前展示缓存结果。"
        case .discardedMismatch:
            return "旧请求结果已丢弃，不会覆盖当前资料。"
        }
    }

    private static func progress(
        document: SourceDocument,
        bundle: StructuredSourceBundle?,
        status: MaterialParseStatus
    ) -> Double {
        switch status {
        case .remoteAI, .remoteParsed, .cached, .localSkeleton, .insufficientText:
            return 1
        case .parsing:
            return 0.56
        case .imported, .pending:
            return 0.18
        case .requestFailed:
            return bundle == nil ? 0.26 : 1
        case .unconfigured:
            return bundle == nil ? 0.3 : 1
        case .failed, .discardedMismatch:
            return 0.12
        }
    }

    private static func primaryAction(
        document: SourceDocument,
        bundle: StructuredSourceBundle?,
        status: MaterialParseStatus
    ) -> MaterialPrimaryAction {
        switch status {
        case .remoteAI, .remoteParsed:
            return .continueLearning
        case .localSkeleton, .unconfigured, .insufficientText, .cached:
            return .showStructure
        case .requestFailed, .failed:
            return .retry
        case .parsing, .imported, .pending, .discardedMismatch:
            return bundle == nil ? .open : .showStructure
        }
    }
}

private struct HomeAIServiceSummary {
    let sentenceExplain: HomeServiceStatus
    let passageAnalysis: HomeServiceStatus
    let documentParse: HomeServiceStatus
    let modeText: String
    let latestError: String?

    static func current() -> HomeAIServiceSummary {
        let events = TextPipelineDiagnostics.recentEvents(limit: 200)
        let sentenceEvent = events.last { $0.stage == "AI" && ($0.message.contains("[AI][SentenceExplain]") || $0.message.contains("[AI][Sentence]")) }
        let passageEvent = events.last { $0.stage == "AI" && $0.message.contains("[AI][PassageMap]") }
        let parseEvent = events.last { event in
            guard event.stage == "PP" else { return false }
            let message = event.message
            return message.contains("[PP][Route]")
                || message.contains("parse request success")
                || message.contains("remote document parse failed")
                || message.contains("PP-StructureV3 解析失败")
                || message.contains("fallback to legacy")
                || message.contains("fallback to local")
                || message.contains("fallback → legacy")
                || message.contains("上传失败")
        }

        let documentParseStatus: HomeServiceStatus
        if !DocumentParseEndpointConfig.isConfigured {
            documentParseStatus = .unconfigured
        } else if parseEvent?.message.contains("parse request success") == true {
            documentParseStatus = .available
        } else if parseEvent.map(isDocumentParseFailureEvent) == true {
            documentParseStatus = .failed
        } else {
            documentParseStatus = .configured
        }

        let sentenceStatus = serviceStatus(from: sentenceEvent, defaultConfigured: !AIBackendConfig.resolvedBaseURL.isEmpty)
        let passageStatus = serviceStatus(from: passageEvent, defaultConfigured: !AIBackendConfig.resolvedBaseURL.isEmpty)

        let latestError = [sentenceEvent, passageEvent, parseEvent]
            .compactMap { event -> String? in
                guard let event, event.severity == .warning || event.severity == .error else { return nil }
                if let errorCode = DiagnosticsEventParserForHome.value("error_code", in: event.message), errorCode != "nil" {
                    return "最近错误：\(errorCode)"
                }
                if event.stage == "PP" {
                    return "文档云解析请求失败，已使用本地解析。"
                }
                if event.message.contains("[AI][SentenceExplain]") {
                    return "句子精讲请求失败，已保留本地结构。"
                }
                if event.message.contains("[AI][PassageMap]") {
                    return "全文分析请求失败，已保留本地结构。"
                }
                return "云端请求失败，请查看诊断。"
            }
            .last

        return HomeAIServiceSummary(
            sentenceExplain: sentenceStatus,
            passageAnalysis: passageStatus,
            documentParse: documentParseStatus,
            modeText: documentParseStatus == .available ? "云端文档解析 + AI 精讲" : "本地解析 + AI 精讲",
            latestError: latestError
        )
    }

    nonisolated private static func isDocumentParseFailureEvent(_ event: TextPipelineDiagnostics.PipelineEvent) -> Bool {
        event.severity == .error
            || event.message.contains("failed")
            || event.message.contains("解析失败")
            || event.message.contains("fallback")
            || event.message.contains("上传失败")
    }

    private static func serviceStatus(
        from event: TextPipelineDiagnostics.PipelineEvent?,
        defaultConfigured: Bool
    ) -> HomeServiceStatus {
        guard defaultConfigured else { return .unconfigured }
        guard let event else { return .configured }
        if event.message.contains("success") || event.message.contains("cache hit") {
            return .available
        }
        if event.message.contains("local fallback") || event.message.contains("requestFailed") || event.severity == .warning || event.severity == .error {
            return .failed
        }
        return .configured
    }
}

private enum HomeServiceStatus: Equatable {
    case available
    case failed
    case unconfigured
    case configured

    var title: String {
        switch self {
        case .available: return "可用"
        case .failed: return "请求失败"
        case .unconfigured: return "未配置"
        case .configured: return "已配置"
        }
    }

    var tint: Color {
        switch self {
        case .available: return Color(red: 38 / 255, green: 139 / 255, blue: 91 / 255)
        case .failed: return Color(red: 180 / 255, green: 74 / 255, blue: 58 / 255)
        case .unconfigured: return AppPalette.amber
        case .configured: return AppPalette.primary
        }
    }
}

private enum DiagnosticsEventParserForHome {
    static func value(_ key: String, in message: String) -> String? {
        message
            .split(separator: " ")
            .compactMap { chunk -> (String, String)? in
                let parts = chunk.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (parts[0], parts[1])
            }
            .first(where: { $0.0 == key })?
            .1
    }
}

private struct HomeMaterialDiagnosticsSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    let document: SourceDocument

    private var liveDocument: SourceDocument {
        viewModel.sourceDocuments.first(where: { $0.id == document.id }) ?? document
    }

    private var display: MaterialDisplayInfo {
        MaterialDisplayMapper.displayInfo(for: liveDocument, viewModel: viewModel)
    }

    private var parseInfo: ParseSessionInfo? {
        viewModel.parseSessionInfo(for: liveDocument)
    }

    private var latestAIEvent: TextPipelineDiagnostics.PipelineEvent? {
        TextPipelineDiagnostics.recentEvents(limit: 200)
            .last {
                $0.stage == "AI"
                    && $0.message.contains(liveDocument.id.uuidString)
                    && ($0.message.contains("[AI][SentenceExplain]") || $0.message.contains("[AI][PassageMap]"))
            }
    }

    var body: some View {
        NavigationView {
            List {
                Section("Build") {
                    HomeDiagnosticRow(label: "gitSHA", value: RuntimeBuildFingerprint.current.gitSHA)
                    HomeDiagnosticRow(label: "branch", value: RuntimeBuildFingerprint.current.branchName)
                    HomeDiagnosticRow(label: "buildTime", value: RuntimeBuildFingerprint.current.buildTime)
                }

                Section("资料状态") {
                    HomeDiagnosticRow(label: "parseStatus", value: display.status.title)
                    HomeDiagnosticRow(label: "materialMode", value: display.materialModeTitle)
                    HomeDiagnosticRow(label: "currentResultSource", value: display.status.title)
                    HomeDiagnosticRow(label: "documentParseEndpointConfigured", value: parseInfo?.documentParseEndpointConfigured == true ? "true" : "false")
                    HomeDiagnosticRow(label: "documentParseRemoteStatus", value: parseInfo?.documentParseRemoteStatus ?? "nil")
                    HomeDiagnosticRow(label: "fallbackReason", value: parseInfo?.fallbackReason ?? liveDocument.lastProcessingError ?? "nil")
                }

                Section("AI 请求") {
                    HomeDiagnosticRow(label: "cloudExplainAttempted", value: latestAIEvent?.message.contains("[AI][SentenceExplain]") == true ? "true" : "false")
                    HomeDiagnosticRow(label: "cloudPassageAttempted", value: latestAIEvent?.message.contains("[AI][PassageMap]") == true ? "true" : "false")
                    HomeDiagnosticRow(label: "lastErrorCode", value: latestValue("error_code") ?? "nil")
                    HomeDiagnosticRow(label: "requestID", value: latestValue("request_id") ?? latestValue("client_request_id") ?? "nil")
                }
            }
            .navigationTitle("资料诊断")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func latestValue(_ key: String) -> String? {
        guard let message = latestAIEvent?.message else { return nil }
        return DiagnosticsEventParserForHome.value(key, in: message)
    }
}

private struct HomeBuildFingerprintCard: View {
    let fingerprint: RuntimeBuildFingerprint

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeDiagnosticRow(label: "gitSHA", value: fingerprint.gitSHA)
            HomeDiagnosticRow(label: "branch", value: fingerprint.branchName)
            HomeDiagnosticRow(label: "buildTime", value: fingerprint.buildTime)
            HomeDiagnosticRow(label: "AI backend", value: fingerprint.aiBackendBaseURL)
            HomeDiagnosticRow(label: "document parser", value: fingerprint.documentParseEndpointStatus)
        }
    }
}

private struct HomeDiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 156, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private struct HomeAmbientGlow: View {
    private var glowScale: CGFloat {
        AppPerformance.prefersReducedEffects ? 0.72 : 1
    }

    private var blurScale: CGFloat {
        AppPerformance.prefersReducedEffects ? 0.48 : 1
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.34))
                .frame(width: 250 * glowScale, height: 250 * glowScale)
                .blur(radius: 76 * blurScale)
                .offset(x: 104, y: -64)

            Circle()
                .fill(AppPalette.paperHighlight.opacity(0.3))
                .frame(width: 224 * glowScale, height: 224 * glowScale)
                .blur(radius: 92 * blurScale)
                .offset(x: 138, y: 92)

            Circle()
                .fill(AppPalette.paperTapeBlue.opacity(0.18))
                .frame(width: 292 * glowScale, height: 292 * glowScale)
                .blur(radius: 102 * blurScale)
                .offset(x: -18, y: 244)

            Circle()
                .fill(AppPalette.paperHighlightMint.opacity(0.22))
                .frame(width: 214 * glowScale, height: 214 * glowScale)
                .blur(radius: 90 * blurScale)
                .offset(x: -108, y: 134)

            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(Color.white.opacity(0.2))
                .frame(width: 280 * glowScale, height: 126 * glowScale)
                .blur(radius: 64 * blurScale)
                .offset(x: 10, y: 166)
        }
        .allowsHitTesting(false)
    }
}

struct HomeStatItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let value: String
    let tint: Color
}

private struct DashboardRailItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .serif))
            }
            .foregroundStyle(isSelected ? AppPalette.paperInk : AppPalette.paperMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.68) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(isSelected ? Color.white.opacity(0.9) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct MasteryRing: View {
    let progress: Double
    var size: CGFloat = 100

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppPalette.paperInk.opacity(0.18), lineWidth: size * 0.08)

            Circle()
                .trim(from: 0, to: max(min(progress, 1), 0.05))
                .stroke(
                    LinearGradient(
                        colors: [AppPalette.paperInk.opacity(0.72), AppPalette.fabricNavy],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: AppPalette.fabricNavy.opacity(0.12), radius: size * 0.08)

            VStack(spacing: size > 160 ? 6 : 2) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: size * 0.22, weight: .bold, design: .serif))
                    .foregroundStyle(AppPalette.paperInk)

                Text("Mastery")
                    .font(.system(size: size * 0.11, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(AppPalette.paperInk.opacity(0.88))
            }
        }
        .frame(width: size, height: size)
        .padding(size * 0.08)
        .background(
            Circle()
                .fill(Color.white.opacity(0.45))
                .overlay(Circle().stroke(AppPalette.paperInk.opacity(0.08), lineWidth: 1))
        )
    }
}

struct StartReviewGlassButton: View {
    let action: () -> Void

    private var glowScale: CGFloat {
        AppPerformance.prefersReducedEffects ? 0.7 : 1
    }

    private var blurScale: CGFloat {
        AppPerformance.prefersReducedEffects ? 0.45 : 1
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Text("开始今天的复习")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppPalette.softText)

                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 64, height: 64)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.72), AppPalette.mint.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppPalette.deepNavy)
                        .offset(x: 2)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity, minHeight: 126)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay {
                        if !AppPerformance.prefersReducedEffects {
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .opacity(0.3)
                        }
                    }
                    .overlay {
                        ZStack {
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(Color.white.opacity(0.24), lineWidth: 1.2)

                            Circle()
                                .fill(AppPalette.cyan.opacity(0.68))
                                .frame(width: 188 * glowScale, height: 188 * glowScale)
                                .blur(radius: 52 * blurScale)
                                .offset(x: 8, y: 12)

                            Circle()
                                .fill(AppPalette.primary.opacity(0.48))
                                .frame(width: 146 * glowScale, height: 146 * glowScale)
                                .blur(radius: 46 * blurScale)
                                .offset(x: -42, y: 20)

                            Circle()
                                .fill(AppPalette.mint.opacity(0.46))
                                .frame(width: 146 * glowScale, height: 146 * glowScale)
                                .blur(radius: 48 * blurScale)
                                .offset(x: 82, y: 18)

                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.3), .clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(height: 58)
                                .offset(y: -28)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    }
                    .shadow(color: AppPalette.cyan.opacity(0.18), radius: AppPerformance.prefersReducedEffects ? 12 : 24, y: AppPerformance.prefersReducedEffects ? 6 : 12)
            )
        }
        .buttonStyle(.plain)
    }
}

struct WeakPointCard: View {
    let chunk: KnowledgeChunkSummary

    var body: some View {
        GlassPanel(tone: .dark, cornerRadius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                FrostedOrb(icon: "doc.text.fill", size: 34, tone: .dark)

                Text(chunk.title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppPalette.softText)
                    .lineLimit(2)

                VStack(alignment: .leading, spacing: 8) {
                    Text(chunk.sourceTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppPalette.softMutedText)
                        .lineLimit(1)

                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 6)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.95), AppPalette.amber],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: min(CGFloat(chunk.errorFrequency) * 28, 92), height: 6)
                        }
                }
            }
            .frame(width: 166, alignment: .leading)
        }
    }
}

struct HomeStatCard: View {
    let item: HomeStatItem

    var body: some View {
        GlassPanel(tone: .dark, cornerRadius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                FrostedOrb(icon: item.icon, size: 34, tone: .dark)

                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppPalette.softMutedText)

                Text(item.value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.softText)
            }
            .frame(width: 162, alignment: .leading)
        }
    }
}

struct FocusPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .serif))
        }
        .foregroundStyle(AppPalette.paperInk.opacity(0.82))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.78))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

private struct HomeRecentMaterialRow: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let document: SourceDocument

    private var liveDocument: SourceDocument {
        viewModel.sourceDocuments.first(where: { $0.id == document.id }) ?? document
    }

    private var parseInfo: ParseSessionInfo? {
        viewModel.parseSessionInfo(for: liveDocument)
    }

    private var display: MaterialDisplayInfo {
        MaterialDisplayMapper.displayInfo(for: liveDocument, viewModel: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: liveDocument.documentType.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppPalette.paperInk.opacity(0.72))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(liveDocument.title)
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(AppPalette.paperInk)
                        .lineLimit(2)

                    Text("\(liveDocument.documentType.displayName) · \(liveDocument.pageCount) 页 · \(display.status.title)")
                        .font(.system(size: 12, weight: .medium, design: .serif))
                        .foregroundStyle(AppPalette.paperMuted)
                }

                Spacer(minLength: 8)

                Text(relativeImportDate)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppPalette.paperMuted)
            }

            HStack(spacing: 8) {
                MaterialModeBadge(title: display.materialModeTitle)
                MaterialParseStatusBadge(status: display.status)
            }
        }
        .padding(.vertical, 8)
    }

    private var relativeImportDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: liveDocument.importDate, relativeTo: Date())
    }
}

private struct ReviewWorkbenchEntryCard: View {
    let document: SourceDocument
    let progress: ReviewWorkbenchProgress
    let masteryValue: Int
    let learnedSentenceCount: Int
    let action: () -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var lastStudyText: String {
        Self.relativeFormatter.localizedString(for: progress.lastVisitedAt, relativeTo: Date())
    }

    var body: some View {
        GlassPanel(tone: .dark, cornerRadius: 28, padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    FrostedOrb(icon: "character.book.closed.fill", size: 42, tone: .dark)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(document.title)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppPalette.softText)
                            .lineLimit(2)

                        Text("上次学习 \(lastStudyText)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppPalette.softMutedText)
                    }

                    Spacer(minLength: 10)

                    MetricCapsule(label: "\(masteryValue)% 掌握度", tone: .dark, tint: AppPalette.mint)
                }

                HStack(spacing: 10) {
                    FocusPill(icon: "text.quote", text: "已学 \(learnedSentenceCount) 句")
                    FocusPill(icon: "bookmark.fill", text: progress.lastAnchorLabel)
                }

                Button(action: action) {
                    HStack(spacing: 10) {
                        Text("继续复盘")
                            .font(.system(size: 15, weight: .bold, design: .rounded))

                        Spacer()

                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(AppPalette.deepNavy)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [AppPalette.primary, AppPalette.cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#if DEBUG
struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(AppViewModel())
    }
}
#endif
