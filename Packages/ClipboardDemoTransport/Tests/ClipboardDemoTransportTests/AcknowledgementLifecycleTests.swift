#if canImport(Network) && canImport(Security)
import CryptoKit
import Foundation
import Network
import Security
import XCTest
@testable import ClipboardDemoTransport

final class AcknowledgementLifecycleTests: XCTestCase {
    func testDelayedClientReceivesAcceptanceAndRejection() throws {
        for accepted in [true, false] {
            let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            let invitation = DemoInvitation(service: UUID(), key: key,
                                            validUntil: Date().addingTimeInterval(100))
            let receiver = try DemoReceiver(invitation: invitation, loopback: true)
            defer { receiver.stop() }
            let ready = expectation(description: "Receiver ready")
            let staged = expectation(description: "Synthetic payload validated")
            let item = DemoTransfer(kind: .text, bytes: Data("delayed ACK reader fixture".utf8))
            receiver.start(status: { if $0 == CaptureArcText.value("Ready to receive") { ready.fulfill() } }, intake: { received, reply in
                XCTAssertEqual(received.bytes, item.bytes)
                reply(accepted)
                staged.fulfill()
            })
            wait(for: [ready], timeout: 5)
            let tls = NWProtocolTLS.Options()
            let options = tls.securityProtocolOptions
            sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
            sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
            sec_protocol_options_append_tls_ciphersuite(options,
                tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
            let psk = key.withUnsafeBytes { DispatchData(bytes: $0) }
            let identity = Data(invitation.service.uuidString.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
            sec_protocol_options_add_pre_shared_key(options, psk as __DispatchData, identity as __DispatchData)
            let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
            parameters.requiredInterfaceType = .loopback
            let client = NWConnection(host: "127.0.0.1", port: try XCTUnwrap(receiver.boundPort), using: parameters)
            defer { client.cancel() }
            let queue = DispatchQueue(label: "capturearc.tests.delayed-ack")
            let acknowledged = expectation(description: "Delayed client reads ACK")
            let frame = try item.framed()
            client.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    client.stateUpdateHandler = nil
                    client.send(content: frame, completion: .contentProcessed { error in
                        XCTAssertNil(error)
                        queue.asyncAfter(deadline: .now() + 0.3) {
                            client.receive(minimumIncompleteLength: 1, maximumLength: 1) { data, _, _, error in
                                XCTAssertNil(error)
                                XCTAssertEqual(data, Data([accepted ? 1 : 0]))
                                acknowledged.fulfill()
                                // The existing iPhone closes after consuming the one-byte ACK.
                                client.cancel()
                            }
                        }
                    })
                case .failed(let error): XCTFail("Client failed: \(error)")
                default: break
                }
            }
            client.start(queue: queue)
            wait(for: [staged, acknowledged], timeout: 8)
        }
    }
}
#endif
