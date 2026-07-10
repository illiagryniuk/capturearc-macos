import SwiftUI

struct MenuBarView: View {
    let captureCount: Int
    let runtimeStatus: String
    let onOpenShelf: () -> Void
    let onOpenSettings: () -> Void
    let onOpenFolder: () -> Void
    let onQuit: () -> Void

    init(
        captureCount: Int = 0,
        runtimeStatus: String = "Ready to watch",
        onOpenShelf: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenFolder: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.captureCount = captureCount
        self.runtimeStatus = runtimeStatus
        self.onOpenShelf = onOpenShelf
        self.onOpenSettings = onOpenSettings
        self.onOpenFolder = onOpenFolder
        self.onQuit = onQuit
    }

    var body: some View {
        Group {
            Text(shortMenuLabel(runtimeStatus))
                .accessibilityLabel("CaptureArc status: \(runtimeStatus)")

            Text(captureCountLabel)
                .accessibilityLabel("\(captureCount) captures in the shelf")

            Divider()

            Button(action: onOpenShelf) {
                Label("Open Shelf", systemImage: "rectangle.topthird.inset.filled")
            }
            .help("Open the CaptureArc screenshot shelf")
            .accessibilityLabel("Open CaptureArc shelf")

            Button(action: onOpenFolder) {
                Label("Open Capture Folder", systemImage: "folder")
            }
            .help("Reveal the capture folder in Finder")
            .accessibilityLabel("Open capture folder in Finder")

            Button(action: onOpenSettings) {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",")
            .help("Open CaptureArc settings")
            .accessibilityLabel("Open CaptureArc settings")

            Divider()

            Button(action: onQuit) {
                Label("Quit CaptureArc", systemImage: "power")
            }
            .keyboardShortcut("q")
            .help("Quit CaptureArc")
        }
    }

    private var captureCountLabel: String {
        captureCount == 1 ? "1 capture" : "\(captureCount) captures"
    }

    private func shortMenuLabel(_ label: String) -> String {
        let singleLine = label
            .split(whereSeparator: { $0.isNewline })
            .joined(separator: " ")

        guard singleLine.count > 30 else {
            return singleLine
        }

        return String(singleLine.prefix(27)) + "…"
    }
}
