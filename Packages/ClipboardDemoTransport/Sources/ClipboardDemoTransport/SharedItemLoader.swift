#if canImport(UIKit)
import Foundation
import UIKit
import UniformTypeIdentifiers

public enum SharedItemError: LocalizedError {
    case unsupported, oversized, unreadable, tooMany
    public var errorDescription: String? {
        switch self {
        case .unsupported: return CaptureArcText.value("Choose text, a web link, a photo, or a file.")
        case .oversized: return CaptureArcText.value("Photos and files can be up to 10 MB each. Text can be up to 1 MB.")
        case .unreadable: return CaptureArcText.value("Could not read the selected item.")
        case .tooMany: return CaptureArcText.value("Choose up to 5 items at a time.")
        }
    }
}

public enum SharedItemLoader {
    public static func load(_ provider: NSItemProvider, index: Int = 1) async throws -> DemoTransfer {
        if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
            return try await loadFile(provider, type: type, kind: .photo, index: index)
        }
        if provider.canLoadObject(ofClass: NSURL.self),
           let url = try? await loadURL(provider), !url.isFileURL {
            let result = DemoTransfer(kind: .link, bytes: Data(url.absoluteString.utf8))
            // Some hosts advertise URL as an alternative to selected text, but cannot
            // vend it. Continue to the text representation when that alternative fails.
            if (try? result.check()) != nil { return result }
        }
        if provider.canLoadObject(ofClass: NSString.self),
           let text = try? await loadString(provider) {
            return try textTransfer(text)
        }
        // Selected text from host apps is also delivered through the older item
        // API, as NSString, NSAttributedString, or encoded plain-text data.
        // Supporting the type does not imply support for loadObject(NSString.self).
        var visited = Set<String>()
        let textTypes = [UTType.plainText.identifier, UTType.text.identifier] +
            provider.registeredTypeIdentifiers.filter { UTType($0)?.conforms(to: .plainText) == true }
        for type in textTypes where visited.insert(type).inserted && provider.hasItemConformingToTypeIdentifier(type) {
            guard let value = try? await provider.loadItem(forTypeIdentifier: type, options: nil) else { continue }
            if let text = value as? String { return try textTransfer(text) }
            if let text = value as? NSAttributedString { return try textTransfer(text.string) }
            if let data = value as? Data {
                guard data.count <= DemoTransfer.maximumText * 2 else { throw SharedItemError.oversized }
                let encoding: String.Encoding = type == UTType.utf16PlainText.identifier ||
                    type == UTType.utf16ExternalPlainText.identifier ? .utf16 : .utf8
                if let text = String(data: data, encoding: encoding) { return try textTransfer(text) }
            }
            // Never read an arbitrary URL returned as text; files stay on the
            // provider-managed file-representation path below.
        }
        if let type = provider.registeredTypeIdentifiers.first(where: {
            guard let value = UTType($0) else { return false }
            return value.conforms(to: .data) && !value.conforms(to: .url)
        }) {
            return try await loadFile(provider, type: type, kind: .file, index: index)
        }
        throw SharedItemError.unsupported
    }

    private static func textTransfer(_ text: String) throws -> DemoTransfer {
        guard text.utf8.count <= DemoTransfer.maximumText else { throw SharedItemError.oversized }
        let result = DemoTransfer(kind: .text, bytes: Data(text.utf8))
        try result.check()
        return result
    }

    private static func loadURL(_ provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: NSURL.self) { object, error in
                guard error == nil, let url = object as? URL else {
                    continuation.resume(throwing: SharedItemError.unreadable); return
                }
                continuation.resume(returning: url)
            }
        }
    }

    private static func loadString(_ provider: NSItemProvider) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: NSString.self) { object, error in
                guard error == nil, let text = object as? String else {
                    continuation.resume(throwing: SharedItemError.unreadable); return
                }
                continuation.resume(returning: text)
            }
        }
    }

    private static func loadFile(_ provider: NSItemProvider, type: String,
                                 kind: DemoTransfer.Kind, index: Int) async throws -> DemoTransfer {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                do {
                    guard error == nil, let url else { throw SharedItemError.unreadable }
                    // The provider removes this temporary URL after this callback returns.
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let bytes = try handle.read(upToCount: DemoTransfer.maximumPayload + 1) ?? Data()
                    guard bytes.count <= DemoTransfer.maximumPayload else { throw SharedItemError.oversized }
                    let suffix = UTType(type)?.preferredFilenameExtension ?? (kind == .photo ? "jpg" : "bin")
                    var name = provider.suggestedName ?? "CaptureArc-\(index).\(suffix)"
                    if (name as NSString).pathExtension.isEmpty { name += ".\(suffix)" }
                    if name.isEmpty || name.hasPrefix(".") || name.utf8.count > 200 ||
                        name.contains("/") || name.contains("\\") || name.contains(":") ||
                        name.rangeOfCharacter(from: .controlCharacters) != nil {
                        name = "CaptureArc-\(index).\(suffix)"
                    }
                    let result = DemoTransfer(kind: kind, bytes: bytes, name: name)
                    try result.check()
                    continuation.resume(returning: result)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
#endif
