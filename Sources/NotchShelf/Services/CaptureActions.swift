import AppKit
import Foundation
import OSLog
@preconcurrency import Quartz

/// Native desktop actions shared by the SwiftUI toolbar and the AppKit
/// collection view. File URLs are kept intact at the boundary so drag, copy,
/// sharing, Finder, and sandbox-aware destination apps receive real URLs.
@MainActor
final class CaptureActions: NSObject, ObservableObject {
    @Published private(set) var isWorking = false
    @Published var presentedError: String?
    var onTransientUIVisibilityChanged: ((Bool) -> Void)?

    private enum TransientSurface: Hashable {
        case quickLook
        case sharingPicker
    }

    private unowned let library: CaptureLibrary
    private var previewItems: [URL] = []
    private var sharingPicker: NSSharingServicePicker?
    private weak var sharingAnchorView: NSView?
    private var visibleTransientSurfaces: Set<TransientSurface> = []
    private var quickLookObservationTokens: [NSObjectProtocol] = []
    private var quickLookVisibilityTask: Task<Void, Never>?

    var hasVisibleTransientUI: Bool {
        if sharingPicker != nil {
            return true
        }
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared() else {
            return false
        }
        return panel.isVisible && panel.dataSource as AnyObject? === self
    }

    init(library: CaptureLibrary) {
        self.library = library
        super.init()
    }

    func setSharingAnchorView(_ view: NSView?) {
        sharingAnchorView = view
    }

    func tearDown() {
        sharingPicker?.delegate = nil
        sharingPicker?.close()
        stopObservingQuickLook()
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(),
           panel.dataSource as AnyObject? === self {
            panel.dataSource = nil
            panel.delegate = nil
            panel.orderOut(nil)
        }
        previewItems.removeAll()
        sharingPicker = nil
        sharingAnchorView = nil
        visibleTransientSurfaces.removeAll()
        onTransientUIVisibilityChanged?(false)
    }

    func open(_ items: [CaptureItem]) {
        let urls = readyURLs(from: items)
        guard !urls.isEmpty else { return }

        for url in urls {
            NSWorkspace.shared.open(url)
        }
        actionLogger.info("Opened \(urls.count, privacy: .public) capture(s)")
    }

    func quickLook(_ items: [CaptureItem]) {
        let urls = readyURLs(from: items)
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }

        if panel.isVisible, previewItems == urls {
            panel.orderOut(nil)
            setTransientSurface(.quickLook, visible: false)
            return
        }

