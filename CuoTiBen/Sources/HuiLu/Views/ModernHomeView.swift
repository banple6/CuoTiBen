import SwiftUI

// MARK: - Modern Home View 2026
// Redesigned for iPhone & iPad

struct ModernHomeView: View {
  @EnvironmentObject var viewModel: AppViewModel
  @Environment(\.horizontalSizeClass) var horizontalSizeClass
  
  private var isiPad: Bool {
    horizontalSizeClass == .regular
  }
  
  var body: some View {
    ZStack {
      ModernColors.background
        .ignoresSafeArea()
      
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: isiPad ? ModernSpacing.xxxl : ModernSpacing.xxl) {
          
          // Header
          headerSection
            .padding(.horizontal, isiPad ? ModernSpacing.pageMarginiPad : ModernSpacing.pageMarginiPhone)
          
          // Stats Grid
          statsSection
            .padding(.horizontal, isiPad ? ModernSpacing.pageMarginiPad : ModernSpacing.pageMarginiPhone)
          
          // Quick Actions
          quickActionsSection
            .padding(.horizontal, isiPad ? ModernSpacing.pageMarginiPad : ModernSpacing.pageMarginiPhone)
          
          // Continue Reading
          if shouldShowContinueReading {
            continueReadingSection
              .padding(.horizontal, isiPad ? ModernSpacing.pageMarginiPad : ModernSpacing.pageMarginiPhone)
          }
          
          // Recent Notes
          recentNotesSection
            .padding(.horizontal, isiPad ? ModernSpacing.pageMarginiPad : ModernSpacing.pageMarginiPhone)
          
          // Upcoming Reviews
          upcomingReviewsSection
            .padding(.horizontal, isiPad ? ModernSpacing.pageMarginiPad : ModernSpacing.pageMarginiPhone)
          
          // Bottom padding for tab bar
          Rectangle()
            .fill(Color.clear)
            .frame(height: isiPad ? 40 : 100)
        }
      }
    }
    .navigationBarHidden(true)
  }
  
  // MARK: - Header Section
  
  private var headerSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.md) {
      HStack {
        VStack(alignment: .leading, spacing: ModernSpacing.xs) {
          Text(greeting)
            .font(ModernTypography.body)
            .foregroundColor(ModernColors.textSecondary)
          
          Text("学习空间")
            .font(isiPad ? ModernTypography.displayLarge : ModernTypography.displayMedium)
            .foregroundColor(ModernColors.textPrimary)
            .fontWeight(.bold)
        }
        
        Spacer()
        
        // Settings button
        IconButton(
          icon: "gearshape",
          color: ModernColors.textSecondary,
          backgroundColor: ModernColors.surface,
          action: {
            print("Settings tapped")
          }
        )
      }
      
      // Date
      Text(formattedDate)
        .font(ModernTypography.label)
        .foregroundColor(ModernColors.textTertiary)
    }
    .padding(.top, isiPad ? ModernSpacing.xxl : ModernSpacing.lg)
  }
  
  // MARK: - Stats Section
  
  private var statsSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "chart.line.uptrend.xyaxis",
        title: "今日学习",
        showDivider: false
      )
      
      if isiPad {
        // iPad: 4 cards in 2x2 grid
        LazyVGrid(columns: ModernLayout.gridColumns2, spacing: ModernSpacing.md) {
          StatCard(
            icon: "timer",
            value: formatDuration(mockStats.studyDuration),
            label: "学习时长",
            accentColor: ModernColors.primary,
            trend: mockStats.studyDuration > 60 ? "+12%" : nil
          )
          
          StatCard(
            icon: "book.fill",
            value: "\(mockStats.materialsRead)",
            label: "阅读材料",
            accentColor: ModernColors.accent
          )
          
          StatCard(
            icon: "note.text",
            value: "\(mockStats.notesCreated)",
            label: "创建笔记",
            accentColor: ModernColors.success
          )
          
          StatCard(
            icon: "lightbulb.fill",
            value: "\(mockStats.knowledgePointsLearned)",
            label: "知识点",
            accentColor: ModernColors.warning
          )
        }
      } else {
        // iPhone: Horizontal scroll
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: ModernSpacing.md) {
            StatCard(
              icon: "timer",
              value: formatDuration(mockStats.studyDuration),
              label: "学习时长",
              accentColor: ModernColors.primary,
              trend: mockStats.studyDuration > 60 ? "+12%" : nil
            )
            .frame(width: 160)
            
            StatCard(
              icon: "book.fill",
              value: "\(mockStats.materialsRead)",
              label: "阅读材料",
              accentColor: ModernColors.accent
            )
            .frame(width: 160)
            
            StatCard(
              icon: "note.text",
              value: "\(mockStats.notesCreated)",
              label: "创建笔记",
              accentColor: ModernColors.success
            )
            .frame(width: 160)
            
            StatCard(
              icon: "lightbulb.fill",
              value: "\(mockStats.knowledgePointsLearned)",
              label: "知识点",
              accentColor: ModernColors.warning
            )
            .frame(width: 160)
          }
        }
      }
    }
  }
  
  // MARK: - Quick Actions Section
  
  private var quickActionsSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "bolt.fill",
        title: "快速开始",
        showDivider: false
      )
      
      if isiPad {
        HStack(spacing: ModernSpacing.lg) {
          ActionCard(
            icon: "plus.app",
            label: "新建笔记",
            color: ModernColors.primary,
            action: { print("New note") }
          )
          
          ActionCard(
            icon: "book.badge.plus",
            label: "导入资料",
            color: ModernColors.accent,
            action: { print("Import material") }
          )
          
          ActionCard(
            icon: "brain.head.profile",
            label: "开始复习",
            color: ModernColors.warning,
            action: { print("Start review") }
          )
        }
      } else {
        HStack(spacing: ModernSpacing.md) {
          ActionCard(
            icon: "plus.app",
            label: "新建笔记",
            color: ModernColors.primary,
            action: { print("New note") }
          )
          
          ActionCard(
            icon: "book.badge.plus",
            label: "导入资料",
            color: ModernColors.accent,
            action: { print("Import material") }
          )
        }
        
        HStack(spacing: ModernSpacing.md) {
          ActionCard(
            icon: "brain.head.profile",
            label: "开始复习",
            color: ModernColors.warning,
            action: { print("Start review") }
          )
        }
      }
    }
  }
  
  // MARK: - Continue Reading Section
  
  private var shouldShowContinueReading: Bool {
    !mockMaterials.isEmpty
  }
  
  private var continueReadingSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "book.open",
        title: "继续阅读",
        actionTitle: "全部",
        action: { print("View all materials") }
      )
      
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: ModernSpacing.md) {
          ForEach(mockMaterials, id: \.id) { material in
            MaterialCard(material: material)
              .frame(width: isiPad ? 320 : 280)
          }
        }
      }
    }
  }
  
  // MARK: - Recent Notes Section
  
  private var recentNotesSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "note.text",
        title: "最近笔记",
        actionTitle: "全部",
        action: { print("View all notes") }
      )
      
      if mockNotes.isEmpty {
        EmptyState(
          icon: "note.text",
          title: "暂无笔记",
          subtitle: "开始阅读材料或手动创建第一条笔记",
          actionTitle: "新建笔记",
          action: { print("New note") }
        )
        .frame(maxWidth: .infinity)
        .padding(ModernSpacing.xxl)
        .background(ModernColors.surface)
        .cornerRadius(ModernCornerRadius.xl)
      } else {
        VStack(spacing: ModernSpacing.sm) {
          ForEach(mockNotes.prefix(isiPad ? 5 : 3), id: \.id) { note in
            NoteListRow(note: note)
          }
        }
      }
    }
  }
  
  // MARK: - Upcoming Reviews Section
  
  private var upcomingReviewsSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "clock.badge.checkmark",
        title: "待复习",
        actionTitle: "\(mockReviews.count)项",
        action: { print("Start review") }
      )
      
      if mockReviews.isEmpty {
        EmptyState(
          icon: "checkmark.circle",
          title: "太棒了！",
          subtitle: "所有复习已完成，继续保持",
          actionTitle: nil,
          action: nil
        )
        .frame(maxWidth: .infinity)
        .padding(ModernSpacing.xxl)
        .background(ModernColors.successBackground)
        .cornerRadius(ModernCornerRadius.xl)
      } else {
        VStack(spacing: ModernSpacing.sm) {
          ForEach(mockReviews.prefix(isiPad ? 5 : 3), id: \.id) { review in
            ReviewListRow(review: review)
          }
        }
      }
    }
  }
  
  // MARK: - Helper Methods
  
  private var greeting: String {
    let hour = Calendar.current.component(.hour, from: Date())
    switch hour {
    case 5..<12: return "早上好"
    case 12..<14: return "中午好"
    case 14..<18: return "下午好"
    case 18..<22: return "晚上好"
    default: return "夜深了"
    }
  }
  
  private var formattedDate: String {
    let formatter = DateFormatter()
    formatter.dateStyle = .full
    formatter.timeStyle = .none
    return formatter.string(from: Date())
  }
  
  private func formatDuration(_ minutes: Int) -> String {
    if minutes >= 60 {
      let hours = minutes / 60
      let mins = minutes % 60
      return "\(hours)小时\(mins)分"
    } else {
      return "\(minutes)分钟"
    }
  }
  
  // MARK: - Mock Data (Replace with ViewModel data)
  
  private var mockStats: TodayLearningStats {
    TodayLearningStats(
      studyDuration: 135,
      materialsRead: 3,
      notesCreated: 7,
      knowledgePointsLearned: 12,
      reviewDue: 8,
      streakDays: 5
    )
  }
  
  private var mockMaterials: [SourceDocument] {
    [] // Replace with viewModel.materials
  }
  
  private var mockNotes: [Note] {
    [] // Replace with viewModel.recentNotes
  }
  
  private var mockReviews: [ReviewSession] {
    [] // Replace with viewModel.upcomingReviews
  }
}

