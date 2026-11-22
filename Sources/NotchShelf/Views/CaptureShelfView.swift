import ClipboardDemoTransport
import SwiftUI

private enum ShelfSection: String, CaseIterable, Identifiable {
    case screenshots
    case files
    case incomingFromiPhone

    var id: Self { self }

    var tabTitle: String {
        switch self {
        case .screenshots: return CaptureArcText.value("Screenshots")
        case .files: return CaptureArcText.value("Files")
        case .incomingFromiPhone: return CaptureArcText.value("From iPhone")
        }
    }

    var tabIcon: String {
        switch self {
        case .screenshots: return "camera.viewfinder"
        case .files: return "folder"
        case .incomingFromiPhone: return "iphone"
        }
    }
}

struct CaptureShelfView: View {
    @ObservedObject private var library: CaptureLibrary
    @ObservedObject private var actions: CaptureActions
    @ObservedObject private var fileStore: FileShelfStore
    @ObservedObject private var incomingStore: IncomingTransferStore
    private let onRequestClose: () -> Void

    @State private var isConfirmingTrashAll = false
    @AppStorage(PreferenceKeys.selectedShelfSection)
    private var selectedSectionRawValue = ShelfSection.screenshots.rawValue

    init(
        library: CaptureLibrary,
        actions: CaptureActions,
        fileStore: FileShelfStore,
        incomingStore: IncomingTransferStore,
        onRequestClose: @escaping () -> Void = {}
    ) {
        self.library = library
        self.actions = actions
        self.fileStore = fileStore
        self.incomingStore = incomingStore
        self.onRequestClose = onRequestClose
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.24)

