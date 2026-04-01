import SwiftUI

// MARK: - Workspace Home View
// "今日学习驾驶舱" - 温和玻璃感 + 低饱和蓝灰 + 克制交互

struct WorkspaceHomeView: View {
  @EnvironmentObject var viewModel: AppViewModel
  
  var body: some View {
    ZStack {
      // Background
      WorkspaceColors.backgroundPrimary
        .ignoresSafeArea()
      
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: WorkspaceSpacing.xxl) {
          
          // MARK: - Page Header
          AppPageHeader(
            title: "学习空间",
            subtitle: formattedGreeting,
            trailingActions: [
              ({ print("Settings tapped") }, "设置", Image(systemName: "gearshape"))
            ]
          )
          .padding(.horizontal, WorkspaceLayout.cardHorizontalMarginiPhone)
          
          // MARK: - Today's Stats
          SectionHeader(
            icon: "chart.line.uptrend.xyaxis",
            title: "今日学习",
            showDivider: false
          )
          
          TodayStatsGrid(stats: mockTodayStats)
            .padding(.horizontal, WorkspaceLayout.cardHorizontalMarginiPhone)
          
          // MARK: - Quick Actions
          SectionHeader(
            icon: "bolt.fill",
            title: "快速开始",
            showDivider: false
          )
          
          QuickActionsRow()
            .padding(.horizontal, WorkspaceLayout.cardHorizontalMarginiPhone)
          
          // MARK: - Continue Reading
          SectionHeader(
            icon: "book.open",
            title: "继续阅读",
            actionTitle: "全部",
            action: { print("View all materials") }
          )
          
          RecentMaterialsCarousel(materials: mockMaterials)
            .padding(.horizontal, WorkspaceLayout.cardHorizontalMarginiPhone)
          
          // MARK: - Recent Notes
          SectionHeader(
            icon: "note.text",
            title: "最近笔记",
            actionTitle: "全部",
            action: { print("View all notes") }
          )
          
          RecentNotesList(notes: mockNotes)
            .padding(.horizontal, WorkspaceLayout.cardHorizontalMarginiPhone)
          
          // MARK: - Upcoming Reviews
          SectionHeader(
            icon: "clock.badge.checkmark",
            title: "待复习",
            actionTitle: "\(mockReviews.count)项",
            action: { print("Start review") }
          )
          
          UpcomingReviewsList(reviews: mockReviews)
            .padding(.horizontal, WorkspaceLayout.cardHorizontalMarginiPhone)
          
          // Bottom padding
          Rectangle()
            .fill(Color.clear)
            .frame(height: 40)
        }
      }
    }
  }
  
  // MARK: - Computed Properties
  
  private var formattedGreeting: String {
    let hour = Calendar.current.component(.hour, from: Date())
    switch hour {
    case 5..<12: return "早上好，开始今天的学习吧"
    case 12..<14: return "中午好，休息一下眼睛"
    case 14..<18: return "下午好，保持专注"
    case 18..<22: return "晚上好，巩固今日所学"
    default: return "夜深了，注意休息"
    }
  }
  
  // MARK: - Mock Data (Replace with actual viewModel data)
  
  private var mockTodayStats: TodayLearningStats {
    TodayLearningStats(
      studyDuration: 125,
      materialsRead: 3,
      notesCreated: 7,
      knowledgePointsLearned: 12,
      reviewDue: 8,
      streakDays: 5
    )
  }
  
  private var mockMaterials: [SourceDocument] {
    // Replace with actual data from viewModel
    []
  }
  
  private var mockNotes: [Note] {
    // Replace with actual data from viewModel
    []
  }
  
  private var mockReviews: [ReviewSession] {
    // Replace with actual data from viewModel
    []
  }
}

// MARK: - Today's Stats Grid

struct TodayStatsGrid: View {
  let stats: TodayLearningStats
  
