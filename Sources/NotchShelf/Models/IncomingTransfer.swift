import Foundation
import ClipboardDemoTransport

enum IncomingTransferPayload {
    case text(String)
    case link(URL)
    case photo(name: String, data: Data)
    case file(name: String, data: Data)
}

enum IncomingTransferError: LocalizedError, Equatable {
    case unsupportedLink, invalidName, invalidSize, full

    var errorDescription: String? {
        switch self {
        case .full: return CaptureArcText.value("The shelf is full. Remove cards you no longer need, then send again.")
        case .invalidSize: return CaptureArcText.value("Photos and files can be up to 10 MB each. Text can be up to 1 MB.")
        case .invalidName: return CaptureArcText.value("The filename is invalid.")
        case .unsupportedLink: return CaptureArcText.value("This link is unsupported. Use HTTP or HTTPS.")
        }
    }
}

struct IncomingTransfer: Identifiable {
    enum Kind: String, Codable {
        case text, link, photo, file

        var label: String {
            switch self {
            case .text: return CaptureArcText.value("Text")
            case .link: return CaptureArcText.value("Link")
            case .photo: return CaptureArcText.value("Photo")
            case .file: return CaptureArcText.value("File")
            }
        }

        var symbol: String {
            switch self {
            case .text: return "text.alignleft"
            case .link: return "link"
            case .photo: return "photo"
            case .file: return "doc"
            }
        }
    }

    let id: UUID
    let kind: Kind
    let title: String
    let text: String?
    let url: URL?
}

struct IncomingTransferStaging {
    static let maximumFileBytes = Int(FileTransferLimits.maximumBytes)
    static let maximumTextBytes = DemoTransfer.maximumText
    let directory: URL

    func stage(_ payload: IncomingTransferPayload) throws -> IncomingTransfer {
        let id = UUID()
        switch payload {
        case .text(let value):
            guard !value.isEmpty, value.utf8.count <= Self.maximumTextBytes else {
                throw IncomingTransferError.invalidSize
            }
            return IncomingTransfer(id: id, kind: .text, title: String(value.prefix(100)), text: value, url: nil)
        case .link(let url):
            guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
                  url.absoluteString.utf8.count <= Self.maximumTextBytes else {
                throw IncomingTransferError.unsupportedLink
            }
            return IncomingTransfer(id: id, kind: .link, title: url.absoluteString, text: nil, url: url)
        case .photo(let name, let data):
            return try stageFile(id: id, kind: .photo, name: name, data: data)
        case .file(let name, let data):
            return try stageFile(id: id, kind: .file, name: name, data: data)
        }
    }

    func adopt(_ file: TransferFile) throws -> IncomingTransfer {
        guard !file.cancellation.isCancelled else { throw DemoWireError.cancelled }
        try file.metadata.check()
        let values = try file.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              values.fileSize.map(Int64.init) == file.metadata.byteCount else { throw FileTransferError.integrity }
        let id = UUID()
        let folder = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = folder.appendingPathComponent(file.metadata.name)
        do { try FileManager.default.moveItem(at: file.url, to: destination) }
        catch { try? FileManager.default.removeItem(at: folder); throw error }
        return IncomingTransfer(id: id, kind: file.metadata.kind == .photo ? .photo : .file,
                                title: file.metadata.name, text: nil, url: destination)
    }

    static func validateName(_ name: String) throws {
        guard !name.isEmpty, !name.hasPrefix("."), name.utf8.count <= 200,
              !name.contains("/"), !name.contains("\\"), !name.contains(":"),
              name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw IncomingTransferError.invalidName
        }
    }

    private func stageFile(id: UUID, kind: IncomingTransfer.Kind, name: String, data: Data) throws -> IncomingTransfer {
        try Self.validateName(name)
        guard !data.isEmpty, data.count <= DemoTransfer.maximumPayload else { throw IncomingTransferError.invalidSize }
        let folder = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let location = folder.appendingPathComponent(name)
        try data.write(to: location, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
        return IncomingTransfer(id: id, kind: kind, title: name, text: nil, url: location)
    }
}
