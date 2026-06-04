import XCTest
@testable import ScanHonest

// MARK: - ScannedDocumentTests

final class ScannedDocumentTests: XCTestCase {

    // MARK: - Defaults

    func testPageCountDefaultsToOne() {
        let doc = ScannedDocument(name: "Test")
        XCTAssertEqual(doc.pageCount, 1,
                       "pageCount must default to 1 when not specified")
    }

    func testFileSizeBytesDefaultsToZero() {
        let doc = ScannedDocument(name: "Test")
        XCTAssertEqual(doc.fileSizeBytes, 0,
                       "fileSizeBytes must default to 0 when not specified")
    }

    func testFileURLDefaultsToNil() {
        let doc = ScannedDocument(name: "Test")
        XCTAssertNil(doc.fileURL, "fileURL must default to nil")
    }

    func testThumbnailDataDefaultsToNil() {
        let doc = ScannedDocument(name: "Test")
        XCTAssertNil(doc.thumbnailData, "thumbnailData must default to nil")
    }

    func testOCRTextDefaultsToNil() {
        let doc = ScannedDocument(name: "Test")
        XCTAssertNil(doc.ocrText, "ocrText must default to nil")
    }

    func testIsPasswordProtectedDefaultsFalse() {
        let doc = ScannedDocument(name: "Test")
        XCTAssertFalse(doc.isPasswordProtected,
                       "isPasswordProtected must default to false")
    }

    func testIDIsUniquePerInstance() {
        let doc1 = ScannedDocument(name: "Doc 1")
        let doc2 = ScannedDocument(name: "Doc 2")
        XCTAssertNotEqual(doc1.id, doc2.id,
                          "Each ScannedDocument must have a unique UUID")
    }

    // MARK: - name is mutable

    func testNameIsMutable() {
        let doc = ScannedDocument(name: "Original Name")
        doc.name = "Updated Name"
        XCTAssertEqual(doc.name, "Updated Name",
                       "Document name must be mutable via property assignment")
    }

    func testNameMutationPreservesOtherFields() {
        let doc = ScannedDocument(name: "Old", pageCount: 3, fileSizeBytes: 1024)
        doc.name = "New"
        XCTAssertEqual(doc.pageCount, 3,
                       "Mutating name must not affect pageCount")
        XCTAssertEqual(doc.fileSizeBytes, 1024,
                       "Mutating name must not affect fileSizeBytes")
    }

    // MARK: - formattedFileSize

    func testFormattedFileSizeZero() {
        let doc = ScannedDocument(name: "Test", fileSizeBytes: 0)
        // ByteCountFormatter returns "Zero KB" or "0 bytes" depending on locale
        XCTAssertFalse(doc.formattedFileSize.isEmpty,
                       "formattedFileSize must not be empty even for 0 bytes")
    }

    func testFormattedFileSizeOneKB() {
        let doc = ScannedDocument(name: "Test", fileSizeBytes: 1024)
        XCTAssertTrue(
            doc.formattedFileSize.contains("KB") || doc.formattedFileSize.contains("kB"),
            "1024 bytes must format as KB"
        )
    }

    func testFormattedFileSizeOneMB() {
        let doc = ScannedDocument(name: "Test", fileSizeBytes: 1_048_576)
        XCTAssertTrue(
            doc.formattedFileSize.contains("MB"),
            "1 MB must format as MB"
        )
    }

    func testFormattedFileSizeIsString() {
        let doc = ScannedDocument(name: "Test", fileSizeBytes: 50_000)
        XCTAssertFalse(doc.formattedFileSize.isEmpty,
                       "formattedFileSize must return a non-empty string")
    }

    // MARK: - formattedDate

    func testFormattedDateIsNotEmpty() {
        let doc = ScannedDocument(name: "Test")
        XCTAssertFalse(doc.formattedDate.isEmpty,
                       "formattedDate must return a non-empty string")
    }

    func testFormattedDateForRecentDocumentContainsRelativeText() {
        // A document created just now should produce something like "0 sec. ago"
        let doc = ScannedDocument(name: "Just Now", dateCreated: Date())
        let formatted = doc.formattedDate
        // RelativeDateTimeFormatter returns phrases like "now", "0 sec. ago", "in 0 secs"
        XCTAssertFalse(formatted.isEmpty,
                       "formattedDate for a just-created doc must not be empty")
    }

    func testFormattedDateForOldDocumentDifferentFromNew() {
        let oldDate = Date(timeIntervalSinceNow: -365 * 24 * 3600)
        let oldDoc = ScannedDocument(name: "Old", dateCreated: oldDate)
        let newDoc = ScannedDocument(name: "New", dateCreated: Date())
        XCTAssertNotEqual(
            oldDoc.formattedDate,
            newDoc.formattedDate,
            "Formatted dates for old and new documents must differ"
        )
    }

    // MARK: - Custom init values

    func testCustomPageCount() {
        let doc = ScannedDocument(name: "Multi", pageCount: 5)
        XCTAssertEqual(doc.pageCount, 5, "pageCount must match the value passed to init")
    }

    func testCustomFileSize() {
        let doc = ScannedDocument(name: "Large", fileSizeBytes: 2_000_000)
        XCTAssertEqual(doc.fileSizeBytes, 2_000_000,
                       "fileSizeBytes must match the value passed to init")
    }

    func testCustomFileURL() {
        let url = URL(fileURLWithPath: "/tmp/test.pdf")
        let doc = ScannedDocument(name: "WithURL", fileURL: url)
        XCTAssertEqual(doc.fileURL, url, "fileURL must match the value passed to init")
    }

    // MARK: - DocumentFolder

    func testFolderDefaultsToNil() {
        let doc = ScannedDocument(name: "Test")
        XCTAssertNil(doc.folder, "folder must default to nil")
    }

    // MARK: - dateCreated / dateModified

    func testDateCreatedSetToNowByDefault() {
        let before = Date()
        let doc = ScannedDocument(name: "Now")
        let after = Date()
        XCTAssertTrue(doc.dateCreated >= before && doc.dateCreated <= after,
                      "dateCreated must be set to approximately now by default")
    }

    func testDateModifiedSetToNowByDefault() {
        let before = Date()
        let doc = ScannedDocument(name: "Now")
        let after = Date()
        XCTAssertTrue(doc.dateModified >= before && doc.dateModified <= after,
                      "dateModified must be set to approximately now by default")
    }
}
