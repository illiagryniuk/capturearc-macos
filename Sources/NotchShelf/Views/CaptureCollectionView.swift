import AppKit
import OSLog
import SwiftUI

/// SwiftUI owns the capture state while NSCollectionView supplies the mature
/// desktop selection, keyboard, context-menu, and file-drag behavior.
struct CaptureCollectionView: NSViewRepresentable {
    @ObservedObject var library: CaptureLibrary
    let actions: CaptureActions
    var onRequestClose: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            library: library,
            actions: actions,
            onRequestClose: onRequestClose
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let flowLayout = NSCollectionViewFlowLayout()
        flowLayout.minimumInteritemSpacing = 12
        flowLayout.minimumLineSpacing = 12
        flowLayout.sectionInset = NSEdgeInsets(top: 8, left: 16, bottom: 16, right: 16)
        flowLayout.headerReferenceSize = NSSize(width: 0, height: 32)
        flowLayout.itemSize = NSSize(width: 142, height: 128)
        flowLayout.sectionHeadersPinToVisibleBounds = true

        let collectionView = CaptureNativeCollectionView()
        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.isSelectable = true
        collectionView.allowsEmptySelection = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        collectionView.register(
            CaptureCollectionItem.self,
            forItemWithIdentifier: CaptureCollectionItem.reuseIdentifier
        )
        collectionView.register(
            CaptureSectionHeader.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: CaptureSectionHeader.reuseIdentifier
        )

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        context.coordinator.connect(collectionView)
        context.coordinator.apply(
            sections: library.sections,
            selectedIDs: library.selectedIDs,
            forceReload: true
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onRequestClose = onRequestClose
        context.coordinator.apply(
            sections: library.sections,
            selectedIDs: library.selectedIDs
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        let library: CaptureLibrary
        let actions: CaptureActions
        var onRequestClose: () -> Void

        private(set) var sections: [CaptureSection] = []
        private weak var collectionView: CaptureNativeCollectionView?
        private var isApplyingModelSelection = false

        init(
            library: CaptureLibrary,
            actions: CaptureActions,
            onRequestClose: @escaping () -> Void
        ) {
            self.library = library
            self.actions = actions
            self.onRequestClose = onRequestClose
        }

        fileprivate func connect(_ collectionView: CaptureNativeCollectionView) {
            self.collectionView = collectionView

            collectionView.itemsAtIndexPaths = { [weak self] indexPaths in
                self?.items(at: indexPaths) ?? []
            }
            collectionView.allIndexPaths = { [weak self] in
                self?.orderedIndexPaths ?? []
            }
            collectionView.selectionDidChange = { [weak self] in
                self?.syncSelectionToLibrary()
            }
            collectionView.onOpen = { [weak self] items in
                self?.actions.open(items)
            }
            collectionView.onQuickLook = { [weak self] items in
                self?.actions.quickLook(items)
            }
            collectionView.onShare = { [weak self, weak collectionView] items in
                self?.actions.share(items, from: collectionView)
            }
            collectionView.onCopy = { [weak self] items in
                self?.actions.copy(items)
            }
            collectionView.onReveal = { [weak self] items in
                self?.actions.reveal(items)
            }
            collectionView.onTrash = { [weak self] items in
                self?.actions.moveToTrash(items)
            }
            collectionView.onSelectAll = { [weak self] in
                self?.library.selectAll()
            }
            collectionView.onRequestClose = { [weak self] in
                self?.onRequestClose()
            }
        }

        func apply(
            sections: [CaptureSection],
            selectedIDs: Set<CaptureItem.ID>,
            forceReload: Bool = false
        ) {
            let contentChanged = forceReload || self.sections != sections
            self.sections = sections

            if contentChanged {
                isApplyingModelSelection = true
                collectionView?.reloadData()
                isApplyingModelSelection = false
            }
            applySelection(selectedIDs)
        }

        private var orderedIndexPaths: [IndexPath] {
            sections.enumerated().flatMap { sectionIndex, section in
                section.items.indices.map {
                    IndexPath(item: $0, section: sectionIndex)
                }
            }
        }

        private func item(at indexPath: IndexPath) -> CaptureItem? {
            guard sections.indices.contains(indexPath.section),
                  sections[indexPath.section].items.indices.contains(indexPath.item) else {
                return nil
            }
            return sections[indexPath.section].items[indexPath.item]
        }

        private func items(at indexPaths: Set<IndexPath>) -> [CaptureItem] {
            orderedIndexPaths
                .filter(indexPaths.contains)
                .compactMap(item(at:))
        }

        private func applySelection(_ selectedIDs: Set<CaptureItem.ID>) {
            guard let collectionView else { return }
            let paths = Set(orderedIndexPaths.filter {
                item(at: $0).map { selectedIDs.contains($0.id) } ?? false
            })
            guard collectionView.selectionIndexPaths != paths else { return }

            isApplyingModelSelection = true
            collectionView.selectionIndexPaths = paths
            isApplyingModelSelection = false
        }

        private func syncSelectionToLibrary() {
            guard !isApplyingModelSelection, let collectionView else { return }
            let selectedItems = items(at: collectionView.selectionIndexPaths)
            let selectedIDs = Set(selectedItems.map(\.id))
            guard library.selectedIDs != selectedIDs else { return }
            library.selectedIDs = selectedIDs
            collectionLogger.info(
                "Native selection changed: \(selectedIDs.count, privacy: .public) item(s)"
            )
        }
    }
}

@MainActor
extension CaptureCollectionView.Coordinator:
    NSCollectionViewDataSource,
    NSCollectionViewDelegate,
    NSCollectionViewDelegateFlowLayout
{
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        sections.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        guard sections.indices.contains(section) else { return 0 }
        return sections[section].items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let collectionItem = collectionView.makeItem(
            withIdentifier: CaptureCollectionItem.reuseIdentifier,
            for: indexPath
        )
        guard let captureItem = collectionItem as? CaptureCollectionItem,
              let item = item(at: indexPath) else {
            return collectionItem
        }

        captureItem.configure(with: item, thumbnailService: library.thumbnailService)
        return captureItem
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
        at indexPath: IndexPath
    ) -> NSView {
        let view = collectionView.makeSupplementaryView(
            ofKind: kind,
            withIdentifier: CaptureSectionHeader.reuseIdentifier,
            for: indexPath
        )
        guard let header = view as? CaptureSectionHeader,
              sections.indices.contains(indexPath.section) else {
            return view
        }
        header.configure(title: Self.title(for: sections[indexPath.section].group))
        return header
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        syncSelectionToLibrary()
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didDeselectItemsAt indexPaths: Set<IndexPath>
    ) {
        syncSelectionToLibrary()
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard let item = item(at: indexPath), item.status == .ready else { return nil }
        collectionLogger.debug("Starting external file URL drag")
        return item.fileURL as NSURL
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        let availableWidth = max(300, collectionView.bounds.width - 32)
        let preferredWidth: CGFloat = 142
        let columns = max(2, min(4, Int((availableWidth + 12) / (preferredWidth + 12))))
        let width = floor((availableWidth - CGFloat(columns - 1) * 12) / CGFloat(columns))
        return NSSize(width: width, height: 128)
    }

