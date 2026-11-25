import Foundation
import CryptoKit
import Darwin

public enum FileTransferLimits {
    public static let version = 3
    public static let maximumBytes: Int64 = 1_073_741_824 // 1 GiB, inclusive
    public static let chunkBytes = 256 * 1024
    public static let diskReserve: Int64 = 64 * 1024 * 1024
    public static let idleTimeout: TimeInterval = 30
    public static let sessionTimeout: TimeInterval = 2 * 60 * 60
    static let magic = Data([0x43, 0x41, 0x46, 0x33]) // CAF3; outside legacy frame length range
}

public enum FileTransferError: String, Error, Codable, LocalizedError {
    case upgrade, tooLarge, diskFull, invalidFile, changedFile, integrity, storage, shelfFull, protocolMismatch, busy
    public var errorDescription: String? {
        switch self {
        case .busy: return DemoWireError.busy.errorDescription
        case .upgrade: return CaptureArcText.value("For files over 10 MiB, update CaptureArc on both devices and scan the Mac QR code again.")
        case .tooLarge: return CaptureArcText.value("The file exceeds the 1 GiB limit.")
        case .diskFull: return CaptureArcText.value("Not enough free storage. Free space on the sending and receiving devices, then try again.")
        case .invalidFile: return CaptureArcText.value("Choose a nonempty file. Export folders as an archive first.")
        case .changedFile: return CaptureArcText.value("The file changed while preparing the transfer. Try again.")
        case .integrity: return CaptureArcText.value("The file could not be verified. It was not saved.")
        case .storage: return CaptureArcText.value("The file could not be saved. Check available storage and try again.")
        case .shelfFull: return CaptureArcText.value("The shelf is full. Remove cards you no longer need, then send again.")
        case .protocolMismatch: return CaptureArcText.value("Update CaptureArc on both devices and scan the Mac QR code again.")
        }
    }
}

public struct FileTransferMetadata: Codable {
    public let version: Int
    public let kind: DemoTransfer.Kind
    public let name: String
    public let byteCount: Int64
    public init(kind: DemoTransfer.Kind, name: String, byteCount: Int64) {
        version = FileTransferLimits.version; self.kind = kind; self.name = name; self.byteCount = byteCount
    }
    public func check() throws {
        guard version == FileTransferLimits.version else { throw FileTransferError.protocolMismatch }
        guard byteCount <= FileTransferLimits.maximumBytes else { throw FileTransferError.tooLarge }
        guard byteCount > 0, kind == .file || kind == .photo,
              !name.isEmpty, !name.hasPrefix("."), name.utf8.count <= 200,
              !name.contains("/"), !name.contains("\\"), !name.contains(":"),
              name.rangeOfCharacter(from: .controlCharacters) == nil else { throw FileTransferError.invalidFile }
    }
}

public struct FileTransferProgress {
    public let completed: Int64
    public let total: Int64
    public var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    public var label: String {
        ByteCountFormatter.string(fromByteCount: completed, countStyle: .file) + " / " +
        ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}

/// Owns a private snapshot, never the host app's original URL. Release to clean up.
public final class TransferFile {
    public let url: URL
    public let cancellation = TransferCancellation()
    public let metadata: FileTransferMetadata
    let directory: URL
    private let lease: FileHandle
    init(url: URL, metadata: FileTransferMetadata, directory: URL, lease: FileHandle) {
        self.url = url; self.metadata = metadata; self.directory = directory; self.lease = lease
    }
    deinit { try? FileManager.default.removeItem(at: directory); try? lease.close() }

    public static func prepare(_ source: URL, kind: DemoTransfer.Kind = .file, name: String? = nil,
                               invitation: DemoInvitation? = nil,
                               cancelled: () -> Bool = { false },
                               progress: (FileTransferProgress) -> Void = { _ in }) throws -> TransferFile {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var outcome: Result<TransferFile, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { url in
            outcome = Result { try snapshot(url, kind: kind, name: name, invitation: invitation, cancelled: cancelled, progress: progress) }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw FileTransferError.invalidFile }
        return try outcome.get()
    }

