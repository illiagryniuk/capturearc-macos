import AppKit
import XCTest
@testable import NotchShelf

final class IncomingTransferClipboardTests: XCTestCase {
    @MainActor
    func testReceivedLongTextIsReadyToPasteWithoutTruncation() async throws {
        let board = NSPasteboard(name: .init("CaptureArc-QA-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = IncomingTransferStore(directory: directory, pasteboard: board)
        let text = String(repeating: "Вибраний текст — café 😀.\n\n", count: 3000)
        try store.receiveFromPhone(.text(text))
        XCTAssertEqual(board.string(forType: .string), text)
        XCTAssertEqual(store.items.first?.text, text)
        XCTAssertTrue(store.hasReceived)
        XCTAssertNotNil(store.clipboardStatus)
    }

    @MainActor
    func testRejectedTextDoesNotReplaceClipboard() async throws {
        let board = NSPasteboard(name: .init("CaptureArc-QA-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        board.setString("Previous synthetic clipboard", forType: .string)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = IncomingTransferStore(directory: directory, pasteboard: board)
        XCTAssertThrowsError(try store.receiveFromPhone(.text(String(repeating: "x", count: IncomingTransferStaging.maximumTextBytes + 1))))
        XCTAssertEqual(board.string(forType: .string), "Previous synthetic clipboard")
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(store.hasReceived)
    }

    @MainActor
    func testSamplesPhotosAndLinksDoNotReplaceClipboard() async throws {
        let board = NSPasteboard(name: .init("CaptureArc-QA-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        board.setString("Previous synthetic clipboard", forType: .string)
        let store = IncomingTransferStore(directory: directory, pasteboard: board)
        try store.receive(.text("Local sample"))
        try store.receiveFromPhone(.photo(name: "synthetic.png", data: Data([1, 2, 3])))
        try store.receiveFromPhone(.link(URL(string: "https://example.com")!))
        XCTAssertEqual(board.string(forType: .string), "Previous synthetic clipboard")
        XCTAssertNil(store.clipboardStatus)
    }
}
