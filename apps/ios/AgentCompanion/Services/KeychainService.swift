import Foundation
import Security

/// Keychain helper for storing secrets (tokens, DB passphrase).
/// Uses kSecClassGenericPassword with the app's bundle identifier as service.
enum KeychainService {
    private static let service = Bundle.main.bundleIdentifier ?? "com.agentcompanion"

    // MARK: - Save

    static func save(key: String, data: Data) -> Bool {
        delete(key: key) // Remove existing before saving

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func save(key: String, string: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(key: key, data: data)
    }

    // MARK: - Read

    static func read(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func readString(key: String) -> String? {
        guard let data = read(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Keys

    enum Keys {
        static let accessToken = "access_token"
        static let refreshToken = "refresh_token"
        static let dbPassphrase = "db_passphrase"
    }

    // MARK: - DB Passphrase

    /// Returns existing passphrase or generates and stores a new one.
    static func getOrCreateDBPassphrase() -> String {
        if let existing = readString(key: Keys.dbPassphrase) {
            return existing
        }

        // Generate a cryptographically random 32-byte passphrase
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let passphrase = Data(bytes).base64EncodedString()

        _ = save(key: Keys.dbPassphrase, string: passphrase)
        return passphrase
    }
}
