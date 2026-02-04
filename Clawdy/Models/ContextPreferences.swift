import Foundation
import CoreLocation

// MARK: - Context Preferences Types

/// Geofence zone configuration for location-based context detection.
struct GeofenceZone: Codable, Equatable, Sendable {
    /// Latitude in degrees (-90 to 90)
    let latitude: Double
    /// Longitude in degrees (-180 to 180)
    let longitude: Double
    /// Radius in meters (10 to 10000)
    let radius: Double
    /// Human-readable name for the zone
    let name: String
    
    /// Validate geofence zone parameters
    var isValid: Bool {
        latitude >= -90 && latitude <= 90 &&
        longitude >= -180 && longitude <= 180 &&
        radius >= 10 && radius <= 10000 &&
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Verbosity level for AI responses in different contexts.
enum VerbosityLevel: String, Codable, CaseIterable, Sendable {
    case brief = "brief"
    case normal = "normal"
    case detailed = "detailed"
    
    var displayName: String {
        switch self {
        case .brief: return "Brief"
        case .normal: return "Normal"
        case .detailed: return "Detailed"
        }
    }
    
    var description: String {
        switch self {
        case .brief: return "Short, concise responses"
        case .normal: return "Balanced responses"
        case .detailed: return "Thorough, comprehensive responses"
        }
    }
}

/// Manual override mode for context detection.
enum ManualOverrideMode: String, Codable, CaseIterable, Sendable {
    case driving = "driving"
    case office = "office"
    case home = "home"
    
    var displayName: String {
        switch self {
        case .driving: return "Driving"
        case .office: return "Office"
        case .home: return "Home"
        }
    }
}

/// Driving mode settings - used when in motion.
struct DrivingModeSettings: Codable, Equatable, Sendable {
    /// Response verbosity (default: brief for safety)
    var verbosity: VerbosityLevel
    /// Whether to auto-enable hands-free mode
    var handsFree: Bool
    
    static let `default` = DrivingModeSettings(
        verbosity: .brief,
        handsFree: true
    )
}

/// Mode settings for location-based contexts (office, home).
struct ModeSettings: Codable, Equatable, Sendable {
    /// Response verbosity
    var verbosity: VerbosityLevel
    
    static let defaultOffice = ModeSettings(verbosity: .detailed)
    static let defaultHome = ModeSettings(verbosity: .normal)
}

/// User context preferences stored on the gateway.
/// Synced across all devices for the same user.
struct UserContextPreferences: Codable, Equatable, Sendable {
    /// Device ID this preference set belongs to
    let deviceId: String
    /// Office geofence zone (optional)
    var office: GeofenceZone?
    /// Home geofence zone (optional)
    var home: GeofenceZone?
    /// Driving mode settings
    var drivingMode: DrivingModeSettings
    /// Office mode settings
    var officeMode: ModeSettings
    /// Home mode settings
    var homeMode: ModeSettings
    /// Manual override (nil = auto-detect)
    var manualOverride: ManualOverrideMode?
    /// Last update timestamp (milliseconds since epoch)
    var updatedAt: Int64
    
    static func `default`(deviceId: String) -> UserContextPreferences {
        UserContextPreferences(
            deviceId: deviceId,
            office: nil,
            home: nil,
            drivingMode: .default,
            officeMode: .defaultOffice,
            homeMode: .defaultHome,
            manualOverride: nil,
            updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }
}

// MARK: - RPC Request/Response Types

/// Parameters for context.update RPC call
struct ContextUpdateParams: Codable, Sendable {
    var office: GeofenceZone?
    var home: GeofenceZone?
    var drivingMode: DrivingModeSettings?
    var officeMode: ModeSettings?
    var homeMode: ModeSettings?
    var manualOverride: ManualOverrideMode?
    
    /// Flag to clear office zone (send null)
    var clearOffice: Bool = false
    /// Flag to clear home zone (send null)
    var clearHome: Bool = false
    /// Flag to clear manual override (send null)
    var clearManualOverride: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case office, home, drivingMode, officeMode, homeMode, manualOverride
    }
    
    /// Convert to dictionary for RPC call, handling null values
    func toParams() -> [String: Any] {
        var params: [String: Any] = [:]
        
        if clearOffice {
            params["office"] = NSNull()
        } else if let office = office {
            params["office"] = [
                "latitude": office.latitude,
                "longitude": office.longitude,
                "radius": office.radius,
                "name": office.name
            ]
        }
        
        if clearHome {
            params["home"] = NSNull()
        } else if let home = home {
            params["home"] = [
                "latitude": home.latitude,
                "longitude": home.longitude,
                "radius": home.radius,
                "name": home.name
            ]
        }
        
        if let drivingMode = drivingMode {
            params["drivingMode"] = [
                "verbosity": drivingMode.verbosity.rawValue,
                "handsFree": drivingMode.handsFree
            ]
        }
        
        if let officeMode = officeMode {
            params["officeMode"] = ["verbosity": officeMode.verbosity.rawValue]
        }
        
        if let homeMode = homeMode {
            params["homeMode"] = ["verbosity": homeMode.verbosity.rawValue]
        }
        
        if clearManualOverride {
            params["manualOverride"] = NSNull()
        } else if let manualOverride = manualOverride {
            params["manualOverride"] = manualOverride.rawValue
        }
        
        return params
    }
}

/// Response from context.update RPC call
struct ContextUpdateResult: Codable, Sendable {
    let updated: Bool
    let preferences: UserContextPreferences
}

/// Response from context.get RPC call
struct ContextGetResult: Codable, Sendable {
    let preferences: UserContextPreferences
}

// MARK: - Context Preferences Manager

/// Manages local caching and gateway sync of context preferences.
@MainActor
class ContextPreferencesManager: ObservableObject {
    static let shared = ContextPreferencesManager()
    
    private let userDefaultsKey = "com.clawdy.contextPreferences"
    
    /// Current preferences (cached locally, synced with gateway)
    @Published private(set) var preferences: UserContextPreferences?
    
    /// Whether preferences are currently being synced
    @Published private(set) var isSyncing = false
    
    /// Last sync error (nil if last sync succeeded)
    @Published private(set) var lastSyncError: String?
    
    /// Last successful sync timestamp
    @Published private(set) var lastSyncedAt: Date?
    
    private init() {
        // Load cached preferences on init
        self.preferences = Self.loadCached()
        
        // Set up listener for context updates from other devices
        Task { @MainActor in
            await setupContextUpdateListener()
        }
    }
    
    /// Set up listener for context.updated broadcasts from gateway
    private func setupContextUpdateListener() async {
        let manager = GatewayDualConnectionManager.shared
        manager.onContextUpdated = { [weak self] updatedPreferences in
            Task { @MainActor in
                guard let self = self else { return }
                // Update local cache with preferences from another device
                self.saveToCache(updatedPreferences)
            }
        }
    }
    
    // MARK: - Local Cache
    
    /// Load cached preferences from UserDefaults
    private static func loadCached() -> UserContextPreferences? {
        guard let data = UserDefaults.standard.data(forKey: "com.clawdy.contextPreferences"),
              let prefs = try? JSONDecoder().decode(UserContextPreferences.self, from: data) else {
            return nil
        }
        return prefs
    }
    
    /// Save preferences to local cache
    private func saveToCache(_ prefs: UserContextPreferences) {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
        self.preferences = prefs
        
        // Sync geofence zones to ContextDetectionService
        syncToContextDetectionService(prefs)
    }
    
    /// Sync geofence zones to ContextDetectionService for local detection
    private func syncToContextDetectionService(_ prefs: UserContextPreferences) {
        let service = ContextDetectionService.shared
        
        if let home = prefs.home {
            let location = CLLocation(latitude: home.latitude, longitude: home.longitude)
            service.setHomeLocation(location)
        }
        
        if let office = prefs.office {
            let location = CLLocation(latitude: office.latitude, longitude: office.longitude)
            service.setWorkLocation(location)
        }
    }
    
    // MARK: - Gateway Sync
    
    /// Fetch preferences from gateway
    /// Call this on app launch and when connection is established
    func fetchFromGateway() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let result = try await GatewayContextService.shared.getPreferences()
            saveToCache(result.preferences)
            lastSyncError = nil
            lastSyncedAt = Date()
        } catch {
            lastSyncError = error.localizedDescription
        }
    }
    
