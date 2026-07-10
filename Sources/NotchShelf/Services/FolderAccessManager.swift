import Foundation
import OSLog

public struct FolderAccessResolution: Sendable {
    public let url: URL
    public let bookmarkWasStale: Bool

    public init(url: URL, bookmarkWasStale: Bool) {
        self.url = url
        self.bookmarkWasStale = bookmarkWasStale
    }
}

public enum FolderAccessError: Error, Equatable {
    case noStoredBookmark
    case notDirectory
    case unreadableDirectory
}

public final class FolderAccessManager {
    public static let defaultBookmarkKey = "NotchShelf.captureFolderBookmark"

    private let defaults: UserDefaults
    private let bookmarkKey: String
    private var scopedURL: URL?
    private var isUsingSecurityScope = false
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CaptureArc",
        category: "FolderAccess"
    )

    public init(
        defaults: UserDefaults = .standard,
        bookmarkKey: String = FolderAccessManager.defaultBookmarkKey
    ) {
        self.defaults = defaults
        self.bookmarkKey = bookmarkKey
    }

    deinit {
        relinquishAccess()
    }

    public var hasStoredBookmark: Bool {
        defaults.data(forKey: bookmarkKey) != nil
    }

    @discardableResult
    public func authorize(_ selectedURL: URL) throws -> FolderAccessResolution {
        let url = selectedURL.standardizedFileURL
        try validateDirectory(url)

        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: [.isDirectoryKey],
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: bookmarkKey)

        beginAccessing(url)
        logger.info("Capture folder authorization stored")
        return FolderAccessResolution(url: url, bookmarkWasStale: false)
    }

    public func restore() throws -> FolderAccessResolution {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else {
            throw FolderAccessError.noStoredBookmark
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).standardizedFileURL

        beginAccessing(url)

        do {
            try validateDirectory(url)
            if isStale {
                let refreshedBookmark = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: [.isDirectoryKey],
                    relativeTo: nil
                )
                defaults.set(refreshedBookmark, forKey: bookmarkKey)
                logger.info("Capture folder authorization refreshed")
            } else {
                logger.info("Capture folder authorization restored")
            }
            return FolderAccessResolution(url: url, bookmarkWasStale: isStale)
        } catch {
            relinquishAccess()
            throw error
        }
    }

    public func relinquishAccess() {
        if isUsingSecurityScope {
            scopedURL?.stopAccessingSecurityScopedResource()
        }
        scopedURL = nil
        isUsingSecurityScope = false
    }

    public func forgetFolder() {
        relinquishAccess()
        defaults.removeObject(forKey: bookmarkKey)
        logger.info("Capture folder authorization removed")
    }

    private func beginAccessing(_ url: URL) {
        relinquishAccess()
        scopedURL = url
        isUsingSecurityScope = url.startAccessingSecurityScopedResource()
    }

    private func validateDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
        guard values.isDirectory == true else {
            throw FolderAccessError.notDirectory
        }
        guard values.isReadable != false else {
            throw FolderAccessError.unreadableDirectory
        }
    }
}