// MARK: - Material Card

struct MaterialCard: View {
  let material: SourceDocument
  
  var body: some View {
    ModernCard(variant: .elevated) {
      VStack(alignment: .leading, spacing: ModernSpacing.md) {
        // Thumbnail
        RoundedRectangle(cornerRadius: ModernCornerRadius.md)
          .fill(ModernColors.surfaceVariant)
          .frame(height: 140)
          .overlay(
            Image(systemName: "doc.fill")
              .font(.system(size: 48, weight: .light))
              .foregroundColor(ModernColors.textTertiary)
          )
        
        // Title
        Text(material.title)
          .font(ModernTypography.titleMedium)
          .foregroundColor(ModernColors.textPrimary)
          .fontWeight(.semibold)
          .lineLimit(2)
        
        // Metadata
        HStack(spacing: ModernSpacing.md) {
          Text(material.pageCount > 0 ? "\(material.pageCount) 页" : "")
            .font(ModernTypography.caption)
            .foregroundColor(ModernColors.textTertiary)
          
          Text("·")
            .font(ModernTypography.caption)
            .foregroundColor(ModernColors.textPlaceholder)
          
          Text("已读 67%")
            .font(ModernTypography.caption)
            .foregroundColor(ModernColors.primary)
            .fontWeight(.medium)
        }
      }
    }
  }
}

