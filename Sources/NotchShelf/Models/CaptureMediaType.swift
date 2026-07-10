import Foundation
import UniformTypeIdentifiers

public enum CaptureMediaType: String, Codable, CaseIterable, Sendable {
    case image
    case video

    public static func classify(_ contentType: UTType) -> CaptureMediaType? {
        if contentType.conforms(to: .image) {
            return .image
        }

        if contentType.conforms(to: .movie) {
            return .video
        }

        return nil
    }

    public static func classify(url: URL, contentType: UTType? = nil) -> CaptureMediaType? {
        let resolvedType = contentType ?? UTType(filenameExtension: url.pathExtension)
        return resolvedType.flatMap(classify)
    }
}
