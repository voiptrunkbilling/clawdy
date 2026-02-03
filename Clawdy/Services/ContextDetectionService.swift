import Foundation
import CoreLocation

/// Service for detecting user context (location, time, device state).
/// Provides context information to enhance agent interactions.
@MainActor
class ContextDetectionService: NSObject, ObservableObject {
    static let shared = ContextDetectionService()
    
    // MARK: - Types
    
    /// User context snapshot
    struct ContextSnapshot: Codable {
        let timestamp: Date
        let timeOfDay: TimeOfDay
        let dayOfWeek: DayOfWeek
        let location: LocationContext?
        let deviceState: DeviceState
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
    }
    
    struct DeviceState: Codable {
        let batteryLevel: Float
        let isCharging: Bool
        let isLowPowerMode: Bool
    }
    
    // MARK: - Published Properties
    
    /// Current context snapshot
    @Published private(set) var currentContext: ContextSnapshot?
    
    /// Last known location
    @Published private(set) var lastLocation: CLLocation?
    
    /// Whether location services are available
    @Published private(set) var locationAvailable: Bool = false
    
    // MARK: - Properties
    
    private var locationManager: CLLocationManager?
    private var geocoder: CLGeocoder?
    
    /// Home location (set by user)
    private var homeLocation: CLLocation?
    
    /// Work location (set by user)
    private var workLocation: CLLocation?
    
    /// Proximity threshold for "at home" / "at work" detection (meters)
    private let proximityThreshold: Double = 100
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        setupLocationManager()
        updateContext()
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
        geocoder = CLGeocoder()
        
        checkLocationAvailability()
    }
    
    private func checkLocationAvailability() {
        let status = locationManager?.authorizationStatus ?? .notDetermined
        locationAvailable = status == .authorizedWhenInUse || status == .authorizedAlways
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
            deviceState: detectDeviceState()
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
            dict["location"] = locationDict
        }
        
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
            isWork: isWork
        )
    }
    
    // MARK: - Location Management
    
    /// Request a single location update.
    func requestLocationUpdate() {
        guard locationAvailable else {
            print("[ContextDetectionService] Location not available")
            return
        }
        
        locationManager?.requestLocation()
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
            updateContext()
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
}

// MARK: - UIDevice Extension

import UIKit
