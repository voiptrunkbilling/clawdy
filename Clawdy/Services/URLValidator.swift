import Foundation

// MARK: - URL Validator

/// Validates WebSocket connection URLs for gateway configuration.
/// Ensures the URL has a valid scheme, hostname, and optional port.
struct URLValidator {
    
    // MARK: - Validation Result
    
    /// Result of URL validation with detailed error information.
    struct ValidationResult: Equatable {
        let isValid: Bool
        let error: ValidationError?
        let normalizedURL: URL?
        let hostname: String?
        let port: Int?
        let useTLS: Bool
        
        static func success(url: URL, hostname: String, port: Int, useTLS: Bool) -> ValidationResult {
            ValidationResult(
                isValid: true,
                error: nil,
                normalizedURL: url,
                hostname: hostname,
                port: port,
                useTLS: useTLS
            )
        }
        
        static func failure(_ error: ValidationError) -> ValidationResult {
            ValidationResult(
                isValid: false,
                error: error,
                normalizedURL: nil,
                hostname: nil,
                port: nil,
                useTLS: false
            )
        }
    }
    
    // MARK: - Validation Errors
    
    /// Specific validation errors for connection URLs.
    enum ValidationError: LocalizedError, Equatable {
        case emptyHostname
        case invalidHostnameCharacters
        case invalidScheme(provided: String, expected: [String])
        case invalidPort(value: Int, min: Int, max: Int)
        case portOutOfRange(value: String)
        case malformedURL(reason: String)
        case hostnameResolutionFailed
        
        var errorDescription: String? {
            switch self {
            case .emptyHostname:
                return "Hostname cannot be empty"
            case .invalidHostnameCharacters:
                return "Hostname contains invalid characters"
            case .invalidScheme(let provided, let expected):
                let schemes = expected.joined(separator: ", ")
                return "Invalid scheme '\(provided)'. Use \(schemes)"
            case .invalidPort(let value, let min, let max):
                return "Port \(value) is out of range. Must be between \(min) and \(max)"
            case .portOutOfRange(let value):
                return "Invalid port '\(value)'. Must be a number between 1 and 65535"
            case .malformedURL(let reason):
                return "Invalid URL format: \(reason)"
            case .hostnameResolutionFailed:
                return "Could not resolve hostname"
            }
        }
        
        /// Short error message suitable for inline display
        var shortDescription: String {
            switch self {
            case .emptyHostname:
                return "Hostname required"
            case .invalidHostnameCharacters:
                return "Invalid hostname"
            case .invalidScheme(_, _):
                return "Use ws:// or wss://"
            case .invalidPort(_, _, _), .portOutOfRange(_):
                return "Port must be 1-65535"
            case .malformedURL(_):
                return "Invalid URL"
            case .hostnameResolutionFailed:
                return "Cannot resolve host"
            }
        }
    }
    
    // MARK: - Port Range
    
    static let minPort = 1
    static let maxPort = 65535
    static let defaultPort = GATEWAY_WS_PORT  // 18789
    static let validSchemes = ["ws", "wss"]
    
    // MARK: - Validation Methods
    
    /// Validate a complete WebSocket URL string.
    /// - Parameter urlString: The URL string to validate (e.g., "ws://host:18789" or just "host")
    /// - Returns: ValidationResult with normalized URL or error details
    static func validate(_ urlString: String) -> ValidationResult {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            return .failure(.emptyHostname)
        }
        
        // Determine if scheme is provided
        let hasScheme = trimmed.contains("://")
        
        // If no scheme, treat as hostname and build URL
        if !hasScheme {
            return validateHostnameOnly(trimmed)
        }
        
        // Parse full URL
        guard let url = URL(string: trimmed) else {
            return .failure(.malformedURL(reason: "Could not parse URL"))
        }
        
