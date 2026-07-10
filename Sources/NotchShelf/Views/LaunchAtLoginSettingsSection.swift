import AppKit
import SwiftUI

@MainActor
struct LaunchAtLoginSettingsSection: View {
    @ObservedObject private var service: LaunchAtLoginService

    init(service: LaunchAtLoginService) {
        self.service = service
    }

    var body: some View {
        Section {
            HStack(spacing: 10) {
                Toggle("Launch CaptureArc at login", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .disabled(service.busy)
                    .help("Open CaptureArc automatically when you sign in")
                    .accessibilityLabel("Launch CaptureArc at login")
                    .accessibilityValue(service.enabled ? "On" : "Off")
                    .accessibilityHint("Controls whether CaptureArc opens automatically after sign-in")

                if service.busy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Updating Launch at Login")
                }
            }

            statusMessage

            if let error = service.error {
                Label {
                    Text(error)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Launch at Login error: \(error)")
            }

            if service.status == .requiresApproval {
                Button("Open Login Items…") {
                    service.openLoginItemsSettings()
                }
                .help("Open System Settings to approve CaptureArc")
                .accessibilityLabel("Open Login Items in System Settings")
                .accessibilityHint("Opens the macOS settings where you can allow CaptureArc to launch at login")
            }
        } header: {
            Text("Startup")
        }
        .onAppear {
            service.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            service.refresh()
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { service.enabled },
            set: { service.setEnabled($0) }
        )
    }

    private var statusMessage: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusSymbolName)
                .foregroundStyle(statusTint)
                .accessibilityHidden(true)

            Text(service.busy ? "Updating Launch at Login…" : service.helper)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(service.busy ? "Updating Launch at Login" : service.helper)
    }

    private var statusSymbolName: String {
        switch service.status {
        case .notRegistered:
            return "power"
        case .enabled:
            return "checkmark.circle.fill"
        case .requiresApproval:
            return "person.crop.circle.badge.exclamationmark"
        case .unavailable:
            return "exclamationmark.circle.fill"
        }
    }

    private var statusTint: Color {
        switch service.status {
        case .notRegistered:
            return .secondary
        case .enabled:
            return .green
        case .requiresApproval, .unavailable:
            return .orange
        }
    }
}