    private static func title(for group: CaptureDateGroup) -> String {
        switch group {
        case .today:
            return "Today"
        case .yesterday:
            return "Yesterday"
        case .day(let date):
            return sectionDateFormatter.string(from: date)
        }
    }
}

/// The native responder surface. It deliberately delegates all state and file
/// actions back through closures instead of becoming a second source of truth.
@MainActor
private final class CaptureNativeCollectionView: NSCollectionView {
    var itemsAtIndexPaths: (Set<IndexPath>) -> [CaptureItem] = { _ in [] }
    var allIndexPaths: () -> [IndexPath] = { [] }
    var selectionDidChange: () -> Void = {}
    var onOpen: ([CaptureItem]) -> Void = { _ in }
    var onQuickLook: ([CaptureItem]) -> Void = { _ in }
    var onShare: ([CaptureItem]) -> Void = { _ in }
    var onCopy: ([CaptureItem]) -> Void = { _ in }
    var onReveal: ([CaptureItem]) -> Void = { _ in }
    var onTrash: ([CaptureItem]) -> Void = { _ in }
    var onSelectAll: () -> Void = {}
    var onRequestClose: () -> Void = {}

    private var keyboardAnchor: IndexPath?
    private var keyboardLead: IndexPath?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Hovering is deliberately nonactivating. A deliberate item click is
        // the handoff point where keyboard navigation, Space, Delete, and
        // Command shortcuts must belong to CaptureArc until it collapses.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        window?.makeFirstResponder(self)

        let location = convert(event.locationInWindow, from: nil)
        let clickedIndexPath = indexPathForItem(at: location)
        super.mouseDown(with: event)

        if event.modifierFlags.contains(.shift) {
            keyboardLead = clickedIndexPath
        } else {
            keyboardAnchor = clickedIndexPath
            keyboardLead = clickedIndexPath
        }
        selectionDidChange()

