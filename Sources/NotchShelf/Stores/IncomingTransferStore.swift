import AppKit
import ClipboardDemoTransport
import Combine
import CryptoKit
import Foundation

@MainActor
final class IncomingTransferStore: ObservableObject {
    @Published private(set) var items: [IncomingTransfer] = []
    @Published var error: String?
    @Published private(set) var invitationCode: String?
    @Published private(set) var pairingStatus = CaptureArcText.value("No iPhone paired")
    @Published private(set) var hasReceived = false
    @Published private(set) var clipboardStatus: String?
    private let pasteboard: NSPasteboard
    private var receiver: DemoReceiver?
    private var generation: UUID?
    private let staging: IncomingTransferStaging
    private let persistence: IncomingTransferPersistence
    private let savedPairing: MacReceiverPairing?
    private var restoreFailed = false

    static func live() -> IncomingTransferStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CaptureArc/IncomingTransfers", isDirectory: true)
        return IncomingTransferStore(directory: directory, savedPairing: MacReceiverPairing())
    }

    init(directory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("CaptureArc-Received-\(UUID().uuidString)", isDirectory: true),
         pasteboard: NSPasteboard = .general, savedPairing: MacReceiverPairing? = nil) {
        self.pasteboard = pasteboard
        staging = IncomingTransferStaging(directory: directory)
        persistence = IncomingTransferPersistence(directory: directory)
        self.savedPairing = savedPairing
        do { items = try persistence.load(); hasReceived = !items.isEmpty }
        catch { restoreFailed = true; self.error = CaptureArcText.value("Could not restore received items. The data remains on disk.") }
        do { if let invitation = try savedPairing?.load() { try startReceiver(invitation) } }
        catch { self.error = error.localizedDescription }
    }

    deinit { receiver?.stop() }

    func receive(_ payload: IncomingTransferPayload) throws {
        guard !restoreFailed, items.count < 20 else { throw IncomingTransferError.full }
        let item = try staging.stage(payload)
        do { try persistence.save([item] + items) }
        catch { try? persistence.removeFile(for: item); throw error }
        items.insert(item, at: 0)
    }

    func receiveFromPhone(_ payload: IncomingTransferPayload) throws {
        // Validate and accept the full item before changing the clipboard.
        try receive(payload)
        hasReceived = true
        clipboardStatus = nil
        error = nil
        guard case .text(let text) = payload else { return }
        pasteboard.clearContents()
        if pasteboard.setString(text, forType: .string) {
            clipboardStatus = CaptureArcText.value("Text copied — paste with ⌘V.")
        } else {
            error = CaptureArcText.value("Text received but not copied. Right-click the card and choose Copy.")
        }
    }

    var canPair: Bool { true }

    func startPairing() {
        stopReceiver()
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let invitation = DemoInvitation(service: UUID(), key: key, untilStopped: true)
        do {
            try savedPairing?.save(invitation)
            try startReceiver(invitation)
        } catch { stopReceiver(); self.error = error.localizedDescription }
    }

    private func startReceiver(_ invitation: DemoInvitation) throws {
        let id = invitation.service
            let receiver = try DemoReceiver(invitation: invitation)
            generation = id
            invitationCode = try invitation.pasteCode()
            pairingStatus = CaptureArcText.value("Starting receiver…")
            self.receiver = receiver
            receiver.start(status: { [weak self] status in
                DispatchQueue.main.async {
                    guard let self, self.generation == id else { return }
                    self.pairingStatus = status
                }
            }, intake: { [weak self] item, reply in
                DispatchQueue.main.async {
                    guard let self, self.generation == id, invitation.isValid() else { reply(false); return }
                    do {
                        try self.receiveFromPhone(self.payload(item))
                        reply(true)
                    } catch {
                        self.error = error.localizedDescription
                        reply(false)
                    }
                }
            })

    }

    func remove(_ item: IncomingTransfer) {
        do {
            let remaining = items.filter { $0.id != item.id }
            try persistence.save(remaining)
            items = remaining
            try persistence.removeFile(for: item)
        } catch { self.error = error.localizedDescription }
    }

    func clearReceivedItems() {
        guard !restoreFailed else { return }
        do {
            try persistence.save([])
            let removed = items
            items = []
            hasReceived = false
            clipboardStatus = nil
            error = nil
            for item in removed { try persistence.removeFile(for: item) }
        } catch { self.error = error.localizedDescription }
    }

    func endPairing() {
        stopReceiver()
        do { try savedPairing?.clear() }
        catch { self.error = error.localizedDescription }
    }

    private func stopReceiver() {
        generation = nil
        receiver?.stop()
        receiver = nil
        invitationCode = nil
        pairingStatus = CaptureArcText.value("No iPhone paired")
    }

    private func payload(_ item: DemoTransfer) throws -> IncomingTransferPayload {
        switch item.kind {
        case .text:
            guard let value = String(data: item.bytes, encoding: .utf8) else { throw DemoWireError.badFrame }
            return .text(value)
        case .link:
            guard let value = String(data: item.bytes, encoding: .utf8),
                  let url = URL(string: value) else { throw DemoWireError.badFrame }
            return .link(url)
        case .photo:
            guard let name = item.name else { throw DemoWireError.badFrame }
            return .photo(name: name, data: item.bytes)
        case .file:
            guard let name = item.name else { throw DemoWireError.badFrame }
            return .file(name: name, data: item.bytes)
        }
    }

}
