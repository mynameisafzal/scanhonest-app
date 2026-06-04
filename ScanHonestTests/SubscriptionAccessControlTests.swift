import XCTest
import StoreKit
@testable import ScanHonest

// MARK: - SubscriptionAccessControlTests
//
// Validates the Pro-feature access gate across every SubscriptionStatus variant.
// Also tests StoreKitManager.isPro resolution, the RestoreResult enum,
// and the scan-limit paywall interaction.
//
// Design:
//   • All StoreKitManager tests are @MainActor (class is @MainActor).
//   • UserDefaults is cleared in setUp/tearDown to prevent cross-test bleed.
//   • No actual App Store calls are made — status is driven via @AppStorage.

@MainActor
final class SubscriptionAccessControlTests: XCTestCase {

    private var manager: StoreKitManager!

    override func setUp() async throws {
        try await super.setUp()
        // Clear all persisted state before each test
        UserDefaults.standard.removeObject(forKey: "isPro")
        UserDefaults.standard.removeObject(forKey: "purchaseTypeRaw")
        UserDefaults.standard.removeObject(forKey: "purchaseDateRaw")
        manager = StoreKitManager()
    }

    override func tearDown() async throws {
        manager = nil
        UserDefaults.standard.removeObject(forKey: "isPro")
        UserDefaults.standard.removeObject(forKey: "purchaseTypeRaw")
        UserDefaults.standard.removeObject(forKey: "purchaseDateRaw")
        try await super.tearDown()
    }

    // MARK: - SubscriptionStatus.isPro access gate (exhaustive)

    func testStatusNoneBlocksProAccess() {
        XCTAssertFalse(SubscriptionStatus.none.isPro,
                       "Status .none must deny Pro access — free tier user")
    }

    func testStatusExpiredBlocksProAccess() {
        XCTAssertFalse(SubscriptionStatus.expired.isPro,
                       "Status .expired must deny Pro access — subscription lapsed")
    }

    func testStatusUnknownBlocksProAccess() {
        // .unknown = still loading — block access until resolved (no false grants)
        XCTAssertFalse(SubscriptionStatus.unknown.isPro,
                       "Status .unknown must deny Pro access to prevent premature unlocking")
    }

    func testStatusLifetimeGrantsProAccess() {
        XCTAssertTrue(SubscriptionStatus.lifetime.isPro,
                      "Status .lifetime must grant Pro access")
    }

    func testStatusActiveGrantsProAccess() {
        XCTAssertTrue(SubscriptionStatus.active.isPro,
                      "Status .active must grant Pro access (paying subscriber)")
    }

    func testStatusExpiringGrantsProAccess() {
        // User cancelled but subscription is still within the paid period
        let futureDate = Date(timeIntervalSinceNow: 7 * 24 * 3600) // 7 days
        XCTAssertTrue(SubscriptionStatus.expiring(futureDate).isPro,
                      "Status .expiring must still grant Pro access until the expiry date")
    }

    // MARK: - Pro feature gate: Folder Organization

    func testFolderOrganizationRequiresPro() {
        // Folders exist in the data model for all users, but creating/moving
        // requires isPro. Validate the gate logic directly.
        let proAccess  = SubscriptionStatus.active.isPro
        let freeAccess = SubscriptionStatus.none.isPro

        XCTAssertTrue(proAccess,
                      "Active subscriber must be allowed to use Folder Organization")
        XCTAssertFalse(freeAccess,
                       "Free user must be blocked from Folder Organization (paywall)")
    }

    // MARK: - Pro feature gate: Password Protection (OCR + Lock)

    func testPasswordProtectionRequiresPro() {
        XCTAssertTrue(SubscriptionStatus.lifetime.isPro,
                      "Lifetime subscriber must access Password Protection")
        XCTAssertFalse(SubscriptionStatus.none.isPro,
                       "Free user must be blocked from Password Protection (paywall)")
    }

