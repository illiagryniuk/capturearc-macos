import Foundation
import XCTest
@testable import NotchShelf

final class ScreenshotLocationResolverTests: XCTestCase {
    func testFallsBackToDesktopWhenPreferenceIsAbsent() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let resolver = ScreenshotLocationResolver(
            homeDirectoryURL: home,
            locationPreferenceReader: { nil }
        )

        XCTAssertEqual(
            resolver.resolve(),
            home.appendingPathComponent("Desktop", isDirectory: true).standardizedFileURL
        )
    }

    func testResolvesExplicitAbsoluteAndHomeRelativeLocations() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let absoluteResolver = ScreenshotLocationResolver(
            homeDirectoryURL: home,
            locationPreferenceReader: { "/Volumes/Captures" }
        )
        let homeRelativeResolver = ScreenshotLocationResolver(
            homeDirectoryURL: home,
            locationPreferenceReader: { "~/Pictures/Screenshots" }
        )

        XCTAssertEqual(
            absoluteResolver.resolve(),
            URL(fileURLWithPath: "/Volumes/Captures", isDirectory: true).standardizedFileURL
        )
        XCTAssertEqual(
            homeRelativeResolver.resolve(),
            home.appendingPathComponent(
                "Pictures/Screenshots",
                isDirectory: true
            ).standardizedFileURL
        )
    }
}