  var body: some View {
    LazyVGrid(columns: [
      GridItem(.flexible(), spacing: WorkspaceSpacing.md),
      GridItem(.flexible(), spacing: WorkspaceSpacing.md)
    ], spacing: WorkspaceSpacing.md) {
      StatCard(
        icon: "timer",
        iconColor: WorkspaceColors.accentIndigo,
        value: formatDuration(stats.studyDuration),
        label: "学习时长"
      )
      
      StatCard(
        icon: "book.fill",
        iconColor: WorkspaceColors.accentTeal,
        value: "\(stats.materialsRead)",
        label: "阅读材料"
      )
      
      StatCard(
        icon: "note.text",
        iconColor: WorkspaceColors.accentTurquoise,
        value: "\(stats.notesCreated)",
        label: "创建笔记"
      )
      
      StatCard(
        icon: "lightbulb.fill",
        iconColor: WorkspaceColors.accentAmber,
        value: "\(stats.knowledgePointsLearned)",
        label: "知识点"
      )
    }
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
}

// MARK: - Stat Card

struct StatCard: View {
  let icon: String
  let iconColor: Color
  let value: String
  let label: String
  
  var body: some View {
    VStack(alignment: .leading, spacing: WorkspaceSpacing.md) {
      Image(systemName: icon)
        .font(.system(size: 20, weight: .semibold))
        .foregroundColor(iconColor)
        .frame(width: 44, height: 44)
        .background(
          RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
            .fill(iconColor.opacity(0.1))
        )
      
      Text(value)
        .font(WorkspaceTypography.displayMedium)
        .foregroundColor(WorkspaceColors.textPrimary)
        .fontWeight(.bold)
      
      HStack(spacing: WorkspaceSpacing.xs) {
        Text(label)
          .font(WorkspaceTypography.label)
          .foregroundColor(WorkspaceColors.textSecondary)
      }
    }
    .padding(WorkspaceSpacing.lg)
    .background(
      RoundedRectangle(cornerRadius: WorkspaceCornerRadius.xl)
        .fill(WorkspaceColors.cardBackground)
    )
    .shadow(color: WorkspaceColors.shadowLight, radius: 10, x: 0, y: 4)
  }
}

// MARK: - Quick Actions Row

struct QuickActionsRow: View {
  var body: some View {
    HStack(spacing: WorkspaceSpacing.md) {
      QuickActionButton(
        icon: "plus.app",
        label: "新建笔记",
        color: WorkspaceColors.accentIndigo
      )
      
      QuickActionButton(
        icon: "book.badge.plus",
        label: "导入资料",
        color: WorkspaceColors.accentTeal
      )
      
      QuickActionButton(
        icon: "brain.head.profile",
        label: "开始复习",
        color: WorkspaceColors.accentAmber
      )
    }
  }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
  let icon: String
  let label: String
  let color: Color
  
  var body: some View {
    Button(action: {}) {
      VStack(spacing: WorkspaceSpacing.sm) {
        Image(systemName: icon)
          .font(.system(size: 22, weight: .semibold))
          .foregroundColor(color)
          .frame(width: 56, height: 56)
          .background(
            Circle()
              .fill(color.opacity(0.1))
          )
        
        Text(label)
          .font(WorkspaceTypography.labelSmall)
          .foregroundColor(WorkspaceColors.textSecondary)
      }
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Recent Materials Carousel

struct RecentMaterialsCarousel: View {
  let materials: [SourceDocument]
  
  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: WorkspaceSpacing.md) {
        ForEach(materials, id: \.id) { material in
          MaterialPreviewCard(material: material)
            .frame(width: 280)
        }
        
        if materials.isEmpty {
          EmptyMaterialPlaceholder()
            .frame(width: 280)
        }
      }
    }
  }
}

// MARK: - Material Preview Card

struct MaterialPreviewCard: View {
  let material: SourceDocument
  
