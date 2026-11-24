import AppKit
import ImageIO
import UniformTypeIdentifiers

extension IncomingTransfer {
    /// A bounded preview; drag and copy always use the complete original text.
    var cardText: String { String((text ?? url?.absoluteString ?? title).prefix(700)) }

    func dragProvider() -> NSItemProvider {
        if let text { return NSItemProvider(object: text as NSString) }
        guard let url else { return NSItemProvider() }
        if url.isFileURL {
            // Offer original file bytes to image/document apps and the file URL to Finder.
            let provider = NSItemProvider()
            let type = UTType(filenameExtension: url.pathExtension) ?? .data
            provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
                completion(url, false, nil)
                return nil
            }
            provider.registerObject(url as NSURL, visibility: .all)
            provider.suggestedName = title
            return provider
        }
        return NSItemProvider(object: url as NSURL)
    }
}

enum IncomingTransferThumbnail {
    static func load(_ url: URL, maximumPixels: Int = 480) -> CGImage? {
        guard url.isFileURL,
              let source = CGImageSourceCreateWithURL(url as CFURL,
                  [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}
