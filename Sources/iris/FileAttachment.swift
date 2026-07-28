import Foundation

public enum AttachmentCategory: String, Codable, Sendable {
    case image
    case pdf
    case document
    case text
    case unknown
}

public struct FileAttachment: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let filename: String
    public let fileURL: URL
    public let mimeType: String
    public let fileSize: Int64
    public let category: AttachmentCategory

    public init(
        id: UUID = UUID(),
        filename: String,
        fileURL: URL,
        mimeType: String,
        fileSize: Int64,
        category: AttachmentCategory
    ) {
        self.id = id
        self.filename = filename
        self.fileURL = fileURL
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.category = category
    }
}

public struct InlineData: Codable, Equatable, Sendable {
    public let mimeType: String
    public let data: String // Base64 encoded

    public init(mimeType: String, data: String) {
        self.mimeType = mimeType
        self.data = data
    }
}
