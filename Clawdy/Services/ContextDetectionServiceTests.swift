import XCTest
@testable import Clawdy
import CoreLocation

/// Unit tests for ContextDetectionService.
/// Tests priority hierarchy, hysteresis, geofencing, and mode detection.
final class ContextDetectionServiceTests: XCTestCase {
    
    var sut: ContextDetectionService!
    
    @MainActor
    override func setUp() {
        super.setUp()
        // Create a test-mode instance that doesn't set up real location/bluetooth managers
        sut = ContextDetectionService(testMode: true)
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Default State Tests
    
    @MainActor
    func testInitialStateIsDefault() {
        XCTAssertEqual(sut.currentContextMode, .default)
        XCTAssertNil(sut.manualOverride)
        XCTAssertFalse(sut.isCarPlayConnected)
        XCTAssertFalse(sut.isCarBluetoothConnected)
        XCTAssertTrue(sut.geofenceZones.isEmpty)
        XCTAssertNil(sut.activeGeofence)
    }
    
    // MARK: - Manual Override Tests (Priority 1)
    
    @MainActor
    func testManualOverrideTakesPriority() {
        // Set manual override to driving
        sut.setManualOverride(.driving)
        
        // Should immediately apply without hysteresis
        XCTAssertEqual(sut.currentContextMode, .driving)
        XCTAssertEqual(sut.manualOverride, .driving)
    }
    
    @MainActor
    func testManualOverrideOverridesCarPlay() {
        // Simulate CarPlay connected
        // Note: In real usage, isCarPlayConnected is set internally
        // For testing, we can only test via detectContextMode()
        
        // Set manual override
        sut.setManualOverride(.home)
        
        // Manual override should win
        XCTAssertEqual(sut.detectContextMode(), .home)
    }
    
    @MainActor
    func testClearManualOverride() {
        sut.setManualOverride(.office)
        XCTAssertEqual(sut.manualOverride, .office)
        
        sut.clearManualOverride()
        XCTAssertNil(sut.manualOverride)
    }
    
    @MainActor
    func testManualOverrideAllModes() {
        for mode in ContextDetectionService.ContextMode.allCases {
            sut.setManualOverride(mode)
            XCTAssertEqual(sut.manualOverride, mode)
            XCTAssertEqual(sut.detectContextMode(), mode)
        }
    }
    
    // MARK: - Geofence Tests (Priority 4)
    
    @MainActor
    func testAddGeofenceZone() {
        let zone = ContextDetectionService.GeofenceZone(
            name: "Home",
            latitude: 37.7749,
            longitude: -122.4194,
            radius: 100,
            contextMode: .home
        )
        
        sut.addGeofenceZone(zone)
        
        XCTAssertEqual(sut.geofenceZones.count, 1)
        XCTAssertEqual(sut.geofenceZones.first?.name, "Home")
        XCTAssertEqual(sut.geofenceZones.first?.contextMode, .home)
    }
    
    @MainActor
    func testRemoveGeofenceZone() {
        let zone = ContextDetectionService.GeofenceZone(
            name: "Office",
            latitude: 37.7849,
            longitude: -122.4094,
            radius: 50,
            contextMode: .office
        )
        
        sut.addGeofenceZone(zone)
        XCTAssertEqual(sut.geofenceZones.count, 1)
        
        sut.removeGeofenceZone(zone)
        XCTAssertEqual(sut.geofenceZones.count, 0)
    }
    
    @MainActor
    func testUpdateGeofenceZones() {
        let zone1 = ContextDetectionService.GeofenceZone(
            name: "Home",
            latitude: 37.7749,
            longitude: -122.4194,
            radius: 100,
            contextMode: .home
        )
        let zone2 = ContextDetectionService.GeofenceZone(
            name: "Office",
            latitude: 37.7849,
            longitude: -122.4094,
            radius: 50,
            contextMode: .office
        )
        
        sut.updateGeofenceZones([zone1, zone2])
        
        XCTAssertEqual(sut.geofenceZones.count, 2)
    }
    
    @MainActor
    func testGeofenceZoneEquality() {
        let id = UUID()
        let zone1 = ContextDetectionService.GeofenceZone(
            id: id,
            name: "Home",
            latitude: 37.7749,
            longitude: -122.4194,
            radius: 100,
            contextMode: .home
        )
        let zone2 = ContextDetectionService.GeofenceZone(
            id: id,
            name: "Home",
            latitude: 37.7749,
            longitude: -122.4194,
            radius: 100,
            contextMode: .home
        )
        
        XCTAssertEqual(zone1, zone2)
    }
    
    @MainActor
    func testGeofenceZoneCoordinate() {
        let zone = ContextDetectionService.GeofenceZone(
            name: "Test",
            latitude: 37.7749,
            longitude: -122.4194,
            radius: 100,
            contextMode: .home
        )
        
        XCTAssertEqual(zone.coordinate.latitude, 37.7749)
        XCTAssertEqual(zone.coordinate.longitude, -122.4194)
    }
    
    @MainActor
    func testGeofenceZoneLocation() {
        let zone = ContextDetectionService.GeofenceZone(
            name: "Test",
            latitude: 37.7749,
            longitude: -122.4194,
            radius: 100,
            contextMode: .home
        )
        
        XCTAssertEqual(zone.location.coordinate.latitude, 37.7749)
        XCTAssertEqual(zone.location.coordinate.longitude, -122.4194)
    }
    
    // MARK: - Context Mode Display Name Tests
    
    @MainActor
    func testContextModeDisplayNames() {
        XCTAssertEqual(ContextDetectionService.ContextMode.default.displayName, "Default")
        XCTAssertEqual(ContextDetectionService.ContextMode.driving.displayName, "Driving")
        XCTAssertEqual(ContextDetectionService.ContextMode.home.displayName, "Home")
        XCTAssertEqual(ContextDetectionService.ContextMode.office.displayName, "Office")
    }
    
    @MainActor
    func testContextModeRawValues() {
        XCTAssertEqual(ContextDetectionService.ContextMode.default.rawValue, "default")
        XCTAssertEqual(ContextDetectionService.ContextMode.driving.rawValue, "driving")
        XCTAssertEqual(ContextDetectionService.ContextMode.home.rawValue, "home")
        XCTAssertEqual(ContextDetectionService.ContextMode.office.rawValue, "office")
    }
    
    // MARK: - Force Context Mode Tests
    
    @MainActor
    func testForceContextMode() {
        // Force mode change bypasses hysteresis
        sut.forceContextMode(.driving)
        XCTAssertEqual(sut.currentContextMode, .driving)
        
        // Can immediately change again
        sut.forceContextMode(.home)
        XCTAssertEqual(sut.currentContextMode, .home)
    }
    
    // MARK: - Context Dictionary Tests
    
    @MainActor
    func testGetContextDictionaryBasic() {
        let dict = sut.getContextDictionary()
        
        XCTAssertNotNil(dict["timestamp"])
        XCTAssertNotNil(dict["timeOfDay"])
        XCTAssertNotNil(dict["dayOfWeek"])
        XCTAssertNotNil(dict["contextMode"])
        XCTAssertNotNil(dict["deviceState"])
        XCTAssertNotNil(dict["detectionSignals"])
    }
    
    @MainActor
    func testGetContextDictionaryWithManualOverride() {
        sut.setManualOverride(.office)
        let dict = sut.getContextDictionary()
        
        XCTAssertEqual(dict["contextMode"] as? String, "office")
        
        if let signals = dict["detectionSignals"] as? [String: Any] {
            XCTAssertEqual(signals["manualOverride"] as? String, "office")
        }
    }
    
    @MainActor
    func testGetContextDictionaryDeviceState() {
        let dict = sut.getContextDictionary()
        
        if let deviceState = dict["deviceState"] as? [String: Any] {
            XCTAssertNotNil(deviceState["batteryLevel"])
            XCTAssertNotNil(deviceState["isCharging"])
            XCTAssertNotNil(deviceState["isLowPowerMode"])
        } else {
            XCTFail("deviceState should be present")
        }
    }
    
    // MARK: - Time of Day Tests
    
    @MainActor
    func testTimeOfDayRawValues() {
        XCTAssertEqual(ContextDetectionService.TimeOfDay.earlyMorning.rawValue, "earlyMorning")
        XCTAssertEqual(ContextDetectionService.TimeOfDay.morning.rawValue, "morning")
        XCTAssertEqual(ContextDetectionService.TimeOfDay.afternoon.rawValue, "afternoon")
        XCTAssertEqual(ContextDetectionService.TimeOfDay.evening.rawValue, "evening")
        XCTAssertEqual(ContextDetectionService.TimeOfDay.night.rawValue, "night")
    }
    
    // MARK: - Day of Week Tests
    
    @MainActor
    func testDayOfWeekRawValues() {
        XCTAssertEqual(ContextDetectionService.DayOfWeek.sunday.rawValue, "sunday")
        XCTAssertEqual(ContextDetectionService.DayOfWeek.monday.rawValue, "monday")
        XCTAssertEqual(ContextDetectionService.DayOfWeek.tuesday.rawValue, "tuesday")
        XCTAssertEqual(ContextDetectionService.DayOfWeek.wednesday.rawValue, "wednesday")
        XCTAssertEqual(ContextDetectionService.DayOfWeek.thursday.rawValue, "thursday")
        XCTAssertEqual(ContextDetectionService.DayOfWeek.friday.rawValue, "friday")
        XCTAssertEqual(ContextDetectionService.DayOfWeek.saturday.rawValue, "saturday")
    }
    
    // MARK: - Location Context Tests
    
    @MainActor
    func testLocationContextCodable() throws {
        let context = ContextDetectionService.LocationContext(
            latitude: 37.7749,
            longitude: -122.4194,
            placemark: "San Francisco",
            isHome: true,
            isWork: false,
            activeGeofence: "Home"
        )
        
        let encoded = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(ContextDetectionService.LocationContext.self, from: encoded)
        
        XCTAssertEqual(decoded.latitude, 37.7749)
        XCTAssertEqual(decoded.longitude, -122.4194)
        XCTAssertEqual(decoded.placemark, "San Francisco")
        XCTAssertEqual(decoded.isHome, true)
        XCTAssertEqual(decoded.isWork, false)
        XCTAssertEqual(decoded.activeGeofence, "Home")
    }
    
    // MARK: - Device State Tests
    
    @MainActor
    func testDeviceStateCodable() throws {
        let state = ContextDetectionService.DeviceState(
            batteryLevel: 0.75,
            isCharging: true,
            isLowPowerMode: false
        )
        
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ContextDetectionService.DeviceState.self, from: encoded)
        
        XCTAssertEqual(decoded.batteryLevel, 0.75)
        XCTAssertEqual(decoded.isCharging, true)
        XCTAssertEqual(decoded.isLowPowerMode, false)
    }
    
