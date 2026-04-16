import SwiftUI
import UIKit

struct ReviewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AppViewModel

    @State private var currentIndex = 0
    @State private var isAnswerVisible = false
    @State private var dragOffset: CGSize = .zero
    @State private var showDetailOverlay = false
    @State private var correctCount = 0
    @State private var partialCount = 0
    @State private var needsReviewCount = 0
    @State private var sessionStartTime = Date()

    private var currentCard: Card? {
        guard currentIndex < viewModel.reviewQueue.count else { return nil }
        return viewModel.reviewQueue[currentIndex]
    }

    private var usesRichMotion: Bool {
        !AppPerformance.prefersReducedEffects
    }

    private var totalReviewed: Int {
        correctCount + partialCount + needsReviewCount
    }

    private var masteryScore: Int {
        guard totalReviewed > 0 else { return 75 }
        let weighted = Double(correctCount) + Double(partialCount) * 0.6
        return Int((weighted / Double(totalReviewed)) * 100)
    }

    private var elapsedMinutes: Int {
        max(Int(Date().timeIntervalSince(sessionStartTime) / 60), 1)
    }

    private var dragProgress: CGFloat {
        min(abs(dragOffset.width) / 180, 1)
    }

    private var horizontalTilt: Double {
        usesRichMotion ? Double(dragOffset.width / 14) : 0
    }

    private var verticalTilt: Double {
        usesRichMotion ? Double(-dragOffset.height / 16) : 0
    }

    private var swipeAccent: Color {
        if dragOffset.width > 18 {
            return AppPalette.mint
        }
        if dragOffset.width < -18 {
            return AppPalette.amber
        }
        return AppPalette.primary
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = max(proxy.safeAreaInsets.top, 16)

            ZStack {
                ReviewSketchBackdrop()

                if let card = currentCard {
                    activeReviewView(card: card, topInset: topInset)
                } else {
                    summaryView(topInset: topInset)
                }

                if showDetailOverlay, let card = currentCard {
                    ReviewDetailOverlay(card: card) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                            showDetailOverlay = false
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(4)
                }
            }
            .ignoresSafeArea()
        }
    }

    private func activeReviewView(card: Card, topInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    Feedback.soft()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .frame(width: 54, height: 54)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1.4)
                                )
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Circle())

                Spacer()

                Text("\(min(currentIndex + 1, viewModel.reviewQueue.count)) / \(viewModel.reviewQueue.count)")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.92))
            }
            .padding(.horizontal, 28)
            .padding(.top, topInset + 8)
            .zIndex(2)

            ReviewProgressHeader(progress: progressValue, elapsedMinutes: elapsedMinutes)
                .padding(.top, 14)
                .padding(.horizontal, 24)

            Spacer(minLength: 18)

            ZStack {
                ReviewPaperStackBackground()
                    .padding(.horizontal, 36)

                ReviewFlipCard(
                    card: card,
                    sourceTitle: resolvedSourceTitle(for: card),
                    isFlipped: isAnswerVisible
                )
                .offset(dragOffset)
                .rotationEffect(.degrees(Double(dragOffset.width / (usesRichMotion ? 20 : 28))))
                .rotation3DEffect(.degrees(horizontalTilt), axis: (x: 0, y: 1, z: 0), perspective: 0.76)
                .rotation3DEffect(.degrees(verticalTilt), axis: (x: 1, y: 0, z: 0), perspective: 0.76)
                .scaleEffect(1 - dragProgress * (usesRichMotion ? 0.05 : 0.025))
                .shadow(color: swipeAccent.opacity(0.08 + Double(dragProgress) * 0.16), radius: usesRichMotion ? 28 : 12, y: usesRichMotion ? 18 : 8)
                .overlay { swipeEdgeGlow }
                .gesture(cardGesture)

                swipeFeedbackOverlay
            }
            .frame(height: 490)

            if isAnswerVisible {
                VStack(spacing: 18) {
                    HStack(spacing: 24) {
                        ReviewOrbButton(title: "困难", color: AppPalette.amber) {
                            triggerResult(.unknown, travel: -440)
                        }

                        ReviewOrbButton(title: "一般", color: AppPalette.primary) {
                            Feedback.medium()
                            Task { await advance(with: .vague) }
                        }

                        ReviewOrbButton(title: "轻松", color: AppPalette.mint) {
                            triggerResult(.known, travel: 440)
                        }
                    }

                    Text("左右拖动卡片也可以快速评分")
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .padding(.top, 24)
            } else {
                ShowAnswerButton {
                    Feedback.soft()
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                        isAnswerVisible = true
                    }
                }
                .padding(.top, 26)
            }

            footerContext(card: card)
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 30)
        }
    }

    private var swipeFeedbackOverlay: some View {
        ZStack {
            if dragOffset.width < -18 {
                SwipeFeedbackHalo(
                    title: "困难",
                    subtitle: "向左滑动",
                    color: AppPalette.amber,
                    systemImage: "arrow.left.circle.fill"
                )
                .offset(x: -110)
                .opacity(Double(dragProgress))
            }

            if dragOffset.width > 18 {
                SwipeFeedbackHalo(
                    title: "轻松",
                    subtitle: "向右滑动",
                    color: AppPalette.mint,
                    systemImage: "arrow.right.circle.fill"
                )
                .offset(x: 110)
                .opacity(Double(dragProgress))
            }
        }
        .allowsHitTesting(false)
    }

    private var swipeEdgeGlow: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        swipeAccent.opacity(0.55 * Double(dragProgress)),
                        Color.white.opacity(0.1 * Double(dragProgress)),
                        swipeAccent.opacity(0.22 * Double(dragProgress))
                    ],
                    startPoint: dragOffset.width >= 0 ? .topLeading : .topTrailing,
                    endPoint: dragOffset.width >= 0 ? .bottomTrailing : .bottomLeading
                ),
                lineWidth: AppPerformance.prefersReducedEffects ? 1.25 : 2
            )
            .padding(.horizontal, 24)
            .opacity(Double(dragProgress))
            .allowsHitTesting(false)
    }

    private func footerContext(card: Card) -> some View {
        PaperSheetCard(
            padding: 18,
            cornerRadius: 24,
            rotation: -0.6,
            accent: AppPalette.paperTapeBlue.opacity(0.72),
            showsTape: false
        ) {
            VStack(spacing: 14) {
                HStack {
                    Text("来源：\(resolvedSourceTitle(for: card))")
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(AppPalette.paperInk.opacity(0.84))

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            showDetailOverlay = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up")
                            Text("查看详解")
                        }
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(AppPalette.paperInk)
                    }
                    .buttonStyle(.plain)
                }

                Text("标签：\(card.keywords.joined(separator: "、"))")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(AppPalette.paperMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .topLeading) {
            ReviewPaperClip()
                .offset(x: 14, y: -10)
        }
    }

    private func summaryView(topInset: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                HStack {
                    Button {
                        Feedback.soft()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppPalette.softMutedText)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())

                    Spacer()

                    Text("复习总结")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.softText)

                    Spacer()

                    Color.clear.frame(width: 16, height: 16)
                }

                summaryRing
                    .padding(.top, 4)

                momentumCard

                HStack(spacing: 14) {
                    AchievementCard(
                        icon: "bolt.fill",
                        title: "快节奏状态",
                        message: "本轮有 \(max(correctCount, 1)) 张卡片在一分钟内完成判断",
                        tint: AppPalette.cyan
                    )

                    AchievementCard(
                        icon: "sparkles",
                        title: "稳定推进",
                        message: "整轮复习没有中断，节奏保持很完整",
                        tint: AppPalette.mint
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("结果拆解")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.softText)

                    SummaryRow(title: "回答正确", value: "\(correctCount)", tint: AppPalette.mint)
                    SummaryRow(title: "回答一般", value: "\(partialCount)", tint: AppPalette.primary)
                    SummaryRow(title: "需要回看", value: "\(needsReviewCount)", tint: AppPalette.rose)
                }

                HStack(spacing: 14) {
                    Button(action: {}) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("分享")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppPalette.softMutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    PrimaryGlowButton(title: "完成", icon: "checkmark.circle.fill") {
                        dismiss()
                    }
                }

                Spacer(minLength: 36)
            }
            .padding(.horizontal, 24)
            .padding(.top, topInset + 14)
            .padding(.bottom, 36)
        }
    }

    private var summaryRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 16)
                .frame(width: 190, height: 190)

            Circle()
                .trim(from: 0, to: Double(masteryScore) / 100)
                .stroke(
                    LinearGradient(
                        colors: [AppPalette.mint, Color.green.opacity(0.72)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .frame(width: 190, height: 190)
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text("\(masteryScore)%")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.softText)

                Text("掌握度")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppPalette.softMutedText)
                    .tracking(1.2)
            }
        }
        .padding(18)
    }

    private var momentumCard: some View {
        GlassPanel(tone: .dark, cornerRadius: 30, padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本周节奏")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(AppPalette.primary)

                        Text("这一周整体推进比较稳定")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppPalette.softMutedText)
                    }

                    Spacer()

                    MetricCapsule(label: "\(viewModel.dailyProgress.streakDays) 天连续", tone: .dark, tint: AppPalette.mint)
                }

                HStack(spacing: 8) {
                    ForEach(Array(momentumValues.enumerated()), id: \.offset) { index, value in
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(momentumColor(for: value))
                                .frame(height: 50)

                            Text(weekdays[index])
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppPalette.softMutedText)
                        }
                    }
                }
            }
        }
    }

    private var weekdays: [String] {
        ["一", "二", "三", "四", "五", "六", "日"]
    }

    private var momentumValues: [Double] {
        [1.0, 0.82, 0.45, 0.92, 0.58, 0.88, 0.1]
    }

    private func momentumColor(for value: Double) -> Color {
        if value > 0.75 { return AppPalette.mint }
        if value > 0.45 { return AppPalette.mint.opacity(0.72) }
        if value > 0.15 { return AppPalette.primaryDeep.opacity(0.55) }
        return Color.white.opacity(0.06)
    }

    private var progressValue: Double {
        guard !viewModel.reviewQueue.isEmpty else { return 0 }
        return Double(currentIndex) / Double(viewModel.reviewQueue.count)
    }

    private func resolvedSourceTitle(for card: Card) -> String {
        viewModel.sourceTitle(for: card)
    }

    private var cardGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard isAnswerVisible else { return }
                dragOffset = CGSize(
                    width: value.translation.width,
                    height: max(min(value.translation.height * 0.18, 36), -46)
                )
            }
            .onEnded { value in
                guard isAnswerVisible else { return }

                if value.translation.width > 104 {
                    triggerResult(.known, travel: 440)
                } else if value.translation.width < -104 {
                    triggerResult(.unknown, travel: -440)
                } else if value.translation.height < -110 {
                    Feedback.soft()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                        showDetailOverlay = true
                    }
                    dragOffset = .zero
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    private func triggerResult(_ result: ReviewResult, travel: CGFloat) {
        switch result {
        case .known:
            Feedback.success()
        case .vague:
            Feedback.medium()
        case .unknown:
            Feedback.warning()
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            dragOffset = CGSize(width: travel, height: -10)
        }

        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            await advance(with: result)
        }
    }

    @MainActor
    private func advance(with result: ReviewResult) async {
        guard let card = currentCard else { return }

        await viewModel.submitReviewResult(result, for: card)

        switch result {
        case .known:
            correctCount += 1
        case .vague:
            partialCount += 1
        case .unknown:
            needsReviewCount += 1
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
            currentIndex += 1
            isAnswerVisible = false
            dragOffset = .zero
            showDetailOverlay = false
        }
    }
}

