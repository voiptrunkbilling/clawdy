import Foundation
import Security

/// Manager for secure credential storage using iOS Keychain.
class KeychainManager {
    // MARK: - Singleton

    static let shared = KeychainManager()
    private init() {}

    // MARK: - Keychain Keys

    private enum KeychainKey: String {
        case gatewayHost = "com.clawdy.gateway.host"
        case gatewayPort = "com.clawdy.gateway.port"
        case gatewayAuthToken = "com.clawdy.gateway.authToken"
        case gatewayTLS = "com.clawdy.gateway.tls"
    }

    // MARK: - Gateway Credentials

    /// Gateway connection credentials for Clawdbot
    struct GatewayCredentials {
        var host: String
        var port: Int
        var authToken: String?
        var useTLS: Bool

        static var empty: GatewayCredentials {
            GatewayCredentials(host: "", port: 18790, authToken: nil, useTLS: false)
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
        let authToken = getString(forKey: .gatewayAuthToken)
        let tlsString = getString(forKey: .gatewayTLS)
        let useTLS = tlsString == "true"

        return GatewayCredentials(
            host: host,
            port: port,
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
