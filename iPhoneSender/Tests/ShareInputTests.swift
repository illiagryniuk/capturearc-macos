@testable import ClipboardDemoTransport
import CryptoKit
import Network
import Darwin
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import CaptureArcSender

final class ShareInputTests: XCTestCase {
    func testPairedWiFiPathDiagnostic() async throws {
        guard Bundle(for: Self.self).url(forResource: "CaptureArc-QA-Pairing", withExtension: "txt") != nil else {
            throw XCTSkip("Optional paired QA diagnostic")
        }
        let result: String = await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
            let queue = DispatchQueue(label: "capturearc.synthetic.path")
            var finished = false
            let finish: (String) -> Void = { message in
                guard !finished else { return }; finished = true
                monitor.cancel(); continuation.resume(returning: message)
            }
            monitor.pathUpdateHandler = { path in
                finish("status=\(path.status), reason=\(path.unsatisfiedReason), wifi=\(path.usesInterfaceType(.wifi)), interfaces=\(path.availableInterfaces.map { String(describing: $0.type) }.joined(separator: ","))")
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 5) { finish("no path update within 5 seconds") }
        }
        print("Synthetic paired Wi-Fi path: \(result)")
        let code = try String(contentsOf: Bundle(for: Self.self).url(forResource: "CaptureArc-QA-Pairing", withExtension: "txt")!, encoding: .utf8)
        let invitation = try DemoInvitation.parse(code)
        let connectionResult: String = await withCheckedContinuation { continuation in
            let link = NWConnection(to: .service(name: invitation.service.uuidString, type: DemoInvitation.serviceType, domain: "local.", interface: nil), using: demoParameters(invitation))
            let queue = DispatchQueue(label: "capturearc.synthetic.connection")
            var finished = false
            var stateDescription = "setup"
            let finish: (String) -> Void = { message in
                guard !finished else { return }; finished = true
                link.stateUpdateHandler = nil; link.cancel(); continuation.resume(returning: message)
            }
            link.stateUpdateHandler = { state in
                switch state {
                case .ready: finish("ready; expected authenticated TLS=\(negotiatedDemoTLS(link))")
                case .waiting(let error): stateDescription = "waiting: \(error)"
                case .failed(let error): finish("failed: \(error)")
                default: break
                }
            }
            link.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 5) { finish(stateDescription) }
        }
        print("Synthetic paired authenticated endpoint: \(connectionResult)")
    }

    // Optional device/simulator integration test. The private pairing resource is
    // injected into the signed test bundle locally, never into the shipping app.
    func testPairedReceiverThroughShareProvider() async throws {
        guard let config = Bundle(for: Self.self).url(forResource: "CaptureArc-QA-Pairing", withExtension: "txt") else {
            throw XCTSkip("Requires an isolated QA receiver and private test-bundle pairing resource")
        }
        let invitation = try DemoInvitation.parse(String(contentsOf: config, encoding: .utf8))
        let sender = DemoSender()
        func send(_ provider: NSItemProvider, label: String) async throws {
            let item = try await SharedItemLoader.loadOutgoing(provider, invitation: invitation)
            if case .file(let file) = item {
                let reader = try FileHandle(forReadingFrom: file.url)
                var hash = SHA256()
                while true {
                    let more = try autoreleasepool { () throws -> Bool in
                        let data = try reader.read(upToCount: FileTransferLimits.chunkBytes) ?? Data()
                        if data.isEmpty { return false }; hash.update(data: data); return true
                    }
                    if !more { break }
                }
                try reader.close()
                let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
                print("Synthetic paired source: \(label), bytes=\(file.metadata.byteCount), SHA256=\(digest)")
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sender.transmit(item, invitation: invitation) { continuation.resume(with: $0) }
            }
            print("Synthetic paired saved-file ACK: \(label)")
        }
        try await send(NSItemProvider(object: "Synthetic selected text — paired QA" as NSString), label: "selected text")
        try await send(NSItemProvider(object: URL(string: "https://example.com/capturearc-synthetic-qa")! as NSURL), label: "link")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PairedSynthetic-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Deterministic noisy pixels produce a real PNG larger than 1 MiB.
        var pixels = [UInt8](repeating: 0, count: 1024 * 1024 * 4)
        var seed: UInt32 = 12345
        for index in stride(from: 0, to: pixels.count, by: 4) {
            for channel in 0..<3 { seed = 1664525 &* seed &+ 1013904223; pixels[index + channel] = UInt8(truncatingIfNeeded: seed >> 24) }
            pixels[index + 3] = 255
        }
        let bitmap = CGDataProvider(data: Data(pixels) as CFData)!
        let cg = CGImage(width: 1024, height: 1024, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4096,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                         provider: bitmap, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let png = try XCTUnwrap(UIImage(cgImage: cg).pngData())
        XCTAssertGreaterThan(png.count, 1024 * 1024)
        let photo = directory.appendingPathComponent("synthetic-photo-over-1MiB.png")
        try png.write(to: photo)
        try await send(try XCTUnwrap(NSItemProvider(contentsOf: photo)), label: photo.lastPathComponent)
        for (name, size) in [("synthetic-transcript-11MiB.txt", Int64(11 * 1024 * 1024 + 17)),
                              ("synthetic-hour-48k.wav", Int64(345600044)),
                              ("synthetic-exact-1GiB.vtbackup", FileTransferLimits.maximumBytes)] {
            let url = directory.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let writer = try FileHandle(forWritingTo: url)
            try writer.truncate(atOffset: UInt64(size))
            if name.hasSuffix(".wav") {
                var header = Data("RIFF".utf8)
                func append<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
                append(UInt32(size - 8)); header.append(Data("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
                append(UInt32(48000)); append(UInt32(96000)); append(UInt16(2)); append(UInt16(16)); header.append(Data("data".utf8)); append(UInt32(size - 44))
                try writer.write(contentsOf: header)
            }
            try writer.close()
            try await send(try XCTUnwrap(NSItemProvider(contentsOf: url)), label: name)
        }
    }

    private var fileInvitation: DemoInvitation {
        DemoInvitation(service: UUID(), key: Data(repeating: 8, count: 32), untilStopped: true).supportingFiles()
    }
    private func selectedItem(_ provider: NSItemProvider) async throws -> DemoTransfer {
        let item = try await SharedItemLoader.loadOutgoing(provider, invitation: fileInvitation)
        guard case .inline(let value) = item else { XCTFail("Selected text/link became a document"); throw DemoWireError.badFrame }
        return value
    }
    func testExactOneGiBThroughRealFileProviderWithBoundedSnapshot() async throws {
        try await verifyOneGiBProvider(explicitFile: false)
        try await verifyOneGiBProvider(explicitFile: true)
    }
    private func verifyOneGiBProvider(explicitFile: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(FileTransferLimits.maximumBytes)); try handle.close()
        defer { try? FileManager.default.removeItem(at: url) }
        let provider: NSItemProvider
        if explicitFile {
            provider = NSItemProvider(); provider.suggestedName = "synthetic.txt"
            provider.registerFileRepresentation(forTypeIdentifier: UTType.plainText.identifier, fileOptions: [], visibility: .all) { done in
                done(url, false, nil); return nil
            }
        } else { provider = try XCTUnwrap(NSItemProvider(contentsOf: url)) }
        var before = rusage(); getrusage(RUSAGE_SELF, &before)
        let item = try await SharedItemLoader.loadOutgoing(provider, invitation: fileInvitation)
        guard case .file(let file) = item else { XCTFail("Large text export became inline text"); return }
        XCTAssertEqual(file.metadata.byteCount, FileTransferLimits.maximumBytes)
        var expected = SHA256(), actual = SHA256()
        let zeroChunk = Data(repeating: 0, count: FileTransferLimits.chunkBytes)
        let reader = try FileHandle(forReadingFrom: file.url); defer { try? reader.close() }
        for _ in 0..<(Int(FileTransferLimits.maximumBytes) / FileTransferLimits.chunkBytes) {
            try autoreleasepool {
                expected.update(data: zeroChunk)
                actual.update(data: try XCTUnwrap(reader.read(upToCount: FileTransferLimits.chunkBytes)))
            }
        }
        XCTAssertEqual(Data(expected.finalize()), Data(actual.finalize()))
        XCTAssertTrue((try reader.read(upToCount: 1) ?? Data()).isEmpty)
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        print("Synthetic iOS 1 GiB provider (explicit file: \(explicitFile)) process peak RSS bytes: \(usage.ru_maxrss); increase: \(usage.ru_maxrss - before.ru_maxrss)")
        XCTAssertLessThan(usage.ru_maxrss - before.ru_maxrss, 64 * 1024 * 1024, "Provider import accumulated file-sized buffers")
    }

    func testOverOneGiBFileURLIsRejectedBeforeSnapshot() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(FileTransferLimits.maximumBytes + 1)); try handle.close()
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = try XCTUnwrap(NSItemProvider(contentsOf: url))
        do { _ = try await SharedItemLoader.loadOutgoing(provider, invitation: fileInvitation); XCTFail("Over-limit file imported") }
        catch { XCTAssertEqual(error as? FileTransferError, .tooLarge) }
    }

    func testNamedTextDocumentOverTenMiBStaysAFileEvenWithTextAlternative() async throws {
        let size = 11 * 1024 * 1024 + 1
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let writer = try FileHandle(forWritingTo: url)
        try writer.truncate(atOffset: UInt64(size)); try writer.close()
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = NSItemProvider(object: "Wrong inline alternative" as NSString)
        provider.suggestedName = "transcript-export.txt"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.plainText.identifier, fileOptions: [], visibility: .all) { done in
            done(url, false, nil); return nil
        }
        let item = try await SharedItemLoader.loadOutgoing(provider, invitation: fileInvitation)
        guard case .file(let file) = item else { XCTFail(".txt document became inline text"); return }
        XCTAssertEqual(file.metadata.kind, .file)
        XCTAssertEqual(file.metadata.byteCount, Int64(size))
        XCTAssertEqual(file.metadata.name, "transcript-export.txt")
        XCTAssertNotEqual(file.url, url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testFileURLProviderKeepsTextDocumentAndCleansOwnedSnapshot() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("Synthetic transcript document".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = try XCTUnwrap(NSItemProvider(contentsOf: url))
        var result: OutgoingItem? = try await SharedItemLoader.loadOutgoing(provider, invitation: fileInvitation)
        let ownedURL: URL
        if case .file(let file) = result { ownedURL = file.url; XCTAssertEqual(file.metadata.kind, .file) }
        else { XCTFail("File URL was extracted as selected text"); return }
        result = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: ownedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testAudioArchivesAndOpaqueBackupsUseFileRepresentation() async throws {
        for (type, name) in [(UTType.mpeg4Audio.identifier, "recording.m4a"),
                             (UTType.zip.identifier, "export.zip"),
                             ("com.example.synthetic.backup", "recording.vtbackup")] {
            let bytes = Data(repeating: 73, count: 4096)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try bytes.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let provider = NSItemProvider(); provider.suggestedName = name
            provider.registerFileRepresentation(forTypeIdentifier: type, fileOptions: [], visibility: .all) { done in
                done(url, false, nil); return nil
            }
            let item = try await SharedItemLoader.loadOutgoing(provider, invitation: fileInvitation)
            guard case .file(let file) = item else { XCTFail("Export was not a file"); continue }
            XCTAssertEqual(file.metadata.name, name)
            XCTAssertEqual(file.metadata.kind, .file)
            XCTAssertEqual(try Data(contentsOf: file.url), bytes)
        }
    }
    func testCancellingUnresponsiveFileProviderCompletesPromptly() async throws {
        let provider = NSItemProvider(); provider.suggestedName = "synthetic.zip"
        let started = expectation(description: "provider started")
        provider.registerFileRepresentation(forTypeIdentifier: UTType.zip.identifier, fileOptions: [], visibility: .all) { _ in
            started.fulfill(); return Progress(totalUnitCount: 1)
        }
        let invite = fileInvitation
        let task = Task { try await SharedItemLoader.loadOutgoing(provider, invitation: invite) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled provider returned success") }
        catch { XCTAssertTrue(error is DemoWireError) }
    }
    func testCancelledProviderPreparationDoesNotProduceAFile() async throws {
        let cancellation = TransferCancellation(); cancellation.cancel()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("Synthetic export".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = try XCTUnwrap(NSItemProvider(contentsOf: url))
        do { _ = try await SharedItemLoader.loadOutgoing(provider, invitation: fileInvitation, cancellation: cancellation); XCTFail("Cancelled import succeeded") }
        catch { XCTAssertTrue(error is DemoWireError) }
    }

    func testTenPagesOfUnicodeTextPreserveAllBytesAndParagraphs() async throws {
        let text = String(repeating: "Сторінка тесту — café 😀. Text with paragraphs.\n\n", count: 2500)
        let item = try await selectedItem(NSItemProvider(object: text as NSString))
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.bytes, Data(text.utf8))
        XCTAssertGreaterThan(item.bytes.count, 64 * 1024)
    }

    func testSelectedTextWithLegacyProviderPreservesUnicodeAndParagraphs() async throws {
        let text = "Вибраний текст із нотатки — café 😀.\n\nДругий абзац."
        let provider = NSItemProvider(item: text as NSString, typeIdentifier: UTType.text.identifier)
        let item = try await selectedItem(provider)
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.bytes, Data(text.utf8))
    }

    func testSelectedAttributedTextUsesPlainContents() async throws {
        let text = "Formatted selected text.\n\nSecond paragraph 😀."
        let provider = NSItemProvider()
        provider.registerItem(forTypeIdentifier: UTType.text.identifier) { completion, _, _ in
            completion?(NSAttributedString(string: text), nil)
        }
        let item = try await selectedItem(provider)
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.bytes, Data(text.utf8))
    }

    func testUnavailableURLRepresentationFallsBackToSelectedText() async throws {
        let text = "Selected note text, not a web link."
        let provider = NSItemProvider(object: text as NSString)
        provider.registerItem(forTypeIdentifier: UTType.url.identifier) { completion, _, _ in
            completion?(nil, NSError(domain: NSItemProvider.errorDomain, code: -1000))
        }
        let item = try await selectedItem(provider)
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.bytes, Data(text.utf8))
    }

    func testUTF8TextDataPreservesContent() async throws {
        let bytes = Data("Selected plain text — 😀\n\nNext paragraph.".utf8)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            completion(bytes, nil); return nil
        }
        let item = try await selectedItem(provider)
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.bytes, bytes)
    }

    func testWebLinkPreservesQueryAndFragment() async throws {
        let url = URL(string: "https://example.com/path?q=caf%C3%A9#section")!
        let item = try await selectedItem(NSItemProvider(object: url as NSURL))
        XCTAssertEqual(item.kind, .link)
        XCTAssertEqual(item.bytes, Data(url.absoluteString.utf8))
    }

    func testPhotoUsesOriginalFileBytesAndSafeName() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { ctx in
            UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        let bytes = try XCTUnwrap(image.pngData())
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try bytes.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let provider = NSItemProvider()
        provider.suggestedName = "../bad-name"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            completion(file, false, nil); return nil
        }
        let item = try await SharedItemLoader.load(provider)
        XCTAssertEqual(item.kind, .photo)
        XCTAssertEqual(item.bytes, bytes)
        XCTAssertEqual(item.name, "CaptureArc-1.png")
        let outgoing = try await SharedItemLoader.loadOutgoing(provider, invitation: fileInvitation)
        guard case .file(let file) = outgoing else { XCTFail("Photo did not use the file route"); return }
        XCTAssertEqual(file.metadata.kind, .photo)
        XCTAssertEqual(file.metadata.name, "CaptureArc-1.png")
        XCTAssertEqual(try Data(contentsOf: file.url), bytes)
    }

    func testOversizedTextIsRejectedBeforeTransmission() async {
        let provider = NSItemProvider(object: String(repeating: "x", count: DemoTransfer.maximumText + 1) as NSString)
        do { _ = try await selectedItem(provider); XCTFail("Oversized text accepted") }
        catch { XCTAssertTrue(error is SharedItemError) }
    }

    func testPairingKeychainRoundTripAndForget() throws {
        defer { PairingStore.clear() }
        let invite = DemoInvitation(service: UUID(), key: Data(repeating: 7, count: 32), untilStopped: true)
        try PairingStore.save(invite)
        XCTAssertEqual(PairingStore.load()?.service, invite.service)
        XCTAssertEqual(PairingStore.load()?.key, invite.key)
        PairingStore.clear()
        XCTAssertNil(PairingStore.load())
    }
}
