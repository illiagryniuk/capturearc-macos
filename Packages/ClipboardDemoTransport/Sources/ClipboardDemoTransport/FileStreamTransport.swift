#if canImport(Network) && canImport(Security)
import Foundation
import CryptoKit
import Network

public struct FileReceiveOptions {
    var diskCheck: (URL, Int64) throws -> Void = checkTransferDisk
    var idleTimeout = FileTransferLimits.idleTimeout
    var writeChunk: (FileHandle, Data) throws -> Void = { try $0.write(contentsOf: $1) }
    public let directory: URL
    public let admit: (FileTransferMetadata, @escaping (Bool) -> Void) -> Void
    public let save: (TransferFile, @escaping (Result<Void, Error>) -> Void) -> Void
    public let progress: (FileTransferProgress?) -> Void
    public let failure: (Error) -> Void
    public init(directory: URL,
                admit: @escaping (FileTransferMetadata, @escaping (Bool) -> Void) -> Void,
                save: @escaping (TransferFile, @escaping (Result<Void, Error>) -> Void) -> Void,
                progress: @escaping (FileTransferProgress?) -> Void = { _ in },
                failure: @escaping (Error) -> Void = { _ in }) {
        self.directory = directory; self.admit = admit; self.save = save
        self.progress = progress; self.failure = failure
    }
}

struct FileStreamReply: Codable {
    var version = FileTransferLimits.version
    var maximumBytes = FileTransferLimits.maximumBytes
    var chunkBytes = FileTransferLimits.chunkBytes
    var error: FileTransferError?
    func check() throws {
        if let error { throw error }
        guard version == FileTransferLimits.version,
              maximumBytes == FileTransferLimits.maximumBytes,
              chunkBytes == FileTransferLimits.chunkBytes else { throw FileTransferError.protocolMismatch }
    }
}

// One connection, one bounded chunk in flight. All mutable state is queue-confined.
class FileStreamSession {
    let link: NWConnection
    let queue: DispatchQueue
    var ended = false
    var lastActivity = ProcessInfo.processInfo.systemUptime
    let started = ProcessInfo.processInfo.systemUptime
    var timer: DispatchSourceTimer?
    var completion: ((Result<Void, Error>) -> Void)?
    var idleTimeout = FileTransferLimits.idleTimeout
    init(link: NWConnection, queue: DispatchQueue, completion: @escaping (Result<Void, Error>) -> Void) {
        self.link = link; self.queue = queue; self.completion = completion
    }
    func arm() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if now - self.lastActivity >= self.idleTimeout || now - self.started >= FileTransferLimits.sessionTimeout {
                self.finish(.failure(DemoWireError.deadline))
            }
        }
        self.timer = timer; timer.resume()
    }
    func finish(_ result: Result<Void, Error>) {
        guard !ended else { return }; ended = true
        timer?.cancel(); timer = nil
        link.stateUpdateHandler = nil; link.cancel()
        let done = completion; completion = nil; done?(result)
    }
    func send(_ data: Data, then: @escaping () -> Void) {
        guard !ended else { return }
        link.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, !self.ended else { return }
            if let error { self.finish(.failure(error)); return }
            self.lastActivity = ProcessInfo.processInfo.systemUptime
            then()
        })
    }
    func read(_ count: Int, then: @escaping (Data) -> Void) {
        guard !ended, count > 0, count <= FileTransferLimits.chunkBytes else { return }
        link.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] data, _, _, error in
            guard let self, !self.ended else { return }
            if let error { self.finish(.failure(error)); return }
            guard let data, data.count == count else { self.finish(.failure(DemoWireError.badFrame)); return }
            self.lastActivity = ProcessInfo.processInfo.systemUptime
            then(data)
        }
    }
    func sendJSON<T: Encodable>(_ value: T, then: @escaping () -> Void) {
        do {
            let data = try JSONEncoder().encode(value)
            guard !data.isEmpty, data.count <= 4096 else { throw DemoWireError.badFrame }
            var length = UInt32(data.count).bigEndian
            var packet = withUnsafeBytes(of: &length) { Data($0) }; packet.append(data)
            send(packet, then: then)
        } catch { finish(.failure(error)) }
    }
    func readJSON<T: Decodable>(_ type: T.Type, then: @escaping (T) -> Void) {
        read(4) { [self] header in
            let count = header.reduce(0) { ($0 << 8) | Int($1) }
            guard count > 0, count <= 4096 else { finish(.failure(DemoWireError.badFrame)); return }
            read(count) { [self] data in
                do { then(try JSONDecoder().decode(type, from: data)) }
                catch { finish(.failure(error)) }
            }
        }
    }
}

