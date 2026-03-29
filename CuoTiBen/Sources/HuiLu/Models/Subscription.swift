import Foundation

// MARK: - Subscription Tier
public enum SubscriptionTier: String, Codable {
    case free = "免费版"
    case premium = "订阅版"
    
    public var maxDocuments: Int {
        switch self {
        case .free: return 3
        case .premium: return Int.max
        }
    }
    
    public var maxDailyReviews: Int {
        switch self {
        case .free: return 20
        case .premium: return Int.max
        }
    }
    
    public var hasAdvancedStats: Bool {
        switch self {
        case .free: return false
        case .premium: return true
        }
    }
    
    public var hasOCRBatch: Bool {
        switch self {
        case .free: return false
        case .premium: return true
        }
    }
    
    public var cloudSyncEnabled: Bool {
        switch self {
        case .free: return false
        case .premium: return true
        }
    }
}

// MARK: - Subscription State
/// Tracks user's subscription status
public struct SubscriptionState: Codable {
    public var currentTier: SubscriptionTier
    public var subscribedAt: Date?
    public var expiresAt: Date?
    public var trialEnded: Bool
    public var paywallShownCount: Int
    public var lastPaywallDate: Date?
    
    public init(
        currentTier: SubscriptionTier = .free,
        subscribedAt: Date? = nil,
        expiresAt: Date? = nil,
        trialEnded: Bool = false,
        paywallShownCount: Int = 0,
        lastPaywallDate: Date? = nil
    ) {
        self.currentTier = currentTier
        self.subscribedAt = subscribedAt
        self.expiresAt = expiresAt
        self.trialEnded = trialEnded
        self.paywallShownCount = paywallShownCount
        self.lastPaywallDate = lastPaywallDate
    }
    
    public var isActive: Bool {
        if let expiry = expiresAt {
            return expiry > Date()
        }
        return false
    }
    
    public var daysUntilExpiry: Int? {
        guard let expiry = expiresAt else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
    }
}
