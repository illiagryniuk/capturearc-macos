import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    init<Content: View>(rootView: Content) {
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)

        window.title = "Welcome to CaptureArc"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.animationBehavior = .documentWindow
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 680, height: 700))
        window.contentMinSize = NSSize(width: 620, height: 620)
        window.contentMaxSize = NSSize(width: 820, height: 900)
        window.center()

        super.init(window: window)
        shouldCascadeWindows = false
    }

    convenience init(
        captureFolderURL: URL,
        captureCount: Int = 0,
        runtimeStatus: String = "Ready to watch",
        requiresExplicitCaptureFolderAuthorization: Bool = false,
        onChooseFolder: @escaping () -> Void,
        onRevealFolder: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.init(
            rootView: OnboardingView(
                captureFolderURL: captureFolderURL,
                captureCount: captureCount,
                runtimeStatus: runtimeStatus,
                requiresExplicitCaptureFolderAuthorization:
                    requiresExplicitCaptureFolderAuthorization,
                onChooseFolder: onChooseFolder,
                onRevealFolder: onRevealFolder,
                onComplete: onComplete
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }

        NSApplication.shared.activate(ignoringOtherApps: true)
        if !window.isVisible {
            window.center()
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
