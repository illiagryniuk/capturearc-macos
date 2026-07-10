import AppKit
import SwiftUI

struct OnboardingView: View {
    static let defaultCaptureFolderURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures", isDirectory: true)
        .appendingPathComponent("CaptureArc Captures", isDirectory: true)

    let captureFolderURL: URL
    let captureCount: Int
    let runtimeStatus: String
    let requiresExplicitCaptureFolderAuthorization: Bool
    let onChooseFolder: () -> Void
    let onRevealFolder: () -> Void
    let onComplete: () -> Void

    init(
        captureFolderURL: URL = Self.defaultCaptureFolderURL,
        captureCount: Int = 0,
        runtimeStatus: String = "Ready to watch",
        requiresExplicitCaptureFolderAuthorization: Bool = false,
        onChooseFolder: @escaping () -> Void,
        onRevealFolder: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.captureFolderURL = captureFolderURL
        self.captureCount = captureCount
        self.runtimeStatus = runtimeStatus
        self.requiresExplicitCaptureFolderAuthorization =
            requiresExplicitCaptureFolderAuthorization
        self.onChooseFolder = onChooseFolder
        self.onRevealFolder = onRevealFolder
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    folderCard
                    screenshotSetupCard
                    privacyCard
                }
                .padding(28)
            }

            Divider()

            HStack(spacing: 12) {
                Button(
                    requiresExplicitCaptureFolderAuthorization && !canFinishSetup
                        ? "Choose Capture Folder…"
                        : "Show Capture Folder",
                    action: onRevealFolder
                )
                    .help("Reveal the selected capture folder in Finder")
                    .accessibilityLabel("Show capture folder in Finder")

                Spacer()

                Button(primaryActionTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .help(primaryActionHelp)
                    .accessibilityLabel(primaryActionHelp)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .background(.bar)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 620, idealHeight: 700)
        .background(.regularMaterial)
    }

    private var canFinishSetup: Bool {
        runtimeStatus.localizedCaseInsensitiveContains("watching")
    }

    private var primaryActionTitle: String {
        if canFinishSetup {
            return "Finish Setup"
        }
        return requiresExplicitCaptureFolderAuthorization
            ? "Authorize Capture Folder…"
            : "Choose Fallback Folder…"
    }

    private var primaryActionHelp: String {
        canFinishSetup
            ? "Finish CaptureArc setup"
            : (requiresExplicitCaptureFolderAuthorization
                ? "Authorize a capture folder before finishing setup"
                : "Choose a fallback folder before finishing setup")
    }

    private func primaryAction() {
        if canFinishSetup {
            onComplete()
        } else {
            onChooseFolder()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                Text("Welcome to CaptureArc")
                    .font(.largeTitle.weight(.semibold))

                Text(headerDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var folderCard: some View {
        OnboardingCard(
            title: requiresExplicitCaptureFolderAuthorization
                ? "1. Authorize your capture folder"
                : "1. Choose a fallback folder",
            systemImage: "folder.fill"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(folderDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(captureFolderURL.lastPathComponent)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        Text(captureFolderURL.path(percentEncoded: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 8)

                    Button("Choose…", action: onChooseFolder)
                        .help("Select a different folder for captures")
                        .accessibilityLabel("Choose a different capture folder")
                }
                .padding(12)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: 8) {
                    Image(systemName: "wave.3.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(runtimeStatus)
                        .lineLimit(2)
                    Spacer()
                    Text(captureCount == 1 ? "1 capture" : "\(captureCount) captures")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Status: \(runtimeStatus). \(captureCount) captures found.")
            }
        }
    }

    private var screenshotSetupCard: some View {
        OnboardingCard(
            title: requiresExplicitCaptureFolderAuthorization
                ? "2. Point Screenshot to CaptureArc"
                : "2. Point Screenshot here only if needed",
            systemImage: "camera.viewfinder"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingStep(number: 1, text: "Press Shift–Command–5.")
                OnboardingStep(number: 2, text: "Open Options.")
                OnboardingStep(number: 3, text: "Under Save to, choose Other Location…")
                OnboardingStep(number: 4, text: "Select \(captureFolderURL.lastPathComponent).")

                Divider()

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text(screenshotSetupDescription)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var privacyCard: some View {
        OnboardingCard(
            title: "Private by design",
            systemImage: "hand.raised.fill"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Label("No Screen Recording permission", systemImage: "checkmark.circle.fill")
                Label("No Accessibility permission", systemImage: "checkmark.circle.fill")
                Label("No Full Disk Access", systemImage: "checkmark.circle.fill")

                Text(privacyDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .symbolRenderingMode(.hierarchical)
            .accessibilityElement(children: .combine)
        }
    }

    private var headerDescription: String {
        if requiresExplicitCaptureFolderAuthorization {
            return "CaptureArc keeps screenshots local. App Store security requires you to approve the one folder it watches."
        }
        return "CaptureArc normally follows the macOS screenshot folder automatically. If that location is unavailable, choose a fallback folder here."
    }

    private var folderDescription: String {
        if requiresExplicitCaptureFolderAuthorization {
            return "Choose or create a folder such as ~/Pictures/CaptureArc Captures. CaptureArc stores a secure bookmark so access survives restarts."
        }
        return "The recommended fallback is ~/Pictures/CaptureArc Captures. CaptureArc will watch it in addition to the normal macOS Screenshot destination."
    }

    private var screenshotSetupDescription: String {
        if requiresExplicitCaptureFolderAuthorization {
            return "Keep Show Floating Thumbnail enabled if you like. After macOS saves the file into your authorized folder, CaptureArc continues the motion into the notch."
        }
        return "You can keep Show Floating Thumbnail enabled. CaptureArc waits for Apple’s thumbnail to finish, then continues the handoff into the notch. Once macOS can use this destination, CaptureArc follows it automatically."
    }

    private var privacyDescription: String {
        if requiresExplicitCaptureFolderAuthorization {
            return "CaptureArc does not capture your screen. It reads only the folder you authorize, and your captures stay on your Mac."
        }
        return "CaptureArc does not capture your screen. It reads the current macOS Screenshot destination and any fallback folder you explicitly authorize; your captures stay on your Mac."
    }
}

private struct OnboardingCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct OnboardingStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.quaternary, in: Circle())
                .accessibilityHidden(true)

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }
}