private struct ReviewSketchBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 49 / 255, green: 86 / 255, blue: 143 / 255),
                    Color(red: 40 / 255, green: 71 / 255, blue: 122 / 255),
                    Color(red: 33 / 255, green: 60 / 255, blue: 105 / 255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 340, height: 340)
                .blur(radius: 120)
                .offset(x: 140, y: -230)

            Circle()
                .fill(Color.black.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 120)
                .offset(x: -120, y: 240)

            ReviewDoodleMarks()
                .opacity(0.34)
        }
    }
}

private struct ReviewDoodleMarks: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let marks: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                    (0.12, 0.08, 14, 42),
                    (0.22, 0.18, 10, 34),
                    (0.82, 0.13, 11, 38),
                    (0.78, 0.32, 9, 30),
                    (0.18, 0.58, 15, 45),
                    (0.84, 0.7, 10, 34),
                    (0.1, 0.88, 12, 40)
                ]

                for mark in marks {
                    let x = proxy.size.width * mark.0
                    let y = proxy.size.height * mark.1
                    path.move(to: CGPoint(x: x, y: y))
                    path.addQuadCurve(
                        to: CGPoint(x: x + mark.2, y: y + mark.3),
                        control: CGPoint(x: x - 8, y: y + mark.3 * 0.45)
                    )
                }
            }
            .stroke(Color.black.opacity(0.18), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

private struct ReviewPaperStackBackground: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(AppPalette.paperCard.opacity(0.86))
                .offset(x: 14, y: 18)
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 5)

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(AppPalette.paperBackgroundDeep.opacity(0.94))
                .offset(x: 7, y: 9)
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 5)
        }
        .frame(height: 430)
    }
}

