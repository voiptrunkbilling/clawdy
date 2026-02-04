import Foundation

/// A gateway profile configuration for connecting to different Clawdbot gateways.
/// Supports multiple profiles for dev/prod switching and team testing.
struct GatewayProfile: Codable, Identifiable, Equatable {
    /// Unique identifier for the profile
    let id: UUID
    
    /// User-friendly name for the profile (e.g., "Production", "Development")
    var name: String
    
    /// Gateway hostname or IP address
    var host: String
    
    /// Gateway port (default: 18789)
    var port: Int
    
    /// Whether to use TLS (wss://) for the connection
    var useTLS: Bool
    
    /// Whether this is the primary/default profile
    var isPrimary: Bool
    
    /// Create a new gateway profile
    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 18789,
        useTLS: Bool = false,
        isPrimary: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.isPrimary = isPrimary
    }
    
    /// Keychain key prefix for this profile's credentials
    var keychainPrefix: String {
        "profile.\(id.uuidString)"
    }
    
    /// Display string for the connection URL
    var connectionURL: String {
        let scheme = useTLS ? "wss" : "ws"
        return "\(scheme)://\(host):\(port)"
    }
    
    /// Short display string (just host:port)
    var shortDisplayString: String {
        "\(host):\(port)"
    }
}

// MARK: - Profile Validation

extension GatewayProfile {
    /// Validate the profile configuration
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        port > 0 && port <= 65535
    }
    
    /// Validation error message, if any
    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Profile name is required"
        }
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Host is required"
        }
        if port <= 0 || port > 65535 {
            return "Port must be between 1 and 65535"
        }
        return nil
    }
}

// MARK: - Default Profiles

extension GatewayProfile {
    /// Create a default "Production" profile from existing credentials
    static func defaultProduction(from credentials: KeychainManager.GatewayCredentials) -> GatewayProfile {
        GatewayProfile(
            name: "Production",
            host: credentials.host,
            port: credentials.port,
            useTLS: credentials.useTLS,
            isPrimary: true
        )
    }
    
    /// Empty profile for creating new profiles
    static var empty: GatewayProfile {
        GatewayProfile(
            name: "",
            host: "",
            port: 18789,
            useTLS: false,
            isPrimary: false
        )
    }
}
