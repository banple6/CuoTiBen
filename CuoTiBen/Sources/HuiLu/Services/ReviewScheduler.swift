import Foundation

// MARK: - Review Scheduler Protocol
public protocol ReviewSchedulerProtocol {
    func scheduleNextReview(for card: Card, result: ReviewResult) -> Date
    func getDueCards(limit: Int) async throws -> [Card]
    func rescheduleAllOverdueCards() async throws
}

// MARK: - Spaced Repetition Algorithm Configuration
/// Configuration for spaced repetition intervals
public struct SRSConfig {
    public var baseIntervalDays: Double
    public var easeFactor: Double
    public var minimumInterval: Double
    public var maximumInterval: Double
    public var penaltyMultiplier: Double
    
    /// Default configuration optimized for language/exam preparation
    public static let `default` = SRSConfig(
        baseIntervalDays: 1.0,
        easeFactor: 2.5,
        minimumInterval: 1.0,
        maximumInterval: 365.0,
        penaltyMultiplier: 0.7
    )
    
    /// Aggressive schedule for cram sessions (exam prep)
    public static let aggressive = SRSConfig(
        baseIntervalDays: 0.5,
        easeFactor: 2.0,
        minimumInterval: 0.5,
        maximumInterval: 90.0,
        penaltyMultiplier: 0.5
    )
}

// MARK: - Review Scheduler Implementation
/// Implements spaced repetition algorithm for optimal review timing
public final class ReviewScheduler: ReviewSchedulerProtocol {
    
    private let config: SRSConfig
    
    public init(config: SRSConfig = .default) {
        self.config = config
    }
    
    // MARK: - Schedule Next Review
    
    public func scheduleNextReview(for card: Card, result: ReviewResult) -> Date {
        let intervalDays = calculateInterval(card: card, result: result)
        
        let calendar = Calendar.current
        guard let nextDate = calendar.date(byAdding: .day, value: Int(intervalDays), to: Date()) else {
            return Date().addingTimeInterval(86400) // Fallback: 1 day
        }
        
        return nextDate
    }
    
    // MARK: - Get Due Cards
    
    public func getDueCards(limit: Int = 20) async throws -> [Card] {
        // Would query database for cards where nextReviewAt <= now
        // Placeholder implementation
        return []
    }
    
    public func rescheduleAllOverdueCards() async throws {
        // Would bulk-reschedule overdue cards with reduced intervals
        // Placeholder
    }
    
    // MARK: - Interval Calculation Logic
    
    /// Calculate next interval based on SM-2 inspired algorithm
    private func calculateInterval(card: Card, result: ReviewResult) -> Double {
        let errorCount = card.errorCount
        let previousErrors = errorCount
        
        switch result {
        case .known:
            // Success: increase interval exponentially
            let easeBonus = pow(config.easeFactor, Double(previousErrors + 1))
            let newInterval = config.baseIntervalDays * easeBonus
            
            return min(newInterval, config.maximumInterval)
            
        case .vague:
            // Partial recall: modest increase or reset
            if previousErrors == 0 {
                return config.baseIntervalDays * 1.5
            } else {
                return config.baseIntervalDays * config.penaltyMultiplier
            }
            
        case .unknown:
            // Failure: reset to minimum interval with penalty
            let penalizedBase = config.baseIntervalDays * config.penaltyMultiplier
            return max(penalizedBase, config.minimumInterval)
        }
    }
    
    // MARK: - Priority Score Calculation
    
    /// Calculate priority score for sorting due cards
    public func calculatePriorityScore(for card: Card) -> Int {
        guard let nextReview = card.nextReviewAt else {
            return 100 // Unknown urgency = high priority
        }
        
        let daysUntilDue = Calendar.current.dateComponents([.day], from: Date(), to: nextReview).day ?? 0
        
        if daysUntilDue < 0 {
            // Overdue: priority increases with each day overdue
            return abs(daysUntilDue) * 20 + card.errorCount * 10
        } else if daysUntilDue == 0 {
            // Due today
            return 50 + card.errorCount * 10
        } else {
            // Future: lower priority
            return max(0, 30 - daysUntilDue * 5) + card.errorCount * 5
        }
    }
}

// MARK: - Review Statistics Calculator

extension ReviewScheduler {
    /// Estimate time needed for reviewing given cards
    public func estimateReviewDuration(cardsCount: Int) -> TimeInterval {
        // Average 15 seconds per card (reading + thinking + rating)
        return TimeInterval(cardsCount) * 15.0
    }
    
    /// Convert duration to human-readable format
    public func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes)分钟"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)小时\(remainingMinutes)分钟"
        }
    }
}
