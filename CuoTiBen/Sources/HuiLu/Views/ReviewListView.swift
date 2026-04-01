import SwiftUI

struct ReviewListView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showingSession = false

    private var upcomingCards: [Card] {
        Array(viewModel.reviewQueue.prefix(3))
    }

    var body: some View {
        ZStack {
            reviewBackdrop

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    reviewHeader

                    pendingHeroCard

                    VStack(alignment: .leading, spacing: 16) {
                        MarkerTitle(text: "卡片队列", tint: AppPalette.paperHighlightMint)
                            .padding(.leading, 4)

                        ForEach(Array(upcomingCards.enumerated()), id: \.element.id) { index, card in
                            PaperReviewPreviewCard(
                                card: card,
                                orderLabel: index == 0 ? "下一张" : "随后",
                                accent: index == 0 ? AppPalette.paperTapeBlue : AppPalette.paperTape
                            )
                            .padding(.leading, CGFloat(index * 12))
                            .padding(.trailing, CGFloat(max(0, 2 - index) * 6))
                        }
                    }

                    focusSignalsBoard

                    Spacer(minLength: 140)
                }
                .padding(.horizontal, 22)
                .padding(.top, 54)
                .padding(.bottom, 48)
            }
        }
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $showingSession) {
            ReviewSessionView()
                .environmentObject(viewModel)
        }
    }

    private var reviewBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [AppPalette.fabricNavy, AppPalette.oceanBlue.opacity(0.72), AppPalette.fabricNavy],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: 150, y: -260)

            Circle()
                .fill(AppPalette.paperTape.opacity(0.14))
                .frame(width: 240, height: 240)
                .blur(radius: 90)
                .offset(x: -120, y: -20)
        }
    }

    private var reviewHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("沉浸复习")
                    .font(.system(size: 36, weight: .bold, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.95))

                Text("把今天的卡片收成一叠，一次性推进完。")
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.72))
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 6)
                    .frame(width: 92, height: 92)

                Circle()
                    .trim(from: 0, to: min(Double(viewModel.dailyProgress.pendingReviewsCount) / 30, 1))
                    .stroke(
                        Color.white.opacity(0.85),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 92, height: 92)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 3) {
                    Text("\(viewModel.dailyProgress.pendingReviewsCount)")
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(Color.white)
                    Text("待处理")
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.74))
                }
            }
        }
    }

    private var pendingHeroCard: some View {
        ZStack {
            PaperSheetCard(
                padding: 0,
                cornerRadius: 32,
                rotation: -2.2,
                accent: AppPalette.paperTapeBlue.opacity(0.55),
                showsTape: false
            ) {
                Color.clear.frame(height: 360)
            }
            .offset(y: 26)
            .opacity(0.62)

            PaperSheetCard(
                padding: 0,
                cornerRadius: 32,
                rotation: 2,
                accent: AppPalette.paperTape.opacity(0.5),
                showsTape: false
            ) {
                Color.clear.frame(height: 344)
            }
            .offset(y: 12)
            .opacity(0.72)

            PaperSheetCard(
                padding: 30,
                cornerRadius: 34,
                rotation: -1,
                accent: AppPalette.paperTape,
                showsTape: true
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("\(viewModel.dailyProgress.pendingReviewsCount) 张卡片待处理")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.paperInk)

                    MarkerTitle(
                        text: "预计 \(viewModel.dailyProgress.estimatedDurationMinutes) 分钟完成，建议整段专注推进。",
                        tint: AppPalette.paperHighlight
                    )

                    Button {
                        showingSession = true
                    } label: {
                        HStack(spacing: 12) {
                            Text("开始沉浸复习")
                            Image(systemName: "play.fill")
                        }
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RibbonButtonStyle(tint: Color(red: 165 / 255, green: 117 / 255, blue: 84 / 255)))
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(upcomingCards.prefix(2).enumerated()), id: \.offset) { index, card in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(index == 0 ? "下一张" : "随后")
                                    .font(.system(size: 15, weight: .medium, design: .serif))
                                    .foregroundStyle(AppPalette.paperMuted)

                                Text(card.frontContent)
                                    .font(.system(size: 22, weight: .semibold, design: .serif))
                                    .foregroundStyle(AppPalette.paperInk)
                                    .lineSpacing(5)

                                HStack(spacing: 10) {
                                    SketchBadge(title: "\(card.errorCount) 次错题", tint: Color.red.opacity(0.16))
                                    SketchBadge(title: "难度 \(card.difficultyLevel)", tint: Color.green.opacity(0.18))
                                }
                            }

                            if index == 0 {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundStyle(AppPalette.paperMuted.opacity(0.72))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .padding(.trailing, 10)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var focusSignalsBoard: some View {
        VStack(alignment: .leading, spacing: 16) {
            MarkerTitle(text: "专注信号", tint: AppPalette.paperHighlightMint)
                .padding(.leading, 4)

            HStack(spacing: 14) {
                ReviewSignalTile(
                    icon: "flame.fill",
                    value: "\(viewModel.dailyProgress.streakDays)",
                    label: "连续天数",
                    tint: AppPalette.paperHighlightMint
                )

                ReviewSignalTile(
                    icon: "brain.head.profile",
                    value: "\(viewModel.reviewQueue.count)",
                    label: "待复习",
                    tint: AppPalette.paperTapeBlue.opacity(0.3)
                )

                ReviewSignalTile(
                    icon: "clock.fill",
                    value: "\(viewModel.dailyProgress.estimatedDurationMinutes) 分",
                    label: "专注时长",
                    tint: AppPalette.paperTape.opacity(0.36)
                )
            }
        }
    }
}

struct ReviewSignalTile: View {
    let icon: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        PaperSheetCard(padding: 18, cornerRadius: 24, rotation: icon == "flame.fill" ? -1.1 : (icon == "brain.head.profile" ? 0.8 : -0.5), accent: tint, showsTape: false) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppPalette.paperMuted)

                Text(label)
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(AppPalette.paperInk)

                Text(value)
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(AppPalette.paperMuted)

                Capsule()
                    .fill(AppPalette.paperInk.opacity(0.14))
                    .frame(height: 10)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(AppPalette.paperInk.opacity(0.72))
                            .frame(width: 54)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PaperReviewPreviewCard: View {
    let card: Card
    let orderLabel: String
    let accent: Color

    var body: some View {
        PaperSheetCard(
            padding: 22,
            cornerRadius: 28,
            rotation: orderLabel == "下一张" ? -1.2 : 1.4,
            accent: accent,
            showsTape: true
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(orderLabel)
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(AppPalette.paperMuted)

                    Spacer()

                    SketchBadge(title: card.type.displayName, tint: accent.opacity(0.24))
                }

                Text(card.frontContent)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(AppPalette.paperInk)
                    .lineSpacing(4)
                    .lineLimit(3)

                HStack(spacing: 10) {
                    SketchBadge(title: "\(card.errorCount) 次错题", tint: Color.red.opacity(0.16))
                    SketchBadge(title: "难度 \(card.difficultyLevel)", tint: Color.green.opacity(0.16))
                }
            }
        }
    }
}
