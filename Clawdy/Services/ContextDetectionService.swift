import Foundation
import CoreLocation
import CoreBluetooth
import UIKit

/// Service for detecting user context (location, time, device state, driving mode).
/// Provides context information to enhance agent interactions.
/// 
/// Priority hierarchy for context mode detection:
/// 1. Manual override (user explicitly sets mode)
/// 2. CarPlay connection (iOS 16+)
/// 3. Car Bluetooth device (filtered by keywords)
/// 4. GPS geofencing (office, home zones)
/// 5. Default mode
///
/// Implements 30-second hysteresis to prevent rapid mode flipping.
@MainActor
class ContextDetectionService: NSObject, ObservableObject {
    static let shared = ContextDetectionService()
    
    // MARK: - Context Mode
    
    /// User context mode for response adaptation
    enum ContextMode: String, Codable, CaseIterable {
        case `default` = "default"
        case driving = "driving"
        case home = "home"
        case office = "office"
        
        var displayName: String {
            switch self {
            case .default: return "Default"
            case .driving: return "Driving"
            case .home: return "Home"
            case .office: return "Office"
            }
        }
    }
    
    /// Geofence zone configuration
    struct GeofenceZone: Codable, Identifiable, Equatable {
        let id: UUID
        let name: String
        let latitude: Double
        let longitude: Double
        let radius: Double // meters
        let contextMode: ContextMode
        
