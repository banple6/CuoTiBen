import Foundation

// MARK: - Review Session Model
/// Represents a single review session (a batch of cards reviewed together)
public struct ReviewSession: Identifiable, Codable, Equatable {
    public var id: UUID
    public var startTime: Date
    public var endTime: Date?
    public var completedCardsCount: Int
    public var totalCardsCount: Int
    public var correctRate: Double // 0.0 to 1.0
    public var sessionType: SessionType
    
    public init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        endTime: Date? = nil,
        completedCardsCount: Int = 0,
        totalCardsCount: Int = 0,
        correctRate: Double = 0.0,
        sessionType: SessionType = .dailyReview
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.completedCardsCount = completedCardsCount
        self.totalCardsCount = totalCardsCount
        self.correctRate = correctRate
        self.sessionType = sessionType
    }
    
    /// Duration in minutes
    public var durationMinutes: Int? {
        guard let end = endTime else { return nil }
        return Int(end.timeIntervalSince(startTime) / 60)
    }
}

// MARK: - Session Type
public enum SessionType: String, Codable {
    case dailyReview = "每日回炉"
    case extraPractice = "额外练习"
    case errorReview = "错题再压"
    case initialLearn = "初次学习"
}

// MARK: - Review Result Record
/// Records a single card's review result
public struct ReviewResultRecord: Identifiable, Codable, Equatable {
    public var id: UUID
    public var cardID: UUID
    public var sessionID: UUID
    public var result: ReviewResult
    public var responseTime: TimeInterval // Time spent in seconds
    public var errorReason: ErrorReason?
    public var recordedAt: Date
    
    public init(
        id: UUID = UUID(),
        cardID: UUID,
        sessionID: UUID,
        result: ReviewResult,
        responseTime: TimeInterval = 0,
        errorReason: ErrorReason? = nil,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.cardID = cardID
        self.sessionID = sessionID
        self.result = result
        self.responseTime = responseTime
        self.errorReason = errorReason
        self.recordedAt = recordedAt
    }
}
