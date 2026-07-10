import AppKit
import OSLog
import SwiftUI

@MainActor
final class NotchPanelController {
    private let library: CaptureLibrary
    private let panel: NotchShelfPanel
    private let presentation: NotchPanelPresentation
    private let actions: CaptureActions
    private let hostingView: NSHostingView<NotchPanelRootView>
    private let arrivalAnimator: CaptureArrivalAnimator
    private var hoverMonitor: HoverMonitor!
    private var geometry: NotchGeometry?
    private var previousFrontmostApplication: NSRunningApplication?
    private var isStarted = false

    init(library: CaptureLibrary) {
        self.library = library
        panel = NotchShelfPanel()
        presentation = NotchPanelPresentation()
        actions = CaptureActions(library: library)
        arrivalAnimator = CaptureArrivalAnimator()

        let rootView = NotchPanelRootView(
            library: library,
            actions: actions,
            presentation: presentation
        )
        hostingView = NSHostingView(rootView: rootView)
        // The panel owns its exact geometry. NSHostingView's default intrinsic
        // sizing would otherwise clamp the compact notch-wrap surface to the
        // shelf content's minimum size.
        hostingView.sizingOptions = []

        let contentContainer = NSView(frame: .zero)
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.frame = contentContainer.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentContainer.addSubview(hostingView)
        panel.contentView = contentContainer
        panel.contentMinSize = .zero
        panel.minSize = .zero
        actions.setSharingAnchorView(hostingView)
        panel.onCancelOperation = { [weak self] in
            self?.collapse()
        }
        presentation.onRequestClose = { [weak self] in
            self?.collapse()
        }
        presentation.onRequestOpen = { [weak self] in
            self?.show(expanded: true)
        }
        arrivalAnimator.onArrivalPulse = { [weak presentation] in
            presentation?.pulse()
        }

        hoverMonitor = HoverMonitor(
            geometryProvider: { location in
                NotchGeometry.resolve(at: location)
            },
            panelFrameProvider: { [weak panel] in
                guard panel?.isVisible == true else { return nil }
                return panel?.frame
            },
            openDelay: { Self.hoverDelay },
            onOpen: { [weak self] in
                self?.show(expanded: true)
            },
            onClose: { [weak self] in
                self?.collapse()
            },
            onScreenParametersChanged: { [weak self] in
                self?.refreshGeometry()
            },
            closeSuspensionProvider: { [weak actions] in
                actions?.hasVisibleTransientUI == true
            }
        )
        actions.onTransientUIVisibilityChanged = { [weak self] isVisible in
            self?.hoverMonitor.setCloseSuspended(isVisible)
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        actions.setSharingAnchorView(hostingView)
        refreshGeometry()
        show(expanded: false)
        hoverMonitor.start()
        panelLogger.info("Notch shelf panel controller started")
    }

    func stop() {
        guard isStarted else { return }
        hoverMonitor.stop()
        arrivalAnimator.cancelAll()
        actions.tearDown()
        panel.orderOut(nil)
        presentation.isExpanded = false
        isStarted = false
        panelLogger.info("Notch shelf panel controller stopped")
    }

    func show(expanded: Bool = true) {
        if geometry == nil || expanded {
            refreshGeometry(updatePanelFrame: false)
        }
        guard let geometry else { return }

        if expanded, !presentation.isExpanded {
            let current = NSWorkspace.shared.frontmostApplication
            if current?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previousFrontmostApplication = current
            }
        }

        presentation.contentTopInset = geometry.contentTopInset
        presentation.hasPhysicalNotch = geometry.hasPhysicalNotch
        presentation.notchCutoutSize = geometry.notchCutoutSize
        presentation.isExpanded = expanded
        hoverMonitor.setPanelExpanded(expanded)

        let targetFrame = expanded
            ? geometry.expandedPanelRect
            : geometry.collapsedPanelRect
        transitionPanel(to: targetFrame, animated: panel.isVisible)

        if !panel.isVisible {
            panel.orderFrontRegardless()
        } else {
            panel.orderFront(nil)
        }

        panelLogger.info(
            "Notch shelf shown in \(expanded ? "expanded" : "collapsed", privacy: .public) state"
        )
    }

    func collapse() {
        guard panel.isVisible else { return }
        show(expanded: false)
        restorePreviousApplicationIfNeeded()
    }

    func toggle() {
        show(expanded: !presentation.isExpanded)
    }

    func handleNewCapture(_ item: CaptureItem) {
        if geometry == nil {
            refreshGeometry(updatePanelFrame: false)
        }
        guard let geometry else {
            presentation.pulse()
            return
        }

        if !panel.isVisible {
            show(expanded: false)
        }

        let shouldAnimate = UserDefaults.standard.object(
            forKey: PreferenceKeys.animateNewCaptures
        ) as? Bool ?? true
        guard shouldAnimate else {
            presentation.pulse()
            return
        }

        arrivalAnimator.animate(
            item,
            to: geometry.arrivalTargetRect,
            on: NotchGeometry.screen(for: geometry.displayID)
        )
        panelLogger.info("New capture arrival animation requested")
    }

