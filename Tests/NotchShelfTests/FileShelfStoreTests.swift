import Foundation
import XCTest
@testable import NotchShelf

@MainActor
final class FileShelfStoreTests: XCTestCase {
    func testFolderTabLoadsNavigatesAndRestoresFromLocalBookmarks() async throws {
        let suiteName = "FileShelfStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureArcFileShelf-\(UUID().uuidString)", isDirectory: true)
        let child = root.appendingPathComponent("Projects", isDirectory: true)
        let file = root.appendingPathComponent("Read Me.txt")

        try FileManager.default.createDirectory(
            at: child,
            withIntermediateDirectories: true
        )
        try Data("CaptureArc".utf8).write(to: file)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let firstStore = FileShelfStore(defaults: defaults)
        firstStore.addFolder(root)
        try await waitForLoad(firstStore)

        XCTAssertEqual(firstStore.tabs.count, 1)
        XCTAssertEqual(firstStore.items.map(\.displayName), ["Projects", "Read Me.txt"])

        let folder = try XCTUnwrap(firstStore.items.first(where: \.isDirectory))
        firstStore.activate(folder)
        try await waitForLoad(firstStore)
        XCTAssertEqual(firstStore.selectedTab?.currentRelativePath, "Projects")

        let restoredStore = FileShelfStore(defaults: defaults)
        try await waitForLoad(restoredStore)
        XCTAssertEqual(restoredStore.tabs.count, 1)
        XCTAssertEqual(restoredStore.selectedTab?.rootURL, root.standardizedFileURL)
        XCTAssertEqual(restoredStore.selectedTab?.currentRelativePath, "Projects")

        if let tabID = restoredStore.selectedTabID {
            restoredStore.closeTab(tabID)
        }
        XCTAssertTrue(restoredStore.tabs.isEmpty)
    }

    private func waitForLoad(
        _ store: FileShelfStore,
        timeout: Duration = .seconds(2)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while store.isLoading {
            if clock.now >= deadline {
                XCTFail("Timed out waiting for the file shelf to load")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
