import AppKit
import Foundation
import QuickLookThumbnailing

public enum ThumbnailServiceError: Error {
    case unavailable
}

public actor ThumbnailService {
    public static let shared = ThumbnailService()

    private let generator: QLThumbnailGenerator
    private let cache = NSCache<NSString, NSImage>()

    public init(generator: QLThumbnailGenerator = .shared) {
        self.generator = generator
        cache.countLimit = 250
    }

    public func thumbnail(
        for item: CaptureItem,
        size: CGSize = CGSize(width: 180, height: 120),
        scale: CGFloat = 2
    ) async throws -> NSImage {
        let key = cacheKey(for: item, size: size, scale: scale) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: item.fileURL,
            size: size,
            scale: scale,
            representationTypes: [.thumbnail, .lowQualityThumbnail]
        )
        let representation = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<QLThumbnailRepresentation, Error>) in
                generator.generateBestRepresentation(for: request) { representation, error in
                    if let representation {
                        continuation.resume(returning: representation)
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(throwing: ThumbnailServiceError.unavailable)
                    }
                }
            }
        } onCancel: {
            generator.cancel(request)
        }

        let image = NSImage(cgImage: representation.cgImage, size: size)
        cache.setObject(image, forKey: key)
        return image
    }

    public func removeThumbnail(for item: CaptureItem) {
        // Size-specific entries are bounded by the cache and naturally expire. A file update
        // receives a new key through its modification timestamp.
    }

    public func removeAll() {
        cache.removeAllObjects()
    }

    private func cacheKey(for item: CaptureItem, size: CGSize, scale: CGFloat) -> String {
        [
            item.thumbnailCacheKey,
            String(item.modifiedAt.timeIntervalSinceReferenceDate),
            String(Int(size.width.rounded())),
            String(Int(size.height.rounded())),
            String(format: "%.2f", scale),
        ].joined(separator: "-")
    }
}
