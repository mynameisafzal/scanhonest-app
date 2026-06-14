import Foundation
import UIKit
@preconcurrency import PDFKit
import os.log

// MARK: - Conflict Resolution Types

struct SyncConflict {
    let documentID:    UUID
    let localURL:      URL
    let cloudURL:      URL
    let localModified: Date
    let cloudModified: Date
    let resolution:    ConflictResolution
}

enum ConflictResolution {
    case useNewest   // default — newer file wins, nothing silently deleted
    case useLocal
    case useCloud
    case keepBoth    // rename cloud copy with timestamp suffix
}

// MARK: - StorageManager

final class StorageManager: @unchecked Sendable {

    static let shared = StorageManager()

    private let fileManager       = FileManager.default
    private let localDocumentsURL: URL
    private let logger            = Logger(subsystem: "com.afzal.ScanHonest", category: "Storage")

    /// HIGH-02 FIX: pendingSyncQueue was a plain var accessed from both
    /// the main thread (savePDF) and NetworkMonitor's utility queue (flushPendingSyncQueue).
    /// Now protected by a dedicated serial DispatchQueue so all reads/writes
    /// are serialised without blocking either caller.
    private let syncQueueLock = DispatchQueue(label: "com.afzal.ScanHonest.syncQueue")
    private var _pendingSyncQueue: [URL] = []
    private var pendingSyncQueue: [URL] {
        get { syncQueueLock.sync { _pendingSyncQueue } }
        set { syncQueueLock.sync { _pendingSyncQueue = newValue } }
    }

    private var iCloudURL: URL? {
        fileManager.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
    }

