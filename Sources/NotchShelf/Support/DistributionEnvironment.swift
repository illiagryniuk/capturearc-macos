import Foundation

enum DistributionChannel: Equatable {
    case local
    case appStore

    static var current: DistributionChannel {
        resolve(
            distributionValue: Bundle.main.object(
                forInfoDictionaryKey: "CaptureArcDistribution"
            ) as? String,
            sandboxContainerID: ProcessInfo.processInfo.environment[
                "APP_SANDBOX_CONTAINER_ID"
            ]
        )
    }

    static func resolve(
        distributionValue: String?,
        sandboxContainerID: String?
    ) -> DistributionChannel {
        if distributionValue?.localizedCaseInsensitiveCompare("app-store") == .orderedSame {
            return .appStore
        }

        if let sandboxContainerID, !sandboxContainerID.isEmpty {
            return .appStore
        }

        return .local
    }

    var requiresExplicitCaptureFolderAuthorization: Bool {
        self == .appStore
    }
}
