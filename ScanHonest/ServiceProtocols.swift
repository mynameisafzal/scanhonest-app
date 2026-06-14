import Foundation
import UIKit
@preconcurrency import PDFKit

// MARK: - ServiceProtocols.swift
//
// Protocol definitions for the four core singletons.
// Extracting these enables:
//   1. Dependency injection in SwiftUI views and services
//   2. Mock implementations in unit and UI tests (no real disk I/O, Vision, or UIKit)
//   3. Future implementation swaps without touching call sites
//
// Concrete classes (StorageManager, DocumentEncryptionManager, OCRProcessor,
// ShareExportService) conform to their respective protocols via extensions below.
// All existing call sites using .shared continue to work unchanged.

// MARK: - DocumentStorage

/// Abstracts all PDF persistence operations.
/// Replace with MockDocumentStorage in tests to avoid real file I/O.
protocol DocumentStorage: AnyObject {
    func savePDF(
        _ pdfDocument: PDFDocument,
        name: String,
        thumbnail: UIImage?
    ) async -> (url: URL, size: Int64)?

    func savePDFSync(
        _ pdfDocument: PDFDocument,
        name: String,
        thumbnail: UIImage?
    ) -> (url: URL, size: Int64)?

    func loadPDF(from url: URL) -> PDFDocument?
    func deleteDocument(at url: URL)
    func localStorageUsedAsync() async -> Int64
    func deleteDocumentsOlderThanOneYear() async
    func flushPendingSyncQueue()
    var iCloudEnabled: Bool { get set }
}

extension StorageManager: DocumentStorage {}

// MARK: - DocumentEncrypting

/// Abstracts AES-256-GCM at-rest encryption.
/// Replace with PassthroughEncryption in tests to skip crypto overhead.
protocol DocumentEncrypting: AnyObject {
    func writeEncrypted(_ data: Data, to url: URL) throws
    func readEncrypted(from url: URL) throws -> Data
}

extension DocumentEncryptionManager: DocumentEncrypting {}

// MARK: - TextExtracting

/// Abstracts Vision OCR operations.
/// Replace with MockTextExtractor in tests to avoid live Vision framework calls.
protocol TextExtracting: AnyObject {
    func extractText(from image: UIImage) async throws -> String
    func suggestFileName(from text: String) -> String
}

extension OCRProcessor: TextExtracting {}

// MARK: - DocumentSharing

/// Abstracts share sheet presentation and file preparation.
/// Replace with MockDocumentSharing in tests to avoid UIKit sheet presentation.
@MainActor
protocol DocumentSharing: AnyObject {
    func prepareURLs(
        for document: ScannedDocument,
        format: ShareExportFormat
    ) async throws -> [URL]

    func presentRich(
        urls: [URL],
        target: ShareTarget,
        docName: String,
        thumbnailData: Data?,
        cleanup: @escaping ([URL]) -> Void
    )

    func printDocument(
        url: URL,
        jobName: String,
        cleanup: @escaping () -> Void
    )

    func cleanupURLs(_ urls: [URL])
}

extension ShareExportService: DocumentSharing {}

// MARK: - Mock implementations (for testing only)
//
// These stubs satisfy all protocol requirements without touching disk, Vision,
// or UIKit. Inject them via the environment or init parameters in unit tests.

#if DEBUG

/// Passthrough encryption — writes/reads plain data. Use in tests only.
final class PassthroughEncryption: DocumentEncrypting, @unchecked Sendable {
    static let shared = PassthroughEncryption()
    private init() {}
    func writeEncrypted(_ data: Data, to url: URL) throws { try data.write(to: url) }
    func readEncrypted(from url: URL) throws -> Data { try Data(contentsOf: url) }
}

/// Returns canned OCR text immediately. Use in tests only.
final class MockTextExtractor: TextExtracting {
    var cannedText = "Mock OCR text from test"
    func extractText(from image: UIImage) async throws -> String { cannedText }
    func suggestFileName(from text: String) -> String { "Mock_Doc" }
}

#endif
