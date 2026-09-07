import Foundation
import Security

/// Secure wrapper around macOS Keychain Services
public final class KeychainHelper: Sendable {
    public static let shared = KeychainHelper()
    private let serviceName = "com.sidekik.keys"

    private init() {}

    public func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Remove existing item if present
        let queryDelete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(queryDelete as CFDictionary)

        guard !value.isEmpty else { return }

        // Add new item
        let queryAdd: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(queryAdd as CFDictionary, nil)
    }

    public func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data, let string = String(data: data, encoding: .utf8) {
            return string
        }
        return nil
    }

    public func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
