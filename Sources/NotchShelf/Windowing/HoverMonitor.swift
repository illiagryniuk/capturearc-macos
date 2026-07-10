@preconcurrency import AppKit
import OSLog

/// Combines global pointer observation (other apps) with local observation
/// (CaptureArc itself). Keyboard monitoring remains local so opening the shelf
/// never requires Accessibility permission.
@MainActor
final class HoverMonitor {
    typealias GeometryProvider = (_ pointerLocation: CGPoint) -> NotchGeometry?

    private let geometryProvider: GeometryProvider
    private let panelFrameProvider: () -> CGRect?
    private let openDelayProvider: () -> TimeInterval
    private let closeDelay: TimeInterval
    private let onOpen: () -> Void
    private let onClose: () -> Void
    private let onScreenParametersChanged: () -> Void
    private let closeSuspensionProvider: () -> Bool

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var applicationNotificationTokens: [NSObjectProtocol] = []
    private var workspaceNotificationTokens: [NSObjectProtocol] = []
    private var pendingOpen: DispatchWorkItem?
    private var pendingClose: DispatchWorkItem?
    private var isCloseSuspended = false
    private(set) var isPanelExpanded = false
    private(set) var isRunning = false

    init(
        geometryProvider: @escaping GeometryProvider,
        panelFrameProvider: @escaping () -> CGRect?,
        openDelay: @escaping () -> TimeInterval = { 0.20 },
        closeDelay: TimeInterval = 0.24,
        onOpen: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onScreenParametersChanged: @escaping () -> Void = {},
        closeSuspensionProvider: @escaping () -> Bool = { false }
    ) {
        self.geometryProvider = geometryProvider
        self.panelFrameProvider = panelFrameProvider
        openDelayProvider = openDelay
        self.closeDelay = closeDelay
        self.onOpen = onOpen
        self.onClose = onClose
        self.onScreenParametersChanged = onScreenParametersChanged
        self.closeSuspensionProvider = closeSuspensionProvider
    }

    deinit {
        MainActor.assumeIsolated {
            if let globalMonitor {
                NSEvent.removeMonitor(globalMonitor)
            }
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
            }
            applicationNotificationTokens.forEach {
                NotificationCenter.default.removeObserver($0)
            }
            workspaceNotificationTokens.forEach {
                NSWorkspace.shared.notificationCenter.removeObserver($0)
            }
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let pointerEvents: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: pointerEvents) { [weak self] event in
            Task { @MainActor in
                self?.handlePointerEvent(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: pointerEvents) { [weak self] event in
            guard let self else { return event }
            self.handlePointerEvent(event)
            return event
        }

        let center = NotificationCenter.default
        applicationNotificationTokens.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.closeImmediately(reason: "screen parameters changed")
                    self?.onScreenParametersChanged()
                }
            }
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ] {
            workspaceNotificationTokens.append(
                workspaceCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.closeImmediately(reason: name.rawValue)
                    }
                }
            )
        }

        hoverLogger.info("Hover monitoring started")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        cancelPendingTransitions()

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        applicationNotificationTokens.forEach {
            NotificationCenter.default.removeObserver($0)
        }
        applicationNotificationTokens.removeAll()
        workspaceNotificationTokens.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        workspaceNotificationTokens.removeAll()
        isPanelExpanded = false
        hoverLogger.info("Hover monitoring stopped")
    }

    func setPanelExpanded(_ expanded: Bool) {
        isPanelExpanded = expanded
        if expanded {
            pendingOpen?.cancel()
            pendingOpen = nil
        } else {
            pendingClose?.cancel()
            pendingClose = nil
        }
    }

    /// Keeps transient native UI (for example NSSharingServicePicker) usable
    /// after the pointer leaves the panel's bounds.
    func setCloseSuspended(_ suspended: Bool) {
        isCloseSuspended = suspended
        if suspended {
            pendingClose?.cancel()
            pendingClose = nil
            return
        }

        guard isPanelExpanded, !isCloseEffectivelySuspended else { return }
        let location = NSEvent.mouseLocation
        let insideTrigger = geometryProvider(location)?.triggerRect.contains(location) ?? false
        let insidePanel = panelFrameProvider()?.contains(location) ?? false
        if !insideTrigger, !insidePanel {
            scheduleClose()
        }
    }

    private func handlePointerEvent(_ event: NSEvent) {
        guard isRunning else { return }

        let location = NSEvent.mouseLocation
        guard let geometry = geometryProvider(location) else {
            if isPanelExpanded {
                scheduleClose()
            }
            return
        }

        let isClick = event.type == .leftMouseDown
            || event.type == .rightMouseDown
            || event.type == .otherMouseDown
        let isInsideTrigger = geometry.triggerRect.contains(location)
        let isInsidePanel = panelFrameProvider()?.contains(location) ?? false

        if isInsideTrigger || (isPanelExpanded && isInsidePanel) {
            pendingClose?.cancel()
            pendingClose = nil

            if isInsideTrigger && !isPanelExpanded {
                scheduleOpen()
            }
            return
        }

        pendingOpen?.cancel()
        pendingOpen = nil

        guard isPanelExpanded else { return }
        guard !isCloseEffectivelySuspended else { return }
        if isClick {
            closeImmediately(reason: "outside click")
        } else {
            scheduleClose()
        }
    }

    private func scheduleOpen() {
        guard pendingOpen == nil else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, !self.isPanelExpanded else { return }
            self.pendingOpen = nil

            let location = NSEvent.mouseLocation
            guard self.geometryProvider(location)?.triggerRect.contains(location) == true else {
                return
            }

            hoverLogger.debug("Notch hover delay elapsed; opening shelf")
            self.onOpen()
        }
        pendingOpen = work
        let delay = min(max(openDelayProvider(), 0.10), 0.80)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleClose() {
        guard pendingClose == nil, !isCloseEffectivelySuspended else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.isRunning,
                  self.isPanelExpanded,
                  !self.isCloseEffectivelySuspended else { return }
            self.pendingClose = nil

            let location = NSEvent.mouseLocation
            let triggerContainsPointer = self.geometryProvider(location)?
                .triggerRect.contains(location) ?? false
            let panelContainsPointer = self.panelFrameProvider()?.contains(location) ?? false
            guard !triggerContainsPointer, !panelContainsPointer else { return }

            hoverLogger.debug("Pointer left notch shelf; collapsing")
            self.closeImmediately(reason: "pointer exit")
        }
        pendingClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay, execute: work)
    }

    private func closeImmediately(reason: String) {
        cancelPendingTransitions()
        guard isPanelExpanded else { return }
        isPanelExpanded = false
        hoverLogger.debug("Closing notch shelf: \(reason, privacy: .public)")
        onClose()
    }

    private func cancelPendingTransitions() {
        pendingOpen?.cancel()
        pendingClose?.cancel()
        pendingOpen = nil
        pendingClose = nil
    }

    private var isCloseEffectivelySuspended: Bool {
        isCloseSuspended || closeSuspensionProvider()
    }
}

private let hoverLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.illiagryniuk.capturearc",
    category: "HoverMonitor"
)
