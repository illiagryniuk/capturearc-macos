import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct CaptureFileSnapshot: Equatable, Sendable {
    public let fileSize: Int64
    public let modifiedAt: Date

    public init(fileSize: Int64, modifiedAt: Date) {
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
    }
}

public enum CaptureFileStability {
    public static func hasStableTail(
        _ samples: [CaptureFileSnapshot],
        requiredSampleCount: Int = 3
    ) -> Bool {
        guard requiredSampleCount >= 2, samples.count >= requiredSampleCount else {
            return false
        }

        let tail = samples.suffix(requiredSampleCount)
        guard let first = tail.first, first.fileSize > 0 else { return false }
        return tail.dropFirst().allSatisfy { $0 == first }
    }
}

public struct CaptureFileCandidate: Sendable {
    public let url: URL
    public let mediaType: CaptureMediaType
    public let snapshot: CaptureFileSnapshot
    public let fileResourceIdentifier: Data?

    public init(
        url: URL,
        mediaType: CaptureMediaType,
        snapshot: CaptureFileSnapshot,
        fileResourceIdentifier: Data? = nil
    ) {
        self.url = url
        self.mediaType = mediaType
        self.snapshot = snapshot
        self.fileResourceIdentifier = fileResourceIdentifier
    }
}

public enum CaptureMetadataError: Error {
    case unsupportedType
    case notRegularFile
    case unreadableFile
    case missingFileMetadata
    case didNotStabilize
    case invalidImage
    case invalidVideo
}

