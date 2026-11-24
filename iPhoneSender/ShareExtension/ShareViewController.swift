import ClipboardDemoTransport
import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private var transferTask: Task<Void, Never>?
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in self?.finish() })
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        preferredContentSize = CGSize(width: 380, height: 330)
        transferTask = Task { [weak self] in await self?.sendSelection() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        transferTask?.cancel()
        model.cancellation.cancel()
        model.sender.cancel()
    }

    private func sendSelection() async {
        guard let invitation = PairingStore.load() else {
            model.fail(CaptureArcText.value("Pair your Mac first"), detail: CaptureArcText.value("Open CaptureArc Sender and scan the QR code on your Mac. Then share the item with CaptureArc again."))
            return
        }
        let inputs = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        var providers = inputs.flatMap { $0.attachments ?? [] }
        if providers.isEmpty {
            providers = inputs.compactMap { $0.attributedContentText?.string }.filter { !$0.isEmpty }
                .map { NSItemProvider(object: $0 as NSString) }
        }
        guard !providers.isEmpty else { model.fail(CaptureArcText.value("No item selected"), detail: SharedItemError.unsupported.localizedDescription); return }
        guard providers.count <= DemoTransfer.maximumBatchCount else { model.fail(CaptureArcText.value("Too many items"), detail: SharedItemError.tooMany.localizedDescription); return }
        var count = 0
        do {
            for (index, provider) in providers.enumerated() {
                try Task.checkCancellation()
                model.progress = nil
                model.title = CaptureArcText.value("Sending to Mac…")
                model.detail = CaptureArcText.format("Item %d of %d", index + 1, providers.count)
                let item = try await SharedItemLoader.loadOutgoing(provider, index: index + 1, invitation: invitation, cancellation: model.cancellation)
                try Task.checkCancellation()
                try await model.transmit(item, invitation: invitation)
                count += 1
            }
            model.busy = false
            model.succeeded = true
            model.title = CaptureArcText.value("Sent to Mac")
            model.detail = CaptureArcText.format("Mac confirmed receipt of %d item(s).", count)
        } catch is CancellationError {
            return
        } catch {
            model.fail(count == 0 ? CaptureArcText.value("Not sent") : CaptureArcText.format("Sent %d of %d", count, providers.count),
                       detail: error.localizedDescription + (count > 0 ? CaptureArcText.value(" Retry only the items that were not sent.") : ""))
        }
    }

    private func finish() {
        transferTask?.cancel()
        model.cancellation.cancel()
        model.sender.cancel()
        extensionContext?.completeRequest(returningItems: nil)
    }
}

@MainActor
private final class ShareModel: ObservableObject {
    @Published var title = CaptureArcText.value("Preparing transfer…")
    @Published var detail = ""
    @Published var busy = true
    @Published var succeeded = false
    let sender = DemoSender()
    let cancellation = TransferCancellation()
    @Published var progress: FileTransferProgress?

    func fail(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
        busy = false
    }

    func transmit(_ item: OutgoingItem, invitation: DemoInvitation) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sender.transmit(item, invitation: invitation, progress: { [weak self] value in
                Task { @MainActor in self?.progress = value }
            }) { continuation.resume(with: $0) }
        }
    }
}

private struct ShareView: View {
    @ObservedObject var model: ShareModel
    let done: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: model.succeeded ? "checkmark.circle.fill" : "desktopcomputer")
                .font(.system(size: 42)).foregroundStyle(model.succeeded ? .green : .accentColor)
            Text(model.title).font(.title2.bold())
            Text(model.detail).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if model.busy {
                if let progress = model.progress {
                    ProgressView(value: progress.fraction)
                    Text(progress.label).font(.caption)
                    if progress.fraction == 1 { Text(CaptureArcText.value("Waiting for Mac to save and verify…")).font(.caption) }
                } else { ProgressView() }
            }
            Button(model.busy ? CaptureArcText.value("Cancel") : CaptureArcText.value("Done"), action: done)
                .buttonStyle(.borderedProminent)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
