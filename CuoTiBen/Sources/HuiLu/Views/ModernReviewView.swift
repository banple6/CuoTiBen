import SwiftUI

// MARK: - Modern Review View

struct ModernReviewView: View {
  @EnvironmentObject var viewModel: AppViewModel
  @Environment(\.horizontalSizeClass) var horizontalSizeClass
  
  @State private var selectedFilter: ReviewFilter = .due
  @State private var showingReviewSession = false
  @State private var selectedSubject: Subject?
  
  private var isiPad: Bool {
    horizontalSizeClass == .regular
  }
  
  enum ReviewFilter: String, CaseIterable {
    case all = "全部"
    case due = "待复习"
    case learned = "已掌握"
    case new = "新内容"
  }
  
  var body: some View {
    Group {
      if isiPad {
        iPadGridView
      } else {
        iPhoneListView
      }
    }
    .background(ModernColors.background)
    .fullScreenCover(isPresented: $showingReviewSession) {
      ReviewSessionView()
        .environmentObject(viewModel)
    }
  }
  
  // MARK: - iPad Grid View
  
  private var iPadGridView: some View {
    NavigationView {
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: ModernSpacing.xxl) {
          // Header
          headerSection
          
          // Stats overview
          statsOverviewSection
          
          // Quick actions
          quickActionsSection
          
          // Due cards
          dueCardsSection
          
          // Subjects breakdown
          subjectsBreakdownSection
        }
        .padding(.horizontal, ModernSpacing.xxl)
        .padding(.top, ModernSpacing.lg)
        .padding(.bottom, ModernSpacing.xxxl)
      }
      .background(ModernColors.background)
      .navigationTitle("复习")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          IconButton(
            icon: "gearshape",
            color: ModernColors.primary,
            backgroundColor: ModernColors.surface
          ) {
            print("Settings tapped")
          }
        }
      }
    }
  }
  
  // MARK: - iPhone List View
  
  private var iPhoneListView: some View {
    NavigationView {
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: ModernSpacing.xxl) {
          // Stats overview
          statsOverviewSection
          
          // Quick action
          startReviewButton
          
          // Filter chips
          filterChipsSection
          
          // Due cards list
          dueCardsListSection
        }
        .padding(.horizontal, ModernSpacing.lg)
        .padding(.top, ModernSpacing.lg)
        .padding(.bottom, ModernSpacing.xxxl)
      }
      .background(ModernColors.background)
      .navigationTitle("复习")
      .navigationBarTitleDisplayMode(.large)
    }
  }
  
  // MARK: - Header Section
  
  private var headerSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.sm) {
      Text("复习计划")
        .font(ModernTypography.displaySmall)
        .foregroundColor(ModernColors.textPrimary)
        .fontWeight(.bold)
      
      Text("今天需复习 \(mockDueCount) 张卡片")
        .font(ModernTypography.bodyLarge)
        .foregroundColor(ModernColors.textTertiary)
    }
  }
  
  // MARK: - Stats Overview Section
  
  private var statsOverviewSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "chart.bar",
        title: "学习概览",
        showDivider: true
      )
      
      if isiPad {
        LazyVGrid(columns: ModernLayout.gridColumns4, spacing: ModernSpacing.lg) {
          StatCard(
            icon: "clock",
            value: "\(mockTodayStudyMinutes)",
            label: "今日学习",
            trend: "+12%",
            color: ModernColors.primary
          )
          
          StatCard(
            icon: "checkmark.circle",
            value: "\(mockCompletedCount)",
            label: "已完成",
            trend: "+5%",
            color: ModernColors.accent
          )
          
          StatCard(
            icon: "flame",
            value: "\(mockStreakDays)",
            label: "连续天数",
            trend: nil,
            color: ModernColors.secondary
          )
          
          StatCard(
            icon: "star",
            value: "\(mockMasteredCount)",
            label: "已掌握",
            trend: "+3%",
            color: Color.purple
          )
        }
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: ModernSpacing.lg) {
            StatCard(
              icon: "clock",
              value: "\(mockTodayStudyMinutes)",
              label: "今日学习",
              trend: "+12%",
              color: ModernColors.primary
            )
            
            StatCard(
              icon: "checkmark.circle",
              value: "\(mockCompletedCount)",
              label: "已完成",
              trend: "+5%",
              color: ModernColors.accent
            )
            
            StatCard(
              icon: "flame",
              value: "\(mockStreakDays)",
              label: "连续天数",
              trend: nil,
              color: ModernColors.secondary
            )
            
            StatCard(
              icon: "star",
              value: "\(mockMasteredCount)",
              label: "已掌握",
              trend: "+3%",
              color: Color.purple
            )
          }
        }
      }
    }
  }
  
  // MARK: - Quick Actions Section
  
  private var quickActionsSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "bolt",
        title: "快速开始",
        showDivider: true
      )
      
      HStack(spacing: ModernSpacing.lg) {
        ActionCard(
          icon: "play.circle",
          title: "开始复习",
          subtitle: "\(mockDueCount) 张卡片待复习",
          color: ModernColors.primary
        ) {
          showingReviewSession = true
        }
        
        ActionCard(
          icon: "plus.circle",
          title: "新建卡片",
          subtitle: "手动添加学习内容",
          color: ModernColors.accent
        ) {
          print("Create new card")
        }
      }
    }
  }
  
  // MARK: - Start Review Button (iPhone)
  
  private var startReviewButton: some View {
    PrimaryButton(
      title: "开始复习 (\(mockDueCount))",
      icon: "play.circle",
      action: {
        showingReviewSession = true
      }
    )
  }
  
  // MARK: - Filter Chips Section
  
  private var filterChipsSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "line.3.horizontal.decrease.circle",
        title: "复习内容",
        showDivider: true
      )
      
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: ModernSpacing.sm) {
          ForEach(ReviewFilter.allCases, id: \.rawValue) { filter in
            Chip(
              label: filter.rawValue,
              icon: filter == .due ? "clock" : nil,
              isSelected: selectedFilter == filter,
              color: ModernColors.primary
            ) {
              selectedFilter = filter
            }
          }
        }
      }
    }
  }
  
  // MARK: - Due Cards Section (iPad)
  
  private var dueCardsSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "clock",
        title: "待复习卡片",
        actionTitle: "查看全部",
        showDivider: true
      ) {
        print("View all due cards")
      }
      
      LazyVGrid(columns: ModernLayout.gridColumns2, spacing: ModernSpacing.lg) {
        ForEach(mockDueCards.prefix(4), id: \.id) { card in
          ReviewCardPreview(card: card)
        }
      }
    }
  }
  
  // MARK: - Due Cards List Section (iPhone)
  
  private var dueCardsListSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "clock",
        title: "待复习卡片",
        showDivider: true
      )
      
      VStack(spacing: ModernSpacing.sm) {
        ForEach(mockDueCards.prefix(5), id: \.id) { card in
          ReviewListRow(card: card)
        }
      }
    }
  }
  
  // MARK: - Subjects Breakdown Section
  
  private var subjectsBreakdownSection: some View {
    VStack(alignment: .leading, spacing: ModernSpacing.lg) {
      SectionHeader(
        icon: "rectangle.3.group",
        title: "学科分布",
        showDivider: true
      )
      
      VStack(spacing: ModernSpacing.md) {
        ForEach(mockSubjects, id: \.id) { subject in
          SubjectProgressRow(subject: subject)
        }
      }
    }
  }
  
  // MARK: - Mock Data
  
  private var mockDueCount: Int {
    12 // Replace with viewModel.dueCards.count
  }
  
  private var mockTodayStudyMinutes: Int {
    45 // Replace with viewModel.todayStudyDuration / 60
  }
  
  private var mockCompletedCount: Int {
    28 // Replace with viewModel.todayCompletedCount
  }
  
  private var mockStreakDays: Int {
    7 // Replace with viewModel.streakDays
  }
  
  private var mockMasteredCount: Int {
    156 // Replace with viewModel.masteredCardsCount
  }
  
  private var mockDueCards: [Card] {
    [] // Replace with viewModel.dueCards
  }
  
  private var mockSubjects: [Subject] {
    [
      Subject(id: UUID(), name: "数学", icon: "function", color: "#476BE0"),
      Subject(id: UUID(), name: "物理", icon: "atom", color: "#EB617A"),
      Subject(id: UUID(), name: "化学", icon: "testtube.2", color: "#52C7B8"),
      Subject(id: UUID(), name: "生物", icon: "leaf", color: "#34A853"),
      Subject(id: UUID(), name: "英语", icon: "bubble.left.and.bubble.right", color: "#EA4335")
    ]
  }
}