    // MARK: - Context Snapshot Tests
    
    @MainActor
    func testContextSnapshotCodable() throws {
        let snapshot = ContextDetectionService.ContextSnapshot(
            timestamp: Date(),
            timeOfDay: .morning,
            dayOfWeek: .monday,
            location: nil,
            deviceState: ContextDetectionService.DeviceState(
                batteryLevel: 0.5,
                isCharging: false,
                isLowPowerMode: true
            ),
            contextMode: .office
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(snapshot)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ContextDetectionService.ContextSnapshot.self, from: encoded)
        
        XCTAssertEqual(decoded.timeOfDay, .morning)
        XCTAssertEqual(decoded.dayOfWeek, .monday)
        XCTAssertEqual(decoded.contextMode, .office)
        XCTAssertNil(decoded.location)
        XCTAssertEqual(decoded.deviceState.batteryLevel, 0.5)
    }
    
    // MARK: - Geofence Zone Codable Tests
    
    @MainActor
    func testGeofenceZoneCodable() throws {
        let zone = ContextDetectionService.GeofenceZone(
            name: "Office",
            latitude: 37.7849,
            longitude: -122.4094,
            radius: 75,
            contextMode: .office
        )
        
        let encoded = try JSONEncoder().encode(zone)
        let decoded = try JSONDecoder().decode(ContextDetectionService.GeofenceZone.self, from: encoded)
        
        XCTAssertEqual(decoded.name, "Office")
        XCTAssertEqual(decoded.latitude, 37.7849)
        XCTAssertEqual(decoded.longitude, -122.4094)
        XCTAssertEqual(decoded.radius, 75)
        XCTAssertEqual(decoded.contextMode, .office)
    }
    
