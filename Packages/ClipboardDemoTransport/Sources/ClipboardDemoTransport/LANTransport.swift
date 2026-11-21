#if canImport(Network) && canImport(Security)
import Foundation
import Network
import Security
import os

private let transportLog = Logger(subsystem: "com.illiagryniuk.capturearc.clipboarddemo.transport", category: "receiver")

private let demoCipher = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!

private func demoParameters(_ invitation: DemoInvitation, loopback: Bool = false) -> NWParameters {
    let tls = NWProtocolTLS.Options()
    let options = tls.securityProtocolOptions
    sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
    sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
    sec_protocol_options_append_tls_ciphersuite(options, demoCipher)
    let psk = invitation.key.withUnsafeBytes { DispatchData(bytes: $0) }
    let identity = Data(invitation.service.uuidString.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
    sec_protocol_options_add_pre_shared_key(options, psk as __DispatchData, identity as __DispatchData)
    let params = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    params.requiredInterfaceType = loopback ? .loopback : .wifi
    return params
}

private func negotiatedDemoTLS(_ connection: NWConnection) -> Bool {
    guard let metadata = connection.metadata(definition: NWProtocolTLS.definition)
        as? NWProtocolTLS.Metadata else { return false }
    return sec_protocol_metadata_get_negotiated_tls_ciphersuite(metadata.securityProtocolMetadata) == demoCipher
}

private func sendFinished(_ bytes: Data, over connection: NWConnection, done: @escaping (NWError?) -> Void) {
    connection.send(content: bytes, completion: .contentProcessed(done))
}

private func receiveExactly(_ count: Int, over connection: NWConnection, done: @escaping (Result<Data, Error>) -> Void) {
    connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
        if let error { done(.failure(error)); return }
        guard let data, data.count == count else { done(.failure(DemoWireError.badFrame)); return }
        done(.success(data))
    }
}

public final class DemoReceiver {
    private let queue = DispatchQueue(label: "capturearc.demo.receiver")
    private let listener: NWListener
    private let invitation: DemoInvitation
    private var running = false
    private var active: [UUID: NWConnection] = [:]
    public typealias Intake = (DemoTransfer, @escaping (Bool) -> Void) -> Void

    public convenience init(invitation: DemoInvitation) throws {
        try self.init(invitation: invitation, loopback: false)
    }

    var boundPort: NWEndpoint.Port? { listener.port }

    init(invitation: DemoInvitation, loopback: Bool) throws {
        guard invitation.key.count == 32, invitation.isValid(),
              (invitation.isManualSession || invitation.validUntil.timeIntervalSinceNow <= DemoInvitation.lifetime) else {
            throw DemoWireError.badInvite
        }
        self.invitation = invitation
        let params = demoParameters(invitation, loopback: loopback)
        if loopback { params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any) }
        listener = try NWListener(using: params)
        if !loopback {
            listener.service = .init(name: invitation.service.uuidString, type: DemoInvitation.serviceType)
        }
    }

    public func start(status: @escaping (String) -> Void, intake: @escaping Intake) {
        queue.async { [self] in
            guard !running else { return }
            running = true
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    transportLog.notice("listener_ready")
                    status(CaptureArcText.value("Ready to receive"))
                case .failed(let error): status(error.localizedDescription)
                case .waiting(let error): status(error.localizedDescription)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] link in
                self?.accept(link, intake: intake)
            }
            listener.start(queue: queue)
            if !invitation.isManualSession {
                queue.asyncAfter(deadline: .now() + max(0, invitation.validUntil.timeIntervalSinceNow)) { [weak self] in
                    guard let self, self.running else { return }
                    self.end()
                    status(CaptureArcText.value("Pairing code expired"))
                }
            }
        }
    }

    public func stop() { queue.async { [self] in end() } }

    private func end() {
        running = false
        listener.cancel()
        active.values.forEach { $0.cancel() }
        active.removeAll()
    }

    private func accept(_ link: NWConnection, intake: @escaping Intake) {
        guard running, active.count < 2, invitation.isValid() else {
            link.cancel()
            return
        }
        transportLog.notice("peer_accepted")
        let id = UUID()
        active[id] = link
        link.stateUpdateHandler = { [weak self, weak link] state in
            guard let self, let link else { return }
            switch state {
            case .ready:
                guard self.running, self.active[id] != nil, negotiatedDemoTLS(link),
                      self.invitation.isValid() else {
                    self.disconnect(id); return
                }
                transportLog.notice("peer_tls_authenticated")
                link.stateUpdateHandler = nil
                receiveExactly(4, over: link) { [weak self, weak link] result in
                    guard let self, let link, let header = try? result.get(),
                          let count = try? DemoTransfer.length(header) else {
                        transportLog.error("frame_header_rejected")
                        self?.disconnect(id); return
                    }
                    transportLog.notice("frame_header_received")
                    receiveExactly(count, over: link) { [weak self, weak link] result in
                        guard let self, let link else { return }
                        guard self.running, self.active[id] != nil,
                              self.invitation.isValid(), let data = try? result.get(),
                              let item = try? DemoTransfer.parse(data) else {
                            transportLog.error("frame_body_rejected")
                            self.disconnect(id); return
                        }
                        transportLog.notice("frame_validated")
                        intake(item) { [weak self, weak link] accepted in
                            self?.queue.async { [weak self, weak link] in
                                guard let self, let link, self.active[id] != nil else { return }
                                transportLog.notice("intake_accepted=\(accepted, privacy: .public)")
                                // The ACK is the final server message. Keep the connection alive
                                // until the peer closes, rather than canceling as soon as the
                                // local send is processed. The existing deadline bounds cleanup.
                                link.send(content: Data([accepted ? 1 : 0]), contentContext: .finalMessage,
                                          isComplete: true, completion: .contentProcessed { [weak self, weak link] error in
                                    guard let self, let link, self.active[id] != nil else { return }
                                    guard error == nil else {
                                        transportLog.error("ack_send_failed")
                                        self.disconnect(id); return
                                    }
                                    transportLog.notice("ack_send_processed_waiting_for_peer_close")
                                    link.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, _, _ in
                                        transportLog.notice("peer_closed_after_ack")
                                        self?.disconnect(id)
                                    }
                                })
                            }
                        }
                    }
                }
            case .failed, .cancelled: self.disconnect(id)
            default: break
            }
        }
        queue.asyncAfter(deadline: .now() + DemoTransfer.connectionTimeout) { [weak self] in
            guard let self, self.active[id] != nil else { return }
            transportLog.notice("peer_deadline_cleanup")
            self.disconnect(id)
        }
        link.start(queue: queue)
    }

    private func disconnect(_ id: UUID) {
        if let link = active.removeValue(forKey: id) {
            link.stateUpdateHandler = nil
            link.cancel()
        }
    }
}