final class FileReceiveSession: FileStreamSession {
    let options: FileReceiveOptions
    var file: TransferFile?
    var writer: FileHandle?
    var count: Int64 = 0
    var hash = SHA256()
    var acknowledged = false
    var admissionError: FileTransferError?
    init(link: NWConnection, queue: DispatchQueue, options: FileReceiveOptions,
         completion: @escaping (Result<Void, Error>) -> Void) {
        self.options = options
        super.init(link: link, queue: queue, completion: completion)
        idleTimeout = options.idleTimeout
    }
    func begin() {
        arm()
        readJSON(FileTransferMetadata.self) { [self] metadata in
            do { try metadata.check() } catch { reject(error); return }
            if let admissionError { reject(admissionError); return }
            options.admit(metadata) { [weak self] allowed in
                guard let self else { return }
                self.queue.async { [self] in
                    guard !self.ended else { return }
                    guard allowed else { self.reject(FileTransferError.shelfFull); return }
                    do {
                        try FileManager.default.createDirectory(at: self.options.directory, withIntermediateDirectories: true,
                                                                attributes: [.posixPermissions: 0o700])
                        let (directory, lease) = try makeTransferDirectory(self.options.directory)
                        let url = directory.appendingPathComponent(metadata.name)
                        let staged = TransferFile(url: url, metadata: metadata, directory: directory, lease: lease)
                        self.file = staged
                        try self.options.diskCheck(self.options.directory, metadata.byteCount)
                        guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                                            attributes: [.posixPermissions: 0o600]) else { throw FileTransferError.storage }
                        self.writer = try FileHandle(forWritingTo: url)
                        self.options.progress(.init(completed: 0, total: metadata.byteCount))
                        self.sendJSON(FileStreamReply()) { [self] in self.receiveChunk() }
                    } catch { self.reject(error) }
                }
            }
        }
    }
    func receiveChunk() {
        guard let file, !ended else { return }
        let remaining = file.metadata.byteCount - count
        if remaining == 0 {
            read(32) { [self] digest in
                guard digest == Data(hash.finalize()) else { reject(FileTransferError.integrity); return }
                do { try writer?.synchronize(); try writer?.close(); writer = nil }
                catch { reject(error); return }
                options.save(file) { [weak self] result in
                    guard let self else { return }
                    self.queue.async { [self] in
                        guard !self.ended else { return }
                        switch result {
                        case .success: self.reply(nil)
                        case .failure(let error): self.reject(error)
                        }
                    }
                }
            }
            return
        }
        read(Int(min(Int64(FileTransferLimits.chunkBytes), remaining))) { [self] data in
            do {
                guard let writer else { throw FileTransferError.storage }
                try options.writeChunk(writer, data)
            } catch { reject(error); return }
            hash.update(data: data); count += Int64(data.count)
            options.progress(.init(completed: count, total: file.metadata.byteCount))
            receiveChunk()
        }
    }
    func reject(_ error: Error) {
        options.failure(error)
        let cocoa = error as NSError
        let noSpace = (cocoa.domain == NSPOSIXErrorDomain && cocoa.code == Int(ENOSPC)) ||
            (cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSFileWriteOutOfSpaceError)
        reply(error as? FileTransferError ?? (noSpace ? .diskFull : .storage))
    }
    func reply(_ error: FileTransferError?) {
        guard !ended else { return }
        acknowledged = error == nil
        sendJSON(FileStreamReply(error: error)) { [self] in
            // Preserve the established ACK lifecycle: peer must read the final
            // reply before we close. The idle timer also bounds a silent peer.
            options.progress(nil)
            link.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
                guard let self, !self.ended else { return }
                self.link.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, _, _ in
                    self?.finish(error.map { .failure($0) } ?? .success(()))
                }
            })
        }
    }
    override func finish(_ result: Result<Void, Error>) {
        guard !ended else { return }
        if !acknowledged { file?.cancellation.cancel() }
        try? writer?.close(); writer = nil; file = nil
        options.progress(nil)
        if case .failure(let error) = result { options.failure(error) }
        super.finish(result)
    }
}

