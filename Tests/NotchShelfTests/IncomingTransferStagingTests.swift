import Foundation
import XCTest
@testable import NotchShelf

final class IncomingTransferStagingTests: XCTestCase {
    func testStagesTextWebLinkPhotoAndFileWithoutChangingNamesOrBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let staging = IncomingTransferStaging(directory: directory)
        let text = try staging.stage(.text("Тестові дані"))
        XCTAssertEqual(text.kind, .text)
        XCTAssertEqual(text.text, "Тестові дані")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let link = try XCTUnwrap(URL(string: "https://example.com/path"))
        XCTAssertEqual(try staging.stage(.link(link)).url, link)
        let bytes = Data([0, 1, 2, 255])
        let photo = try staging.stage(.photo(name: "приклад.png", data: bytes))
        let file = try staging.stage(.file(name: "приклад.png", data: bytes))
        let photoURL = try XCTUnwrap(photo.url)
        let fileURL = try XCTUnwrap(file.url)
        XCTAssertNotEqual(photoURL, fileURL)
        XCTAssertEqual(photoURL.lastPathComponent, "приклад.png")
        XCTAssertEqual(fileURL.lastPathComponent, "приклад.png")
        XCTAssertEqual(try Data(contentsOf: photoURL), bytes)
        XCTAssertEqual(try Data(contentsOf: fileURL), bytes)
    }

    func testRejectsTraversalAndUnsafeLinks() throws {
        let staging = IncomingTransferStaging(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
        for name in ["../outside", "/outside", "part\\escape", ".hidden", ""] {
            XCTAssertThrowsError(try staging.stage(.file(name: name, data: Data([1])))) {
                XCTAssertEqual($0 as? IncomingTransferError, .invalidName)
            }
        }
        for address in ["file:///tmp/test", "javascript:alert(0)", "https://user:secret@example.com"] {
            let url = try XCTUnwrap(URL(string: address))
            XCTAssertThrowsError(try staging.stage(.link(url))) {
                XCTAssertEqual($0 as? IncomingTransferError, .unsupportedLink)
            }
        }
        XCTAssertThrowsError(try staging.stage(.photo(name: "empty.png", data: Data())))
        XCTAssertThrowsError(try staging.stage(.text(String(repeating: "x", count: IncomingTransferStaging.maximumTextBytes + 1))))
    }
}