public final class DemoSender {
    private let queue = DispatchQueue(label: "capturearc.demo.sender")
    private var active: NWConnection?
    private var cancelActive: (() -> Void)?

    public init() {}

    public func cancel() { queue.async { [weak self] in self?.cancelActive?() } }

    public func transmit(_ item: DemoTransfer, invitation: DemoInvitation,
                         completion: @escaping (Result<Void, Error>) -> Void) {
        transmit(item, invitation: invitation, loopbackPort: nil, completion: completion)
    }

    func transmit(_ item: DemoTransfer, invitation: DemoInvitation, loopbackPort: NWEndpoint.Port?,
                  completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            guard active == nil else { completion(.failure(DemoWireError.busy)); return }
            guard invitation.key.count == 32, invitation.isValid() else {
                completion(.failure(DemoWireError.badInvite)); return
            }
            let frame: Data
            do { frame = try item.framed() } catch { completion(.failure(error)); return }
            let endpoint: NWEndpoint
            if let loopbackPort {
                endpoint = .hostPort(host: "127.0.0.1", port: loopbackPort)
            } else {
                endpoint = .service(name: invitation.service.uuidString, type: DemoInvitation.serviceType,
                                    domain: "local.", interface: nil)
            }
            let link = NWConnection(to: endpoint, using: demoParameters(invitation, loopback: loopbackPort != nil))
            active = link
            let finish: (Result<Void, Error>) -> Void = { [weak self, weak link] result in
                guard let self, let link, self.active === link else { return }
                self.active = nil
                self.cancelActive = nil
                link.stateUpdateHandler = nil
                link.cancel()
                completion(result)
            }
            cancelActive = { finish(.failure(DemoWireError.cancelled)) }
            link.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard negotiatedDemoTLS(link), invitation.isValid() else {
                        finish(.failure(DemoWireError.rejected)); return
                    }
                    link.stateUpdateHandler = nil
                    sendFinished(frame, over: link) { error in
                        if let error { finish(.failure(error)); return }
                        receiveExactly(1, over: link) { result in
                            do {
                                guard try result.get() == Data([1]) else { throw DemoWireError.rejected }
                                finish(.success(()))
                            } catch { finish(.failure(error)) }
                        }
                    }
                case .failed(let error): finish(.failure(error))
                case .cancelled: finish(.failure(DemoWireError.deadline))
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + DemoTransfer.connectionTimeout) { finish(.failure(DemoWireError.deadline)) }
            link.start(queue: queue)
        }
    }
}
#endif
