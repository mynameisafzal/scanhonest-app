import Foundation
import UIKit
import PDFKit
import UniformTypeIdentifiers
import LinkPresentation
import MessageUI
import os.log

// MARK: - Share target
//
// Typed enum for every destination button in the share sheet.
// This replaces all string-switch logic and makes exhaustive handling
// enforceable at compile time.

enum ShareTarget {
    case airDrop
    case messages
    case mail
    case whatsApp
    case drive
    case dropbox
    case notes
    case files
    case print          // UIPrintInteractionController — NOT UIActivityViewController
    case moreOptions
    case nearbyShare    // handled in-app via MultipeerConnectivity
}

// MARK: - Export format

enum ShareExportFormat {
    case pdf
    case pdfCompact
    case jpeg
    case text
}

// MARK: - Errors

enum ShareExportError: LocalizedError {
    case noFileURL
    case emptySourceFile
    case exportFailed(String)
    case noOCRText
    case emptyFile(String)
    case fileMissing(String)
    case noFilesPrepared

    var errorDescription: String? {
        switch self {
        case .noFileURL:
            return "This document has no saved file. Please re-scan or re-import it."
        case .emptySourceFile:
            return "The document file appears to be empty. Please re-scan."
        case .exportFailed(let detail):
            return "Export failed: \(detail)"
        case .noOCRText:
            return "No OCR text found. Run OCR on this document first (tap the OCR button in the viewer), then share as Text."
        case .emptyFile(let name):
            return "Exported file \"\(name)\" is empty. Please try again."
        case .fileMissing(let name):
            return "Exported file \"\(name)\" could not be found. Please try again."
        case .noFilesPrepared:
            return "No files were prepared for sharing."
        }
    }
}

// MARK: - RichShareItem  (UIActivityItemSource + LPLinkMetadata)
//
// Wraps a file URL with document metadata so UIActivityViewController's header
// shows the document name + thumbnail instead of a raw file path.
// activityViewControllerLinkMetadata(_:) is called before the sheet renders,
// so the preview is synchronous — no async flicker.

final class RichShareItem: NSObject, UIActivityItemSource {
    private let url:      URL
    private let metadata: LPLinkMetadata

    init(url: URL, title: String, thumbnailData: Data?) {
        self.url  = url
        metadata  = LPLinkMetadata()
        metadata.title       = title
        metadata.originalURL = url
        if let data = thumbnailData, let img = UIImage(data: data) {
            metadata.iconProvider  = NSItemProvider(object: img)
            metadata.imageProvider = NSItemProvider(object: img)
        }
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ vc: UIActivityViewController) -> Any { url }
    func activityViewController(_ vc: UIActivityViewController,
                                itemForActivityType type: UIActivity.ActivityType?) -> Any? { url }
    func activityViewControllerLinkMetadata(_ vc: UIActivityViewController) -> LPLinkMetadata? { metadata }
}

// MARK: - ShareExportService
//
// Single source of truth for ALL file export and share/print presentation.
//
// Thread safety design:
//   • All SwiftData model property reads happen on @MainActor inside
//     prepareURLs(for:format:) before any async work begins.
//   • File I/O is done on Task.detached (background) via the async variants.
//   • All UIKit presentation (UIActivityViewController, UIPrintInteractionController)
//     is dispatched to @MainActor.
//
// This is why the Library screen was broken:
//   The old code called exportForSharing(document:format:) from DispatchQueue.global,
//   which read ScannedDocument properties off the @MainActor — a SwiftData model
//   can only be safely accessed on the thread that owns its ModelContext.
//   Reading fileURL or ocrText from a background thread returned nil or crashed.
//
// Fix:
//   prepareURLs(for:format:) is now an async function marked @MainActor.
//   It snapshots all needed model values on main, then dispatches file I/O
//   to a background Task, then returns the URLs back to main.

@MainActor
final class ShareExportService {

    static let shared = ShareExportService()
    private init() {}

    private let logger = Logger(subsystem: "com.afzal.ScanHonest", category: "ShareExport")

    // MARK: - Primary async export entry point
    //
    // Step 1: snapshot SwiftData model properties on @MainActor (safe).
    // Step 2: do file I/O off-main via Task.detached.
    // Step 3: validate and return URLs.
    //
    // Throws ShareExportError with a user-readable message on any failure.

