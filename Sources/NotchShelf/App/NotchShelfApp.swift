import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        AppRuntime.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppRuntime.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct NotchShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runtime = AppRuntime.shared

    var body: some Scene {
        MenuBarExtra("CaptureArc", systemImage: "photo.stack.fill") {
            MenuBarView(
                captureCount: runtime.captureCount,
                runtimeStatus: runtime.runtimeStatus,
                onOpenShelf: runtime.showShelf,
                onOpenSettings: runtime.openSettings,
                onOpenFolder: runtime.openCaptureFolder,
                onQuit: runtime.quit
            )
        }
        .menuBarExtraStyle(.menu)

        Settings {
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
}