        return validateURL(url)
    }
    
    /// Validate hostname and port separately (for Settings UI with separate fields).
    /// - Parameters:
    ///   - hostname: The hostname or IP address
    ///   - port: The port number
    ///   - useTLS: Whether to use secure WebSocket (wss://)
    /// - Returns: ValidationResult with normalized URL or error details
    static func validate(hostname: String, port: Int, useTLS: Bool) -> ValidationResult {
        let trimmedHostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate hostname
        if let error = validateHostname(trimmedHostname) {
            return .failure(error)
        }
        
        // Validate port
        if let error = validatePort(port) {
            return .failure(error)
        }
        
        // Build URL
        let scheme = useTLS ? "wss" : "ws"
        let urlString = "\(scheme)://\(trimmedHostname):\(port)"
        
        guard let url = URL(string: urlString) else {
            return .failure(.malformedURL(reason: "Could not construct URL"))
        }
        
        return .success(url: url, hostname: trimmedHostname, port: port, useTLS: useTLS)
    }
    
    /// Validate a port number string from user input.
    /// - Parameter portString: The port string to validate
    /// - Returns: The port number if valid, or nil with error
    static func validatePortString(_ portString: String) -> (port: Int?, error: ValidationError?) {
        let trimmed = portString.trimmingCharacters(in: .whitespaces)
        
        guard !trimmed.isEmpty else {
            return (defaultPort, nil)  // Empty means use default
        }
        
        guard let port = Int(trimmed) else {
            return (nil, .portOutOfRange(value: trimmed))
        }
        
        if let error = validatePort(port) {
            return (nil, error)
        }
        
        return (port, nil)
    }
    
    // MARK: - Private Helpers
    
    private static func validateHostnameOnly(_ hostname: String) -> ValidationResult {
        // Check for port in hostname (e.g., "host:8080")
        let parts = hostname.split(separator: ":", maxSplits: 1)
        let host = String(parts[0])
        
        // Validate hostname
        if let error = validateHostname(host) {
            return .failure(error)
        }
        
        // Parse port if provided
        var port = defaultPort
        if parts.count > 1 {
            guard let parsedPort = Int(parts[1]) else {
                return .failure(.portOutOfRange(value: String(parts[1])))
            }
            if let error = validatePort(parsedPort) {
                return .failure(error)
            }
            port = parsedPort
        }
        
        // Build URL with default scheme (ws://)
        let urlString = "ws://\(host):\(port)"
        guard let url = URL(string: urlString) else {
            return .failure(.malformedURL(reason: "Could not construct URL"))
        }
        
        return .success(url: url, hostname: host, port: port, useTLS: false)
    }
    
    private static func validateURL(_ url: URL) -> ValidationResult {
        // Validate scheme
        guard let scheme = url.scheme?.lowercased() else {
            return .failure(.invalidScheme(provided: "", expected: validSchemes))
        }
        
        guard validSchemes.contains(scheme) else {
            return .failure(.invalidScheme(provided: scheme, expected: validSchemes))
        }
        
        // Validate hostname
        guard let host = url.host, !host.isEmpty else {
            return .failure(.emptyHostname)
        }
        
        if let error = validateHostname(host) {
            return .failure(error)
        }
        
        // Validate port
        let port = url.port ?? (scheme == "wss" ? 443 : defaultPort)
        if let error = validatePort(port) {
            return .failure(error)
        }
        
        let useTLS = scheme == "wss"
        
        // Normalize URL
        let normalizedString = "\(scheme)://\(host):\(port)"
        guard let normalizedURL = URL(string: normalizedString) else {
            return .failure(.malformedURL(reason: "Could not normalize URL"))
        }
        
        return .success(url: normalizedURL, hostname: host, port: port, useTLS: useTLS)
    }
    
    private static func validateHostname(_ hostname: String) -> ValidationError? {
        guard !hostname.isEmpty else {
            return .emptyHostname
        }
        
        // Allow IP addresses (IPv4 and IPv6) and domain names
        // Basic character validation
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-:[]"))
        let hostnameCharacters = CharacterSet(charactersIn: hostname)
        
        guard allowedCharacters.isSuperset(of: hostnameCharacters) else {
            return .invalidHostnameCharacters
        }
        
        // Basic structure checks
        if hostname.hasPrefix(".") || hostname.hasSuffix(".") ||
           hostname.hasPrefix("-") || hostname.hasSuffix("-") {
            return .invalidHostnameCharacters
        }
        
        // Check for consecutive dots
        if hostname.contains("..") {
            return .invalidHostnameCharacters
        }
        
        return nil
    }
    
    private static func validatePort(_ port: Int) -> ValidationError? {
        guard port >= minPort && port <= maxPort else {
            return .invalidPort(value: port, min: minPort, max: maxPort)
        }
        return nil
    }
}

// MARK: - GatewayCredentials URL Building Extension

extension KeychainManager.GatewayCredentials {
    
    /// Build a WebSocket URL from the credentials.
    /// - Returns: The WebSocket URL or nil if invalid
    func buildWebSocketURL() -> URL? {
        let scheme = useTLS ? "wss" : "ws"
        let urlString = "\(scheme)://\(host):\(port)"
        return URL(string: urlString)
    }
    
    /// Validate the credentials and return a validation result.
    /// - Returns: URLValidator.ValidationResult with details
    func validate() -> URLValidator.ValidationResult {
        return URLValidator.validate(hostname: host, port: port, useTLS: useTLS)
    }
}
