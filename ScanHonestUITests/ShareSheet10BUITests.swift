import XCTest

/// Targeted verification of the 10B Native Handoff share sheet.
extension ScanHonestUITests {

    // MARK: - Helpers

    private func launchSeeded(isPro: Bool = false) {
        app.terminate()
        var args = ["--uitesting", "--skipOnboarding", "--seedTestDocument"]
        if isPro { args.append("--isPro") }
        app.launchArguments = args
        app.launch()
    }

    /// Waits for the document grid to show at least one document.
    /// SwiftUI LazyVGrid children appear as otherElements in XCUITest.
    private func waitForDocument(timeout: TimeInterval = 10) -> Bool {
        // First wait for the grid container
        let grid = app.otherElements["documentGrid"]
        guard grid.waitForExistence(timeout: timeout) else {
            print("documentGrid not found")
            return false
        }
        // Then wait for at least one child element (any type)
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            if grid.children(matching: .any).count > 0 { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        print("documentGrid found but has 0 children")
        return false
    }

    // MARK: - 10B sheet structure

    @MainActor
    func test10B_ShareSheetStructure() {
        launchSeeded()
        guard waitForDocument() else {
            XCTFail("Library grid empty after seedTestDocument — check ScanHonestApp.seedTestDocument")
            return
        }

        // Open the seeded document
        app.otherElements["documentGrid"].children(matching: .any).firstMatch.tap()
        XCTAssertTrue(app.buttons["shareButton"].waitForExistence(timeout: 5),
                      "Share button must appear in document detail")
        app.buttons["shareButton"].tap()

        // FORMAT section header (kept in 10B)
        XCTAssertTrue(app.staticTexts["FORMAT"].waitForExistence(timeout: 5),
                      "10B sheet must show FORMAT header")

        // Format chips
        XCTAssertTrue(app.staticTexts["PDF"].exists, "PDF chip must be present")
        XCTAssertTrue(app.staticTexts["JPEG"].exists, "JPEG chip must be present")

        // Password Protect row
        XCTAssertTrue(app.staticTexts["Password Protect"].waitForExistence(timeout: 3),
                      "Password Protect row must be present")
        XCTAssertTrue(app.staticTexts["AES-256 encryption"].exists,
                      "AES-256 encryption subtitle must be present")

        // Nearby Share row
        XCTAssertTrue(app.staticTexts["Nearby Share"].exists, "Nearby Share row must be present")

        // Primary CTA button — labelled "Share via iOS…" with share icon
        let cta = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Share via iOS'")).firstMatch
        XCTAssertTrue(cta.exists, "'Share via iOS…' CTA button must be present")

        // Caption removed — verify it is not shown
        let caption = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'opens iOS share sheet'")).firstMatch
        XCTAssertFalse(caption.exists, "'opens iOS share sheet' caption must NOT be present")

        // Old design elements REMOVED
        XCTAssertFalse(app.staticTexts["SEND TO"].exists, "SEND TO section must not exist in 10B")
        XCTAssertFalse(app.staticTexts["AirDrop"].exists, "AirDrop per-app row must not exist in 10B")
        XCTAssertFalse(app.staticTexts["More options"].exists, "More options row must not exist in 10B")
    }

    // MARK: - Share button triggers UIActivityViewController without crashing

    @MainActor
    func test10B_ShareViaIOSOpensNativeSheet() {
        launchSeeded()
        guard waitForDocument() else {
            XCTFail("Library grid empty after seeding")
            return
        }

        app.otherElements["documentGrid"].children(matching: .any).firstMatch.tap()
        app.buttons["shareButton"].waitForExistence(timeout: 5)
        app.buttons["shareButton"].tap()

        // Confirm the custom sheet is open
        XCTAssertTrue(app.staticTexts["FORMAT"].waitForExistence(timeout: 5),
                      "Custom share sheet must be visible before tapping Share")

        // Find and tap the "Share via iOS…" CTA
        let cta = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Share via iOS'")).firstMatch
        XCTAssertTrue(cta.waitForExistence(timeout: 5), "'Share via iOS…' CTA button must be present")
        cta.tap()

        // Wait for file prep + sheet dismiss animation + share sheet presentation.
        // handleShare() prepares the file, dismisses the custom sheet (~0.38 s
        // animation), then presents UIActivityViewController.
        Thread.sleep(forTimeInterval: 2.5)

        // The "Sharing Failed" alert must NOT appear — that indicates a prep error.
        let errorAlert = app.alerts["Sharing Failed"]
        XCTAssertFalse(errorAlert.exists,
                       "'Sharing Failed' alert must NOT appear — file export must succeed")

        // Custom sheet is dismissed first, so FORMAT text must be gone.
        XCTAssertFalse(app.staticTexts["FORMAT"].exists,
                       "Custom sheet must be dismissed before the native share sheet appears")

        // The native iOS share sheet (UIActivityViewController) is presented.
        // iOS 26 Liquid Glass redesigned the share sheet — "Cancel" is gone, but
        // a collection view of share targets is always present.
        let shareTargets = app.collectionViews.firstMatch
        let nativeSheetAppeared = shareTargets.waitForExistence(timeout: 5)
        XCTAssertTrue(nativeSheetAppeared,
                      "Native iOS share sheet (UIActivityViewController) collection view must appear")
    }

    // MARK: - Password Protect toggle (Pro user)

    @MainActor
    func test10B_PasswordProtectTogglePro() {
        launchSeeded(isPro: true)
        guard waitForDocument() else {
            XCTFail("Library grid empty after seeding")
            return
        }

        app.otherElements["documentGrid"].children(matching: .any).firstMatch.tap()
        app.buttons["shareButton"].waitForExistence(timeout: 5)
        app.buttons["shareButton"].tap()

        // Verify toggle exists and starts OFF
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "Password protect switch must be present")
        XCTAssertEqual(toggle.value as? String, "0", "Toggle must be OFF by default")

        // Tap ON
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1", "Toggle must turn ON for Pro user")

        // SecureField must appear
        let pwField = app.secureTextFields.firstMatch
        XCTAssertTrue(pwField.waitForExistence(timeout: 2), "Password SecureField must appear after toggle ON")
    }

    // MARK: - Password Protect toggle (free user stays OFF)

    @MainActor
    func test10B_PasswordProtectToggleFreeUserStaysOff() {
        launchSeeded(isPro: false)
        guard waitForDocument() else {
            XCTFail("Library grid empty after seeding")
            return
        }

        app.otherElements["documentGrid"].children(matching: .any).firstMatch.tap()
        app.buttons["shareButton"].waitForExistence(timeout: 5)
        app.buttons["shareButton"].tap()

        // PRO badge visible next to the label
        XCTAssertTrue(app.staticTexts["PRO"].exists, "PRO badge must appear for free users")

        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.tap()

        // Toggle stays OFF because paywall was triggered
        XCTAssertEqual(toggle.value as? String, "0",
                       "Toggle must stay OFF for free user — paywall shown instead")
    }
}
