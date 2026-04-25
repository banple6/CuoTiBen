import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showingReview = false
    @State private var selectedWorkbenchDocument: SourceDocument?
    @State private var selectedWorkbenchAnchor: SourceAnchor?
    @State private var selectedRecentDocument: SourceDocument?
    @State private var showsSettings = false
    @State private var showsNotesHome = false

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
            ZStack {
                PaperCanvasBackground()
                HomeAmbientGlow()

                if usesPadDashboard {
                    HStack(spacing: 26) {
                        dashboardSideRail

                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 24) {
                                dashboardHero(isPad: true)

                                HStack(alignment: .top, spacing: 22) {
                                    continueReviewPanel(isPad: true)
                                        .frame(maxWidth: .infinity)

                                    todayTaskPanel(isPad: true)
                                        .frame(maxWidth: .infinity)
                                }

                                recentImportedMaterialsPanel(isPad: true)

                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: 18),
                                        GridItem(.flexible(), spacing: 18),
                                        GridItem(.flexible(minimum: 120), spacing: 18)
                                    ],
                                    spacing: 18
                                ) {
                                    dashboardWeakPointsCard
                                    dashboardStatisticsCard
                                    dashboardCompactNotesCard
                                }
                            }
                            .padding(.top, max(proxy.safeAreaInsets.top, 24))
                            .padding(.bottom, max(proxy.safeAreaInsets.bottom, 28))
                        }
                    }
                    .padding(.horizontal, 28)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            dashboardHero(isPad: false)
                            recentImportedMaterialsPanel(isPad: false)
                            continueReviewPanel(isPad: false)
                            todayTaskPanel(isPad: false)
                            dashboardWeakPointsCard
                            dashboardStatisticsCard
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, max(proxy.safeAreaInsets.top, 24))
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom, 32))
                    }
                }
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

    private var materialMode: String {
        viewModel.structuredSource(for: liveDocument)?
            .passageAnalysisDiagnostics?
            .materialMode
            .rawValue ?? "pending"
    }

    private var statusText: String {
        if parseInfo?.skippedBecauseUnconfigured == true {
            return "文档解析接口未配置 · 本地骨架"
        }
        if parseInfo?.fallbackUsed == true {
            return "本地骨架"
        }
        switch liveDocument.processingStatus {
        case .imported: return "已导入"
        case .parsing: return "云端解析中"
        case .ready: return "AI 已分析"
        case .failed: return "请求失败，可重试"
        }
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

                    Text("\(liveDocument.documentType.displayName) · \(liveDocument.pageCount) 页 · \(statusText)")
                        .font(.system(size: 12, weight: .medium, design: .serif))
                        .foregroundStyle(AppPalette.paperMuted)
                }

                Spacer(minLength: 8)

                Text(relativeImportDate)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppPalette.paperMuted)
            }

            Text("materialMode=\(materialMode) · progress=\(progressText)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(AppPalette.paperInk.opacity(0.58))
        }
        .padding(.vertical, 8)
    }

    private var progressText: String {
        switch liveDocument.processingStatus {
        case .ready: return "100%"
        case .parsing: return "42%"
        case .imported: return "20%"
        case .failed: return parseInfo?.fallbackUsed == true ? "100%" : "12%"
        }
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
