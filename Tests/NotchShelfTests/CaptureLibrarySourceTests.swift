import Foundation
import XCTest
@testable import NotchShelf

@MainActor
final class CaptureLibrarySourceTests: XCTestCase {
    func testSystemSourceBaselinesExistingFilesThenNotifiesOnceForNewFile() async throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )

        let baselineURL = folderURL.appendingPathComponent("baseline.png")
        let newCaptureURL = folderURL.appendingPathComponent("new-capture.png")
        try pngData.write(to: baselineURL, options: .atomic)

        let loader = CaptureMetadataLoader(
            screenCaptureMetadataProvider: TestFilenameMetadataProvider(
                captureNames: [
                    baselineURL.lastPathComponent,
                    newCaptureURL.lastPathComponent,
                ]
            ),
            stabilitySampleCount: 2,
            stabilityInterval: 0.01,
            maximumStabilityAttempts: 10
        )
        let defaultsSuiteName = "CaptureLibrarySourceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        let library = CaptureLibrary(
            folderAccessManager: FolderAccessManager(defaults: defaults),
            metadataLoader: loader
        )
        var notifiedURLs: [URL] = []
        library.onNewCapture = { notifiedURLs.append($0.fileURL.standardizedFileURL) }
        library.start()

        defer {
            library.stop()
            defaults.removePersistentDomain(forName: defaultsSuiteName)
            try? FileManager.default.removeItem(at: folderURL)
        }

        await library.setSystemScreenshotFolder(folderURL)
        let baselineLoaded = await waitUntil {
            library.items.count == 1 && !library.isReconciling
        }
        XCTAssertTrue(baselineLoaded)
        XCTAssertEqual(library.systemScreenshotFolderURL, folderURL.standardizedFileURL)
        XCTAssertTrue(notifiedURLs.isEmpty)

        try pngData.write(to: newCaptureURL, options: .atomic)
        library.rescan()

        let newCaptureLoaded = await waitUntil {
            library.items.count == 2
                && notifiedURLs == [newCaptureURL.standardizedFileURL]
                && !library.isReconciling
        }
        XCTAssertTrue(newCaptureLoaded)

        library.rescan()
        let rescanCompleted = await waitUntil { !library.isReconciling }
        XCTAssertTrue(rescanCompleted)
        XCTAssertEqual(library.items.count, 2)
        XCTAssertEqual(notifiedURLs, [newCaptureURL.standardizedFileURL])

        await library.setSystemScreenshotFolder(folderURL)
        let unchangedSourceCompleted = await waitUntil { !library.isReconciling }
        XCTAssertTrue(unchangedSourceCompleted)
        XCTAssertEqual(library.items.count, 2)
        XCTAssertEqual(notifiedURLs, [newCaptureURL.standardizedFileURL])
    }

    private var pngData: Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}
