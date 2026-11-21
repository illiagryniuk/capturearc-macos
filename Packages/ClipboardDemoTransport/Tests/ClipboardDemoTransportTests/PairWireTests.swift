import Foundation
import XCTest
@testable import ClipboardDemoTransport

final class PairWireTests: XCTestCase {
    func testInvitationValidation() throws {
        let now = Date()
        let invitation = DemoInvitation(service: UUID(), key: Data(repeating: 42, count: 32),
                                        validUntil: now.addingTimeInterval(120))
        let code = try invitation.pasteCode()
        let decoded = try DemoInvitation.parse(code, now: now)
        XCTAssertEqual(decoded.service, invitation.service)
        XCTAssertEqual(decoded.key, invitation.key)
        XCTAssertThrowsError(try DemoInvitation.parse(code, now: now.addingTimeInterval(121)))
        XCTAssertThrowsError(try DemoInvitation.parse("bad invite", now: now))
    }

    func testManualSessionRemainsValidUntilReceiverStopsAndUsesVersionedCode() throws {
        let invitation = DemoInvitation(service: UUID(), key: Data(repeating: 5, count: 32), untilStopped: true)
        let code = try invitation.pasteCode()
        XCTAssertTrue(code.hasPrefix("capturearc-demo-v2:"))
        XCTAssertTrue(try DemoInvitation.parse(code, now: Date().addingTimeInterval(86400)).isManualSession)
        XCTAssertThrowsError(try DemoInvitation.parse(code.replacingOccurrences(of: "-v2:", with: "-v1:")))
    }

    func testLongUnicodeTextAndTextBoundaryRoundTrip() throws {
        let text = String(repeating: "Long text. Український текст. 😀\n\n", count: 5000)
        let data = Data(text.utf8)
        XCTAssertGreaterThan(data.count, 64 * 1024)
        let frame = try DemoTransfer(kind: .text, bytes: data).framed()
        XCTAssertEqual(try DemoTransfer.parse(Data(frame.dropFirst(4))).bytes, data)
        XCTAssertNoThrow(try DemoTransfer(kind: .text, bytes: Data(repeating: 65, count: DemoTransfer.maximumText)).check())
        XCTAssertThrowsError(try DemoTransfer(kind: .text, bytes: Data(repeating: 65, count: DemoTransfer.maximumText + 1)).check())
    }

    func testFramingAndValidation() throws {
        // A maximum-size base64 frame with repeated slashes also fits the cap.
        let payload = Data(repeating: 255, count: DemoTransfer.maximumPayload)
        let frame = try DemoTransfer(kind: .file, bytes: payload, name: "fixture.bin").framed()
        let size = try DemoTransfer.length(Data(frame.prefix(4)))
        XCTAssertEqual(size, frame.count - 4)
        XCTAssertEqual(try DemoTransfer.parse(Data(frame.dropFirst(4))).bytes, payload)
        XCTAssertThrowsError(try DemoTransfer.length(Data([255, 255, 255, 255])))
        XCTAssertThrowsError(try DemoTransfer(kind: .photo, bytes: Data([1]), name: "../x").framed())
        XCTAssertThrowsError(try DemoTransfer(kind: .link, bytes: Data("file:///tmp/x".utf8)).framed())
    }
}
