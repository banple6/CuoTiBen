import SwiftUI

// MARK: - Enhanced Home View (Workspace Redesign)
// "今日学习驾驶舱" - 清晰的学习状态概览 + 快速入口
// 温和玻璃感 + 低饱和蓝灰 + 克制交互

struct EnhancedHomeView: View {
  @EnvironmentObject var viewModel: AppViewModel
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
    
    // MARK: - Enhanced Header
    
    private var enhancedHeader: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(greeting)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(EnhancedPalette.secondaryTextDark)
                
                Text(userName)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, EnhancedPalette.cyanGlow.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text(encouragementMessage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(EnhancedPalette.tertiaryTextDark)
                    .lineSpacing(2)
            }
            
            Spacer()
            
            VStack(spacing: 12) {
                // Quick actions
                HStack(spacing: 8) {
                    HeaderActionButton(icon: "note.text", title: "笔记") {
                        showsNotesHome = true
                    }
                    
                    HeaderActionButton(icon: "gearshape.fill", title: "设置") {
                        showsSettings = true
                    }
                }
                
                // Mastery ring
                enhancedMasteryRing
            }
        }
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "早上好"
        case 12..<18: return "下午好"
        default: return "晚上好"
        }
    }
    
    private var userName: String {
        "博雨"
    }
    
    private var encouragementMessage: String {
        "今天继续把薄弱知识点一点点补齐。"
    }
    
    // MARK: - Enhanced Mastery Ring
    
    private var enhancedMasteryRing: some View {
        ZStack {
            Circle()
                .stroke(EnhancedPalette.glassBorder, lineWidth: 10)
                .frame(width: 92, height: 92)
            
            Circle()
                .trim(from: 0, to: max(min(viewModel.progressPercentage, 1), 0.05))
                .stroke(
                    LinearGradient(
                        colors: [EnhancedPalette.auroraGreen, EnhancedPalette.cyanGlow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: EnhancedPalette.auroraGreen.opacity(0.4), radius: 8, y: 4)
            
            VStack(spacing: 2) {
                Text("\(masteryValue)%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("掌握")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(EnhancedPalette.secondaryTextDark)
            }
        }
        .padding(8)
        .background(
            Circle()
                .fill(EnhancedPalette.glassDark)
                .background(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .stroke(EnhancedPalette.glassBorder.opacity(0.4), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Start Review Button
    
    private var enhancedStartReviewButton: some View {
        PremiumGlassPanel(tone: .dark, cornerRadius: 32, padding: 0) {
            Button(action: { showingReview = true }) {
                HStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("开始今天的复习")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("\(viewModel.dailyProgress.pendingReviewsCount) 张卡片 · 预计 \(viewModel.dailyProgress.estimatedDurationMinutes) 分钟")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(EnhancedPalette.secondaryTextDark)
                    }
                    
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [EnhancedPalette.electricBlue, EnhancedPalette.cyanGlow],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                        
                        Image(systemName: "play.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: 2)
                    }
                    .shadow(color: EnhancedPalette.electricBlue.opacity(0.4), radius: 12, y: 6)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 26)
            }
            .buttonStyle(.plain)
        }
        .overlay(
            ZStack {
                Circle()
                    .fill(EnhancedPalette.electricBlue.opacity(0.15))
                    .frame(width: 180, height: 180)
                    .blur(radius: 60)
                    .offset(x: 120, y: -40)
                
                Circle()
                    .fill(EnhancedPalette.cyanGlow.opacity(0.12))
                    .frame(width: 140, height: 140)
                    .blur(radius: 50)
                    .offset(x: -60, y: 60)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .mask(RoundedRectangle(cornerRadius: 32, style: .continuous))
        )
    }
    
    // MARK: - Stats Overview
    
    private var statsOverviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ElegantSectionHeader(
                title: "学习统计",
                subtitle: "持续积累，每天进步一点点",
                icon: "chart.bar.fill",
                accentColor: EnhancedPalette.electricBlue
            )
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    StatCard(
                        icon: "flame.fill",
                        title: "连续学习",
                        value: "\(viewModel.dailyProgress.streakDays) 天",
                        gradient: LinearGradient(
                            colors: [EnhancedPalette.sunsetOrange, EnhancedPalette.magentaDream],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    
                    StatCard(
                        icon: "bolt.fill",
                        title: "累计经验",
                        value: "\(viewModel.totalCardsLearned * 52)",
                        gradient: LinearGradient(
                            colors: [EnhancedPalette.electricBlue, EnhancedPalette.cyanGlow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    
                    StatCard(
                        icon: "clock.fill",
                        title: "投入时长",
                        value: "3h 20m",
                        gradient: LinearGradient(
                            colors: [EnhancedPalette.auroraGreen, EnhancedPalette.cyanGlow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    
                    StatCard(
                        icon: "target",
                        title: "本周正确率",
                        value: "\(Int(viewModel.dailyProgress.weeklyAccuracy * 100))%",
                        gradient: LinearGradient(
                            colors: [EnhancedPalette.magentaDream, EnhancedPalette.sunsetOrange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
                .padding(.horizontal, 2)
            }
        }
    }
    
    // MARK: - Workbench Section
    
    private var workbenchSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("继续复盘")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("我的英语资料")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(EnhancedPalette.tertiaryTextDark)
            }
            
            let documents = viewModel.englishDocumentsForWorkbench()
            
            if documents.isEmpty {
                PremiumGlassPanel(tone: .dark, cornerRadius: 28, padding: 24) {
                    HStack(spacing: 16) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(EnhancedPalette.tertiaryTextDark)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("暂无学习资料")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(EnhancedPalette.secondaryTextDark)
                            
                            Text("导入英语资料后，这里会保留你的上次学习位置")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(EnhancedPalette.tertiaryTextDark)
                        }
                    }
                }
            } else {
                VStack(spacing: 14) {
                    ForEach(documents.prefix(3)) { document in
                        EnhancedWorkbenchCard(
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
    
    // MARK: - Weak Points Section
    
    private var weakPointsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ElegantSectionHeader(
                title: "薄弱点",
                subtitle: "重点突破这些高频错题",
                icon: "exclamationmark.triangle.fill",
                accentColor: EnhancedPalette.sunsetOrange
            )
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(viewModel.dailyProgress.highErrorChunks.prefix(5)) { chunk in
                        EnhancedWeakPointCard(chunk: chunk)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
    
    // MARK: - Daily Focus Card
    
    private var dailyFocusCard: some View {
        PremiumGlassPanel(tone: .dark, cornerRadius: 32, padding: 26) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("今日专注", systemImage: "brain.head.profile")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    ModernChip(text: "\(masteryValue)% 掌握度", icon: "checkmark.circle.fill", accentColor: EnhancedPalette.auroraGreen)
                }
                
                Text("先处理高错误率知识块，再把今天剩余复习卡片顺着推进，节奏会更稳。")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(EnhancedPalette.secondaryTextDark)
                    .lineSpacing(4)
                
                HStack(spacing: 10) {
                    InfoChip(icon: "doc.text.fill", text: "\(viewModel.dailyProgress.pendingReviewsCount) 张卡片")
                    InfoChip(icon: "clock", text: "\(viewModel.dailyProgress.estimatedDurationMinutes) 分钟")
                    InfoChip(icon: "sparkles", text: "智能混排")
                }
            }
        }
    }
}

// MARK: - Supporting Components

struct HeaderActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(EnhancedPalette.glassDark)
                    .overlay(
                        Capsule()
                            .stroke(EnhancedPalette.glassBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let gradient: LinearGradient
    
    var body: some View {
        PremiumGlassPanel(tone: .dark, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(gradient)
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(EnhancedPalette.tertiaryTextDark)
                    
                    Text(value)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 156, alignment: .leading)
        }
    }
}

struct EnhancedWorkbenchCard: View {
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
        PremiumGlassPanel(tone: .dark, cornerRadius: 28, padding: 22) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [EnhancedPalette.electricBlue, EnhancedPalette.cyanGlow],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "character.book.closed.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .shadow(color: EnhancedPalette.electricBlue.opacity(0.3), radius: 8, y: 4)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(document.title)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        
                        Text("上次学习 \(lastStudyText)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(EnhancedPalette.tertiaryTextDark)
                    }
                    
                    Spacer()
                    
                    ModernChip(text: "\(masteryValue)% 掌握度", icon: "chart.line.uptrend.xyaxis", accentColor: EnhancedPalette.auroraGreen)
                }
                
                HStack(spacing: 10) {
                    InfoChip(icon: "text.quote", text: "已学 \(learnedSentenceCount) 句")
                    InfoChip(icon: "bookmark.fill", text: progress.lastAnchorLabel)
                }
                
                Button(action: action) {
                    HStack(spacing: 10) {
                        Text("继续复盘")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [EnhancedPalette.electricBlue, EnhancedPalette.cyanGlow],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: EnhancedPalette.electricBlue.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct EnhancedWeakPointCard: View {
    let chunk: KnowledgeChunkSummary
    
    var body: some View {
        PremiumGlassPanel(tone: .dark, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [EnhancedPalette.sunsetOrange, EnhancedPalette.magentaDream],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                    
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text(chunk.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(chunk.sourceTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(EnhancedPalette.tertiaryTextDark)
                        .lineLimit(1)
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(EnhancedPalette.glassDark)
                                .frame(height: 6)
                            
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [EnhancedPalette.sunsetOrange, EnhancedPalette.magentaDream],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: min(CGFloat(chunk.errorFrequency) * 32, 92), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
            .frame(width: 172, alignment: .leading)
        }
    }
}

struct InfoChip: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(EnhancedPalette.secondaryTextDark)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(EnhancedPalette.glassDark)
                .overlay(
                    Capsule()
                        .stroke(EnhancedPalette.glassBorder.opacity(0.5), lineWidth: 1)
                )
        )
    }
}

#if DEBUG
struct EnhancedHomeView_Previews: PreviewProvider {
    static var previews: some View {
        EnhancedHomeView()
            .environmentObject(AppViewModel())
    }
}
#endif