final class FileSendSession: FileStreamSession {
    let file: TransferFile
    let progress: (FileTransferProgress) -> Void
    var reader: FileHandle?
    var count: Int64 = 0
    var hash = SHA256()
    init(link: NWConnection, queue: DispatchQueue, file: TransferFile,
         progress: @escaping (FileTransferProgress) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        self.file = file; self.progress = progress
        super.init(link: link, queue: queue, completion: completion)
    }
    func begin() {
        do { try file.metadata.check(); reader = try FileHandle(forReadingFrom: file.url) }
        catch { finish(.failure(error)); return }
        send(FileTransferLimits.magic) { [self] in
            sendJSON(file.metadata) { [self] in
                readJSON(FileStreamReply.self) { [self] response in
                    do { try response.check() } catch { finish(.failure(error)); return }
                    sendChunk()
                }
            }
        }
    }
    func sendChunk() {
        guard !ended else { return }
        do {
            let remaining = file.metadata.byteCount - count
            if remaining == 0 {
                guard (try reader?.read(upToCount: 1) ?? Data()).isEmpty else { throw FileTransferError.changedFile }
                try reader?.close(); reader = nil
                send(Data(hash.finalize())) { [self] in
                    readJSON(FileStreamReply.self) { [self] response in
                        do { try response.check(); finish(.success(())) }
                        catch { finish(.failure(error)) }
                    }
                }
                return
            }
            let data = try reader?.read(upToCount: Int(min(Int64(FileTransferLimits.chunkBytes), remaining))) ?? Data()
            guard !data.isEmpty else { throw FileTransferError.changedFile }
            hash.update(data: data)
            send(data) { [self] in
                count += Int64(data.count)
                progress(.init(completed: count, total: file.metadata.byteCount))
                sendChunk()
            }
        } catch { finish(.failure(error)) }
    }
    override func finish(_ result: Result<Void, Error>) {
        try? reader?.close(); reader = nil
        super.finish(result)
    }
}

extension DemoSender {
    public func transmit(_ item: OutgoingItem, invitation: DemoInvitation,
                         progress: @escaping (FileTransferProgress) -> Void = { _ in },
                         completion: @escaping (Result<Void, Error>) -> Void) {
        switch item {
        case .inline(let item): transmit(item, invitation: invitation, completion: completion)
        case .file(let file): transmit(file, invitation: invitation, loopbackPort: nil, progress: progress, completion: completion)
        }
    }

    func transmit(_ file: TransferFile, invitation: DemoInvitation, loopbackPort: NWEndpoint.Port?,
                  progress: @escaping (FileTransferProgress) -> Void = { _ in },
                  completion: @escaping (Result<Void, Error>) -> Void) {
        // Old QR codes deliberately use the old protocol. The advertised capability
        // is confirmed again inside TLS before any file content is transmitted.
        if invitation.fileProtocol != FileTransferLimits.version {
            do { try transmit(file.legacy(), invitation: invitation, loopbackPort: loopbackPort, completion: completion) }
            catch { completion(.failure(error)) }
            return
        }
        queue.async { [self] in
            guard active == nil else { completion(.failure(DemoWireError.busy)); return }
            guard invitation.key.count == 32, invitation.isValid() else { completion(.failure(DemoWireError.badInvite)); return }
            let endpoint: NWEndpoint = loopbackPort.map { .hostPort(host: "127.0.0.1", port: $0) } ??
                .service(name: invitation.service.uuidString, type: DemoInvitation.serviceType, domain: "local.", interface: nil)
            let link = NWConnection(to: endpoint, using: demoParameters(invitation, loopback: loopbackPort != nil))
            let session = FileSendSession(link: link, queue: queue, file: file, progress: progress) { [weak self, weak link] result in
                guard let self, let link, self.active === link else { return }
                self.active = nil; self.cancelActive = nil
                completion(result)
            }
            active = link
            cancelActive = { session.finish(.failure(DemoWireError.cancelled)) }
            link.stateUpdateHandler = { [weak session] state in
                guard let session, !session.ended else { return }
                switch state {
                case .ready:
                    guard negotiatedDemoTLS(link), invitation.isValid() else { session.finish(.failure(DemoWireError.rejected)); return }
                    session.begin()
                case .failed(let error): session.finish(.failure(error))
                case .cancelled: session.finish(.failure(DemoWireError.cancelled))
                default: break
                }
            }
            session.arm(); link.start(queue: queue)
        }
    }
}
#endif