    func refreshGeometry() {
        refreshGeometry(updatePanelFrame: true)
    }

    private func refreshGeometry(updatePanelFrame: Bool) {
        guard let resolved = NotchGeometry.resolve(at: NSEvent.mouseLocation) else {
            return
        }
        geometry = resolved
        presentation.contentTopInset = resolved.contentTopInset
        presentation.hasPhysicalNotch = resolved.hasPhysicalNotch
        presentation.notchCutoutSize = resolved.notchCutoutSize

        guard updatePanelFrame, panel.isVisible else { return }
        let target = presentation.isExpanded
            ? resolved.expandedPanelRect
            : resolved.collapsedPanelRect
        panel.setFrame(target, display: true)
        panelLogger.debug("Notch shelf geometry refreshed")
    }

    private func transitionPanel(to frame: CGRect, animated: Bool) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated, !reduceMotion else {
            panel.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = presentation.isExpanded ? 0.19 : 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func restorePreviousApplicationIfNeeded() {
        guard let previousFrontmostApplication else { return }
        self.previousFrontmostApplication = nil

        let current = NSWorkspace.shared.frontmostApplication
        guard current?.processIdentifier == ProcessInfo.processInfo.processIdentifier else {
            return
        }
        previousFrontmostApplication.activate(options: [])
    }

    private static var hoverDelay: TimeInterval {
        let milliseconds = UserDefaults.standard.double(
            forKey: PreferenceKeys.hoverDelayMilliseconds
        )
        return min(max(milliseconds > 0 ? milliseconds : 200, 100), 800) / 1_000
    }
}

@MainActor
private final class NotchShelfPanel: NSPanel {
    var onCancelOperation: () -> Void = {}

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // The SwiftUI compound surface owns its shaped shadow. A window-level
        // shadow would haze the transparent camera cutout as one rectangle.
        hasShadow = false
        level = .statusBar
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        contentMinSize = .zero
        minSize = .zero
        acceptsMouseMovedEvents = true
        animationBehavior = .utilityWindow
        title = "CaptureArc Screenshot Shelf"
        setAccessibilityLabel("CaptureArc Screenshot Shelf")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The shelf is intentionally anchored inside the menu-bar / safe-area
    /// region. AppKit's default constraint would push it below that region.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            makeKey()
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancelOperation()
    }
}

@MainActor
private final class NotchPanelPresentation: ObservableObject {
    @Published var isExpanded = false
    @Published var contentTopInset: CGFloat = 28
    @Published var hasPhysicalNotch = false
    @Published var notchCutoutSize: CGSize = .zero
    @Published var isPulsing = false
    var onRequestOpen: () -> Void = {}
    var onRequestClose: () -> Void = {}

    private var pulseReset: DispatchWorkItem?

    func pulse() {
        pulseReset?.cancel()
        isPulsing = false
        DispatchQueue.main.async { [weak self] in
            self?.isPulsing = true
        }

        let reset = DispatchWorkItem { [weak self] in
            self?.isPulsing = false
        }
        pulseReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52, execute: reset)
    }
}

private struct NotchPanelRootView: View {
    @ObservedObject var library: CaptureLibrary
    @ObservedObject var actions: CaptureActions
    @ObservedObject var presentation: NotchPanelPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var collapsedControlFocused: Bool

    var body: some View {
        ZStack {
            if presentation.isExpanded {
                surface

                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: presentation.contentTopInset)
                        .accessibilityHidden(true)
                    CaptureShelfView(
                        library: library,
                        actions: actions,
                        onRequestClose: presentation.onRequestClose
                    )
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: outerCornerRadius,
                        style: .continuous
                    )
                )