        if event.clickCount == 2 {
            let items = selectedItems(fallingBackTo: clickedIndexPath)
            guard !items.isEmpty else { return }
            onOpen(items)
        }
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "a" {
            selectEveryItem()
            return
        }
        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" {
            onCopy(selectedItems())
            return
        }

        switch event.keyCode {
        case 53: // Escape
            onRequestClose()
        case 49: // Space
            onQuickLook(selectedItems())
        case 36, 76: // Return / keypad enter
            onOpen(selectedItems())
        case 51, 117: // Delete / forward delete
            onTrash(selectedItems())
        case 123: // Left
            moveSelection(by: -1, extending: flags.contains(.shift))
        case 124: // Right
            moveSelection(by: 1, extending: flags.contains(.shift))
        case 125: // Down
            moveSelection(by: estimatedColumnCount, extending: flags.contains(.shift))
        case 126: // Up
            moveSelection(by: -estimatedColumnCount, extending: flags.contains(.shift))
        default:
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased()
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        if key == "a" {
            selectEveryItem()
            return true
        }
        if key == "c" {
            onCopy(selectedItems())
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        guard let indexPath = indexPathForItem(at: location) else { return nil }

        if !selectionIndexPaths.contains(indexPath) {
            selectionIndexPaths = [indexPath]
            keyboardAnchor = indexPath
            keyboardLead = indexPath
            selectionDidChange()
        }

        let menu = NSMenu(title: "Capture")
        menu.autoenablesItems = false
        menu.addItem(menuItem("Open", action: #selector(openSelected), key: ""))
        menu.addItem(menuItem("Quick Look", action: #selector(quickLookSelected), key: " "))
        menu.addItem(.separator())
        menu.addItem(menuItem("Share…", action: #selector(shareSelected), key: ""))
        menu.addItem(menuItem("Copy", action: #selector(copySelected), key: "c"))
        menu.addItem(menuItem("Show in Finder", action: #selector(revealSelected), key: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Move to Trash", action: #selector(trashSelected), key: ""))
        return menu
    }

    @objc private func openSelected() { onOpen(selectedItems()) }
    @objc private func quickLookSelected() { onQuickLook(selectedItems()) }

    @objc private func shareSelected() {
        onShare(selectedItems())
    }

    @objc private func copySelected() { onCopy(selectedItems()) }
    @objc private func revealSelected() { onReveal(selectedItems()) }
    @objc private func trashSelected() { onTrash(selectedItems()) }

    private func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = !selectionIndexPaths.isEmpty
        return item
    }

    private func selectedItems(fallingBackTo indexPath: IndexPath? = nil) -> [CaptureItem] {
        var paths = selectionIndexPaths
        if paths.isEmpty, let indexPath {
            paths = [indexPath]
        }
        return itemsAtIndexPaths(paths)
    }

    private func selectEveryItem() {
        let paths = Set(allIndexPaths())
        selectionIndexPaths = paths
        keyboardAnchor = allIndexPaths().first
        keyboardLead = allIndexPaths().last
        onSelectAll()
        selectionDidChange()
    }

    private func moveSelection(by delta: Int, extending: Bool) {
        let paths = allIndexPaths()
        guard !paths.isEmpty else { return }

        let current = keyboardLead
            .flatMap { paths.firstIndex(of: $0) }
            ?? selectionIndexPaths.compactMap { paths.firstIndex(of: $0) }.sorted().last
            ?? (delta < 0 ? paths.count : -1)
        let destinationIndex = min(max(0, current + delta), paths.count - 1)
        let destination = paths[destinationIndex]

        if extending {
            let anchor = keyboardAnchor ?? selectionIndexPaths.first ?? destination
            let anchorIndex = paths.firstIndex(of: anchor) ?? destinationIndex
            let bounds = min(anchorIndex, destinationIndex)...max(anchorIndex, destinationIndex)
            selectionIndexPaths = Set(bounds.map { paths[$0] })
            keyboardLead = destination
        } else {
            selectionIndexPaths = [destination]
            keyboardAnchor = destination
            keyboardLead = destination
        }

        scrollToItems(at: [destination], scrollPosition: .nearestHorizontalEdge)
        scrollToItems(at: [destination], scrollPosition: .nearestVerticalEdge)
        selectionDidChange()
    }

    private var estimatedColumnCount: Int {
        // Keep this formula in sync with the flow-layout delegate above. The
        // actual item width is delegate-provided, so flowLayout.itemSize alone
        // cannot reliably describe the number of columns.
        let availableWidth = max(300, bounds.width - 32)
        let preferredWidth: CGFloat = 142
        return max(2, min(4, Int((availableWidth + 12) / (preferredWidth + 12))))
    }
}

@MainActor
private final class CaptureCollectionItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("CaptureCollectionItem")

    private let thumbnailView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let videoBadge = NSTextField(labelWithString: "")
    private let missingBadge = NSImageView()
    private var representedID: CaptureItem.ID?
    private var thumbnailTask: Task<Void, Never>?

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    override func loadView() {
        let root = NSVisualEffectView()
        root.material = .contentBackground
        root.blendingMode = .withinWindow
        root.state = .followsWindowActiveState
        root.wantsLayer = true
        root.layer?.cornerRadius = NotchShelfTheme.cardCornerRadius
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor.controlBackgroundColor
            .withAlphaComponent(0.18)
            .cgColor
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.separatorColor
            .withAlphaComponent(0.28)
            .cgColor

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.imageAlignment = .alignCenter
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 9
        thumbnailView.layer?.cornerCurve = .continuous
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.26).cgColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        videoBadge.translatesAutoresizingMaskIntoConstraints = false
        videoBadge.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        videoBadge.textColor = .white
        videoBadge.alignment = .center
        videoBadge.wantsLayer = true
        videoBadge.layer?.cornerRadius = 5
        videoBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.74).cgColor
        videoBadge.isHidden = true

        missingBadge.translatesAutoresizingMaskIntoConstraints = false
        missingBadge.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "File missing")
        missingBadge.contentTintColor = .systemOrange
        missingBadge.isHidden = true

        [thumbnailView, titleLabel, detailLabel, videoBadge, missingBadge].forEach(root.addSubview)
        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            thumbnailView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            thumbnailView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            thumbnailView.heightAnchor.constraint(equalToConstant: 82),

            titleLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -5),

            videoBadge.trailingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: -5),
            videoBadge.bottomAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: -5),
            videoBadge.heightAnchor.constraint(equalToConstant: 18),
            videoBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 38),

            missingBadge.centerXAnchor.constraint(equalTo: thumbnailView.centerXAnchor),
            missingBadge.centerYAnchor.constraint(equalTo: thumbnailView.centerYAnchor),
            missingBadge.widthAnchor.constraint(equalToConstant: 24),
            missingBadge.heightAnchor.constraint(equalToConstant: 24)
        ])

        root.setAccessibilityElement(true)
        view = root
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        thumbnailTask = nil
        representedID = nil
        thumbnailView.image = nil
        titleLabel.stringValue = ""
        detailLabel.stringValue = ""
        videoBadge.isHidden = true
        missingBadge.isHidden = true
    }

    func configure(with item: CaptureItem, thumbnailService: ThumbnailService) {
        thumbnailTask?.cancel()
        representedID = item.id
        titleLabel.stringValue = item.displayName
        detailLabel.stringValue = Self.detailText(for: item)
        missingBadge.isHidden = item.status != .missing

        if item.isVideo {
            videoBadge.stringValue = Self.durationText(item.duration)
            videoBadge.isHidden = false
        } else {
            videoBadge.isHidden = true
        }

        let dimensions = item.dimensions.map { "\($0.width) × \($0.height)" } ?? "Unknown dimensions"
        let accessibility = [
            item.displayName,
            Self.timeFormatter.string(from: item.createdAt),
            dimensions,
            ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file),
            item.isVideo ? "Screen recording" : "Screenshot"
        ].joined(separator: ", ")
        view.setAccessibilityLabel(accessibility)
        view.toolTip = accessibility

        let representedID = item.id
        thumbnailTask = Task { [weak self] in
            let image = try? await thumbnailService.thumbnail(
                for: item,
                size: CGSize(width: 220, height: 132),
                scale: NSScreen.main?.backingScaleFactor ?? 2
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.representedID == representedID else { return }
                self.thumbnailView.image = image
                if image == nil {
                    self.thumbnailView.image = NSImage(
                        systemSymbolName: item.isVideo ? "film" : "photo",
                        accessibilityDescription: nil
                    )
                }
            }
        }
    }

    private func updateSelectionAppearance() {
        view.layer?.borderWidth = isSelected ? 2 : 1
        view.layer?.borderColor = isSelected
            ? NotchShelfTheme.selectionBorderColor.cgColor
            : NSColor.separatorColor.withAlphaComponent(0.28).cgColor
        view.layer?.backgroundColor = isSelected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.24).cgColor
            : NSColor.controlBackgroundColor.withAlphaComponent(0.18).cgColor
    }

    private static func detailText(for item: CaptureItem) -> String {
        let time = timeFormatter.string(from: item.createdAt)
        let size = ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file)
        return "\(time)  •  \(size)"
    }

    private static func durationText(_ duration: TimeInterval?) -> String {
        guard let duration, duration.isFinite else { return "VIDEO" }
        let total = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

@MainActor
private final class CaptureSectionHeader: NSVisualEffectView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("CaptureSectionHeader")
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .contentBackground
        blendingMode = .withinWindow
        state = .followsWindowActiveState
        wantsLayer = true
        layer?.backgroundColor = NSColor.black
            .withAlphaComponent(0.28)
            .cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11.5, weight: .semibold)
        label.textColor = .labelColor
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(title: String) {
        label.stringValue = title
        setAccessibilityLabel(title)
    }
}

private let sectionDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    formatter.doesRelativeDateFormatting = false
    return formatter
}()

private let collectionLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.illiagryniuk.capturearc",
    category: "CaptureCollection"
)
