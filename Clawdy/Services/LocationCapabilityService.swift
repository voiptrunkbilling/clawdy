import CoreLocation
import Foundation
import UIKit

/// Service for handling location capabilities for node invocations.
/// Uses CoreLocation for GPS access.
@MainActor
final class LocationCapabilityService: NSObject, CLLocationManagerDelegate {
    
    // MARK: - Errors
    
    enum LocationServiceError: LocalizedError {
        case servicesDisabled
        case permissionDenied
        case permissionRestricted
        case timeout
        case unavailable
        case backgroundRestricted
        
        var errorDescription: String? {
            switch self {
            case .servicesDisabled:
                return "Location services are disabled on this device"
            case .permissionDenied:
                return "Location permission denied. Enable in Settings > Clawdy > Location"
            case .permissionRestricted:
                return "Location access is restricted on this device"
            case .timeout:
                return "Location request timed out"
            case .unavailable:
                return "Location unavailable"
            case .backgroundRestricted:
                return "Location requires app to be in foreground or 'Always' permission"
            }
        }
    }
    
    // MARK: - Singleton
    
    static let shared = LocationCapabilityService()
    
    // MARK: - Properties
    
    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var cachedAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    // MARK: - Public API
    
    /// Get current location with specified parameters.
    /// - Parameter params: Location request parameters
    /// - Returns: LocationGetResult with coordinates and metadata
    func getLocation(params: LocationGetParams) async -> LocationGetResult {
        // Check if app is in background
        let isBackground = UIApplication.shared.applicationState == .background
        
        // If backgrounded and we don't have "always" permission, return error
        if isBackground {
            let status = cachedAuthorizationStatus
            if status != .authorizedAlways {
                return LocationGetResult(
                    latitude: nil,
                    longitude: nil,
                    accuracy: nil,
                    altitude: nil,
                    altitudeAccuracy: nil,
                    speed: nil,
                    heading: nil,
                    timestamp: nil,
                    error: LocationServiceError.backgroundRestricted.errorDescription
                )
            }
        }
        
        // Check if location services are enabled
        guard CLLocationManager.locationServicesEnabled() else {
            return LocationGetResult(
                latitude: nil,
                longitude: nil,
                accuracy: nil,
                altitude: nil,
                altitudeAccuracy: nil,
                speed: nil,
                heading: nil,
                timestamp: nil,
                error: LocationServiceError.servicesDisabled.errorDescription
            )
        }
        
        // Ensure we have authorization
        do {
            try await ensureAuthorization()
        } catch let error as LocationServiceError {
            return LocationGetResult(
                latitude: nil,
                longitude: nil,
                accuracy: nil,
                altitude: nil,
                altitudeAccuracy: nil,
                speed: nil,
                heading: nil,
                timestamp: nil,
                error: error.errorDescription
            )
        } catch {
            return LocationGetResult(
                latitude: nil,
                longitude: nil,
                accuracy: nil,
                altitude: nil,
                altitudeAccuracy: nil,
                speed: nil,
                heading: nil,
                timestamp: nil,
                error: error.localizedDescription
            )
        }
        
        // Check for cached location within maxAgeMs
        let maxAgeMs = params.maxAgeMs ?? 60000 // Default: 1 minute
        if let cached = manager.location {
            let ageMs = Date().timeIntervalSince(cached.timestamp) * 1000
            if ageMs <= Double(maxAgeMs) {
                return makeResult(from: cached)
            }
        }
        
        // Set desired accuracy
        manager.desiredAccuracy = mapAccuracy(params.desiredAccuracy)
        
        // Request location with timeout
        let timeoutMs = params.timeoutMs ?? 10000 // Default: 10 seconds
        
        do {
            let location = try await withTimeout(timeoutMs: timeoutMs) {
                try await self.requestLocation()
            }
            return makeResult(from: location)
        } catch let error as LocationServiceError {
            return LocationGetResult(
                latitude: nil,
                longitude: nil,
                accuracy: nil,
                altitude: nil,
                altitudeAccuracy: nil,
                speed: nil,
                heading: nil,
                timestamp: nil,
                error: error.errorDescription
            )
        } catch {
            return LocationGetResult(
                latitude: nil,
                longitude: nil,
                accuracy: nil,
                altitude: nil,
                altitudeAccuracy: nil,
                speed: nil,
                heading: nil,
                timestamp: nil,
                error: error.localizedDescription
            )
        }
    }
    
    /// Check current authorization status.
    var authorizationStatus: CLAuthorizationStatus {
        cachedAuthorizationStatus
    }
    
    // MARK: - Authorization
    
    /// Ensure location authorization is granted, requesting if needed.
    private func ensureAuthorization() async throws {
        let status = cachedAuthorizationStatus
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            return
            
        case .notDetermined:
            // Request "when in use" authorization
            manager.requestWhenInUseAuthorization()
            let newStatus = await awaitAuthorizationChange()
            
            switch newStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                return
            case .denied:
                throw LocationServiceError.permissionDenied
            case .restricted:
                throw LocationServiceError.permissionRestricted
            default:
                throw LocationServiceError.permissionDenied
            }
            
        case .denied:
            throw LocationServiceError.permissionDenied
            
        case .restricted:
            throw LocationServiceError.permissionRestricted
            
        @unknown default:
            throw LocationServiceError.permissionDenied
        }
    }
    
    /// Wait for authorization status change.
    private func awaitAuthorizationChange() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            self.authContinuation = continuation
        }
    }
    
    // MARK: - Location Request
    
    /// Request a single location update.
    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            self.manager.requestLocation()
        }
    }
    
    // MARK: - Timeout
    
    /// Execute operation with timeout.
    private func withTimeout<T: Sendable>(
        timeoutMs: Int,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Add the main operation
            group.addTask {
                try await operation()
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                throw LocationServiceError.timeout
            }
            
            // Return first result, cancel the other
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    // MARK: - Accuracy Mapping
    
    /// Map accuracy string to CLLocationAccuracy.
    private func mapAccuracy(_ accuracy: String?) -> CLLocationAccuracy {
        switch accuracy?.lowercased() {
        case "best":
            return kCLLocationAccuracyBest
        case "nearesttenmeters":
            return kCLLocationAccuracyNearestTenMeters
        case "hundredmeters":
            return kCLLocationAccuracyHundredMeters
        case "kilometer":
            return kCLLocationAccuracyKilometer
        case "threekilometers":
            return kCLLocationAccuracyThreeKilometers
        default:
            return kCLLocationAccuracyBest
        }
    }
    
    // MARK: - Result Construction
    
    /// Convert CLLocation to LocationGetResult.
    private func makeResult(from location: CLLocation) -> LocationGetResult {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return LocationGetResult(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy,
            altitude: location.altitude,
            altitudeAccuracy: location.verticalAccuracy,
            speed: location.speed >= 0 ? location.speed : nil,
            heading: location.course >= 0 ? location.course : nil,
            timestamp: isoFormatter.string(from: location.timestamp),
            error: nil
        )
    }
    
    // MARK: - CLLocationManagerDelegate
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.cachedAuthorizationStatus = status
            if let cont = self.authContinuation {
                self.authContinuation = nil
                cont.resume(returning: status)
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let locs = locations
        Task { @MainActor in
            guard let cont = self.locationContinuation else { return }
            self.locationContinuation = nil
            
            if let latest = locs.last {
                cont.resume(returning: latest)
            } else {
                cont.resume(throwing: LocationServiceError.unavailable)
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let err = error
        Task { @MainActor in
            guard let cont = self.locationContinuation else { return }
            self.locationContinuation = nil
            cont.resume(throwing: err)
        }
    }
}