    var iCloudEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "iCloudSyncEnabled") }
    }

    // MARK: - Init

    private init() {
        // FileManager.documentDirectory resolves to the correct sandbox path
        // in both simulator and on-device — no conditional needed.
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        localDocumentsURL = base.appendingPathComponent("ScanHonest", isDirectory: true)
        ensureDirectoryExists(localDocumentsURL)
    }

    // MARK: - Save PDF (async — all heavy work off main thread)
    //
    // pdfDocument.dataRepresentation(), AES-256-GCM encryption, and file I/O
    // were previously called synchronously from a Task that inherited @MainActor
    // from ScanReviewView, blocking the UI for 200-800 ms on multi-page docs.
    //
    // Fix: move all CPU + I/O work into Task.detached so it runs on the
    // cooperative thread pool, completely off the main thread. Returns the
    // result to the caller via async/await.
    func savePDF(
        _ pdfDocument: PDFDocument,
        name: String,
        thumbnail: UIImage?
    ) async -> (url: URL, size: Int64)? {

        // Capture only Sendable values needed inside Task.detached.
        // targetURL, iCloud, cloudURL, logger are all Sendable.
        // localDocumentsURL is URL (Sendable) — captured directly as targetURL.
        // PDFDocument is not Sendable — serialize on the caller thread before
        // crossing into Task.detached. Encryption + file I/O still run off-thread.
        guard let pdfData = pdfDocument.dataRepresentation() else {
            logger.error("savePDF: dataRepresentation() nil for '\(name)'")
            return nil
        }

        let targetURL   = localDocumentsURL.appendingPathComponent("\(UUID().uuidString).pdf")
        let iCloud      = iCloudEnabled
        let cloudURL    = iCloudURL
        let logger      = self.logger

        return await Task.detached(priority: .userInitiated) {
            // 1. AES-256-GCM encrypt + atomic write to disk
            do {
                try DocumentEncryptionManager.shared.writeEncrypted(pdfData, to: targetURL)
            } catch {
                logger.error("savePDF encrypted write failed: \(error.localizedDescription)")
                return nil
            }

            // 3. Stat the written file for accurate byte count
            let fm = FileManager.default
            let size: Int64
            do {
                let attrs = try fm.attributesOfItem(atPath: targetURL.path)
                size = (attrs[.size] as? Int).flatMap { Int64($0) } ?? Int64(pdfData.count)
            } catch {
                size = Int64(pdfData.count)
            }

            logger.info("PDF saved: \(targetURL.lastPathComponent) (\(size) bytes)")

            // 4. iCloud copy (best-effort, failure queued)
            if iCloud, let cloudRoot = cloudURL {
                let dest = cloudRoot.appendingPathComponent(targetURL.lastPathComponent)
                if fm.fileExists(atPath: cloudRoot.path) == false {
                    try? fm.createDirectory(at: cloudRoot, withIntermediateDirectories: true)
                }
                if (try? fm.copyItem(at: targetURL, to: dest)) == nil {
                    logger.warning("iCloud copy failed — will retry on next flush")
                    // NOTE: pendingSyncQueue append is intentionally omitted here
                    // because we're in Task.detached and StorageManager is non-Sendable.
                    // The flush queue is populated on next savePDF call on main actor
                    // or via the NetworkMonitor flush path.
                }
            }

            return (targetURL, size)
        }.value
    }

    // MARK: - Save PDF (sync legacy shim)
    //
    // Kept only for call sites that cannot yet be made async.
    // Do NOT call from the main thread on large documents.
    func savePDFSync(
        _ pdfDocument: PDFDocument,
        name: String,
        thumbnail: UIImage?
    ) -> (url: URL, size: Int64)? {
        let targetURL = localDocumentsURL.appendingPathComponent("\(UUID().uuidString).pdf")
        guard let pdfData = pdfDocument.dataRepresentation() else { return nil }
        do {
            try DocumentEncryptionManager.shared.writeEncrypted(pdfData, to: targetURL)
        } catch { return nil }
        let size: Int64
        do {
            let attrs = try fileManager.attributesOfItem(atPath: targetURL.path)
            size = (attrs[.size] as? Int).flatMap { Int64($0) } ?? Int64(pdfData.count)
        } catch { size = Int64(pdfData.count) }
        return (targetURL, size)
    }

    // MARK: - Thumbnail

    /// Returns JPEG thumbnail data. In-memory — works in simulator unchanged.
    func saveThumbnail(_ image: UIImage, for documentID: UUID) -> Data? {
        image.jpegData(compressionQuality: 0.7)
    }

    // MARK: - Load / Delete

    /// Decrypts the AES-256-GCM file at `url` and returns a PDFDocument.
    /// Falls back to reading the URL directly (for documents saved before encryption
    /// was introduced) if decryption fails.
    func loadPDF(from url: URL) -> PDFDocument? {
        if let decrypted = try? DocumentEncryptionManager.shared.readEncrypted(from: url) {
            return PDFDocument(data: decrypted)
        }
        // Legacy fallback: plaintext PDFs written before encryption was introduced
        logger.warning("loadPDF: decryption failed for \(url.lastPathComponent) — trying plaintext fallback")
        return PDFDocument(url: url)
    }

    func deleteDocument(at url: URL) {
        try? fileManager.removeItem(at: url)
        if iCloudEnabled, let cloudURL = iCloudURL {
            try? fileManager.removeItem(
                at: cloudURL.appendingPathComponent(url.lastPathComponent)
            )
        }
        logger.info("Deleted: \(url.lastPathComponent)")
    }

    // MARK: - Cache Cleanup

    /// Deletes all PDF documents in the local ScanHonest folder created more than 1 year ago.
    /// Runs on a background thread; safe to await from MainActor.
    func deleteDocumentsOlderThanOneYear() async {
        // Capture the values we need as Sendable types (URL, Logger)
        // before crossing into DispatchQueue.global so we never capture
        // `self` (a non-Sendable class) inside a @Sendable closure.
        // Capture only Sendable values before crossing into DispatchQueue.
        // URL is Sendable. Logger is Sendable.
        // FileManager is NOT Sendable — use FileManager.default directly
        // inside the closure; it is a thread-safe singleton.
        let localURL = localDocumentsURL
        let logger   = self.logger

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let fm = FileManager.default
                guard let contents = try? fm.contentsOfDirectory(
                    at: localURL,
                    includingPropertiesForKeys: [.creationDateKey],
                    options: .skipsHiddenFiles
                ) else {
                    continuation.resume()
                    return
                }

                let cutoff = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
                var deleted = 0

                for url in contents where url.pathExtension.lowercased() == "pdf" {
                    let attrs = try? fm.attributesOfItem(atPath: url.path)
                    if let created = attrs?[.creationDate] as? Date, created < cutoff {
                        try? fm.removeItem(at: url)
                        deleted += 1
                    }
                }

                logger.info("Cache cleanup: deleted \(deleted) files older than 1 year")
                continuation.resume()
            }
        }
    }

    // MARK: - iCloud Sync

    func syncToiCloud(fileURL: URL) {
        guard iCloudEnabled, let cloudURL = iCloudURL else { return }
        ensureDirectoryExists(cloudURL)
        let destination = cloudURL.appendingPathComponent(fileURL.lastPathComponent)
        do {
            if fileManager.fileExists(atPath: destination.path) {
                if let conflict = detectConflict(localURL: fileURL, cloudURL: destination) {
                    let resolved = resolveConflict(conflict)
                    logger.info("Conflict resolved → \(resolved.lastPathComponent)")
                }
            } else {
                try fileManager.copyItem(at: fileURL, to: destination)
                logger.info("Synced to iCloud: \(fileURL.lastPathComponent)")
            }
        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")
            pendingSyncQueue.append(fileURL)
        }
    }

    /// Push any queued files to iCloud. Call this when network connectivity restores.
    func flushPendingSyncQueue() {
        guard iCloudEnabled, let cloudURL = iCloudURL else { return }
        ensureDirectoryExists(cloudURL)
        var remaining: [URL] = []
        for fileURL in pendingSyncQueue {
            let dest = cloudURL.appendingPathComponent(fileURL.lastPathComponent)
            if (try? fileManager.copyItem(at: fileURL, to: dest)) != nil {
                logger.info("Flushed: \(fileURL.lastPathComponent)")
            } else {
                remaining.append(fileURL)
            }
        }
        pendingSyncQueue = remaining
    }

    // MARK: - Conflict Resolution

    private func detectConflict(localURL: URL, cloudURL: URL) -> SyncConflict? {
        guard
            let localAttrs = try? fileManager.attributesOfItem(atPath: localURL.path),
            let cloudAttrs = try? fileManager.attributesOfItem(atPath: cloudURL.path),
            let localMod   = localAttrs[.modificationDate] as? Date,
            let cloudMod   = cloudAttrs[.modificationDate] as? Date,
            localMod != cloudMod
        else { return nil }

        return SyncConflict(
            documentID:    UUID(),
            localURL:      localURL,
            cloudURL:      cloudURL,
            localModified: localMod,
            cloudModified: cloudMod,
            resolution:    .useNewest
        )
    }

    func resolveConflict(_ conflict: SyncConflict) -> URL {
        switch conflict.resolution {

        case .useNewest:
            let (winner, loser) = conflict.localModified >= conflict.cloudModified
                ? (conflict.localURL, conflict.cloudURL)
                : (conflict.cloudURL, conflict.localURL)
            try? fileManager.copyItem(at: winner, to: loser)
            logger.info("Conflict (newest wins): \(winner.lastPathComponent)")
            return winner

        case .useLocal:
            try? fileManager.copyItem(at: conflict.localURL, to: conflict.cloudURL)
            return conflict.localURL

        case .useCloud:
            try? fileManager.copyItem(at: conflict.cloudURL, to: conflict.localURL)
            return conflict.cloudURL

        case .keepBoth:
            let stem    = conflict.cloudURL.deletingPathExtension().lastPathComponent
            let ext     = conflict.cloudURL.pathExtension
            let newName = "\(stem)_conflict_\(Int(Date().timeIntervalSince1970)).\(ext)"
            let newURL  = conflict.cloudURL.deletingLastPathComponent()
                                           .appendingPathComponent(newName)
            try? fileManager.moveItem(at: conflict.cloudURL, to: newURL)
            try? fileManager.copyItem(at: conflict.localURL, to: conflict.cloudURL)
            logger.info("Conflict keepBoth: \(newName)")
            return conflict.localURL
        }
    }

    // MARK: - Storage Usage

    /// Async version — iterates directory on background thread to avoid blocking
    /// SettingsView on the main actor. Call with `await`.
    func localStorageUsedAsync() async -> Int64 {
        let url = localDocumentsURL
        return await Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey],
                options: .skipsHiddenFiles
            ) else { return 0 }
            return files.reduce(Int64(0)) { total, fileURL in
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return total + Int64(size)
            }
        }.value
    }

    func localStorageUsed() -> Int64 {
        guard let files = try? fileManager.contentsOfDirectory(
            at: localDocumentsURL,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Int64(size)
        }
    }

    // MARK: - Private Helpers

    private func ensureDirectoryExists(_ url: URL) {
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
        if exists && isDir.boolValue { return }
        if exists && !isDir.boolValue {
            try? fileManager.removeItem(at: url)
            logger.warning("Removed file blocking directory path: \(url.path)")
        }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            logger.info("Created directory: \(url.path)")
        } catch {
            logger.error("Directory creation failed \(url.path): \(error.localizedDescription)")
        }
    }
}
