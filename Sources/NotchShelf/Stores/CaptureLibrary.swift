import Combine
import Foundation
import OSLog

public enum CaptureLibraryError: Error {
    case initialReconciliationFailed
}

@MainActor
public final class CaptureLibrary: ObservableObject {
    @Published public private(set) var items: [CaptureItem] = []
    @Published public var selectedIDs: Set<CaptureItem.ID> = []
    @Published public private(set) var captureFolderURL: URL?
    @Published public private(set) var systemScreenshotFolderURL: URL?
    @Published public private(set) var folderStatus: FolderAccessStatus = .notConfigured
    @Published public private(set) var systemScreenshotFolderStatus: FolderAccessStatus = .notConfigured
    @Published public private(set) var isReconciling = false

    public var onNewCapture: ((CaptureItem) -> Void)?
    public let thumbnailService: ThumbnailService

    public var folderURL: URL? { captureFolderURL }
    public var selectedItems: [CaptureItem] {
        items.filter { selectedIDs.contains($0.id) }
    }
    public var selectedURLs: [URL] { selectedItems.map(\.fileURL) }
    public var sections: [CaptureSection] { CaptureGrouping.sections(from: items) }

    private struct PendingLoad {
        let id: UUID
        let task: Task<Void, Never>
    }

    private enum SourceKind: Hashable, Sendable {
        case primary
        case systemScreenshots
    }

    private struct SourceIdentity: Hashable, Sendable {
        let kind: SourceKind
        let folderURL: URL
    }

    private struct CaptureSource: Sendable {
        let identity: SourceIdentity
        let filter: CaptureFileFilter
    }

    private enum CandidateIdentity: Hashable {
        case resource(Data)
        case url(URL)
    }

    private struct CandidateRecord {
        var candidate: CaptureFileCandidate
        var sourceIDs: Set<SourceIdentity>
        var priority: Int
    }