  var body: some View {
    VStack(alignment: .leading, spacing: WorkspaceSpacing.md) {
      RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
        .fill(WorkspaceColors.backgroundSecondary)
        .frame(height: 140)
        .overlay(
          Image(systemName: "doc.fill")
            .font(.system(size: 48, weight: .light))
            .foregroundColor(WorkspaceColors.textPlaceholder)
        )
      
      Text(material.title)
        .font(WorkspaceTypography.headlineSmall)
        .foregroundColor(WorkspaceColors.textPrimary)
        .fontWeight(.semibold)
        .lineLimit(2)
      
      HStack(spacing: WorkspaceSpacing.md) {
        Text(material.pageCount > 0 ? "\(material.pageCount) 页" : "")
          .font(WorkspaceTypography.caption)
          .foregroundColor(WorkspaceColors.textTertiary)
        
        Text("·")
          .font(WorkspaceTypography.caption)
          .foregroundColor(WorkspaceColors.textPlaceholder)
        
        Text("已读 67%")
          .font(WorkspaceTypography.caption)
          .foregroundColor(WorkspaceColors.accentIndigo)
      }
    }
    .padding(WorkspaceSpacing.lg)
    .background(
      RoundedRectangle(cornerRadius: WorkspaceCornerRadius.xl)
        .fill(WorkspaceColors.cardBackground)
    )
    .shadow(color: WorkspaceColors.shadowLight, radius: 10, x: 0, y: 4)
  }
}

// MARK: - Empty Material Placeholder

struct EmptyMaterialPlaceholder: View {
  var body: some View {
    VStack(spacing: WorkspaceSpacing.md) {
      RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
        .fill(WorkspaceColors.backgroundSecondary.opacity(0.5))
        .frame(height: 140)
        .overlay(
          Image(systemName: "book.closed")
            .font(.system(size: 40, weight: .light))
            .foregroundColor(WorkspaceColors.textPlaceholder)
        )
      
      Text("暂无阅读材料")
        .font(WorkspaceTypography.body)
        .foregroundColor(WorkspaceColors.textTertiary)
      
      Text("导入 PDF 或其他资料后，这里会显示阅读进度")
        .font(WorkspaceTypography.caption)
        .foregroundColor(WorkspaceColors.textPlaceholder)
        .multilineTextAlignment(.center)
    }
    .padding(WorkspaceSpacing.lg)
    .background(
      RoundedRectangle(cornerRadius: WorkspaceCornerRadius.xl)
        .fill(WorkspaceColors.cardBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: WorkspaceCornerRadius.xl)
        .strokeBorder(WorkspaceColors.borderLight, lineWidth: 1)
        .strokeStyle(.init(dash: [5, 5]))
    )
  }
}

// MARK: - Recent Notes List

struct RecentNotesList: View {
  let notes: [Note]
  
  var body: some View {
    VStack(spacing: WorkspaceSpacing.sm) {
      ForEach(notes.prefix(3), id: \.id) { note in
        NoteSummaryRow(note: note)
      }
      
      if notes.isEmpty {
        EmptyNotesPlaceholder()
      }
    }
  }
}

// MARK: - Note Summary Row

struct NoteSummaryRow: View {
  let note: Note
  
  var body: some View {
    HStack(spacing: WorkspaceSpacing.md) {
      Image(systemName: "note.text")
        .font(.system(size: 18, weight: .medium))
        .foregroundColor(WorkspaceColors.accentIndigo)
        .frame(width: 40, height: 40)
        .background(
          RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
            .fill(WorkspaceColors.accentIndigo.opacity(0.08))
        )
      
      VStack(alignment: .leading, spacing: 4) {
        Text(note.title ?? "未命名笔记")
          .font(WorkspaceTypography.body)
          .foregroundColor(WorkspaceColors.textPrimary)
          .fontWeight(.medium)
          .lineLimit(1)
        
        Text(formatDate(note.createdAt))
          .font(WorkspaceTypography.caption)
          .foregroundColor(WorkspaceColors.textTertiary)
      }
      
      Spacer()
      
      Text("\(note.blocks.count) 块")
        .font(WorkspaceTypography.caption)
        .foregroundColor(WorkspaceColors.textPlaceholder)
    }
    .padding(.horizontal, WorkspaceSpacing.md)
    .padding(.vertical, WorkspaceSpacing.md)
    .background(
      RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
        .fill(WorkspaceColors.backgroundSecondary.opacity(0.5))
    )
  }
  