    private static func snapshot(_ source: URL, kind: DemoTransfer.Kind, name: String?, invitation: DemoInvitation?,
                                 cancelled: () -> Bool, progress: (FileTransferProgress) -> Void) throws -> TransferFile {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize else {
            throw FileTransferError.invalidFile
        }
        let metadata = FileTransferMetadata(kind: kind, name: name ?? source.lastPathComponent, byteCount: Int64(size))
        try metadata.check()
        if let invitation, invitation.fileProtocol != FileTransferLimits.version, size > DemoTransfer.maximumPayload {
            throw FileTransferError.upgrade
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CaptureArc-Outgoing-v3", isDirectory: true)
        let (directory, lease) = try makeTransferDirectory(root)
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: directory); try? lease.close() } }
        try checkTransferDisk(directory, bytes: metadata.byteCount)
        let url = directory.appendingPathComponent(metadata.name)
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw FileTransferError.storage
        }
        let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: url)
        defer { try? input.close(); try? output.close() }
        var count: Int64 = 0
        while count < metadata.byteCount {
            // Foundation's FileHandle bridges autoreleased NSData. Drain it per
            // chunk, including inside an NSItemProvider callback's outer pool.
            try autoreleasepool {
                if cancelled() { throw DemoWireError.cancelled }
                let data = try input.read(upToCount: Int(min(Int64(FileTransferLimits.chunkBytes), metadata.byteCount - count))) ?? Data()
                guard !data.isEmpty else { throw FileTransferError.changedFile }
                try output.write(contentsOf: data)
                count += Int64(data.count)
                progress(.init(completed: count, total: metadata.byteCount))
            }
        }
        guard (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw FileTransferError.changedFile }
        let after = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard after.fileSize == size, after.contentModificationDate == values.contentModificationDate else { throw FileTransferError.changedFile }
        if cancelled() { throw DemoWireError.cancelled }
        try output.synchronize()
        succeeded = true
        return TransferFile(url: url, metadata: metadata, directory: directory, lease: lease)
    }

    func legacy() throws -> DemoTransfer {
        guard metadata.byteCount <= Int64(DemoTransfer.maximumPayload) else { throw FileTransferError.upgrade }
        let data = try Data(contentsOf: url)
        guard data.count == metadata.byteCount else { throw FileTransferError.changedFile }
        return DemoTransfer(kind: metadata.kind, bytes: data, name: metadata.name)
    }
}

public enum OutgoingItem {
    case inline(DemoTransfer)
    case file(TransferFile)
}

func checkTransferDisk(_ directory: URL, bytes: Int64) throws {
    let values = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
    guard let free = (values[.systemFreeSize] as? NSNumber)?.int64Value,
          bytes > 0, bytes <= FileTransferLimits.maximumBytes,
          free >= bytes + FileTransferLimits.diskReserve else { throw FileTransferError.diskFull }
}

/// Thread-safe cancellation for provider callbacks and file preparation.
public final class TransferCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public func cancel() { lock.lock(); value = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

// Advisory leases identify app-owned incomplete transfers. An interrupted process
// releases its lease automatically; the next transfer removes that orphan. Active
// snapshots remain protected even when two app processes share the temporary root.
func makeTransferDirectory(_ root: URL) throws -> (URL, FileHandle) {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let rootValues = try root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
    guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { throw FileTransferError.storage }
    let rootFD = open(root.appendingPathComponent(".lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard rootFD >= 0 else { throw FileTransferError.storage }
    defer { close(rootFD) }
    guard flock(rootFD, LOCK_EX) == 0 else { throw FileTransferError.storage }
    for child in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
        guard UUID(uuidString: child.lastPathComponent) != nil,
              let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { continue }
        let fd = open(child.appendingPathComponent(".lease").path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        if fd >= 0 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { try? FileManager.default.removeItem(at: child) }
            close(fd)
        }
    }
    let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let fd = open(directory.appendingPathComponent(".lease").path, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { try? FileManager.default.removeItem(at: directory); throw FileTransferError.storage }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
        close(fd); try? FileManager.default.removeItem(at: directory); throw FileTransferError.storage
    }
    return (directory, FileHandle(fileDescriptor: fd, closeOnDealloc: true))
}
