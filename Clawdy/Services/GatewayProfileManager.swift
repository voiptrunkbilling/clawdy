import Foundation
import Combine
import Security

/// Manages multiple gateway profiles for dev/prod switching and team testing.
/// Handles profile storage, switching, and per-profile credentials.
@MainActor
class GatewayProfileManager: ObservableObject {
    // MARK: - Singleton
    
    static let shared = GatewayProfileManager()
    
    // MARK: - Published Properties
    
    /// All gateway profiles
    @Published private(set) var profiles: [GatewayProfile] = []
    
    /// Currently active profile
    @Published private(set) var activeProfile: GatewayProfile?
    
    /// Whether a profile switch is in progress
    @Published private(set) var isSwitching: Bool = false
    
    // MARK: - Storage Keys
    
    private static let profilesKey = "com.clawdy.gateway.profiles"
    private static let activeProfileIdKey = "com.clawdy.gateway.activeProfileId"
    private static let keychainService = "com.clawdy.gateway.profile"
    
    // MARK: - Initialization
    
    private init() {
        loadProfiles()
        migrateExistingCredentialsIfNeeded()
    }
    
    // MARK: - Profile Management
    
    /// Add a new profile
    func addProfile(_ profile: GatewayProfile) {
        var newProfile = profile
        
        // If this is the first profile or marked as primary, ensure only one primary
        if profiles.isEmpty || profile.isPrimary {
            newProfile.isPrimary = true
            profiles = profiles.map { p in
                var updated = p
                updated.isPrimary = false
                return updated
            }
        }
        
        profiles.append(newProfile)
        saveProfiles()
        
        // If this is the first profile, make it active
        if profiles.count == 1 {
            setActiveProfile(newProfile)
        }
    }
    
    /// Update an existing profile
    func updateProfile(_ profile: GatewayProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        
        var updatedProfile = profile
        
        // If setting as primary, unset others
        if profile.isPrimary {
            profiles = profiles.map { p in
                var updated = p
                updated.isPrimary = false
                return updated
            }
        }
        
        profiles[index] = updatedProfile
        saveProfiles()
        
        // Update active profile if it was the one being edited
        if activeProfile?.id == profile.id {
            activeProfile = updatedProfile
        }
    }
    
    /// Delete a profile
    func deleteProfile(_ profile: GatewayProfile) {
        // Don't allow deleting the last profile
        guard profiles.count > 1 else { return }
        
        // Clear credentials for this profile
        clearCredentials(for: profile)
        
        profiles.removeAll { $0.id == profile.id }
        
        // If we deleted the primary, make the first one primary
        if profile.isPrimary, let first = profiles.first {
            var updated = first
            updated.isPrimary = true
            if let index = profiles.firstIndex(where: { $0.id == first.id }) {
                profiles[index] = updated
            }
        }
        
        // If we deleted the active profile, switch to primary
        if activeProfile?.id == profile.id {
            if let primary = profiles.first(where: { $0.isPrimary }) {
                setActiveProfile(primary)
            } else if let first = profiles.first {
                setActiveProfile(first)
            }
        }
        
        saveProfiles()
    }
    
    /// Set a profile as the active one (triggers connection switch)
    func setActiveProfile(_ profile: GatewayProfile) {
        guard profile.id != activeProfile?.id else { return }
        
        activeProfile = profile
        UserDefaults.standard.set(profile.id.uuidString, forKey: Self.activeProfileIdKey)
        
        print("[GatewayProfileManager] Active profile set to: \(profile.name) (\(profile.host):\(profile.port))")
    }
    
    /// Switch to a profile (disconnects current, connects to new)
    func switchToProfile(_ profile: GatewayProfile) async {
        guard profile.id != activeProfile?.id else { return }
        
        isSwitching = true
        defer { isSwitching = false }
        
        print("[GatewayProfileManager] Switching from \(activeProfile?.name ?? "none") to \(profile.name)")
        
        // Disconnect current connection
        await GatewayDualConnectionManager.shared.disconnect()
        
        // Set new active profile
        setActiveProfile(profile)
        
        // Connect to new profile
        await GatewayDualConnectionManager.shared.connectIfNeeded()
    }
    