// MARK: - Review Card Preview

struct ReviewCardPreview: View {
  let card: Card
  
  var body: some View {
    ModernCard(variant: .elevated) {
      VStack(alignment: .leading, spacing: ModernSpacing.md) {
        // Question preview
        Text(card.front ?? "")
          .font(ModernTypography.bodyLarge)
          .foregroundColor(ModernColors.textPrimary)
          .lineLimit(3)
        
        // Metadata
        HStack(spacing: ModernSpacing.sm) {
          Image(systemName: "calendar")
            .font(.system(size: 12, weight: .medium))
          Text("下次复习：今天")
            .font(ModernTypography.caption)
            .foregroundColor(ModernColors.textTertiary)
          
          Spacer()
          
          Image(systemName: "star")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(ModernColors.secondary)
        }
      }
    }
  }
}

// MARK: - Review List Row

struct ReviewListRow: View {
  let card: Card
  
  var body: some View {
    HStack(spacing: ModernSpacing.md) {
      // Icon
      Image(systemName: "circle")
        .font(.system(size: 12, weight: .bold))
        .foregroundColor(ModernColors.primary)
        .frame(width: 40, height: 40)
        .background(
          Circle()
            .fill(ModernColors.primary.opacity(0.1))
        )
      
      // Content
      VStack(alignment: .leading, spacing: 4) {
        Text(card.front ?? "")
          .font(ModernTypography.body)
          .foregroundColor(ModernColors.textPrimary)
          .fontWeight(.medium)
          .lineLimit(2)
        
        Text("下次复习：今天")
          .font(ModernTypography.caption)
          .foregroundColor(ModernColors.textTertiary)
      }
      
      Spacer()
      
      Image(systemName: "chevron.right")
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(ModernColors.textTertiary)
    }
    .padding(ModernSpacing.md)
    .background(ModernColors.surfaceVariant)
    .cornerRadius(ModernCornerRadius.md)
  }
}

