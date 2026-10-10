import SwiftUI

private enum ShelfSection: String, CaseIterable {
    case screenshots
    case files
}

struct CaptureShelfView: View {
    @ObservedObject private var library: CaptureLibrary
    @ObservedObject private var actions: CaptureActions
    @ObservedObject private var fileStore: FileShelfStore
    private let onRequestClose: () -> Void

    @State private var isConfirmingTrashAll = false
    @AppStorage(PreferenceKeys.selectedShelfSection)
    private var selectedSectionRawValue = ShelfSection.screenshots.rawValue

    init(
        library: CaptureLibrary,
        actions: CaptureActions,
        fileStore: FileShelfStore,
        onRequestClose: @escaping () -> Void = {}
    ) {
        self.library = library
        self.actions = actions
        self.fileStore = fileStore
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
        HStack(spacing: 12) {
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
                Text(selectedSection == .screenshots ? "Capture Shelf" : "File Shelf")
                    .font(.system(size: 13, weight: .semibold))
                Label(
                    selectedSection == .screenshots ? statusText : fileStatusText,
                    systemImage: statusSystemImage
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Picker("Shelf", selection: selectedSectionBinding) {
                Label("Screenshots", systemImage: "camera.viewfinder")
                    .tag(ShelfSection.screenshots)
                Label("Files", systemImage: "folder")
                    .tag(ShelfSection.files)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 230)
            .accessibilityLabel("Shelf section")

            if selectedSection == .screenshots && library.isReconciling {
                ProgressView()
                    .controlSize(.small)
                    .help("Scanning the capture folder")
            }

            if selectedSection == .screenshots {
                Button(action: library.rescan) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Rescan capture folder")
                .help("Rescan capture folder")
            }

            Button(action: onRequestClose) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Collapse Capture Shelf")
            .help("Collapse shelf")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color.white.opacity(0.035))
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

    private var statusSystemImage: String {
        if selectedSection == .screenshots {
            return library.isReconciling
                ? "arrow.triangle.2.circlepath"
                : "checkmark.circle"
        }
        return fileStore.tabs.isEmpty ? "folder.badge.plus" : "folder.fill"
    }
}
