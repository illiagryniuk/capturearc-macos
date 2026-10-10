import Foundation
import XCTest
@testable import NotchShelf

final class FileShelfPathTests: XCTestCase {
    func testBuildsCurrentURLFromRootAndRelativePath() {
        let root = URL(fileURLWithPath: "/tmp/CaptureArcFiles", isDirectory: true)

        XCTAssertEqual(
            FileShelfPath.currentURL(root: root, relativePath: "Projects/Current"),
            root.appendingPathComponent("Projects/Current", isDirectory: true)
                .standardizedFileURL
        )
    }

    func testRelativePathAcceptsRootAndDescendants() {
        let root = URL(fileURLWithPath: "/tmp/CaptureArcFiles", isDirectory: true)

        XCTAssertEqual(FileShelfPath.relativePath(of: root, inside: root), "")
        XCTAssertEqual(
            FileShelfPath.relativePath(
                of: root.appendingPathComponent("Projects/Current", isDirectory: true),
                inside: root
            ),
            "Projects/Current"
        )
    }

    func testRelativePathRejectsSiblingFolderWithMatchingPrefix() {
        let root = URL(fileURLWithPath: "/tmp/CaptureArcFiles", isDirectory: true)
        let sibling = URL(fileURLWithPath: "/tmp/CaptureArcFiles-Archive", isDirectory: true)

        XCTAssertNil(FileShelfPath.relativePath(of: sibling, inside: root))
    }

    func testSortsFoldersBeforeFilesThenUsesFinderStyleNames() {
        let items = [
            item("zeta.txt", directory: false),
            item("Beta", directory: true),
            item("alpha.txt", directory: false),
            item("alpha", directory: true)
        ]

        XCTAssertEqual(
            FileShelfPath.sorted(items).map(\.displayName),
            ["alpha", "Beta", "alpha.txt", "zeta.txt"]
        )
    }

    private func item(_ name: String, directory: Bool) -> FileShelfItem {
        FileShelfItem(
            url: URL(fileURLWithPath: "/tmp/\(name)", isDirectory: directory),
            displayName: name,
            isDirectory: directory,
            modifiedAt: nil,
            fileSize: nil,
            typeDescription: directory ? "Folder" : "File"
        )
    }
}
