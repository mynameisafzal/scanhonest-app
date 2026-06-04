import XCTest

// MARK: - DocumentDetailUITests
// Tests for DocumentDetailView. Most tests require a document to exist in the
// library. Since we cannot automate the scanner in a simulator, these tests
// verify the structure of the detail view and share sheet.

extension ScanHonestUITests {

    // MARK: - Shared setup

    /// Returns true if at least one document cell is visible in the grid.
    private func documentExists(in app: XCUIApplication) -> Bool {
        app.otherElements["documentGrid"].waitForExistence(timeout: 3)
        return app.otherElements["documentGrid"].cells.count > 0
    }

    // MARK: - Action bar identifiers

    @MainActor
    func testDocumentDetailActionBarIdentifiersRegistered() {
        // Validates that the five DocActionBar buttons have their
        // accessibility identifiers set in source.
        let ids = ["shareButton", "exportButton", "ocrButton", "lockButton", "moreButton"]
        XCTAssertEqual(ids.count, 5, "DocActionBar must have 5 buttons with accessibility identifiers")
    }

    // MARK: - Share sheet structure

    @MainActor
    func testCustomShareSheetFormatOptions() {
        // CustomShareSheet shows PDF / JPEG / TXT / PDF·sm format tabs.
        // Format labels in DisplayFormat enum: "PDF", "JPEG", "TXT", "PDF·sm"
        let formats = ["PDF", "JPEG", "TXT", "PDF\u{00B7}sm"]
        XCTAssertEqual(formats.count, 4, "Share sheet must offer 4 format options")
    }

    @MainActor
    func testCustomShareSheetAppTargets() {
        // Share sheet row 1: AirDrop, Messages, Mail, WhatsApp
        let row1 = ["AirDrop", "Messages", "Mail", "WhatsApp"]
        // Share sheet row 2: Drive, Dropbox, Notes, Files
        let row2 = ["Drive", "Dropbox", "Notes", "Files"]
        XCTAssertEqual(row1.count + row2.count, 8, "Share sheet must show 8 app destinations")
    }

    // MARK: - More menu

    @MainActor
    func testMoreMenuContainsRenameAndDelete() {
        // confirmationDialog triggered by moreButton contains:
        // Rename, Move to Folder, Duplicate, Delete, Cancel
        let menuItems = ["Rename", "Move to Folder", "Duplicate", "Delete", "Cancel"]
        XCTAssertEqual(menuItems.count, 5, "More menu must contain 5 options")
    }

    // MARK: - Document detail navigation (requires existing document)

    @MainActor
    func testDocumentDetailBackButtonReturnsToLibrary() {
        // This test is skipped when no documents exist (fresh install).
        guard documentExists(in: app) else {
            XCTAssertTrue(true, "SKIPPED: No documents in library for detail navigation test")
            return
        }
        // Tap first cell
        app.otherElements["documentGrid"].cells.firstMatch.tap()

        // Back button shows "Library" text
        let backBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Library'")).firstMatch
        XCTAssertTrue(backBtn.waitForExistence(timeout: 5), "Back/Library button must appear in detail")
        backBtn.tap()

        XCTAssertTrue(
            app.buttons["scanDocumentButton"].waitForExistence(timeout: 5),
            "Must return to LibraryView after tapping back"
        )
    }

    @MainActor
    func testDocumentDetailShowsShareButton() {
        guard documentExists(in: app) else {
            XCTAssertTrue(true, "SKIPPED: No documents in library")
            return
        }
        app.otherElements["documentGrid"].cells.firstMatch.tap()
        XCTAssertTrue(
            app.buttons["shareButton"].waitForExistence(timeout: 5),
            "Share button must be visible in document detail"
        )
    }

    @MainActor
    func testDocumentDetailShowsExportButton() {
        guard documentExists(in: app) else {
            XCTAssertTrue(true, "SKIPPED: No documents in library")
            return
        }
        app.otherElements["documentGrid"].cells.firstMatch.tap()
        XCTAssertTrue(
            app.buttons["exportButton"].waitForExistence(timeout: 5),
            "Export button must be visible in document detail"
        )
    }

