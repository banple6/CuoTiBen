import Foundation

// MARK: - Daily Progress Summary
/// Aggregated progress data for home screen display
public struct DailyProgress: Codable, Equatable {
    public var date: Date
    public var pendingReviewsCount: Int
    public var estimatedDurationMinutes: Int
    public var completedToday: Int
    public var streakDays: Int
    public var weeklyAccuracy: Double // 0.0 to 1.0
    public var highErrorChunks: [KnowledgeChunkSummary]
    
    public init(
        date: Date = Date(),
        pendingReviewsCount: Int = 0,
        estimatedDurationMinutes: Int = 0,
        completedToday: Int = 0,
        streakDays: Int = 0,
        weeklyAccuracy: Double = 0.0,
        highErrorChunks: [KnowledgeChunkSummary] = []
    ) {
        self.date = date
        self.pendingReviewsCount = pendingReviewsCount
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.completedToday = completedToday
        self.streakDays = streakDays
        self.weeklyAccuracy = weeklyAccuracy
        self.highErrorChunks = highErrorChunks
    }
}

// MARK: - Knowledge Chunk Summary
/// Lightweight summary for displaying in stats
public struct KnowledgeChunkSummary: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var sourceTitle: String
    public var errorFrequency: Int
    
    public init(id: UUID, title: String, sourceTitle: String, errorFrequency: Int) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        self.errorFrequency = errorFrequency
    }
}

// MARK: - Weekly Stats
public struct WeeklyStats: Codable, Equatable {
    public var weekStart: Date
    public var totalCompleted: Int
    public var averageAccuracy: Double
    public var studyDays: Int
    public var totalTimeSpentMinutes: Int
    
    public init(
        weekStart: Date,
        totalCompleted: Int = 0,
        averageAccuracy: Double = 0.0,
        studyDays: Int = 0,
        totalTimeSpentMinutes: Int = 0
    ) {
        self.weekStart = weekStart
        self.totalCompleted = totalCompleted
        self.averageAccuracy = averageAccuracy
        self.studyDays = studyDays
        self.totalTimeSpentMinutes = totalTimeSpentMinutes
    }
}
