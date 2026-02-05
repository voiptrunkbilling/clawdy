import Foundation

// MARK: - Gateway Protocol Types
// Types used for the unified WebSocket protocol (port 18789)

// MARK: - Protocol Constants

let GATEWAY_PROTOCOL_VERSION = 3
let GATEWAY_WS_PORT = 18789
let GATEWAY_CLIENT_ID = "moltbot-ios"  // Must match GATEWAY_CLIENT_IDS in clawdbot gateway
let GATEWAY_CLIENT_MODE = "node"

// MARK: - Gateway Info

/// Information about the connected gateway server.
public struct GatewayInfo: Sendable, Equatable {
    /// Server name/identifier
    public var serverName: String
    
    /// Protocol version supported by the server
    public var protocolVersion: Int
    
    /// Minimum protocol version supported by the server
    public var minProtocolVersion: Int
    
    /// Maximum protocol version supported by the server
    public var maxProtocolVersion: Int
    
    /// Server uptime in seconds (if provided)
    public var uptimeSeconds: Int?
    
    /// Server version string (if provided)
    public var serverVersion: String?
    
    /// Canvas host URL for web UI (if provided)
    public var canvasHostUrl: String?
    
    /// Tick interval in milliseconds
    public var tickIntervalMs: Double
    
    /// Timestamp when connection was established
    public var connectedAt: Date
    
    public init(
        serverName: String,
        protocolVersion: Int = GATEWAY_PROTOCOL_VERSION,
        minProtocolVersion: Int = GATEWAY_PROTOCOL_VERSION,
        maxProtocolVersion: Int = GATEWAY_PROTOCOL_VERSION,
        uptimeSeconds: Int? = nil,
        serverVersion: String? = nil,
        canvasHostUrl: String? = nil,
        tickIntervalMs: Double = 30000,
        connectedAt: Date = Date()
    ) {
        self.serverName = serverName
        self.protocolVersion = protocolVersion
        self.minProtocolVersion = minProtocolVersion
        self.maxProtocolVersion = maxProtocolVersion
        self.uptimeSeconds = uptimeSeconds
        self.serverVersion = serverVersion
        self.canvasHostUrl = canvasHostUrl
        self.tickIntervalMs = tickIntervalMs
        self.connectedAt = connectedAt
    }
    
    /// Formatted uptime string (e.g., "2h 15m" or "3d 5h")
    public var formattedUptime: String? {
        guard let uptime = uptimeSeconds else { return nil }
        
        let days = uptime / 86400
        let hours = (uptime % 86400) / 3600
        let minutes = (uptime % 3600) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    /// Protocol compatibility description
    public var protocolDescription: String {
        if minProtocolVersion == maxProtocolVersion {
            return "v\(protocolVersion)"
        } else {
            return "v\(minProtocolVersion)-v\(maxProtocolVersion)"
        }
    }
}

// MARK: - Connection Test Result

/// Result of a gateway connection test with latency and protocol info.
public struct ConnectionTestResult: Sendable {
    /// Server name/identifier
    public var serverName: String
    
    /// Negotiated protocol version
    public var protocolVersion: Int
    
    /// Connection latency in milliseconds
    public var latencyMs: Int
    
    /// Full gateway info (if available)
    public var gatewayInfo: GatewayInfo?
    
    public init(
        serverName: String,
        protocolVersion: Int,
        latencyMs: Int,
        gatewayInfo: GatewayInfo? = nil
    ) {
        self.serverName = serverName
        self.protocolVersion = protocolVersion
        self.latencyMs = latencyMs
        self.gatewayInfo = gatewayInfo
    }
    
    /// Formatted latency string (e.g., "45ms" or "1.2s")
    public var formattedLatency: String {
        if latencyMs < 1000 {
            return "\(latencyMs)ms"
        } else {
            return String(format: "%.1fs", Double(latencyMs) / 1000)
        }
    }
    
