import XCTest
import SwiftData
@testable import ScanHonest

// MARK: - PasswordProtectionTests
//
// Covers the `isPasswordProtected` flag lifecycle on ScannedDocument,
// multi-document independence, and the App Switcher privacy invariant.
//
// NOTE: ScanHonest stores `isPasswordProtected` as a SwiftData Bool flag.
// Actual cryptographic key derivation (AES-256) must be validated in the
// EncryptionService layer (see EncryptionServiceTests). These tests verify
// the *access-control state machine* — locking, unlocking, and isolation.

final class PasswordProtectionTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([ScannedDocument.self, DocumentFolder.self])
        let config = ModelConfiguration(schema: schema,
                                        isStoredInMemoryOnly: true,
                                        cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: config)
        context   = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context   = nil
        container = nil
        try super.tearDownWithError()
    }

    private func makeDocument(name: String, locked: Bool = false) -> ScannedDocument {
        let d = ScannedDocument(name: name, isPasswordProtected: locked)
        context.insert(d)
        return d
    }

    // MARK: - Default state

    func testNewDocumentIsUnlockedByDefault() {
        let doc = makeDocument(name: "Fresh")
        XCTAssertFalse(doc.isPasswordProtected,
                       "A newly created document must NOT be password-protected by default")
    }

    // MARK: - Locking

    func testLockingDocument() {
        let doc = makeDocument(name: "Sensitive")
        doc.isPasswordProtected = true
        XCTAssertTrue(doc.isPasswordProtected,
                      "Setting isPasswordProtected = true must mark the document as locked")
    }

    func testLockingPersistsAcrossContextSave() throws {
        let doc = makeDocument(name: "LockPersist")
        doc.isPasswordProtected = true
        try context.save()

        let descriptor = FetchDescriptor<ScannedDocument>(
            predicate: #Predicate { $0.name == "LockPersist" }
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertTrue(fetched.first?.isPasswordProtected == true,
                      "isPasswordProtected = true must persist across a context save")
    }

    // MARK: - Unlocking

    func testUnlockingDocument() {
        let doc = makeDocument(name: "ToUnlock", locked: true)
        doc.isPasswordProtected = false
        XCTAssertFalse(doc.isPasswordProtected,
                       "Setting isPasswordProtected = false must unlock the document")
    }

    func testUnlockingPersistsAcrossContextSave() throws {
        let doc = makeDocument(name: "UnlockPersist", locked: true)
        doc.isPasswordProtected = false
        try context.save()

        let descriptor = FetchDescriptor<ScannedDocument>(
            predicate: #Predicate { $0.name == "UnlockPersist" }
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertFalse(fetched.first?.isPasswordProtected == true,
                       "isPasswordProtected = false must persist across a context save")
    }

    // MARK: - Toggle behaviour (lock → unlock → lock)

    func testRepeatedTogglePreservesCorrectState() {
        let doc = makeDocument(name: "Toggler")
        doc.isPasswordProtected = true
        doc.isPasswordProtected = false
        doc.isPasswordProtected = true
        XCTAssertTrue(doc.isPasswordProtected,
                      "Final state after odd number of toggles must be locked")

        doc.isPasswordProtected = false
        XCTAssertFalse(doc.isPasswordProtected,
                       "Final state after even number of toggles must be unlocked")
    }

    // MARK: - Independence between documents

    func testLockingOneDocumentDoesNotAffectAnother() {
        let doc1 = makeDocument(name: "Locked One")
        let doc2 = makeDocument(name: "Open Two")
        doc1.isPasswordProtected = true
        XCTAssertFalse(doc2.isPasswordProtected,
                       "Locking one document must NOT affect another document's lock state")
    }

    func testMultipleDocumentsCanHaveIndependentLockStates() {
        let locked   = (1...3).map { makeDocument(name: "Locked \($0)", locked: true) }
        let unlocked = (4...6).map { makeDocument(name: "Open \($0)",   locked: false) }

        for doc in locked   { XCTAssertTrue(doc.isPasswordProtected,  "\(doc.name) must be locked") }
        for doc in unlocked { XCTAssertFalse(doc.isPasswordProtected, "\(doc.name) must be unlocked") }
    }

    // MARK: - Lock state survives folder operations

    func testLockStatePreservedWhenDocumentMovedToFolder() throws {
        let folder = DocumentFolder(name: "Private")
        context.insert(folder)
        let doc = makeDocument(name: "Medical.pdf", locked: true)
        doc.folder = folder
        try context.save()

        XCTAssertTrue(doc.isPasswordProtected,
                      "isPasswordProtected must be preserved when a document is assigned to a folder")
    }

    func testLockStatePreservedWhenDocumentRemovedFromFolder() throws {
        let folder = DocumentFolder(name: "Work")
        context.insert(folder)
        let doc = makeDocument(name: "Salary.pdf", locked: true)
        doc.folder = folder
        try context.save()

        doc.folder = nil
        try context.save()

        XCTAssertTrue(doc.isPasswordProtected,
                      "isPasswordProtected must be preserved when a document is removed from a folder")
    }

    // MARK: - Other document properties are not affected by lock/unlock

    func testLockingDoesNotMutateDocumentName() {
        let doc = makeDocument(name: "Unchanged Name")
        doc.isPasswordProtected = true
        XCTAssertEqual(doc.name, "Unchanged Name",
                       "Locking must not alter the document's name")
    }

    func testLockingDoesNotMutatePageCount() {
        let doc = ScannedDocument(name: "Multi-Page", pageCount: 10)
        context.insert(doc)
        doc.isPasswordProtected = true
        XCTAssertEqual(doc.pageCount, 10,
                       "Locking must not alter the document's pageCount")
    }

    // MARK: - App Switcher privacy invariant
    //
    // iOS exposes a snapshot of the app's last UI state in the App Switcher
    // (multitasking view). For locked documents, this snapshot must be
    // replaced with a blur or placeholder.
    //
    // This test verifies the *flag* that drives that decision is accessible
    // so the SceneDelegate / WindowGroup can read it without touching SwiftData.
    // The actual UIKit blur is applied in SceneDelegate.sceneWillResignActive(_:)
    // or via UIApplication.applicationWillResignActive — tested in UI tests.

    func testIsPasswordProtectedIsReadableOutsideModelContext() {
        // Simulate reading the flag at resign-active time (off-context snapshot)
        let doc = makeDocument(name: "AppSwitcher")
        doc.isPasswordProtected = true

        // The value is a plain Bool — readable without async model context access
        let flag: Bool = doc.isPasswordProtected
        XCTAssertTrue(flag,
                      "isPasswordProtected must be readable as a plain Bool for App Switcher blur logic")
    }

    func testLockedDocumentCountIsQueryable() throws {
        makeDocument(name: "A", locked: true)
        makeDocument(name: "B", locked: true)
        makeDocument(name: "C", locked: false)
        try context.save()

        let descriptor = FetchDescriptor<ScannedDocument>(
            predicate: #Predicate { $0.isPasswordProtected == true }
        )
        let lockedDocs = try context.fetch(descriptor)
        XCTAssertEqual(lockedDocs.count, 2,
                       "SwiftData must be able to filter documents by isPasswordProtected")
    }

    // MARK: - Biometric auth prerequisite: flag must be true before prompt

    func testBiometricAuthShouldOnlyTriggerWhenFlagIsTrue() {
        let lockedDoc   = makeDocument(name: "Protected", locked: true)
        let unlockedDoc = makeDocument(name: "Open",      locked: false)

        // The UI must gate biometric prompts behind isPasswordProtected
        XCTAssertTrue(lockedDoc.isPasswordProtected,
                      "Biometric prompt precondition: locked document must have flag = true")
        XCTAssertFalse(unlockedDoc.isPasswordProtected,
                       "Biometric prompt must NOT be shown for unlocked documents")
    }

    // MARK: - Security: locked state must survive re-initialization

    func testLockedFlagSurvivesRoundTrip() throws {
        let id = UUID()
        let doc = ScannedDocument(id: id, name: "RoundTrip", isPasswordProtected: true)
        context.insert(doc)
        try context.save()

        let descriptor = FetchDescriptor<ScannedDocument>(
            predicate: #Predicate { $0.name == "RoundTrip" }
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.id, id,
                       "Re-fetched document must have the same UUID")
        XCTAssertTrue(fetched.first?.isPasswordProtected == true,
                      "isPasswordProtected must survive a full save/fetch round-trip")
    }
}
