// ProGate.swift
// Target: ScanHonest main app ONLY
#if !WIDGET_EXTENSION

import SwiftUI

// MARK: - ProFeature
//
// Every Pro-only capability in the app, mapped to a canonical identifier.
// This enum is the single source of truth for feature availability.
//
// Graceful-downgrade rules (applied when a subscription expires):
//   • .folderOrganization  — existing folders remain visible; new creation/move blocked
//   • .passwordProtection  — locked documents stay locked; new locking blocked
//   • .aiSmartNaming       — no read-only fallback; feature fully hidden
//   • .homeScreenWidget    — widget shows "Pro Required" placeholder
//   • .cloudExport         — upload blocked at service level; no read-only mode

enum ProFeature: String {
    case folderOrganization = "folder_organization"
    case aiSmartNaming      = "ai_smart_naming"
    case homeScreenWidget   = "home_screen_widget"
    case passwordProtection = "password_protection"
    case cloudExport        = "cloud_export"

    /// Human-readable name for logging / analytics.
    var displayName: String {
        switch self {
        case .folderOrganization: return "Folder Organization"
        case .aiSmartNaming:      return "AI Smart Naming"
        case .homeScreenWidget:   return "Home Screen Widget"
        case .passwordProtection: return "Password Protection"
        case .cloudExport:        return "Cloud Export"
        }
    }

    /// The paywall screen variant to present for this feature.
    var paywallTrigger: PaywallView.PaywallTrigger {
        switch self {
        case .folderOrganization: return .folders
        case .aiSmartNaming:      return .aiNaming
        case .homeScreenWidget:   return .widget
        case .passwordProtection: return .protect
        case .cloudExport:        return .cloudExport
        }
    }

    /// Whether this feature has a meaningful read-only fallback after downgrade.
    /// When `true`, existing content remains accessible but writes are blocked.
    var supportsGracefulReadOnly: Bool {
        switch self {
        case .folderOrganization, .passwordProtection: return true
        case .aiSmartNaming, .homeScreenWidget, .cloudExport: return false
        }
    }
}

// MARK: - ProGateError
//
// Thrown by service-layer methods when a Pro-only operation is attempted by
// a free user who bypassed the UI gate. Callers should catch this and route
// the user to the paywall.

enum ProGateError: LocalizedError {
    case featureRequiresPro(ProFeature)

    var errorDescription: String? {
        switch self {
        case .featureRequiresPro(let f):
            return "\(f.displayName) requires a Pro subscription."
        }
    }

    var feature: ProFeature {
        switch self { case .featureRequiresPro(let f): return f }
    }
}

// MARK: - ProGate
//
// Namespace for all subscription-guard logic.
//
// ## UI layer (SwiftUI views)
//
//   if ProGate.isLocked(.cloudExport, isPro: isPro) {
//       paywallTrigger = .cloudExport; showPaywall = true; return
//   }
//
// ## Service layer (throwing functions / async tasks)
//
//   try ProGate.verify(.folderOrganization, isPro: isPro)
//
// The service-layer variant throws `ProGateError` so callers can display the
// paywall or surface an error without knowing which feature was blocked.

enum ProGate {

    // MARK: - Core predicate

    /// Returns `true` when `feature` is UNAVAILABLE (i.e. user is free).
    /// Use this in `guard` statements to decide whether to show the paywall.
    static func isLocked(_ feature: ProFeature, isPro: Bool) -> Bool {
        !isPro
    }

    // MARK: - Service-level guard (throwing)

    /// Throws `ProGateError.featureRequiresPro` when the feature is locked.
    /// Call at the top of every Pro-only service method.
    ///
    ///     func createFolder(...) throws {
    ///         try ProGate.verify(.folderOrganization, isPro: StoreKitManager.shared.isPro)
    ///         ...
    ///     }
    static func verify(_ feature: ProFeature, isPro: Bool) throws {
        guard isPro else { throw ProGateError.featureRequiresPro(feature) }
    }

    // MARK: - Graceful-downgrade read check

    /// Returns `true` when a user (possibly expired) may still READ this feature's
    /// existing data, even if they cannot write new data.
    ///
    /// Example: folders are always visible after expiry, but creation is blocked.
    static func allowsReadAccess(_ feature: ProFeature, isPro: Bool) -> Bool {
        isPro || feature.supportsGracefulReadOnly
    }

    // MARK: - Convenience paywall trigger

    /// Convenience: returns the `PaywallView.PaywallTrigger` for a feature,
    /// making call sites read as:
    ///
    ///     paywallTrigger = ProGate.paywallTrigger(for: .cloudExport)
    ///
    static func paywallTrigger(for feature: ProFeature) -> PaywallView.PaywallTrigger {
        feature.paywallTrigger
    }
}

// MARK: - ProLockedOverlay
//
// Dims and overlays any view to signal it is Pro-locked.
// Usage:
//
//   SomeView()
//       .proLocked(!isPro)
//
// `ProBadge` and `Color.shGold` are defined in DesignSystem.swift.

struct ProLockedOverlay: ViewModifier {
    let isLocked: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isLocked ? 0.45 : 1.0)
            .overlay(alignment: .topTrailing) {
                if isLocked {
                    ProBadge()
                        .padding(6)
                }
            }
            .allowsHitTesting(!isLocked)   // pass-through when locked — parent handles tap
    }
}

extension View {
    /// Dims the view and overlays a PRO badge when `isLocked` is true.
    /// The view does NOT intercept taps — the parent button/tap gesture
    /// should call the paywall when isLocked.
    func proLocked(_ isLocked: Bool) -> some View {
        modifier(ProLockedOverlay(isLocked: isLocked))
    }
}

#endif