private struct ReviewPencilProgressBar: View {
    let progress: Double
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.1))
                .frame(width: max(width - 36, 0), height: 12)
                .offset(x: 18)

            Capsule(style: .continuous)
                .fill(Color(red: 142 / 255, green: 143 / 255, blue: 85 / 255))
                .frame(width: max((width - 36) * progress, 22), height: 12)
                .offset(x: 18)

            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(red: 212 / 255, green: 133 / 255, blue: 122 / 255))
                    .frame(width: 18, height: 18)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(red: 233 / 255, green: 214 / 255, blue: 168 / 255))
                    .frame(width: max(width - 52, 0), height: 14)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.8), lineWidth: 1)
                    )

                Triangle()
                    .fill(Color(red: 233 / 255, green: 214 / 255, blue: 168 / 255))
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(90))
                    .overlay(alignment: .trailing) {
                        Triangle()
                            .fill(Color(red: 122 / 255, green: 82 / 255, blue: 50 / 255))
                            .frame(width: 7, height: 7)
                            .rotationEffect(.degrees(90))
                    }
            }
            .frame(height: 20)
        }
        .overlay(alignment: .trailing) {
            Text("\(Int(progress * 100))%")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(Color.white.opacity(0.92))
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct ReviewMaskedTape: View {
    let sourceTitle: String
    let tags: [String]

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 10)

            VStack(alignment: .leading, spacing: 6) {
                Text("来源：\(sourceTitle)")
                Text("标签：\(tags.joined(separator: "、"))")
            }
            .font(.system(size: 15, weight: .medium, design: .serif))
            .foregroundStyle(AppPalette.paperInk)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppPalette.paperBackground.opacity(0.95))
                    .overlay {
                        NotebookGrid(spacing: 12)
                            .opacity(0.2)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppPalette.paperLine.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [1, 7]))
                    )
            )
        }
    }
}

