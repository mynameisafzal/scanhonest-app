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
        folder: DocumentFolder? = nil
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

@Model
final class DocumentFolder {
    var id: UUID
    var name: String
    var dateCreated: Date
    var colorHex: String
    @Relationship(deleteRule: .nullify, inverse: \ScannedDocument.folder)
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