    /// Summary string for display
    public var summary: String {
        var parts = ["protocol v\(protocolVersion)", "latency \(formattedLatency)"]
        if let uptime = gatewayInfo?.formattedUptime {
            parts.append("uptime \(uptime)")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - WebSocket Close Codes

/// Standard WebSocket close codes with gateway-specific interpretations.
public enum WebSocketCloseCode: Int, Sendable {
    case normalClosure = 1000
    case goingAway = 1001
    case protocolError = 1002
    case unsupportedData = 1003
    case noStatusReceived = 1005
    case abnormalClosure = 1006
    case invalidPayload = 1007
    case policyViolation = 1008
    case messageTooLarge = 1009
    case mandatoryExtension = 1010
    case internalError = 1011
    case serviceRestart = 1012
    case tryAgainLater = 1013
    case badGateway = 1014
    case tlsHandshakeFailed = 1015
    
    /// Human-readable description of the close code
    public var description: String {
        switch self {
        case .normalClosure:
            return "Connection closed normally"
        case .goingAway:
            return "Server shutting down"
        case .protocolError:
            return "Protocol error"
        case .unsupportedData:
            return "Unsupported data format"
        case .noStatusReceived:
            return "No status received"
        case .abnormalClosure:
            return "Connection lost unexpectedly"
        case .invalidPayload:
            return "Invalid message format"
        case .policyViolation:
            return "Policy violation - check authentication"
        case .messageTooLarge:
            return "Message too large"
        case .mandatoryExtension:
            return "Required extension not supported"
        case .internalError:
            return "Server internal error"
        case .serviceRestart:
            return "Server restarting"
        case .tryAgainLater:
            return "Server busy, try again later"
        case .badGateway:
            return "Bad gateway"
        case .tlsHandshakeFailed:
            return "TLS handshake failed"
        }
    }
    
    /// Whether this close code suggests the client should retry
    public var shouldRetry: Bool {
        switch self {
        case .goingAway, .serviceRestart, .tryAgainLater, .abnormalClosure:
            return true
        default:
            return false
        }
    }
    
    /// Whether this close code indicates an authentication/authorization issue
    public var isAuthError: Bool {
        self == .policyViolation
    }
}

// MARK: - App Lifecycle Phase

/// App lifecycle phase for connection management
enum AppLifecyclePhase: Equatable {
    case active
    case inactive
    case background
}

// MARK: - Gateway Errors

enum GatewayError: LocalizedError {
    case notConnected
    case vpnNotConnected
    case connectionFailed(String)
    case requestFailed(String)
    case protocolMismatch(clientVersion: Int, serverMinVersion: Int, serverMaxVersion: Int)
    case invalidURL(reason: String)
    case policyViolation(reason: String)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to gateway"
        case .vpnNotConnected:
            return "VPN is not connected"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .requestFailed(let reason):
            return "Request failed: \(reason)"
        case .protocolMismatch(let clientVersion, let serverMinVersion, let serverMaxVersion):
            if clientVersion < serverMinVersion {
                return "App update required. Server requires protocol v\(serverMinVersion)+, but app uses v\(clientVersion). Please update Clawdy."
            } else {
                return "Gateway upgrade required. App uses protocol v\(clientVersion), but server only supports v\(serverMinVersion)-v\(serverMaxVersion)."
            }
        case .invalidURL(let reason):
            return "Invalid connection URL: \(reason)"
        case .policyViolation(let reason):
            return "Connection rejected: \(reason)"
        }
    }
    
    /// Whether this error indicates the user should update the app
    var requiresAppUpdate: Bool {
        if case .protocolMismatch(let clientVersion, let serverMinVersion, _) = self {
            return clientVersion < serverMinVersion
        }
        return false
    }
    
    /// Whether this error indicates the server should be updated
    var requiresServerUpdate: Bool {
        if case .protocolMismatch(let clientVersion, _, let serverMaxVersion) = self {
            return clientVersion > serverMaxVersion
        }
        return false
    }
}

// MARK: - Push Events

/// Push events received from the gateway.
public enum GatewayPush: Sendable {
    case snapshot(HelloOkPayload)
    case event(GatewayEvent)
    case seqGap(expected: Int, received: Int)
}

/// Parsed hello-ok/connect response payload.
public struct HelloOkPayload: @unchecked Sendable {
    public var serverName: String
    public var canvasHostUrl: String?
    public var policy: [String: Any]
    public var auth: [String: Any]?