private struct ReviewPaperClip: View {
    var body: some View {
        Image(systemName: "paperclip")
            .font(.system(size: 28, weight: .medium))
            .foregroundStyle(Color(red: 150 / 255, green: 122 / 255, blue: 77 / 255))
            .rotationEffect(.degrees(90))
    }
}

private struct ReviewSparkleStamp: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 28, weight: .light))
            .foregroundStyle(AppPalette.paperMuted.opacity(0.9))
    }
}

private struct ReviewMiniPaperButton: View {
    let title: String
    let subtitle: String
    let tint: Color
    let rotation: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint.opacity(0.58))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(AppPalette.fabricNavy.opacity(0.3), lineWidth: 1)
                    )

                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(AppPalette.fabricNavy)
            }

            Text(subtitle)
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(AppPalette.paperMuted)

            Capsule(style: .continuous)
                .fill(tint.opacity(0.75))
                .frame(width: 54, height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppPalette.paperCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.92), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    PaperTapeAccent(color: tint.opacity(0.9), width: 54, height: 18)
                        .offset(x: 6, y: -8)
                }
                .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
        )
        .rotationEffect(.degrees(rotation))
    }
}

private struct ReviewSectionPaper<Content: View>: View {
    let title: String
    let tint: Color
    var rotation: Double = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        PaperSheetCard(
            padding: 18,
            cornerRadius: 24,
            rotation: rotation,
            accent: tint.opacity(0.8),
            showsTape: true
        ) {
            VStack(alignment: .leading, spacing: 12) {
                MarkerTitle(text: title, tint: tint.opacity(0.8))
                content()
            }
        }
    }
}

