import ClipboardDemoTransport
import Foundation
import Security

/// Only the pairing invitation is shared with our own Share extension.
/// Never stores shared text, photos, URLs, or clipboard contents.
enum PairingStore {
    private static var query: [String: Any] {
        var value: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: "capturearc.pairing",
                                  kSecAttrAccount as String: "active-invitation"]
        if let group = Bundle.main.object(forInfoDictionaryKey: "CaptureArcKeychainGroup") as? String {
            value[kSecAttrAccessGroup as String] = group
        }
        return value
    }

    static func save(_ invitation: DemoInvitation) throws {
        let data = Data(try invitation.pasteCode().utf8)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0] = $1 }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw PairingError.unavailable }
        } else if result != errSecSuccess {
            throw PairingError.unavailable
        }
    }

    static func load() -> DemoInvitation? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let code = String(data: data, encoding: .utf8) else { return nil }
        guard let invitation = try? DemoInvitation.parse(code) else { clear(); return nil }
        return invitation
    }

    static func clear() { SecItemDelete(query as CFDictionary) }

    private enum PairingError: LocalizedError {
        case unavailable
        var errorDescription: String? { CaptureArcText.value("Could not save pairing for the Share menu.") }
    }
}
