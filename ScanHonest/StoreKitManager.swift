// StoreKitManager.swift
// Target: ScanHonest main app ONLY
#if !WIDGET_EXTENSION

import StoreKit
import SwiftUI
import Combine
import os.log

// MARK: - SubscriptionStatus

enum SubscriptionStatus: Equatable {
    case none
    case lifetime
    case active
    case expiring(Date)
    case expired
    case unknown

    var displayText: String {
        switch self {
        case .none:              return "Free · 5 scans/month"
        case .lifetime:          return "Pro · Lifetime"
        case .active:            return "Pro · Renews monthly"
        case .expiring(let date):
            let f = DateFormatter(); f.dateStyle = .medium
            return "Cancels \(f.string(from: date))"
        case .expired:           return "Expired · Tap to renew"
        case .unknown:           return "Checking..."
        }
    }

    var isPro: Bool {
        switch self {
        case .lifetime, .active, .expiring: return true
        default:                            return false
        }
    }
}

// MARK: - RestoreResult

enum RestoreResult {
    case success(SubscriptionStatus)
    case nothingToRestore
    case failed(Error)
}

// MARK: - StoreKitError

enum StoreKitError: LocalizedError {
    case verification(Error)
    case productNotFound
    case purchaseFailed(String)

    var errorDescription: String? {
        switch self {
        case .verification(let e):   return "Verification failed: \(e.localizedDescription)"
        case .productNotFound:       return "Product not available."
        case .purchaseFailed(let m): return m
        }
    }
}

// MARK: - Product IDs
//
// Single source of truth for all In-App Purchase identifiers.
// These must match exactly what is configured in App Store Connect.

enum ProductID {
    static let monthly  = "scanhonest.pro.monthly"
    static let lifetime = "scanhonest.pro.lifetime"

    /// All product IDs — passed to Product.products(for:) on launch.
    static let all: Set<String> = [monthly, lifetime]
}

// MARK: - StoreKitManager

@MainActor
class StoreKitManager: ObservableObject {

    // MARK: Persistence — survives app relaunch and offline launches
    @AppStorage("isPro")           var storedIsPro:      Bool   = false
    @AppStorage("purchaseTypeRaw") var purchaseTypeRaw:  String = ""
    @AppStorage("purchaseDateRaw") var purchaseDateRaw:  Double = 0

    // MARK: Published state — drives UI
    @Published var products:              [Product]           = []
    @Published var isLoading:             Bool                = false
    @Published var errorMessage:          String?             = nil
    @Published var subscriptionStatus:    SubscriptionStatus  = .unknown
    @Published var subscriptionExpiryDate: Date?              = nil
    @Published var subscriptionRenewalDate: Date?             = nil
    @Published var isSubscriptionActive:  Bool                = false

    // MARK: Product ID aliases — kept for call-sites that reference Self.*
    static let lifetimeProductID = ProductID.lifetime
    static let monthlyProductID  = ProductID.monthly

    private let logger = Logger(subsystem: "com.afzal.ScanHonest", category: "StoreKit")

    /// Background listener for real-time transaction updates
    /// (renewals, revocations, family-sharing grants, Ask-to-Buy approvals).
    /// Started once in init, cancelled in deinit — never duplicated.
    private var transactionListener: Task<Void, Error>?

    // MARK: - Convenience accessors

    /// True if the user has an active Pro entitlement.
    /// MED-06 FIX: the old implementation OR'd subscriptionStatus.isPro with storedIsPro,
    /// meaning a cancelled monthly subscriber retained Pro access indefinitely while offline.
    /// New logic:
    ///   • Lifetime purchase → storedIsPro is the only offline signal (correct: lifetime never expires)
    ///   • Monthly subscription → use subscriptionStatus exclusively once we have checked;
    ///     fall back to storedIsPro ONLY during the brief .unknown initialisation window
    ///     so the UI doesn't incorrectly downgrade before the first entitlement check completes.
    var isPro: Bool {
        switch subscriptionStatus {
        case .unknown:
            // Still loading — use persisted value to avoid a flash of downgraded UI.
            // For lifetime purchases this is always correct.
            // For monthly: worst case the user sees Pro for <1 s until check completes.
            return storedIsPro
        default:
            // Authoritative result from StoreKit 2 — trust it completely.
            return subscriptionStatus.isPro
        }
    }

    var lifetimeProduct: Product? { products.first { $0.id == Self.lifetimeProductID } }
    var monthlyProduct:  Product? { products.first { $0.id == Self.monthlyProductID  } }

    // MARK: - Init / Deinit

    init() {
        // UITest fast-path: trust UserDefaults directly, skip all StoreKit I/O.
        // updateSubscriptionStatus() would overwrite storedIsPro = false because
        // the UITest sandbox has no real entitlements — this guard prevents that.
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            subscriptionStatus = storedIsPro ? .lifetime : .none
            isLoading = false
            return
        }