  private func formatDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}

// MARK: - Empty Notes Placeholder

struct EmptyNotesPlaceholder: View {
  var body: some View {
    VStack(spacing: WorkspaceSpacing.md) {
      Image(systemName: "note.text")
        .font(.system(size: 40, weight: .light))
        .foregroundColor(WorkspaceColors.textPlaceholder)
      
      Text("还没有笔记")
        .font(WorkspaceTypography.body)
        .foregroundColor(WorkspaceColors.textTertiary)
      
      Text("开始阅读材料或手动创建第一条笔记")
        .font(WorkspaceTypography.caption)
        .foregroundColor(WorkspaceColors.textPlaceholder)
    }
    .padding(WorkspaceSpacing.xxl)
    .frame(maxWidth: .infinity)
    .background(
      RoundedRectangle(cornerRadius: WorkspaceCornerRadius.xl)
        .fill(WorkspaceColors.backgroundSecondary.opacity(0.3))
    )
    .overlay(
      RoundedRectangle(cornerRadius: WorkspaceCornerRadius.xl)
        .strokeBorder(WorkspaceColors.borderLight, lineWidth: 1)
        .strokeStyle(.init(dash: [5, 5]))
    )
  }
}

// MARK: - Upcoming Reviews List

struct UpcomingReviewsList: View {
  let reviews: [ReviewSession]
  
  var body: some View {
    VStack(spacing: WorkspaceSpacing.sm) {
      ForEach(reviews.prefix(3), id: \.id) { review in
        ReviewSummaryRow(review: review)
      }
      
      if reviews.isEmpty {
        EmptyReviewsPlaceholder()
      }
    }
  }
}

// MARK: - Review Summary Row

struct ReviewSummaryRow: View {
  let review: ReviewSession
  
  var body: some View {
    HStack(spacing: WorkspaceSpacing.md) {
      Image(systemName: "clock.badge.checkmark")
        .font(.system(size: 18, weight: .medium))
        .foregroundColor(WorkspaceColors.accentAmber)
        .frame(width: 40, height: 40)
        .background(
          RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
            .fill(WorkspaceColors.accentAmber.opacity(0.08))
        )
      
      VStack(alignment: .leading, spacing: 4) {
        Text("知识点复习")
          .font(WorkspaceTypography.body)
          .foregroundColor(WorkspaceColors.textPrimary)
          .fontWeight(.medium)
        
        Text("\(review.cardsToReview.count) 张卡片待复习")
          .font(WorkspaceTypography.caption)
          .foregroundColor(WorkspaceColors.textTertiary)
      }
      
      Spacer()
      
      Text(review.cardsToReview.count > 10 ? "高优先级" : "普通")
        .font(WorkspaceTypography.captionSmall)
        .foregroundColor(
          review.cardsToReview.count > 10
            ? WorkspaceColors.accentCoral
            : WorkspaceColors.textSecondary
        )
        .padding(.horizontal, WorkspaceSpacing.sm)
        .padding(.vertical, WorkspaceSpacing.xs)
        .background(
          Capsule()
            .fill(
              review.cardsToReview.count > 10
                ? WorkspaceColors.accentCoral.opacity(0.1)
                : WorkspaceColors.backgroundSecondary
            )
        )
    }
    .padding(.horizontal, WorkspaceSpacing.md)
    .padding(.vertical, WorkspaceSpacing.md)
    .background(
      RoundedRectangle(cornerRadius: WorkspaceCornerRadius.lg)
        .fill(WorkspaceColors.backgroundSecondary.opacity(0.5))
    )
  }
}

// MARK: - Empty Reviews Placeholder

struct EmptyReviewsPlaceholder: View {
  var body: some View {
    VStack(spacing: WorkspaceSpacing.md) {
      Image(systemName: "checkmark.circle")
        .font(.system(size: 40, weight: .light))
        .foregroundColor(WorkspaceColors.accentTurquoise)
      
      Text("太棒了！")
        .font(WorkspaceTypography.body)
        .foregroundColor(WorkspaceColors.textPrimary)
        .fontWeight(.medium)
      
      Text("所有复习已完成，继续保持")
        .font(WorkspaceTypography.caption)
        .foregroundColor(WorkspaceColors.textTertiary)
    }
    .padding(WorkspaceSpacing.xxl)
    .frame(maxWidth: .infinity)
    .background(
      RoundedRectangle(cornerRadius: WorkspaceCornerRadius.xl)
        .fill(WorkspaceColors.accentTurquoise.opacity(0.05))
    )
  }
}

// MARK: - Data Model

struct TodayLearningStats {
  var studyDuration: Int // minutes
  var materialsRead: Int
  var notesCreated: Int
  var knowledgePointsLearned: Int
  var reviewDue: Int
  var streakDays: Int
}

// MARK: - Preview

#Preview {
  WorkspaceHomeView()
    .environmentObject(AppViewModel())
}
