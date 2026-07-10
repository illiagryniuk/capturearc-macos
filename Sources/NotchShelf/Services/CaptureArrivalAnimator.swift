import AppKit
import QuartzCore
import OSLog

enum CaptureArrivalTiming {
    static let movementStartDelay: TimeInterval = 0
    static let sourceHaloStartDelay: TimeInterval = 0
    static let reducedMotionStartDelay: TimeInterval = 0
    static let flightDuration: TimeInterval = 0.64
    static let positionDuration: TimeInterval = 0.48
    static let sourceHaloDuration: TimeInterval = 0.19
    static let reducedMotionDuration: TimeInterval = 0.28
}

@MainActor
final class CaptureArrivalAnimator {
    var onArrivalPulse: (() -> Void)?

    private struct ActiveAnimation {
        let panel: NSPanel
        let completionDelegate: ArrivalAnimationCompletionDelegate
    }

    private let thumbnailService: ThumbnailService
    private var activeAnimations: [UUID: ActiveAnimation] = [:]
    private var activeOrder: [UUID] = []
    private var thumbnailTasks: [UUID: Task<Void, Never>] = [:]
    private var thumbnailTaskOrder: [UUID] = []
    private let maximumConcurrentArrivals = 3

    init(thumbnailService: ThumbnailService = .shared) {
        self.thumbnailService = thumbnailService
    }

    func animate(_ item: CaptureItem, to targetRect: CGRect, on screen: NSScreen?) {
        guard let destinationScreen = resolvedScreen(for: targetRect, preferred: screen) else {
            arrivalLogger.error("Capture arrival skipped because no display was available")
            onArrivalPulse?()
            return
        }

        let identifier = UUID()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let thumbnailService = self.thumbnailService

        makeRoomForThumbnailTask()
        let task = Task { [weak self] in
            defer {
                self?.thumbnailTasks[identifier] = nil
                self?.thumbnailTaskOrder.removeAll { $0 == identifier }
            }
            do {
                let image = try await thumbnailService.thumbnail(
                    for: item,
                    size: CGSize(width: 180, height: 120),
                    scale: destinationScreen.backingScaleFactor
                )
                guard !Task.isCancelled, let self else { return }
                guard let cgImage = self.cgImage(from: image) else {
                    self.emitFallbackPulse()
                    return
                }

                if reduceMotion {
                    self.showReducedMotionFade(
                        cgImage,
                        identifier: identifier,
                        targetRect: targetRect,
                        screen: destinationScreen
                    )
                } else {
                    self.showFlight(
                        cgImage,
                        identifier: identifier,
                        targetRect: targetRect,
                        screen: destinationScreen
                    )
                }
            } catch is CancellationError {
                arrivalLogger.debug("Capture arrival thumbnail request was cancelled")
            } catch {
                self?.emitFallbackPulse()
            }
        }
        thumbnailTasks[identifier] = task
        thumbnailTaskOrder.append(identifier)
    }

    func cancelAll() {
        thumbnailTasks.values.forEach { $0.cancel() }
        thumbnailTasks.removeAll()
        thumbnailTaskOrder.removeAll()

        for activeAnimation in activeAnimations.values {
            activeAnimation.panel.orderOut(nil)
            activeAnimation.panel.close()
        }
        activeAnimations.removeAll()
        activeOrder.removeAll()
        arrivalLogger.debug("Capture arrival work cancelled")
    }

