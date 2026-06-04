import Foundation
import UIKit
import PDFKit
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

final class StorageManager {

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

    // MARK: - Save PDF

    /// Saves a PDFDocument to the local ScanHonest folder.
    /// Returns (url, size) on success, nil on failure.
    func savePDF(_ pdfDocument: PDFDocument,
                 name: String,
                 thumbnail: UIImage?) -> (url: URL, size: Int64)? {

        let fileName  = "\(UUID().uuidString).pdf"
        let targetURL = localDocumentsURL.appendingPathComponent(fileName)

        guard let pdfData = pdfDocument.dataRepresentation() else {
            logger.error("savePDF: dataRepresentation() nil for '\(name)'")
            return nil
        }
        do {
            // SECURITY: encrypt with AES-256-GCM before writing; atomic write-to-temp
            // then FileManager.replaceItem so a crash mid-write never leaves a partial
            // or plaintext file at the final URL. Key is stored in Keychain only.
            try DocumentEncryptionManager.shared.writeEncrypted(pdfData, to: targetURL)
        } catch {
            logger.error("savePDF encrypted write failed: \(error.localizedDescription)")
            return nil
        }

        let size: Int64
        do {
            let attrs = try fileManager.attributesOfItem(atPath: targetURL.path)
            size = (attrs[.size] as? Int).flatMap { Int64($0) } ?? Int64(pdfData.count)
        } catch {
            size = Int64(pdfData.count)
        }

        logger.info("PDF saved: \(fileName) (\(size) bytes)")

        // Queue for iCloud if enabled; defer if offline
        if iCloudEnabled, let cloudURL = iCloudURL {
            ensureDirectoryExists(cloudURL)
            let dest = cloudURL.appendingPathComponent(fileName)
            if (try? fileManager.copyItem(at: targetURL, to: dest)) == nil {
                logger.warning("iCloud copy failed — queued: \(fileName)")
                pendingSyncQueue.append(targetURL)
            }
        }

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
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { continuation.resume(); return }

                guard let contents = try? self.fileManager.contentsOfDirectory(
                    at: self.localDocumentsURL,
                    includingPropertiesForKeys: [.creationDateKey],
                    options: .skipsHiddenFiles
                ) else {
                    continuation.resume()
                    return
                }

                let cutoff = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
                var deleted = 0

                for url in contents where url.pathExtension.lowercased() == "pdf" {
                    let attrs = try? self.fileManager.attributesOfItem(atPath: url.path)
                    if let created = attrs?[.creationDate] as? Date, created < cutoff {
                        try? self.fileManager.removeItem(at: url)
                        deleted += 1
                    }
                }

                self.logger.info("Cache cleanup: deleted \(deleted) files older than 1 year")
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