struct ReviewFlipCard: View {
    let card: Card
    let sourceTitle: String
    let isFlipped: Bool

    var body: some View {
        let rotation = isFlipped ? 180.0 : 0.0

        ZStack {
            questionFace
                .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                .opacity(isFlipped ? 0 : 1)

            answerFace
                .rotation3DEffect(.degrees(rotation + 180), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                .opacity(isFlipped ? 1 : 0)
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: isFlipped)
        .padding(.horizontal, 24)
    }

    private var questionFace: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                Spacer(minLength: 12)

                Text(card.frontContent)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(AppPalette.fabricNavy)
                    .lineSpacing(8)
                    .minimumScaleFactor(0.84)

                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 410, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 120)
            .background(reviewPaperCardBackground)
        }
        .overlay(alignment: .bottomLeading) {
            ReviewMaskedTape(
                sourceTitle: sourceTitle,
                tags: card.keywords
            )
            .padding(.leading, -2)
            .padding(.bottom, 48)
        }
        .overlay(alignment: .trailing) {
            ReviewPaperClip()
                .padding(.trailing, 18)
                .offset(y: 52)
        }
        .overlay(alignment: .bottomTrailing) {
            ReviewSparkleStamp()
                .padding(.trailing, 26)
                .padding(.bottom, 28)
        }
    }

    private var answerFace: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                MarkerTitle(text: "答案", tint: AppPalette.paperHighlightMint)
                Spacer()
                SketchBadge(title: card.type.displayName, tint: AppPalette.paperTapeBlue.opacity(0.22))
            }

            Text(card.backContent)
                .font(.system(size: 25, weight: .medium, design: .serif))
                .foregroundStyle(AppPalette.paperInk.opacity(0.88))
                .lineSpacing(7)

            if !card.keywords.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    ForEach(card.keywords, id: \.self) { keyword in
                        SketchBadge(title: keyword, tint: AppPalette.paperHighlight.opacity(0.52))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 410, alignment: .topLeading)
        .padding(28)
        .background(reviewPaperCardBackground)
        .overlay(alignment: .topTrailing) {
            PaperTapeAccent(color: AppPalette.paperTapeBlue, width: 78, height: 20)
                .offset(x: -2, y: -8)
        }
        .overlay(alignment: .bottomLeading) {
            MarkerTitle(text: "记住思路", tint: AppPalette.paperHighlight.opacity(0.8))
                .padding(.leading, 28)
                .padding(.bottom, 24)
        }
        .overlay(alignment: .bottomTrailing) {
            ReviewSparkleStamp()
                .padding(.trailing, 24)
                .padding(.bottom, 24)
        }
    }

    private var reviewPaperCardBackground: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(AppPalette.paperCard)
            .overlay {
                NotebookGrid(spacing: 26)
                    .opacity(0.08)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.white.opacity(0.92), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 20, y: 8)
    }
}

struct ReviewProgressHeader: View {
    let progress: Double
    let elapsedMinutes: Int

    var body: some View {
        VStack(spacing: 12) {
            Text("已用 \(elapsedMinutes) 分钟")
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(Color.white.opacity(0.9))

            GeometryReader { proxy in
                ReviewPencilProgressBar(progress: progress, width: proxy.size.width)
            }
            .frame(height: 28)
        }
    }
}

struct ShowAnswerButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("查看答案")
                .font(.system(size: 23, weight: .bold, design: .serif))
                .foregroundStyle(AppPalette.fabricNavy)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppPalette.paperCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppPalette.fabricNavy.opacity(0.78), lineWidth: 1.8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppPalette.fabricNavy.opacity(0.42), lineWidth: 1)
                                .padding(8)
                        )
                        .shadow(color: Color.black.opacity(0.16), radius: 12, y: 6)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 34)
    }
}

struct ReviewOrbButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ReviewMiniPaperButton(
                title: title,
                subtitle: subtitle,
                tint: color,
                rotation: rotation
            )
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        switch title {
        case "困难": return "再看一遍"
        case "一般": return "基本记住"
        case "轻松": return "已经掌握"
        default: return "快速标记"
        }
    }

    private var rotation: Double {
        switch title {
        case "困难": return -2.2
        case "轻松": return 1.8
        default: return -0.4
        }
    }
}

