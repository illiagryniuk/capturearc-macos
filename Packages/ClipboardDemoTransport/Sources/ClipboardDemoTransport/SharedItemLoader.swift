#if canImport(UIKit)
import Foundation
import UIKit
import UniformTypeIdentifiers

public enum SharedItemError: LocalizedError {
    case unsupported, oversized, unreadable, tooMany, preparationTimedOut
    public var errorDescription: String? {
        switch self {
        case .preparationTimedOut: return CaptureArcText.value("Preparing the file timed out. Download it on your iPhone first, then share it again.")
        case .unsupported: return CaptureArcText.value("Choose text, a web link, a photo, or a file.")
        case .oversized: return CaptureArcText.value("Photos and files can be up to 10 MB each. Text can be up to 1 MB.")
        case .unreadable: return CaptureArcText.value("Could not read the selected item.")
        case .tooMany: return CaptureArcText.value("Choose up to 5 items at a time.")
        }
    }
}

public enum SharedItemLoader {
    /// File representations are snapshotted while the provider URL is valid.
    /// A named .txt export stays a document; selected text remains inline text.
    public static func loadOutgoing(_ provider: NSItemProvider, index: Int = 1,
                                    invitation: DemoInvitation,
                                    cancellation: TransferCancellation = TransferCancellation()) async throws -> OutgoingItem {
        try Task.checkCancellation()
        guard !cancellation.isCancelled else { throw DemoWireError.cancelled }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let file = try await prepareItemURL(provider, type: UTType.fileURL.identifier, invitation: invitation, cancellation: cancellation) {
                return .file(file)
            }
            if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .url) != true }) {
                return .file(try await prepareFile(provider, type: type, index: index, invitation: invitation, cancellation: cancellation))
            }
        }
        // Prefer the declared file extension's exact representation. A provider
        // may also offer an NSString alternative that must not replace the file.
        let extensionType = provider.suggestedName.flatMap { UTType(filenameExtension: ($0 as NSString).pathExtension)?.identifier }
        let preferredFileType = extensionType.flatMap { provider.registeredTypeIdentifiers.contains($0) ? $0 : nil }
        let type = preferredFileType ?? provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true }
            ?? provider.registeredTypeIdentifiers.first {
                let namedFile = !(provider.suggestedName.map { ($0 as NSString).pathExtension } ?? "").isEmpty
                guard let type = UTType($0) else { return namedFile }
                guard !type.conforms(to: .url) else { return false }
                return namedFile || (type.conforms(to: .data) && !type.conforms(to: .text))
            }
        if let type {
            return .file(try await prepareFile(provider, type: type, index: index,
                                              invitation: invitation, cancellation: cancellation))
        }
        // Some document providers return a URL for a text type without declaring
        // file-url or a suggested filename. Never decode that URL into clipboard text.
        for type in provider.registeredTypeIdentifiers where UTType(type)?.conforms(to: .text) == true {
            if let file = try await prepareItemURL(provider, type: type, invitation: invitation, cancellation: cancellation) {
                return .file(file)
            }
        }
        return .inline(try await load(provider, index: index))
    }

    private static func prepareItemURL(_ provider: NSItemProvider, type: String, invitation: DemoInvitation,
                                       cancellation: TransferCancellation) async throws -> TransferFile? {
        let request = SharedProviderRequest<TransferFile?>(cancellation: cancellation)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TransferFile?, Error>) in
                guard request.install(continuation) else { return }
                provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                    var source = item as? URL
                    if source == nil, type == UTType.fileURL.identifier, let data = item as? Data, data.count <= 16 * 1024 {
                        source = (try? NSURL.object(withItemProviderData: data, typeIdentifier: type)) as URL?
                    }
                    guard let url = source, url.isFileURL else { request.complete(.success(nil)); return }
                    do {
                        let kind: DemoTransfer.Kind = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true ? .photo : .file
                        request.complete(.success(try TransferFile.prepare(url, kind: kind, invitation: invitation,
                                                                                cancelled: { cancellation.isCancelled })))
                    } catch { request.complete(.failure(error)) }
                }
            }
        } onCancel: { request.cancel(DemoWireError.cancelled) }
    }

    private static func prepareFile(_ provider: NSItemProvider, type: String, index: Int,
                                    invitation: DemoInvitation, cancellation: TransferCancellation) async throws -> TransferFile {
        let request = SharedProviderRequest<TransferFile>(cancellation: cancellation)
        let suggestedName = provider.suggestedName
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard request.install(continuation) else { return }
                let progress = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                    do {
                        guard !cancellation.isCancelled else { throw DemoWireError.cancelled }
                        guard error == nil, let url else { throw SharedItemError.unreadable }
                        let kind: DemoTransfer.Kind = UTType(type)?.conforms(to: .image) == true ? .photo : .file
                        let suffix = UTType(type)?.preferredFilenameExtension ?? (kind == .photo ? "jpg" : "bin")
                        var name = suggestedName ?? url.lastPathComponent
                        if (name as NSString).pathExtension.isEmpty { name += "." + suffix }
                        if (try? FileTransferMetadata(kind: kind, name: name, byteCount: 1).check()) == nil {
                            name = "CaptureArc-\(index).\(suffix)"
                        }
                        request.complete(.success(try TransferFile.prepare(url, kind: kind, name: name, invitation: invitation,
                                                                                cancelled: { cancellation.isCancelled })))
                    } catch { request.complete(.failure(error)) }
                }
                request.setProgress(progress)
            }
        } onCancel: { request.cancel(DemoWireError.cancelled) }
    }

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
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                do {
                    guard error == nil, let url else { throw SharedItemError.unreadable }
                    // The provider removes this temporary URL after this callback returns.
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let bytes = try handle.read(upToCount: DemoTransfer.maximumPayload + 1) ?? Data()
                    guard bytes.count <= DemoTransfer.maximumPayload else { throw SharedItemError.oversized }
                    let suffix = UTType(type)?.preferredFilenameExtension ?? (kind == .photo ? "jpg" : "bin")
                    var name = suggestedName ?? "CaptureArc-\(index).\(suffix)"
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
/// Complete once even if an uncooperative host ignores cancellation or calls back
/// after the extension is dismissed. No file snapshot is retained after failure.
private final class SharedProviderRequest<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var progress: Progress?
    private var deadline: DispatchWorkItem?
    private let cancellation: TransferCancellation
    init(cancellation: TransferCancellation) { self.cancellation = cancellation }
    func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        if finished, let result {
            self.result = nil
            lock.unlock(); continuation.resume(with: result); return false
        }
        self.continuation = continuation
        let deadline = DispatchWorkItem { [weak self] in self?.cancel(SharedItemError.preparationTimedOut) }
        self.deadline = deadline
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: deadline)
        return true
    }
    func setProgress(_ progress: Progress) {
        lock.lock()
        let finished = self.finished
        if !finished { self.progress = progress }
        lock.unlock()
        if finished { progress.cancel() }
    }
    func complete(_ value: Result<Value, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation; self.continuation = nil
        // Only cache cancellation that arrived before install. Keeping a successful
        // file here would retain its snapshot as long as the host kept its callback.
        result = continuation == nil ? value : nil
        let deadline = self.deadline; self.deadline = nil
        progress = nil
        lock.unlock()
        deadline?.cancel(); continuation?.resume(with: value)
    }
    func cancel(_ error: Error) {
        cancellation.cancel()
        lock.lock(); let progress = self.progress; lock.unlock()
        complete(.failure(error)); progress?.cancel()
    }
}
#endif
