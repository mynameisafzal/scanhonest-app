import XCTest
@testable import ScanHonest

// MARK: - ScanLimitManagerTests

@MainActor
final class ScanLimitManagerTests: XCTestCase {

    private var manager: ScanLimitManager!
    private let testSuiteDefaults = "com.afzal.ScanHonest.testSuite"

    override func setUp() async throws {
        try await super.setUp()
        // Wipe UserDefaults keys used by ScanLimitManager before each test
        let ud = UserDefaults.standard
        ud.removeObject(forKey: "scansUsedThisMonth")
        ud.removeObject(forKey: "scanCountResetDate")
        ud.removeObject(forKey: "appFirstInstallDate")
        manager = ScanLimitManager()
    }

    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }

    // MARK: - recordScan

    func testRecordScanIncrementsCount() {
        manager.recordScan()
        XCTAssertEqual(manager.scansUsedThisMonth, 1,
                       "recordScan() must increment scansUsedThisMonth from 0 to 1")
    }

    func testRecordScanIncrementsTwice() {
        manager.recordScan()
        manager.recordScan()
        XCTAssertEqual(manager.scansUsedThisMonth, 2,
                       "recordScan() called twice must result in count of 2")
    }

    func testRecordScanDoesNotExceedLimit() {
        // Call recordScan() more times than the free limit
        for _ in 0..<(ScanLimitManager.freeMonthlyLimit + 3) {
            manager.recordScan()
        }
        XCTAssertEqual(
            manager.scansUsedThisMonth,
            ScanLimitManager.freeMonthlyLimit,
            "scansUsedThisMonth must not exceed freeMonthlyLimit (\(ScanLimitManager.freeMonthlyLimit))"
        )
    }

    // MARK: - hasReachedLimit

    func testHasReachedLimitFalseWhenBelowLimit() {
        manager.recordScan()
        XCTAssertFalse(manager.hasReachedLimit,
                       "hasReachedLimit must be false when only 1 scan used")
    }

    func testHasReachedLimitTrueAtExactLimit() {
        for _ in 0..<ScanLimitManager.freeMonthlyLimit {
            manager.recordScan()
        }
        XCTAssertTrue(manager.hasReachedLimit,
                      "hasReachedLimit must be true when \(ScanLimitManager.freeMonthlyLimit) scans used")
    }

    func testHasReachedLimitFalseOnFreshInstall() {
        XCTAssertFalse(manager.hasReachedLimit,
                       "hasReachedLimit must be false on a fresh install with 0 scans")
    }

    // MARK: - scansRemaining

    func testScansRemainingStartsAtLimit() {
        XCTAssertEqual(
            manager.scansRemaining,
            ScanLimitManager.freeMonthlyLimit,
            "scansRemaining must equal freeMonthlyLimit on fresh install"
        )
    }

    func testScansRemainingDecreasesAfterScan() {
        manager.recordScan()
        XCTAssertEqual(
            manager.scansRemaining,
            ScanLimitManager.freeMonthlyLimit - 1,
            "scansRemaining must decrease by 1 after one scan"
        )
    }

    func testScansRemainingNeverGoesNegative() {
        for _ in 0..<(ScanLimitManager.freeMonthlyLimit + 5) {
            manager.recordScan()
        }
        XCTAssertGreaterThanOrEqual(
            manager.scansRemaining, 0,
            "scansRemaining must never be negative"
        )
    }

    func testScansRemainingCalculatesCorrectly() {
        let usedCount = 3
        for _ in 0..<usedCount {
            manager.recordScan()
        }
        XCTAssertEqual(
            manager.scansRemaining,
            ScanLimitManager.freeMonthlyLimit - usedCount,
            "scansRemaining must equal limit minus used count"
        )
    }

    // MARK: - resetCount

    func testResetCountClearsUsedScans() {
        manager.recordScan()
        manager.recordScan()
        manager.resetCount()
        XCTAssertEqual(manager.scansUsedThisMonth, 0,
                       "scansUsedThisMonth must be 0 after resetCount()")
    }

    func testResetCountRestoresFullRemaining() {
        manager.recordScan()
        manager.resetCount()
        XCTAssertEqual(manager.scansRemaining, ScanLimitManager.freeMonthlyLimit,
                       "scansRemaining must equal full limit after resetCount()")
    }

    func testResetCountAllowsNewScans() {
        // Exhaust the limit
        for _ in 0..<ScanLimitManager.freeMonthlyLimit {
            manager.recordScan()
        }
        XCTAssertTrue(manager.hasReachedLimit)

        // Reset and verify scans work again
        manager.resetCount()
        manager.recordScan()
        XCTAssertEqual(manager.scansUsedThisMonth, 1,
                       "Must be able to record scans after reset")
        XCTAssertFalse(manager.hasReachedLimit,
                       "hasReachedLimit must be false after reset")
    }

    // MARK: - counterState

    func testCounterStateFreeWhenNotPro() {
        manager.recordScan()
        let state = manager.counterState(isPro: false)
        if case .free(let used, let limit) = state {
            XCTAssertEqual(used, 1)
            XCTAssertEqual(limit, ScanLimitManager.freeMonthlyLimit)
        } else {
            XCTFail("counterState must return .free when isPro is false")
        }
    }

    func testCounterStateProWhenIsPro() {
        let state = manager.counterState(isPro: true)
        if case .pro = state {
            XCTAssertTrue(true)
        } else {
            XCTFail("counterState must return .pro when isPro is true")
        }
    }

    // MARK: - progressFraction

    func testProgressFractionZeroOnFreshInstall() {
        XCTAssertEqual(manager.progressFraction, 0.0, accuracy: 0.001,
                       "progressFraction must be 0 on fresh install")
    }

    func testProgressFractionOneAtLimit() {
        for _ in 0..<ScanLimitManager.freeMonthlyLimit {
            manager.recordScan()
        }
        XCTAssertEqual(manager.progressFraction, 1.0, accuracy: 0.001,
                       "progressFraction must be 1.0 when limit reached")
    }

    func testProgressFractionNeverExceedsOne() {
        for _ in 0..<(ScanLimitManager.freeMonthlyLimit + 5) {
            manager.recordScan()
        }
        XCTAssertLessThanOrEqual(manager.progressFraction, 1.0,
                                  "progressFraction must never exceed 1.0")
    }

    // MARK: - freeMonthlyLimit constant

    func testFreeMonthlyLimitIsFive() {
        XCTAssertEqual(ScanLimitManager.freeMonthlyLimit, 5,
                       "Free monthly limit must be 5 scans")
    }
}
