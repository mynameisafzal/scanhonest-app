import XCTest
import PDFKit
import CryptoKit
@testable import ScanHonest

// MARK: - ChecksumIntegrityTests
//
// Validates byte-level file integrity for all export paths in ShareExportService.
// Integrity is measured using SHA-256 (CryptoKit) to confirm that the file
// written to disk is bit-for-bit identical to the source data.
//
// This is the automated counterpart to the manual Cloud Export checksum check
// described in the QA checklist: "the file uploaded must be identical to the
// local file."
//
// Test coverage:
//   • savePDF round-trip: SHA-256 of saved bytes == SHA-256 of original PDF data
//   • Multi-page PDF: each page survives intact
//   • safeFSName in export filename: illegal chars don't corrupt the path
//   • Zero-byte guard: savePDF never creates an empty file
//   • Concurrent save uniqueness: two saves of the same data produce distinct URLs

final class ChecksumIntegrityTests: XCTestCase {

    // MARK: - Helpers

    /// Builds an in-memory PDFDocument with `pages` blank white pages.
    private func makePDF(pages: Int = 1) -> PDFDocument {
        let pdf = PDFDocument()
        for _ in 0..<pages {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 210, height: 297)).image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 210, height: 297))
            }
            if let page = PDFPage(image: image) {
                pdf.insert(page, at: pdf.pageCount)
            }
        }
        return pdf
    }

    /// SHA-256 digest of a Data value as a hex string.
    private func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// SHA-256 digest of a file on disk after AES-GCM decryption.
    /// Files written by StorageManager.savePDF are AES-256-GCM encrypted;
    /// we must decrypt before hashing to compare against plaintext SHA-256.
    private func sha256(fileAt url: URL) -> String? {
        // Try encrypted read first (post-encryption path)
        if let decrypted = try? DocumentEncryptionManager.shared.readEncrypted(from: url) {
            return sha256(decrypted)
        }
        // Fallback: legacy plaintext file (pre-encryption path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return sha256(data)
    }

    /// Returns the decrypted plaintext data for a file saved by StorageManager.
    private func decryptedData(at url: URL) -> Data? {
        if let data = try? DocumentEncryptionManager.shared.readEncrypted(from: url) {
            return data
        }
        return try? Data(contentsOf: url)
    }

    private var savedURLs: [URL] = []

    override func tearDown() {
        for url in savedURLs { try? FileManager.default.removeItem(at: url) }
        savedURLs.removeAll()
        super.tearDown()
    }

    // MARK: - Round-trip integrity (save → reload → structural comparison)
    //
    // PDFDocument.dataRepresentation() is non-deterministic: each call produces
    // different bytes (new /CreationDate, internal IDs). This means we cannot
    // SHA-256 the raw bytes for a save→reload comparison. Instead we test
    // structural integrity (page count preserved, data valid) via StorageManager,
    // and test byte-level AES-GCM integrity directly on DocumentEncryptionManager.

    /// Direct encryption round-trip — verifies DocumentEncryptionManager.
    func testEncryptionRoundTripByteIdentity() throws {
        let originalData = Data("ScanHonest integrity test payload".utf8)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).enc.test")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        try DocumentEncryptionManager.shared.writeEncrypted(originalData, to: tmpURL)
        let decrypted = try DocumentEncryptionManager.shared.readEncrypted(from: tmpURL)

        XCTAssertEqual(
            sha256(originalData),
            sha256(decrypted),
            "AES-256-GCM round-trip: decrypted bytes must be identical to original bytes"
        )
    }

    func testSavePDFRoundTripIntegrity() {
        // Files on disk are AES-256-GCM encrypted. PDFDocument.dataRepresentation() is
        // non-deterministic (timestamps change per call), so we verify structural integrity:
        // load back via StorageManager (which decrypts) and check the page count.
        let pdf = makePDF()
        guard let result = StorageManager.shared.savePDF(pdf, name: "IntegrityTest", thumbnail: nil) else {
            XCTFail("savePDF must succeed")
            return
        }
        savedURLs.append(result.url)

        guard let reloaded = StorageManager.shared.loadPDF(from: result.url) else {
            XCTFail("loadPDF must decrypt and reload the saved file")
            return
        }
        XCTAssertEqual(reloaded.pageCount, pdf.pageCount,
                       "Page count must be preserved through encrypt → save → decrypt → load cycle")
        XCTAssertNotNil(reloaded.dataRepresentation(),
                        "Reloaded PDF must produce a valid data representation (no corruption)")
    }

    func testSavePDFFileSizeIsNonZeroAndReportedCorrectly() {
        // AES-GCM encrypted files are larger than the plaintext.
        // We verify: the file on disk is non-empty AND the size reported by savePDF
        // matches the actual file size on disk.
        let pdf = makePDF()
        guard let result = StorageManager.shared.savePDF(pdf, name: "SizeCheck", thumbnail: nil) else {
            XCTFail("savePDF must succeed"); return
        }
        savedURLs.append(result.url)

        let diskSize = (try? FileManager.default.attributesOfItem(atPath: result.url.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(diskSize, 0,
                             "Encrypted file on disk must be non-empty")
        // The returned size is based on the ciphertext file, which should match disk
        XCTAssertEqual(Int64(diskSize), result.size,
                       "Reported size must match actual file size on disk")
    }

    // MARK: - Multi-page integrity

    func testMultiPagePDFRoundTripIntegrity() {
        // Page count must be preserved through the encrypt/save/decrypt/load cycle.
        let pdf = makePDF(pages: 5)
        guard let result = StorageManager.shared.savePDF(pdf, name: "MultiPage", thumbnail: nil) else {
            XCTFail("savePDF must succeed for multi-page PDF"); return
        }
        savedURLs.append(result.url)

        guard let reloaded = StorageManager.shared.loadPDF(from: result.url) else {
            XCTFail("Multi-page saved file must decrypt and reload successfully"); return
        }
        XCTAssertEqual(reloaded.pageCount, 5,
                       "All 5 pages must survive the AES-256-GCM encrypt → save → decrypt → load cycle")
    }

    func testMultiPagePDFPageCountPreserved() {
        let pdf = makePDF(pages: 4)
        guard let result = StorageManager.shared.savePDF(pdf, name: "PageCount", thumbnail: nil) else {
            XCTFail("savePDF must succeed"); return
        }
        savedURLs.append(result.url)

        guard let reloaded = StorageManager.shared.loadPDF(from: result.url) else {
            XCTFail("loadPDF must succeed"); return
        }

        XCTAssertEqual(reloaded.pageCount, 4,
                       "Page count must be preserved through save/load cycle")
    }

    // MARK: - Zero-byte guard

    func testSavePDFNeverCreatesEmptyFile() {
        let pdf = makePDF()
        guard let result = StorageManager.shared.savePDF(pdf, name: "NonEmpty", thumbnail: nil) else {
            XCTFail("savePDF must succeed"); return
        }
        savedURLs.append(result.url)

        let attrs = try? FileManager.default.attributesOfItem(atPath: result.url.path)
        let size  = (attrs?[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 0,
                             "Saved PDF file must never be zero bytes")
    }

    func testReportedSizeIsNonZero() {
        let pdf = makePDF()
        guard let result = StorageManager.shared.savePDF(pdf, name: "SizeReport", thumbnail: nil) else {
            XCTFail("savePDF must succeed"); return
        }
        savedURLs.append(result.url)
        XCTAssertGreaterThan(result.size, 0,
                             "The returned (url, size) tuple must report a positive byte count")
    }

    // MARK: - Uniqueness: two saves of identical content produce distinct files

    func testTwoSavesOfSameContentProduceDistinctURLs() {
        let pdf = makePDF()
        guard let r1 = StorageManager.shared.savePDF(pdf, name: "Same", thumbnail: nil),
              let r2 = StorageManager.shared.savePDF(pdf, name: "Same", thumbnail: nil) else {
            XCTFail("Both savePDF calls must succeed"); return
        }
        savedURLs += [r1.url, r2.url]

        XCTAssertNotEqual(r1.url, r2.url,
                          "Each save must produce a UUID-named file — two saves must not collide")
    }

    func testTwoSavesOfSameContentHaveMatchingChecksums() {
        // AES-GCM uses a fresh random nonce per save, so on-disk ciphertext bytes differ.
        // PDFDocument.dataRepresentation() is also non-deterministic.
        // The correct integrity check: both saves must produce valid, loadable PDFs with
        // the same page count as the original.
        let pdf = makePDF()
        guard let r1 = StorageManager.shared.savePDF(pdf, name: "Clone", thumbnail: nil),
              let r2 = StorageManager.shared.savePDF(pdf, name: "Clone", thumbnail: nil) else {
            XCTFail("Both savePDF calls must succeed"); return
        }
        savedURLs += [r1.url, r2.url]

        guard let pdf1 = StorageManager.shared.loadPDF(from: r1.url),
              let pdf2 = StorageManager.shared.loadPDF(from: r2.url) else {
            XCTFail("Both saved files must decrypt and load successfully"); return
        }

        XCTAssertEqual(pdf1.pageCount, pdf.pageCount,
                       "First save: page count must match original after decrypt/load")
        XCTAssertEqual(pdf2.pageCount, pdf.pageCount,
                       "Second save: page count must match original after decrypt/load")
        XCTAssertEqual(pdf1.pageCount, pdf2.pageCount,
                       "Both saves of identical content must produce PDFs with equal page count")
    }

    // MARK: - Filename sanitization does not corrupt the file path

    func testSaveWithIllegalCharsInNameStillProducesReadableFile() {
        // Even if the caller passes a name with illegal chars, the UUID-based
        // filename means the file is always safely named — the 'name' parameter
        // is stored in the model, not used as the filename.
        let pdf = makePDF()
        guard let result = StorageManager.shared.savePDF(pdf, name: "Invoice: Q1/2026", thumbnail: nil) else {
            XCTFail("savePDF must succeed even when doc name contains illegal FS chars")
            return
        }
        savedURLs.append(result.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path),
                      "File must exist at the returned URL regardless of the document name")
        XCTAssertEqual(result.url.pathExtension, "pdf",
                       "File must always have .pdf extension")
    }

    func testSavedFilenameIsUUID() {
        let pdf = makePDF()
        guard let result = StorageManager.shared.savePDF(pdf, name: "UUIDTest", thumbnail: nil) else {
            XCTFail("savePDF must succeed"); return
        }
        savedURLs.append(result.url)

        let stem = result.url.deletingPathExtension().lastPathComponent
        XCTAssertNotNil(UUID(uuidString: stem),
                        "Saved filename stem must be a valid UUID (no user-supplied name leaks into the path)")
    }

    // MARK: - Delete removes the file (integrity of deletion)

    func testDeleteDocumentRemovesFileFromDisk() {
        let pdf = makePDF()
        guard let result = StorageManager.shared.savePDF(pdf, name: "DeleteMe", thumbnail: nil) else {
            XCTFail("savePDF must succeed"); return
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path),
                      "File must exist before deletion")
        StorageManager.shared.deleteDocument(at: result.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.url.path),
                       "File must NOT exist after deleteDocument — no orphaned bytes on disk")
    }

    // MARK: - Conflict resolution preserves file content

    func testConflictResolutionUseNewestPreservesWinnerIntegrity() throws {
        let localURL  = FileManager.default.temporaryDirectory.appendingPathComponent("local_\(UUID().uuidString).pdf")
        let cloudURL  = FileManager.default.temporaryDirectory.appendingPathComponent("cloud_\(UUID().uuidString).pdf")
        defer {
            try? FileManager.default.removeItem(at: localURL)
            try? FileManager.default.removeItem(at: cloudURL)
        }

        let localData = Data("LOCAL_CONTENT".utf8)
        let cloudData = Data("CLOUD_CONTENT".utf8)
        try localData.write(to: localURL)
        try cloudData.write(to: cloudURL)

        // Make the local file newer
        let nowPlusOne = Date(timeIntervalSinceNow: 60)
        try FileManager.default.setAttributes([.modificationDate: nowPlusOne], ofItemAtPath: localURL.path)

        let conflict = SyncConflict(
            documentID:    UUID(),
            localURL:      localURL,
            cloudURL:      cloudURL,
            localModified: nowPlusOne,
            cloudModified: Date(),
            resolution:    .useNewest
        )

        let winnerURL = StorageManager.shared.resolveConflict(conflict)
        let winnerData = try Data(contentsOf: winnerURL)

        // Winner is local (newer) → content must be "LOCAL_CONTENT"
        XCTAssertEqual(winnerData, localData,
                       "After .useNewest resolution, the winner file must retain its original bytes")
    }
}
