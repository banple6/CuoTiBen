import Foundation

// MARK: - Card Type
/// Types of review cards supported in MVP
public enum CardType: String, Codable, CaseIterable {
    case questionAnswer = "问答卡"
    case fillInBlank = "填空卡"
    case trueFalseChoice = "判断/选择卡"
    
    public var displayName: String {
        switch self {
        case .questionAnswer: return "问答卡"
        case .fillInBlank: return "填空卡"
        case .trueFalseChoice: return "判断/选择卡"
        }
    }
}

// MARK: - Review Result
/// User's self-assessment result for a card
public enum ReviewResult: String, Codable {
    case known = "会"
    case vague = "模糊"
    case unknown = "不会"
    
    public var priorityBoost: Int {
        switch self {
        case .known: return 0
        case .vague: return 1
        case .unknown: return 2
        }
    }
    
    public var colorCode: String {
        switch self {
        case .known: return "#34C759" // Green
        case .vague: return "#FF9500" // Orange
        case .unknown: return "#FF3B30" // Red
        }
    }
}

// MARK: - Error Reason Tag
/// Tags for why a card was marked wrong or vague
public enum ErrorReason: String, Codable, CaseIterable {
    case conceptUnclear = "概念模糊"
    case memoryGap = "记忆断裂"
    case confusion = "混淆相近点"
    case careless = "粗心看错"
    
    public var displayName: String {
        return rawValue
    }
}

// MARK: - Card Model
/// Represents a review card generated from a knowledge chunk
public struct Card: Identifiable, Codable, Equatable {
    public var id: UUID
    public var type: CardType
    public var frontContent: String // Question or sentence with blank
    public var backContent: String // Answer
    public var keywords: [String]
    public var knowledgeChunkID: UUID
    public var options: [String]
    public var correctOption: String?
    public var difficultyLevel: Int // 1-5 scale
    public var errorCount: Int
    public var lastReviewedAt: Date?
    public var nextReviewAt: Date?
    public var isActive: Bool
    public var isDraft: Bool
    
    public init(
        id: UUID = UUID(),
        type: CardType,
        frontContent: String,
        backContent: String,
        keywords: [String] = [],
        knowledgeChunkID: UUID,
        options: [String] = [],
        correctOption: String? = nil,
        difficultyLevel: Int = 3,
        errorCount: Int = 0,
        lastReviewedAt: Date? = nil,
        nextReviewAt: Date? = nil,
        isActive: Bool = true,
        isDraft: Bool = false
    ) {
        self.id = id
        self.type = type
        self.frontContent = frontContent
        self.backContent = backContent
        self.keywords = keywords
        self.knowledgeChunkID = knowledgeChunkID
        self.options = options
        self.correctOption = correctOption
        self.difficultyLevel = difficultyLevel
        self.errorCount = errorCount
        self.lastReviewedAt = lastReviewedAt
        self.nextReviewAt = nextReviewAt
        self.isActive = isActive
        self.isDraft = isDraft
    }
    
    /// Calculate priority score for review scheduling
    /// Higher score = higher priority
    public var priorityScore: Int {
        guard isActive else { return -1 }
        
        let baseScore = errorCount * 10
        
        if let nextReview = nextReviewAt {
            let daysUntilDue = Calendar.current.dateComponents([.day], from: Date(), to: nextReview).day ?? 0
            if daysUntilDue <= 0 {
                return baseScore + 100 // Overdue
            } else if daysUntilDue == 1 {
                return baseScore + 50 // Due tomorrow
            }
        }
        
        return baseScore
    }
}