    private func showFlight(
        _ image: CGImage,
        identifier: UUID,
        targetRect: CGRect,
        screen: NSScreen
    ) {
        let panel = makeOverlayPanel(on: screen)
        guard let rootLayer = panel.contentView?.layer else {
            emitFallbackPulse()
            return
        }

        let destinationRect = normalizedTargetRect(targetRect, on: screen)
        let thumbnailSize = fittedThumbnailSize(for: image, maximum: CGSize(width: 180, height: 120))
        let sourceRect = CGRect(
            x: screen.visibleFrame.maxX - thumbnailSize.width - 28,
            y: screen.visibleFrame.minY + 28,
            width: thumbnailSize.width,
            height: thumbnailSize.height
        )
        let start = localPoint(sourceRect.center, on: screen)
        let destination = localPoint(destinationRect.center, on: screen)

        let thumbnailLayer = makeThumbnailLayer(image: image, size: thumbnailSize, on: screen)
        thumbnailLayer.position = start
        thumbnailLayer.shadowColor = NSColor(
            calibratedRed: 0.39,
            green: 0.40,
            blue: 0.95,
            alpha: 1
        ).cgColor
        thumbnailLayer.shadowOffset = .zero
        thumbnailLayer.shadowRadius = 22
        thumbnailLayer.shadowOpacity = 0.42
        rootLayer.addSublayer(thumbnailLayer)

        // A quick cyan/indigo outline marks the end of the system thumbnail and
        // the beginning of CaptureArc's motion. It is deliberately brief so the
        // screenshot itself remains the only persistent moving element.
        let handoffLayer = makeHandoffLayer(size: thumbnailSize, on: screen)
        handoffLayer.position = start
        rootLayer.insertSublayer(handoffLayer, below: thumbnailLayer)

        let handoffOpacity = CAKeyframeAnimation(keyPath: "opacity")
        handoffOpacity.values = [0.42, 0.86, 0.0]
        handoffOpacity.keyTimes = [0, 0.30, 1]

        let handoffScale = CAKeyframeAnimation(keyPath: "transform.scale")
        handoffScale.values = [0.96, 1.0, 1.10]
        handoffScale.keyTimes = [0, 0.30, 1]

        let handoff = CAAnimationGroup()
        handoff.animations = [handoffOpacity, handoffScale]
        handoff.beginTime = CaptureArrivalTiming.sourceHaloStartDelay
        handoff.duration = CaptureArrivalTiming.sourceHaloDuration
        handoff.timingFunction = CAMediaTimingFunction(name: .easeOut)
        handoffLayer.add(handoff, forKey: "capture-handoff")

        let position = CAKeyframeAnimation(keyPath: "position")
        let path = CGMutablePath()
        path.move(to: start)

        let verticalDistance = destination.y - start.y
        let horizontalDistance = start.x - destination.x
        path.addCurve(
            to: destination,
            control1: CGPoint(
                x: start.x - horizontalDistance * 0.08,
                y: start.y + verticalDistance * 0.42
            ),
            control2: CGPoint(
                x: destination.x + horizontalDistance * 0.34,
                y: destination.y - max(32, abs(verticalDistance) * 0.12)
            )
        )
        position.path = path
        position.calculationMode = .cubic
        position.beginTime = CaptureArrivalTiming.movementStartDelay
        position.duration = CaptureArrivalTiming.positionDuration
        position.fillMode = .both
        position.isRemovedOnCompletion = false

        let finalScale = destinationScale(for: destinationRect, thumbnailSize: thumbnailSize)
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.94, 1.0, finalScale]
        scale.keyTimes = [0, 0.18, 1]

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0.94, 1.0, 1.0, 0.0]
        opacity.keyTimes = [0, 0.12, 0.82, 1]

        let shadowOpacity = CAKeyframeAnimation(keyPath: "shadowOpacity")
        shadowOpacity.values = [0.0, 0.48, 0.32, 0.0]
        shadowOpacity.keyTimes = [0, 0.20, 0.70, 1]

        let shadowRadius = CAKeyframeAnimation(keyPath: "shadowRadius")
        shadowRadius.values = [12, 24, 8, 2]
        shadowRadius.keyTimes = [0, 0.24, 0.76, 1]

        let animation = CAAnimationGroup()
        animation.animations = [position, scale, opacity, shadowOpacity, shadowRadius]
        animation.duration = CaptureArrivalTiming.flightDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        thumbnailLayer.position = destination
        thumbnailLayer.transform = CATransform3DMakeScale(finalScale, finalScale, 1)
        thumbnailLayer.opacity = 0
        CATransaction.commit()

        panel.orderFrontRegardless()
        run(
            animation,
            on: thumbnailLayer,
            in: panel,
            identifier: identifier,
            pulsesOnStart: false,
            pulsesOnCompletion: true
        )
        arrivalLogger.info("Capture arrival flight started immediately from the system thumbnail edge")
    }

    private func showReducedMotionFade(
        _ image: CGImage,
        identifier: UUID,
        targetRect: CGRect,
        screen: NSScreen
    ) {
        let panel = makeOverlayPanel(on: screen)
        guard let rootLayer = panel.contentView?.layer else {
            emitFallbackPulse()
            return
        }

        let destinationRect = normalizedTargetRect(targetRect, on: screen)
        let maximumSize = CGSize(
            width: min(96, max(64, destinationRect.width * 0.58)),
            height: 60
        )
        let thumbnailSize = fittedThumbnailSize(for: image, maximum: maximumSize)
        let thumbnailLayer = makeThumbnailLayer(image: image, size: thumbnailSize, on: screen)
        thumbnailLayer.position = localPoint(
            CGPoint(
                x: destinationRect.midX,
                y: max(screen.frame.minY + thumbnailSize.height / 2 + 8,
                       destinationRect.minY - thumbnailSize.height / 2 - 8)
            ),
            on: screen
        )
        thumbnailLayer.opacity = 0
        rootLayer.addSublayer(thumbnailLayer)

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0.0, 0.82, 0.0]
        opacity.keyTimes = [0, 0.35, 1]

        let animation = CAAnimationGroup()
        animation.animations = [opacity]
        animation.beginTime = CaptureArrivalTiming.reducedMotionStartDelay
        animation.duration = CaptureArrivalTiming.reducedMotionDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        panel.orderFrontRegardless()
        run(
            animation,
            on: thumbnailLayer,
            in: panel,
            identifier: identifier,
            pulsesOnStart: true,
            pulsesOnCompletion: false
        )
        arrivalLogger.info("Capture arrival used the reduced-motion fade")
    }

    private func run(
        _ animation: CAAnimation,
        on layer: CALayer,
        in panel: NSPanel,
        identifier: UUID,
        pulsesOnStart: Bool,
        pulsesOnCompletion: Bool
    ) {
        makeRoomForActiveAnimation()
        let completionDelegate = ArrivalAnimationCompletionDelegate { [weak self] in
            self?.finishAnimation(identifier, shouldPulse: pulsesOnCompletion)
        }
        activeAnimations[identifier] = ActiveAnimation(
            panel: panel,
            completionDelegate: completionDelegate
        )
        activeOrder.append(identifier)
        animation.delegate = completionDelegate
        layer.add(animation, forKey: "capture-arrival")

        if pulsesOnStart {
            onArrivalPulse?()
        }
    }

    private func finishAnimation(_ identifier: UUID, shouldPulse: Bool) {
        guard let activeAnimation = activeAnimations.removeValue(forKey: identifier) else {
            return
        }
        activeOrder.removeAll { $0 == identifier }

        activeAnimation.panel.orderOut(nil)
        activeAnimation.panel.close()
        if shouldPulse {
            onArrivalPulse?()
        }
    }

    private func emitFallbackPulse() {
        arrivalLogger.error("Capture thumbnail was unavailable; emitting arrival pulse only")
        onArrivalPulse?()
    }

    private func makeRoomForThumbnailTask() {
        while thumbnailTaskOrder.count >= maximumConcurrentArrivals,
              let oldest = thumbnailTaskOrder.first {
            thumbnailTaskOrder.removeFirst()
            thumbnailTasks.removeValue(forKey: oldest)?.cancel()
        }
    }

    private func makeRoomForActiveAnimation() {
        while activeOrder.count >= maximumConcurrentArrivals,
              let oldest = activeOrder.first {
            activeOrder.removeFirst()
            guard let animation = activeAnimations.removeValue(forKey: oldest) else {
                continue
            }
            animation.panel.orderOut(nil)
            animation.panel.close()
        }
    }

    private func makeOverlayPanel(on screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.setFrame(screen.frame, display: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let overlayView = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        overlayView.autoresizingMask = [.width, .height]
        overlayView.wantsLayer = true
        overlayView.layer = CALayer()
        overlayView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = overlayView
        return panel
    }

    private func makeThumbnailLayer(
        image: CGImage,
        size: CGSize,
        on screen: NSScreen
    ) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.contents = image
        layer.contentsGravity = .resizeAspectFill
        layer.contentsScale = screen.backingScaleFactor
        layer.cornerRadius = min(12, min(size.width, size.height) * 0.12)
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.borderWidth = 1
        layer.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        return layer
    }

    private func makeHandoffLayer(size: CGSize, on screen: NSScreen) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.contentsScale = screen.backingScaleFactor
        layer.cornerRadius = min(14, min(size.width, size.height) * 0.14)
        layer.cornerCurve = .continuous
        layer.borderWidth = 2
        layer.borderColor = NSColor(
            calibratedRed: 0.13,
            green: 0.82,
            blue: 0.93,
            alpha: 0.92
        ).cgColor
        layer.shadowColor = NSColor(
            calibratedRed: 0.49,
            green: 0.23,
            blue: 0.93,
            alpha: 1
        ).cgColor
        layer.shadowOffset = .zero
        layer.shadowRadius = 20
        layer.shadowOpacity = 0.58
        layer.opacity = 0
        return layer
    }

    private func resolvedScreen(for targetRect: CGRect, preferred screen: NSScreen?) -> NSScreen? {
        if let screen {
            return screen
        }

        if !targetRect.isNull, !targetRect.isEmpty,
           let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(targetRect.center) }) {
            return targetScreen
        }

        return NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func normalizedTargetRect(_ targetRect: CGRect, on screen: NSScreen) -> CGRect {
        if !targetRect.isNull, !targetRect.isEmpty {
            let intersection = targetRect.intersection(screen.frame)
            if !intersection.isNull, !intersection.isEmpty {
                return intersection
            }
        }

        return CGRect(
            x: screen.frame.midX - 32,
            y: screen.frame.maxY - 24,
            width: 64,
            height: 20
        )
    }

    private func localPoint(_ point: CGPoint, on screen: NSScreen) -> CGPoint {
        CGPoint(x: point.x - screen.frame.minX, y: point.y - screen.frame.minY)
    }

    private func fittedThumbnailSize(for image: CGImage, maximum: CGSize) -> CGSize {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0 else {
            return maximum
        }

        let scale = min(maximum.width / imageSize.width, maximum.height / imageSize.height)
        return CGSize(
            width: max(1, imageSize.width * scale),
            height: max(1, imageSize.height * scale)
        )
    }

    private func destinationScale(for destinationRect: CGRect, thumbnailSize: CGSize) -> CGFloat {
        let widthScale = destinationRect.width / thumbnailSize.width
        let heightScale = destinationRect.height / thumbnailSize.height
        return max(0.08, min(0.32, min(widthScale, heightScale)))
    }

    private func cgImage(from image: NSImage) -> CGImage? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}

private final class ArrivalAnimationCompletionDelegate:
    NSObject,
    CAAnimationDelegate,
    @unchecked Sendable
{
    private let completion: @MainActor @Sendable () -> Void

    init(completion: @escaping @MainActor @Sendable () -> Void) {
        self.completion = completion
    }

    func animationDidStop(_ animation: CAAnimation, finished flag: Bool) {
        let completion = completion
        Task { @MainActor in
            completion()
        }
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private let arrivalLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.illiagryniuk.capturearc",
    category: "CaptureArrival"
)