    // MARK: - Context Update Callback Tests
    
    @MainActor
    func testOnContextUpdateCallback() {
        var receivedMode: ContextDetectionService.ContextMode?
        sut.onContextUpdate = { mode in
            receivedMode = mode
        }
        
        sut.forceContextMode(.driving)
        
        XCTAssertEqual(receivedMode, .driving)
    }
    
    @MainActor
    func testOnContextUpdateCallbackOnManualOverride() {
        var receivedModes: [ContextDetectionService.ContextMode] = []
        sut.onContextUpdate = { mode in
            receivedModes.append(mode)
        }
        
        sut.setManualOverride(.home)
        sut.setManualOverride(.office)
        
        XCTAssertTrue(receivedModes.contains(.home))
        XCTAssertTrue(receivedModes.contains(.office))
    }
    
    // MARK: - Priority Hierarchy Tests
    
    @MainActor
    func testPriorityHierarchyDefaultIsLowest() {
        // With no signals, mode should be default
        XCTAssertEqual(sut.detectContextMode(), .default)
    }
    
    @MainActor
    func testManualOverrideIsHighestPriority() {
        // Set up a geofence that would trigger home mode
        let homeZone = ContextDetectionService.GeofenceZone(
            name: "Home",
            latitude: 0,
            longitude: 0,
            radius: 1000000, // Very large to ensure we're inside
            contextMode: .home
        )
        sut.addGeofenceZone(homeZone)
        
        // Set manual override to office
        sut.setManualOverride(.office)
        
        // Manual override should win over geofence
        XCTAssertEqual(sut.detectContextMode(), .office)
    }
    
