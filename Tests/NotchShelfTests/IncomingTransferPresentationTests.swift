import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import NotchShelf

final class IncomingTransferPresentationTests: XCTestCase {
    func testTextCardDragKeepsFullTextBeyondPreview() async throws {
        let text = String(repeating: "Повний текст 😀 — café.\n\n", count: 2000)
        let item = try IncomingTransferStaging(directory: FileManager.default.temporaryDirectory).stage(.text(text))
        XCTAssertLessThan(item.cardText.count, text.count)
        let provider = item.dragProvider()
        let dropped: String = try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: NSString.self) { value, error in
                if let error { continuation.resume(throwing: error) }
                else if let text = value as? String { continuation.resume(returning: text) }
                else { continuation.resume(throwing: CocoaError(.coderReadCorrupt)) }
            }
        }
        XCTAssertEqual(dropped, text)
    }

    func testPhotoDragOffersOriginalImageBytesAndFileURL() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bytes = try XCTUnwrap(NSBitmapImageRep(cgImage: image()).representation(using: .png, properties: [:]))
        let item = try IncomingTransferStaging(directory: folder).stage(.photo(name: "original.png", data: bytes))
        let provider = item.dragProvider()
        XCTAssertEqual(provider.suggestedName, "original.png")
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.png.identifier))
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        let dropped: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { value, error in
                if let error { continuation.resume(throwing: error) }
                else if let value { continuation.resume(returning: value) }
                else { continuation.resume(throwing: CocoaError(.coderReadCorrupt)) }
            }
        }
        XCTAssertEqual(dropped, bytes)
    }

    func testPhotoThumbnailIsBoundedAndHonorsPortraitOrientation() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: file) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image(), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let thumbnail = try XCTUnwrap(IncomingTransferThumbnail.load(file))
        XCTAssertEqual(thumbnail.height, 480)
        XCTAssertEqual(thumbnail.width, 320)
    }

    private func image() -> CGImage {
        let context = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.55, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        return context.makeImage()!
    }
}