    /// Update preferences on gateway
    /// - Parameter params: Update parameters
    /// - Returns: Updated preferences on success
    @discardableResult
    func updateOnGateway(_ params: ContextUpdateParams) async throws -> UserContextPreferences {
        isSyncing = true
        defer { isSyncing = false }
        
        let result = try await GatewayContextService.shared.updatePreferences(params)
        saveToCache(result.preferences)
        lastSyncError = nil
        lastSyncedAt = Date()
        return result.preferences
    }
    
    /// Set office geofence zone
    func setOfficeZone(_ zone: GeofenceZone?) async throws {
        var params = ContextUpdateParams()
        if let zone = zone {
            params.office = zone
        } else {
            params.clearOffice = true
        }
        try await updateOnGateway(params)
    }
    
    /// Set home geofence zone
    func setHomeZone(_ zone: GeofenceZone?) async throws {
        var params = ContextUpdateParams()
        if let zone = zone {
            params.home = zone
        } else {
            params.clearHome = true
        }
        try await updateOnGateway(params)
    }
    
    /// Set driving mode settings
    func setDrivingMode(_ settings: DrivingModeSettings) async throws {
        var params = ContextUpdateParams()
        params.drivingMode = settings
        try await updateOnGateway(params)
    }
    
    /// Set office mode settings
    func setOfficeMode(_ settings: ModeSettings) async throws {
        var params = ContextUpdateParams()
        params.officeMode = settings
        try await updateOnGateway(params)
    }
    
    /// Set home mode settings
    func setHomeMode(_ settings: ModeSettings) async throws {
        var params = ContextUpdateParams()
        params.homeMode = settings
        try await updateOnGateway(params)
    }
    
    /// Set or clear manual override
    func setManualOverride(_ mode: ManualOverrideMode?) async throws {
        var params = ContextUpdateParams()
        if let mode = mode {
            params.manualOverride = mode
        } else {
            params.clearManualOverride = true
        }
        try await updateOnGateway(params)
    }
    
    /// Clear all cached preferences
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        preferences = nil
        lastSyncedAt = nil
        lastSyncError = nil
    }
}

// MARK: - Gateway Context Service

/// Service for making context RPC calls to the gateway.
actor GatewayContextService {
    static let shared = GatewayContextService()
    
    private init() {}
    
    /// Get current context preferences from gateway
    func getPreferences() async throws -> ContextGetResult {
        let manager = await GatewayDualConnectionManager.shared
        let data = try await manager.request(method: "context.get", params: nil)
        
        let decoder = JSONDecoder()
        return try decoder.decode(ContextGetResult.self, from: data)
    }
    
    /// Update context preferences on gateway
    func updatePreferences(_ params: ContextUpdateParams) async throws -> ContextUpdateResult {
        let manager = await GatewayDualConnectionManager.shared
        let rpcParams = params.toParams()
        let data = try await manager.request(method: "context.update", params: rpcParams)
        
        let decoder = JSONDecoder()
        return try decoder.decode(ContextUpdateResult.self, from: data)
    }
}
