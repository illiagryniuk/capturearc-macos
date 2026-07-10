import Foundation
import XCTest
@testable import NotchShelf

final class SystemScreenCaptureTests: XCTestCase {
    func testClassifierAcceptsScreenshotsAndScreenRecordings() {
        XCTAssertTrue(SystemScreenCaptureClassifier.isSystemScreenCapture(
            ScreenCaptureMetadata(
                isScreenCapture: true,
                hasScreenCaptureType: false
            )
        ))
        XCTAssertTrue(SystemScreenCaptureClassifier.isSystemScreenCapture(
            ScreenCaptureMetadata(
                isScreenCapture: false,
                hasScreenCaptureType: true
            )
        ))
        XCTAssertFalse(SystemScreenCaptureClassifier.isSystemScreenCapture(
            ScreenCaptureMetadata(
                isScreenCapture: false,
                hasScreenCaptureType: false
            )
        ))
    }

    func testSystemSourceFilterRejectsOrdinaryMedia() async throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let screenshotURL = folderURL.appendingPathComponent("renamed-system-capture.png")
        let ordinaryURL = folderURL.appendingPathComponent("ordinary-image.png")
        try Data([1]).write(to: screenshotURL)
        try Data([2]).write(to: ordinaryURL)

        let loader = CaptureMetadataLoader(
            screenCaptureMetadataProvider: TestFilenameMetadataProvider(
                captureNames: [screenshotURL.lastPathComponent]
            )
        )

        let allMedia = try await loader.supportedFiles(
            in: folderURL,
            filter: .supportedMedia
        )
        let systemCaptures = try await loader.supportedFiles(
            in: folderURL,
            filter: .macOSScreenCapturesOnly
        )

        XCTAssertEqual(Set(allMedia.map { $0.url.lastPathComponent }), [
            screenshotURL.lastPathComponent,
            ordinaryURL.lastPathComponent,
        ])
        XCTAssertEqual(
            systemCaptures.map { $0.url.lastPathComponent },
            [screenshotURL.lastPathComponent]
        )
    }
}

struct TestFilenameMetadataProvider: ScreenCaptureMetadataProviding {
    let captureNames: Set<String>

    func metadata(for url: URL) -> ScreenCaptureMetadata {
        ScreenCaptureMetadata(
            isScreenCapture: captureNames.contains(url.lastPathComponent),
            hasScreenCaptureType: false
        )
    }
}