        init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, radius: Double, contextMode: ContextMode) {
            self.id = id
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
            self.radius = radius
            self.contextMode = contextMode
        }
        
        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        
        var location: CLLocation {
            CLLocation(latitude: latitude, longitude: longitude)
        }
    }
    
    // MARK: - Types
    
    /// User context snapshot
    struct ContextSnapshot: Codable {
        let timestamp: Date
        let timeOfDay: TimeOfDay
        let dayOfWeek: DayOfWeek
        let location: LocationContext?
        let deviceState: DeviceState
        let contextMode: ContextMode
    }
    
    enum TimeOfDay: String, Codable {
        case earlyMorning // 5-8 AM
        case morning      // 8-12 PM
        case afternoon    // 12-5 PM
        case evening      // 5-9 PM
        case night        // 9 PM - 5 AM
    }
    
    enum DayOfWeek: String, Codable {
        case monday, tuesday, wednesday, thursday, friday, saturday, sunday
    }
    
    struct LocationContext: Codable {
        let latitude: Double
        let longitude: Double
        let placemark: String?
        let isHome: Bool?
        let isWork: Bool?
        let activeGeofence: String?
    }
    
    struct DeviceState: Codable {
        let batteryLevel: Float
        let isCharging: Bool
        let isLowPowerMode: Bool
    }
    
    // MARK: - Constants
    
    /// Hysteresis duration to prevent rapid mode flipping (seconds)
    private static let hysteresisDuration: TimeInterval = 30
    
    /// GPS buffer around geofence radius (meters)
    private static let geofenceBuffer: Double = 10
    
    /// Keywords to identify car Bluetooth devices
    private static let carBluetoothKeywords = [
        "car", "vehicle", "auto", "ford", "tesla", "bmw", "honda",
        "toyota", "chevy", "chevrolet", "mercedes", "audi", "lexus",
        "sync", "carplay", "bluetooth audio", "hands-free"
    ]
    
    // MARK: - Published Properties
    
    /// Current context snapshot
    @Published private(set) var currentContext: ContextSnapshot?
    
    /// Current context mode (driving, home, office, default)
    @Published private(set) var currentContextMode: ContextMode = .default
    
    /// Manual override mode (when set, takes highest priority)
    @Published var manualOverride: ContextMode? {
        didSet {
            if manualOverride != oldValue {
                updateContextMode()
                saveManualOverride()
            }
        }
    }
    
    /// Whether CarPlay is currently connected
    @Published private(set) var isCarPlayConnected: Bool = false
    
    /// Whether a car Bluetooth device is connected
    @Published private(set) var isCarBluetoothConnected: Bool = false
    
    /// Configured geofence zones
    @Published private(set) var geofenceZones: [GeofenceZone] = []
    
    /// Currently active geofence (if any)
    @Published private(set) var activeGeofence: GeofenceZone?
    
    /// Last known location
    @Published private(set) var lastLocation: CLLocation?
    
    /// Whether location services are available
    @Published private(set) var locationAvailable: Bool = false
    
    // MARK: - Private Properties
    
    private var locationManager: CLLocationManager?
    private var geocoder: CLGeocoder?
    private var centralManager: CBCentralManager?
    private var connectedPeripherals: [CBPeripheral] = []
    
    /// Home location (set by user or from geofence)
    private var homeLocation: CLLocation?
    
    /// Work location (set by user or from geofence)
    private var workLocation: CLLocation?
    
    /// Whether the current mode was set via manual override (for hysteresis bypass on clear)
    private var wasFromManualOverride: Bool = false
    
    /// Proximity threshold for "at home" / "at work" detection (meters)
    private let proximityThreshold: Double = 100
    
    /// Last time context mode changed (for hysteresis)
    var lastModeChangeAt: Date = .distantPast
    
    /// Internal context mode before hysteresis is applied
    var detectedMode: ContextMode = .default
    
    /// Callback for sending context updates to gateway
    var onContextUpdate: ((ContextMode) -> Void)?
    
    // MARK: - CarPlay Connection
    
    /// Sets the CarPlay connected state and triggers context mode recalculation.
    /// Called by CarPlaySceneDelegate when CarPlay connects/disconnects.
    func setCarPlayConnected(_ connected: Bool) {
        guard connected != isCarPlayConnected else { return }
        
        isCarPlayConnected = connected
        print("[ContextDetection] CarPlay connected: \(connected)")
        
        // Trigger immediate context recalculation
        // Note: updateContextMode() calls sendContextUpdateToGateway() when mode changes,
        // so we don't call it again here to avoid duplicate RPC calls
        updateContextMode()
    }
    
    // MARK: - Test Mode Properties
    
    /// For testing: allows setting CarPlay connected state directly
    func setCarPlayConnectedForTesting(_ connected: Bool) {
        isCarPlayConnected = connected
    }
    
    /// For testing: allows setting Bluetooth car connected state directly
    func setCarBluetoothConnectedForTesting(_ connected: Bool) {
        isCarBluetoothConnected = connected
    }
    
    /// For testing: allows setting last location directly
    func setLastLocationForTesting(_ location: CLLocation?) {
        lastLocation = location
    }
    
    /// For testing: reset hysteresis state
    func resetHysteresisForTesting() {
        lastModeChangeAt = .distantPast
        detectedMode = .default
    }
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        setupLocationManager()
        setupBluetoothManager()
        loadManualOverride()
        loadGeofenceZones()
        startCarPlayMonitoring()
        updateContext()
    }
    
    /// For testing - allows injection of initial state
    init(testMode: Bool) {
        super.init()
        if !testMode {
            setupLocationManager()
            setupBluetoothManager()
            loadManualOverride()
            loadGeofenceZones()
            startCarPlayMonitoring()
            updateContext()
        }
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyBest
        locationManager?.allowsBackgroundLocationUpdates = false
        geocoder = CLGeocoder()
        
        checkLocationAvailability()
    }
    
    private func setupBluetoothManager() {
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionShowPowerAlertKey: false
        ])
    }
    
    private func checkLocationAvailability() {
        let status = locationManager?.authorizationStatus ?? .notDetermined
        locationAvailable = status == .authorizedWhenInUse || status == .authorizedAlways
    }
    
    // MARK: - CarPlay Monitoring
    
    private func startCarPlayMonitoring() {
        // Monitor for CarPlay scene connections (iOS 16+)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneDidConnect(_:)),
            name: UIScene.didActivateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneDidDisconnect(_:)),
            name: UIScene.didDisconnectNotification,
            object: nil
        )
        
        // Check current CarPlay status
        checkCarPlayStatus()
    }
    
    @objc private func sceneDidConnect(_ notification: Notification) {
        checkCarPlayStatus()
    }
    
    @objc private func sceneDidDisconnect(_ notification: Notification) {
        checkCarPlayStatus()
    }
    
    private func checkCarPlayStatus() {
        // Check if any connected scene is a CarPlay scene
        let scenes = UIApplication.shared.connectedScenes
        let hasCarPlay = scenes.contains { scene in
            // CarPlay scenes have role .carTemplateApplication
            if #available(iOS 16.0, *) {
                return scene.session.role == .carTemplateApplication
            } else {
                // Fallback for older iOS - check scene configuration name
                return scene.session.configuration.name?.lowercased().contains("carplay") == true
            }
        }
        
        if hasCarPlay != isCarPlayConnected {
            isCarPlayConnected = hasCarPlay
            print("[ContextDetection] CarPlay connected: \(hasCarPlay)")
            updateContextMode()
        }
    }
    
    // MARK: - Context Mode Detection
    
    /// Detect the appropriate context mode based on available signals.
    /// Priority: Manual > CarPlay > Bluetooth > Geofence > Default
    func detectContextMode() -> ContextMode {
        // Priority 1: Manual override
        if let manual = manualOverride {
            return manual
        }
        
        // Priority 2: CarPlay connected
        if isCarPlayConnected {
            return .driving
        }
        
        // Priority 3: Car Bluetooth connected
        if isCarBluetoothConnected {
            return .driving
        }
        
        // Priority 4: Geofence match
        if let geofenceMode = detectGeofenceMode() {
            return geofenceMode
        }
        
        // Priority 5: Default
        return .default
    }
    
    /// Detect context mode from geofence zones.
    /// Returns the mode for the smallest overlapping geofence (most specific wins).
    private func detectGeofenceMode() -> ContextMode? {
        guard let location = lastLocation else { return nil }
        
        // Find all geofences the user is inside (with buffer)
        var matchingZones = geofenceZones.filter { zone in
            let distance = location.distance(from: zone.location)
            // Apply ±10m buffer around the radius
            return distance <= (zone.radius + Self.geofenceBuffer)
        }
        
        // If multiple matches, smallest radius wins (most specific)
        matchingZones.sort { $0.radius < $1.radius }
        
        if let bestMatch = matchingZones.first {
            activeGeofence = bestMatch
            return bestMatch.contextMode
        }
        
        activeGeofence = nil
        return nil
    }
    
    /// Update the current context mode with hysteresis.
    func updateContextMode() {
        let newMode = detectContextMode()
        let finalMode = applyHysteresis(newMode)
        
        if finalMode != currentContextMode {
            currentContextMode = finalMode
            print("[ContextDetection] Mode changed to: \(finalMode.rawValue)")
            
            // Notify gateway of context change
            onContextUpdate?(finalMode)
            sendContextUpdateToGateway()
        }
        
        updateContext()
    }
    
    /// Apply 30-second hysteresis to prevent rapid mode flipping.
    private func applyHysteresis(_ newMode: ContextMode) -> ContextMode {
        // Manual override bypasses hysteresis
        if manualOverride != nil {
            detectedMode = newMode
            lastModeChangeAt = Date()
            wasFromManualOverride = true
            return newMode
        }
        
        // Also bypass hysteresis when clearing manual override
        // (so we immediately recalculate based on actual context)
        if wasFromManualOverride {
            wasFromManualOverride = false
            detectedMode = newMode
            lastModeChangeAt = Date()
            return newMode
        }
        
        if newMode != detectedMode {
            let elapsed = Date().timeIntervalSince(lastModeChangeAt)
            if elapsed < Self.hysteresisDuration {
                // Too soon since last change, keep current mode
                return currentContextMode
            }
            
            // Accept the change
            detectedMode = newMode
            lastModeChangeAt = Date()
        }
        
        return newMode
    }
    
    /// Force a context mode change (bypasses hysteresis).
    /// Use for testing or explicit user actions.
    func forceContextMode(_ mode: ContextMode) {
        detectedMode = mode
        currentContextMode = mode
        lastModeChangeAt = Date()
        onContextUpdate?(mode)
        sendContextUpdateToGateway()
        updateContext()
    }
    
    // MARK: - Manual Override
    
    /// Set manual override mode and sync to gateway.
    func setManualOverride(_ mode: ContextMode?) {
        manualOverride = mode
        syncManualOverrideToGateway()
    }
    
    /// Clear manual override, returning to automatic detection.
    func clearManualOverride() {
        manualOverride = nil
        syncManualOverrideToGateway()
    }
    
    private func loadManualOverride() {
        if let rawValue = UserDefaults.standard.string(forKey: "context_manual_override"),
           let mode = ContextMode(rawValue: rawValue) {
            manualOverride = mode
        }
    }
    
    private func saveManualOverride() {
        if let mode = manualOverride {
            UserDefaults.standard.set(mode.rawValue, forKey: "context_manual_override")
        } else {
            UserDefaults.standard.removeObject(forKey: "context_manual_override")
        }
    }
    
    // MARK: - Geofence Management
    
    /// Add a new geofence zone.
    func addGeofenceZone(_ zone: GeofenceZone) {
        geofenceZones.append(zone)
        saveGeofenceZones()
        startMonitoringGeofence(zone)
        updateContextMode()
    }
    
    /// Remove a geofence zone.
    func removeGeofenceZone(_ zone: GeofenceZone) {
        geofenceZones.removeAll { $0.id == zone.id }
        saveGeofenceZones()
        stopMonitoringGeofence(zone)
        updateContextMode()
    }
    
    /// Update geofence zones from gateway data.
    func updateGeofenceZones(_ zones: [GeofenceZone]) {
        // Stop monitoring old zones
        for zone in geofenceZones {
            stopMonitoringGeofence(zone)
        }
        
        geofenceZones = zones
        saveGeofenceZones()
        
        // Start monitoring new zones
        for zone in zones {
            startMonitoringGeofence(zone)
        }
        
        updateContextMode()
    }
    
    private func loadGeofenceZones() {
        guard let data = UserDefaults.standard.data(forKey: "context_geofence_zones"),
              let zones = try? JSONDecoder().decode([GeofenceZone].self, from: data) else {
            return
        }
        geofenceZones = zones
        
        // Start monitoring loaded zones
        for zone in zones {
            startMonitoringGeofence(zone)
        }
    }
    
    private func saveGeofenceZones() {
        guard let data = try? JSONEncoder().encode(geofenceZones) else { return }
        UserDefaults.standard.set(data, forKey: "context_geofence_zones")
    }
    
    private func startMonitoringGeofence(_ zone: GeofenceZone) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            print("[ContextDetection] Geofence monitoring not available")
            return
        }
        
        let region = CLCircularRegion(
            center: zone.coordinate,
            radius: zone.radius + Self.geofenceBuffer,
            identifier: zone.id.uuidString
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        
        locationManager?.startMonitoring(for: region)
        print("[ContextDetection] Started monitoring geofence: \(zone.name)")
    }
    
    private func stopMonitoringGeofence(_ zone: GeofenceZone) {
        let region = CLCircularRegion(
            center: zone.coordinate,
            radius: zone.radius + Self.geofenceBuffer,
            identifier: zone.id.uuidString
        )
        locationManager?.stopMonitoring(for: region)
        print("[ContextDetection] Stopped monitoring geofence: \(zone.name)")
    }
    
    // MARK: - Gateway Integration
    
    /// Fetch geofence zones from gateway and sync to local detection.
    func fetchGeofenceZonesFromGateway() async {
        print("[ContextDetection] Fetching geofence zones from gateway...")
        
        // Fetch preferences from gateway via ContextPreferencesManager
        await ContextPreferencesManager.shared.fetchFromGateway()
        
        // Map gateway zones to local geofence zones
        await syncGeofenceZonesFromPreferences()
    }
    
    /// Sync geofence zones from ContextPreferencesManager to local detection service.
    @MainActor
    func syncGeofenceZonesFromPreferences() {
        let prefs = ContextPreferencesManager.shared.preferences
        var zones: [GeofenceZone] = []
        
        // Map home zone if configured
        if let home = prefs?.home {
            let homeZone = GeofenceZone(
                name: home.name,
                latitude: home.latitude,
                longitude: home.longitude,
                radius: home.radius,
                contextMode: .home
            )
            zones.append(homeZone)
        }
        
        // Map office zone if configured
        if let office = prefs?.office {
            let officeZone = GeofenceZone(
                name: office.name,
                latitude: office.latitude,
                longitude: office.longitude,
                radius: office.radius,
                contextMode: .office
            )
            zones.append(officeZone)
        }
        
        // Update local geofence zones
        if !zones.isEmpty || !geofenceZones.isEmpty {
            updateGeofenceZones(zones)
            print("[ContextDetection] Synced \(zones.count) geofence zones from gateway")
        }
    }
    
    /// Send context mode update to gateway via RPC.
    private func sendContextUpdateToGateway() {
        print("[ContextDetection] Sending context mode update to gateway: \(currentContextMode.rawValue)")
        
        Task { @MainActor in
            // Build context update parameters
            let contextDict = getContextDictionary()
            
            // Include current mode and detection signals
            // Only add manualOverride to params when non-nil to ensure JSON-serializable types
            var params: [String: Any] = [
                "mode": currentContextMode.rawValue,
                "context": contextDict
            ]
            
            // Include manual override if set (only add key when value exists)
            if let manual = manualOverride {
                params["manualOverride"] = manual.rawValue
            }
            
            do {
                // Send via gateway RPC
                _ = try await GatewayDualConnectionManager.shared.request(
                    method: "context.update",
                    params: params
                )
                print("[ContextDetection] Context update sent successfully")
            } catch {
                print("[ContextDetection] Failed to send context update: \(error.localizedDescription)")
            }
        }
    }
    
    /// Sync manual override to ContextPreferencesManager for gateway persistence.
    private func syncManualOverrideToGateway() {
        Task { @MainActor in
            do {
                // Convert ContextMode to ManualOverrideMode if applicable
                let overrideMode: ManualOverrideMode?
                if let mode = manualOverride {
                    switch mode {
                    case .driving: overrideMode = .driving
                    case .office: overrideMode = .office
                    case .home: overrideMode = .home
                    case .default: overrideMode = nil
                    }
                } else {
                    overrideMode = nil
                }
                
                try await ContextPreferencesManager.shared.setManualOverride(overrideMode)
                print("[ContextDetection] Manual override synced to gateway")
            } catch {
                print("[ContextDetection] Failed to sync manual override: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Context Detection
    
    /// Update the current context snapshot.
    func updateContext() {
        let now = Date()
        
        currentContext = ContextSnapshot(
            timestamp: now,
            timeOfDay: detectTimeOfDay(now),
            dayOfWeek: detectDayOfWeek(now),
            location: buildLocationContext(),
            deviceState: detectDeviceState(),
            contextMode: currentContextMode
        )
    }
    
    /// Get the current context as a dictionary for sending to the gateway.
    func getContextDictionary() -> [String: Any] {
        updateContext()
        
        guard let context = currentContext else {
            return [:]
        }
        
        var dict: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: context.timestamp),
            "timeOfDay": context.timeOfDay.rawValue,
            "dayOfWeek": context.dayOfWeek.rawValue,
            "contextMode": context.contextMode.rawValue,
            "deviceState": [
                "batteryLevel": context.deviceState.batteryLevel,
                "isCharging": context.deviceState.isCharging,
                "isLowPowerMode": context.deviceState.isLowPowerMode
            ]
        ]
        
        if let location = context.location {
            var locationDict: [String: Any] = [
                "latitude": location.latitude,
                "longitude": location.longitude
            ]
            if let placemark = location.placemark {
                locationDict["placemark"] = placemark
            }
            if let isHome = location.isHome {
                locationDict["isHome"] = isHome
            }
            if let isWork = location.isWork {
                locationDict["isWork"] = isWork
            }
            if let activeGeofence = location.activeGeofence {
                locationDict["activeGeofence"] = activeGeofence
            }
            dict["location"] = locationDict
        }
        
        // Add detection signals - only include values when present (no Optionals in JSON)
        var detectionSignals: [String: Any] = [
            "carPlayConnected": isCarPlayConnected,
            "carBluetoothConnected": isCarBluetoothConnected
        ]
        if let manual = manualOverride {
            detectionSignals["manualOverride"] = manual.rawValue
        }
        if let geofence = activeGeofence {
            detectionSignals["activeGeofence"] = geofence.name
        }
        dict["detectionSignals"] = detectionSignals
        
        return dict
    }
    
    // MARK: - Detection Helpers
    
    private func detectTimeOfDay(_ date: Date) -> TimeOfDay {
        let hour = Calendar.current.component(.hour, from: date)
        
        switch hour {
        case 5..<8:
            return .earlyMorning
        case 8..<12:
            return .morning
        case 12..<17:
            return .afternoon
        case 17..<21:
            return .evening
        default:
            return .night
        }
    }
    
    private func detectDayOfWeek(_ date: Date) -> DayOfWeek {
        let weekday = Calendar.current.component(.weekday, from: date)
        
        switch weekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }
    
    private func detectDeviceState() -> DeviceState {
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        return DeviceState(
            batteryLevel: UIDevice.current.batteryLevel,
            isCharging: UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
    
    private func buildLocationContext() -> LocationContext? {
        guard let location = lastLocation else {
            return nil
        }
        
        var isHome: Bool?
        var isWork: Bool?
        
        if let home = homeLocation {
            isHome = location.distance(from: home) < proximityThreshold
        }
        
        if let work = workLocation {
            isWork = location.distance(from: work) < proximityThreshold
        }
        
        return LocationContext(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            placemark: nil, // Set via geocoding
            isHome: isHome,
            isWork: isWork,
            activeGeofence: activeGeofence?.name
        )
    }
    
    // MARK: - Location Management
    
    /// Request location authorization.
    func requestLocationAuthorization() {
        locationManager?.requestWhenInUseAuthorization()
    }
    
    /// Request a single location update.
    func requestLocationUpdate() {
        guard locationAvailable else {
            print("[ContextDetectionService] Location not available")
            return
        }
        
        locationManager?.requestLocation()
    }
    
    /// Start continuous location updates.
    func startLocationUpdates() {
        guard locationAvailable else {
            print("[ContextDetectionService] Location not available")
            return
        }
        
        locationManager?.startUpdatingLocation()
    }
    
    /// Stop continuous location updates.
    func stopLocationUpdates() {
        locationManager?.stopUpdatingLocation()
    }
    
    /// Set the home location for proximity detection.
    func setHomeLocation(_ location: CLLocation) {
        homeLocation = location
        print("[ContextDetectionService] Home location set")
    }
    
    /// Set the work location for proximity detection.
    func setWorkLocation(_ location: CLLocation) {
        workLocation = location
        print("[ContextDetectionService] Work location set")
    }
}

// MARK: - CLLocationManagerDelegate

extension ContextDetectionService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            lastLocation = location
            updateContextMode()
            print("[ContextDetectionService] Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[ContextDetectionService] Location error: \(error.localizedDescription)")
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            checkLocationAvailability()
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in
            print("[ContextDetection] Entered geofence: \(region.identifier)")
            updateContextMode()
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            print("[ContextDetection] Exited geofence: \(region.identifier)")
            updateContextMode()
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension ContextDetectionService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn {
                checkConnectedBluetoothDevices()
            } else {
                isCarBluetoothConnected = false
                updateContextMode()
            }
        }
    }
    
    @MainActor
    private func checkConnectedBluetoothDevices() {
        // Check for connected peripherals that match car keywords
        // Note: This requires the device to have been previously discovered/connected
        // In practice, we also listen for connection notifications
        
        // For already-paired devices, we can check EAAccessoryManager
        // But for privacy reasons, iOS limits what info we can get about BT devices
        // This is a best-effort detection
        
        let hasCarDevice = checkForCarAudioDevice()
        
        if hasCarDevice != isCarBluetoothConnected {
            isCarBluetoothConnected = hasCarDevice
            print("[ContextDetection] Car Bluetooth connected: \(hasCarDevice)")
            updateContextMode()
        }
    }
    
    private func checkForCarAudioDevice() -> Bool {
        // Check audio route for car-related outputs
        let audioSession = AVAudioSession.sharedInstance()
        let currentRoute = audioSession.currentRoute
        
        for output in currentRoute.outputs {
            let portName = output.portName.lowercased()
            let portType = output.portType.rawValue.lowercased()
            
            // Check if the output matches car keywords
            for keyword in Self.carBluetoothKeywords {
                if portName.contains(keyword) || portType.contains(keyword) {
                    return true
                }
            }
            
            // Bluetooth A2DP could be a car stereo
            if output.portType == .bluetoothA2DP {
                // Check the device name for car keywords
                for keyword in Self.carBluetoothKeywords {
                    if portName.contains(keyword) {
                        return true
                    }
                }
            }
        }
        
        return false
    }
}

// MARK: - AVFoundation Import

import AVFoundation