        // Show cached state immediately while real check runs in background
        subscriptionStatus = storedIsPro ? .unknown : .none

        // Flag loading immediately so the paywall CTA is disabled before the
        // first Product.products(for:) call completes. Without this there is a
        // brief window where isLoading=false and products=[] — tapping the CTA
        // during that window triggers the "Product not available" error.
        isLoading = true

        // Single transaction listener — handles:
        // • Subscription auto-renewals
        // • Refunds / revocations
        // • Family-sharing purchases
        // • Ask-to-Buy approvals
        transactionListener = Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { break }
                do {
                    // Verify on background, hop to MainActor for state update
                    let tx = try self.checkVerified(result)
                    await self.updateSubscriptionStatus()
                    await tx.finish()
                } catch {
                    // Never grant access on unverified transactions — silently ignore
                }
            }
        }

        // Load products and check entitlements concurrently on launch
        Task { await loadProducts() }
        Task { await updateSubscriptionStatus() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Product Loading

    /// Fetches products from App Store Connect.
    /// Skipped if products are already loaded (call reloadProducts() to force a refresh).
    /// isLoading is set true in init() so the paywall CTA is always disabled
    /// during the fetch window — no race condition possible.
    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            print("[StoreKit] Requesting product IDs:", ProductID.all.sorted())
            let fetched = try await Product.products(for: Array(ProductID.all))

            print("[StoreKit] Requested IDs:", ProductID.all.sorted())
            print("[StoreKit] Returned product count:", fetched.count)
            print("[StoreKit] Returned product IDs:", fetched.map { $0.id })

            for p in fetched {
                print("[StoreKit] ↳ id:", p.id,
                      "| name:", p.displayName,
                      "| price:", p.displayPrice,
                      "| type:", String(describing: p.type))
            }

            if fetched.isEmpty {
                print("""
                [StoreKit] ⚠️ No products returned from App Store Connect.
                  Checklist — verify ALL of the following:
                  1. App Bundle ID in App Store Connect must be: com.afzal.ScanHonest
                  2. In-App Purchase capability must be enabled in the Xcode target
                  3. Paid Apps Agreement, Tax & Banking must be complete in App Store Connect
                  4. Product IDs must match EXACTLY (case-sensitive):
                       \(ProductID.monthly)  → type: Auto-Renewable Subscription
                       \(ProductID.lifetime) → type: Non-Consumable
                  5. Each product must have a price tier, at least one localization, and
                     be set to "Cleared for Sale" in App Store Connect
                  6. For App Store production, IAPs must be submitted and approved alongside
                     (or before) the first app build that references them
                  7. TestFlight uses the sandbox environment automatically — no extra config needed
                  8. Sandbox: sign in with a Sandbox Apple ID in Settings → App Store
                """)
            }

            products = fetched
            logger.info("loadProducts: loaded \(fetched.count) product(s)")
        } catch {
            print("[StoreKit] Product fetch error:", error.localizedDescription)
            logger.error("loadProducts failed: \(error.localizedDescription)")
            errorMessage = "Could not load products. Check your connection and try again."
        }
    }

    /// Clears the product cache and re-fetches from App Store Connect.
    /// Called from the paywall "Try Again" button after a failed or empty load.
    func reloadProducts() async {
        products = []
        await loadProducts()
    }

    // MARK: - Purchase

    /// Initiates a purchase and returns true on success.
    /// Updates subscription status and persists the result.
    func purchase(_ product: Product) async -> Bool {
        print("[StoreKit] Initiating purchase:", product.id)
        print("[StoreKit]   displayName:", product.displayName)
        print("[StoreKit]   displayPrice:", product.displayPrice)
        print("[StoreKit]   type:", String(describing: product.type))
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                print("[StoreKit] Purchase result: success for", product.id)
                do {
                    let tx = try checkVerified(verification)
                    print("[StoreKit] Transaction productID:", tx.productID)
                    print("[StoreKit] Transaction ID:", tx.id)
                    print("[StoreKit] Transaction verification: verified ✓")
                    await updateSubscriptionStatus()
                    await tx.finish()
                    // Persist immediately for offline resilience
                    storedIsPro     = true
                    purchaseTypeRaw = product.id
                    purchaseDateRaw = Date().timeIntervalSince1970
                    logger.info("Purchase success: \(product.id)")
                    return true
                } catch {
                    print("[StoreKit] Transaction verification FAILED:", error.localizedDescription)
                    logger.error("Purchase verification failed: \(error.localizedDescription)")
                    // Do NOT unlock Pro on a failed verification
                    return false
                }

            case .userCancelled:
                print("[StoreKit] Purchase cancelled by user — no error shown")
                return false

            case .pending:
                print("[StoreKit] Purchase pending (Ask-to-Buy or payment processing)")
                errorMessage = "Purchase is pending approval."
                return false

            @unknown default:
                print("[StoreKit] Unknown purchase result")
                return false
            }
        } catch {
            print("[StoreKit] Purchase error:", error.localizedDescription)
            errorMessage = error.localizedDescription
            logger.error("Purchase failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Restore Purchases

    /// Full restore returning a typed result.
    /// Used by SettingsView for toast feedback.
    func restorePurchases() async -> RestoreResult {
        do {
            // AppStore.sync() re-fetches all transactions from Apple servers
            try await AppStore.sync()
            await updateSubscriptionStatus()

            if subscriptionStatus.isPro {
                logger.info("Restore: found active entitlement — \(self.subscriptionStatus.displayText)")
                return .success(subscriptionStatus)
            } else {
                storedIsPro = false
                logger.info("Restore: no active entitlement found")
                return .nothingToRestore
            }
        } catch {
            logger.error("Restore failed: \(error.localizedDescription)")
            return .failed(error)
        }
    }

    /// Fire-and-forget wrapper — sets errorMessage for observers that can't await.
    func restorePurchasesSimple() async {
        let result = await restorePurchases()
        switch result {
        case .nothingToRestore:
            errorMessage = "No previous purchase found on this Apple ID. " +
                           "If you purchased on a different Apple ID, sign in to that account first."
        case .failed(let error):
            errorMessage = error.localizedDescription
        case .success:
            break // UI updates via @Published subscriptionStatus
        }
    }

    // MARK: - Entitlement Check

    /// Re-evaluates current entitlements from StoreKit 2's trusted local cache.
    /// Called on launch, after purchase, after restore, and on each transaction update.
    /// Safe to call multiple times — reads a cached async sequence, not the network.
    func updateSubscriptionStatus() async {
        var newStatus:        SubscriptionStatus = .none
        var foundExpiryDate:  Date?              = nil
        var foundRenewalDate: Date?              = nil
        var entitlementIDs:   [String]           = []

        for await result in Transaction.currentEntitlements {
            do {
                let tx = try checkVerified(result)
                entitlementIDs.append(tx.productID)
                print("[StoreKit] Entitlement:", tx.productID,
                      "| revoked:", tx.revocationDate != nil,
                      "| expires:", tx.expirationDate?.description ?? "n/a")

                // Skip revoked transactions (refunds, family-sharing removals)
                guard tx.revocationDate == nil else { continue }

                if tx.productID == Self.lifetimeProductID {
                    // Lifetime purchase found — highest priority, stop immediately
                    newStatus       = .lifetime
                    purchaseDateRaw = tx.purchaseDate.timeIntervalSince1970
                    break
                }

                if tx.productID == Self.monthlyProductID {
                    guard let expiry = tx.expirationDate else { continue }
                    foundExpiryDate = expiry
                    newStatus       = expiry > Date() ? .active : .expired
                    if expiry > Date() { foundRenewalDate = expiry }
                    // Don't break — continue in case lifetime exists in another entitlement
                }
            } catch {
                print("[StoreKit] Entitlement verification FAILED:", error.localizedDescription)
                logger.error("Entitlement check failed: \(error.localizedDescription)")
            }
        }

        print("[StoreKit] Current entitlement IDs:", entitlementIDs)

        // If monthly is active, check whether user cancelled (willAutoRenew = false)
        if newStatus == .active, let monthly = monthlyProduct, let expiry = foundExpiryDate {
            if let statuses = try? await monthly.subscription?.status {
                for status in statuses {
                    if let info = try? checkVerified(status.renewalInfo),
                       info.willAutoRenew == false {
                        newStatus = .expiring(expiry)
                        break
                    }
                }
            }
        }

        // Commit all state together to minimise partial-update flicker
        subscriptionStatus      = newStatus
        subscriptionExpiryDate  = foundExpiryDate
        subscriptionRenewalDate = foundRenewalDate
        isSubscriptionActive    = newStatus.isPro
        storedIsPro             = newStatus.isPro
        if case .none = newStatus { purchaseTypeRaw = "" }

        NotificationCenter.default.post(name: .subscriptionStatusDidChange, object: nil)
        logger.info("Subscription status updated: \(newStatus.displayText)")
        print("[StoreKit] Subscription status →", newStatus.displayText, "| isPro:", newStatus.isPro)
    }

    // MARK: - Receipt Verification (StoreKit 2 built-in)

    /// Unwraps a VerificationResult, throwing on unverified transactions.
    /// StoreKit 2 verifies receipts locally using Apple's public key —
    /// no server round-trip needed for v1.
    nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw StoreKitError.verification(error)
        case .verified(let safe):
            return safe
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let subscriptionStatusDidChange = Notification.Name("subscriptionStatusDidChange")
}

#endif // !WIDGET_EXTENSION

