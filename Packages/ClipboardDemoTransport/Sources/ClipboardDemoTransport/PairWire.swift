import Foundation

public enum DemoWireError: LocalizedError {
    case badInvite, badFrame, deadline, rejected, busy, cancelled
    public var errorDescription: String? {
        switch self {
        case .badInvite: return CaptureArcText.value("The pairing code is invalid or expired.")
        case .badFrame: return CaptureArcText.value("The item is too large or invalid.")
        case .deadline: return CaptureArcText.value("Transfer timed out. Keep CaptureArc open on your Mac and connect both devices to the same Wi-Fi. If receiving was stopped, pair again.")
        case .rejected: return CaptureArcText.value("Your Mac could not accept the item. Check the From iPhone tab for details.")
        case .busy: return CaptureArcText.value("A transfer is already in progress.")
        case .cancelled: return CaptureArcText.value("Transfer cancelled.")
        }
    }
}

public struct DemoInvitation: Codable, Sendable {
    public static let serviceType = "_caparc-demo._tcp"
    public static let lifetime: TimeInterval = 120
    public let service: UUID
    public let key: Data
    public let validUntil: Date
    public let untilStopped: Bool?
    public let fileProtocol: Int?

    public var isManualSession: Bool { untilStopped == true }
    public func isValid(at now: Date = Date()) -> Bool { isManualSession || validUntil > now }

    public init(service: UUID, key: Data, validUntil: Date, fileProtocol: Int? = nil) {
        self.fileProtocol = fileProtocol
        self.service = service
        self.key = key
        self.validUntil = validUntil
        self.untilStopped = nil
    }

    public init(service: UUID, key: Data, untilStopped: Bool, fileProtocol: Int? = nil) {
        self.fileProtocol = fileProtocol
        self.service = service
        self.key = key
        self.untilStopped = untilStopped
        self.validUntil = untilStopped ? .distantFuture : Date().addingTimeInterval(Self.lifetime)
    }

    public func supportingFiles() -> Self {
        if isManualSession { return Self(service: service, key: key, untilStopped: true, fileProtocol: FileTransferLimits.version) }
        return Self(service: service, key: key, validUntil: validUntil, fileProtocol: FileTransferLimits.version)
    }

    public func pasteCode() throws -> String {
        (isManualSession ? "capturearc-demo-v2:" : "capturearc-demo-v1:") + (try JSONEncoder().encode(self)).base64EncodedString()
    }

    public static func parse(_ code: String, now: Date = Date()) throws -> Self {
        let text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = text.hasPrefix("capturearc-demo-v2:") ? "capturearc-demo-v2:" : "capturearc-demo-v1:"
        guard text.utf8.count <= 512, text.hasPrefix(prefix),
              let data = Data(base64Encoded: String(text.dropFirst(prefix.count))),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.key.count == 32, value.isValid(at: now),
              (value.isManualSession ? prefix == "capturearc-demo-v2:" :
               value.validUntil.timeIntervalSince(now) <= lifetime + 15) else { throw DemoWireError.badInvite }
        return value
    }
}

public struct DemoTransfer: Codable {
    public enum Kind: String, Codable, Sendable {
        case text, link, photo, file
    }
    public static let maximumPayload = 10 * 1024 * 1024
    public static let maximumText = 1024 * 1024
    public static let maximumFrame = ((maximumPayload + 2) / 3) * 4 + 4096
    public static let maximumBatchCount = 5
    public static let connectionTimeout: TimeInterval = 30
    public let kind: Kind
    public let bytes: Data
    public let name: String?

    public init(kind: Kind, bytes: Data, name: String? = nil) {
        self.kind = kind
        self.bytes = bytes
        self.name = name
    }

    public func check() throws {
        let isFile = kind == .file || kind == .photo
        guard !bytes.isEmpty, bytes.count <= (isFile ? Self.maximumPayload : Self.maximumText) else {
            throw DemoWireError.badFrame
        }
        if isFile {
            guard let name, !name.isEmpty, !name.hasPrefix("."), !name.contains("/"),
                  !name.contains("\\"), !name.contains(":"), name.utf8.count <= 200,
                  name.rangeOfCharacter(from: .controlCharacters) == nil else { throw DemoWireError.badFrame }
        } else {
            guard name == nil, let text = String(data: bytes, encoding: .utf8) else { throw DemoWireError.badFrame }
            if kind == .link {
                guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
                      ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty,
                      url.user == nil, url.password == nil else { throw DemoWireError.badFrame }
            }
        }
    }

    public func framed() throws -> Data {
        try check()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumFrame else { throw DemoWireError.badFrame }
        var length = UInt32(data.count).bigEndian
        var result = withUnsafeBytes(of: &length) { Data($0) }
        result.append(data)
        return result
    }

    public static func length(_ header: Data) throws -> Int {
        guard header.count == 4 else { throw DemoWireError.badFrame }
        let count = header.reduce(0) { ($0 << 8) | Int($1) }
        guard count > 0, count <= maximumFrame else { throw DemoWireError.badFrame }
        return count
    }

    public static func parse(_ data: Data) throws -> Self {
        guard data.count <= maximumFrame else { throw DemoWireError.badFrame }
        let item = try JSONDecoder().decode(Self.self, from: data)
        try item.check()
        return item
    }
}