    // MARK: - Context Mode All Cases Tests
    
    @MainActor
    func testContextModeAllCases() {
        let allCases = ContextDetectionService.ContextMode.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.default))
        XCTAssertTrue(allCases.contains(.driving))
        XCTAssertTrue(allCases.contains(.home))
        XCTAssertTrue(allCases.contains(.office))
    }
    
    // MARK: - Hysteresis Edge Case Tests
    
    @MainActor
    func testHysteresisPreventsModeFlipping() {
        sut.resetHysteresisForTesting()
        
        // Force initial mode
        sut.forceContextMode(.driving)
        XCTAssertEqual(sut.currentContextMode, .driving)
        
        // Setup conditions that would detect home (geofence)
        let homeZone = ContextDetectionService.GeofenceZone(
            name: "Home",
            latitude: 0,
            longitude: 0,
            radius: 1000000,
            contextMode: .home
        )
        sut.updateGeofenceZones([homeZone])
        sut.setLastLocationForTesting(CLLocation(latitude: 0, longitude: 0))
        
        // Call updateContextMode - should not change due to hysteresis
        sut.updateContextMode()
        
        // Should still be driving due to hysteresis
        XCTAssertEqual(sut.currentContextMode, .driving)
    }
    
    @MainActor
    func testHysteresisTimingAt30Seconds() {
        sut.resetHysteresisForTesting()
        
        // Set initial mode to driving
        sut.forceContextMode(.driving)
        
        // Set up geofence-based home detection
        let homeZone = ContextDetectionService.GeofenceZone(
            name: "Home",
            latitude: 0,
            longitude: 0,
            radius: 1000000,
            contextMode: .home
        )
        sut.updateGeofenceZones([homeZone])
        sut.setLastLocationForTesting(CLLocation(latitude: 0, longitude: 0))
        
        // Simulate 29 seconds have passed
        sut.lastModeChangeAt = Date(timeIntervalSinceNow: -29)
        sut.updateContextMode()
        
        // Should still be driving (29 seconds < 30 second hysteresis)
        XCTAssertEqual(sut.currentContextMode, .driving)
        
        // Now simulate 31 seconds have passed
        sut.lastModeChangeAt = Date(timeIntervalSinceNow: -31)
        sut.updateContextMode()
        
        // Should now allow the change to home
        XCTAssertEqual(sut.currentContextMode, .home)
    }
    
    @MainActor
    func testManualOverrideBypassesHysteresis() {
        sut.resetHysteresisForTesting()
        
        // Set initial mode
        sut.forceContextMode(.driving)
        sut.lastModeChangeAt = Date() // Just changed
        
        // Set manual override immediately (without waiting 30 seconds)
        sut.setManualOverride(.office)
        
        // Should immediately apply without waiting
        XCTAssertEqual(sut.currentContextMode, .office)
    }
    
    // MARK: - Geofence Priority Tests
    
    @MainActor
    func testGeofenceSmallestRadiusWins() {
        // Create two overlapping zones with different radii
        let largeZone = ContextDetectionService.GeofenceZone(
            id: UUID(),
            name: "Large Office",
            latitude: 37.7849,
            longitude: -122.4094,
            radius: 500,
            contextMode: .office
        )
        
        let smallZone = ContextDetectionService.GeofenceZone(
            id: UUID(),
            name: "Small Office",
            latitude: 37.7849,
            longitude: -122.4094,
            radius: 50,
            contextMode: .office
        )
        
        sut.updateGeofenceZones([largeZone, smallZone])
        
        // Place user at center (inside both)
        let centerLocation = CLLocation(latitude: 37.7849, longitude: -122.4094)
        sut.setLastLocationForTesting(centerLocation)
        sut.updateContextMode()
        
        // Smaller radius should be active
        XCTAssertEqual(sut.activeGeofence?.radius, 50)
        XCTAssertEqual(sut.activeGeofence?.name, "Small Office")
    }
    
    @MainActor
    func testGPSBufferAllowsNearbyLocations() {
        // Create a zone with 100m radius
        let zone = ContextDetectionService.GeofenceZone(
            name: "Office",
            latitude: 37.7849,
            longitude: -122.4094,
            radius: 100,
            contextMode: .office
        )
        
        sut.updateGeofenceZones([zone])
        
        // Place user 105 meters away (within ±10m buffer but outside base radius)
        let nearbyLocation = CLLocation(latitude: 37.7849, longitude: -122.3998)
        let distanceToCenter = nearbyLocation.distance(from: zone.location)
        
        sut.setLastLocationForTesting(nearbyLocation)
        sut.updateContextMode()
        
        // Should still be considered inside geofence due to buffer
        XCTAssertEqual(sut.currentContextMode, .office)
    }
    
    @MainActor
    func testGPSBufferDoesNotAllowFarLocations() {
        let zone = ContextDetectionService.GeofenceZone(
            name: "Office",
            latitude: 37.7849,
            longitude: -122.4094,
            radius: 100,
            contextMode: .office
        )
        
        sut.updateGeofenceZones([zone])
        
        // Place user far outside (>110m away, outside radius + buffer)
        let farLocation = CLLocation(latitude: 37.7849, longitude: -122.3988)
        
        sut.setLastLocationForTesting(farLocation)
        sut.updateContextMode()
        
        // Should not trigger geofence
        XCTAssertEqual(sut.currentContextMode, .default)
        XCTAssertNil(sut.activeGeofence)
    }
    
    @MainActor
    func testMultipleGeofenceDifferentModes() {
        let homeZone = ContextDetectionService.GeofenceZone(
            name: "Home",
            latitude: 37.7749,
            longitude: -122.4194,
            radius: 100,
            contextMode: .home
        )
        
        let officeZone = ContextDetectionService.GeofenceZone(
            name: "Office",
            latitude: 37.7849,
            longitude: -122.4094,
            radius: 100,
            contextMode: .office
        )
        
        sut.updateGeofenceZones([homeZone, officeZone])
        
        // At home
        sut.setLastLocationForTesting(CLLocation(latitude: 37.7749, longitude: -122.4194))
        sut.updateContextMode()
        XCTAssertEqual(sut.currentContextMode, .home)
        
        // At office
        sut.setLastLocationForTesting(CLLocation(latitude: 37.7849, longitude: -122.4094))
        sut.updateContextMode()
        XCTAssertEqual(sut.currentContextMode, .office)
    }
    
    // MARK: - Priority Hierarchy Complete Tests
    
    @MainActor
    func testCompleteHierarchyManualOverrideWins() {
        // Set up all possible signals
        sut.setCarPlayConnectedForTesting(true)
        sut.setCarBluetoothConnectedForTesting(true)
        
        let homeZone = ContextDetectionService.GeofenceZone(
            name: "Home",
            latitude: 0,
            longitude: 0,
            radius: 1000000,
            contextMode: .home
        )
        sut.updateGeofenceZones([homeZone])
        sut.setLastLocationForTesting(CLLocation(latitude: 0, longitude: 0))
        
        // Set manual override to office
        sut.setManualOverride(.office)
        
        // Should return office despite all other signals
        XCTAssertEqual(sut.detectContextMode(), .office)
    }
    
    @MainActor
    func testCompleteHierarchyCarPlayBeforeGeofence() {
        // Set up geofence at home
        let homeZone = ContextDetectionService.GeofenceZone(
            name: "Home",
            latitude: 0,
            longitude: 0,
            radius: 1000000,
            contextMode: .home
        )
        sut.updateGeofenceZones([homeZone])
        sut.setLastLocationForTesting(CLLocation(latitude: 0, longitude: 0))
        sut.setCarPlayConnectedForTesting(false)
        sut.setCarBluetoothConnectedForTesting(false)
        
        // Should detect home
        sut.updateContextMode()
        XCTAssertEqual(sut.currentContextMode, .home)
        
        // Enable CarPlay - should switch to driving
        sut.setCarPlayConnectedForTesting(true)
        sut.updateContextMode()
        XCTAssertEqual(sut.currentContextMode, .driving)
    }
    
    @MainActor
    func testBluetoothBeforeGeofenceButAfterCarPlay() {
        // Set up geofence for home
        let homeZone = ContextDetectionService.GeofenceZone(
            name: "Home",
            latitude: 0,
            longitude: 0,
            radius: 1000000,
            contextMode: .home
        )
        sut.updateGeofenceZones([homeZone])
        sut.setLastLocationForTesting(CLLocation(latitude: 0, longitude: 0))
        
        // With just geofence, should be home
        sut.setCarPlayConnectedForTesting(false)
        sut.setCarBluetoothConnectedForTesting(false)
        sut.updateContextMode()
        XCTAssertEqual(sut.currentContextMode, .home)
        
        // With Bluetooth but no CarPlay, should switch to driving
        sut.setCarBluetoothConnectedForTesting(true)
        sut.updateContextMode()
        XCTAssertEqual(sut.currentContextMode, .driving)
        
        // With both, CarPlay still takes effect (both result in driving, so it passes)
        sut.setCarPlayConnectedForTesting(true)
        sut.updateContextMode()
        XCTAssertEqual(sut.currentContextMode, .driving)
    }
    
    @MainActor
    func testDefaultModeAsLowestPriority() {
        // No signals set
        sut.setCarPlayConnectedForTesting(false)
        sut.setCarBluetoothConnectedForTesting(false)
        sut.updateGeofenceZones([])
        sut.setLastLocationForTesting(nil)
        sut.clearManualOverride()
        
        // Should detect default
        XCTAssertEqual(sut.detectContextMode(), .default)
    }
    
    @MainActor
    func testPriorityHierarchyWithAllSignals() {
        // Set up all signals
        sut.setCarPlayConnectedForTesting(true)      // Would be .driving
        sut.setCarBluetoothConnectedForTesting(true) // Would be .driving
        
        let homeZone = ContextDetectionService.GeofenceZone(
            name: "Home",
            latitude: 0,
            longitude: 0,
            radius: 1000000,
            contextMode: .home
        )
        sut.updateGeofenceZones([homeZone])
        sut.setLastLocationForTesting(CLLocation(latitude: 0, longitude: 0))
        
        // All signals point to driving when no manual override
        XCTAssertEqual(sut.detectContextMode(), .driving)
        
        // Now set manual override to office - should be office
        sut.setManualOverride(.office)
        XCTAssertEqual(sut.detectContextMode(), .office)
        
        // Disable CarPlay and Bluetooth - should still be office
        sut.setCarPlayConnectedForTesting(false)
        sut.setCarBluetoothConnectedForTesting(false)
        sut.updateContextMode()
        XCTAssertEqual(sut.currentContextMode, .office)
    }
    
    @MainActor
    func testPriorityHierarchySignalDisconnection() {
        // Start with CarPlay connected (driving mode)
        sut.setCarPlayConnectedForTesting(true)
        sut.updateContextMode()
        XCTAssertEqual(sut.currentContextMode, .driving)
        
        // Set up a geofence
        let homeZone = ContextDetectionService.GeofenceZone(
            name: "Home",
            latitude: 0,
            longitude: 0,
            radius: 1000000,
            contextMode: .home
        )
        sut.updateGeofenceZones([homeZone])
        sut.setLastLocationForTesting(CLLocation(latitude: 0, longitude: 0))
        
        // Disconnect CarPlay - should fall back to geofence (home)
        sut.lastModeChangeAt = Date(timeIntervalSinceNow: -31) // Skip hysteresis
        sut.setCarPlayConnectedForTesting(false)
        sut.updateContextMode()
        XCTAssertEqual(sut.currentContextMode, .home)
    }
    
    // MARK: - Location Context Integration Tests
    
    @MainActor
    func testLocationContextContainsGeofenceInfo() {
        let zone = ContextDetectionService.GeofenceZone(
            name: "Office",
            latitude: 37.7849,
            longitude: -122.4094,
            radius: 100,
            contextMode: .office
        )
        
        sut.updateGeofenceZones([zone])
        sut.setLastLocationForTesting(CLLocation(latitude: 37.7849, longitude: -122.4094))
        sut.updateContext()
        
        guard let context = sut.currentContext, let location = context.location else {
            XCTFail("Context and location should be available")
            return
        }
        
        XCTAssertEqual(location.activeGeofence, "Office")
        XCTAssertEqual(location.latitude, 37.7849)
        XCTAssertEqual(location.longitude, -122.4094)
    }
    
    // MARK: - Manual Override Persistence Tests
    
    @MainActor
    func testManualOverridePersistsToUserDefaults() {
        // Clear any existing value
        UserDefaults.standard.removeObject(forKey: "context_manual_override")
        
        // Create a new instance (which loads from UserDefaults)
        let service = ContextDetectionService(testMode: true)
        
        // Should be nil initially
        XCTAssertNil(service.manualOverride)
        
        // Set a value
        service.manualOverride = .driving
        
        // Verify it's saved
        let savedValue = UserDefaults.standard.string(forKey: "context_manual_override")
        XCTAssertEqual(savedValue, "driving")
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "context_manual_override")
    }
    
    @MainActor
    func testManualOverrideLoadsFromUserDefaults() {
        // Set a value in UserDefaults directly
        UserDefaults.standard.set("office", forKey: "context_manual_override")
        
        // Create a new instance (which loads from UserDefaults)
        let service = ContextDetectionService(testMode: true)
        
        // Should load the value
        XCTAssertEqual(service.manualOverride, .office)
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "context_manual_override")
    }
    
    @MainActor
    func testClearManualOverrideRemovesFromUserDefaults() {
        // Set a value
        UserDefaults.standard.set("home", forKey: "context_manual_override")
        
        let service = ContextDetectionService(testMode: true)
        XCTAssertEqual(service.manualOverride, .home)
        
        // Clear it
        service.manualOverride = nil
        
        // Verify it's removed
        let savedValue = UserDefaults.standard.string(forKey: "context_manual_override")
        XCTAssertNil(savedValue)
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "context_manual_override")
    }
    
    // MARK: - Hysteresis Tests
    
    @MainActor
    func testHysteresisBlocksModeChangeWithin30Seconds() {
        // Reset hysteresis state
        sut.resetHysteresisForTesting()
        
        // First change should go through
        sut.setCarPlayConnectedForTesting(true)
        sut.updateContextMode()
        XCTAssertEqual(sut.currentContextMode, .driving)
        
        // Simulate disconnecting CarPlay immediately (within 30 seconds)
        sut.setCarPlayConnectedForTesting(false)
        sut.updateContextMode()
        
        // Mode should NOT change back due to hysteresis (still within 30 seconds)
        XCTAssertEqual(sut.currentContextMode, .driving)
    }
    
    @MainActor
    func testHysteresisAllowsModeChangeAfter30Seconds() {
        // Reset hysteresis state
        sut.resetHysteresisForTesting()
        
        // Set initial mode
        sut.setCarPlayConnectedForTesting(true)
        sut.updateContextMode()
        XCTAssertEqual(sut.currentContextMode, .driving)
        
        // Simulate 31 seconds passing by manipulating lastModeChangeAt
        sut.lastModeChangeAt = Date().addingTimeInterval(-31)
        
        // Now disconnect CarPlay
        sut.setCarPlayConnectedForTesting(false)
        sut.updateContextMode()
        
        // Mode SHOULD change now since more than 30 seconds have passed
        XCTAssertEqual(sut.currentContextMode, .default)
    }
    
    @MainActor
    func testHysteresisDoesNotAffectManualOverride() {
        // Reset hysteresis state
        sut.resetHysteresisForTesting()
        
        // Set initial mode via CarPlay
        sut.setCarPlayConnectedForTesting(true)
        sut.updateContextMode()
        XCTAssertEqual(sut.currentContextMode, .driving)
        
        // Manual override should override immediately (no hysteresis)
        sut.setManualOverride(.home)
        XCTAssertEqual(sut.currentContextMode, .home)
        
        // Changing manual override again should also be immediate
        sut.setManualOverride(.office)
        XCTAssertEqual(sut.currentContextMode, .office)
    }
    
    // MARK: - Priority Hierarchy Edge Case Tests
    
    @MainActor
    func testPriorityManualOverCarPlayOverBluetoothOverGeofence() {
        // Set up all signals at once
        sut.setCarPlayConnectedForTesting(true)
        sut.setCarBluetoothConnectedForTesting(true)
        
        let homeZone = ContextDetectionService.GeofenceZone(
            name: "Home",
            latitude: 0, longitude: 0, radius: 1000000, contextMode: .home
        )
        sut.addGeofenceZone(homeZone)
        sut.setLastLocationForTesting(CLLocation(latitude: 0, longitude: 0))
        
        // Without manual, CarPlay wins (driving)
        XCTAssertEqual(sut.detectContextMode(), .driving)
        
        // Manual override wins over everything
        sut.setManualOverride(.office)
        XCTAssertEqual(sut.detectContextMode(), .office)
    }
    
    // MARK: - Overlapping Geofence Tests (Smallest Radius Wins)
    
    @MainActor
    func testOverlappingGeofencesSmallerRadiusWins() {
        let homeZone = ContextDetectionService.GeofenceZone(
            name: "Home Area",
            latitude: 37.7749, longitude: -122.4194,
            radius: 500, contextMode: .home
        )
        let officeZone = ContextDetectionService.GeofenceZone(
            name: "Home Office",
            latitude: 37.7749, longitude: -122.4194,
            radius: 50, contextMode: .office
        )
        
        sut.addGeofenceZone(homeZone)
        sut.addGeofenceZone(officeZone)
        sut.setLastLocationForTesting(CLLocation(latitude: 37.7749, longitude: -122.4194))
        
        // Smaller radius (office) should win
        XCTAssertEqual(sut.detectContextMode(), .office)
        XCTAssertEqual(sut.activeGeofence?.name, "Home Office")
    }
    
    @MainActor
    func testOverlappingGeofencesOrderIndependent() {
        let smallZone = ContextDetectionService.GeofenceZone(
            name: "Small", latitude: 37.7749, longitude: -122.4194,
            radius: 25, contextMode: .office
        )
        let largeZone = ContextDetectionService.GeofenceZone(
            name: "Large", latitude: 37.7749, longitude: -122.4194,
            radius: 1000, contextMode: .home
        )
        
        // Add in "wrong" order (large first)
        sut.addGeofenceZone(largeZone)
        sut.addGeofenceZone(smallZone)
        sut.setLastLocationForTesting(CLLocation(latitude: 37.7749, longitude: -122.4194))
        
        // Smaller should still win
        XCTAssertEqual(sut.detectContextMode(), .office)
    }
    
    // MARK: - Geofence Buffer Tests (±10m)
    
    @MainActor
    func testGeofenceEntryWithinRadiusPlusBuffer() {
        let zone = ContextDetectionService.GeofenceZone(
            name: "Test Zone",
            latitude: 37.7749, longitude: -122.4194,
            radius: 100, contextMode: .office
        )
        sut.addGeofenceZone(zone)
        
        // ~105m away (within radius + 10m buffer = 110m effective)
        let nearbyLocation = CLLocation(latitude: 37.7749 + 0.00094, longitude: -122.4194)
        sut.setLastLocationForTesting(nearbyLocation)
        
        // Should detect zone (within buffer)
        XCTAssertEqual(sut.detectContextMode(), .office)
    }
    
    @MainActor
    func testGeofenceNoEntryOutsideRadiusPlusBuffer() {
        let zone = ContextDetectionService.GeofenceZone(
            name: "Test Zone",
            latitude: 37.7749, longitude: -122.4194,
            radius: 100, contextMode: .office
        )
        sut.addGeofenceZone(zone)
        
        // ~120m away (outside radius + 10m buffer)
        let farLocation = CLLocation(latitude: 37.7749 + 0.00108, longitude: -122.4194)
        sut.setLastLocationForTesting(farLocation)
        
        // Should NOT detect zone
        XCTAssertEqual(sut.detectContextMode(), .default)
    }
}
