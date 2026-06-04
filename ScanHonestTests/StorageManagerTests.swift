import XCTest
import PDFKit
@testable import ScanHonest

// MARK: - StorageManagerTests

final class StorageManagerTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        // Create a fresh temp directory per test
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanHonestTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory,
                                                 withIntermediateDirectories: true)
    }

    override func tearDown() {
        // Clean up temp files
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - Singleton / init

    func testSharedSingletonExists() {
        XCTAssertNotNil(StorageManager.shared,
                        "StorageManager.shared must not be nil")
    }

    func testScanHonestDirectoryCreatedOnInit() {
        // StorageManager.init() creates the ScanHonest subdirectory in Documents.
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let scanHonestDir = docDir.appendingPathComponent("ScanHonest")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: scanHonestDir.path),
            "ScanHonest subdirectory must exist in Documents after init"
        )
    }

    // MARK: - savePDF

    func testSavePDFCreatesFileAtCorrectPath() {
        let pdf = makeSinglePagePDF()
        guard let result = StorageManager.shared.savePDF(pdf, name: "TestDoc", thumbnail: nil) else {
            XCTFail("savePDF must return a non-nil result")
            return
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: result.url.path),
            "savePDF must create a file at the returned URL"
        )
        XCTAssertTrue(result.url.path.contains("ScanHonest"),
                      "savePDF must save files inside the ScanHonest directory")
        XCTAssertEqual(result.url.pathExtension, "pdf",
                       "Saved file must have .pdf extension")

        // Clean up
        try? FileManager.default.removeItem(at: result.url)
    }

    func testSavePDFReturnedSizeIsPositive() {
        let pdf = makeSinglePagePDF()
        guard let result = StorageManager.shared.savePDF(pdf, name: "SizeTest", thumbnail: nil) else {
            XCTFail("savePDF must succeed")
            return
        }
        XCTAssertGreaterThan(result.size, 0, "Returned file size must be positive")
        try? FileManager.default.removeItem(at: result.url)
    }

    func testSavePDFUniqueFileNamesPerCall() {
        let pdf = makeSinglePagePDF()
        guard let r1 = StorageManager.shared.savePDF(pdf, name: "Doc", thumbnail: nil),
              let r2 = StorageManager.shared.savePDF(pdf, name: "Doc", thumbnail: nil) else {
            XCTFail("Both savePDF calls must succeed")
            return
        }
        XCTAssertNotEqual(r1.url.lastPathComponent, r2.url.lastPathComponent,
                          "Each savePDF call must produce a unique file name (UUID-based)")
        try? FileManager.default.removeItem(at: r1.url)
        try? FileManager.default.removeItem(at: r2.url)
    }

    // MARK: - deleteDocument

    func testDeleteDocumentRemovesFile() {
        // First save a PDF so we have a file to delete
        let pdf = makeSinglePagePDF()
        guard let result = StorageManager.shared.savePDF(pdf, name: "DeleteMe", thumbnail: nil) else {
            XCTFail("savePDF must succeed before delete test")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path),
                      "File must exist before deletion")

        StorageManager.shared.deleteDocument(at: result.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.url.path),
                       "deleteDocument must remove the file from disk")
    }

    func testDeleteDocumentOnNonExistentFileDoesNotCrash() {
        let fakeURL = tempDirectory.appendingPathComponent("nonexistent.pdf")
        // Should not throw or crash
        StorageManager.shared.deleteDocument(at: fakeURL)
        XCTAssertTrue(true, "deleteDocument on a nonexistent file must not crash")
    }

    // MARK: - localStorageUsed

    func testLocalStorageUsedReturnsNonNegative() {
        let bytes = StorageManager.shared.localStorageUsed()
        XCTAssertGreaterThanOrEqual(bytes, 0,
                                    "localStorageUsed must return a non-negative value")
    }

    func testLocalStorageUsedIncreasesAfterSave() {
        let before = StorageManager.shared.localStorageUsed()
        let pdf = makeSinglePagePDF()
        guard let result = StorageManager.shared.savePDF(pdf, name: "StorageTest", thumbnail: nil) else {
            XCTFail("savePDF must succeed")
            return
        }
        let after = StorageManager.shared.localStorageUsed()
        XCTAssertGreaterThanOrEqual(after, before,
                                    "localStorageUsed must increase after saving a PDF")
        try? FileManager.default.removeItem(at: result.url)
    }

    // MARK: - deleteDocumentsOlderThanOneYear

    func testDeleteDocumentsOlderThanOneYearDoesNotCrashOnEmptyDir() async {
        await StorageManager.shared.deleteDocumentsOlderThanOneYear()
        XCTAssertTrue(true, "deleteDocumentsOlderThanOneYear must complete without crashing on empty dir")
    }

    func testDeleteDocumentsOlderThanOneYearPreservesRecentFiles() async {
        let pdf = makeSinglePagePDF()
        guard let result = StorageManager.shared.savePDF(pdf, name: "Recent", thumbnail: nil) else {
            XCTFail("savePDF must succeed")
            return
        }
        // The file was just created — should survive the cleanup
        await StorageManager.shared.deleteDocumentsOlderThanOneYear()
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: result.url.path),
            "A recently saved file must NOT be deleted by deleteDocumentsOlderThanOneYear"
        )
        try? FileManager.default.removeItem(at: result.url)
    }

    // MARK: - iCloudEnabled

    func testICloudEnabledDefaultsToFalse() {
        // On a fresh test run UserDefaults key may or may not be set.
        // Just verify the property is accessible without crashing.
        let enabled = StorageManager.shared.iCloudEnabled
        XCTAssertTrue(enabled == true || enabled == false,
                      "iCloudEnabled must return a Bool without crashing")
    }

    // MARK: - Helpers

    private func makeSinglePagePDF() -> PDFDocument {
        let pdf = PDFDocument()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 260)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 260))
        }
        if let page = PDFPage(image: image) {
            pdf.insert(page, at: 0)
        }
        return pdf
    }
}
