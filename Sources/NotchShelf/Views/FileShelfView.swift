import AppKit
import SwiftUI

struct FileShelfView: View {
    @ObservedObject var store: FileShelfStore

    var body: some View {
        VStack(spacing: 0) {
            folderTabs
            Divider().opacity(0.24)

            if store.tabs.isEmpty {
                emptyState
            } else {
                navigationBar
                Divider().opacity(0.18)
                fileList
                Divider().opacity(0.24)
                actionBar
            }
        }
        .alert(
            "Folder action failed",
            isPresented: Binding(
                get: { store.presentedError != nil },
                set: { if !$0 { store.presentedError = nil } }
            )
        ) {
            Button("OK") { store.presentedError = nil }
        } message: {
            Text(store.presentedError ?? "Unknown error")
        }
    }

    private var folderTabs: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.tabs) { tab in
                        HStack(spacing: 4) {
                            Button {
                                store.selectTab(tab.id)
                            } label: {
                                Label(tab.displayName, systemImage: "folder.fill")
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)

                            Button {
                                store.closeTab(tab.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close \(tab.displayName) tab")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(store.selectedTabID == tab.id ? .primary : .secondary)
                        .padding(.leading, 10)
                        .padding(.trailing, 5)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    store.selectedTabID == tab.id
                                        ? Color.white.opacity(0.13)
                                        : Color.white.opacity(0.045)
                                )
                        )
                    }
                }
            }

            Button(action: store.chooseFolder) {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Add a persistent folder tab")
            .accessibilityLabel("Add folder tab")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.white.opacity(0.025))
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            Button(action: store.goUp) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.selectedTab?.currentRelativePath.isEmpty != false)
            .help("Go to enclosing folder")

            Button(action: store.goToRoot) {
                Image(systemName: "house")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.selectedTab?.currentRelativePath.isEmpty != false)
            .help("Return to tab folder")

            Image(systemName: "folder.fill")
                .foregroundStyle(NotchShelfTheme.accentGradient)

            Text(currentPathTitle)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            if store.isLoading {
                ProgressView().controlSize(.small)
            }

            Button(action: store.reload) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Reload this folder")

            Button(action: store.revealSelected) {
                Image(systemName: "arrow.forward.square")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Show this location in Finder")
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    @ViewBuilder
    private var fileList: some View {
        if store.isLoading && store.items.isEmpty {
            ProgressView("Opening folder…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Folder Is Empty")
                    .font(.headline)
                Text("Files and folders placed here will appear in this tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $store.selectedItemIDs) {
                ForEach(store.items) { item in
                    FileShelfRow(item: item)
                        .tag(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            store.activate(item)
                        }
                        .contextMenu {
                            Button(item.isDirectory ? "Open Folder" : "Open") {
                                store.activate(item)
                            }
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            }
                        }
                }
            }
            .listStyle(.inset)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Label(selectionText, systemImage: "checkmark.circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Show in Finder", action: store.revealSelected)
                .buttonStyle(.bordered)

            Button("Open", action: store.openSelected)
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedItemIDs.isEmpty)
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.white.opacity(0.025))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(NotchShelfTheme.accentGradient)
            Text("Keep folders at the notch")
                .font(.headline)
            Text("Add a folder as a tab. CaptureArc remembers it locally and restores access after relaunch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
            Button("Add Folder Tab…", action: store.chooseFolder)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var currentPathTitle: String {
        guard let tab = store.selectedTab else { return "Files" }
        if tab.currentRelativePath.isEmpty { return tab.displayName }
        return "\(tab.displayName) / \(tab.currentRelativePath)"
    }

    private var selectionText: String {
        let count = store.selectedItemIDs.count
        if count == 0 { return "\(store.items.count) items" }
        return count == 1 ? "1 selected" : "\(count) selected"
    }
}

private struct FileShelfRow: View {
    let item: FileShelfItem

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.typeDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if let modifiedAt = item.modifiedAt {
                Text(modifiedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .trailing)
            }

            Text(sizeText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.displayName), \(item.typeDescription), \(sizeText)")
    }

    private var sizeText: String {
        guard let fileSize = item.fileSize else { return "—" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
