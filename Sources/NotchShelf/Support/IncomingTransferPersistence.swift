import Foundation
import ClipboardDemoTransport
import Security

/// The manifest stores relative file identities, never arbitrary paths supplied by a peer.
struct IncomingTransferPersistence {
    let directory: URL
    private struct Record: Codable {
        let id: UUID
        let kind: IncomingTransfer.Kind
        let title: String
        let text: String?
        let link: URL?
    }
    private var manifest: URL { directory.appendingPathComponent("items.json") }

    func load() throws -> [IncomingTransfer] {
        guard FileManager.default.fileExists(atPath: manifest.path) else { return [] }
        let records = try JSONDecoder().decode([Record].self, from: Data(contentsOf: manifest))
        guard records.count <= 20, Set(records.map(\.id)).count == records.count else { throw IncomingTransferError.full }
        return try records.map { record in
            let url: URL?
            switch record.kind {
            case .text:
                guard let text = record.text, !text.isEmpty,
                      text.utf8.count <= IncomingTransferStaging.maximumTextBytes else { throw IncomingTransferError.invalidSize }
                url = nil
            case .link:
                guard let link = record.link else { throw IncomingTransferError.unsupportedLink }
                _ = try IncomingTransferStaging(directory: directory).stage(.link(link))
                url = link
            case .photo, .file:
                try IncomingTransferStaging.validateName(record.title)
                let location = directory.appendingPathComponent(record.id.uuidString).appendingPathComponent(record.title)
                let values = try location.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize, size > 0, size <= IncomingTransferStaging.maximumFileBytes else { throw IncomingTransferError.invalidSize }
                url = location
            }
            return IncomingTransfer(id: record.id, kind: record.kind, title: record.title, text: record.text, url: url)
        }
    }

    func save(_ items: [IncomingTransfer]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let records = items.map { Record(id: $0.id, kind: $0.kind, title: $0.title, text: $0.text,
                                         link: $0.kind == .link ? $0.url : nil) }
        try JSONEncoder().encode(records).write(to: manifest, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifest.path)
    }

    func removeFile(for item: IncomingTransfer) throws {
        guard item.kind == .file || item.kind == .photo else { return }
        let folder = directory.appendingPathComponent(item.id.uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }
}

/// Store the receiving secret only in this app's Keychain, never in preferences or logs.
struct MacReceiverPairing {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.illiagryniuk.capturearc.receiving",
         kSecAttrAccount as String: "active-invitation"]
    }
    func load() throws -> DemoInvitation? {
        guard UserDefaults.standard.bool(forKey: "captureArcReceivingEnabled") else { return nil }
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let code = String(data: data, encoding: .utf8) else { throw PairingStorageError.unavailable }
        return try DemoInvitation.parse(code)
    }
    func save(_ invitation: DemoInvitation) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(try invitation.pasteCode().utf8),
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0] = $1 }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw PairingStorageError.unavailable }
        } else if status != errSecSuccess { throw PairingStorageError.unavailable }
        UserDefaults.standard.set(true, forKey: "captureArcReceivingEnabled")
    }
    func clear() throws {
        // Stop remains effective even if Keychain is temporarily unavailable.
        UserDefaults.standard.set(false, forKey: "captureArcReceivingEnabled")
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PairingStorageError.unavailable }
    }
    private enum PairingStorageError: LocalizedError {
        case unavailable
        var errorDescription: String? { CaptureArcText.value("Could not save pairing. Please try again.") }
    }
}
