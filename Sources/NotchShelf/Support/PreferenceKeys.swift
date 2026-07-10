import Foundation

enum PreferenceKeys {
    static let hoverDelayMilliseconds = "hoverDelayMilliseconds"
    static let animateNewCaptures = "animateNewCaptures"
    static let retentionPolicy = "retentionPolicy"
    static let preferredDisplayID = "preferredDisplayID"
    static let managedCaptureKeys = "managedCaptureKeys"
}

enum RetentionPolicy: String, CaseIterable, Identifiable {
    case indefinitely
    case oneDay
    case sevenDays
    case thirtyDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .indefinitely:
            return "Keep indefinitely"
        case .oneDay:
            return "Keep for 24 hours"
        case .sevenDays:
            return "Keep for 7 days"
        case .thirtyDays:
            return "Keep for 30 days"
        }
    }

    var ageLimit: TimeInterval? {
        switch self {
        case .indefinitely:
            return nil
        case .oneDay:
            return 24 * 60 * 60
        case .sevenDays:
            return 7 * 24 * 60 * 60
        case .thirtyDays:
            return 30 * 24 * 60 * 60
        }
    }
}