        previewItems = urls
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = 0
        panel.reloadData()
        // Quick Look needs to become key so its own Escape/arrow handling wins
        // over the shelf responder. The controller restores the previously
        // frontmost app when the shelf later collapses.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        observeQuickLook(panel)
        setTransientSurface(.quickLook, visible: true)
        actionLogger.info("Quick Look opened for \(urls.count, privacy: .public) capture(s)")
    }

    func share(_ items: [CaptureItem], from sourceView: NSView? = nil) {
        let urls = readyURLs(from: items)
        guard !urls.isEmpty else { return }

        guard let anchor = sourceView
            ?? sharingAnchorView
            ?? NSApp.keyWindow?.contentView
            ?? NSApp.windows.first(where: { $0.isVisible })?.contentView else {
            presentedError = "The Share menu could not find a window to anchor to."
            return
        }

        sharingPicker?.delegate = nil
        sharingPicker?.close()
        setTransientSurface(.sharingPicker, visible: false)

        let picker = NSSharingServicePicker(items: urls)
        picker.delegate = self
        sharingPicker = picker
        let anchorRect = NSRect(
            x: anchor.bounds.midX,
            y: anchor.bounds.maxY - 1,
            width: 1,
            height: 1
        )
        setTransientSurface(.sharingPicker, visible: true)
        picker.show(relativeTo: anchorRect, of: anchor, preferredEdge: .minY)
        actionLogger.info("Presented native sharing services for \(urls.count, privacy: .public) capture(s)")
    }

    func copy(_ items: [CaptureItem]) {
        let readyItems = items.filter { $0.status == .ready && $0.fileURL.isFileURL }
        guard !readyItems.isEmpty else { return }

        let pasteboardItems: [NSPasteboardItem] = readyItems.map { item in
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(item.fileURL.absoluteString, forType: .fileURL)

            // Supplying image data as an additional representation makes a
            // single screenshot paste naturally into image-aware editors while
            // retaining its file URL for Finder and upload destinations.
            if readyItems.count == 1,
               item.mediaType == .image,
               let image = NSImage(contentsOf: item.fileURL),
               let tiff = image.tiffRepresentation {
                pasteboardItem.setData(tiff, forType: .tiff)
            }
            return pasteboardItem
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.writeObjects(pasteboardItems) {
            presentedError = "The selected captures could not be copied."
            actionLogger.error("Writing capture URLs to the pasteboard failed")
        } else {
            actionLogger.info("Copied \(readyItems.count, privacy: .public) capture(s)")
        }
    }

    func reveal(_ items: [CaptureItem]) {
        let urls = readyURLs(from: items)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        actionLogger.info("Revealed \(urls.count, privacy: .public) capture(s) in Finder")
    }

    func moveToTrash(_ items: [CaptureItem]) {
        let urls = readyURLs(from: items)
        guard !urls.isEmpty, !isWorking else { return }

        isWorking = true
        actionLogger.info("Moving \(urls.count, privacy: .public) capture(s) to Trash")

        Task { [weak self] in
            let failures = await Task.detached(priority: .userInitiated) {
                var failures: [String] = []
                for url in urls {
                    do {
                        var resultingURL: NSURL?
                        try FileManager.default.trashItem(
                            at: url,
                            resultingItemURL: &resultingURL
                        )
                    } catch {
                        failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                return failures
            }.value

            guard let self else { return }
            self.isWorking = false
            self.library.clearSelection()
            self.library.rescan()

            if failures.isEmpty {
                actionLogger.info("Move to Trash completed")
            } else {
                self.presentedError = failures.joined(separator: "\n")
                actionLogger.error(
                    "Move to Trash finished with \(failures.count, privacy: .public) failure(s)"
                )
            }
        }
    }

    private func readyURLs(from items: [CaptureItem]) -> [URL] {
        items.compactMap { item in
            guard item.status == .ready, item.fileURL.isFileURL else { return nil }
            return item.fileURL
        }
    }

    private func setTransientSurface(_ surface: TransientSurface, visible: Bool) {
        if visible {
            visibleTransientSurfaces.insert(surface)
        } else {
            visibleTransientSurfaces.remove(surface)
        }
        onTransientUIVisibilityChanged?(!visibleTransientSurfaces.isEmpty)
    }

    private func observeQuickLook(_ panel: QLPreviewPanel) {
        stopObservingQuickLook()
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            quickLookObservationTokens.append(
                center.addObserver(forName: name, object: panel, queue: .main) { [weak self, weak panel] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        // didResignKey is delivered before Quick Look finishes
                        // ordering itself out, so re-check on the next run loop.
                        await Task.yield()
                        if panel?.isVisible != true {
                            self.quickLookDidDisappear()
                        }
                    }
                }
            )
        }

        quickLookVisibilityTask = Task { [weak self, weak panel] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                guard panel?.isVisible == true else {
                    self?.quickLookDidDisappear()
                    return
                }
            }
        }
    }

    private func stopObservingQuickLook() {
        quickLookObservationTokens.forEach {
            NotificationCenter.default.removeObserver($0)
        }
        quickLookObservationTokens.removeAll()
        quickLookVisibilityTask?.cancel()
        quickLookVisibilityTask = nil
    }

    private func quickLookDidDisappear() {
        stopObservingQuickLook()
        setTransientSurface(.quickLook, visible: false)
    }
}

extension CaptureActions:
    @preconcurrency QLPreviewPanelDataSource,
    QLPreviewPanelDelegate,
    @preconcurrency NSSharingServicePickerDelegate
{
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard previewItems.indices.contains(index) else { return nil }
        return previewItems[index] as NSURL
    }

    func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        previewItems.removeAll()
        Task { [weak self, weak panel] in
            await Task.yield()
            if panel?.isVisible != true {
                self?.quickLookDidDisappear()
            }
        }
        if panel.dataSource as AnyObject? === self {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        if self.sharingPicker === sharingServicePicker {
            self.sharingPicker = nil
        }
        setTransientSurface(.sharingPicker, visible: false)
    }
}

private let actionLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.illiagryniuk.capturearc",
    category: "CaptureActions"
)