    /// Get the primary profile
    var primaryProfile: GatewayProfile? {
        profiles.first(where: { $0.isPrimary }) ?? profiles.first
    }
    
    // MARK: - Per-Profile Credentials
    
    /// Get credentials for a profile
    func getCredentials(for profile: GatewayProfile) -> KeychainManager.GatewayCredentials {
        let authToken = loadAuthToken(for: profile)
        return KeychainManager.GatewayCredentials(
            host: profile.host,
            port: profile.port,
            authToken: authToken,
            useTLS: profile.useTLS
        )
    }
    
    /// Save auth token for a profile
    func saveAuthToken(_ token: String?, for profile: GatewayProfile) {
        let key = authTokenKey(for: profile)
        
        if let token = token, !token.isEmpty {
            saveToKeychain(value: token, forKey: key)
        } else {
            deleteFromKeychain(forKey: key)
        }
    }
    
    /// Load auth token for a profile
    func loadAuthToken(for profile: GatewayProfile) -> String? {
        let key = authTokenKey(for: profile)
        return loadFromKeychain(forKey: key)
    }
    
    /// Clear all credentials for a profile
    func clearCredentials(for profile: GatewayProfile) {
        // Clear auth token
        let authKey = authTokenKey(for: profile)
        deleteFromKeychain(forKey: authKey)
        
        // Clear device tokens for this profile
        let identity = DeviceIdentityStore.loadOrCreate()
        DeviceAuthStore.clearAllTokens(deviceId: "\(identity.deviceId).\(profile.id.uuidString)")
        
        print("[GatewayProfileManager] Cleared credentials for profile: \(profile.name)")
    }
    
    /// Get device ID for a profile (includes profile ID for isolation)
    func deviceId(for profile: GatewayProfile) -> String {
        let identity = DeviceIdentityStore.loadOrCreate()
        return "\(identity.deviceId).\(profile.id.uuidString)"
    }
    
    // MARK: - Persistence
    
    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: Self.profilesKey),
              let decoded = try? JSONDecoder().decode([GatewayProfile].self, from: data) else {
            profiles = []
            return
        }
        profiles = decoded
        
        // Load active profile
        if let activeIdString = UserDefaults.standard.string(forKey: Self.activeProfileIdKey),
           let activeId = UUID(uuidString: activeIdString),
           let active = profiles.first(where: { $0.id == activeId }) {
            activeProfile = active
        } else if let primary = primaryProfile {
            activeProfile = primary
        }
        
        print("[GatewayProfileManager] Loaded \(profiles.count) profiles, active: \(activeProfile?.name ?? "none")")
    }
    
    private func saveProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: Self.profilesKey)
        print("[GatewayProfileManager] Saved \(profiles.count) profiles")
    }
    
    /// Migrate existing credentials to a default profile if no profiles exist
    private func migrateExistingCredentialsIfNeeded() {
        guard profiles.isEmpty else { return }
        
        // Check for existing gateway credentials
        if let existingCredentials = KeychainManager.shared.loadGatewayCredentials(),
           !existingCredentials.host.isEmpty {
            // Create a default "Production" profile from existing credentials
            let defaultProfile = GatewayProfile.defaultProduction(from: existingCredentials)
            profiles.append(defaultProfile)
            activeProfile = defaultProfile
            
            // Migrate auth token
            if let authToken = existingCredentials.authToken {
                saveAuthToken(authToken, for: defaultProfile)
            }
            
            saveProfiles()
            print("[GatewayProfileManager] Migrated existing credentials to default profile")
        }
    }
    
    // MARK: - Keychain Helpers
    
    private func authTokenKey(for profile: GatewayProfile) -> String {
        "\(Self.keychainService).\(profile.id.uuidString).authToken"
    }
    
    private func saveToKeychain(value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    private func loadFromKeychain(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    private func deleteFromKeychain(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Active Profile Credentials Extension

extension GatewayProfileManager {
    /// Get credentials for the active profile (for GatewayDualConnectionManager)
    var activeCredentials: KeychainManager.GatewayCredentials? {
        guard let profile = activeProfile else { return nil }
        return getCredentials(for: profile)
    }
    
    /// Whether we have a configured active profile
    var hasActiveProfile: Bool {
        activeProfile != nil && activeProfile?.host.isEmpty == false
    }
}
