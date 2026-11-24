import ClipboardDemoTransport
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct IncomingTransferView: View {
    @ObservedObject var store: IncomingTransferStore
    @State private var showPairingCode = true
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 10) {
            if store.canPair {
                pairingControls
            }
            if let progress = store.transferProgress {
                HStack {
                    ProgressView(value: progress.fraction)
                    Text(progress.label).font(.caption)
                    Button(CaptureArcText.value("Cancel"), action: store.cancelTransfer)
                }.padding(.horizontal, 16)
            }
            if store.items.isEmpty && store.invitationCode == nil {
                Spacer()
                Image(systemName: "iphone")
                    .font(.system(size: 30, weight: .light))
                Text(CaptureArcText.value("No iPhone paired")).font(.headline)
                Text(CaptureArcText.value("Pair your iPhone to send text, photos, and links here."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(CaptureArcText.value("Both devices must be on the same Wi-Fi network."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            if !store.items.isEmpty {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 12)], spacing: 12) {
                        ForEach(store.items) { item in
                            IncomingTransferCard(item: item, copy: { copy(item) }, remove: { store.remove(item) })
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                HStack {
                    Label(CaptureArcText.value("Drag a card into another app"), systemImage: "hand.draw")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(CaptureArcText.value("Clear")) { confirmingClear = true }.buttonStyle(.borderless)
                }.padding(.horizontal, 16)
            }
            if let error = store.error {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 10)
        .confirmationDialog(CaptureArcText.value("Remove all received items?"), isPresented: $confirmingClear) {
            Button(CaptureArcText.value("Clear"), role: .destructive, action: store.clearReceivedItems)
            Button(CaptureArcText.value("Cancel"), role: .cancel) {}
        } message: {
            Text(CaptureArcText.value("This deletes local copies in CaptureArc. Originals on your iPhone stay unchanged."))
        }
        .onAppear { if store.hasReceived { showPairingCode = false } }
        .onChange(of: store.hasReceived) { received in
            if received { showPairingCode = false }
        }
    }

    @ViewBuilder
    private var pairingControls: some View {
        if let code = store.invitationCode {
            VStack(spacing: 8) {
                if showPairingCode {
                    if let image = qr(code) {
                        Image(nsImage: image).interpolation(.none).resizable()
                            .scaledToFit().frame(width: 135, height: 135)
                            .accessibilityLabel(CaptureArcText.value("Pairing QR code"))
                    }
                    Text(CaptureArcText.value("Scan once in CaptureArc Sender."))
                        .font(.caption)
                    DisclosureGroup(CaptureArcText.value("Manual code (keep private)")) {
                        Text(code).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).lineLimit(2)
                    }.frame(maxWidth: 300)
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(CaptureArcText.value("Receiving until you stop it."), systemImage: "wifi")
                        Text(store.clipboardStatus ?? CaptureArcText.value("Received text is automatically copied on your Mac."))
                            .foregroundStyle(.secondary)
                    }.font(.caption)
                    Spacer(minLength: 8)
                    Button(showPairingCode ? CaptureArcText.value("Hide QR") : CaptureArcText.value("Show QR")) { showPairingCode.toggle() }
                        .buttonStyle(.borderless)
                    Button(CaptureArcText.value("Stop Receiving"), action: store.endPairing).buttonStyle(.bordered)
                }.padding(.horizontal, 16)
                if store.pairingStatus != CaptureArcText.value("Ready to receive") {
                    Text(store.pairingStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            Button(CaptureArcText.value("Pair iPhone")) { showPairingCode = true; store.startPairing() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func qr(_ code: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(code.utf8)
        guard let output = filter.outputImage else { return nil }
        let quiet = output.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: quiet)
        let scaled = output.composited(over: white).transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        guard let bitmap = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: bitmap, size: NSSize(width: CGFloat(bitmap.width), height: CGFloat(bitmap.height)))
    }

    private func copy(_ item: IncomingTransfer) {
        guard let value = item.text ?? item.url?.absoluteString else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.setString(value, forType: .string) {
            store.error = CaptureArcText.value("Could not copy the item.")
        }
    }
}