// MARK: - Subject Progress Row

struct SubjectProgressRow: View {
  let subject: Subject
  
  var body: some View {
    HStack(spacing: ModernSpacing.md) {
      // Icon
      Image(systemName: subject.icon)
        .font(.system(size: 18, weight: .medium))
        .foregroundColor(Color(hex: subject.color))
        .frame(width: 40, height: 40)
        .background(
          RoundedRectangle(cornerRadius: ModernCornerRadius.md)
            .fill(Color(hex: subject.color).opacity(0.1))
        )
      
      // Subject info
      VStack(alignment: .leading, spacing: 4) {
        Text(subject.name)
          .font(ModernTypography.body)
          .foregroundColor(ModernColors.textPrimary)
          .fontWeight(.medium)
        
        // Progress bar
        GeometryReader { geometry in
          ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: ModernCornerRadius.xs)
              .fill(ModernColors.surfaceVariant)
              .frame(height: 6)
            
            RoundedRectangle(cornerRadius: ModernCornerRadius.xs)
              .fill(Color(hex: subject.color))
              .frame(width: geometry.size.width * 0.6, height: 6)
          }
        }
        .frame(height: 6)
      }
      
      Spacer()
      
      Text("60%")
        .font(ModernTypography.caption)
        .foregroundColor(ModernColors.textTertiary)
    }
  }
}

// MARK: - Preview

#Preview {
  ModernReviewView()
    .environmentObject(AppViewModel())
}
