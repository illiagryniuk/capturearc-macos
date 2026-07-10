import AppKit
import CoreGraphics
import OSLog

/// Geometry for the shelf on one display, expressed in AppKit's global screen
/// coordinate space (origin at the bottom-left of the primary display).
struct NotchGeometry {
    static let defaultExpandedSize = CGSize(width: 680, height: 438)

    /// The physical camera housing remains untouched. The collapsed window is
    /// deliberately larger than the visible idle rim so hover and click remain
    /// forgiving; pixels away from the rim are transparent.
    static let notchShoulderWidth: CGFloat = 44
    static let notchBottomBridgeHeight: CGFloat = 18
    static let notchCutoutClearance: CGFloat = 2

    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let visibleFrame: CGRect
    let physicalNotchRect: CGRect?
    let collapsedPanelRect: CGRect
    let triggerRect: CGRect
    let expandedPanelRect: CGRect
    let contentTopInset: CGFloat
    let notchCutoutSize: CGSize

    var hasPhysicalNotch: Bool { physicalNotchRect != nil }
    var arrivalTargetRect: CGRect { physicalNotchRect ?? collapsedPanelRect }

    @MainActor
    static func resolve(
        at point: CGPoint = NSEvent.mouseLocation,
        preferredDisplayID: CGDirectDisplayID? = nil,
        expandedSize: CGSize = defaultExpandedSize
    ) -> NotchGeometry? {
        guard let screen = screen(
            containing: point,
            preferredDisplayID: preferredDisplayID
        ) else {
            geometryLogger.error("Unable to resolve a display for the notch shelf")
            return nil
        }

        return NotchGeometry(screen: screen, expandedSize: expandedSize)
    }

    @MainActor
    init(screen: NSScreen, expandedSize: CGSize = defaultExpandedSize) {
        let frame = screen.frame
        let safeAreaInsets = screen.safeAreaInsets
        let notch = Self.physicalNotchRect(
            screenFrame: frame,
            safeAreaInsets: safeAreaInsets,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        )

        displayID = Self.displayID(for: screen)
        screenFrame = frame
        visibleFrame = screen.visibleFrame
        physicalNotchRect = notch

        let layout = Self.panelLayout(
            screenFrame: frame,
            physicalNotchRect: notch,
            expandedSize: expandedSize
        )
        collapsedPanelRect = layout.collapsedPanelRect
        triggerRect = layout.triggerRect
        expandedPanelRect = layout.expandedPanelRect
        contentTopInset = layout.contentTopInset
        notchCutoutSize = layout.notchCutoutSize
    }

    struct PanelLayout: Equatable {
        let collapsedPanelRect: CGRect
        let triggerRect: CGRect
        let expandedPanelRect: CGRect
        let contentTopInset: CGFloat
        let notchCutoutSize: CGSize
    }

    /// Pure layout helper used by both the live NSScreen path and tests. The
    /// top edge always remains aligned with the selected display, including
    /// displays whose global origin is not zero.
    static func panelLayout(
        screenFrame: CGRect,
        physicalNotchRect: CGRect?,
        expandedSize: CGSize = defaultExpandedSize
    ) -> PanelLayout {
        let collapsedPanelRect: CGRect
        let triggerRect: CGRect
        let contentTopInset: CGFloat
        let notchCutoutSize: CGSize

        if let notch = physicalNotchRect {
            let collapsedWidth = min(
                notch.width + notchShoulderWidth * 2,
                max(1, screenFrame.width - 8)
            )
            let collapsedHeight = min(
                notch.height + notchBottomBridgeHeight,
                screenFrame.height
            )
            let collapsed = CGRect(
                x: notch.midX - collapsedWidth / 2,
                y: screenFrame.maxY - collapsedHeight,
                width: collapsedWidth,
                height: collapsedHeight
            )

            collapsedPanelRect = clampPosition(collapsed, to: screenFrame).integral
            notchCutoutSize = CGSize(
                width: min(
                    collapsedPanelRect.width,
                    notch.width + notchCutoutClearance * 2
                ),
                height: min(
                    collapsedPanelRect.height,
                    notch.height + notchCutoutClearance
                )
            )
            contentTopInset = collapsedPanelRect.height
            triggerRect = clamp(
                collapsedPanelRect.insetBy(dx: -10, dy: -10),
                to: screenFrame
            )
        } else {
            let pillSize = CGSize(width: 188, height: 30)
            let pill = CGRect(
                x: screenFrame.midX - pillSize.width / 2,
                y: screenFrame.maxY - pillSize.height,
                width: min(pillSize.width, screenFrame.width),
                height: min(pillSize.height, screenFrame.height)
            )

            collapsedPanelRect = clampPosition(pill, to: screenFrame).integral
            notchCutoutSize = .zero
            contentTopInset = collapsedPanelRect.height
            triggerRect = clamp(
                collapsedPanelRect.insetBy(dx: -18, dy: -12),
                to: screenFrame
            )
        }

        let width = min(max(420, expandedSize.width), max(1, screenFrame.width - 24))
        let height = min(max(260, expandedSize.height), max(1, screenFrame.height - 24))
        let proposedX = collapsedPanelRect.midX - width / 2
        let x = min(
            max(screenFrame.minX + 12, proposedX),
            screenFrame.maxX - width - 12
        )
        let expandedPanelRect = CGRect(
            x: x,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        ).integral

        return PanelLayout(
            collapsedPanelRect: collapsedPanelRect,
            triggerRect: triggerRect,
            expandedPanelRect: expandedPanelRect,
            contentTopInset: contentTopInset,
            notchCutoutSize: notchCutoutSize
        )
    }

    /// Pure geometry helper kept separate so notch detection can be verified
    /// without depending on the machine running the tests.
    static func physicalNotchRect(
        screenFrame: CGRect,
        safeAreaInsets: NSEdgeInsets,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?
    ) -> CGRect? {
        guard safeAreaInsets.top > 0,
              let leftArea = auxiliaryTopLeftArea,
              let rightArea = auxiliaryTopRightArea else {
            return nil
        }

        let minX = leftArea.maxX
        let maxX = rightArea.minX
        let bottom = max(
            screenFrame.maxY - safeAreaInsets.top,
            min(leftArea.minY, rightArea.minY)
        )
        let candidate = CGRect(
            x: minX,
            y: bottom,
            width: maxX - minX,
            height: screenFrame.maxY - bottom
        )

        // A gap between the two auxiliary top areas is the reliable signal for
        // a camera housing. The bounds also reject malformed display metadata.
        guard candidate.width >= 40,
              candidate.height >= 12,
              candidate.maxX <= screenFrame.maxX + 1,
              candidate.minX >= screenFrame.minX - 1,
              candidate.maxY <= screenFrame.maxY + 1 else {
            return nil
        }

        return candidate.intersection(screenFrame).integral
    }

    @MainActor
    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { Self.displayID(for: $0) == displayID }
    }

    @MainActor
    private static func screen(
        containing point: CGPoint,
        preferredDisplayID: CGDirectDisplayID?
    ) -> NSScreen? {
        if let preferredDisplayID,
           let preferred = screen(for: preferredDisplayID) {
            return preferred
        }

        if let containing = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return containing
        }

        if let nearest = NSScreen.screens.min(by: {
            squaredDistance(from: point, to: $0.frame)
                < squaredDistance(from: point, to: $1.frame)
        }) {
            return nearest
        }

        return NSScreen.main
    }

    @MainActor
    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) } ?? 0
    }

    private static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        rect.intersection(bounds)
    }

    private static func clampPosition(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

private let geometryLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.illiagryniuk.capturearc",
    category: "NotchGeometry"
)
