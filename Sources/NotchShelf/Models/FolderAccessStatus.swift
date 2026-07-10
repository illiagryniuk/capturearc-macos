import Foundation

public enum FolderAccessStatus: Equatable, Sendable {
    case notConfigured
    case resolving
    case available
    case needsReselection
    case inaccessible
}
