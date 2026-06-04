import XCTest

// MARK: - UITestHelpers
// Shared helper functions used by all UITest extensions.

extension XCTestCase {

    // MARK: - App factory

    /// Creates a configured app ready for most tests (onboarding skipped, state cleared).
    func makeApp(skipOnboarding: Bool = true, isPro: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["--uitesting"]
        if skipOnboarding { args.append("--skipOnboarding") }
        else              { args.append("--showOnboarding") }
        if isPro          { args.append("--isPro") }
        app.launchArguments = args
        return app
    }

    // MARK: - Navigation helpers

    /// Dismisses onboarding by tapping "Maybe Later" on the permissions slide.
    func skipOnboarding(in app: XCUIApplication) {
        // Tap through all slides until Maybe Later is visible
        let getStarted = app.buttons["getStartedButton"]
        if getStarted.waitForExistence(timeout: 5) {
            getStarted.tap()
        }
        let continueBtn = app.buttons["continueButton"]
        if continueBtn.waitForExistence(timeout: 5) {
            continueBtn.tap()
        }
        // Slide 3 → "Set Up Permissions"
        let setupPerms = app.buttons.matching(identifier: "Set Up Permissions").firstMatch
        if setupPerms.waitForExistence(timeout: 5) {
            setupPerms.tap()
        }
        let maybeLater = app.buttons["maybeLaterButton"]
        if maybeLater.waitForExistence(timeout: 5) {
            maybeLater.tap()
        }
    }

    /// Opens Settings from LibraryView.
    func openSettings(in app: XCUIApplication) {
        let settingsBtn = app.buttons["settingsButton"]
        XCTAssertTrue(settingsBtn.waitForExistence(timeout: 5),
                      "Settings button must be visible in library")
        settingsBtn.tap()
    }

    /// Opens the import action sheet.
    func openImportSheet(in app: XCUIApplication) {
        let importBtn = app.buttons["importButton"]
        XCTAssertTrue(importBtn.waitForExistence(timeout: 5),
                      "Import button must be visible")
        importBtn.tap()
    }

    /// Saves a document from ScanReviewView with the given name.
    /// Assumes ScanReviewView is already presented.
    func saveDocument(named name: String, in app: XCUIApplication) {
        let saveBtn = app.buttons["saveButton"]
        XCTAssertTrue(saveBtn.waitForExistence(timeout: 5), "Save button must be visible")
        saveBtn.tap()

        // Fill in file name
        let nameField = app.textFields["Document name"]
        if nameField.waitForExistence(timeout: 3) {
            nameField.clearAndType(name)
        }

        // Tap "Save to ScanHonest"
        let saveToApp = app.buttons["Save to ScanHonest"]
        XCTAssertTrue(saveToApp.waitForExistence(timeout: 5), "Save to ScanHonest button must appear")
        saveToApp.tap()
    }

    /// Opens a document by tapping its cell in the grid.
    func openDocument(named name: String, in app: XCUIApplication) {
        let cell = app.staticTexts[name]
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "Document '\(name)' must appear in library")
        cell.tap()
    }
}

// MARK: - XCUIElement extensions

extension XCUIElement {
    /// Clears existing text and types new text into a text field.
    func clearAndType(_ text: String) {
        guard self.exists else { return }
        tap()
        // Select all and delete
        let selectAll = XCUIApplication().menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 1) {
            selectAll.tap()
            typeText(text)
        } else {
            // Fallback: triple-tap to select all
            let stringValue = (value as? String) ?? ""
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
            typeText(deleteString)
            typeText(text)
        }
    }

    /// Waits for the element to exist and asserts it does.
    @discardableResult
    func assertExists(timeout: TimeInterval = 5, message: String = "") -> Self {
        XCTAssertTrue(waitForExistence(timeout: timeout), message.isEmpty ? "\(self) must exist" : message)
        return self
    }
}
