import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showingReview = false
    @State private var selectedWorkbenchDocument: SourceDocument?
    @State private var selectedWorkbenchAnchor: SourceAnchor?
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

    var body: some View {
        ZStack {
            AppBackground(style: .dark)
            HomeAmbientGlow()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("欢迎回来，")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(AppPalette.softText)

                            Text("博雨")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(AppPalette.softText)

                            Text("今天继续把薄弱知识点一点点补齐。")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppPalette.softMutedText)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 14) {
                            HStack(spacing: 10) {
                                Button {
                                    showsNotesHome = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "note.text")
                                        Text("笔记")
                                    }
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppPalette.softText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.white.opacity(0.1))
                                    )
                                }

                                Button {
                                    showsSettings = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "gearshape.fill")
                                        Text("设置")
                                    }
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppPalette.softText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.white.opacity(0.1))
                                    )
                                }
                            }
                            .buttonStyle(.plain)

                            MasteryRing(progress: viewModel.progressPercentage)
                        }
                    }

                    StartReviewGlassButton {
                        showingReview = true
                    }

                    reviewWorkbenchSection

                    VStack(alignment: .leading, spacing: 18) {
                        Text("薄弱点")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppPalette.softText)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(viewModel.dailyProgress.highErrorChunks) { chunk in
                                    WeakPointCard(chunk: chunk)
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        Text("学习统计")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppPalette.softText)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(statItems) { item in
                                    HomeStatCard(item: item)
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }

                    GlassPanel(tone: .dark, cornerRadius: 30, padding: 22) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("今日专注")
                                    .font(.system(size: 19, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppPalette.softText)

                                Spacer()

                                MetricCapsule(label: "\(masteryValue)% 掌握度", tone: .dark, tint: AppPalette.mint)
                            }

                            Text("先处理高错误率知识块，再把今天剩余复习卡片顺着推进，节奏会更稳。")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppPalette.softMutedText)
                                .lineSpacing(5)

                            HStack(spacing: 10) {
                                FocusPill(icon: "brain.head.profile", text: "\(viewModel.dailyProgress.pendingReviewsCount) 张卡片")
                                FocusPill(icon: "clock", text: "\(viewModel.dailyProgress.estimatedDurationMinutes) 分钟")
                                FocusPill(icon: "sparkles", text: "智能混排")
                            }
                        }
                    }

                    Spacer(minLength: 160)
                }
                .padding(.horizontal, 24)
                .padding(.top, 62)
            }
        }
        .ignoresSafeArea()
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

    @ViewBuilder
    private var reviewWorkbenchSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("继续复盘")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.softText)

                Spacer()

                Text("我的英语资料")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppPalette.softMutedText)
            }

            if workbenchDocuments.isEmpty {
                GlassPanel(tone: .dark, cornerRadius: 28, padding: 20) {
                    Text("导入英语资料后，这里会保留你的上次学习位置，方便继续复盘。")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppPalette.softMutedText)
                        .lineSpacing(4)
                }
            } else {
                VStack(spacing: 14) {
                    ForEach(workbenchDocuments.prefix(3)) { document in
                        ReviewWorkbenchEntryCard(
                            document: document,
                            progress: viewModel.reviewWorkbenchProgress(for: document),
                            masteryValue: viewModel.workbenchMastery(for: document),
                            learnedSentenceCount: viewModel.workbenchStudiedSentenceCount(for: document)
                        ) {
                            selectedWorkbenchDocument = document
                        }
                    }
                }
            }
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
                .fill(AppPalette.cyan.opacity(0.24))
                .frame(width: 250 * glowScale, height: 250 * glowScale)
                .blur(radius: 76 * blurScale)
                .offset(x: 104, y: -64)

            Circle()
                .fill(AppPalette.mint.opacity(0.2))
                .frame(width: 224 * glowScale, height: 224 * glowScale)
                .blur(radius: 92 * blurScale)
                .offset(x: 138, y: 92)

            Circle()
                .fill(AppPalette.amber.opacity(0.18))
                .frame(width: 292 * glowScale, height: 292 * glowScale)
                .blur(radius: 102 * blurScale)
                .offset(x: -18, y: 244)

            Circle()
                .fill(AppPalette.primary.opacity(0.16))
                .frame(width: 214 * glowScale, height: 214 * glowScale)
                .blur(radius: 90 * blurScale)
                .offset(x: -108, y: 134)

            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(AppPalette.cyan.opacity(0.12))
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

struct MasteryRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 11)

            Circle()
                .trim(from: 0, to: max(min(progress, 1), 0.05))
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.92), AppPalette.primary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: AppPalette.primary.opacity(0.18), radius: 10)

            Text("\(Int(progress * 100))%")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppPalette.softText)
        }
        .frame(width: 100, height: 100)
        .padding(8)
        .background(
            Circle()
                .fill(Color.white.opacity(0.08))
                .overlay {
                    if !AppPerformance.prefersReducedEffects {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.32)
                    }
                }
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
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
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(AppPalette.softText)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.08)))
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
