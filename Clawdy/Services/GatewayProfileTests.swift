import XCTest
@testable import Clawdy

/// Unit tests for GatewayProfile model and profile management
final class GatewayProfileTests: XCTestCase {
    
    // MARK: - GatewayProfile Model Tests
    
    func testProfileCreation() {
        let profile = GatewayProfile(
            name: "Test Profile",
            host: "test.example.com",
            port: 18789,
            useTLS: true,
            isPrimary: false
        )
        
        XCTAssertEqual(profile.name, "Test Profile")
        XCTAssertEqual(profile.host, "test.example.com")
        XCTAssertEqual(profile.port, 18789)
        XCTAssertTrue(profile.useTLS)
        XCTAssertFalse(profile.isPrimary)
        XCTAssertNotNil(profile.id)
    }
    
    func testProfileDefaultPort() {
        let profile = GatewayProfile(
            name: "Default Port Test",
            host: "localhost"
        )
        
        XCTAssertEqual(profile.port, 18789)
        XCTAssertFalse(profile.useTLS)
        XCTAssertFalse(profile.isPrimary)
    }
    
    func testProfileConnectionURL() {
        let httpProfile = GatewayProfile(
            name: "HTTP",
            host: "localhost",
            port: 8080,
            useTLS: false
        )
        XCTAssertEqual(httpProfile.connectionURL, "ws://localhost:8080")
        
        let httpsProfile = GatewayProfile(
            name: "HTTPS",
            host: "secure.example.com",
            port: 443,
            useTLS: true
        )
        XCTAssertEqual(httpsProfile.connectionURL, "wss://secure.example.com:443")
    }
    
    func testProfileShortDisplayString() {
        let profile = GatewayProfile(
            name: "Test",
            host: "gateway.local",
            port: 18789
        )
        XCTAssertEqual(profile.shortDisplayString, "gateway.local:18789")
    }
    
    func testProfileKeychainPrefix() {
        let profile = GatewayProfile(
            name: "Test",
            host: "localhost"
        )
        XCTAssertTrue(profile.keychainPrefix.hasPrefix("profile."))
        XCTAssertTrue(profile.keychainPrefix.contains(profile.id.uuidString))
    }
    
    // MARK: - Validation Tests
    
    func testProfileValidation_Valid() {
        let profile = GatewayProfile(
            name: "Valid Profile",
            host: "localhost",
            port: 18789
        )
        XCTAssertTrue(profile.isValid)
        XCTAssertNil(profile.validationError)
    }
    
    func testProfileValidation_EmptyName() {
        let profile = GatewayProfile(
            name: "",
            host: "localhost",
            port: 18789
        )
        XCTAssertFalse(profile.isValid)
        XCTAssertEqual(profile.validationError, "Profile name is required")
    }
    
    func testProfileValidation_WhitespaceName() {
        let profile = GatewayProfile(
            name: "   ",
            host: "localhost",
            port: 18789
        )
        XCTAssertFalse(profile.isValid)
        XCTAssertEqual(profile.validationError, "Profile name is required")
    }
    
    func testProfileValidation_EmptyHost() {
        let profile = GatewayProfile(
            name: "Test",
            host: "",
            port: 18789
        )
        XCTAssertFalse(profile.isValid)
        XCTAssertEqual(profile.validationError, "Host is required")
    }
    
    func testProfileValidation_InvalidPortZero() {
        let profile = GatewayProfile(
            name: "Test",
            host: "localhost",
            port: 0
        )
        XCTAssertFalse(profile.isValid)
        XCTAssertEqual(profile.validationError, "Port must be between 1 and 65535")
    }
    
    func testProfileValidation_InvalidPortNegative() {
        let profile = GatewayProfile(
            name: "Test",
            host: "localhost",
            port: -1
        )
        XCTAssertFalse(profile.isValid)
        XCTAssertEqual(profile.validationError, "Port must be between 1 and 65535")
    }
    
    func testProfileValidation_InvalidPortTooHigh() {
        let profile = GatewayProfile(
            name: "Test",
            host: "localhost",
            port: 65536
        )
        XCTAssertFalse(profile.isValid)
        XCTAssertEqual(profile.validationError, "Port must be between 1 and 65535")
    }
    
    func testProfileValidation_ValidPortBoundaries() {
        let minPortProfile = GatewayProfile(name: "Min", host: "localhost", port: 1)
        XCTAssertTrue(minPortProfile.isValid)
        
        let maxPortProfile = GatewayProfile(name: "Max", host: "localhost", port: 65535)
        XCTAssertTrue(maxPortProfile.isValid)
    }
    
    // MARK: - Codable Tests
    
    func testProfileEncodeDecode() throws {
        let original = GatewayProfile(
            name: "Codable Test",
            host: "encode.test.com",
            port: 9999,
            useTLS: true,
            isPrimary: true
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(GatewayProfile.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.host, original.host)
        XCTAssertEqual(decoded.port, original.port)
        XCTAssertEqual(decoded.useTLS, original.useTLS)
        XCTAssertEqual(decoded.isPrimary, original.isPrimary)
    }
    
    func testProfileArrayEncodeDecode() throws {
        let profiles = [
            GatewayProfile(name: "Profile 1", host: "host1.com", port: 8001),
            GatewayProfile(name: "Profile 2", host: "host2.com", port: 8002, useTLS: true),
            GatewayProfile(name: "Profile 3", host: "host3.com", port: 8003, isPrimary: true)
        ]
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(profiles)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode([GatewayProfile].self, from: data)
        
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].name, "Profile 1")
        XCTAssertEqual(decoded[1].useTLS, true)
        XCTAssertEqual(decoded[2].isPrimary, true)
    }
    
    // MARK: - Equatable Tests
    
    func testProfileEquality() {
        let id = UUID()
        let profile1 = GatewayProfile(
            id: id,
            name: "Same",
            host: "localhost",
            port: 18789
        )
        let profile2 = GatewayProfile(
            id: id,
            name: "Same",
            host: "localhost",
            port: 18789
        )
        
        XCTAssertEqual(profile1, profile2)
    }
    
    func testProfileInequalityDifferentId() {
        let profile1 = GatewayProfile(name: "Same", host: "localhost")
        let profile2 = GatewayProfile(name: "Same", host: "localhost")
        
        // Different UUIDs, so not equal
        XCTAssertNotEqual(profile1, profile2)
    }
    
    // MARK: - Default Profile Creation Tests
    
    func testDefaultProductionProfile() {
        let credentials = KeychainManager.GatewayCredentials(
            host: "prod.example.com",
            port: 18789,
            authToken: "secret-token",
            useTLS: true
        )
        
        let profile = GatewayProfile.defaultProduction(from: credentials)
        
        XCTAssertEqual(profile.name, "Production")
        XCTAssertEqual(profile.host, "prod.example.com")
        XCTAssertEqual(profile.port, 18789)
        XCTAssertTrue(profile.useTLS)
        XCTAssertTrue(profile.isPrimary)
    }
    
    func testEmptyProfile() {
        let empty = GatewayProfile.empty
        
        XCTAssertEqual(empty.name, "")
        XCTAssertEqual(empty.host, "")
        XCTAssertEqual(empty.port, 18789)
        XCTAssertFalse(empty.useTLS)
        XCTAssertFalse(empty.isPrimary)
    }
}