public actor CaptureMetadataLoader {
    private let fileManager: FileManager
    private let screenCaptureMetadataProvider: any ScreenCaptureMetadataProviding
    private let stabilitySampleCount: Int
    private let stabilityIntervalNanoseconds: UInt64
    private let maximumStabilityAttempts: Int

    public init(
        fileManager: FileManager = .default,
        screenCaptureMetadataProvider: any ScreenCaptureMetadataProviding = SpotlightScreenCaptureMetadataProvider(),
        stabilitySampleCount: Int = 3,
        stabilityInterval: TimeInterval = 0.5,
        maximumStabilityAttempts: Int = 120
    ) {
        self.fileManager = fileManager
        self.screenCaptureMetadataProvider = screenCaptureMetadataProvider
        self.stabilitySampleCount = max(2, stabilitySampleCount)
        self.stabilityIntervalNanoseconds = UInt64(max(0.01, stabilityInterval) * 1_000_000_000)
        self.maximumStabilityAttempts = max(stabilitySampleCount, maximumStabilityAttempts)
    }

    public func supportedFiles(
        in folderURL: URL,
        filter: CaptureFileFilter = .supportedMedia
    ) throws -> [CaptureFileCandidate] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isReadableKey,
            .isHiddenKey,
            .contentTypeKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        return urls.compactMap { rawURL in
            let url = rawURL.standardizedFileURL
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isReadable != false,
                  values.isHidden != true,
                  let mediaType = CaptureMediaType.classify(
                      url: url,
                      contentType: values.contentType
                  ),
                  let fileSize = values.fileSize,
                  let modifiedAt = values.contentModificationDate
            else {
                return nil
            }

            if case .macOSScreenCapturesOnly = filter {
                let metadata = screenCaptureMetadataProvider.metadata(for: url)
                guard SystemScreenCaptureClassifier.isSystemScreenCapture(metadata) else {
                    return nil
                }
            }

            return CaptureFileCandidate(
                url: url,
                mediaType: mediaType,
                snapshot: CaptureFileSnapshot(
                    fileSize: Int64(fileSize),
                    modifiedAt: modifiedAt
                ),
                fileResourceIdentifier: archiveResourceIdentifier(
                    values.fileResourceIdentifier
                )
            )
        }
    }

    public func waitUntilStable(at url: URL) async throws -> CaptureFileSnapshot {
        var samples: [CaptureFileSnapshot] = []
        samples.reserveCapacity(stabilitySampleCount)

        for attempt in 0..<maximumStabilityAttempts {
            try Task.checkCancellation()
            let sample = try snapshot(at: url)
            samples.append(sample)
            if samples.count > stabilitySampleCount {
                samples.removeFirst(samples.count - stabilitySampleCount)
            }

            if CaptureFileStability.hasStableTail(
                samples,
                requiredSampleCount: stabilitySampleCount
            ) {
                return sample
            }

            if attempt + 1 < maximumStabilityAttempts {
                try await Task.sleep(nanoseconds: stabilityIntervalNanoseconds)
            }
        }

        throw CaptureMetadataError.didNotStabilize
    }

    public func loadMetadata(
        for candidate: CaptureFileCandidate,
        preservingID id: UUID? = nil,
        isPinned: Bool = false
    ) async throws -> CaptureItem {
        _ = try await waitUntilStable(at: candidate.url)

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isReadableKey,
            .contentTypeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .fileResourceIdentifierKey,
        ]
        let values = try candidate.url.resourceValues(forKeys: keys)
        guard values.isRegularFile == true else {
            throw CaptureMetadataError.notRegularFile
        }
        guard values.isReadable != false else {
            throw CaptureMetadataError.unreadableFile
        }
        guard let mediaType = CaptureMediaType.classify(
            url: candidate.url,
            contentType: values.contentType
        ) else {
            throw CaptureMetadataError.unsupportedType
        }
        guard let modifiedAt = values.contentModificationDate,
              let fileSize = values.fileSize
        else {
            throw CaptureMetadataError.missingFileMetadata
        }

        try verifyReadable(candidate.url)

        let dimensions: CaptureDimensions?
        let duration: TimeInterval?
        switch mediaType {
        case .image:
            dimensions = try imageDimensions(at: candidate.url)
            duration = nil
        case .video:
            let videoMetadata = try await videoMetadata(at: candidate.url)
            dimensions = videoMetadata.dimensions
            duration = videoMetadata.duration
        }

        let resourceIdentifier = archiveResourceIdentifier(values.fileResourceIdentifier)
        return CaptureItem(
            id: id ?? UUID(),
            fileURL: candidate.url,
            fileResourceIdentifier: resourceIdentifier,
            createdAt: values.creationDate ?? modifiedAt,
            modifiedAt: modifiedAt,
            mediaType: mediaType,
            pixelWidth: dimensions?.width,
            pixelHeight: dimensions?.height,
            duration: duration,
            fileSize: Int64(fileSize),
            thumbnailCacheKey: cacheKey(
                resourceIdentifier: resourceIdentifier,
                url: candidate.url
            ),
            isPinned: isPinned,
            status: .ready
        )
    }

    private func snapshot(at url: URL) throws -> CaptureFileSnapshot {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isReadableKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ])
        guard values.isRegularFile == true else {
            throw CaptureMetadataError.notRegularFile
        }
        guard values.isReadable != false else {
            throw CaptureMetadataError.unreadableFile
        }
        guard let fileSize = values.fileSize,
              let modifiedAt = values.contentModificationDate
        else {
            throw CaptureMetadataError.missingFileMetadata
        }

        return CaptureFileSnapshot(fileSize: Int64(fileSize), modifiedAt: modifiedAt)
    }

    private func verifyReadable(_ url: URL) throws {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            try handle.close()
        } catch {
            throw CaptureMetadataError.unreadableFile
        }
    }

    private func imageDimensions(at url: URL) throws -> CaptureDimensions {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0
        else {
            throw CaptureMetadataError.invalidImage
        }

        return CaptureDimensions(width: width, height: height)
    }

    private func videoMetadata(
        at url: URL
    ) async throws -> (dimensions: CaptureDimensions?, duration: TimeInterval) {
        let asset = AVURLAsset(url: url)
        let loadedDuration = try await asset.load(.duration)
        let seconds = loadedDuration.seconds
        guard seconds.isFinite, seconds >= 0 else {
            throw CaptureMetadataError.invalidVideo
        }

        let tracks = try await asset.loadTracks(withMediaType: .video)
        let dimensions: CaptureDimensions?
        if let track = tracks.first {
            async let naturalSize = track.load(.naturalSize)
            async let preferredTransform = track.load(.preferredTransform)
            let transformedSize = try await naturalSize.applying(preferredTransform)
            let width = Int(abs(transformedSize.width).rounded())
            let height = Int(abs(transformedSize.height).rounded())
            dimensions = width > 0 && height > 0
                ? CaptureDimensions(width: width, height: height)
                : nil
        } else {
            dimensions = nil
        }

        return (dimensions, seconds)
    }

    private func archiveResourceIdentifier(_ identifier: Any?) -> Data? {
        guard let identifier else { return nil }
        if let data = identifier as? Data {
            return data
        }
        return try? NSKeyedArchiver.archivedData(
            withRootObject: identifier,
            requiringSecureCoding: false
        )
    }

    private func cacheKey(resourceIdentifier: Data?, url: URL) -> String {
        let sourceData = resourceIdentifier ?? Data(url.standardizedFileURL.path.utf8)
        return SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()
    }
}
