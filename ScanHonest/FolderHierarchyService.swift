import Foundation
import SwiftData
import os.log

// MARK: - FolderHierarchyService
//
// Safe CRUD layer for DocumentFolder ↔ ScannedDocument hierarchy.
//
// Key guarantees:
//   • Folder delete cascades to all child documents AND removes their PDF files
//     from disk before the SwiftData records are erased. (SwiftData's .cascade
//     rule handles the DB records; we handle the filesystem ourselves here.)
//   • Document moves are atomic — the document is never left parentless mid-operation.
//   • All operations are @MainActor so they run on the SwiftData main context by
//     default. For bulk background operations, pass a background ModelContext
//     explicitly (see the async variants below).

@MainActor
final class FolderHierarchyService {

    static let shared = FolderHierarchyService()
    private let logger = Logger(subsystem: "com.afzal.ScanHonest", category: "FolderHierarchy")

    private init() {}

    // MARK: - Create Folder

    /// Creates a new folder and inserts it into `context`.
    ///
    /// - Throws: `ProGateError.featureRequiresPro(.folderOrganization)` when `isPro` is false.
    ///   This prevents service-leakage even if the UI gate was somehow bypassed.
    @discardableResult
    func createFolder(
        name:      String,
        colorHex:  String = "1B4332",
        isPro:     Bool,
        in context: ModelContext
    ) throws -> DocumentFolder {
        try ProGate.verify(.folderOrganization, isPro: isPro)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder  = DocumentFolder(
            name:      trimmed.isEmpty ? "Untitled Folder" : trimmed,
            colorHex:  colorHex
        )
        context.insert(folder)
        logger.info("Created folder '\(folder.name)'")
        return folder
    }

    // MARK: - Rename Folder

    func renameFolder(_ folder: DocumentFolder, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folder.name = trimmed
        logger.info("Renamed folder → '\(trimmed)'")
    }

    func recolorFolder(_ folder: DocumentFolder, colorHex: String) {
        folder.colorHex = colorHex
    }

    // MARK: - Move Document

    /// Moves `document` into `targetFolder`, or removes it from any folder when `nil`.
    ///
    /// - Throws: `ProGateError.featureRequiresPro(.folderOrganization)` when `isPro` is false.
    ///   Moving documents into folders is a Pro operation; removing from a folder
    ///   (targetFolder == nil) is always allowed for graceful downgrade.
    func moveDocument(_ document: ScannedDocument, to targetFolder: DocumentFolder?,
                      isPro: Bool) throws {
        // Graceful downgrade: removing a document from a folder is always allowed
        // (prevents data-loss for expired subscribers).
        if targetFolder != nil {
            try ProGate.verify(.folderOrganization, isPro: isPro)
        }
        document.folder       = targetFolder
        document.dateModified = Date()
        logger.info("Moved '\(document.name)' → '\(targetFolder?.name ?? "none")'")
    }

    /// Moves all documents from `sourceFolder` into `destinationFolder` (or inbox if nil).
    ///
    /// - Throws: `ProGateError.featureRequiresPro(.folderOrganization)` when `isPro` is false
    ///   and `destinationFolder` is non-nil.
    func moveAllDocuments(from sourceFolder: DocumentFolder,
                          to destinationFolder: DocumentFolder?,
                          isPro: Bool) throws {
        if destinationFolder != nil {
            try ProGate.verify(.folderOrganization, isPro: isPro)
        }
        for doc in sourceFolder.documents {
            doc.folder       = destinationFolder
            doc.dateModified = Date()
        }
        logger.info("Bulk-moved \(sourceFolder.documents.count) doc(s) from '\(sourceFolder.name)'")
    }

    // MARK: - Delete Folder

    /// Deletes `folder`, its SwiftData records (via .cascade), AND its files on disk.
    ///
    /// Call order matters:
    ///   1. Collect file URLs while the records still exist.
    ///   2. Remove disk files.
    ///   3. Delete folder record — SwiftData cascade removes child ScannedDocuments.
    func deleteFolder(_ folder: DocumentFolder, in context: ModelContext) {
        let name  = folder.name
        let docs  = folder.documents          // snapshot before cascade
        let count = docs.count

        // 1. Delete PDF files from disk
        removeDiskFiles(for: docs)

        // 2. Delete folder record → SwiftData .cascade removes child documents
        context.delete(folder)
        logger.info("Deleted folder '\(name)' (\(count) document(s) cascaded).")
    }

    // MARK: - Delete Document

    /// Deletes a single document record and its PDF file from disk.
    func deleteDocument(_ document: ScannedDocument, in context: ModelContext) {
        let name = document.name
        if let url = document.fileURL {
            try? FileManager.default.removeItem(at: url)
            logger.debug("Removed file: \(url.lastPathComponent)")
        }
        context.delete(document)
        logger.info("Deleted document '\(name)'")
    }

    // MARK: - Queries

    /// All folders sorted by name (ascending).
    func allFolders(in context: ModelContext) throws -> [DocumentFolder] {
        let descriptor = FetchDescriptor<DocumentFolder>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    /// All documents not assigned to any folder ("inbox").
    func inboxDocuments(in context: ModelContext) throws -> [ScannedDocument] {
        let descriptor = FetchDescriptor<ScannedDocument>(
            predicate: #Predicate { $0.folder == nil },
            sortBy:    [SortDescriptor(\.dateModified, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Documents inside `folder`, newest first.
    func documents(in folder: DocumentFolder) -> [ScannedDocument] {
        folder.documents.sorted { $0.dateModified > $1.dateModified }
    }

    /// Total byte count of all documents inside `folder`.
    func totalSize(of folder: DocumentFolder) -> Int64 {
        folder.documents.reduce(0) { $0 + $1.fileSizeBytes }
    }

    // MARK: - Private Helpers

    private func removeDiskFiles(for documents: [ScannedDocument]) {
        let fm = FileManager.default
        for doc in documents {
            guard let url = doc.fileURL else { continue }
            do {
                try fm.removeItem(at: url)
                logger.debug("Removed \(url.lastPathComponent)")
            } catch {
                logger.warning("Could not remove \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
