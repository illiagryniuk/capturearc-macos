import CoreFoundation
import Foundation

public struct ScreenshotLocationResolver: Sendable {
    public typealias LocationPreferenceReader = @Sendable () -> String?

    private let homeDirectoryURL: URL
    private let locationPreferenceReader: LocationPreferenceReader

    public init(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        locationPreferenceReader: @escaping LocationPreferenceReader = {
            _ = CFPreferencesAppSynchronize(
                "com.apple.screencapture" as CFString
            )
            return CFPreferencesCopyAppValue(
                "location" as CFString,
                "com.apple.screencapture" as CFString
            ) as? String
        }
    ) {
        self.homeDirectoryURL = homeDirectoryURL.standardizedFileURL
        self.locationPreferenceReader = locationPreferenceReader
    }

    public func resolve() -> URL {
        guard let rawLocation = locationPreferenceReader()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawLocation.isEmpty
        else {
            return homeDirectoryURL
                .appendingPathComponent("Desktop", isDirectory: true)
                .standardizedFileURL
        }

        if let fileURL = URL(string: rawLocation), fileURL.isFileURL {
            return fileURL.standardizedFileURL
        }

        if rawLocation == "~" {
            return homeDirectoryURL
        }

        if rawLocation.hasPrefix("~/") {
            return homeDirectoryURL
                .appendingPathComponent(String(rawLocation.dropFirst(2)), isDirectory: true)
                .standardizedFileURL
        }

        if rawLocation.hasPrefix("/") {
            return URL(fileURLWithPath: rawLocation, isDirectory: true).standardizedFileURL
        }

        return homeDirectoryURL
            .appendingPathComponent(rawLocation, isDirectory: true)
            .standardizedFileURL
    }
}
