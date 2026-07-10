import AppKit
import Combine
import Darwin
import Foundation
import OSLog
import SwiftUI

@MainActor
final class AppRuntime: ObservableObject {
    static let shared = AppRuntime()

    let library: CaptureLibrary
    let launchAtLoginService: LaunchAtLoginService
    let distributionChannel = DistributionChannel.current

    @Published private(set) var captureCount = 0
    @Published private(set) var captureFolderURL: URL?
    @Published private(set) var systemScreenshotFolderURL: URL?
    @Published private(set) var runtimeStatus = "Connecting to macOS Screenshot…"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.illiagryniuk.capturearc",
        category: "Lifecycle"
    )
    private var cancellables = Set<AnyCancellable>()
    private var panelController: NotchPanelController?
    private var onboardingWindowController: OnboardingWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var hasStarted = false
    private var retentionTask: Task<Void, Never>?
    private var retentionWakeTask: Task<Void, Never>?
    private var sourceConfigurationTask: Task<Void, Never>?
    private var screenshotLocationPollingTask: Task<Void, Never>?
    private var managedCaptureKeys: Set<String>
    private let screenshotLocationResolver = ScreenshotLocationResolver()

    private init() {
        self.library = CaptureLibrary()
        self.launchAtLoginService = LaunchAtLoginService()
        self.managedCaptureKeys = Set(
            UserDefaults.standard.stringArray(forKey: PreferenceKeys.managedCaptureKeys) ?? []
        )

        UserDefaults.standard.register(defaults: [
            PreferenceKeys.hoverDelayMilliseconds: 200.0,
            PreferenceKeys.animateNewCaptures: true,
            PreferenceKeys.retentionPolicy: RetentionPolicy.indefinitely.rawValue
        ])

        bindLibrary()
    }

    var presentedCaptureFolderURL: URL {
        if distributionChannel.requiresExplicitCaptureFolderAuthorization {
            return captureFolderURL ?? recommendedCaptureFolderURL
        }
        return systemScreenshotFolderURL ?? captureFolderURL ?? recommendedCaptureFolderURL
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        let controller = NotchPanelController(library: library)
        panelController = controller
        controller.start()

        library.onNewCapture = { [weak self] item in
            self?.markCaptureAsManaged(item)
            self?.logger.info("Finalized capture added to shelf")
            self?.panelController?.handleNewCapture(item)
            self?.applyRetentionPolicyIfNeeded()
        }
        launchAtLoginService.refresh()
        sourceConfigurationTask = Task { [weak self] in
            guard let self else { return }

            if self.distributionChannel.requiresExplicitCaptureFolderAuthorization {
                // Mac App Store builds are sandboxed. They intentionally avoid
                // reading the system Screenshot destination until the person
                // explicitly authorizes a capture folder through NSOpenPanel.
                await self.library.setSystemScreenshotFolder(nil)
            } else {
                let screenshotFolderURL = self.screenshotLocationResolver.resolve()
                await self.library.setSystemScreenshotFolder(screenshotFolderURL)
            }
            guard !Task.isCancelled else { return }

            // Install both the optional extra folder and the actual macOS
            // screenshot destination in a single baseline pass. Existing files
            // appear on the shelf without pretending they are new arrivals.
            self.library.start()
            if !self.distributionChannel.requiresExplicitCaptureFolderAuthorization {
                self.startScreenshotLocationPolling()
            }
            self.refreshStatus()

            if self.distributionChannel.requiresExplicitCaptureFolderAuthorization,
               self.library.captureFolderURL == nil {
                self.showOnboarding()
            } else if self.library.captureFolderURL == nil,
                      self.library.systemScreenshotFolderURL == nil {
                self.showOnboarding()
            }
        }

        logger.info("CaptureArc runtime started")
    }

    func stop() {
        guard hasStarted else { return }
        library.stop()
        retentionTask?.cancel()
        retentionTask = nil
        retentionWakeTask?.cancel()
        retentionWakeTask = nil
        sourceConfigurationTask?.cancel()
        sourceConfigurationTask = nil
        screenshotLocationPollingTask?.cancel()
        screenshotLocationPollingTask = nil
        panelController?.stop()
        panelController = nil
        onboardingWindowController?.close()
        onboardingWindowController = nil
        settingsWindowController?.close()
        settingsWindowController = nil
        hasStarted = false
        logger.info("CaptureArc runtime stopped")
    }

    func showShelf() {
        panelController?.show(expanded: true)
    }

    func openCaptureFolder() {
        if distributionChannel.requiresExplicitCaptureFolderAuthorization,
           captureFolderURL == nil {
            chooseCaptureFolder()
            return
        }

        let url = systemScreenshotFolderURL
            ?? captureFolderURL
            ?? preparedRecommendedFolderURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
        logger.info("Active capture folder revealed")
    }

    func chooseCaptureFolder() {
        let panel = NSOpenPanel()
        if distributionChannel.requiresExplicitCaptureFolderAuthorization {
            panel.title = "Authorize Capture Folder"
            panel.message = "Choose the folder CaptureArc should watch. Afterward, select the same folder in Shift–Command–5 → Options → Save to."
            panel.prompt = "Authorize Folder"
        } else {
            panel.title = "Watch an Additional Folder"
            panel.message = "CaptureArc already watches the macOS Screenshot destination. Choose another folder only if you also keep captures elsewhere."
            panel.prompt = "Watch Folder"
        }
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = recommendedCaptureFolderURL.deletingLastPathComponent()
        panel.nameFieldStringValue = preparedRecommendedFolderURL.lastPathComponent

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }

            Task { @MainActor in
                do {
                    self.retentionTask?.cancel()
                    self.retentionWakeTask?.cancel()
                    try await self.library.setCaptureFolder(url)
                    self.onboardingWindowController?.close()
                    self.onboardingWindowController = nil
                    self.panelController?.refreshGeometry()
                    self.panelController?.show(expanded: true)
                    self.logger.info("Capture folder authorization selected")
                } catch {
                    self.refreshStatus()
                    self.showFolderError(error)
                    self.logger.error("Additional capture folder selection failed")
                }
            }
        }
    }

    func rescan() {
        runtimeStatus = "Scanning capture sources…"
        library.rescan()
    }

    func openSettings() {
        if let settingsWindowController {
            settingsWindowController.show()
            return
        }

        let controller = SettingsWindowController(
            rootView: RuntimeSettingsView(runtime: self)
        )
        settingsWindowController = controller
        controller.show()
        logger.info("Settings window opened")
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func bindLibrary() {
        library.$items
            .sink { [weak self] items in
                self?.captureCount = items.count
                self?.refreshStatus()
                self?.applyRetentionPolicyIfNeeded()
            }
            .store(in: &cancellables)

        library.$captureFolderURL
            .sink { [weak self] url in
                self?.retentionTask?.cancel()
                self?.retentionTask = nil
                self?.retentionWakeTask?.cancel()
                self?.retentionWakeTask = nil
                self?.captureFolderURL = url
                self?.refreshStatus()
            }
            .store(in: &cancellables)

        library.$systemScreenshotFolderURL
            .sink { [weak self] url in
                self?.retentionTask?.cancel()
                self?.retentionTask = nil
                self?.retentionWakeTask?.cancel()
                self?.retentionWakeTask = nil
                self?.systemScreenshotFolderURL = url
                self?.refreshStatus()
                self?.applyRetentionPolicyIfNeeded()
            }
            .store(in: &cancellables)

        library.$isReconciling
            .sink { [weak self] _ in
                self?.refreshStatus()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyRetentionPolicyIfNeeded()
            }
            .store(in: &cancellables)

        library.$folderStatus
            .sink { [weak self] _ in
                self?.refreshStatus()
            }
            .store(in: &cancellables)

        library.$systemScreenshotFolderStatus
            .sink { [weak self] _ in
                self?.refreshStatus()
            }
            .store(in: &cancellables)
    }

    private func refreshStatus() {
        guard hasStarted else {
            runtimeStatus = "Connecting to macOS Screenshot…"
            return
        }

        if library.isReconciling {
            runtimeStatus = "Scanning capture sources…"
            return
        }

        if distributionChannel.requiresExplicitCaptureFolderAuthorization {
            switch library.folderStatus {
            case .notConfigured:
                runtimeStatus = "Authorize a capture folder to continue"
            case .resolving:
                runtimeStatus = "Restoring folder access…"
            case .available:
                runtimeStatus = captureCount == 1
                    ? "Watching authorized folder • 1 capture"
                    : "Watching authorized folder • \(captureCount) captures"
            case .needsReselection:
                runtimeStatus = "Authorize the capture folder again"
            case .inaccessible:
                runtimeStatus = "Authorized capture folder unavailable"
            }
            return
        }

        if let systemScreenshotFolderURL {
            switch library.systemScreenshotFolderStatus {
            case .available:
                let folderName = systemScreenshotFolderURL.lastPathComponent.isEmpty
                    ? "macOS screenshots"
                    : systemScreenshotFolderURL.lastPathComponent
                runtimeStatus = captureCount == 1
                    ? "Watching \(folderName) • 1 capture"
                    : "Watching \(folderName) • \(captureCount) captures"
                return
            case .resolving:
                runtimeStatus = "Connecting to macOS Screenshot…"
                return
            case .needsReselection, .inaccessible:
                runtimeStatus = library.folderStatus == .available
                    ? "Screenshot folder unavailable • extra folder active"
                    : "macOS screenshot folder unavailable"
                return
            case .notConfigured:
                break
            }
        }

        switch library.folderStatus {
        case .notConfigured:
            runtimeStatus = "macOS screenshot folder unavailable"
        case .resolving:
            runtimeStatus = "Restoring folder access…"
        case .available:
            runtimeStatus = captureCount == 1
                ? "Watching • 1 capture"
                : "Watching • \(captureCount) captures"
        case .needsReselection:
            runtimeStatus = "Choose the additional folder again"
        case .inaccessible:
            runtimeStatus = "Capture sources unavailable"
        }
    }

    private func startScreenshotLocationPolling() {
        screenshotLocationPollingTask?.cancel()
        screenshotLocationPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                    guard let self, !Task.isCancelled else { return }

                    let resolvedURL = self.screenshotLocationResolver
                        .resolve()
                        .standardizedFileURL
                    guard resolvedURL
                        != self.library.systemScreenshotFolderURL?.standardizedFileURL
                    else {
                        continue
                    }

                    await self.library.setSystemScreenshotFolder(resolvedURL)
                    guard !Task.isCancelled else { return }
                    self.logger.info("macOS screenshot destination change detected")
                } catch is CancellationError {
                    return
                } catch {
                    self?.logger.error("Screenshot destination polling failed")
                }
            }
        }
    }

    private func showOnboarding() {
        if let onboardingWindowController {
            onboardingWindowController.show()
            return
        }

        let controller = OnboardingWindowController(
            captureFolderURL: presentedCaptureFolderURL,
            captureCount: captureCount,
            runtimeStatus: runtimeStatus,
            requiresExplicitCaptureFolderAuthorization:
                distributionChannel.requiresExplicitCaptureFolderAuthorization,
            onChooseFolder: { [weak self] in self?.chooseCaptureFolder() },
            onRevealFolder: { [weak self] in self?.openCaptureFolder() },
            onComplete: { [weak self] in
                self?.onboardingWindowController?.close()
                self?.onboardingWindowController = nil
            }
        )
        onboardingWindowController = controller
        controller.show()
        logger.info("Onboarding window opened")
    }

    private var recommendedCaptureFolderURL: URL {
        let picturesURL: URL
        if distributionChannel.requiresExplicitCaptureFolderAuthorization,
           let account = getpwuid(getuid()) {
            // FileManager's user directories resolve inside the sandbox
            // container. The system open panel can safely begin at the real
            // Pictures folder and grants access only after explicit approval.
            picturesURL = URL(
                fileURLWithPath: String(cString: account.pointee.pw_dir),
                isDirectory: true
            ).appendingPathComponent("Pictures", isDirectory: true)
        } else {
            picturesURL = FileManager.default.urls(
                for: .picturesDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures")
        }
        return picturesURL.appendingPathComponent("CaptureArc Captures", isDirectory: true)
    }

    private var preparedRecommendedFolderURL: URL {
        let url = recommendedCaptureFolderURL
        guard !distributionChannel.requiresExplicitCaptureFolderAuthorization else {
            // A sandboxed App Store build must not create folders in Pictures
            // before the person grants access through the system open panel.
            return url
        }
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        } catch {
            logger.debug("Recommended folder will be created through the open panel")
        }
        return url
    }

    private func showFolderError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "CaptureArc couldn’t use that folder"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func applyRetentionPolicyIfNeeded() {
        retentionTask?.cancel()
        retentionTask = nil
        retentionWakeTask?.cancel()
        retentionWakeTask = nil

        let sourceSignature = activeSourceSignature
        guard !sourceSignature.isEmpty,
            let rawPolicy = UserDefaults.standard.string(forKey: PreferenceKeys.retentionPolicy),
            let policy = RetentionPolicy(rawValue: rawPolicy),
            let ageLimit = policy.ageLimit
        else {
            return
        }

        let now = Date()
        let cutoff = now.addingTimeInterval(-ageLimit)
        let expiredItems = RetentionEligibility.expiredItems(
            in: library.items,
            managedCaptureKeys: managedCaptureKeys,
            cutoff: cutoff
        )

        guard !expiredItems.isEmpty else {
            let nextExpiration = library.items
                .filter {
                    managedCaptureKeys.contains($0.thumbnailCacheKey) && !$0.isPinned
                }
                .map { $0.createdAt.addingTimeInterval(ageLimit) }
                .filter { $0 > now }
                .min()

            if let nextExpiration {
                scheduleRetentionWake(
                    at: nextExpiration,
                    sourceSignature: sourceSignature,
                    policyRawValue: rawPolicy
                )
            }
            return
        }

        retentionTask = Task { [weak self] in
            guard let self else { return }
            var failureCount = 0
            var retiredKeys: Set<String> = []

            for item in expiredItems {
                guard !Task.isCancelled,
                    self.activeSourceSignature == sourceSignature,
                    UserDefaults.standard.string(forKey: PreferenceKeys.retentionPolicy) == rawPolicy
                else {
                    return
                }

                let succeeded = await Task.detached(priority: .utility) {
                    do {
                        var resultingURL: NSURL?
                        try FileManager.default.trashItem(
                            at: item.fileURL,
                            resultingItemURL: &resultingURL
                        )
                        return true
                    } catch {
                        return false
                    }
                }.value

                if !succeeded {
                    failureCount += 1
                } else {
                    retiredKeys.insert(item.thumbnailCacheKey)
                }
            }

            guard !Task.isCancelled,
                self.activeSourceSignature == sourceSignature
            else {
                return
            }

            self.retentionTask = nil
            if !retiredKeys.isEmpty {
                self.managedCaptureKeys.subtract(retiredKeys)
                self.persistManagedCaptureKeys()
                self.library.rescan()
            }
            if failureCount == 0 {
                self.logger.info("Automatic retention moved expired captures to Trash")
            } else {
                self.logger.error(
                    "Automatic retention completed with \(failureCount, privacy: .public) failure(s)"
                )
                self.scheduleRetentionWake(
                    at: Date().addingTimeInterval(60 * 60),
                    sourceSignature: sourceSignature,
                    policyRawValue: rawPolicy
                )
            }
        }
    }

    private func scheduleRetentionWake(
        at date: Date,
        sourceSignature: [URL],
        policyRawValue: String
    ) {
        retentionWakeTask?.cancel()
        let delay = min(max(1, date.timeIntervalSinceNow), 365 * 24 * 60 * 60)
        let nanoseconds = UInt64(delay * 1_000_000_000)

        retentionWakeTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
                guard let self,
                    !Task.isCancelled,
                    self.activeSourceSignature == sourceSignature,
                    UserDefaults.standard.string(forKey: PreferenceKeys.retentionPolicy) == policyRawValue
                else {
                    return
                }
                self.retentionWakeTask = nil
                self.applyRetentionPolicyIfNeeded()
            } catch {
                // Policy, folder, or app lifecycle changes cancel this wake-up.
            }
        }
    }

    private var activeSourceSignature: [URL] {
        [captureFolderURL, systemScreenshotFolderURL]
            .compactMap { $0?.standardizedFileURL }
            .reduce(into: Set<URL>()) { $0.insert($1) }
            .sorted { $0.path < $1.path }
    }

    private func markCaptureAsManaged(_ item: CaptureItem) {
        managedCaptureKeys.insert(item.thumbnailCacheKey)
        persistManagedCaptureKeys()
    }

    private func persistManagedCaptureKeys() {
        UserDefaults.standard.set(
            Array(managedCaptureKeys).sorted(),
            forKey: PreferenceKeys.managedCaptureKeys
        )
    }
}

private struct RuntimeSettingsView: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        SettingsView(
            screenshotFolderURL: runtime.presentedCaptureFolderURL,
            additionalFolderURL: runtime.captureFolderURL,
            captureCount: runtime.captureCount,
            runtimeStatus: runtime.runtimeStatus,
            requiresExplicitCaptureFolderAuthorization:
                runtime.distributionChannel.requiresExplicitCaptureFolderAuthorization,
            launchAtLoginService: runtime.launchAtLoginService,
            onOpenFolder: runtime.openCaptureFolder,
            onReselectFolder: runtime.chooseCaptureFolder,
            onRescan: runtime.rescan
        )
    }
}
