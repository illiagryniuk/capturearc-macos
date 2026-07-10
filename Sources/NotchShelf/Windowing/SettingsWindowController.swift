import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init<Content: View>(rootView: Content) {
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)

        window.title = "CaptureArc Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.tabbingMode = .disallowed
        window.animationBehavior = .utilityWindow
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 600, height: 650))
        window.contentMinSize = NSSize(width: 560, height: 545)
        window.center()

        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
