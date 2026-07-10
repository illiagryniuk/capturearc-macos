import Combine
import Foundation
import OSLog
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable

    init(serviceStatus: SMAppService.Status) {
        switch serviceStatus {
        case .notRegistered:
            self = .notRegistered
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            // For `SMAppService.mainApp`, macOS can report notFound before the
            // first registration even though register() is valid and succeeds.
            // Treat it as an actionable off state; a genuine signing or bundle
            // problem is surfaced by the registration error itself.
            self = .notRegistered
        @unknown default:
            self = .unavailable
        }
    }

    var isEnabled: Bool {
        switch self {
        case .enabled, .requiresApproval:
            // requiresApproval means ServiceManagement has registered the
            // preference, but macOS has paused it pending the user's consent.
            // Keeping the toggle on lets the user explicitly unregister it.
            return true
        case .notRegistered, .unavailable:
            return false
        }
    }

    var helper: String {
        switch self {
        case .notRegistered:
            return "Open CaptureArc automatically after you sign in to this Mac."
        case .enabled:
            return "CaptureArc will open automatically after you sign in."
        case .requiresApproval:
            return "macOS needs your approval in System Settings before CaptureArc can open at login."
        case .unavailable:
            return "Launch at Login is unavailable for this build. Use a properly signed CaptureArc.app bundle; installing release builds in Applications is recommended."
        }
    }
}

@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var busy = false
    @Published private(set) var status: LaunchAtLoginStatus
    @Published private(set) var helper: String
    @Published private(set) var error: String?

    private let statusProvider: () -> SMAppService.Status
    private let registerAction: () throws -> Void
    private let unregisterAction: () throws -> Void
    private let openLoginItemsAction: () -> Void
    private let logger: Logger
    private var updateTask: Task<Void, Never>?

    init(
        statusProvider: @escaping () -> SMAppService.Status = {
            SMAppService.mainApp.status
        },
        registerAction: @escaping () throws -> Void = {
            try SMAppService.mainApp.register()
        },
        unregisterAction: @escaping () throws -> Void = {
            try SMAppService.mainApp.unregister()
        },
        openLoginItemsAction: @escaping () -> Void = {
            SMAppService.openSystemSettingsLoginItems()
        }
    ) {
        self.statusProvider = statusProvider
        self.registerAction = registerAction
        self.unregisterAction = unregisterAction
        self.openLoginItemsAction = openLoginItemsAction
        self.logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.illiagryniuk.capturearc",
            category: "LaunchAtLogin"
        )

        let initialStatus = LaunchAtLoginStatus(serviceStatus: statusProvider())
        self.status = initialStatus
        self.enabled = initialStatus.isEnabled
        self.helper = initialStatus.helper
    }

    func refresh() {
        apply(serviceStatus: statusProvider(), clearError: true)
        logger.debug("Launch at login status refreshed")
    }

    func setEnabled(_ shouldEnable: Bool) {
        guard !busy else { return }

        let currentStatus = LaunchAtLoginStatus(serviceStatus: statusProvider())
        if shouldEnable == currentStatus.isEnabled {
            apply(status: currentStatus, clearError: true)
            return
        }

        busy = true
        error = nil

        // Yield once so SwiftUI can render the in-progress state before
        // ServiceManagement performs its synchronous registration operation.
        updateTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.performUpdate(shouldEnable: shouldEnable)
        }
    }

    func openLoginItemsSettings() {
        guard status == .requiresApproval else { return }
        logger.info("Opening Login Items settings for launch approval")
        openLoginItemsAction()
    }

    private func performUpdate(shouldEnable: Bool) {
        defer {
            busy = false
            updateTask = nil
        }

        do {
            if shouldEnable {
                try registerAction()
            } else {
                try unregisterAction()
            }

            apply(serviceStatus: statusProvider(), clearError: true)
            logger.info("Launch at login preference updated; requested enabled: \(shouldEnable, privacy: .public)")
        } catch {
            let serviceError = error as NSError
            let refreshedStatus = LaunchAtLoginStatus(serviceStatus: statusProvider())

            // These operations are idempotent from the user's perspective. A
            // status refresh is the source of truth if another process or
            // System Settings won the race.
            if isSatisfied(
                requestedEnabled: shouldEnable,
                status: refreshedStatus,
                errorCode: serviceError.code
            ) {
                apply(status: refreshedStatus, clearError: true)
                logger.debug("Launch at login request was already satisfied")
                return
            }

            apply(status: refreshedStatus, clearError: false)
            self.error = Self.userFacingMessage(
                for: serviceError,
                requestedEnabled: shouldEnable
            )
            logger.error(
                "Launch at login update failed; requested enabled: \(shouldEnable, privacy: .public), domain: \(serviceError.domain, privacy: .public), code: \(serviceError.code, privacy: .public)"
            )
        }
    }

    private func apply(serviceStatus: SMAppService.Status, clearError: Bool) {
        apply(
            status: LaunchAtLoginStatus(serviceStatus: serviceStatus),
            clearError: clearError
        )
    }

    private func apply(status: LaunchAtLoginStatus, clearError: Bool) {
        self.status = status
        enabled = status.isEnabled
        helper = status.helper
        if clearError {
            error = nil
        }
    }

    private func isSatisfied(
        requestedEnabled: Bool,
        status: LaunchAtLoginStatus,
        errorCode: Int
    ) -> Bool {
        if requestedEnabled {
            if status == .enabled && errorCode == Int(kSMErrorAlreadyRegistered) {
                return true
            }

            return status == .requiresApproval
                && (errorCode == Int(kSMErrorAlreadyRegistered)
                    || errorCode == Int(kSMErrorLaunchDeniedByUser))
        }

        return status == .notRegistered && errorCode == Int(kSMErrorJobNotFound)
    }

    private static func userFacingMessage(
        for error: NSError,
        requestedEnabled: Bool
    ) -> String {
        switch error.code {
        case Int(kSMErrorInvalidSignature):
            return "This build is not signed in a way macOS accepts for Launch at Login. Use a properly signed CaptureArc.app build and try again."
        case Int(kSMErrorLaunchDeniedByUser):
            return "macOS did not approve CaptureArc. Open Login Items in System Settings and allow it there."
        case Int(kSMErrorServiceUnavailable):
            return "The macOS login-item service is temporarily unavailable. Please try again."
        case Int(kSMErrorToolNotValid), Int(kSMErrorJobPlistNotFound):
            return "macOS could not register this CaptureArc app bundle. Move a properly signed release build to Applications and try again."
        default:
            let action = requestedEnabled ? "enable" : "disable"
            return "CaptureArc could not \(action) Launch at Login (error \(error.code))."
        }
    }
}
