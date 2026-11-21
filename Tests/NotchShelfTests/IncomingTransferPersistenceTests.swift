import AppKit
import XCTest
@testable import NotchShelf

final class IncomingTransferPersistenceTests: XCTestCase {
    @MainActor
    func testRelaunchRestoresFullTextAndOriginalPhotoWithoutReplacingClipboard() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard(name: .init("CaptureArc-QA-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        let text = String(repeating: "Long selected text — café 😀.\n", count: 3000)
        let bytes = Data([0, 1, 2, 255])
        let original = IncomingTransferStore(directory: directory, pasteboard: board)
        try original.receiveFromPhone(.text(text))
        try original.receiveFromPhone(.photo(name: "photo.png", data: bytes))
        board.setString("New synthetic clipboard", forType: .string)
        let restored = IncomingTransferStore(directory: directory, pasteboard: board)
        XCTAssertEqual(restored.items.count, 2)
        XCTAssertEqual(restored.items.last?.text, text)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(restored.items.first?.url)), bytes)
        XCTAssertEqual(board.string(forType: .string), "New synthetic clipboard")
        XCTAssertNil(restored.error)
        let mode = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("items.json").path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    @MainActor
    func testRemoveAndClearDeleteOnlyAppOwnedCopies() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = IncomingTransferStore(directory: directory)
        try store.receive(.file(name: "test.txt", data: Data("Synthetic".utf8)))
        let first = try XCTUnwrap(store.items.first)
        try store.receive(.text("Keep this one"))
        store.remove(first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(first.url).path))
        XCTAssertEqual(try IncomingTransferPersistence(directory: directory).load().count, 1)
        store.clearReceivedItems()
        XCTAssertTrue(try IncomingTransferPersistence(directory: directory).load().isEmpty)
    }

    @MainActor
    func testUnreadableManifestIsPreservedAndNewIntakeCannotOverwriteIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = directory.appendingPathComponent("items.json")
        let damaged = Data("Synthetic damaged manifest".utf8)
        try damaged.write(to: manifest)
        let store = IncomingTransferStore(directory: directory)
        XCTAssertNotNil(store.error)
        XCTAssertThrowsError(try store.receive(.text("New item")))
        store.clearReceivedItems()
        XCTAssertEqual(try Data(contentsOf: manifest), damaged)
    }

    @MainActor
    func testFullShelfRejectsNewItemWithoutLosingAcceptedItems() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = IncomingTransferStore(directory: directory)
        for index in 0..<20 { try store.receive(.text("Synthetic item \(index)")) }
        XCTAssertThrowsError(try store.receive(.text("Item 21")))
        XCTAssertEqual(try IncomingTransferPersistence(directory: directory).load().count, 20)
    }
}