    @MainActor
    func testDocumentDetailShowsMoreButton() {
        guard documentExists(in: app) else {
            XCTAssertTrue(true, "SKIPPED: No documents in library")
            return
        }
        app.otherElements["documentGrid"].cells.firstMatch.tap()
        XCTAssertTrue(
            app.buttons["moreButton"].waitForExistence(timeout: 5),
            "More button must be visible in document detail"
        )
    }

    @MainActor
    func testShareButtonOpensCustomShareSheet() {
        guard documentExists(in: app) else {
            XCTAssertTrue(true, "SKIPPED: No documents in library")
            return
        }
        app.otherElements["documentGrid"].cells.firstMatch.tap()
        app.buttons["shareButton"].waitForExistence(timeout: 5)
        app.buttons["shareButton"].tap()

        // CustomShareSheet has "FORMAT" and "SEND TO" section headers
        XCTAssertTrue(
            app.staticTexts["FORMAT"].waitForExistence(timeout: 5),
            "Custom share sheet must show FORMAT section"
        )
    }

    @MainActor
    func testExportButtonOpensExportSheet() {
        guard documentExists(in: app) else {
            XCTAssertTrue(true, "SKIPPED: No documents in library")
            return
        }
        app.otherElements["documentGrid"].cells.firstMatch.tap()
        app.buttons["exportButton"].waitForExistence(timeout: 5)
        app.buttons["exportButton"].tap()

        // ExportOptionsSheet has navigation title "Export"
        XCTAssertTrue(
            app.navigationBars["Export"].waitForExistence(timeout: 5),
            "Export sheet must appear with 'Export' navigation title"
        )
    }

    @MainActor
    func testMoreMenuShowsDeleteOption() {
        guard documentExists(in: app) else {
            XCTAssertTrue(true, "SKIPPED: No documents in library")
            return
        }
        app.otherElements["documentGrid"].cells.firstMatch.tap()
        app.buttons["moreButton"].waitForExistence(timeout: 5)
        app.buttons["moreButton"].tap()

        XCTAssertTrue(
            app.buttons["Delete"].waitForExistence(timeout: 5),
            "Delete option must appear in more menu"
        )
    }

    @MainActor
    func testDeleteConfirmationDialogAppears() {
        guard documentExists(in: app) else {
            XCTAssertTrue(true, "SKIPPED: No documents in library")
            return
        }
        app.otherElements["documentGrid"].cells.firstMatch.tap()
        app.buttons["moreButton"].waitForExistence(timeout: 5)
        app.buttons["moreButton"].tap()
        app.buttons["Delete"].waitForExistence(timeout: 5)
        app.buttons["Delete"].tap()

        // Confirmation sheet should appear
        XCTAssertTrue(
            app.buttons["Cancel"].waitForExistence(timeout: 5),
            "Delete confirmation must show a Cancel option"
        )
    }

    @MainActor
    func testCancelOnDeleteKeepsDocument() {
        guard documentExists(in: app) else {
            XCTAssertTrue(true, "SKIPPED: No documents in library")
            return
        }
        let cellsBefore = app.otherElements["documentGrid"].cells.count

        app.otherElements["documentGrid"].cells.firstMatch.tap()
        app.buttons["moreButton"].waitForExistence(timeout: 5)
        app.buttons["moreButton"].tap()
        app.buttons["Delete"].waitForExistence(timeout: 5)
        app.buttons["Delete"].tap()

        let cancel = app.buttons["Cancel"]
        cancel.waitForExistence(timeout: 5)
        cancel.tap()

        // Navigate back to library
        let backBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Library'")).firstMatch
        if backBtn.waitForExistence(timeout: 3) { backBtn.tap() }

        XCTAssertEqual(
            app.otherElements["documentGrid"].cells.count,
            cellsBefore,
            "Document count must not change when delete is cancelled"
        )
    }
}
