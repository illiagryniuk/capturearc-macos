import Foundation

struct FileShelfItem: Identifiable, Hashable, Sendable {
    let url: URL
    let displayName: String
    let isDirectory: Bool
    let modifiedAt: Date?
    let fileSize: Int64?
    let typeDescription: String

    var id: URL { url }
}

enum FileShelfPath {
    static func currentURL(root: URL, relativePath: String) -> URL {
        guard !relativePath.isEmpty else { return root.standardizedFileURL }
        return root
            .appendingPathComponent(relativePath, isDirectory: true)
            .standardizedFileURL
    }

    static func relativePath(of child: URL, inside root: URL) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let childComponents = child.standardizedFileURL.pathComponents

        guard childComponents.count >= rootComponents.count,
              Array(childComponents.prefix(rootComponents.count)) == rootComponents else {
            return nil
        }

        return childComponents
            .dropFirst(rootComponents.count)
            .joined(separator: "/")
    }

    static func sorted(_ items: [FileShelfItem]) -> [FileShelfItem] {
        items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }
}