            switch selectedSection {
            case .screenshots:
                if library.items.isEmpty {
                    emptyState
                } else {
                    CaptureCollectionView(
                        library: library,
                        actions: actions,
                        onRequestClose: onRequestClose
                    )
                }

                Divider().opacity(0.24)
                actionBar
            case .files:
                FileShelfView(store: fileStore)
            case .incomingFromiPhone:
                IncomingTransferView(store: incomingStore)
            }
        }
        .alert(
            "Capture action failed",
            isPresented: Binding(
                get: { actions.presentedError != nil },
                set: { if !$0 { actions.presentedError = nil } }
            ),
            actions: {
                Button("OK") { actions.presentedError = nil }
            },
            message: {
                Text(actions.presentedError ?? "Unknown error")
            }
        )
        .confirmationDialog(
            "Move every capture to the Trash?",
            isPresented: $isConfirmingTrashAll
        ) {
            Button("Move All to Trash", role: .destructive) {
                actions.moveToTrash(library.items)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The files can be recovered from the macOS Trash.")
        }
    }

    private var header: some View {
        ShelfHeaderLayout {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(NotchShelfTheme.accentGradient)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(sectionTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Label(sectionStatus, systemImage: statusSystemImage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            // Fit navigation only inside the space left by the trailing actions.
            ViewThatFits(in: .horizontal) {
                sectionTabs(showsTitles: true)
                sectionTabs(showsTitles: false)
                Menu {
                    Picker("Shelf section", selection: selectedSectionBinding) {
                        ForEach(ShelfSection.allCases) { section in
                            Label(section.tabTitle, systemImage: section.tabIcon).tag(section)
                        }
                    }
                } label: {
                    Image(systemName: selectedSection.tabIcon)
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel("Shelf section")
                .accessibilityValue(selectedSection.tabTitle)
                .help(selectedSection.tabTitle)
            }

            HStack(spacing: 6) {
                if selectedSection == .screenshots && library.isReconciling {
                    ProgressView()
                        .controlSize(.small)
                        .help("Scanning the capture folder")
                }

                if selectedSection == .screenshots {
                    Button(action: library.rescan) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Rescan capture folder")
                    .help("Rescan capture folder")
                }

                Button(action: onRequestClose) {
                    Image(systemName: "chevron.up")
                }
                .accessibilityLabel("Collapse Capture Shelf")
                .help("Collapse shelf")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Color.white.opacity(0.035))
    }

    private func sectionTabs(showsTitles: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(ShelfSection.allCases) { section in
                Button {
                    selectedSectionBinding.wrappedValue = section
                } label: {
                    Label(section.tabTitle, systemImage: section.tabIcon)
                        .labelStyle(ShelfTabLabelStyle(showsTitle: showsTitles))
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, showsTitles ? 7 : 8)
                        .frame(minWidth: 27, minHeight: 24)
                        .contentShape(Rectangle())
                        .background {
                            if selectedSection == section {
                                RoundedRectangle(cornerRadius: 5).fill(.primary.opacity(0.17))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.tabTitle)
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                .help(section.tabTitle)
            }
        }
        .padding(2)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shelf section")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                Circle()
                    .stroke(NotchShelfTheme.accentGradient, lineWidth: 1)
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.primary)
            }
            .frame(width: 54, height: 54)
            .accessibilityHidden(true)

            Text("Take a screenshot to start")
                .font(.headline)
            Text("New screenshots and screen recordings appear here automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Label(
                selectionText,
                systemImage: library.selectedIDs.isEmpty
                    ? "circle.dashed"
                    : "checkmark.circle.fill"
            )
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(minWidth: 92, alignment: .leading)

            Spacer(minLength: 8)

            actionButton(
                "Share",
                systemImage: "square.and.arrow.up",
                prominent: true
            ) {
                actions.share(library.selectedItems)
            }
            actionButton("Copy", systemImage: "doc.on.doc") {
                actions.copy(library.selectedItems)
            }
            actionButton("Reveal", systemImage: "folder") {
                actions.reveal(library.selectedItems)
            }

            Menu {
                Button("Move Selected to Trash") {
                    actions.moveToTrash(library.selectedItems)
                }
                .disabled(library.selectedIDs.isEmpty)

                Divider()

                Button("Move All to Trash", role: .destructive) {
                    isConfirmingTrashAll = true
                }
                .disabled(library.items.isEmpty)
            } label: {
                Label("Trash", systemImage: "trash")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(actions.isWorking)
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.white.opacity(0.025))
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        systemImage: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(action: action) {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(.borderedProminent)
            .disabled(library.selectedIDs.isEmpty || actions.isWorking)
        } else {
            Button(action: action) {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
            .disabled(library.selectedIDs.isEmpty || actions.isWorking)
        }
    }

    private var statusText: String {
        if library.isReconciling {
            return "Scanning capture folder…"
        }
        if library.items.count == 1 {
            return "1 capture ready"
        }
        return "\(library.items.count) captures ready"
    }

    private var selectionText: String {
        let count = library.selectedIDs.count
        if count == 0 { return "No selection" }
        if count == 1 { return "1 selected" }
        return "\(count) selected"
    }

    private var selectedSection: ShelfSection {
        ShelfSection(rawValue: selectedSectionRawValue) ?? .screenshots
    }

    private var selectedSectionBinding: Binding<ShelfSection> {
        Binding(
            get: { selectedSection },
            set: { section in
                selectedSectionRawValue = section.rawValue
                if section == .files {
                    fileStore.reload()
                }
            }
        )
    }

    private var fileStatusText: String {
        if fileStore.isLoading { return "Opening folder…" }
        let count = fileStore.tabs.count
        return count == 1 ? "1 folder tab" : "\(count) folder tabs"
    }

    private var sectionTitle: String {
        switch selectedSection {
        case .screenshots: return "Capture Shelf"
        case .files: return "File Shelf"
        case .incomingFromiPhone: return CaptureArcText.value("From iPhone")
        }
    }

    private var sectionStatus: String {
        switch selectedSection {
        case .screenshots: return statusText
        case .files: return fileStatusText
        case .incomingFromiPhone: return incomingStore.invitationCode != nil ? CaptureArcText.value("Receiving enabled") : (incomingStore.hasReceived ? CaptureArcText.value("Received items") : CaptureArcText.value("Pair your iPhone to get started"))
        }
    }

    private var statusSystemImage: String {
        if selectedSection == .incomingFromiPhone { return "iphone" }
        if selectedSection == .screenshots {
            return library.isReconciling
                ? "arrow.triangle.2.circlepath"
                : "checkmark.circle"
        }
        return fileStore.tabs.isEmpty ? "folder.badge.plus" : "folder.fill"
    }
}

private struct ShelfTabLabelStyle: LabelStyle {
    var showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            if showsTitle { configuration.title }
        }
    }
}

/// Keeps the trailing actions at the right edge. Navigation chooses its
/// presentation only after those actions and a small title reserve are measured.
struct ShelfHeaderLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let actions = subviews[2].sizeThatFits(.unspecified)
        let title = subviews[0].sizeThatFits(.unspecified)
        let navigation = subviews[1].sizeThatFits(.unspecified)
        let idealWidth = title.width + navigation.width + actions.width + ShelfHeaderMetrics.spacing * 2
        return CGSize(width: proposal.width ?? idealWidth,
                      height: max(title.height, navigation.height, actions.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let actions = subviews[2].sizeThatFits(.unspecified)
        let titleIdeal = subviews[0].sizeThatFits(.unspecified)
        let budget = ShelfHeaderMetrics.navigationBudget(width: bounds.width, actions: actions.width, titleIdeal: titleIdeal.width)
        let navigation = subviews[1].sizeThatFits(ProposedViewSize(width: budget, height: bounds.height))
        let actionX = bounds.maxX - actions.width
        let navigationX = actionX - ShelfHeaderMetrics.spacing - navigation.width
        let titleWidth = max(0, navigationX - ShelfHeaderMetrics.spacing - bounds.minX)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: titleWidth, height: bounds.height))
        subviews[1].place(at: CGPoint(x: navigationX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: budget, height: bounds.height))
        subviews[2].place(at: CGPoint(x: actionX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(actions))
    }
}
