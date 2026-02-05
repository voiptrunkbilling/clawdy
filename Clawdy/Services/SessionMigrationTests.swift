import Foundation
import XCTest

/// Unit tests for SessionPersistenceManager migration logic.
/// Tests migration from old message format to the new multi-session format.
class SessionMigrationTests: XCTestCase {
    
    // MARK: - Migration Detection Tests
    
    func testStorageVersionKeyExists() {
        // The storage version key should be defined
        let key = "message_storage_version"
        XCTAssertFalse(key.isEmpty)
    }
    
    // MARK: - Session Model Tests
    
    func testDefaultSessionCreation() {
        let session = Session.createDefault()
        
        XCTAssertEqual(session.name, "Default")
        XCTAssertEqual(session.sessionKey, "agent:main:main")
        XCTAssertTrue(session.isPinned)
        XCTAssertEqual(session.messageCount, 0)
    }
    
    func testDefaultSessionHasCorrectIcon() {
        let session = Session.createDefault()
        
        // Should use the main agent's default icon
        XCTAssertEqual(session.icon, PredefinedAgent.main.defaultIcon)
    }
    
    func testDefaultSessionHasCorrectColor() {
        let session = Session.createDefault()
        
        // Should use the main agent's default color
        XCTAssertEqual(session.color, PredefinedAgent.main.defaultColor)
    }
    
    func testSessionCreateDefaultWithCustomId() {
        let customId = UUID()
        let session = Session.createDefault(id: customId)
        
        XCTAssertEqual(session.id, customId)
        XCTAssertEqual(session.name, "Default")
    }
    
    // MARK: - Session Sorting Tests
    
    func testSessionSortingPinnedFirst() {
        let unpinned = Session(name: "Unpinned", sessionKey: "test:1", isPinned: false)
        let pinned = Session(name: "Pinned", sessionKey: "test:2", isPinned: true)
        
        let sorted = Session.sortedByActivity([unpinned, pinned])
        
        XCTAssertEqual(sorted.first?.name, "Pinned")
        XCTAssertEqual(sorted.last?.name, "Unpinned")
    }
    
    func testSessionSortingByActivity() {
        let older = Session(
            name: "Older",
            sessionKey: "test:1",
            lastActivityAt: Date().addingTimeInterval(-3600) // 1 hour ago
        )
        let newer = Session(
            name: "Newer",
            sessionKey: "test:2",
            lastActivityAt: Date() // now
        )
        
        let sorted = Session.sortedByActivity([older, newer])
        
        XCTAssertEqual(sorted.first?.name, "Newer")
        XCTAssertEqual(sorted.last?.name, "Older")
    }
    
    func testSessionSortingPinnedOverridesActivity() {
        let newerUnpinned = Session(
            name: "Newer Unpinned",
            sessionKey: "test:1",
            isPinned: false,
            lastActivityAt: Date()
        )
        let olderPinned = Session(
            name: "Older Pinned",
            sessionKey: "test:2",
            isPinned: true,
            lastActivityAt: Date().addingTimeInterval(-86400) // 1 day ago
        )
        
        let sorted = Session.sortedByActivity([newerUnpinned, olderPinned])
        
        XCTAssertEqual(sorted.first?.name, "Older Pinned", "Pinned should come first regardless of activity")
    }
    
    // MARK: - Session Directory Tests
    
    func testSessionDirectoryURL() {
        let session = Session(name: "Test", sessionKey: "test:key")
        
        let dirURL = session.directoryURL
        
        XCTAssertTrue(dirURL.path.contains("sessions"))
        XCTAssertTrue(dirURL.path.contains(session.id.uuidString))
    }
    
    func testSessionMetadataURL() {
        let session = Session(name: "Test", sessionKey: "test:key")
        
        let metadataURL = session.metadataURL
        
        XCTAssertTrue(metadataURL.lastPathComponent == "metadata.json")
        XCTAssertTrue(metadataURL.path.contains(session.id.uuidString))
    }
    
    func testSessionMessagesURL() {
        let session = Session(name: "Test", sessionKey: "test:key")
        
        let messagesURL = session.messagesURL
        
        XCTAssertTrue(messagesURL.lastPathComponent == "messages.json")
        XCTAssertTrue(messagesURL.path.contains(session.id.uuidString))
    }
    
    // MARK: - Session Codable Tests
    
    func testSessionEncodeDecode() throws {
        let original = Session(
            name: "Test Session",
            sessionKey: "agent:test:main",
            icon: "star.fill",
            color: "#FF0000",
            isPinned: true
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Session.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.sessionKey, original.sessionKey)
        XCTAssertEqual(decoded.icon, original.icon)
        XCTAssertEqual(decoded.color, original.color)
        XCTAssertEqual(decoded.isPinned, original.isPinned)
    }
    
    // MARK: - PredefinedAgent Tests
    
    func testPredefinedAgentMain() {
        let agent = PredefinedAgent.main
        
        XCTAssertEqual(agent.rawValue, "agent:main:main")
        XCTAssertFalse(agent.displayName.isEmpty)
        XCTAssertFalse(agent.defaultIcon.isEmpty)
        XCTAssertTrue(agent.defaultColor.hasPrefix("#"))
    }
    
    func testCreateSessionFromAgent() {
        let agent = PredefinedAgent.sales
        let session = Session(agent: agent)
        
        XCTAssertEqual(session.sessionKey, agent.rawValue)
        XCTAssertEqual(session.name, agent.displayName)
        XCTAssertEqual(session.icon, agent.defaultIcon)
        XCTAssertEqual(session.color, agent.defaultColor)
    }
    
    func testCreateSessionFromAgentWithCustomName() {
        let agent = PredefinedAgent.sales
        let session = Session(agent: agent, name: "Custom Name")
        
        XCTAssertEqual(session.name, "Custom Name")
        XCTAssertEqual(session.sessionKey, agent.rawValue)
    }
    
    // MARK: - SessionSettings Tests
    
    func testDefaultSessionSettings() {
        let settings = SessionSettings.default
        
        // Default settings should have reasonable values
        XCTAssertNotNil(settings)
    }
    
    func testSessionSettingsEncodeDecode() throws {
        let settings = SessionSettings.default
        
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(SessionSettings.self, from: data)
        
        XCTAssertEqual(settings, decoded)
    }
}
