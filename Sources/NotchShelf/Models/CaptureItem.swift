import Foundation

public enum CaptureStatus: String, Codable, Sendable {
    case ready
    case missing
}

public struct CaptureDimensions: Hashable, Codable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct CaptureItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let fileResourceIdentifier: Data?
    public let createdAt: Date
    public let modifiedAt: Date
    public let mediaType: CaptureMediaType
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let duration: TimeInterval?
    public let fileSize: Int64
    public let thumbnailCacheKey: String
    public var isPinned: Bool
    public var status: CaptureStatus

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        fileResourceIdentifier: Data? = nil,
        createdAt: Date,
        modifiedAt: Date,
        mediaType: CaptureMediaType,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        duration: TimeInterval? = nil,
        fileSize: Int64,
        thumbnailCacheKey: String,
        isPinned: Bool = false,
        status: CaptureStatus = .ready
    ) {
        self.id = id
        self.fileURL = fileURL
        self.fileResourceIdentifier = fileResourceIdentifier
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.mediaType = mediaType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.fileSize = fileSize
        self.thumbnailCacheKey = thumbnailCacheKey
        self.isPinned = isPinned
        self.status = status
    }

    public var url: URL { fileURL }
    public var displayName: String { fileURL.lastPathComponent }
    public var isVideo: Bool { mediaType == .video }

    public var dimensions: CaptureDimensions? {
        guard let pixelWidth, let pixelHeight else { return nil }
        return CaptureDimensions(width: pixelWidth, height: pixelHeight)
    }
}
