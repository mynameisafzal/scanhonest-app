import XCTest

// MARK: - LibraryUITests

extension ScanHonestUITests {

    // MARK: - Basic load

    @MainActor
    func testLibraryLoadsCorrectly() {
        XCTAssertTrue(
            app.buttons["scanDocumentButton"].waitForExistence(timeout: 5),
            "Library must load and show Scan Document button"
        )
    }

    @MainActor
    func testScanCounterBannerVisible() {
        XCTAssertTrue(
            app.otherElements["scanCounterBanner"].waitForExistence(timeout: 5),
            "Scan counter banner must be visible in LibraryView"
        )
    }

    @MainActor
    func testScanDocumentButtonExists() {
        XCTAssertTrue(
            app.buttons["scanDocumentButton"].waitForExistence(timeout: 5),
            "Scan Document button must exist"
        )
    }

    @MainActor
    func testImportButtonExists() {
        XCTAssertTrue(
            app.buttons["importButton"].waitForExistence(timeout: 5),
            "Import button must exist"
        )
    }

    @MainActor
    func testRecentLabelVisible() {
        XCTAssertTrue(
            app.staticTexts["RECENT"].waitForExistence(timeout: 5),
            "RECENT section label must be visible"
        )
    }

    @MainActor
    func testAllFoldersLabelVisible() {
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'folders'")).firstMatch
                .waitForExistence(timeout: 5),
            "All folders navigation label must be visible"
        )
    }

    @MainActor
    func testEmptyStateShowsWhenNoDocuments() {
        // Fresh install has no documents — empty state should show
        XCTAssertTrue(
            app.staticTexts["Your scans will appear here"].waitForExistence(timeout: 5),
            "Empty state message must appear when no documents exist"
        )
    }

    @MainActor
    func testEmptyStateShowsFreeScansMessage() {
        XCTAssertTrue(
            app.staticTexts["You have 5 free scans. No card needed."].waitForExistence(timeout: 5),
            "Empty state must show free scan count"
        )
    }

    // MARK: - Search

    @MainActor
    func testSearchButtonIsTappable() {
        let searchBtn = app.buttons["searchButton"]
        XCTAssertTrue(searchBtn.waitForExistence(timeout: 5), "Search button must exist")
        searchBtn.tap()
        // After tap, search field should appear
        XCTAssertTrue(
            app.textFields["Search documents\u{2026}"].waitForExistence(timeout: 3),
            "Search text field must appear after tapping search"
        )
    }

    @MainActor
    func testSearchCanBeDismissed() {
        app.buttons["searchButton"].waitForExistence(timeout: 5)
        app.buttons["searchButton"].tap()

        // Tap the X (same button now shows xmark)
        app.buttons["searchButton"].tap()

        // RECENT should come back
        XCTAssertTrue(
            app.staticTexts["RECENT"].waitForExistence(timeout: 3),
            "RECENT label must reappear after dismissing search"
        )
    }

    // MARK: - Settings

    @MainActor
    func testSettingsButtonIsTappable() {
        let settingsBtn = app.buttons["settingsButton"]
        XCTAssertTrue(settingsBtn.waitForExistence(timeout: 5), "Settings button must exist")
        settingsBtn.tap()
        XCTAssertTrue(
            app.staticTexts["Settings"].waitForExistence(timeout: 5),
            "Settings view must open after tapping settings button"
        )
    }

    // MARK: - Import flow

    @MainActor
    func testImportButtonShowsActionSheet() {
        let importBtn = app.buttons["importButton"]
        XCTAssertTrue(importBtn.waitForExistence(timeout: 5), "Import button must exist")
        importBtn.tap()

        XCTAssertTrue(
            app.sheets.firstMatch.waitForExistence(timeout: 5)
            || app.otherElements["Import Document"].waitForExistence(timeout: 5),
            "Import action sheet must appear"
        )
    }

    @MainActor
    func testImportActionSheetShowsChoosePhoto() {
        app.buttons["importButton"].waitForExistence(timeout: 5)
        app.buttons["importButton"].tap()

        XCTAssertTrue(
            app.buttons["Choose Photo"].waitForExistence(timeout: 5),
            "Choose Photo option must appear in import sheet"
        )
    }

    @MainActor
    func testImportActionSheetShowsChoosePDF() {
        app.buttons["importButton"].waitForExistence(timeout: 5)
        app.buttons["importButton"].tap()

        XCTAssertTrue(
            app.buttons["Choose PDF or Document"].waitForExistence(timeout: 5),
            "Choose PDF or Document option must appear in import sheet"
        )
    }

    @MainActor
    func testImportActionSheetCancelDismisses() {
        app.buttons["importButton"].waitForExistence(timeout: 5)
        app.buttons["importButton"].tap()

        let cancelBtn = app.buttons["Cancel"]
        XCTAssertTrue(cancelBtn.waitForExistence(timeout: 5), "Cancel must appear in import sheet")
        cancelBtn.tap()

        // Should be back in library
        XCTAssertTrue(
            app.buttons["importButton"].waitForExistence(timeout: 3),
            "Import button must be visible after dismissing action sheet"
        )
    }

    // MARK: - Photo picker

    @MainActor
    func testChoosePhotoOpenPhotosPicker() {
        app.buttons["importButton"].waitForExistence(timeout: 5)
        app.buttons["importButton"].tap()

        app.buttons["Choose Photo"].waitForExistence(timeout: 5)
        app.buttons["Choose Photo"].tap()

        // Photos picker or permission dialog should appear
        let photosPicker = app.navigationBars["Photos"].firstMatch
        let permissionAlert = app.alerts.firstMatch
        XCTAssertTrue(
            photosPicker.waitForExistence(timeout: 5) || permissionAlert.waitForExistence(timeout: 5),
            "Photos picker or permission prompt must appear after Choose Photo"
        )
    }
}