struct SwipeFeedbackHalo: View {
    let title: String
    let subtitle: String
    let color: Color
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppPalette.fabricNavy)

            Text(title)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(AppPalette.fabricNavy)

            Text(subtitle)
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .foregroundStyle(AppPalette.paperMuted)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppPalette.paperCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(color.opacity(0.7), lineWidth: 1.8)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 14, y: 8)
        )
    }
}

struct ReviewDetailOverlay: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let card: Card
    let onClose: () -> Void
    @State private var isExpanded = false
    @State private var dragOffset: CGFloat = 0
    @State private var showsRewriteMeaning = false
    @State private var explanation: AIExplainSentenceResult?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var explainContext: ExplainSentenceContext? {
        viewModel.explainSentenceContext(for: card)
    }

    private var dismissProgress: CGFloat {
        min(max(dragOffset / 220, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let collapsedHeight = min(max(proxy.size.height * 0.64, 460), proxy.size.height * 0.78)
            let expandedHeight = proxy.size.height * 0.88
            let baseHeight = isExpanded ? expandedHeight : collapsedHeight
            let liveHeight = min(max(baseHeight - dragOffset, collapsedHeight), expandedHeight)

            ZStack {
                Color.black.opacity(0.3 - Double(dismissProgress) * 0.16)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)

                VStack(spacing: 0) {
                    Spacer()

                    PaperSheetCard(
                        padding: 0,
                        cornerRadius: 34,
                        rotation: -0.25,
                        accent: AppPalette.paperTapeBlue.opacity(0.9),
                        showsTape: true
                    ) {
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
                                    .padding(.bottom, 28)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(height: liveHeight)
                    .overlay(alignment: .topTrailing) {
                        ReviewPaperClip()
                            .padding(.trailing, 18)
                            .padding(.top, 20)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private var overlayHeader: some View {
        HStack(alignment: .center) {
            Capsule()
                .fill(AppPalette.paperMuted.opacity(0.22))
                .frame(width: 66, height: 6)

            Spacer()

            Text(isExpanded ? "下拉收起" : "上拉展开")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(AppPalette.paperMuted)

            Spacer()

            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                    Text("关闭")
                }
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(AppPalette.paperMuted)
            }
            .buttonStyle(.plain)
        }
    }

    private var overlayBody: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("句子详解")
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(AppPalette.fabricNavy)

            Text(viewModel.sourceTitle(for: card))
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .foregroundStyle(AppPalette.paperMuted)

            if let explainContext {
                sentenceCard(explainContext.sentence)
                explanationContent(for: explainContext)
            } else {
                unsupportedCard
            }

            if !card.keywords.isEmpty {
                keywordCloud
            }

            contextCard
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

    private var taskIdentifier: String {
        card.id.uuidString
    }

    private func sentenceCard(_ sentence: String) -> some View {
        ReviewSectionPaper(title: "目标句子", tint: AppPalette.paperHighlight, rotation: -0.4) {
            Text(sentence)
                .font(.system(size: 21, weight: .semibold, design: .serif))
                .foregroundStyle(AppPalette.fabricNavy)
                .lineSpacing(6)
        }
    }

    @ViewBuilder
    private func explanationContent(for explainContext: ExplainSentenceContext) -> some View {
        if isLoading {
            loadingCard
        } else if let explanation {
            explanationSections(explanation)
        } else if let errorMessage {
            errorCard(message: errorMessage)
        } else {
            placeholderCard(for: explainContext)
        }
    }

    private var loadingCard: some View {
        ReviewSectionPaper(title: "正在生成", tint: AppPalette.paperTapeBlue, rotation: 0.2) {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在请求后端并生成句子讲解")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(AppPalette.paperInk.opacity(0.78))
            }

            Text("首次请求会稍慢一点，结果会直接显示在这里。")
                .font(.system(size: 14, weight: .medium, design: .serif))
                .foregroundStyle(AppPalette.paperMuted)
        }
    }

    private func errorCard(message: String) -> some View {
        ReviewSectionPaper(title: "讲解获取失败", tint: AppPalette.amber, rotation: 0.4) {
            Text(message)
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(AppPalette.paperInk.opacity(0.7))
                .lineSpacing(4)

            manualExplainButton(title: "重新获取云端讲解（会消耗额度）")
        }
    }

    private func placeholderCard(for explainContext: ExplainSentenceContext) -> some View {
        ReviewSectionPaper(title: "等待生成", tint: AppPalette.paperTapeBlue, rotation: 0.15) {
            Text("已关闭自动云端讲解，避免在复习时持续消耗额度。")
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(AppPalette.paperInk.opacity(0.68))
                .lineSpacing(4)

            Text("上下文长度：\(explainContext.context.count) 字符")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(AppPalette.paperMuted)

            manualExplainButton(title: "生成云端讲解（会消耗额度）")
        }
    }

    private func manualExplainButton(title: String) -> some View {
        Button(title) {
            Task {
                await reloadExplanation()
            }
        }
        .font(.system(size: 14, weight: .semibold, design: .serif))
        .buttonStyle(.plain)
        .foregroundStyle(AppPalette.fabricNavy)
    }

    private func explanationSections(_ explanation: AIExplainSentenceResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            let sentenceFunction = explanation.renderedSentenceFunction.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentenceFunction.isEmpty {
                explanationSection(
                    title: "句子定位",
                    body: sentenceFunction,
                    tint: AppPalette.paperTapeBlue,
                    rotation: -0.18
                )
            }

            explanationSection(title: "句子主干", body: explanation.renderedSentenceCore, tint: AppPalette.paperTapeBlue.opacity(0.8), rotation: 0.3)

            explanationSection(
                title: "忠实翻译",
                body: explanation.renderedFaithfulTranslation.isEmpty ? "暂无忠实翻译" : explanation.renderedFaithfulTranslation,
                tint: AppPalette.paperHighlightMint,
                rotation: -0.2
            )

            explanationSection(
                title: "教学解读",
                body: explanation.renderedTeachingInterpretation.isEmpty ? "暂无教学解读" : explanation.renderedTeachingInterpretation,
                tint: AppPalette.paperHighlight.opacity(0.78),
                rotation: 0.12
            )

            if !explanation.renderedChunkLayers.isEmpty {
                ReviewSectionPaper(title: "语块切分", tint: AppPalette.paperHighlightMint, rotation: -0.2) {
                    ForEach(Array(explanation.renderedChunkLayers.enumerated()), id: \.offset) { _, chunk in
                        explanationBullet(title: "语块", body: chunk)
                    }
                }
            }

            if !explanation.renderedGrammarFocus.isEmpty {
                ReviewSectionPaper(title: "关键语法点", tint: AppPalette.amber, rotation: -0.25) {
                    ForEach(Array(explanation.renderedGrammarFocus.enumerated()), id: \.offset) { _, point in
                        explanationBullet(title: "语法点", body: point)
                    }
                }
            }

            if !explanation.renderedMisreadingTraps.isEmpty {
                ReviewSectionPaper(title: "学生易错点", tint: AppPalette.amber.opacity(0.82), rotation: 0.18) {
                    ForEach(Array(explanation.renderedMisreadingTraps.enumerated()), id: \.offset) { _, item in
                        explanationBullet(title: "易错点", body: item)
                    }
                }
            }

            if !explanation.renderedExamParaphraseRoutes.isEmpty {
                ReviewSectionPaper(title: "出题改写点", tint: AppPalette.paperHighlight, rotation: -0.1) {
                    ForEach(Array(explanation.renderedExamParaphraseRoutes.enumerated()), id: \.offset) { _, item in
                        explanationBullet(title: "改写路线", body: item)
                    }
                }
            }

            explanationSection(title: "简化英文改写", body: explanation.renderedSimplerRewrite, tint: AppPalette.paperTapeBlue.opacity(0.72), rotation: 0.14)

            ReviewSectionPaper(title: "改写译意", tint: AppPalette.paperHighlightMint.opacity(0.82), rotation: 0.08) {
                Button(showsRewriteMeaning ? "隐藏译意" : "显示译意") {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        showsRewriteMeaning.toggle()
                    }
                }
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .buttonStyle(.plain)
                .foregroundStyle(AppPalette.fabricNavy)

                if showsRewriteMeaning {
                    Text(explanation.renderedSimplerRewriteTranslation.isEmpty ? "暂无改写译意" : explanation.renderedSimplerRewriteTranslation)
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(AppPalette.paperInk.opacity(0.68))
                        .lineSpacing(4)
                }
            }

            if let miniExercise = explanation.renderedMiniCheck?.trimmingCharacters(in: .whitespacesAndNewlines),
               !miniExercise.isEmpty {
                explanationSection(title: "微练习", body: miniExercise, tint: AppPalette.amber.opacity(0.72), rotation: -0.08)
            }

            if !explanation.keyTerms.isEmpty {
                ReviewSectionPaper(title: "词汇在句中义", tint: AppPalette.paperTapeBlue, rotation: 0.35) {
                    ForEach(Array(explanation.keyTerms.enumerated()), id: \.offset) { _, term in
                        explanationBullet(title: term.term, body: term.meaning)
                    }
                }
            }
        }
    }

    private func explanationSection(title: String, body: String, tint: Color, rotation: Double) -> some View {
        ReviewSectionPaper(title: title, tint: tint, rotation: rotation) {
            Text(body)
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(AppPalette.paperInk.opacity(0.68))
                .lineSpacing(4)
        }
    }

    private func explanationBullet(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(AppPalette.fabricNavy)

            Text(body)
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundStyle(AppPalette.paperInk.opacity(0.58))
                .lineSpacing(4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.56))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppPalette.paperLine.opacity(0.8), lineWidth: 1)
                )
        )
    }

    private var keywordCloud: some View {
        ReviewSectionPaper(title: "卡片标签", tint: AppPalette.paperTape, rotation: -0.1) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(card.keywords, id: \.self) { keyword in
                    SketchBadge(title: keyword, tint: AppPalette.paperHighlight.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var unsupportedCard: some View {
        ReviewSectionPaper(title: "当前卡片暂不支持", tint: AppPalette.amber, rotation: 0.25) {
            Text("这张卡片没有检测到可用于讲解的英语句子。请先切到英语资料生成的卡片，或者在生成卡片时保留原英文句子。")
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(AppPalette.paperInk.opacity(0.64))
                .lineSpacing(4)
        }
    }

    private var contextCard: some View {
        ReviewSectionPaper(title: "来源上下文", tint: AppPalette.paperTapeBlue, rotation: 0.18) {
            Text(viewModel.knowledgeChunk(for: card)?.content ?? card.backContent)
                .font(.system(size: 17, weight: .medium, design: .serif))
                .foregroundStyle(AppPalette.paperInk.opacity(0.72))
                .lineSpacing(4)
        }
    }

    @MainActor
    private func reloadExplanation() async {
        explanation = nil
        errorMessage = nil
        await fetchExplanationIfPossible(forceRefresh: true)
    }

    @MainActor
    private func fetchExplanationIfPossible(forceRefresh: Bool = false) async {
        guard let explainContext else { return }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await AIExplainSentenceService.fetchExplanationWithCache(
                for: explainContext,
                forceRefresh: forceRefresh
            )
            explanation = result
            errorMessage = nil
        } catch {
            explanation = nil
            errorMessage = error.localizedDescription
        }
    }
}

struct AchievementCard: View {
    let icon: String
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        GlassPanel(tone: .dark, cornerRadius: 28, padding: 18) {
            VStack(spacing: 12) {
                FrostedOrb(icon: icon, size: 56, tone: .dark)
                    .overlay(
                        Circle()
                            .stroke(tint.opacity(0.22), lineWidth: 1)
                    )

                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.softText)

                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppPalette.softMutedText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct SummaryRow: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        GlassPanel(tone: .dark, cornerRadius: 24, padding: 16) {
            HStack {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint)
                        .frame(width: 6, height: 28)

                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppPalette.softText)
                }

                Spacer()

                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }
        }
    }
}

private enum Feedback {
    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

#if DEBUG
struct ReviewSessionView_Previews: PreviewProvider {
    static var previews: some View {
        ReviewSessionView()
            .environmentObject(AppViewModel())
    }
}
#endif
