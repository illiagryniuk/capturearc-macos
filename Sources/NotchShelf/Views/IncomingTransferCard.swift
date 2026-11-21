import ClipboardDemoTransport
import AppKit
import SwiftUI

struct IncomingTransferCard: View {
    let item: IncomingTransfer
    let copy: () -> Void
    let remove: () -> Void
    @State private var thumbnail: NSImage?
    @State private var previewFinished = false
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            preview
                .frame(maxWidth: .infinity)
                .frame(height: 108)
                .background(Color.primary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            HStack(spacing: 5) {
                Image(systemName: item.kind.symbol).foregroundStyle(.secondary)
                Text(item.kind == .text ? CaptureArcText.value("Text") : item.title)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 2)
                Image(systemName: "hand.draw").foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium))
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: NotchShelfTheme.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: NotchShelfTheme.cardCornerRadius)
                .stroke(hovered ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.12), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: NotchShelfTheme.cardCornerRadius))
        .onHover { hovered = $0 }
        .onDrag { item.dragProvider() }
        .contextMenu {
            if item.kind == .text || item.kind == .link {
                Button(CaptureArcText.value("Copy"), action: copy)
            }
            if let url = item.url {
                Button(CaptureArcText.value("Open")) { NSWorkspace.shared.open(url) }
                if url.isFileURL {
                    Button(CaptureArcText.value("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
            Divider()
            Button(CaptureArcText.value("Remove"), role: .destructive, action: remove)
        }
        .help(CaptureArcText.value("Drag the card into another app. Right-click for more actions."))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.kind == .text ? "\(item.kind.label): \(item.title)" : "\(item.kind.label): \(item.title)")
        .accessibilityHint(CaptureArcText.value("Drag into another app"))
        .task(id: item.id) {
            guard item.kind == .photo, let url = item.url else { return }
            let image = await Task.detached(priority: .userInitiated) {
                IncomingTransferThumbnail.load(url)
            }.value
            guard !Task.isCancelled else { return }
            thumbnail = image.map { NSImage(cgImage: $0, size: .zero) }
            previewFinished = true
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .photo:
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit()
            } else if previewFinished {
                Label(CaptureArcText.value("Preview unavailable"), systemImage: "photo")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        case .text:
            Text(item.cardText)
                .font(.system(size: 12))
                .lineSpacing(2)
                .lineLimit(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(9)
        case .link:
            VStack(alignment: .leading, spacing: 8) {
                Label(item.url?.host ?? CaptureArcText.value("Link"), systemImage: "link")
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(item.cardText).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(9)
        case .file:
            VStack(spacing: 8) {
                Image(systemName: "doc.fill").font(.system(size: 32)).foregroundStyle(.secondary)
                Text(item.title).font(.caption).lineLimit(2)
            }.padding(9)
        }
    }
}
