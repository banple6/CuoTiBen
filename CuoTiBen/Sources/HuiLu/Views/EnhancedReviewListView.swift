import SwiftUI

struct EnhancedReviewListView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showingSession = false
    
    private var upcomingCards: [Card] {
        Array(viewModel.reviewQueue.prefix(3))
    }
    
    var body: some View {
        ZStack {
            AuroraBackground(mode: .dark)
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    // Enhanced header
                    enhancedHeader
                    
                    // Today's progress card
                    todayProgressCard
                    
                    // Queue preview
                    queuePreviewSection
                    
                    // Focus signals
                    focusSignalsCard
                    
                    // Study statistics
                    studyStatisticsCard
                    
                    Spacer(minLength: 140)
                }
                .padding(.horizontal, 24)
                .padding(.top, 58)
            }
        }
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $showingSession) {
            ReviewSessionView()
                .environmentObject(viewModel)
        }
    }
    
    // MARK: - Enhanced Header
    
    private var enhancedHeader: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("复习流程")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, EnhancedPalette.cyanGlow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("把今天的待复习内容一次性推进完。")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(EnhancedPalette.secondaryTextDark)
            }
            
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [EnhancedPalette.auroraGreen, EnhancedPalette.cyanGlow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
            }
            .shadow(color: EnhancedPalette.auroraGreen.opacity(0.4), radius: 12, y: 6)
        }
    }
    
    // MARK: - Today's Progress Card
    
    private var todayProgressCard: some View {
        PremiumGlassPanel(tone: .dark, cornerRadius: 32, padding: 26) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("今日待复习", systemImage: "calendar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(EnhancedPalette.primary)
                    
                    Spacer()
                    
                    if viewModel.dailyProgress.pendingReviewsCount > 0 {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(EnhancedPalette.sunsetOrange)
                    }
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(viewModel.dailyProgress.pendingReviewsCount)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, EnhancedPalette.cyanGlow],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("张卡片待处理")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(EnhancedPalette.secondaryTextDark)
                }
                
                Text("预计 \(viewModel.dailyProgress.estimatedDurationMinutes) 分钟完成，建议整段专注推进。")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(EnhancedPalette.tertiaryTextDark)
                    .lineSpacing(3)
                
                ElegantButton(
                    title: "开始沉浸复习",
                    icon: "play.fill",
                    style: .primary,
                    size: .large
                ) {
                    showingSession = true
                }
            }
        }
        .overlay(
            ZStack {
                Circle()
                    .fill(EnhancedPalette.auroraGreen.opacity(0.12))
                    .frame(width: 200, height: 200)
                    .blur(radius: 70)
                    .offset(x: 140, y: -60)
                
                Circle()
                    .fill(EnhancedPalette.cyanGlow.opacity(0.1))
                    .frame(width: 160, height: 160)
                    .blur(radius: 60)
                    .offset(x: -80, y: 80)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .mask(RoundedRectangle(cornerRadius: 32, style: .continuous))
        )
    }
    
    // MARK: - Queue Preview Section
    
    private var queuePreviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ElegantSectionHeader(
                title: "队列预览",
                subtitle: "即将复习的卡片",
                icon: "list.bullet.clipboard",
                accentColor: EnhancedPalette.cyanGlow
            )
            
            VStack(spacing: 12) {
                ForEach(Array(upcomingCards.enumerated()), id: \.element.id) { index, card in
                    EnhancedReviewCard(
                        card: card,
                        index: index,
                        isNext: index == 0
                    )
                }
            }
        }
    }
    
    // MARK: - Focus Signals Card
    
    private var focusSignalsCard: some View {
        PremiumGlassPanel(tone: .dark, cornerRadius: 32, padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                Text("专注信号")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                HStack(spacing: 16) {
                    FocusSignalTile(
                        icon: "flame.fill",
                        value: "\(viewModel.dailyProgress.streakDays)",
                        label: "连续天数",
                        gradient: LinearGradient(
                            colors: [EnhancedPalette.sunsetOrange, EnhancedPalette.magentaDream],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    
                    FocusSignalTile(
                        icon: "brain.head.profile",
                        value: "\(Int(viewModel.dailyProgress.weeklyAccuracy * 100))%",
                        label: "本周正确率",
                        gradient: LinearGradient(
                            colors: [EnhancedPalette.electricBlue, EnhancedPalette.cyanGlow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    
                    FocusSignalTile(
                        icon: "clock.fill",
                        value: "\(viewModel.dailyProgress.totalStudyTimeMinutes)",
                        label: "总时长",
                        gradient: LinearGradient(
                            colors: [EnhancedPalette.auroraGreen, EnhancedPalette.cyanGlow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
        }
    }
    
    // MARK: - Study Statistics Card
    
    private var studyStatisticsCard: some View {
        PremiumGlassPanel(tone: .dark, cornerRadius: 32, padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                Text("学习概览")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                HStack(spacing: 16) {
                    StatMiniCard(
                        icon: "checkmark.seal.fill",
                        title: "已掌握",
                        value: "\(viewModel.totalCardsLearned)",
                        unit: "张卡片",
                        accentColor: EnhancedPalette.auroraGreen
                    )
                    
                    StatMiniCard(
                        icon: "xmark.seal.fill",
                        title: "需加强",
                        value: "\(viewModel.dailyProgress.highErrorChunks.count)",
                        unit: "知识点",
                        accentColor: EnhancedPalette.sunsetOrange
                    )
                }
            }
        }
    }
}

// MARK: - Enhanced Review Card

struct EnhancedReviewCard: View {
    let card: Card
    let index: Int
    let isNext: Bool
    
    var body: some View {
        PremiumGlassPanel(
            tone: .dark,
            cornerRadius: 28,
            padding: 20
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isNext ? EnhancedPalette.auroraGreen : EnhancedPalette.cyanGlow)
                            .frame(width: 8, height: 8)
                        
                        Text(isNext ? "下一张" : "随后")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isNext ? EnhancedPalette.auroraGreen : EnhancedPalette.cyanGlow)
                    }
                    
                    Spacer()
                    
                    Text(card.type.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(EnhancedPalette.tertiaryTextDark)
                }
                
                Text(card.frontContent)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .lineSpacing(3)
                
                HStack(spacing: 10) {
                    ErrorCountBadge(count: card.errorCount)
                    DifficultyBadge(level: card.difficultyLevel)
                }
            }
        }
        .overlay(
            isNext ? AnyView(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(EnhancedPalette.auroraGreen.opacity(0.4), lineWidth: 1.5)
            ) : AnyView(EmptyView()))
    }
}

// MARK: - Error Count Badge

struct ErrorCountBadge: View {
    let count: Int
    
    private var color: Color {
        if count == 0 { return EnhancedPalette.auroraGreen }
        if count < 3 { return EnhancedPalette.sunsetOrange }
        return EnhancedPalette.magentaDream
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
            Text("\(count) 次错题")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color)
        )
    }
}

// MARK: - Difficulty Badge

struct DifficultyBadge: View {
    let level: Int
    
    private var config: (label: String, color: Color) {
        if level <= 2 {
            return ("简单", EnhancedPalette.auroraGreen)
        } else if level <= 4 {
            return ("中等", EnhancedPalette.sunsetOrange)
        } else {
            return ("困难", EnhancedPalette.magentaDream)
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 11, weight: .bold))
            Text("难度 \(config.label)")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(config.color)
        )
    }
}

// MARK: - Focus Signal Tile

struct FocusSignalTile: View {
    let icon: String
    let value: String
    let label: String
    let gradient: LinearGradient
    
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(gradient)
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            .shadow(color: gradient.colors[0].opacity(0.3), radius: 8, y: 4)
            
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(EnhancedPalette.tertiaryTextDark)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(EnhancedPalette.glassDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(EnhancedPalette.glassBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - Stat Mini Card

struct StatMiniCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let accentColor: Color
    
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(accentColor)
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(EnhancedPalette.tertiaryTextDark)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(EnhancedPalette.secondaryTextDark)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(EnhancedPalette.glassDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(EnhancedPalette.glassBorder, lineWidth: 1)
                )
        )
    }
}

#if DEBUG
struct EnhancedReviewListView_Previews: PreviewProvider {
    static var previews: some View {
        EnhancedReviewListView()
            .environmentObject(AppViewModel())
    }
}
#endif