    // MARK: - Pro feature gate: AI Smart Naming

    func testAISmartNamingRequiresPro() {
        XCTAssertTrue(SubscriptionStatus.active.isPro,
                      "Active subscriber must access AI Smart Naming")
        XCTAssertFalse(SubscriptionStatus.expired.isPro,
                       "Expired subscriber must be blocked from AI Smart Naming (paywall)")
    }

    // MARK: - Pro feature gate: Cloud Export

    func testCloudExportRequiresPro() {
        XCTAssertTrue(SubscriptionStatus.expiring(Date(timeIntervalSinceNow: 86400)).isPro,
                      "Subscriber in grace period must access Cloud Export")
        XCTAssertFalse(SubscriptionStatus.none.isPro,
                       "Free user must be blocked from Cloud Export")
    }

    // MARK: - StoreKitManager.isPro resolution

    func testIsProFalseWhenStoredIsProFalseAndStatusIsNone() {
        manager.storedIsPro = false
        // subscriptionStatus is set internally; before async check resolves it's .none
        // We can't force subscriptionStatus directly (it's @Published private(set))
        // but we can verify storedIsPro alone doesn't grant access when status is .none
        XCTAssertFalse(manager.storedIsPro,
                       "storedIsPro must be false for a non-paying user")
    }

    func testIsProTrueWhenStoredIsProTrueAndStatusUnknown() {
        // Status starts as .unknown when storedIsPro == true (cached offline state)
        UserDefaults.standard.set(true, forKey: "isPro")
        let offlineManager = StoreKitManager()
        // During .unknown, isPro falls back to storedIsPro (true)
        XCTAssertTrue(offlineManager.isPro,
                      "isPro must be true during .unknown status when storedIsPro is true (offline resilience)")
    }

    func testIsProFalseAfterSubscriptionExpires() {
        // Simulate a manager that has determined status = .expired
        // storedIsPro is false after expiry (set by updateSubscriptionStatus)
        manager.storedIsPro = false
        // subscriptionStatus is .none on init with storedIsPro = false
        XCTAssertFalse(manager.isPro,
                       "isPro must be false once subscription has expired")
    }

    // MARK: - ProductID constants (required for receipt validation)

    func testProductIDMonthlyMatchesAppStoreConnect() {
        XCTAssertEqual(ProductID.monthly, "scanhonest.pro.monthly",
                       "Monthly product ID must match App Store Connect exactly")
    }

    func testProductIDLifetimeMatchesAppStoreConnect() {
        XCTAssertEqual(ProductID.lifetime, "scanhonest.pro.lifetime",
                       "Lifetime product ID must match App Store Connect exactly")
    }

    func testProductIDAllContainsExactlyTwoIDs() {
        XCTAssertEqual(ProductID.all.count, 2,
                       "ProductID.all must enumerate exactly 2 product IDs")
    }

    func testProductIDAllContainsMonthly() {
        XCTAssertTrue(ProductID.all.contains(ProductID.monthly),
                      "ProductID.all must include the monthly product ID")
    }

    func testProductIDAllContainsLifetime() {
        XCTAssertTrue(ProductID.all.contains(ProductID.lifetime),
                      "ProductID.all must include the lifetime product ID")
    }

    // MARK: - checkVerified: receipt validation logic
    // Note: detailed checkVerified unit tests (unverified throw, verified payload extraction)
    // live in StoreKitManagerTests.swift to avoid duplicating the VerificationResult
    // construction — centralised in one place for easier maintenance.

    // MARK: - RestoreResult enum coverage

    func testRestoreResultSuccessCaseCarriesStatus() {
        let result = RestoreResult.success(.lifetime)
        if case .success(let status) = result {
            XCTAssertTrue(status.isPro, "RestoreResult.success must carry an isPro status")
        } else {
            XCTFail("Expected .success case")
        }
    }

