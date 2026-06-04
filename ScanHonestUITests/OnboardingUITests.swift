import XCTest

// MARK: - OnboardingUITests

extension ScanHonestUITests {

    // MARK: - Setup helper for onboarding tests

    private func launchWithOnboarding() -> XCUIApplication {
        app.terminate()
        let freshApp = XCUIApplication()
        freshApp.launchArguments = ["--uitesting", "--showOnboarding"]
        freshApp.launch()
        return freshApp
    }

    // MARK: - Slide 1

    @MainActor
    func testOnboardingShowsOnFirstLaunch() {
        let onboardingApp = launchWithOnboarding()
        XCTAssertTrue(
            onboardingApp.buttons["getStartedButton"].waitForExistence(timeout: 5),
            "Get Started button must appear on first launch"
        )
    }

    @MainActor
    func testGetStartedButtonAdvancesToSlide2() {
        let onboardingApp = launchWithOnboarding()
        let getStarted = onboardingApp.buttons["getStartedButton"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5), "Get Started must exist on slide 1")
        getStarted.tap()

        XCTAssertTrue(
            onboardingApp.buttons["skipButton"].waitForExistence(timeout: 5),
            "Skip button must appear on slide 2 after tapping Get Started"
        )
    }

    @MainActor
    func testSlide1ShowsScanHonestWordmark() {
        let onboardingApp = launchWithOnboarding()
        XCTAssertTrue(
            onboardingApp.staticTexts["ScanHonest"].waitForExistence(timeout: 5),
            "ScanHonest wordmark must appear on slide 1"
        )
    }

    // MARK: - Slide 2

    @MainActor
    func testSkipButtonOnSlide2JumpsToSlide3() {
        let onboardingApp = launchWithOnboarding()

        onboardingApp.buttons["getStartedButton"].waitForExistence(timeout: 5)
        onboardingApp.buttons["getStartedButton"].tap()

        let skip = onboardingApp.buttons["skipButton"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "Skip button must appear on slide 2")
        skip.tap()

        // Slide 3 has "Set Up Permissions" button
        XCTAssertTrue(
            onboardingApp.buttons.matching(NSPredicate(format: "label CONTAINS 'Permissions'")).firstMatch
                .waitForExistence(timeout: 5),
            "Should advance to slide 3 (permissions) after tapping Skip"
        )
    }

    @MainActor
    func testContinueButtonOnSlide2AdvancesToSlide3() {
        let onboardingApp = launchWithOnboarding()

        onboardingApp.buttons["getStartedButton"].waitForExistence(timeout: 5)
        onboardingApp.buttons["getStartedButton"].tap()

        let continueBtn = onboardingApp.buttons["continueButton"]
        XCTAssertTrue(continueBtn.waitForExistence(timeout: 5), "Continue button must exist on slide 2")
        continueBtn.tap()

        XCTAssertTrue(
            onboardingApp.buttons.matching(NSPredicate(format: "label CONTAINS 'Permissions'")).firstMatch
                .waitForExistence(timeout: 5),
            "Tapping Continue on slide 2 must advance to slide 3"
        )
    }

    @MainActor
    func testSlide2ShowsPricingCards() {
        let onboardingApp = launchWithOnboarding()

        onboardingApp.buttons["getStartedButton"].waitForExistence(timeout: 5)
        onboardingApp.buttons["getStartedButton"].tap()

        XCTAssertTrue(
            onboardingApp.staticTexts["$4.99"].waitForExistence(timeout: 5),
            "Lifetime price $4.99 must appear on slide 2"
        )
        XCTAssertTrue(
            onboardingApp.staticTexts["$1.99"].exists,
            "Monthly price $1.99 must appear on slide 2"
        )
    }

    // MARK: - Permissions slide

    @MainActor
    func testMaybeLaterDismissesOnboarding() {
        let onboardingApp = launchWithOnboarding()

        // Navigate to permissions slide
        onboardingApp.buttons["getStartedButton"].waitForExistence(timeout: 5)
        onboardingApp.buttons["getStartedButton"].tap()
        onboardingApp.buttons["continueButton"].waitForExistence(timeout: 5)
        onboardingApp.buttons["continueButton"].tap()

        // Slide 3 → tap Set Up Permissions
        let setupPerms = onboardingApp.buttons.matching(NSPredicate(format: "label CONTAINS 'Permissions'")).firstMatch
        setupPerms.waitForExistence(timeout: 5)
        setupPerms.tap()

        let maybeLater = onboardingApp.buttons["maybeLaterButton"]
        XCTAssertTrue(maybeLater.waitForExistence(timeout: 5), "Maybe Later must appear on permissions slide")
        maybeLater.tap()

        // Should now show LibraryView
        XCTAssertTrue(
            onboardingApp.buttons["scanDocumentButton"].waitForExistence(timeout: 5),
            "Library must appear after dismissing onboarding with Maybe Later"
        )
    }

    @MainActor
    func testAllowAndContinueButtonExists() {
        let onboardingApp = launchWithOnboarding()

        onboardingApp.buttons["getStartedButton"].waitForExistence(timeout: 5)
        onboardingApp.buttons["getStartedButton"].tap()
        onboardingApp.buttons["continueButton"].waitForExistence(timeout: 5)
        onboardingApp.buttons["continueButton"].tap()

        let setupPerms = onboardingApp.buttons.matching(NSPredicate(format: "label CONTAINS 'Permissions'")).firstMatch
        setupPerms.waitForExistence(timeout: 5)
        setupPerms.tap()

        XCTAssertTrue(
            onboardingApp.buttons["allowContinueButton"].waitForExistence(timeout: 5),
            "Allow & Continue button must appear on permissions slide"
        )
    }

    @MainActor
    func testPermissionsSlideShowsCameraAndPhotosRows() {
        let onboardingApp = launchWithOnboarding()

        onboardingApp.buttons["getStartedButton"].waitForExistence(timeout: 5)
        onboardingApp.buttons["getStartedButton"].tap()
        onboardingApp.buttons["continueButton"].waitForExistence(timeout: 5)
        onboardingApp.buttons["continueButton"].tap()

        let setupPerms = onboardingApp.buttons.matching(NSPredicate(format: "label CONTAINS 'Permissions'")).firstMatch
        setupPerms.waitForExistence(timeout: 5)
        setupPerms.tap()

        XCTAssertTrue(
            onboardingApp.staticTexts["Camera"].waitForExistence(timeout: 5),
            "Camera permission row must be visible"
        )
        XCTAssertTrue(
            onboardingApp.staticTexts["Photo Library"].exists,
            "Photo Library permission row must be visible"
        )
    }

    // MARK: - Re-launch

    @MainActor
    func testOnboardingDoesNotShowAfterCompletion() {
        // App launched with --skipOnboarding in default setUp
        XCTAssertFalse(
            app.buttons["getStartedButton"].waitForExistence(timeout: 3),
            "Onboarding must NOT show when hasCompletedOnboarding is true"
        )
        XCTAssertTrue(
            app.buttons["scanDocumentButton"].waitForExistence(timeout: 5),
            "LibraryView must show when onboarding is already completed"
        )
    }
}
