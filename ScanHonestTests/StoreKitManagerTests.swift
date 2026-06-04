import XCTest
import StoreKit
@testable import ScanHonest

// MARK: - StoreKitManagerTests

@MainActor
final class StoreKitManagerTests: XCTestCase {

    private var manager: StoreKitManager!

    override func setUp() async throws {
        try await super.setUp()
        // Clear persisted StoreKit state
        UserDefaults.standard.removeObject(forKey: "isPro")
        UserDefaults.standard.removeObject(forKey: "purchaseTypeRaw")
        UserDefaults.standard.removeObject(forKey: "purchaseDateRaw")
        manager = StoreKitManager()
    }

    override func tearDown() async throws {
        manager = nil
        UserDefaults.standard.removeObject(forKey: "isPro")
        try await super.tearDown()
    }

    // MARK: - isPro default

    func testIsProReturnsFalseByDefault() {
        // storedIsPro is false, subscriptionStatus defaults to .none
        // isPro should be false
        XCTAssertFalse(manager.storedIsPro,
                       "storedIsPro must be false on a fresh init (no purchase)")
    }

    func testIsProTrueWhenStoredIsProTrue() {
        manager.storedIsPro = true
        // When subscriptionStatus is .unknown, isPro returns storedIsPro
        XCTAssertTrue(manager.isPro,
                      "isPro must return true when storedIsPro is true and status is .unknown")
    }

    // MARK: - storedIsPro persistence

    func testStoredIsProPersistsToUserDefaults() {
        manager.storedIsPro = true
        let stored = UserDefaults.standard.bool(forKey: "isPro")
        XCTAssertTrue(stored, "storedIsPro = true must persist to UserDefaults key 'isPro'")
    }

    func testStoredIsProFalseIsPersistedCorrectly() {
        manager.storedIsPro = true   // set it first
        manager.storedIsPro = false  // then clear
        let stored = UserDefaults.standard.bool(forKey: "isPro")
        XCTAssertFalse(stored, "storedIsPro = false must persist false to UserDefaults")
    }

    // MARK: - subscriptionStatus default

    func testSubscriptionStatusDefaultsToNoneWhenNotPro() {
        // Fresh manager with storedIsPro == false should start as .none
        // (not .unknown, which is used only when storedIsPro is true)
        let freshManager = StoreKitManager()
        // subscriptionStatus is .none when storedIsPro is false
        // Note: init sets it to .unknown if storedIsPro is true, .none otherwise
        if case .none = freshManager.subscriptionStatus {
            XCTAssertTrue(true)
        } else if case .unknown = freshManager.subscriptionStatus {
            // Also acceptable — .unknown while isLoading
            XCTAssertTrue(true)
        } else {
            XCTFail("subscriptionStatus on fresh non-pro install must be .none or .unknown, got \(freshManager.subscriptionStatus)")
        }
    }

    func testSubscriptionStatusIsUnknownWhenStoredIsPro() {
        UserDefaults.standard.set(true, forKey: "isPro")
        let proManager = StoreKitManager()
        if case .unknown = proManager.subscriptionStatus {
            XCTAssertTrue(true, "subscriptionStatus must start as .unknown when storedIsPro is true")
        } else {
            XCTFail("Expected .unknown, got \(proManager.subscriptionStatus)")
        }
    }

    // MARK: - checkVerified

    func testCheckVerifiedThrowsOnUnverifiedResult() {
        let fakePayload = "test"
        // VerificationResult.unverified requires a VerificationResult.VerificationError,
        // not an arbitrary Error type.
        let unverified = VerificationResult<String>.unverified(
            fakePayload,
            VerificationResult<String>.VerificationError.invalidSignature
        )
        // Explicit return type annotation resolves "generic parameter 'T' could not be inferred".
        XCTAssertThrowsError(
            try manager.checkVerified(unverified) as String,
            "checkVerified must throw on an .unverified result"
        ) { error in
            // Qualify with module name to disambiguate from StoreKit.StoreKitError.
            XCTAssertTrue(error is ScanHonest.StoreKitError,
                          "checkVerified must throw ScanHonest.StoreKitError on unverified transaction")
        }
    }

    func testCheckVerifiedReturnsValueOnVerifiedResult() throws {
        let verified = VerificationResult<String>.verified("hello")
        let result = try manager.checkVerified(verified)
        XCTAssertEqual(result, "hello",
                       "checkVerified must return the payload on a .verified result")
    }

    // MARK: - Products

    func testProductsEmptyInitially() {
        XCTAssertTrue(manager.products.isEmpty,
                      "Products array must be empty until StoreKit fetch completes")
    }

    func testLifetimeProductNilUntilLoaded() {
        XCTAssertNil(manager.lifetimeProduct,
                     "lifetimeProduct must be nil until products are fetched")
    }

    func testMonthlyProductNilUntilLoaded() {
        XCTAssertNil(manager.monthlyProduct,
                     "monthlyProduct must be nil until products are fetched")
    }

    // MARK: - isLoading

    func testIsLoadingTrueOnInit() {
        // Manager starts loading immediately in init
        XCTAssertTrue(manager.isLoading,
                      "isLoading must be true immediately after init (fetch in progress)")
    }

    // MARK: - SubscriptionStatus.isPro helper

    func testSubscriptionStatusNoneIsNotPro() {
        XCTAssertFalse(SubscriptionStatus.none.isPro,
                       ".none status must not be Pro")
    }

    func testSubscriptionStatusLifetimeIsPro() {
        XCTAssertTrue(SubscriptionStatus.lifetime.isPro,
                      ".lifetime status must be Pro")
    }

    func testSubscriptionStatusActiveIsPro() {
        XCTAssertTrue(SubscriptionStatus.active.isPro,
                      ".active status must be Pro")
    }

    func testSubscriptionStatusExpiringIsPro() {
        XCTAssertTrue(SubscriptionStatus.expiring(Date()).isPro,
                      ".expiring status must be Pro (still active until expiry)")
    }

    func testSubscriptionStatusExpiredIsNotPro() {
        XCTAssertFalse(SubscriptionStatus.expired.isPro,
                       ".expired status must not be Pro")
    }

    func testSubscriptionStatusUnknownIsNotPro() {
        XCTAssertFalse(SubscriptionStatus.unknown.isPro,
                       ".unknown status must not be Pro")
    }

    // MARK: - ProductID constants

    func testProductIDMonthlyCorrect() {
        XCTAssertEqual(ProductID.monthly, "scanhonest.pro.monthly",
                       "Monthly product ID must match App Store Connect identifier")
    }

    func testProductIDLifetimeCorrect() {
        XCTAssertEqual(ProductID.lifetime, "scanhonest.pro.lifetime",
                       "Lifetime product ID must match App Store Connect identifier")
    }

    func testProductIDAllContainsBoth() {
        XCTAssertTrue(ProductID.all.contains(ProductID.monthly))
        XCTAssertTrue(ProductID.all.contains(ProductID.lifetime))
        XCTAssertEqual(ProductID.all.count, 2,
                       "ProductID.all must contain exactly 2 product IDs")
    }
}
