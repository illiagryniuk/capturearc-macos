import AVFoundation
import Network
import ClipboardDemoTransport
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

@main
struct CaptureArcSenderApp: App {
    var body: some Scene { WindowGroup { SenderView() } }
}

private struct SenderView: View {
    @State private var invitation: DemoInvitation?
    @State private var bodyText = ""
    @State private var linkMode = false
    @State private var sending = false
    @State private var scanning = false
    @State private var importing = false
    @State private var showCode = false
    @State private var code = ""
    @State private var status = ""
    @State private var sender = DemoSender()
    @State private var progress: FileTransferProgress?
    @State private var preparation = TransferCancellation()
    @State private var permissionBrowser: NWBrowser?

    var body: some View {
        NavigationStack {
            Form {
                Section(CaptureArcText.value("Pairing")) {
                    Button(CaptureArcText.value("Scan Mac QR Code"), action: scan)
                        .buttonStyle(.borderedProminent)
                    Button(CaptureArcText.value("Enter Code Manually")) { showCode.toggle() }
                    if showCode {
                        TextField(CaptureArcText.value("Pairing code"), text: $code)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(CaptureArcText.value("Use Code")) { pair(code) }
                    }
                    if let invitation {
                        Label("Mac", systemImage: "desktopcomputer")
                        if invitation.isManualSession {
                            Text(CaptureArcText.value("Paired until you stop receiving on your Mac.")).font(.caption)
                        } else { Text(invitation.validUntil, style: .timer) }
                        Text(CaptureArcText.value("Choose text, photos, or a link in another app, then Share → CaptureArc."))
                        Button(CaptureArcText.value("Forget Mac")) { PairingStore.clear(); self.invitation = nil; status = "" }
                    } else {
                        Text(CaptureArcText.value("On your Mac, open From iPhone in CaptureArc, then choose Pair iPhone."))
                    }
                }
                .disabled(sending)
                Section(CaptureArcText.value("Send")) {
                    Toggle(CaptureArcText.value("Send as web link"), isOn: $linkMode)
                    TextField(CaptureArcText.value("Text or HTTPS link"), text: $bodyText, axis: .vertical)
                    Button(CaptureArcText.value("Send to Mac")) {
                        send(.inline(DemoTransfer(kind: linkMode ? .link : .text, bytes: Data(bodyText.utf8))))
                    }.disabled(bodyText.isEmpty || sending)
                    if sending {
                        if let progress { ProgressView(value: progress.fraction); Text(progress.label).font(.caption) }
                        else { ProgressView() }
                        Button(CaptureArcText.value("Cancel")) { preparation.cancel(); sender.cancel() }
                    }
                    Button(CaptureArcText.value("Choose a Photo or File (up to 1 GiB)")) { importing = true }.disabled(sending)
                }
                .disabled(invitation == nil)
                if !status.isEmpty { Section { Text(status).accessibilityAddTraits(.updatesFrequently) } }
                Section(CaptureArcText.value("Selected text")) {
                    Text(CaptureArcText.value("To send part of a note, select the text and use Share in the selection menu. If Share is unavailable, copy the selection and paste it here. The top Share button in Notes sends the whole note."))
                }
                Section {
                    Text(CaptureArcText.value("Requires CaptureArc 1.2 or later on your Mac."))
                    Text(CaptureArcText.value("Both devices must be on the same Wi-Fi network."))
                    Text(CaptureArcText.value("Files and photos: up to 1 GiB with updated apps and pairing. Selected text: up to 1 MiB."))
                    Link(CaptureArcText.value("Help"), destination: URL(string: "https://illiagryniuk.github.io/capturearc-macos/support.html")!)
                    Link(CaptureArcText.value("Privacy Policy"), destination: URL(string: "https://illiagryniuk.github.io/capturearc-macos/privacy.html")!)
                }.font(.footnote)

            }
            .navigationTitle("CaptureArc Sender")
        }
        .task { invitation = PairingStore.load(); if invitation != nil { requestLocalNetworkAccess() } }
        .sheet(isPresented: $scanning) {
            QRScanner { scanned in scanning = false; pair(scanned) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            guard let invitation, !sending else { return }
            do {
                let url = try result.get()
                sending = true; progress = nil
                status = CaptureArcText.value("Preparing transfer…")
                let cancellation = TransferCancellation(); preparation = cancellation
                DispatchQueue.global(qos: .userInitiated).async {
                    let outcome: Result<TransferFile, Error> = Result {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
                        return try TransferFile.prepare(url, kind: type?.conforms(to: .image) == true ? .photo : .file,
                                                        invitation: invitation, cancelled: { cancellation.isCancelled })
                    }
                    DispatchQueue.main.async {
                        sending = false
                        guard !cancellation.isCancelled else { status = DemoWireError.cancelled.localizedDescription; return }
                        switch outcome {
                        case .success(let file): send(.file(file))
                        case .failure(let error): status = error.localizedDescription
                        }
                    }
                }
            } catch { status = error.localizedDescription }
        }
    }

    // Request Local Network access in the containing app, where iOS can show its
    // permission sheet. The Share extension then inherits that permission.
    private func requestLocalNetworkAccess() {
        permissionBrowser?.cancel()
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .wifi
        let browser = NWBrowser(for: .bonjour(type: DemoInvitation.serviceType, domain: nil), using: parameters)
        permissionBrowser = browser
        browser.stateUpdateHandler = { [weak browser] state in
            switch state {
            case .ready, .failed: browser?.cancel()
            case .cancelled: browser?.stateUpdateHandler = nil
            default: break
            }
        }
        browser.start(queue: .main)
    }

    private func scan() {
        guard DataScannerViewController.isSupported else {
            status = CaptureArcText.value("Camera unavailable. Allow camera access in Settings or enter the pairing code manually.")
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { allowed in
            DispatchQueue.main.async {
                if allowed && DataScannerViewController.isAvailable { scanning = true }
                else { status = CaptureArcText.value("Camera unavailable. Allow camera access in Settings or enter the pairing code manually.") }
            }
        }
    }

    private func pair(_ value: String) {
        do {
            let parsed = try DemoInvitation.parse(value)
            try PairingStore.save(parsed)
            invitation = parsed
            requestLocalNetworkAccess()
            status = CaptureArcText.value("Pairing saved. Your Mac will confirm when it receives the first item.")
            code = ""
            showCode = false
        } catch { status = error.localizedDescription }
    }

    private func send(_ item: OutgoingItem) {
        guard let invitation, !sending else { return }
        sending = true
        progress = nil
        status = CaptureArcText.value("Sending…")
        sender.transmit(item, invitation: invitation, progress: { value in
            DispatchQueue.main.async {
                progress = value
                if value.fraction == 1 { status = CaptureArcText.value("Waiting for Mac to save and verify…") }
            }
        }) { result in
            DispatchQueue.main.async {
                sending = false
                switch result {
                case .success: status = CaptureArcText.value("Mac confirmed receipt.")
                case .failure(let error): status = CaptureArcText.value("Not sent. ") + error.localizedDescription
                }
            }
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: false, isGuidanceEnabled: true, isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        context.coordinator.start(controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        var found = false
        init(_ onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func start(_ controller: DataScannerViewController) {
            DispatchQueue.main.async { [weak controller] in
                guard let controller else { return }
                try? controller.startScanning()
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !found else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let code = barcode.payloadStringValue,
                   (code.hasPrefix("capturearc-demo-v1:") || code.hasPrefix("capturearc-demo-v2:")) {
                    found = true
                    dataScanner.stopScanning()
                    onCode(code)
                    return
                }
            }
        }
    }
}
