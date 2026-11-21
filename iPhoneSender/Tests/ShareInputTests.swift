import ClipboardDemoTransport
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import CaptureArcSender

final class ShareInputTests: XCTestCase {
    func testTenPagesOfUnicodeTextPreserveAllBytesAndParagraphs() async throws {
        let text = String(repeating: "Сторінка тесту — café 😀. Text with paragraphs.\n\n", count: 2500)
        let item = try await SharedItemLoader.load(NSItemProvider(object: text as NSString))
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.bytes, Data(text.utf8))
        XCTAssertGreaterThan(item.bytes.count, 64 * 1024)
    }

    func testSelectedTextWithLegacyProviderPreservesUnicodeAndParagraphs() async throws {
        let text = "Вибраний текст із нотатки — café 😀.\n\nДругий абзац."
        let provider = NSItemProvider(item: text as NSString, typeIdentifier: UTType.text.identifier)
        let item = try await SharedItemLoader.load(provider)
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.bytes, Data(text.utf8))
    }

    func testSelectedAttributedTextUsesPlainContents() async throws {
        let text = "Formatted selected text.\n\nSecond paragraph 😀."
        let provider = NSItemProvider()
        provider.registerItem(forTypeIdentifier: UTType.text.identifier) { completion, _, _ in
            completion?(NSAttributedString(string: text), nil)
        }
        let item = try await SharedItemLoader.load(provider)
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.bytes, Data(text.utf8))
    }

    func testUnavailableURLRepresentationFallsBackToSelectedText() async throws {
        let text = "Selected note text, not a web link."
        let provider = NSItemProvider(object: text as NSString)
        provider.registerItem(forTypeIdentifier: UTType.url.identifier) { completion, _, _ in
            completion?(nil, NSError(domain: NSItemProvider.errorDomain, code: -1000))
        }
        let item = try await SharedItemLoader.load(provider)
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.bytes, Data(text.utf8))
    }

    func testUTF8TextDataPreservesContent() async throws {
        let bytes = Data("Selected plain text — 😀\n\nNext paragraph.".utf8)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            completion(bytes, nil); return nil
        }
        let item = try await SharedItemLoader.load(provider)
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.bytes, bytes)
    }

    func testWebLinkPreservesQueryAndFragment() async throws {
        let url = URL(string: "https://example.com/path?q=caf%C3%A9#section")!
        let item = try await SharedItemLoader.load(NSItemProvider(object: url as NSURL))
        XCTAssertEqual(item.kind, .link)
        XCTAssertEqual(item.bytes, Data(url.absoluteString.utf8))
    }

    func testPhotoUsesOriginalFileBytesAndSafeName() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { ctx in
            UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        let bytes = try XCTUnwrap(image.pngData())
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try bytes.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let provider = NSItemProvider()
        provider.suggestedName = "../bad-name"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            completion(file, false, nil); return nil
        }
        let item = try await SharedItemLoader.load(provider)
        XCTAssertEqual(item.kind, .photo)
        XCTAssertEqual(item.bytes, bytes)
        XCTAssertEqual(item.name, "CaptureArc-1.png")
    }

    func testOversizedTextIsRejectedBeforeTransmission() async {
        let provider = NSItemProvider(object: String(repeating: "x", count: DemoTransfer.maximumText + 1) as NSString)
        do { _ = try await SharedItemLoader.load(provider); XCTFail("Oversized text accepted") }
        catch { XCTAssertTrue(error is SharedItemError) }
    }

    func testPairingKeychainRoundTripAndForget() throws {
        defer { PairingStore.clear() }
        let invite = DemoInvitation(service: UUID(), key: Data(repeating: 7, count: 32), untilStopped: true)
        try PairingStore.save(invite)
        XCTAssertEqual(PairingStore.load()?.service, invite.service)
        XCTAssertEqual(PairingStore.load()?.key, invite.key)
        PairingStore.clear()
        XCTAssertNil(PairingStore.load())
    }
}