    private let folderAccessManager: FolderAccessManager
    private let folderMonitor: FSEventsFolderMonitor
    private let metadataLoader: CaptureMetadataLoader
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CaptureArc",
        category: "CaptureLibrary"
    )
    private var pendingLoads: [URL: PendingLoad] = [:]
    private var dirtyPendingURLs: Set<URL> = []
    private var reconciliationTask: Task<Void, Never>?
    private var systemMetadataRetryTask: Task<Void, Never>?
    private var isScanning = false
    private var completedBaselineSources: Set<SourceIdentity> = []
    private var selectionAnchorID: CaptureItem.ID?
    private var folderGeneration = UUID()
    private var isStarted = false

    public init(
        folderAccessManager: FolderAccessManager = FolderAccessManager(),
        folderMonitor: FSEventsFolderMonitor = FSEventsFolderMonitor(),
        metadataLoader: CaptureMetadataLoader = CaptureMetadataLoader(),
        thumbnailService: ThumbnailService = .shared
    ) {
        self.folderAccessManager = folderAccessManager
        self.folderMonitor = folderMonitor
        self.metadataLoader = metadataLoader
        self.thumbnailService = thumbnailService
    }

    deinit {
        reconciliationTask?.cancel()
        systemMetadataRetryTask?.cancel()
        pendingLoads.values.forEach { $0.task.cancel() }
        folderMonitor.stop()
        folderAccessManager.relinquishAccess()
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        folderStatus = .resolving
        captureFolderURL = nil

        do {
            let resolution = try folderAccessManager.restore()
            captureFolderURL = resolution.url.standardizedFileURL
            folderStatus = .available
        } catch FolderAccessError.noStoredBookmark {
            folderStatus = .notConfigured
        } catch FolderAccessError.notDirectory {
            folderStatus = .needsReselection
            logger.error("Stored capture folder is no longer a directory")
        } catch FolderAccessError.unreadableDirectory {
            folderStatus = .inaccessible
            logger.error("Stored capture folder is not readable")
        } catch {
            folderStatus = .needsReselection
            logger.error("Capture folder authorization could not be restored")
        }

        do {
            try reconfigureSources(
                resetLibrary: true,
                resettingBaselines: Set(activeSources.map(\.identity))
            )
            if systemScreenshotFolderURL != nil {
                systemScreenshotFolderStatus = .resolving
            }
            scheduleReconciliation(afterNanoseconds: 0)
        } catch {
            if captureFolderURL != nil {
                folderStatus = .inaccessible
            }
            if systemScreenshotFolderURL != nil {
                systemScreenshotFolderStatus = .inaccessible
            }
            logger.error("Capture source monitoring could not be started")
        }
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        reconciliationTask?.cancel()
        reconciliationTask = nil
        systemMetadataRetryTask?.cancel()
        systemMetadataRetryTask = nil
        cancelPendingLoads()
        folderMonitor.stop()
        folderAccessManager.relinquishAccess()
        isScanning = false
        updateReconcilingState()
    }

    public func setCaptureFolder(_ url: URL) async throws {
        let previousFolderURL = captureFolderURL
        reconciliationTask?.cancel()
        systemMetadataRetryTask?.cancel()
        cancelPendingLoads()
        folderMonitor.stop()

        folderStatus = .resolving
        do {
            let resolution = try folderAccessManager.authorize(url)
            isStarted = true
            captureFolderURL = resolution.url.standardizedFileURL
            folderStatus = .available
            try reconfigureSources(
                resetLibrary: true,
                resettingBaselines: Set(activeSources.map(\.identity))
            )
            await performReconciliation()
            guard folderStatus == .available else {
                throw CaptureLibraryError.initialReconciliationFailed
            }
        } catch FolderAccessError.notDirectory {
            restorePreviousFolderIfPossible(previousFolderURL)
            throw FolderAccessError.notDirectory
        } catch FolderAccessError.unreadableDirectory {
            restorePreviousFolderIfPossible(previousFolderURL)
            throw FolderAccessError.unreadableDirectory
        } catch {
            restorePreviousFolderIfPossible(previousFolderURL)
            throw error
        }
    }

    public func setSystemScreenshotFolder(_ url: URL?) async {
        let standardizedURL = url?.standardizedFileURL
        guard standardizedURL != systemScreenshotFolderURL else {
            if isStarted {
                await performReconciliation()
            }
            return
        }

        let previousURL = systemScreenshotFolderURL
        let previousBaselines = completedBaselineSources
        let previousStatus = systemScreenshotFolderStatus
        systemScreenshotFolderURL = standardizedURL
        systemScreenshotFolderStatus = standardizedURL == nil
            ? .notConfigured
            : .resolving

        let newSystemIdentity = standardizedURL.map {
            SourceIdentity(kind: .systemScreenshots, folderURL: $0)
        }

        do {
            try reconfigureSources(
                resetLibrary: false,
                resettingBaselines: Set([newSystemIdentity].compactMap { $0 })
            )
            if isStarted {
                await performReconciliation()
            }
            logger.info("System screenshot source updated")
        } catch {
            systemScreenshotFolderURL = previousURL
            completedBaselineSources = previousBaselines
            systemScreenshotFolderStatus = previousStatus
            try? reconfigureSources(
                resetLibrary: false,
                resettingBaselines: []
            )
            logger.error("System screenshot source could not be monitored")
        }
    }

    public func forgetCaptureFolder() {
        reconciliationTask?.cancel()
        reconciliationTask = nil
        systemMetadataRetryTask?.cancel()
        systemMetadataRetryTask = nil
        cancelPendingLoads()
        folderMonitor.stop()
        folderAccessManager.forgetFolder()
        captureFolderURL = nil
        folderStatus = .notConfigured

        do {
            try reconfigureSources(
                resetLibrary: systemScreenshotFolderURL == nil,
                resettingBaselines: []
            )
            scheduleReconciliation(afterNanoseconds: 0)
        } catch {
            logger.error("Remaining screenshot source could not be monitored")
        }
    }

    public func rescan() {
        scheduleReconciliation(afterNanoseconds: 0)
    }

    public func rebuildIndex() {
        reconciliationTask?.cancel()
        systemMetadataRetryTask?.cancel()
        cancelPendingLoads()
        folderGeneration = UUID()
        items = []
        selectedIDs = []
        selectionAnchorID = nil
        completedBaselineSources.removeAll()
        Task {
            await thumbnailService.removeAll()
        }
        scheduleReconciliation(afterNanoseconds: 0)
        logger.info("Capture index rebuild requested")
    }

    public func selectOnly(_ id: CaptureItem.ID) {
        guard items.contains(where: { $0.id == id }) else { return }
        selectedIDs = [id]
        selectionAnchorID = id
    }

    public func toggleSelection(_ id: CaptureItem.ID) {
        guard items.contains(where: { $0.id == id }) else { return }
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        selectionAnchorID = id
    }

    public func selectRange(to id: CaptureItem.ID) {
        guard let destinationIndex = items.firstIndex(where: { $0.id == id }) else { return }
        guard let anchorID = selectionAnchorID,
              let anchorIndex = items.firstIndex(where: { $0.id == anchorID })
        else {
            selectOnly(id)
            return
        }

        let bounds = min(anchorIndex, destinationIndex)...max(anchorIndex, destinationIndex)
        selectedIDs.formUnion(bounds.map { items[$0].id })
    }

    public func selectAll() {
        selectedIDs = Set(items.map(\.id))
        selectionAnchorID = items.first?.id
    }

    public func clearSelection() {
        selectedIDs = []
        selectionAnchorID = nil
    }

    private func reconfigureSources(
        resetLibrary: Bool,
        resettingBaselines sourceIDs: Set<SourceIdentity>
    ) throws {
        folderGeneration = UUID()
        reconciliationTask?.cancel()
        systemMetadataRetryTask?.cancel()
        systemMetadataRetryTask = nil
        cancelPendingLoads()
        folderMonitor.stop()

        let sources = activeSources
        let activeSourceIDs = Set(sources.map(\.identity))
        completedBaselineSources.formIntersection(activeSourceIDs)
        completedBaselineSources.subtract(sourceIDs)
        if resetLibrary {
            items = []
            selectedIDs = []
            selectionAnchorID = nil
        }

        guard isStarted, !sources.isEmpty else { return }

        try folderMonitor.start(monitoring: sources.map { $0.identity.folderURL }) { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleReconciliation(afterNanoseconds: 250_000_000)
                self?.scheduleSystemMetadataRetries()
            }
        }
        logger.info(
            "Capture sources installed: \(sources.count, privacy: .public)"
        )
    }

    private func restorePreviousFolderIfPossible(_ previousURL: URL?) {
        guard let previousURL else {
            captureFolderURL = nil
            folderStatus = .needsReselection
            try? reconfigureSources(
                resetLibrary: false,
                resettingBaselines: []
            )
            scheduleReconciliation(afterNanoseconds: 0)
            return
        }

        do {
            _ = try folderAccessManager.authorize(previousURL)
            captureFolderURL = previousURL.standardizedFileURL
            folderStatus = .available
            try reconfigureSources(
                resetLibrary: false,
                resettingBaselines: Set(activeSources
                    .filter { $0.identity.kind == .primary }
                    .map(\.identity))
            )
            scheduleReconciliation(afterNanoseconds: 0)
            logger.info("Previous capture folder restored after selection failure")
        } catch {
            captureFolderURL = nil
            folderStatus = .inaccessible
            try? reconfigureSources(
                resetLibrary: false,
                resettingBaselines: []
            )
            logger.error("Previous capture folder could not be restored")
        }
    }

    private var activeSources: [CaptureSource] {
        var sources: [CaptureSource] = []
        if let captureFolderURL {
            sources.append(CaptureSource(
                identity: SourceIdentity(
                    kind: .primary,
                    folderURL: captureFolderURL.standardizedFileURL
                ),
                filter: .supportedMedia
            ))
        }
        if let systemScreenshotFolderURL {
            sources.append(CaptureSource(
                identity: SourceIdentity(
                    kind: .systemScreenshots,
                    folderURL: systemScreenshotFolderURL.standardizedFileURL
                ),
                filter: .macOSScreenCapturesOnly
            ))
        }
        return sources
    }

    private func scheduleReconciliation(afterNanoseconds delay: UInt64) {
        guard isStarted, !activeSources.isEmpty else { return }
        reconciliationTask?.cancel()
        reconciliationTask = Task { [weak self] in
            do {
                if delay > 0 {
                    try await Task.sleep(nanoseconds: delay)
                }
                try Task.checkCancellation()
                await self?.performReconciliation()
            } catch {
                // A newer filesystem event superseded this scan.
            }
        }
    }

    private func scheduleSystemMetadataRetries() {
        guard isStarted, systemScreenshotFolderURL != nil else { return }
        systemMetadataRetryTask?.cancel()
        systemMetadataRetryTask = Task { [weak self] in
            do {
                // Spotlight attributes normally arrive with the file, but indexing can
                // lag the first FSEvent. Two bounded follow-up scans avoid losing that
                // capture without continuously polling the user's Desktop.
                for delay in [1_000_000_000, 2_000_000_000] as [UInt64] {
                    try await Task.sleep(nanoseconds: delay)
                    try Task.checkCancellation()
                    self?.scheduleReconciliation(afterNanoseconds: 0)
                }
            } catch {
                // A newer filesystem event or source configuration superseded retries.
            }
        }
    }

    private func performReconciliation() async {
        let sources = activeSources
        guard !sources.isEmpty else { return }
        let generation = folderGeneration
        isScanning = true
        updateReconcilingState()
        defer {
            isScanning = false
            updateReconcilingState()
        }

        do {
            let groups = Dictionary(grouping: sources) {
                $0.identity.folderURL.standardizedFileURL
            }
            var recordsByIdentity: [CandidateIdentity: CandidateRecord] = [:]
            var successfulSourceIDs: Set<SourceIdentity> = []
            var scanHadFailure = false
            var primaryScanFailed = false
            var systemScanFailed = false

            for folderURL in groups.keys.sorted(by: { $0.path < $1.path }) {
                guard let groupSources = groups[folderURL] else { continue }
                let includesPrimary = groupSources.contains {
                    $0.identity.kind == .primary
                }
                let includesSystemScreenshots = groupSources.contains {
                    $0.identity.kind == .systemScreenshots
                }
                let filter: CaptureFileFilter = groupSources.contains {
                    if case .supportedMedia = $0.filter { return true }
                    return false
                } ? .supportedMedia : .macOSScreenCapturesOnly

                do {
                    let folderCandidates = try await metadataLoader.supportedFiles(
                        in: folderURL,
                        filter: filter
                    )
                    try Task.checkCancellation()
                    guard generation == folderGeneration else { return }

                    let sourceIDs = Set(groupSources.map(\.identity))
                    let priority = includesPrimary ? 0 : 1
                    successfulSourceIDs.formUnion(sourceIDs)

                    for candidate in folderCandidates {
                        let identity = candidate.fileResourceIdentifier
                            .map(CandidateIdentity.resource)
                            ?? .url(candidate.url.standardizedFileURL)

                        if var existing = recordsByIdentity[identity] {
                            existing.sourceIDs.formUnion(sourceIDs)
                            let existingPath = existing.candidate.url.standardizedFileURL.path
                            let candidatePath = candidate.url.standardizedFileURL.path
                            if priority < existing.priority
                                || (priority == existing.priority && candidatePath < existingPath)
                            {
                                existing.candidate = candidate
                                existing.priority = priority
                            }
                            recordsByIdentity[identity] = existing
                        } else {
                            recordsByIdentity[identity] = CandidateRecord(
                                candidate: candidate,
                                sourceIDs: sourceIDs,
                                priority: priority
                            )
                        }
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    scanHadFailure = true
                    if includesPrimary {
                        primaryScanFailed = true
                    }
                    if includesSystemScreenshots {
                        systemScanFailed = true
                    }
                    logger.error("Capture source reconciliation failed")
                }
            }

            try Task.checkCancellation()
            guard generation == folderGeneration else { return }

            let records = recordsByIdentity.values.sorted {
                $0.candidate.url.standardizedFileURL.path
                    < $1.candidate.url.standardizedFileURL.path
            }
            let candidates = records.map(\.candidate)

            let currentURLs = Set(candidates.map { $0.url.standardizedFileURL })
            let candidateResourceIdentifiers = Set(
                candidates.compactMap(\.fileResourceIdentifier)
            )

            if !scanHadFailure {
                let removedItems = items.filter {
                    guard !currentURLs.contains($0.fileURL.standardizedFileURL) else {
                        return false
                    }
                    guard let resourceIdentifier = $0.fileResourceIdentifier else {
                        return true
                    }
                    return !candidateResourceIdentifiers.contains(resourceIdentifier)
                }
                let removedIDs = Set(removedItems.map(\.id))
                if !removedIDs.isEmpty {
                    items.removeAll { removedIDs.contains($0.id) }
                    selectedIDs.subtract(removedIDs)
                    if let selectionAnchorID, removedIDs.contains(selectionAnchorID) {
                        self.selectionAnchorID = nil
                    }
                }
            }

            if !scanHadFailure {
                let stalePendingURLs = pendingLoads.keys.filter { !currentURLs.contains($0) }
                for pendingURL in stalePendingURLs {
                    pendingLoads[pendingURL]?.task.cancel()
                    pendingLoads[pendingURL] = nil
                    dirtyPendingURLs.remove(pendingURL)
                }
            }

            let existingByURL = Dictionary(
                uniqueKeysWithValues: items.map { ($0.fileURL.standardizedFileURL, $0) }
            )
            var existingByResourceIdentifier: [Data: CaptureItem] = [:]
            for item in items {
                guard let resourceIdentifier = item.fileResourceIdentifier else { continue }
                existingByResourceIdentifier[resourceIdentifier] = item
            }
            for record in records {
                let candidate = record.candidate
                let url = candidate.url.standardizedFileURL
                guard pendingLoads[url] == nil else {
                    dirtyPendingURLs.insert(url)
                    continue
                }

                let existingItem = existingByURL[url]
                    ?? candidate.fileResourceIdentifier.flatMap {
                        existingByResourceIdentifier[$0]
                    }

                if let existingItem {
                    let changed = existingItem.fileURL.standardizedFileURL != url
                        || existingItem.fileSize != candidate.snapshot.fileSize
                        || existingItem.modifiedAt != candidate.snapshot.modifiedAt
                    if changed {
                        scheduleMetadataLoad(
                            candidate,
                            preserving: existingItem,
                            notifyWhenReady: false,
                            generation: generation
                        )
                    }
                } else {
                    let shouldNotifyForNewFile = record.sourceIDs.contains {
                        completedBaselineSources.contains($0)
                    }
                    scheduleMetadataLoad(
                        candidate,
                        preserving: nil,
                        notifyWhenReady: shouldNotifyForNewFile,
                        generation: generation
                    )
                }
            }

            completedBaselineSources.formUnion(successfulSourceIDs)
            if captureFolderURL != nil {
                folderStatus = primaryScanFailed ? .inaccessible : .available
            }
            if systemScreenshotFolderURL != nil {
                systemScreenshotFolderStatus = systemScanFailed
                    ? .inaccessible
                    : .available
            } else {
                systemScreenshotFolderStatus = .notConfigured
            }
            logger.info(
                "Capture sources reconciled; supported items: \(candidates.count, privacy: .public)"
            )
        } catch is CancellationError {
            // A newer scan or folder replaced this one.
        } catch {
            guard generation == folderGeneration else { return }
            if captureFolderURL != nil {
                folderStatus = .inaccessible
            }
            if systemScreenshotFolderURL != nil {
                systemScreenshotFolderStatus = .inaccessible
            }
            logger.error("Capture source reconciliation failed")
        }

    }

    private func scheduleMetadataLoad(
        _ candidate: CaptureFileCandidate,
        preserving existingItem: CaptureItem?,
        notifyWhenReady: Bool,
        generation: UUID
    ) {
        let url = candidate.url.standardizedFileURL
        let loadID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }

            do {
                let item = try await metadataLoader.loadMetadata(
                    for: candidate,
                    preservingID: existingItem?.id,
                    isPinned: existingItem?.isPinned ?? false
                )
                try Task.checkCancellation()

                // Prime Quick Look before announcing a finalized capture. Thumbnail failure
                // should not hide an otherwise valid file from the shelf.
                _ = try? await thumbnailService.thumbnail(for: item)
                try Task.checkCancellation()

                guard generation == folderGeneration,
                      !activeSources.isEmpty,
                      FileManager.default.fileExists(atPath: item.fileURL.path)
                else {
                    finishMetadataLoad(url: url, loadID: loadID)
                    return
                }

                if let index = items.firstIndex(where: {
                    $0.id == item.id || $0.fileURL.standardizedFileURL == url
                }) {
                    items[index] = item
                } else {
                    items.append(item)
                }
                items.sort(by: CaptureGrouping.newestFirst)
                selectedIDs.formIntersection(Set(items.map(\.id)))

                finishMetadataLoad(url: url, loadID: loadID)
                if notifyWhenReady, existingItem == nil {
                    logger.info("New capture finalized")
                    onNewCapture?(item)
                }
            } catch is CancellationError {
                finishMetadataLoad(url: url, loadID: loadID)
            } catch {
                finishMetadataLoad(url: url, loadID: loadID)
                logger.error("Capture metadata loading failed")
            }
        }

        pendingLoads[url] = PendingLoad(id: loadID, task: task)
        updateReconcilingState()
    }

    private func finishMetadataLoad(url: URL, loadID: UUID) {
        guard pendingLoads[url]?.id == loadID else { return }
        pendingLoads[url] = nil
        let needsFollowUpReconciliation = dirtyPendingURLs.remove(url) != nil
        updateReconcilingState()
        if needsFollowUpReconciliation {
            // FSEvents can arrive while the URL is already pending. The scan
            // marks it dirty so a late write cannot leave stale metadata.
            scheduleReconciliation(afterNanoseconds: 0)
        }
    }

    private func cancelPendingLoads() {
        pendingLoads.values.forEach { $0.task.cancel() }
        pendingLoads.removeAll()
        dirtyPendingURLs.removeAll()
        updateReconcilingState()
    }

    private func updateReconcilingState() {
        isReconciling = isScanning || !pendingLoads.isEmpty
    }
}
