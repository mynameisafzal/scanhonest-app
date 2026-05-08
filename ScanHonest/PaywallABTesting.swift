// PaywallABTesting.swift
// Target: ScanHonest main app ONLY
// The #if guard below prevents this file from compiling into the widget
// target if it was accidentally added, which would cause the linker error:
// "Command Ld failed with nonzero exit code"

#if !WIDGET_EXTENSION

import Foundation
import UIKit

// MARK: - PaywallVariant

enum PaywallVariant: String, CaseIterable {
    case variantA = "A"  // one-time card first (default)
    case variantB = "B"  // monthly card first, highlighted
    case variantC = "C"  // feature-focused hero, price below

    var displayName: String {
        switch self {
        case .variantA: return "One-time first"
        case .variantB: return "Monthly first"
        case .variantC: return "Feature hero"
        }
    }
}

// MARK: - PaywallABTesting

final class PaywallABTesting {
    static let shared = PaywallABTesting()
    private init() {}

    /// Deterministic — same device always gets same variant
    var currentVariant: PaywallVariant {
        let id   = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let hash = abs(id.hashValue) % PaywallVariant.allCases.count
        return PaywallVariant.allCases[hash]
    }

    // MARK: - Tracking

    func recordImpression(variant: PaywallVariant, trigger: String) {
        let key     = "impression_\(variant.rawValue)"
        let current = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(current + 1, forKey: key)

        let triggerKey   = "trigger_\(trigger)_\(variant.rawValue)"
        let triggerCount = UserDefaults.standard.integer(forKey: triggerKey)
        UserDefaults.standard.set(triggerCount + 1, forKey: triggerKey)
    }

    func recordConversion(variant: PaywallVariant, product: String) {
        let key     = "conversion_\(variant.rawValue)"
        let current = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(current + 1, forKey: key)

        let productKey   = "conversion_product_\(product)"
        let productCount = UserDefaults.standard.integer(forKey: productKey)
        UserDefaults.standard.set(productCount + 1, forKey: productKey)
    }

    // MARK: - Analytics

    func conversionRate(for variant: PaywallVariant? = nil) -> Double {
        let v           = variant ?? currentVariant
        let impressions = UserDefaults.standard.integer(forKey: "impression_\(v.rawValue)")
        let conversions = UserDefaults.standard.integer(forKey: "conversion_\(v.rawValue)")
        guard impressions > 0 else { return 0 }
        return Double(conversions) / Double(impressions)
    }

    func impressionCount(for variant: PaywallVariant) -> Int {
        UserDefaults.standard.integer(forKey: "impression_\(variant.rawValue)")
    }

    func conversionCount(for variant: PaywallVariant) -> Int {
        UserDefaults.standard.integer(forKey: "conversion_\(variant.rawValue)")
    }

    var debugSummary: String {
        PaywallVariant.allCases.map { v in
            let imp  = impressionCount(for: v)
            let conv = conversionCount(for: v)
            let rate = imp > 0 ? String(format: "%.1f%%", conversionRate(for: v) * 100) : "–"
            return "[\(v.rawValue)] \(imp) imp · \(conv) conv · \(rate)"
        }.joined(separator: "\n")
    }
}

#endif // !WIDGET_EXTENSION
