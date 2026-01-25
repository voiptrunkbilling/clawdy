import Foundation
import Security

/// Manager for secure credential storage using iOS Keychain.
class KeychainManager {
    // MARK: - Singleton

    static let shared = KeychainManager()
    private init() {}

    // MARK: - Keychain Keys
    
    // NOTE: gatewayToken and gatewayAuthToken are LEGACY for the old TCP bridge / hybrid protocol.
    // The unified WebSocket protocol uses DeviceAuthStore for per-role device tokens instead.
    // These legacy keys will be removed in Phase 6 cleanup of the unified WS migration.

    private enum KeychainKey: String {
        case gatewayHost = "com.clawdy.gateway.host"
        case gatewayPort = "com.clawdy.gateway.port"
        case gatewayToken = "com.clawdy.gateway.token"  // LEGACY: Node/pairing token for TCP bridge
        case gatewayAuthToken = "com.clawdy.gateway.authToken"  // LEGACY: WebSocket auth token (gateway.auth.token)
        case gatewayTLS = "com.clawdy.gateway.tls"
    }

    private enum UserDefaultsKey {
        static let hasCleanedLegacyCredentials = "com.clawdy.migration.cleanedLegacyCredentials"
    }

    // MARK: - Gateway Credentials

    /// Gateway connection credentials for Clawdbot
    struct GatewayCredentials {
        var host: String
        var port: Int
        var token: String?      // Node/pairing token for TCP bridge (port 18790)
        var authToken: String?  // WebSocket auth token for chat (port 18789) - gateway.auth.token
        var useTLS: Bool

        static var empty: GatewayCredentials {
            GatewayCredentials(host: "", port: 18790, token: nil, authToken: nil, useTLS: false)
        }

        /// Default gateway port for Clawdbot node bridge (TCP)
        static let defaultPort: Int = 18790
        
        /// Default gateway port for WebSocket chat
        static let defaultChatPort: Int = 18789
    }

    /// Save gateway credentials to Keychain
    func saveGatewayCredentials(_ credentials: GatewayCredentials) throws {
        try saveString(credentials.host, forKey: .gatewayHost)
        try saveString(String(credentials.port), forKey: .gatewayPort)
        if let token = credentials.token {
            try saveString(token, forKey: .gatewayToken)
        } else {
            deleteItem(forKey: .gatewayToken)
        }
        if let authToken = credentials.authToken {
            try saveString(authToken, forKey: .gatewayAuthToken)
        } else {
            deleteItem(forKey: .gatewayAuthToken)
        }
        try saveString(credentials.useTLS ? "true" : "false", forKey: .gatewayTLS)
    }

    /// Load gateway credentials from Keychain
    func loadGatewayCredentials() -> GatewayCredentials? {
        guard let host = getString(forKey: .gatewayHost), !host.isEmpty else {
            return nil
        }

        let portString = getString(forKey: .gatewayPort)
        let port = portString.flatMap { Int($0) } ?? GatewayCredentials.defaultPort
        let token = getString(forKey: .gatewayToken)
        let authToken = getString(forKey: .gatewayAuthToken)
        let tlsString = getString(forKey: .gatewayTLS)
        let useTLS = tlsString == "true"

        return GatewayCredentials(
            host: host,
            port: port,
            token: token,
            authToken: authToken,
            useTLS: useTLS
        )
    }

    /// Check if gateway credentials are configured
    func hasGatewayCredentials() -> Bool {
        guard let host = getString(forKey: .gatewayHost) else { return false }
        return !host.isEmpty
    }

    /// Delete all gateway credentials from Keychain
    func deleteGatewayCredentials() {
        deleteItem(forKey: .gatewayHost)
        deleteItem(forKey: .gatewayPort)
        deleteItem(forKey: .gatewayToken)
        deleteItem(forKey: .gatewayAuthToken)
        deleteItem(forKey: .gatewayTLS)
    }

    // MARK: - Gateway Individual Field Access (for Settings UI)

    var gatewayHost: String? {
        get { getString(forKey: .gatewayHost) }
        set {
            if let value = newValue, !value.isEmpty {
                try? saveString(value, forKey: .gatewayHost)
            } else {
                deleteItem(forKey: .gatewayHost)
            }
        }
    }

    var gatewayPort: Int {
        get {
            guard let portString = getString(forKey: .gatewayPort),
                  let port = Int(portString) else {
                return GatewayCredentials.defaultPort
            }
            return port
        }
        set {
            try? saveString(String(newValue), forKey: .gatewayPort)
        }
    }

    /// LEGACY: Node/pairing token for TCP bridge connection (port 18790)
    /// NOTE: Will be removed in Phase 6 of unified WS migration. Use DeviceAuthStore instead.
    var gatewayToken: String? {
        get { getString(forKey: .gatewayToken) }
        set {
            if let value = newValue, !value.isEmpty {
                try? saveString(value, forKey: .gatewayToken)
            } else {
                deleteItem(forKey: .gatewayToken)
            }
        }
    }
    
    /// LEGACY: WebSocket auth token for chat connection (port 18789)
    /// This corresponds to gateway.auth.token in clawdbot config
    /// NOTE: Will be removed in Phase 6 of unified WS migration. Use DeviceAuthStore instead.
    var gatewayAuthToken: String? {
        get { getString(forKey: .gatewayAuthToken) }
        set {
            if let value = newValue, !value.isEmpty {
                try? saveString(value, forKey: .gatewayAuthToken)
            } else {
                deleteItem(forKey: .gatewayAuthToken)
            }
        }
    }

    var gatewayTLS: Bool {
        get { getString(forKey: .gatewayTLS) == "true" }
        set {
            try? saveString(newValue ? "true" : "false", forKey: .gatewayTLS)
        }
    }

    // MARK: - Legacy Cleanup

    /// Remove legacy credentials on first 2.0 launch.
    func cleanUpLegacyCredentialsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: UserDefaultsKey.hasCleanedLegacyCredentials) else {
            return
        }

        let legacyEncodedKeys = [
            "Y29tLnZvaWNlcmVtb3RlLnNzaC5ob3N0",
            "Y29tLnZvaWNlcmVtb3RlLnNzaC5wb3J0",
            "Y29tLnZvaWNlcmVtb3RlLnNzaC51c2VybmFtZQ==",
            "Y29tLnZvaWNlcmVtb3RlLnNzaC5wcml2YXRlS2V5",
            "Y29tLnZvaWNlcmVtb3RlLnNzaC52YXVsdFBhdGg=",
            "Y29tLnZvaWNlcmVtb3RlLnJwYy5zZXNzaW9uRmlsZVBhdGg="
        ]

        for encodedKey in legacyEncodedKeys {
            if let rawKey = decodeBase64(encodedKey) {
                deleteItem(forRawKey: rawKey)
            }
        }

        defaults.set(true, forKey: UserDefaultsKey.hasCleanedLegacyCredentials)
    }

    // MARK: - Private Keychain Operations

    private func saveString(_ value: String, forKey key: KeychainKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        deleteItem(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func getString(forKey key: KeychainKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    private func deleteItem(forKey key: KeychainKey) {
        deleteItem(forRawKey: key.rawValue)
    }

    private func deleteItem(forRawKey rawKey: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: rawKey
        ]

        SecItemDelete(query as CFDictionary)
    }

    private func decodeBase64(_ value: String) -> String? {
        guard let data = Data(base64Encoded: value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Keychain Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data for Keychain"
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .loadFailed(let status):
            return "Failed to load from Keychain (status: \(status))"
        }
    }
}
