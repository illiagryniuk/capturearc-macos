import SwiftUI

struct SettingsView: View {
    let screenshotFolderURL: URL
    let additionalFolderURL: URL?
    let captureCount: Int
    let runtimeStatus: String
    let requiresExplicitCaptureFolderAuthorization: Bool
    let launchAtLoginService: LaunchAtLoginService
    let onOpenFolder: () -> Void
    let onReselectFolder: () -> Void
    let onRescan: () -> Void

    @AppStorage(PreferenceKeys.hoverDelayMilliseconds)
    private var hoverDelayMilliseconds = 200.0

    @AppStorage(PreferenceKeys.animateNewCaptures)
    private var animateNewCaptures = true

    @AppStorage(PreferenceKeys.retentionPolicy)
    private var retentionPolicyRawValue = RetentionPolicy.indefinitely.rawValue

    init(
        screenshotFolderURL: URL,
        additionalFolderURL: URL? = nil,
        captureCount: Int = 0,
        runtimeStatus: String = "Ready to watch",
        requiresExplicitCaptureFolderAuthorization: Bool = false,
        launchAtLoginService: LaunchAtLoginService,
        onOpenFolder: @escaping () -> Void,
        onReselectFolder: @escaping () -> Void,
        onRescan: @escaping () -> Void
    ) {
        self.screenshotFolderURL = screenshotFolderURL
        self.additionalFolderURL = additionalFolderURL
        self.captureCount = captureCount
        self.runtimeStatus = runtimeStatus
        self.requiresExplicitCaptureFolderAuthorization =
            requiresExplicitCaptureFolderAuthorization
        self.launchAtLoginService = launchAtLoginService
        self.onOpenFolder = onOpenFolder
        self.onReselectFolder = onReselectFolder
        self.onRescan = onRescan
    }

    var body: some View {
        Form {
            captureFolderSection
            shelfSection
            retentionSection
            LaunchAtLoginSettingsSection(service: launchAtLoginService)
            privacySection
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 545)
        .accessibilityElement(children: .contain)
    }

    private var captureFolderSection: some View {
        Section("Capture Sources") {
            LabeledContent(
                requiresExplicitCaptureFolderAuthorization
                    ? "Capture Folder"
                    : "macOS Screenshot"
            ) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(displayPath(for: screenshotFolderURL))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)

                    Text(
                        requiresExplicitCaptureFolderAuthorization
                            ? "Authorized by you"
                            : "Watched automatically"
                    )
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    requiresExplicitCaptureFolderAuthorization
                        ? "Authorized capture folder: \(displayPath(for: screenshotFolderURL))."
                        : "macOS Screenshot folder: \(displayPath(for: screenshotFolderURL)). Watched automatically."
                )
            }

            if !requiresExplicitCaptureFolderAuthorization,
               let additionalFolderURL {
                LabeledContent("Additional Folder") {
                    Text(displayPath(for: additionalFolderURL))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                        .accessibilityLabel("Additional watched folder: \(displayPath(for: additionalFolderURL))")
                }
            }

            LabeledContent("Library") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(captureCount == 1 ? "1 capture" : "\(captureCount) captures")
                    Text(runtimeStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Library status: \(runtimeStatus). \(captureCount) captures.")
            }

            HStack {
                Button(openFolderButtonTitle, action: onOpenFolder)
                    .help(openFolderButtonHelp)
                    .accessibilityLabel(openFolderButtonHelp)

                Button(folderButtonTitle, action: onReselectFolder)
                    .help(folderButtonHelp)
                    .accessibilityLabel(folderButtonHelp)

                Spacer()

                Button("Rescan Now", action: onRescan)
                    .help("Rebuild the shelf from all active capture sources")
                    .accessibilityLabel("Rescan all capture sources now")
            }
        }
    }

    private var shelfSection: some View {
        Section("Shelf") {
            LabeledContent("Hover delay") {
                HStack(spacing: 10) {
                    Slider(
                        value: $hoverDelayMilliseconds,
                        in: 150...500,
                        step: 10
                    )
                    .frame(width: 190)
                    .accessibilityLabel("Shelf hover delay")
                    .accessibilityValue("\(Int(hoverDelayMilliseconds)) milliseconds")
                    .help("How long the pointer rests near the notch before the shelf opens")

                    Text("\(Int(hoverDelayMilliseconds)) ms")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                }
            }

            Toggle("Animate new captures into the notch", isOn: $animateNewCaptures)
                .help("Show a brief arrival animation when a capture is added")
                .accessibilityHint("Turns the new capture arrival animation on or off")
        }
    }

    private var retentionSection: some View {
        Section {
            Picker("Keep captures", selection: retentionPolicyBinding) {
                ForEach(RetentionPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .pickerStyle(.menu)
            .help("Choose when unpinned captures should be moved to the Trash")
            .accessibilityHint("CaptureArc uses this preference for automatic cleanup")

            Text("Automatic cleanup only applies to new captures CaptureArc observes after setup. Existing files are never auto-cleaned, and eligible files move to the Trash rather than being erased permanently.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Retention")
        }
    }

    private var privacySection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(privacyDescription)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text("Privacy")
        }
    }

    private var retentionPolicyBinding: Binding<RetentionPolicy> {
        Binding(
            get: {
                RetentionPolicy(rawValue: retentionPolicyRawValue) ?? .indefinitely
            },
            set: { policy in
                retentionPolicyRawValue = policy.rawValue
            }
        )
    }

    private var folderButtonTitle: String {
        if requiresExplicitCaptureFolderAuthorization {
            return "Change Capture Folder…"
        }
        return additionalFolderURL == nil
            ? "Watch Another Folder…"
            : "Change Extra Folder…"
    }

    private var openFolderButtonTitle: String {
        requiresExplicitCaptureFolderAuthorization
            ? "Open Capture Folder"
            : "Open Screenshot Folder"
    }

    private var openFolderButtonHelp: String {
        requiresExplicitCaptureFolderAuthorization
            ? "Reveal the authorized capture folder in Finder"
            : "Reveal the current macOS screenshot folder in Finder"
    }

    private func displayPath(for url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let components = path.split(separator: "/", omittingEmptySubsequences: true)

        guard components.count >= 3, components[0] == "Users" else {
            return path
        }

        return "~/" + components.dropFirst(2).joined(separator: "/")
    }

    private var folderButtonHelp: String {
        if requiresExplicitCaptureFolderAuthorization {
            return "Choose the screenshot folder CaptureArc is allowed to watch"
        }
        return "Optionally watch another folder in addition to macOS screenshots"
    }

    private var privacyDescription: String {
        if requiresExplicitCaptureFolderAuthorization {
            return "CaptureArc watches only the folder you authorize. It does not record your screen and does not need Screen Recording, Accessibility, or Full Disk Access."
        }
        return "CaptureArc watches the folder macOS already uses for screenshots plus any additional folder you choose. It does not record your screen and does not need Screen Recording, Accessibility, or Full Disk Access."
    }
}
