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

    // MARK: Product IDs
    static let lifetimeProductID = "com.afzal.ScanHonest.pro.lifetime"
    static let monthlyProductID  = "com.afzal.ScanHonest.pro.monthly"

    private let logger = Logger(subsystem: "com.afzal.ScanHonest", category: "StoreKit")

    /// Background listener for real-time transaction updates
    /// (renewals, revocations, family-sharing grants, Ask-to-Buy approvals).
    /// Started once in init, cancelled in deinit — never duplicated.
    private var transactionListener: Task<Void, Error>?

    // MARK: - Convenience accessors

    /// True if the user has an active Pro entitlement.
    /// Falls back to persisted value when subscription status is still loading
    /// (e.g. cold launch with no network) so the UI never incorrectly downgrades.
    var isPro: Bool { subscriptionStatus.isPro || storedIsPro }

    var lifetimeProduct: Product? { products.first { $0.id == Self.lifetimeProductID } }
    var monthlyProduct:  Product? { products.first { $0.id == Self.monthlyProductID  } }

    // MARK: - Init / Deinit

    init() {
        // Show cached state immediately while real check runs in background
        subscriptionStatus = storedIsPro ? .unknown : .none

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
    /// Guarded so it only hits the network once per session.
    /// Retries automatically if called again after a failure (products stays empty).
    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: [
                Self.lifetimeProductID,
                Self.monthlyProductID
            ])
            logger.info("Loaded \(self.products.count) products")
        } catch {
            // Don't crash — show error in PaywallView
            errorMessage = "Could not load products. Check your connection and try again."
            logger.error("Product load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    /// Initiates a purchase and returns true on success.
    /// Updates subscription status and persists the result.
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let tx = try checkVerified(verification)
                await updateSubscriptionStatus()
                await tx.finish()
                // Persist immediately for offline resilience
                storedIsPro     = true
                purchaseTypeRaw = product.id
                purchaseDateRaw = Date().timeIntervalSince1970
                logger.info("Purchase success: \(product.id)")
                return true

            case .userCancelled:
                return false

            case .pending:
                // Ask-to-Buy — transaction will arrive via transactionListener
                errorMessage = "Purchase is pending approval."
                return false

            @unknown default:
                return false
            }
        } catch {
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
        var newStatus:       SubscriptionStatus = .none
        var foundExpiryDate: Date?              = nil
        var foundRenewalDate: Date?             = nil

        for await result in Transaction.currentEntitlements {
            do {
                let tx = try checkVerified(result)

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
                logger.error("Entitlement check failed: \(error.localizedDescription)")
            }
        }

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