    public init(serverName: String, canvasHostUrl: String?, policy: [String: Any], auth: [String: Any]?) {
        self.serverName = serverName
        self.canvasHostUrl = canvasHostUrl
        self.policy = policy
        self.auth = auth
    }
}

/// Gateway event frame.
public struct GatewayEvent: @unchecked Sendable {
    public var event: String
    public var payload: [String: Any]?
    public var seq: Int?

    public init(event: String, payload: [String: Any]?, seq: Int?) {
        self.event = event
        self.payload = payload
        self.seq = seq
    }
}

/// User context preferences received from another device via the gateway.
public struct UserContextPreferences: Codable, Sendable {
    public var deviceId: String
    public var contextMode: String?
    public var timestamp: Date?
    
    public init(deviceId: String, contextMode: String? = nil, timestamp: Date? = nil) {
        self.deviceId = deviceId
        self.contextMode = contextMode
        self.timestamp = timestamp
    }
}

// MARK: - Gateway Response Error

/// Error from a gateway RPC response.
public struct GatewayResponseError: Error, LocalizedError {
    public var method: String
    public var code: String?
    public var message: String?
    public var details: [String: Any]

    public var errorDescription: String? {
        if let message = message {
            return "\(method): \(message)"
        }
        return "\(method) failed"
    }

    public init(method: String, code: String?, message: String?, details: [String: Any]) {
        self.method = method
        self.code = code
        self.message = message
        self.details = details
    }
}

// MARK: - Connect Options

/// Connect options for the gateway.
public struct GatewayConnectOptions: Sendable {
    public var role: String
    public var scopes: [String]
    public var caps: [String]
    public var commands: [String]
    public var permissions: [String: Bool]
    public var clientId: String
    public var clientMode: String
    public var clientDisplayName: String?

    public init(
        role: String = "node",
        scopes: [String] = [],
        caps: [String] = [],
        commands: [String] = [],
        permissions: [String: Bool] = [:],
        clientId: String = "moltbot-ios",
        clientMode: String = "node",
        clientDisplayName: String? = nil
    ) {
        self.role = role
        self.scopes = scopes
        self.caps = caps
        self.commands = commands
        self.permissions = permissions
        self.clientId = clientId
        self.clientMode = clientMode
        self.clientDisplayName = clientDisplayName
    }
    
    // MARK: - Factory Methods for Dual Role Connections
    
    /// Create connection options for the operator role.
    ///
    /// Operator connections are used for chat operations (send/receive messages, history).
    /// Required scopes: `operator.read` (for chat.history), `operator.write` (for chat.send).
    ///
    /// - Parameter displayName: Optional custom display name for the client.
    /// - Returns: Pre-configured options for an operator connection.
    public static func forOperator(displayName: String? = nil) -> GatewayConnectOptions {
        GatewayConnectOptions(
            role: "operator",
            scopes: ["operator.read", "operator.write"],
            caps: [],
            commands: [],
            permissions: [:],
            clientId: "moltbot-ios",
            clientMode: "ui",
            clientDisplayName: displayName
        )
    }
    
