import AppKit
import ClipboardDemoTransport
import UniformTypeIdentifiers
import XCTest
@testable import NotchShelf

final class IncomingTransferStreamingTests: XCTestCase {
    @MainActor
    func testLargeTextDocumentIsSavedRestoredAndDraggableWithoutClipboardChange() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CaptureArc-StoreTest-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("transcript.txt")
        FileManager.default.createFile(atPath: source.path, contents: nil)
        let writer = try FileHandle(forWritingTo: source)
        try writer.truncate(atOffset: 11 * 1024 * 1024 + 1); try writer.close()
        let file = try TransferFile.prepare(source)
        let board = NSPasteboard(name: .init("CaptureArc-Stream-QA-\(UUID())"))
        defer { board.releaseGlobally() }
        board.setString("Synthetic existing clipboard", forType: .string)
        let directory = root.appendingPathComponent("shelf")
        let store = IncomingTransferStore(directory: directory, pasteboard: board)
        try store.receiveFromPhone(file)
        let item = try XCTUnwrap(store.items.first)
        XCTAssertEqual(item.kind, .file); XCTAssertNil(item.text)
        XCTAssertEqual(item.title, "transcript.txt")
        XCTAssertEqual(board.string(forType: .string), "Synthetic existing clipboard")
        XCTAssertNil(store.clipboardStatus)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
        let restored = IncomingTransferStore(directory: directory, pasteboard: board)
        XCTAssertEqual(restored.items.first?.url, item.url)
        let provider = item.dragProvider()
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        let offered: URL = try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: NSURL.self) { object, error in
                if let url = object as? URL { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? FileTransferError.storage) }
            }
        }
        XCTAssertEqual(offered, item.url)
        XCTAssertEqual(try offered.resourceValues(forKeys: [.fileSizeKey]).fileSize, 11 * 1024 * 1024 + 1)
    }

    @MainActor
    func testFailedManifestCommitDoesNotAddCardOrLeaveAdoptedFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("export.zip")
        try Data("Synthetic backup bytes".utf8).write(to: source)
        let file = try TransferFile.prepare(source)
        let shelf = root.appendingPathComponent("shelf")
        let board = NSPasteboard(name: .init("CaptureArc-Commit-QA-\(UUID())"))
        defer { board.releaseGlobally() }
        let store = IncomingTransferStore(directory: shelf, pasteboard: board)
        try FileManager.default.createDirectory(at: shelf.appendingPathComponent("items.json"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.receiveFromPhone(file))
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: shelf.path), ["items.json"])
    }
}
