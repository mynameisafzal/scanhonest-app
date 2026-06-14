import SwiftData
import Foundation

@Model
final class ScannedDocument {
    var id: UUID
    var name: String
    var dateCreated: Date
    var dateModified: Date
    var pageCount: Int
    var fileSizeBytes: Int64
    var fileURL: URL?
    var thumbnailData: Data?
    var ocrText: String?
    var isPasswordProtected: Bool
    var folder: DocumentFolder?
    // Feature: Smart Expiry Detection
    var detectedExpiryDate: Date?   // populated by ExpiryDetector after OCR
    // Feature: Duplicate Detection  
    var thumbnailHash: String?       // MD5 of thumbnail for dedup

    init(
        id: UUID = UUID(),
        name: String,
        dateCreated: Date = Date(),
        dateModified: Date = Date(),
        pageCount: Int = 1,
        fileSizeBytes: Int64 = 0,
        fileURL: URL? = nil,
        thumbnailData: Data? = nil,
        ocrText: String? = nil,
        isPasswordProtected: Bool = false,
        folder: DocumentFolder? = nil,
        detectedExpiryDate: Date? = nil,
        thumbnailHash: String? = nil
    ) {
        self.id = id
        self.name = name
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.pageCount = pageCount
        self.fileSizeBytes = fileSizeBytes
        self.fileURL = fileURL
        self.thumbnailData = thumbnailData
        self.ocrText = ocrText
        self.isPasswordProtected = isPasswordProtected
        self.folder = folder
        self.detectedExpiryDate = detectedExpiryDate
        self.thumbnailHash = thumbnailHash
    }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSizeBytes)
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: dateCreated, relativeTo: Date())
    }
}

// MARK: - ScanTemplate (Feature: Document Templates)
@Model
final class ScanTemplate {
    var id: UUID
    var name: String          // e.g. "Receipt", "Physics Notes"
    var icon: String          // SF Symbol name
    var colorHex: String      // folder color to auto-assign
    var defaultFolderName: String  // auto-move to this folder on save
    var autoOCR: Bool         // run OCR on save
    var dateCreated: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "doc.text",
        colorHex: String = "1B4332",
        defaultFolderName: String = "",
        autoOCR: Bool = false,
        dateCreated: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.defaultFolderName = defaultFolderName
        self.autoOCR = autoOCR
        self.dateCreated = dateCreated
    }
}

// MARK: - AuditEvent (Feature: Audit Log)
@Model
final class AuditEvent {
    var id: UUID
    var documentID: UUID?       // nil for app-level events
    var documentName: String
    var action: String           // "Scanned", "Shared", "OCR", "Deleted", "Renamed", "Exported"
    var detail: String           // e.g. format, destination
    var date: Date

    init(
        id: UUID = UUID(),
        documentID: UUID? = nil,
        documentName: String,
        action: String,
        detail: String = "",
        date: Date = Date()
    ) {
        self.id = id
        self.documentID = documentID
        self.documentName = documentName
        self.action = action
        self.detail = detail
        self.date = date
    }
}

// MARK: - DocumentFolder
@Model
final class DocumentFolder {
    var id: UUID
    var name: String
    var dateCreated: Date
    var colorHex: String
    // .cascade: deleting a folder removes all its ScannedDocument records from
    // SwiftData. FolderHierarchyService.deleteFolder() removes the PDF files from
    // disk BEFORE calling context.delete(folder) so no orphaned files are left.
    @Relationship(deleteRule: .cascade, inverse: \ScannedDocument.folder)
    var documents: [ScannedDocument]

    init(
        id: UUID = UUID(),
        name: String,
        dateCreated: Date = Date(),
        colorHex: String = "1B4332"
    ) {
        self.id = id
        self.name = name
        self.dateCreated = dateCreated
        self.colorHex = colorHex
        self.documents = []
    }
}