    /// Create connection options for the node role.
    ///
    /// Node connections are used for capability invokes (camera, location, etc.).
    /// Nodes advertise their capabilities and handle invoke requests.
    ///
    /// Note: We request the same scopes as operator to avoid scope-upgrade pairing
    /// requirements when both roles connect. The gateway merges scopes on pairing
    /// approval, but checks them on every connect - requesting consistent scopes
    /// ensures a single pairing approval covers both connection roles.
    ///
    /// - Parameter displayName: Optional custom display name for the client.
    /// - Returns: Pre-configured options for a node connection.
    public static func forNode(displayName: String? = nil) -> GatewayConnectOptions {
        GatewayConnectOptions(
            role: "node",
            scopes: ["operator.read", "operator.write"],
            caps: ["camera", "location", "voice"],
            commands: [
                "camera.snap",
                "camera.clip",
                "camera.list",
                "location.get",
                "system.notify"
            ],
            permissions: ["camera.capture": true],
            clientId: "moltbot-ios",
            clientMode: "node",
            clientDisplayName: displayName
        )
    }
}

// MARK: - Base Frame

/// Base frame for determining message type.
struct BridgeBaseFrame: Codable, Sendable {
    let type: String

    init(type: String) {
        self.type = type
    }
}

// MARK: - Events

/// Event frame (bidirectional).
struct BridgeEventFrame: Codable, Sendable {
    let type: String
    let event: String
    let payloadJSON: String?

    init(type: String = "event", event: String, payloadJSON: String? = nil) {
        self.type = type
        self.event = event
        self.payloadJSON = payloadJSON
    }
}

// MARK: - RPC (Node -> Gateway)

/// RPC request from node to gateway.
struct BridgeRPCRequest: Codable, Sendable {
    let type: String
    let id: String
    let method: String
    let paramsJSON: String?

    init(type: String = "req", id: String, method: String, paramsJSON: String? = nil) {
        self.type = type
        self.id = id
        self.method = method
        self.paramsJSON = paramsJSON
    }
}

/// RPC error details.
struct BridgeRPCError: Codable, Sendable, Equatable {
    let code: String
    let message: String

    init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

/// RPC response from gateway.
struct BridgeRPCResponse: Codable, Sendable {
    let type: String
    let id: String
    let ok: Bool
    let payloadJSON: String?
    let error: BridgeRPCError?

    init(
        type: String = "res",
        id: String,
        ok: Bool,
        payloadJSON: String? = nil,
        error: BridgeRPCError? = nil
    ) {
        self.type = type
        self.id = id
        self.ok = ok
        self.payloadJSON = payloadJSON
        self.error = error
    }
}

// MARK: - Invoke (Gateway -> Node)

/// Invoke request from gateway to execute a capability.
struct BridgeInvokeRequest: Codable, Sendable {
    let type: String
    let id: String
    let command: String
    let paramsJSON: String?

    init(type: String = "invoke", id: String, command: String, paramsJSON: String? = nil) {
        self.type = type
        self.id = id
        self.command = command
        self.paramsJSON = paramsJSON
    }
}

/// Node error codes for invoke responses.
enum BridgeNodeErrorCode: String, Codable, Sendable {
    case notPaired = "NOT_PAIRED"
    case unauthorized = "UNAUTHORIZED"
    case backgroundUnavailable = "NODE_BACKGROUND_UNAVAILABLE"
    case invalidRequest = "INVALID_REQUEST"
    case unavailable = "UNAVAILABLE"
}

/// Node error for invoke responses.
struct BridgeNodeError: Error, Codable, Sendable, Equatable {
    var code: BridgeNodeErrorCode
    var message: String
    var retryable: Bool?
    var retryAfterMs: Int?

    init(
        code: BridgeNodeErrorCode,
        message: String,
        retryable: Bool? = nil,
        retryAfterMs: Int? = nil
    ) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.retryAfterMs = retryAfterMs
    }
}

/// Invoke response from node to gateway.
struct BridgeInvokeResponse: Codable, Sendable {
    let type: String
    let id: String
    let ok: Bool
    let payloadJSON: String?
    let error: BridgeNodeError?

    init(
        type: String = "invoke-res",
        id: String,
        ok: Bool,
        payloadJSON: String? = nil,
        error: BridgeNodeError? = nil
    ) {
        self.type = type
        self.id = id
        self.ok = ok
        self.payloadJSON = payloadJSON
        self.error = error
    }
}
