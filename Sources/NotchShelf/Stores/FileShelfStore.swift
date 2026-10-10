import AppKit
import Foundation
import OSLog

struct FileShelfTab: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let rootURL: URL
    var currentRelativePath: String

    var currentURL: URL {
        FileShelfPath.currentURL(root: rootURL, relativePath: currentRelativePath)
    }
}

@MainActor
final class FileShelfStore: ObservableObject {
    @Published private(set) var tabs: [FileShelfTab] = []
    @Published private(set) var selectedTabID: FileShelfTab.ID?
    @Published private(set) var items: [FileShelfItem] = []
    @Published var selectedItemIDs: Set<FileShelfItem.ID> = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPresentingTransientUI = false
    @Published var presentedError: String?

    var onTransientUIVisibilityChanged: ((Bool) -> Void)?

    var selectedTab: FileShelfTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    var selectedItems: [FileShelfItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    private struct PersistedTab: Codable {
        let id: UUID
        let displayName: String
        let currentRelativePath: String
    }

    private let defaults: UserDefaults
    private var accessManagers: [UUID: FolderAccessManager] = [:]
    private var loadTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restoreTabs()
    }

    deinit {
        loadTask?.cancel()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Add Folder Tab"
        panel.message = "Choose a folder to keep available in CaptureArc. Access stays on this Mac."
        panel.prompt = "Add Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        setTransientUIVisible(true)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                self.setTransientUIVisible(false)
                guard response == .OK, let url = panel.url else { return }
                self.addFolder(url)
            }
        }
    }

    func selectTab(_ id: FileShelfTab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
        defaults.set(id.uuidString, forKey: PreferenceKeys.selectedFileShelfTabID)
        selectedItemIDs.removeAll()
        reload()
    }

    func closeTab(_ id: FileShelfTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        accessManagers.removeValue(forKey: id)?.forgetFolder()
        tabs.remove(at: index)

        if selectedTabID == id {
            selectedTabID = tabs.indices.contains(index)
                ? tabs[index].id
                : tabs.last?.id
        }
        selectedItemIDs.removeAll()
        persistTabs()
        persistSelection()
        reload()
        fileShelfLogger.info("Closed persistent folder tab")
    }

    func reload() {
        loadTask?.cancel()
        selectedItemIDs.removeAll()

        guard let tab = selectedTab else {
            items = []
            isLoading = false
            return
        }

        let directoryURL = tab.currentURL
        let expectedTabID = tab.id
        isLoading = true
        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try Self.loadItems(in: directoryURL) }
            }.value

            guard !Task.isCancelled, let self,
                  self.selectedTabID == expectedTabID,
                  self.selectedTab?.currentURL == directoryURL else { return }

            self.isLoading = false
            switch result {
            case .success(let loadedItems):
                self.items = loadedItems
                fileShelfLogger.info(
                    "Loaded \(loadedItems.count, privacy: .public) file shelf item(s)"
                )
            case .failure(let error):
                self.items = []
                self.presentedError = "This folder could not be opened. \(error.localizedDescription)"
                fileShelfLogger.error("Folder tab load failed")
            }
        }
    }

    func activate(_ item: FileShelfItem) {
        if item.isDirectory {
            navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
            fileShelfLogger.info("Opened file from folder tab")
        }
    }

    func openSelected() {
        let selection = selectedItems
        if selection.count == 1, let item = selection.first {
            activate(item)
            return
        }
        selection.filter { !$0.isDirectory }.forEach { NSWorkspace.shared.open($0.url) }
    }

    func revealSelected() {
        let urls = selectedItems.map(\.url)
        if urls.isEmpty, let currentURL = selectedTab?.currentURL {
            NSWorkspace.shared.activateFileViewerSelecting([currentURL])
        } else if !urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    func goToRoot() {
        updateCurrentPath("")
    }

    func goUp() {
        guard let tab = selectedTab, !tab.currentRelativePath.isEmpty else { return }
        let parent = (tab.currentRelativePath as NSString).deletingLastPathComponent
        updateCurrentPath(parent == "." ? "" : parent)
    }

    func addFolder(_ selectedURL: URL) {
        let url = selectedURL.standardizedFileURL
        if let existing = tabs.first(where: { $0.rootURL == url }) {
            selectTab(existing.id)
            return
        }

        let id = UUID()
        let manager = FolderAccessManager(
            defaults: defaults,
            bookmarkKey: bookmarkKey(for: id)
        )

        do {
            let resolution = try manager.authorize(url)
            accessManagers[id] = manager
            let tab = FileShelfTab(
                id: id,
                displayName: FileManager.default.displayName(atPath: resolution.url.path),
                rootURL: resolution.url,
                currentRelativePath: ""
            )
            tabs.append(tab)
            selectedTabID = id
            persistTabs()
            persistSelection()
            reload()
            fileShelfLogger.info("Added persistent folder tab")
        } catch {
            presentedError = "The folder could not be added. \(error.localizedDescription)"
            fileShelfLogger.error("Folder tab authorization failed")
        }
    }

    private func navigate(to directoryURL: URL) {
        guard let tab = selectedTab,
              let relativePath = FileShelfPath.relativePath(
                of: directoryURL,
                inside: tab.rootURL
              ) else {
            presentedError = "CaptureArc can only browse inside the folder authorized for this tab."
            return
        }
        updateCurrentPath(relativePath)
    }

    private func updateCurrentPath(_ path: String) {
        guard let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        tabs[index].currentRelativePath = path
        persistTabs()
        reload()
    }

    private func restoreTabs() {
        guard let data = defaults.data(forKey: PreferenceKeys.fileShelfTabs),
              let records = try? JSONDecoder().decode([PersistedTab].self, from: data) else {
            return
        }

        var restored: [FileShelfTab] = []
        for record in records {
            let manager = FolderAccessManager(
                defaults: defaults,
                bookmarkKey: bookmarkKey(for: record.id)
            )
            do {
                let resolution = try manager.restore()
                accessManagers[record.id] = manager
                let requestedURL = FileShelfPath.currentURL(
                    root: resolution.url,
                    relativePath: record.currentRelativePath
                )
                let isDirectory = (try? requestedURL.resourceValues(
                    forKeys: [.isDirectoryKey]
                ).isDirectory) == true
                restored.append(
                    FileShelfTab(
                        id: record.id,
                        displayName: record.displayName,
                        rootURL: resolution.url,
                        currentRelativePath: isDirectory ? record.currentRelativePath : ""
                    )
                )
            } catch {
                manager.forgetFolder()
                fileShelfLogger.error("A persistent folder tab could not be restored")
            }
        }

        tabs = restored
        let storedSelection = defaults.string(forKey: PreferenceKeys.selectedFileShelfTabID)
            .flatMap(UUID.init(uuidString:))
        selectedTabID = restored.contains(where: { $0.id == storedSelection })
            ? storedSelection
            : restored.first?.id
        persistTabs()
        persistSelection()
        reload()
    }

    private func persistTabs() {
        let records = tabs.map {
            PersistedTab(
                id: $0.id,
                displayName: $0.displayName,
                currentRelativePath: $0.currentRelativePath
            )
        }
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: PreferenceKeys.fileShelfTabs)
        }
    }

    private func persistSelection() {
        if let selectedTabID {
            defaults.set(selectedTabID.uuidString, forKey: PreferenceKeys.selectedFileShelfTabID)
        } else {
            defaults.removeObject(forKey: PreferenceKeys.selectedFileShelfTabID)
        }
    }

    private func bookmarkKey(for id: UUID) -> String {
        "NotchShelf.fileShelfBookmark.\(id.uuidString)"
    }

    private func setTransientUIVisible(_ isVisible: Bool) {
        isPresentingTransientUI = isVisible
        onTransientUIVisibilityChanged?(isVisible)
    }

    private nonisolated static func loadItems(in directoryURL: URL) throws -> [FileShelfItem] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isHiddenKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .localizedTypeDescriptionKey,
            .localizedNameKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        let loaded = urls.compactMap { url -> FileShelfItem? in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isHidden != true else { return nil }
            let isDirectory = values.isDirectory == true
            return FileShelfItem(
                url: url.standardizedFileURL,
                displayName: values.localizedName ?? url.lastPathComponent,
                isDirectory: isDirectory,
                modifiedAt: values.contentModificationDate,
                fileSize: isDirectory ? nil : values.fileSize.map(Int64.init),
                typeDescription: values.localizedTypeDescription
                    ?? (isDirectory ? "Folder" : "File")
            )
        }
        return FileShelfPath.sorted(loaded)
    }
}

private let fileShelfLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.illiagryniuk.capturearc",
    category: "FileShelf"
)
