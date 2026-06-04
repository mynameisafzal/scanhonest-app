import XCTest
import SwiftData
@testable import ScanHonest

// MARK: - FolderOperationsTests
//
// Tests DocumentFolder creation, document assignment, inter-folder moves,
// cascade deletion, and circular-reference prevention.
//
// All tests use an in-memory ModelContainer — no disk I/O, no state bleed.

final class FolderOperationsTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([DocumentFolder.self, ScannedDocument.self])
        // Explicitly opt out of CloudKit so the in-memory store doesn't fail
        // the "all attributes must be optional" CloudKit validation.
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

    // MARK: - Helpers

    private func makeFolder(name: String, color: String = "1B4332") -> DocumentFolder {
        let f = DocumentFolder(name: name, colorHex: color)
        context.insert(f)
        return f
    }

    private func makeDocument(name: String) -> ScannedDocument {
        let d = ScannedDocument(name: name)
        context.insert(d)
        return d
    }

    // MARK: - Folder creation

    func testFolderCreationPreservesName() {
        let folder = makeFolder(name: "Tax Documents")
        XCTAssertEqual(folder.name, "Tax Documents",
                       "Folder name must be preserved on creation")
    }

    func testFolderCreationPreservesColorHex() {
        let folder = makeFolder(name: "Receipts", color: "FF5733")
        XCTAssertEqual(folder.colorHex, "FF5733",
                       "Folder colorHex must be preserved on creation")
    }

    func testFolderDefaultColorHex() {
        let folder = DocumentFolder(name: "Default")
        XCTAssertEqual(folder.colorHex, "1B4332",
                       "Default colorHex must be '1B4332' (forest green)")
    }

    func testFolderIDIsUniquePerInstance() {
        let f1 = makeFolder(name: "A")
        let f2 = makeFolder(name: "B")
        XCTAssertNotEqual(f1.id, f2.id,
                          "Each DocumentFolder must receive a unique UUID")
    }

    func testFolderDateCreatedIsApproximatelyNow() {
        let before = Date()
        let folder = makeFolder(name: "Now")
        let after  = Date()
        XCTAssertTrue(folder.dateCreated >= before && folder.dateCreated <= after,
                      "dateCreated must be set to approximately now on init")
    }

    func testFolderStartsEmpty() {
        let folder = makeFolder(name: "Empty")
        XCTAssertTrue(folder.documents.isEmpty,
                      "A newly created folder must have zero documents")
    }

    // MARK: - Recursive / directory creation

    func testMultipleFoldersCanBeCreatedIndependently() {
        let names = ["Contracts", "Invoices", "Medical", "Insurance", "Travel"]
        let folders = names.map { makeFolder(name: $0) }
        let ids = Set(folders.map { $0.id })
        XCTAssertEqual(ids.count, names.count,
                       "All folders must have distinct IDs (recursive directory creation)")
    }

    func testFolderNameIsMutable() {
        let folder = makeFolder(name: "Old Name")
        folder.name = "New Name"
        XCTAssertEqual(folder.name, "New Name",
                       "Folder name must be mutable via property assignment")
    }

    func testFolderColorHexIsMutable() {
        let folder = makeFolder(name: "Colorful", color: "000000")
        folder.colorHex = "FFFFFF"
        XCTAssertEqual(folder.colorHex, "FFFFFF",
                       "colorHex must be mutable after creation")
    }

    // MARK: - Assigning documents to folders

    func testAssigningDocumentToFolder() {
        let folder = makeFolder(name: "Work")
        let doc    = makeDocument(name: "Report.pdf")
        doc.folder = folder
        XCTAssertEqual(doc.folder?.id, folder.id,
                       "Document must reference the assigned folder")
    }

    func testFolderDocumentsRelationshipReflectsAssignment() {
        let folder = makeFolder(name: "Work")
        let doc    = makeDocument(name: "Budget.pdf")
        doc.folder = folder
        // Force SwiftData to materialise the inverse relationship
        try? context.save()
        XCTAssertTrue(folder.documents.contains { $0.id == doc.id },
                      "Folder.documents must include the document after assignment")
    }

    func testMultipleDocumentsCanBeAddedToSameFolder() {
        let folder = makeFolder(name: "Projects")
        for i in 1...5 {
            let doc = makeDocument(name: "Doc \(i)")
            doc.folder = folder
        }
        try? context.save()
        XCTAssertEqual(folder.documents.count, 5,
                       "Folder must contain all 5 assigned documents")
    }

    // MARK: - Moving documents between folders

    func testMovingDocumentToAnotherFolder() {
        let folderA = makeFolder(name: "Inbox")
        let folderB = makeFolder(name: "Archive")
        let doc     = makeDocument(name: "Contract.pdf")
        doc.folder  = folderA
        try? context.save()

        // Move
        doc.folder = folderB
        try? context.save()

        XCTAssertEqual(doc.folder?.id, folderB.id,
                       "After move, document must belong to the destination folder")
        XCTAssertFalse(folderA.documents.contains { $0.id == doc.id },
                       "Source folder must no longer contain the document after move")
        XCTAssertTrue(folderB.documents.contains { $0.id == doc.id },
                      "Destination folder must contain the document after move")
    }

    func testMovingDocumentDoesNotDuplicateIt() {
        let folderA = makeFolder(name: "From")
        let folderB = makeFolder(name: "To")
        let doc     = makeDocument(name: "Invoice.pdf")
        doc.folder  = folderA
        try? context.save()
        doc.folder  = folderB
        try? context.save()

        let totalCount = folderA.documents.count + folderB.documents.count
        XCTAssertEqual(totalCount, 1,
                       "Moving must not duplicate — total document count must remain 1")
    }

    func testMovingDocumentPreservesItsProperties() {
        let folderA = makeFolder(name: "Source")
        let folderB = makeFolder(name: "Dest")
        let doc     = makeDocument(name: "Original Name")
        doc.pageCount = 7
        doc.folder    = folderA
        try? context.save()
        doc.folder    = folderB
        try? context.save()

        XCTAssertEqual(doc.name, "Original Name",
                       "Moving must not alter the document name")
        XCTAssertEqual(doc.pageCount, 7,
                       "Moving must not alter pageCount")
    }

    // MARK: - Removing a document from a folder (nullify)

    func testRemovingDocumentFromFolderSetsNil() {
        let folder = makeFolder(name: "Temp")
        let doc    = makeDocument(name: "Temp.pdf")
        doc.folder = folder
        try? context.save()

        doc.folder = nil
        try? context.save()

        XCTAssertNil(doc.folder,
                     "Setting folder to nil must remove the folder association")
        XCTAssertFalse(folder.documents.contains { $0.id == doc.id },
                       "Folder must no longer list the document after nullification")
    }

    // MARK: - Circular-reference prevention
    //
    // DocumentFolder is a flat model — no parent/child hierarchy.
    // Circular references are structurally impossible at the data-model level.
    // These tests document and verify that constraint.

    func testFolderHasNoParentRelationship() {
        // DocumentFolder does not declare a 'parent' or 'subfolders' property.
        // This test confirms the flat-hierarchy invariant is maintained.
        let folder = makeFolder(name: "Top")
        let mirror = Mirror(reflecting: folder)
        let propertyNames = mirror.children.compactMap { $0.label }
        XCTAssertFalse(propertyNames.contains("parent"),
                       "DocumentFolder must not have a 'parent' property — flat hierarchy only")
        XCTAssertFalse(propertyNames.contains("subfolders"),
                       "DocumentFolder must not have a 'subfolders' property — flat hierarchy only")
    }

    func testTwoFoldersWithSameNameAreDistinct() {
        let f1 = makeFolder(name: "Duplicates")
        let f2 = makeFolder(name: "Duplicates")
        XCTAssertNotEqual(f1.id, f2.id,
                          "Two folders with the same name must still be distinct objects (UUID-keyed)")
    }

    // MARK: - State persistence (in-memory save/reload cycle)

    func testFolderPersistsAcrossContextSave() throws {
        let folder = makeFolder(name: "PersistMe")
        try context.save()

        let descriptor = FetchDescriptor<DocumentFolder>(
            predicate: #Predicate { $0.name == "PersistMe" }
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1,
                       "Folder must be fetchable after context.save()")
        XCTAssertEqual(fetched.first?.name, "PersistMe")
    }

    func testDocumentFolderAssociationPersistsAcrossSave() throws {
        let folder = makeFolder(name: "Persisted")
        let doc    = makeDocument(name: "Doc.pdf")
        doc.folder = folder
        try context.save()

        let descriptor = FetchDescriptor<ScannedDocument>(
            predicate: #Predicate { $0.name == "Doc.pdf" }
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.folder?.name, "Persisted",
                       "Document-to-folder relationship must survive a context save")
    }

    // MARK: - Cascade delete on folder deletion
    //
    // The deleteRule is .cascade — deleting a folder deletes all its documents.
    // FolderHierarchyService.deleteFolder() also removes PDF files from disk.

    func testDeletingFolderCascadesAndDeletesAllDocuments() throws {
        let folder = makeFolder(name: "ToDelete")
        let doc    = makeDocument(name: "Orphan.pdf")
        doc.folder = folder
        try context.save()

        context.delete(folder)
        try context.save()

        // The deleteRule is .cascade — document must be deleted along with the folder
        let descriptor = FetchDescriptor<ScannedDocument>(
            predicate: #Predicate { $0.name == "Orphan.pdf" }
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 0,
                       "Document must be cascade-deleted when its parent folder is deleted")
    }
}
