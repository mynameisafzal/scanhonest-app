import XCTest

// MARK: - ScanHonestUITests
// Main test class: shared app instance + common setUp/tearDown.
// Each subclass extension in its own file inherits these.

final class ScanHonestUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // Default: skip onboarding, clear all state
        app.launchArguments = ["--uitesting", "--skipOnboarding"]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Smoke test

    @MainActor
    func testAppLaunches() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5),
                      "App should reach foreground within 5 seconds")
    }

    // MARK: - Launch performance

    @MainActor
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
