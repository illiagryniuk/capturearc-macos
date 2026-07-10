import CoreServices
import Foundation

public enum CaptureFileFilter: Sendable {
    case supportedMedia
    case macOSScreenCapturesOnly
}

public struct ScreenCaptureMetadata: Equatable, Sendable {
    public let isScreenCapture: Bool
    public let hasScreenCaptureType: Bool

    public init(isScreenCapture: Bool, hasScreenCaptureType: Bool) {
        self.isScreenCapture = isScreenCapture
        self.hasScreenCaptureType = hasScreenCaptureType
    }
}

public enum SystemScreenCaptureClassifier {
    public static func isSystemScreenCapture(_ metadata: ScreenCaptureMetadata) -> Bool {
        metadata.isScreenCapture || metadata.hasScreenCaptureType
    }
}

public protocol ScreenCaptureMetadataProviding: Sendable {
    func metadata(for url: URL) -> ScreenCaptureMetadata
}

public struct SpotlightScreenCaptureMetadataProvider: ScreenCaptureMetadataProviding {
    public init() {}

    public func metadata(for url: URL) -> ScreenCaptureMetadata {
        guard let item = MDItemCreate(
            kCFAllocatorDefault,
            url.standardizedFileURL.path as CFString
        ) else {
            return ScreenCaptureMetadata(
                isScreenCapture: false,
                hasScreenCaptureType: false
            )
        }

        let screenCaptureValue = MDItemCopyAttribute(
            item,
            "kMDItemIsScreenCapture" as CFString
        )
        let screenCaptureNumber = screenCaptureValue as? NSNumber
        let screenCaptureType = MDItemCopyAttribute(
            item,
            "kMDItemScreenCaptureType" as CFString
        )
        let hasScreenCaptureType = screenCaptureType != nil
            && !(screenCaptureType is NSNull)

        return ScreenCaptureMetadata(
            isScreenCapture: screenCaptureNumber?.intValue == 1,
            hasScreenCaptureType: hasScreenCaptureType
        )
    }
}