// MARK: - Note List Row

struct NoteListRow: View {
  let note: Note
  
  var body: some View {
    ModernCard(variant: .outlined) {
      HStack(spacing: ModernSpacing.md) {
        // Icon
        Image(systemName: "note.text")
          .font(.system(size: 18, weight: .medium))
          .foregroundColor(ModernColors.primary)
          .frame(width: 44, height: 44)
          .background(
            RoundedRectangle(cornerRadius: ModernCornerRadius.lg)
              .fill(ModernColors.primary.opacity(0.1))
          )
        
        // Content
        VStack(alignment: .leading, spacing: 4) {
          Text(note.title ?? "未命名笔记")
            .font(ModernTypography.titleMedium)
            .foregroundColor(ModernColors.textPrimary)
            .fontWeight(.medium)
            .lineLimit(1)
          
          Text(formatDate(note.createdAt))
            .font(ModernTypography.caption)
            .foregroundColor(ModernColors.textTertiary)
        }
        
        Spacer()
        
        // Block count
        Text("\(note.blocks.count) 块")
          .font(ModernTypography.caption)
          .foregroundColor(ModernColors.textTertiary)
      }
    }
  }
  
  private func formatDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}

// MARK: - Review List Row

struct ReviewListRow: View {
  let review: ReviewSession
  
  var body: some View {
    ModernCard(variant: .outlined) {
      HStack(spacing: ModernSpacing.md) {
        // Icon
        Image(systemName: "clock.badge.checkmark")
          .font(.system(size: 18, weight: .medium))
          .foregroundColor(ModernColors.warning)
          .frame(width: 44, height: 44)
          .background(
            RoundedRectangle(cornerRadius: ModernCornerRadius.lg)
              .fill(ModernColors.warning.opacity(0.1))
          )
        
        // Content
        VStack(alignment: .leading, spacing: 4) {
          Text("知识点复习")
            .font(ModernTypography.titleMedium)
            .foregroundColor(ModernColors.textPrimary)
            .fontWeight(.medium)
          
          Text("\(review.cardsToReview.count) 张卡片待复习")
            .font(ModernTypography.caption)
            .foregroundColor(ModernColors.textTertiary)
        }
        
        Spacer()
        
        // Priority badge
        Text(review.cardsToReview.count > 10 ? "高优先级" : "普通")
          .font(ModernTypography.captionSmall)
          .foregroundColor(
            review.cardsToReview.count > 10
              ? ModernColors.error
              : ModernColors.textSecondary
          )
          .padding(.horizontal, ModernSpacing.sm)
          .padding(.vertical, ModernSpacing.xs)
          .background(
            Capsule()
              .fill(
                review.cardsToReview.count > 10
                  ? ModernColors.error.opacity(0.1)
                  : ModernColors.surfaceVariant
              )
          )
      }
    }
  }
}

// MARK: - Data Model

struct TodayLearningStats {
  var studyDuration: Int
  var materialsRead: Int
  var notesCreated: Int
  var knowledgePointsLearned: Int
  var reviewDue: Int
  var streakDays: Int
}

// MARK: - Preview

#Preview {
  NavigationView {
    ModernHomeView()
      .environmentObject(AppViewModel())
  }
}
