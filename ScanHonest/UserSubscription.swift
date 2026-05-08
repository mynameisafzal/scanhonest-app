import Foundation

enum SubscriptionTier: String, Codable {
    case free = "free"
    case pro = "pro"
}

enum PurchaseType: String, Codable {
    case oneTime = "com.scanhonest.pro.lifetime"
    case monthly = "com.scanhonest.pro.monthly"
}

struct UserSubscription: Codable {
    var tier: SubscriptionTier
    var purchaseType: PurchaseType?
    var purchaseDate: Date?
    var nextBillingDate: Date?
    var isActive: Bool

    static let free = UserSubscription(
        tier: .free,
        purchaseType: nil,
        purchaseDate: nil,
        nextBillingDate: nil,
        isActive: true
    )

    var isPro: Bool { tier == .pro }

    var displayStatus: String {
        switch tier {
        case .free: return "Free · 5 scans/month"
        case .pro:
            if purchaseType == .oneTime { return "Pro · Lifetime" }
            return "Pro · Monthly"
        }
    }
}
