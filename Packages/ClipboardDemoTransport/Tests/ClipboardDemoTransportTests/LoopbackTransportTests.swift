#if canImport(Network) && canImport(Security)
import CryptoKit
import Foundation
import XCTest
@testable import ClipboardDemoTransport

final class LoopbackTransportTests: XCTestCase {
    func testManualSessionTransfersLargePayloadThenStops() throws {
        let invite = DemoInvitation(service: UUID(), key: Data(repeating: 83, count: 32), untilStopped: true)
        let receiver = try DemoReceiver(invitation: invite, loopback: true)
        let sender = DemoSender()
        defer { receiver.stop(); sender.cancel() }
        let ready = expectation(description: "manual listener ready")
        let data = Data(repeating: 117, count: DemoTransfer.maximumPayload)
        let received = expectation(description: "10 MiB file intact")
        receiver.start(status: { if $0 == CaptureArcText.value("Ready to receive") { ready.fulfill() } }, intake: { item, reply in
            XCTAssertEqual(item.bytes, data)
            reply(true)
            received.fulfill()
        })
        wait(for: [ready], timeout: 5)
        let port = try XCTUnwrap(receiver.boundPort)
        let ack = expectation(description: "large payload ACK")
        sender.transmit(DemoTransfer(kind: .file, bytes: data, name: "large-fixture.bin"), invitation: invite, loopbackPort: port) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            ack.fulfill()
        }
        wait(for: [received, ack], timeout: DemoTransfer.connectionTimeout + 3)
        receiver.stop()
        let stopped = expectation(description: "stopped listener rejects saved invitation")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            sender.transmit(DemoTransfer(kind: .text, bytes: Data("stop check".utf8)), invitation: invite, loopbackPort: port) { result in
                if case .success = result { XCTFail("Stopped receiver accepted an item") }
                stopped.fulfill()
            }
        }
        wait(for: [stopped], timeout: DemoTransfer.connectionTimeout + 3)
    }

    func testTLSPSKRejectsWrongKeyThenTransfersSyntheticItems() throws {
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let invite = DemoInvitation(service: UUID(), key: key, validUntil: Date().addingTimeInterval(100))
        let wrong = DemoInvitation(service: invite.service, key: Data(repeating: 0, count: 32), validUntil: invite.validUntil)
        let server = try DemoReceiver(invitation: invite, loopback: true)
        let sender = DemoSender()
        defer { server.stop() }
        let ready = expectation(description: "Loopback listener is ready")
        let items = [
            DemoTransfer(kind: .text, bytes: Data("Привіт".utf8)),
            DemoTransfer(kind: .link, bytes: Data("https://example.com".utf8)),
            DemoTransfer(kind: .photo, bytes: Data([11, 22, 33]), name: "sample.png"),
            DemoTransfer(kind: .file, bytes: Data([0, 255, 42]), name: "sample.bin")
        ]
        let accepted = expectation(description: "Only the four authenticated items arrive")
        accepted.expectedFulfillmentCount = items.count
        var received = [DemoTransfer]()
        server.start(status: { if $0 == CaptureArcText.value("Ready to receive") { ready.fulfill() } }, intake: { item, callback in
            received.append(item)
            callback(true)
            accepted.fulfill()
        })
        wait(for: [ready], timeout: 5)
        let port = try XCTUnwrap(server.boundPort)
        let rejected = expectation(description: "Wrong key fails")
        sender.transmit(items[0], invitation: wrong, loopbackPort: port) { result in
            if case .success = result { XCTFail("Invalid PSK accepted") }
            rejected.fulfill()
        }
        wait(for: [rejected], timeout: DemoTransfer.connectionTimeout + 3)
        for item in items {
            let ack = expectation(description: "Authenticated ACK for " + item.kind.rawValue)
            sender.transmit(item, invitation: invite, loopbackPort: port) { result in
                if case let .failure(error) = result { XCTFail(error.localizedDescription) }
                ack.fulfill()
            }
            wait(for: [ack], timeout: DemoTransfer.connectionTimeout + 3)
        }
        wait(for: [accepted], timeout: 5)
        XCTAssertEqual(received.map(\.kind.rawValue), items.map(\.kind.rawValue))
        XCTAssertEqual(received.map(\.bytes), items.map(\.bytes))
        XCTAssertEqual(received.map(\.name), items.map(\.name))
    }
}
#endif
