import SwiftUI

struct ReviewListView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showingSession = false

    private var upcomingCards: [Card] {
        Array(viewModel.reviewQueue.prefix(3))
    }

    var body: some View {
        ZStack {
            AppBackground(style: .dark)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("复习流程")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(AppPalette.softText)

                            Text("把今天的待复习内容一次性推进完。")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppPalette.softMutedText)
                        }

                        Spacer()

                        FrostedOrb(icon: "waveform.path.ecg", size: 60, tone: .dark)
                    }

                    GlassPanel(tone: .dark, cornerRadius: 30, padding: 22) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("今日待复习")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppPalette.primary)

                            Text("\(viewModel.dailyProgress.pendingReviewsCount) 张卡片待处理")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(AppPalette.softText)

                            Text("预计 \(viewModel.dailyProgress.estimatedDurationMinutes) 分钟完成，建议整段专注推进。")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppPalette.softMutedText)

                            PrimaryGlowButton(title: "开始沉浸复习", icon: "play.fill") {
                                showingSession = true
                            }
                        }
                    }

                    Text("队列预览")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.softText)

                    ForEach(Array(upcomingCards.enumerated()), id: \.element.id) { index, card in
                        GlassPanel(tone: .dark, cornerRadius: 28, padding: 20) {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text(index == 0 ? "下一张" : "随后")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(index == 0 ? AppPalette.mint : AppPalette.primary)

                                    Spacer()

                                    Text(card.type.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AppPalette.softMutedText)
                                }

                                Text(card.frontContent)
                                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppPalette.softText)
                                    .lineLimit(3)

                                HStack(spacing: 12) {
                                    MetricCapsule(label: "\(card.errorCount) 次错题", tone: .dark, tint: AppPalette.rose)
                                    MetricCapsule(label: "难度 \(card.difficultyLevel)", tone: .dark, tint: AppPalette.amber)
                                }
                            }
                        }
                    }

                    GlassPanel(tone: .dark, cornerRadius: 28, padding: 22) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("专注信号")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(AppPalette.softText)

                            HStack(spacing: 14) {
                                ReviewSignalTile(
                                    icon: "flame.fill",
                                    value: "\(viewModel.dailyProgress.streakDays)",
                                    label: "连续天数",
                                    tint: AppPalette.mint
                                )

                                ReviewSignalTile(
                                    icon: "brain.head.profile",
                                    value: "\(viewModel.reviewQueue.count)",
                                    label: "待复习",
                                    tint: AppPalette.primary
                                )

                                ReviewSignalTile(
                                    icon: "clock.fill",
                                    value: "\(viewModel.dailyProgress.estimatedDurationMinutes) 分",
                                    label: "专注时长",
                                    tint: AppPalette.cyan
                                )
                            }
                        }
                    }

                    Spacer(minLength: 150)
                }
                .padding(.horizontal, 24)
                .padding(.top, 66)
            }
        }
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $showingSession) {
            ReviewSessionView()
                .environmentObject(viewModel)
        }
    }
}

struct ReviewSignalTile: View {
    let icon: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.softText)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.softMutedText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }
}