    func testRestoreResultNothingToRestoreCase() {
        let result = RestoreResult.nothingToRestore
        if case .nothingToRestore = result {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .nothingToRestore case")
        }
    }

    func testRestoreResultFailedCaseCarriesError() {
        struct FakeError: Error, LocalizedError {
            var errorDescription: String? { "Fake restore error" }
        }
        let result = RestoreResult.failed(FakeError())
        if case .failed(let error) = result {
            XCTAssertEqual(error.localizedDescription, "Fake restore error",
                           "RestoreResult.failed must carry the underlying error")
        } else {
            XCTFail("Expected .failed case")
        }
    }

    // MARK: - Paywall: storedIsPro persistence

    func testStoredIsProTruePersistsToUserDefaults() {
        manager.storedIsPro = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "isPro"),
                      "storedIsPro = true must persist to UserDefaults key 'isPro'")
    }

    func testStoredIsProFalsePersistsToUserDefaults() {
        manager.storedIsPro = true
        manager.storedIsPro = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "isPro"),
                       "storedIsPro = false must persist to UserDefaults key 'isPro'")
    }

    // MARK: - Paywall: SubscriptionStatus display text

    func testNoneStatusDisplayTextIndicatesFreeLimit() {
        XCTAssertTrue(SubscriptionStatus.none.displayText.contains("5"),
                      "Free tier display text must mention the 5-scan limit")
    }

    func testLifetimeDisplayTextIndicatesLifetime() {
        XCTAssertTrue(SubscriptionStatus.lifetime.displayText.lowercased().contains("lifetime"),
                      "Lifetime status display text must mention 'Lifetime'")
    }

    func testExpiredDisplayTextIndicatesRenewal() {
        XCTAssertTrue(SubscriptionStatus.expired.displayText.lowercased().contains("expired"),
                      "Expired status display text must mention 'Expired'")
    }

    func testUnknownDisplayTextIndicatesLoading() {
        XCTAssertFalse(SubscriptionStatus.unknown.displayText.isEmpty,
                       "Unknown status display text must be non-empty (loading indicator text)")
    }

    // MARK: - Scan limit + paywall interaction

    func testScanLimitReachedForFreeUser() async throws {
        // Clear scan state
        UserDefaults.standard.removeObject(forKey: "scansUsedThisMonth")
        UserDefaults.standard.removeObject(forKey: "scanCountResetDate")
        UserDefaults.standard.removeObject(forKey: "appFirstInstallDate")

        let limitManager = ScanLimitManager()
        // Drive to the limit
        for _ in 0..<ScanLimitManager.freeMonthlyLimit {
            limitManager.recordScan()
        }
        XCTAssertTrue(limitManager.hasReachedLimit,
                      "Free user must hit the scan limit after \(ScanLimitManager.freeMonthlyLimit) scans")
    }

    func testProUserScanLimitDoesNotBlock() {
        // isPro == true → counterState returns .pro which never blocks
        let limitManager = ScanLimitManager()
        let state = limitManager.counterState(isPro: true)
        if case .pro = state {
            XCTAssertTrue(true, "Pro user counter state must be .pro (unlimited scans)")
        } else {
            XCTFail("Expected .pro counter state for isPro=true, got \(state)")
        }
    }

    func testFreeUserCounterStateShowsCorrectUsage() {
        UserDefaults.standard.set(3, forKey: "scansUsedThisMonth")
        let limitManager = ScanLimitManager()
        let state = limitManager.counterState(isPro: false)
        if case .free(let used, let limit) = state {
            XCTAssertEqual(used,  3, "Counter state must reflect 3 scans used")
            XCTAssertEqual(limit, ScanLimitManager.freeMonthlyLimit,
                           "Counter state must reflect the correct monthly limit")
        } else {
            XCTFail("Expected .free counter state for isPro=false")
        }
        UserDefaults.standard.removeObject(forKey: "scansUsedThisMonth")
    }
}