                expandedWingStatus
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                notchBridge
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

            } else {
                idleRim
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                collapsedIndicator
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { focusRing }
        .preferredColorScheme(.dark)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.26, dampingFraction: 0.88),
            value: presentation.isExpanded
        )
        .animation(.easeOut(duration: reduceMotion ? 0.16 : 0.48), value: presentation.isPulsing)
    }

    private var outerCornerRadius: CGFloat {
        presentation.isExpanded
            ? NotchShelfTheme.expandedCornerRadius
            : NotchShelfTheme.collapsedCornerRadius
    }

    private var surfaceShape: NotchShelfSurfaceShape {
        NotchShelfSurfaceShape(
            cutoutSize: presentation.notchCutoutSize,
            outerCornerRadius: outerCornerRadius,
            hasPhysicalNotch: presentation.notchCutoutSize.width > 0
                && presentation.notchCutoutSize.height > 0
        )
    }

    private var idleRimShape: NotchShelfIdleRimShape {
        NotchShelfIdleRimShape(
            cutoutSize: presentation.notchCutoutSize,
            hasPhysicalNotch: presentation.hasPhysicalNotch
        )
    }

    private var idleRim: some View {
        ZStack {
            if !reduceTransparency {
                idleRimShape
                    .stroke(
                        NotchShelfTheme.accentGradient,
                        style: StrokeStyle(
                            lineWidth: presentation.isPulsing ? 5 : 3,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .blur(radius: presentation.isPulsing ? 4 : 2.5)
                    .opacity(presentation.isPulsing ? 0.54 : 0.25)
            }

            idleRimShape
                .stroke(
                    NotchShelfTheme.accentGradient,
                    style: StrokeStyle(
                        lineWidth: presentation.isPulsing
                            ? 2.2
                            : (reduceTransparency ? 1.7 : 1.35),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            idleRimShape
                .stroke(
                    Color.white.opacity(reduceTransparency ? 0.42 : 0.20),
                    style: StrokeStyle(
                        lineWidth: 0.55,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
        }
    }

    private var surface: some View {
        ZStack {
            surfaceShape
                .fill(.ultraThinMaterial, style: NotchShelfTheme.evenOddFill)
                .shadow(
                    color: .black.opacity(presentation.isExpanded ? 0.44 : 0.28),
                    radius: presentation.isExpanded ? 24 : 10,
                    y: presentation.isExpanded ? 8 : 4
                )

            surfaceShape
                .fill(NotchShelfTheme.spatialTint, style: NotchShelfTheme.evenOddFill)

            surfaceShape
                .fill(
                    NotchShelfTheme.accentWash(
                        opacity: presentation.isExpanded ? 0.07 : 0.22
                    ),
                    style: NotchShelfTheme.evenOddFill
                )

            if reduceTransparency {
                surfaceShape
                    .fill(
                        Color.black.opacity(0.34),
                        style: NotchShelfTheme.evenOddFill
                    )
            }

            accentStroke(lineWidth: presentation.isPulsing ? 2.4 : 1.15)
                .opacity(presentation.isPulsing ? 0.98 : 0.76)

            accentStroke(lineWidth: presentation.isPulsing ? 6 : 3)
                .blur(radius: presentation.isPulsing ? 8 : 5)
                .opacity(presentation.isPulsing ? 0.50 : 0.20)
                .blendMode(.plusLighter)
        }
        .scaleEffect(
            presentation.isPulsing && !reduceMotion ? 1.012 : 1
        )
    }

    private func accentStroke(lineWidth: CGFloat) -> some View {
        surfaceShape
            .stroke(NotchShelfTheme.accentGradient, lineWidth: lineWidth)
            .mask(
                surfaceShape.fill(
                    Color.white,
                    style: NotchShelfTheme.evenOddFill
                )
            )
    }

    private var expandedWingStatus: some View {
        GeometryReader { proxy in
            let cutoutWidth = presentation.hasPhysicalNotch
                ? min(presentation.notchCutoutSize.width, proxy.size.width)
                : 0
            let wingWidth = max(0, (proxy.size.width - cutoutWidth) / 2)
            let statusHeight = max(
                28,
                min(presentation.contentTopInset, presentation.notchCutoutSize.height)
            )

            HStack(spacing: 0) {
                Label("CaptureArc", systemImage: "camera.viewfinder")
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                    .padding(.leading, 18)
                    .frame(width: wingWidth, alignment: .leading)

                Color.clear
                    .frame(width: cutoutWidth)

                Label(
                    library.isReconciling ? "Scanning" : "Watching",
                    systemImage: library.isReconciling
                        ? "arrow.triangle.2.circlepath"
                        : "checkmark.circle"
                )
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.trailing, 18)
                .frame(width: wingWidth, alignment: .trailing)
            }
            .frame(width: proxy.size.width, height: statusHeight, alignment: .top)
        }
    }

    @ViewBuilder
    private var notchBridge: some View {
        if presentation.hasPhysicalNotch {
            GeometryReader { proxy in
                let gap = max(
                    0,
                    presentation.contentTopInset - presentation.notchCutoutSize.height
                )

                VStack(spacing: 1) {
                    Capsule(style: .continuous)
                        .fill(NotchShelfTheme.accentGradient)
                        .frame(width: 64, height: 2)
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .position(
                    x: proxy.size.width / 2,
                    y: presentation.notchCutoutSize.height + gap / 2
                )
            }
        }
    }

    private var collapsedIndicator: some View {
        Button(action: presentation.onRequestOpen) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .focused($collapsedControlFocused)
        .accessibilityLabel("Open Capture Shelf, \(captureCountDescription)")
        .accessibilityHint("Shows recent screenshots and screen recordings")
    }

    @ViewBuilder
    private var focusRing: some View {
        if collapsedControlFocused && !presentation.isExpanded {
            idleRimShape
                .stroke(
                    Color.white.opacity(0.94),
                    style: StrokeStyle(
                        lineWidth: 2.6,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
        }
    }

    private var captureCountDescription: String {
        library.items.count == 1 ? "1 capture" : "\(library.items.count) captures"
    }
}

private let panelLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.illiagryniuk.capturearc",
    category: "NotchPanel"
)