    func prepareURLs(
        for document: ScannedDocument,
        format: ShareExportFormat
    ) async throws -> [URL] {

        // ── Snapshot all model properties on @MainActor ──────────────────
        // Never pass 'document' into Task.detached — SwiftData @Model objects
        // are not Sendable and must not be accessed off their actor context.
        let sourceURL   = document.fileURL
        let docName     = document.name
        let ocrText     = document.ocrText
        let pageCount   = document.pageCount

        logger.info("prepareURLs: doc='\(docName)' format=\(String(describing: format)) fileURL=\(sourceURL?.path ?? "nil")")

        // ── Validate source ───────────────────────────────────────────────
        if format != .text {
            guard let src = sourceURL else { throw ShareExportError.noFileURL }
            guard FileManager.default.fileExists(atPath: src.path) else {
                throw ShareExportError.fileMissing(src.lastPathComponent)
            }
            let attrs = try FileManager.default.attributesOfItem(atPath: src.path)
            let size  = (attrs[.size] as? Int) ?? 0
            guard size > 0 else { throw ShareExportError.emptySourceFile }
        }

        // ── Pre-decrypt PDF on @MainActor ─────────────────────────────────
        // StorageManager.shared is a non-Sendable class; calling it from a
        // nonisolated Task.detached triggers Swift 6 actor-isolation warnings.
        // We resolve the decrypted Data here (still on @MainActor) and pass
        // it as a plain Sendable value into the detached task.
        let preloadedPDFData: Data?
        if (format == .pdf || format == .pdfCompact), let src = sourceURL {
            preloadedPDFData = StorageManager.shared.loadPDF(from: src)?.dataRepresentation()
        } else {
            preloadedPDFData = nil
        }

        // ── File I/O off-main ─────────────────────────────────────────────
        let urls: [URL] = try await Task.detached(priority: .userInitiated) {
            switch format {
            case .pdf:
                let url = try Self.exportPDF(
                    sourceURL: sourceURL!,
                    name: docName,
                    compact: false,
                    preloadedData: preloadedPDFData
                )
                return [url]

            case .pdfCompact:
                let url = try Self.exportPDF(
                    sourceURL: sourceURL!,
                    name: docName,
                    compact: true,
                    preloadedData: preloadedPDFData
                )
                return [url]

            case .jpeg:
                return try Self.exportJPEG(
                    sourceURL: sourceURL!,
                    name: docName,
                    pageCount: pageCount
                )

            case .text:
                guard let text = ocrText, !text.isEmpty else {
                    throw ShareExportError.noOCRText
                }
                let url = try Self.exportText(text: text, name: docName)
                return [url]
            }
        }.value

        // ── Validate output ───────────────────────────────────────────────
        guard !urls.isEmpty else { throw ShareExportError.noFilesPrepared }
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ShareExportError.fileMissing(url.lastPathComponent)
            }
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size  = (attrs[.size] as? Int64) ?? 0
            guard size > 0 else { throw ShareExportError.emptyFile(url.lastPathComponent) }
            logger.info("prepareURLs: ready \(url.lastPathComponent) (\(size) bytes)")
        }

        return urls
    }

    // MARK: - Password-protected PDF export
    //
    // Mirrors prepareURLs(for:format:) but wraps the output PDF with
    // AES-128 user and owner passwords via PDFKit's write options.
    // Only PDF and PDF·sm formats support password protection;
    // callers should gate this on format == .pdf || .pdfCompact.

    func prepareURLsWithPassword(
        for document: ScannedDocument,
        format: ShareExportFormat,
        password: String
    ) async throws -> [URL] {
        let sourceURL = document.fileURL
        let docName   = document.name

        guard let src = sourceURL else { throw ShareExportError.noFileURL }
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw ShareExportError.fileMissing(src.lastPathComponent)
        }

        // Snapshot `compact` on @MainActor — evaluating ShareExportFormat.== inside
        // Task.detached triggers a Swift 6 warning because the synthesised Equatable
        // conformance is inferred as @MainActor-isolated in this file.
        let compact = (format == .pdfCompact)

        let urls: [URL] = try await Task.detached(priority: .userInitiated) {
            let url = try Self.exportPDFWithPassword(
                sourceURL: src,
                name: docName,
                compact: compact,
                password: password
            )
            return [url]
        }.value

        guard !urls.isEmpty else { throw ShareExportError.noFilesPrepared }
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ShareExportError.fileMissing(url.lastPathComponent)
            }
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size  = (attrs[.size] as? Int64) ?? 0
            guard size > 0 else { throw ShareExportError.emptyFile(url.lastPathComponent) }
            logger.info("prepareURLsWithPassword: ready \(url.lastPathComponent) (\(size) bytes)")
        }
        return urls
    }

    private nonisolated static func exportPDFWithPassword(
        sourceURL: URL,
        name: String,
        compact: Bool,
        password: String
    ) throws -> URL {
        let safeName = safeFSName(name)
        let destURL  = FileManager.default.temporaryDirectory
                           .appendingPathComponent("\(safeName)_protected.pdf")
        try? FileManager.default.removeItem(at: destURL)

        guard let pdf = PDFDocument(url: sourceURL) else {
            throw ShareExportError.exportFailed("Could not open PDF for password protection")
        }

        let options: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption:  password,
            .ownerPasswordOption: password,
        ]

        guard pdf.write(to: destURL, withOptions: options) else {
            throw ShareExportError.exportFailed("Password-protected PDF write failed")
        }

        return destURL
    }

    // MARK: - Present share sheet
    //
    // Called AFTER prepareURLs resolves. Walks the VC hierarchy to find
    // the topmost presented controller, configures the popover anchor for
    // iPad, and registers the cleanup handler.

    func present(
        urls: [URL],
        target: ShareTarget,
        cleanup: @escaping ([URL]) -> Void
    ) {
        guard let top = Self.topmostVC() else {
            logger.error("present: could not find topmost VC")
            cleanup(urls)
            return
        }

        let av = UIActivityViewController(
            activityItems: urls,
            applicationActivities: nil
        )

        // Apply exclusion list based on target
        let excluded = Self.excludedTypes(for: target)
        if !excluded.isEmpty {
            av.excludedActivityTypes = excluded
        }

        av.completionWithItemsHandler = { activityType, completed, _, error in
            self.logger.info("share completed: target=\(String(describing: activityType?.rawValue ?? "nil")) completed=\(completed)")
            cleanup(urls)
        }

        // iPad requires a popover anchor or it crashes
        if let pop = av.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(
                x: top.view.bounds.midX,
                y: top.view.bounds.midY,
                width: 1, height: 1
            )
            pop.permittedArrowDirections = []
        }

        logger.info("presenting UIActivityViewController for target=\(String(describing: target))")
        top.present(av, animated: true)
    }

    // MARK: - Present with rich LPLinkMetadata preview
    //
    // Preferred presenter for all share targets except Print and Mail.
    // Wraps URLs in RichShareItem so the system sheet header shows the
    // document name and thumbnail rather than a bare file path.

    func presentRich(
        urls:          [URL],
        target:        ShareTarget,
        docName:       String,
        thumbnailData: Data?,
        cleanup:       @escaping ([URL]) -> Void
    ) {
        guard let top = Self.topmostVC() else { cleanup(urls); return }

        let items: [Any] = urls.map { RichShareItem(url: $0, title: docName, thumbnailData: thumbnailData) }
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)

        let excluded = Self.excludedTypes(for: target)
        if !excluded.isEmpty { av.excludedActivityTypes = excluded }

        av.completionWithItemsHandler = { activityType, completed, _, _ in
            self.logger.info("share completed: target=\(String(describing: activityType?.rawValue ?? "nil")) completed=\(completed)")
            cleanup(urls)
        }

        if let pop = av.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }

        logger.info("presentRich: target=\(String(describing: target))")
        top.present(av, animated: true)
    }

    // MARK: - Direct mail composition
    //
    // Uses MFMailComposeViewController when the device has at least one mail account
    // configured — skips UIActivityViewController entirely (zero extra taps for mail).
    // Falls back to presentRich(.mail) on unprovisioned devices.

    private var mailCoordinator: MailCoordinator?

    func presentMailComposer(
        urls:          [URL],
        docName:       String,
        thumbnailData: Data?,
        cleanup:       @escaping ([URL]) -> Void
    ) {
        guard MFMailComposeViewController.canSendMail() else {
            logger.info("presentMailComposer: no mail account — falling back to system sheet")
            presentRich(urls: urls, target: .mail, docName: docName, thumbnailData: thumbnailData, cleanup: cleanup)
            return
        }
        guard let top = Self.topmostVC() else { cleanup(urls); return }

        let coordinator = MailCoordinator { [weak self] in
            self?.mailCoordinator = nil
            cleanup(urls)
        }
        mailCoordinator = coordinator   // retain for delegate lifetime

        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = coordinator
        composer.setSubject(docName)

        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime: String
            switch url.pathExtension.lowercased() {
            case "pdf":         mime = "application/pdf"
            case "jpg", "jpeg": mime = "image/jpeg"
            case "zip":         mime = "application/zip"
            default:            mime = "application/octet-stream"
            }
            composer.addAttachmentData(data, mimeType: mime, fileName: url.lastPathComponent)
        }

        logger.info("presentMailComposer: presenting for '\(docName)'")
        top.present(composer, animated: true)
    }

    // MARK: - Print
    //
    // UIPrintInteractionController is completely separate from UIActivityViewController.
    // Print must NOT use UIActivityViewController — it needs UIPrintInfo to set
    // job name, output type, and quality.

    func printDocument(url: URL, jobName: String, cleanup: @escaping () -> Void) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.error("printDocument: file missing at \(url.path)")
            cleanup()
            return
        }

        let controller = UIPrintInteractionController.shared
        let info       = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName    = jobName
        info.orientation = .portrait
        controller.printInfo    = info
        controller.printingItem = url
        // showsPageRange was deprecated in iOS 10 — the system always shows page range
        // in the print panel when applicable, so no property needs to be set.

        logger.info("presenting UIPrintInteractionController for '\(jobName)'")

        controller.present(animated: true) { _, completed, error in
            self.logger.info("print completed=\(completed) error=\(error?.localizedDescription ?? "nil")")
            cleanup()
        }
    }

    // MARK: - Cleanup

    func cleanupURLs(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
            logger.info("cleanup: removed \(url.lastPathComponent)")
        }
    }

    // MARK: - Safe filesystem name

    nonisolated static func safeFSName(_ name: String) -> String {
        let unsafe  = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name
            .components(separatedBy: unsafe)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Document" : String(cleaned.prefix(80))
    }

    // MARK: - Activity type exclusions
    //
    // For first-party system destinations (AirDrop, Messages, Mail) we exclude
    // all other SYSTEM types so iOS jumps straight to that row.
    //
    // For third-party apps (WhatsApp, Drive, Dropbox, Notes, Files) we show
    // the full sheet with NO exclusions. Third-party share extensions register
    // themselves and appear automatically when installed. There is no public
    // API to pre-select or force-open a specific third-party app.
    //
    // Notes on specific targets:
    //   • WhatsApp: appears as a share extension when WhatsApp is installed.
    //     No URL scheme approach is needed — UIActivityViewController handles it.
    //   • Google Drive / Dropbox: appear as document providers / share extensions.
    //   • Apple Notes: appears as a share extension ("Add to Notes").
    //   • Files: appears as "Save to Files" — a system activity type.

    private static let allKnownSystemTypes: [UIActivity.ActivityType] = [
        .airDrop,
        .message,
        .mail,
        .copyToPasteboard,
        .print,
        .assignToContact,
        .saveToCameraRoll,
        .addToReadingList,
        .openInIBooks,
        .markupAsPDF,
        .collaborationInviteWithLink,
        .collaborationCopyLink,
        .sharePlay,
    ]

    static func excludedTypes(for target: ShareTarget) -> [UIActivity.ActivityType] {
        switch target {
        case .airDrop:
            return allKnownSystemTypes.filter { $0 != .airDrop }
        case .messages:
            return allKnownSystemTypes.filter { $0 != .message }
        case .mail:
            return allKnownSystemTypes.filter { $0 != .mail }
        case .whatsApp, .drive, .dropbox, .notes, .files, .moreOptions:
            // Full sheet — third-party extensions appear automatically
            return []
        case .print, .nearbyShare:
            // Handled separately — should not reach UIActivityViewController
            return []
        }
    }

    // MARK: - Topmost VC helper

    static func topmostVC() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root  = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                       ?? scene.windows.first?.rootViewController
        else { return nil }
        var top = root
        // Skip past fully-presented VCs, but STOP before any VC that is currently
        // mid-dismiss.  Presenting on a VC whose dismiss animation is still running
        // causes a silent failure — UIKit queues the presentation and discards it.
        while let p = top.presentedViewController, !p.isBeingDismissed {
            top = p
        }
        return top
    }

    // MARK: - PDF export (nonisolated — called from Task.detached)

    /// - Parameter preloadedData: PDF data already decrypted on `@MainActor` by
    ///   the caller.  Passing it here avoids calling `StorageManager.shared` from
    ///   a nonisolated context, which generates Swift 6 actor-isolation warnings.
    private nonisolated static func exportPDF(
        sourceURL: URL,
        name: String,
        compact: Bool,
        preloadedData: Data? = nil
    ) throws -> URL {
        let safeName = safeFSName(name)
        let destURL  = FileManager.default.temporaryDirectory
                           .appendingPathComponent("\(safeName).pdf")
        try? FileManager.default.removeItem(at: destURL)

        // Use pre-decrypted data when available (the normal path for AES-256-GCM docs).
        // For compact mode PDFKit re-serialises on the fly; for regular mode the data
        // is written directly.  Both paths are a no-op on the main actor.
        if let data = preloadedData {
            if compact, let pdf = PDFDocument(data: data),
               let reserialised = pdf.dataRepresentation() {
                // Re-serialise: PDFKit strips redundant XObjects → smaller file
                try reserialised.write(to: destURL)
            } else {
                try data.write(to: destURL)
            }
            return destURL
        }

        // Fallback: plain/unencrypted file (UITest seed docs, legacy plaintext PDFs).
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        return destURL
    }

    // MARK: - JPEG export (nonisolated — called from Task.detached)
    //
    // Single page  → <name>.jpg
    // Multi-page   → <name>.zip containing <name>_page1.jpg, <name>_page2.jpg, …

    private nonisolated static func exportJPEG(
        sourceURL: URL,
        name: String,
        pageCount: Int
    ) throws -> [URL] {
        guard let pdf = PDFDocument(url: sourceURL) else {
            throw ShareExportError.exportFailed("Could not open PDF for JPEG conversion")
        }

        let safeName = safeFSName(name)

        if pageCount == 1 {
            let url = try renderPageAsJPEG(
                pdf: pdf, pageIndex: 0,
                destName: "\(safeName).jpg"
            )
            return [url]
        }

        // Multi-page: render all pages, build ZIP
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sh_jpeg_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        var pageURLs: [URL] = []
        for i in 0..<pdf.pageCount {
            let url = try renderPageAsJPEG(
                pdf: pdf, pageIndex: i,
                destName: "\(safeName)_page\(i + 1).jpg",
                directory: tmpDir
            )
            pageURLs.append(url)
        }

        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).zip")
        try? FileManager.default.removeItem(at: zipURL)

        guard buildZip(from: pageURLs, to: zipURL) else {
            // ZIP failed — fall back to page 1 only so the user gets something
            let fallback = try renderPageAsJPEG(
                pdf: pdf, pageIndex: 0,
                destName: "\(safeName)_page1of\(pdf.pageCount).jpg"
            )
            return [fallback]
        }

        return [zipURL]
    }

    private nonisolated static func renderPageAsJPEG(
        pdf: PDFDocument,
        pageIndex: Int,
        destName: String,
        directory: URL? = nil
    ) throws -> URL {
        guard let page = pdf.page(at: pageIndex) else {
            throw ShareExportError.exportFailed("Could not access page \(pageIndex)")
        }

        let rect  = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size  = CGSize(width: rect.width * scale, height: rect.height * scale)

        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.scaleBy(x: scale, y: scale)
            ctx.cgContext.translateBy(x: 0, y: rect.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }

        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            throw ShareExportError.exportFailed("JPEG encoding failed for page \(pageIndex)")
        }

        let base = directory ?? FileManager.default.temporaryDirectory
        let dest = base.appendingPathComponent(destName)
        try? FileManager.default.removeItem(at: dest)
        try jpeg.write(to: dest)
        return dest
    }

    // MARK: - Text export (nonisolated — called from Task.detached)

    private nonisolated static func exportText(text: String, name: String) throws -> URL {
        let safeName = safeFSName(name)
        let destURL  = FileManager.default.temporaryDirectory
                           .appendingPathComponent("\(safeName).txt")
        try? FileManager.default.removeItem(at: destURL)
        try text.write(to: destURL, atomically: true, encoding: .utf8)
        return destURL
    }

    // MARK: - ZIP builder (nonisolated — pure data, no actor access)

    private nonisolated static func buildZip(from urls: [URL], to destURL: URL) -> Bool {
        func u16le(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
        func u32le(_ v: UInt32) -> [UInt8] {
            [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
             UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
        }
        let localSig:   [UInt8] = [0x50, 0x4B, 0x03, 0x04]
        let centralSig: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
        let endSig:     [UInt8] = [0x50, 0x4B, 0x05, 0x06]

        var archive = Data(); var centralDir = Data(); var offsets = [UInt32]()

        for url in urls {
            guard let fileData = try? Data(contentsOf: url) else { continue }
            let nameBytes = Array(url.lastPathComponent.utf8)
            let nameLen   = UInt16(nameBytes.count)
            let dataLen   = UInt32(fileData.count)
            let crc       = zip_crc32(fileData)
            let offset    = UInt32(archive.count)
            offsets.append(offset)

            var local = Data(localSig)
            local.append(contentsOf: u16le(20)); local.append(contentsOf: u16le(0))
            local.append(contentsOf: u16le(0));  local.append(contentsOf: u16le(0))
            local.append(contentsOf: u16le(0));  local.append(contentsOf: u32le(crc))
            local.append(contentsOf: u32le(dataLen)); local.append(contentsOf: u32le(dataLen))
            local.append(contentsOf: u16le(nameLen)); local.append(contentsOf: u16le(0))
            local.append(contentsOf: nameBytes); local.append(fileData)
            archive.append(local)

            var central = Data(centralSig)
            central.append(contentsOf: u16le(20)); central.append(contentsOf: u16le(20))
            central.append(contentsOf: u16le(0));  central.append(contentsOf: u16le(0))
            central.append(contentsOf: u16le(0));  central.append(contentsOf: u16le(0))
            central.append(contentsOf: u32le(crc));
            central.append(contentsOf: u32le(dataLen)); central.append(contentsOf: u32le(dataLen))
            central.append(contentsOf: u16le(nameLen)); central.append(contentsOf: u16le(0))
            central.append(contentsOf: u16le(0));  central.append(contentsOf: u16le(0))
            central.append(contentsOf: u16le(0));  central.append(contentsOf: u32le(0))
            central.append(contentsOf: u32le(offset)); central.append(contentsOf: nameBytes)
            centralDir.append(central)
        }

        let centralOffset = UInt32(archive.count)
        archive.append(centralDir)
        var end = Data(endSig)
        let count = UInt16(offsets.count)
        end.append(contentsOf: u16le(0)); end.append(contentsOf: u16le(0))
        end.append(contentsOf: u16le(count)); end.append(contentsOf: u16le(count))
        end.append(contentsOf: u32le(UInt32(centralDir.count)))
        end.append(contentsOf: u32le(centralOffset))
        end.append(contentsOf: u16le(0))
        archive.append(end)

        return (try? archive.write(to: destURL)) != nil
    }

    // MARK: - MailCoordinator (MFMailComposeViewControllerDelegate)

    private final class MailCoordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss; super.init() }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            controller.dismiss(animated: true, completion: onDismiss)
        }
    }

    private nonisolated static func zip_crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        let table: [UInt32] = (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            return c
        }
        for byte in data {
            crc = (crc >> 8) ^ table[Int((crc ^ UInt32(byte)) & 0xFF)]
        }
        return crc ^ 0xFFFF_FFFF
    }
}
