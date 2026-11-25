#if canImport(Network) && canImport(Security)
import Foundation
import Network
import CryptoKit
import Darwin
import XCTest
@testable import ClipboardDemoTransport

final class FileStreamTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CaptureArc-StreamTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func invitation() -> DemoInvitation {
        DemoInvitation(service: UUID(), key: Data(repeating: 57, count: 32), untilStopped: true).supportingFiles()
    }
    private func fixture(_ bytes: Int64, name: String = "synthetic-export.txt") throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString + "-" + name)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: UInt64(bytes))
        // Sparse fixture with distinct data at both ends and in the middle.
        for offset in [Int64(0), bytes / 2, bytes - 64] where offset >= 0 {
            try file.seek(toOffset: UInt64(offset))
            try file.write(contentsOf: Data(repeating: UInt8(offset % 251), count: Int(min(64, bytes - offset))))
        }
        if name.hasSuffix(".wav") {
            try file.seek(toOffset: 0)
            var header = Data("RIFF".utf8)
            func word<T: FixedWidthInteger>(_ value: T) { var le = value.littleEndian; withUnsafeBytes(of: &le) { header.append(contentsOf: $0) } }
            word(UInt32(bytes - 8)); header.append(Data("WAVEfmt ".utf8))
            word(UInt32(16)); word(UInt16(1)); word(UInt16(1)); word(UInt32(48_000)); word(UInt32(96_000))
            word(UInt16(2)); word(UInt16(16)); header.append(Data("data".utf8)); word(UInt32(bytes - 44))
            try file.write(contentsOf: header)
        }
        try file.close(); return url
    }
    private func digest(_ url: URL) throws -> Data {
        let reader = try FileHandle(forReadingFrom: url); defer { try? reader.close() }
        var sha = SHA256()
        while try autoreleasepool(invoking: {
            guard let data = try reader.read(upToCount: FileTransferLimits.chunkBytes), !data.isEmpty else { return false }
            sha.update(data: data); return true
        }) {}
        return Data(sha.finalize())
    }
    private func transfer(_ size: Int64, name: String = "export.txt") throws {
        let invite = invitation(), receiver = try DemoReceiver(invitation: invite, loopback: true), sender = DemoSender()
        defer { receiver.stop(); sender.cancel() }
        let source = try fixture(size, name: name)
        let expected = try digest(source)
        let file = try TransferFile.prepare(source, name: name, invitation: invite)
        let ready = expectation(description: "receiver ready"), saved = expectation(description: "saved"), ack = expectation(description: "ACK")
        let destination = root.appendingPathComponent("saved-" + UUID().uuidString)
        var lastProgress: Int64 = 0
        receiver.start(status: { if $0 == CaptureArcText.value("Ready to receive") { ready.fulfill() } },
                       files: FileReceiveOptions(directory: root.appendingPathComponent("partial"), admit: { _, reply in reply(true) }, save: { incoming, reply in
            do {
                XCTAssertEqual(incoming.metadata.byteCount, size)
                XCTAssertEqual(incoming.metadata.kind, .file)
                XCTAssertEqual(try self.digest(incoming.url), expected)
                try FileManager.default.moveItem(at: incoming.url, to: destination)
                saved.fulfill(); reply(.success(()))
            } catch { XCTFail(String(describing: error)); reply(.failure(error)) }
        }), intake: { _, reply in XCTFail("Used legacy payload for a stream"); reply(false) })
        wait(for: [ready], timeout: 5)
        sender.transmit(file, invitation: invite, loopbackPort: try XCTUnwrap(receiver.boundPort), progress: { value in
            XCTAssertGreaterThanOrEqual(value.completed, lastProgress)
            XCTAssertLessThanOrEqual(value.completed, size)
            lastProgress = value.completed
        }) { result in
            if case .failure(let error) = result { XCTFail(String(describing: error)) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path), "ACK preceded saved data")
            ack.fulfill()
        }
        wait(for: [saved, ack], timeout: 180)
        XCTAssertEqual(lastProgress, size)
        XCTAssertEqual(try digest(destination), expected)
    }
    func testOrphanedPartialsAreCleanedButLiveLeasesSurvive() throws {
        let partial = root.appendingPathComponent("partial")
        let (abandoned, lease) = try makeTransferDirectory(partial)
        try Data("Synthetic interrupted file".utf8).write(to: abandoned.appendingPathComponent("partial.txt"))
        let (live, liveLease) = try makeTransferDirectory(partial)
        XCTAssertTrue(FileManager.default.fileExists(atPath: abandoned.path))
        try lease.close() // Models the OS closing descriptors after a process dies.
        let (next, nextLease) = try makeTransferDirectory(partial)
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: live.path))
        try liveLease.close(); try nextLease.close()
        try FileManager.default.removeItem(at: next)
    }
    func testFileOverTenMiBIsStreamedIntact() throws { try transfer(11 * 1024 * 1024 + 17) }
    func testInclusiveOneGiBBoundaryAndHourLikeExport() throws {
        guard ProcessInfo.processInfo.environment["CAPTUREARC_LARGE_FILE_TESTS"] == "1" else {
            throw XCTSkip("Set CAPTUREARC_LARGE_FILE_TESTS=1 to exercise 2.3 GiB of synthetic transfers")
        }
        var before = rusage(); getrusage(RUSAGE_SELF, &before)
        // PCM-equivalent payload: 48 kHz, 16-bit mono, 3,600 seconds.
        try transfer(48_000 * 2 * 3_600 + 44, name: "synthetic-hour-audio.wav")
        try transfer(FileTransferLimits.maximumBytes - 1, name: "near-limit.backup")
        try transfer(FileTransferLimits.maximumBytes, name: "exact-limit.zip")
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        print("Synthetic large-file suite process peak RSS bytes: \(usage.ru_maxrss); increase: \(usage.ru_maxrss - before.ru_maxrss)")
        XCTAssertLessThan(usage.ru_maxrss - before.ru_maxrss, 64 * 1024 * 1024, "Large-file path accumulated payload buffers")
    }
    func testOverCapAndInvalidLengthsRejectedBeforeSnapshot() throws {
        for size: Int64 in [-1, 0, FileTransferLimits.maximumBytes + 1, Int64.max] {
            XCTAssertThrowsError(try FileTransferMetadata(kind: .file, name: "export.txt", byteCount: size).check())
        }
        let source = try fixture(FileTransferLimits.maximumBytes + 1)
        XCTAssertThrowsError(try TransferFile.prepare(source, invitation: invitation())) {
            XCTAssertEqual($0 as? FileTransferError, .tooLarge)
        }
        XCTAssertNoThrow(try FileTransferMetadata(kind: .file, name: "a.txt", byteCount: FileTransferLimits.maximumBytes).check())
    }
    func testOldPairingRequiresUpgradeForLargeFileWithoutNetwork() throws {
        let old = DemoInvitation(service: UUID(), key: Data(repeating: 1, count: 32), untilStopped: true)
        let source = try fixture(11 * 1024 * 1024)
        XCTAssertThrowsError(try TransferFile.prepare(source, invitation: old)) { XCTAssertEqual($0 as? FileTransferError, .upgrade) }
        let file = try TransferFile.prepare(source)
        let finished = expectation(description: "preflight upgrade")
        DemoSender().transmit(file, invitation: old, loopbackPort: nil) { result in
            if case .failure(let error) = result { XCTAssertEqual(error as? FileTransferError, .upgrade) }
            else { XCTFail("Large file sent to an old peer") }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)
        let oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old.supportingFiles())) as! [String: Any]
        XCTAssertEqual(oldJSON["fileProtocol"] as? Int, 3)
        XCTAssertEqual(try DemoInvitation.parse(old.supportingFiles().pasteCode()).service, old.service)
    }
    func testNewSenderSmallFileToLegacyReceiver() throws {
        let invite = DemoInvitation(service: UUID(), key: Data(repeating: 2, count: 32), untilStopped: true)
        let receiver = try DemoReceiver(invitation: invite, loopback: true), sender = DemoSender()
        defer { receiver.stop(); sender.cancel() }
        let ready = expectation(description: "ready"), ack = expectation(description: "legacy ACK")
        let file = try TransferFile.prepare(fixture(4096), name: "small.txt", invitation: invite)
        receiver.start(status: { if $0 == CaptureArcText.value("Ready to receive") { ready.fulfill() } }, intake: { item, reply in
            XCTAssertEqual(item.kind, .file); XCTAssertEqual(item.name, "small.txt"); XCTAssertEqual(item.bytes.count, 4096); reply(true)
        })
        wait(for: [ready], timeout: 5)
        sender.transmit(file, invitation: invite, loopbackPort: receiver.boundPort) { result in
            if case .failure(let error) = result { XCTFail(String(describing: error)) }; ack.fulfill()
        }
        wait(for: [ack], timeout: 5)
    }
    func testFailedSaveNeverAcknowledgesSuccessAndRemovesPartial() throws {
        try rejectedTransfer(admit: true, saveError: .storage, expected: .storage)
    }
    func testFullShelfRejectsBeforeContents() throws {
        try rejectedTransfer(admit: false, saveError: nil, expected: .shelfFull)
    }
    private func rejectedTransfer(admit: Bool, saveError: FileTransferError?, expected: FileTransferError) throws {
        let invite = invitation(), receiver = try DemoReceiver(invitation: invite, loopback: true), sender = DemoSender()
        defer { receiver.stop(); sender.cancel() }
        let file = try TransferFile.prepare(fixture(11 * 1024 * 1024), invitation: invite)
        let ready = expectation(description: "ready"), ack = expectation(description: "rejected")
        let partial = root.appendingPathComponent("partial")
        receiver.start(status: { if $0 == CaptureArcText.value("Ready to receive") { ready.fulfill() } }, files: FileReceiveOptions(directory: partial, admit: { _, reply in reply(admit) }, save: { _, reply in
            reply(.failure(saveError ?? FileTransferError.storage))
        }), intake: { _, reply in reply(false) })
        wait(for: [ready], timeout: 5)
        sender.transmit(file, invitation: invite, loopbackPort: receiver.boundPort) { result in
            if case .failure(let error) = result { XCTAssertEqual(error as? FileTransferError, expected) }
            else { XCTFail("Rejected file acknowledged") }; ack.fulfill()
        }
        wait(for: [ack], timeout: 10)
        assertClean(partial)
    }
    func testPreflightDiskFullAndMidWriteDiskFullCleanUp() throws {
        for beforeContent in [true, false] {
            let invite = invitation(), receiver = try DemoReceiver(invitation: invite, loopback: true), sender = DemoSender()
            defer { receiver.stop(); sender.cancel() }
            let file = try TransferFile.prepare(fixture(11 * 1024 * 1024), invitation: invite)
            let ready = expectation(description: "ready"), rejected = expectation(description: "disk failure")
            let partial = root.appendingPathComponent(UUID().uuidString)
            var options = FileReceiveOptions(directory: partial, admit: { _, reply in reply(true) }, save: { _, reply in
                XCTFail("Disk failure reached shelf commit"); reply(.failure(FileTransferError.storage))
            })
            if beforeContent { options.diskCheck = { _, _ in throw FileTransferError.diskFull } }
            else { options.writeChunk = { _, _ in throw NSError(domain: NSPOSIXErrorDomain, code: 28) } }
            receiver.start(status: { if $0 == CaptureArcText.value("Ready to receive") { ready.fulfill() } }, files: options, intake: { _, reply in reply(false) })
            wait(for: [ready], timeout: 5)
            sender.transmit(file, invitation: invite, loopbackPort: receiver.boundPort) { result in
                if case .success = result { XCTFail("Out-of-space transfer succeeded") }
                if beforeContent, case .failure(let error) = result { XCTAssertEqual(error as? FileTransferError, .diskFull) }
                rejected.fulfill()
            }
            wait(for: [rejected], timeout: 5); assertClean(partial)
        }
    }
    func testChangedPreparedFileDoesNotCommit() throws {
        let invite = invitation(), receiver = try DemoReceiver(invitation: invite, loopback: true), sender = DemoSender()
        defer { receiver.stop(); sender.cancel() }
        let file = try TransferFile.prepare(fixture(11 * 1024 * 1024), invitation: invite)
        let writer = try FileHandle(forWritingTo: file.url); try writer.truncate(atOffset: 1024); try writer.close()
        let ready = expectation(description: "ready"), failed = expectation(description: "truncated source")
        let partial = root.appendingPathComponent("partial")
        receiver.start(status: { if $0 == CaptureArcText.value("Ready to receive") { ready.fulfill() } }, files: FileReceiveOptions(directory: partial, admit: { _, reply in reply(true) }, save: { _, reply in
            XCTFail("Truncated source was committed"); reply(.success(()))
        }), intake: { _, reply in reply(false) })
        wait(for: [ready], timeout: 5)
        sender.transmit(file, invitation: invite, loopbackPort: receiver.boundPort) { result in
            if case .failure(let error) = result { XCTAssertEqual(error as? FileTransferError, .changedFile) }
            else { XCTFail("Changed source succeeded") }; failed.fulfill()
        }
        wait(for: [failed], timeout: 5); assertClean(partial)
    }
    func testCorruptDigestOverCapHeaderAndIdlePeerCannotCommit() throws {
        for mode in ["digest", "oversize", "idle"] {
            let invite = invitation(), receiver = try DemoReceiver(invitation: invite, loopback: true)
            defer { receiver.stop() }
            let ready = expectation(description: "ready"), failed = expectation(description: "rejected " + mode)
            let partial = root.appendingPathComponent(UUID().uuidString)
            var options = FileReceiveOptions(directory: partial, admit: { _, reply in reply(true) }, save: { _, reply in
                XCTFail("Invalid stream was committed"); reply(.success(()))
            })
            options.idleTimeout = 1
            receiver.start(status: { if $0 == CaptureArcText.value("Ready to receive") { ready.fulfill() } }, files: options, intake: { _, reply in reply(false) })
            wait(for: [ready], timeout: 5)
            let link = NWConnection(to: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(receiver.boundPort)), using: demoParameters(invite, loopback: true))
            let queue = DispatchQueue(label: "capturearc.raw-test")
            let client = FileStreamSession(link: link, queue: queue) { _ in failed.fulfill() }
            link.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                client.send(FileTransferLimits.magic) {
                    let count = mode == "oversize" ? FileTransferLimits.maximumBytes + 1 : 1024
                    client.sendJSON(FileTransferMetadata(kind: .file, name: "synthetic.txt", byteCount: count)) {
                        client.readJSON(FileStreamReply.self) { admission in
                            if mode == "oversize" {
                                XCTAssertEqual(admission.error, .tooLarge); client.finish(.failure(FileTransferError.tooLarge)); return
                            }
                            XCTAssertNil(admission.error)
                            if mode == "idle" {
                                client.readJSON(FileStreamReply.self) { _ in XCTFail("Idle stream succeeded") }
                            } else {
                                client.send(Data(repeating: 1, count: 1024) + Data(repeating: 0, count: 32)) {
                                    client.readJSON(FileStreamReply.self) { response in
                                        XCTAssertEqual(response.error, .integrity)
                                        client.finish(.failure(FileTransferError.integrity))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            client.arm(); link.start(queue: queue)
            wait(for: [failed], timeout: 5); assertClean(partial)
        }
    }

    private func assertClean(_ directory: URL) {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if (try? FileManager.default.contentsOfDirectory(atPath: directory.path).filter { UUID(uuidString: $0) != nil }.isEmpty) ?? true { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTFail("Partial file survived terminal failure")
    }
    func testCancelMidFileRemovesPartialAndAllowsNextTransfer() throws {
        let invite = invitation(), receiver = try DemoReceiver(invitation: invite, loopback: true), sender = DemoSender()
        defer { receiver.stop(); sender.cancel() }
        let file = try TransferFile.prepare(fixture(32 * 1024 * 1024), invitation: invite)
        let ready = expectation(description: "ready"), cancelled = expectation(description: "cancelled")
        let partial = root.appendingPathComponent("partial")
        receiver.start(status: { if $0 == CaptureArcText.value("Ready to receive") { ready.fulfill() } }, files: FileReceiveOptions(directory: partial, admit: { _, reply in reply(true) }, save: { _, reply in
            XCTFail("Cancelled transfer reached save"); reply(.success(()))
        }), intake: { _, reply in reply(true) })
        wait(for: [ready], timeout: 5)
        sender.transmit(file, invitation: invite, loopbackPort: receiver.boundPort, progress: { _ in sender.cancel() }) { result in
            if case .success = result { XCTFail("Cancelled transfer succeeded") }; cancelled.fulfill()
        }
        wait(for: [cancelled], timeout: 5)
        assertClean(partial)
        let small = expectation(description: "still paired")
        sender.transmit(DemoTransfer(kind: .text, bytes: Data("synthetic after cancellation".utf8)), invitation: invite, loopbackPort: receiver.boundPort) { result in
            if case .failure(let error) = result { XCTFail(String(describing: error)) }; small.fulfill()
        }
        wait(for: [small], timeout: 5)
    }
}
#endif
