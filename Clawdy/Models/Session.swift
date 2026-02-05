import Foundation

/// Represents a chat session with its metadata, settings, and file paths.
/// Each session has a unique directory containing its metadata and messages.
struct Session: Identifiable, Codable, Equatable {
    /// Unique identifier for the session
    let id: UUID
    
    /// User-visible name of the session
    var name: String
    
    /// Session key for gateway routing (e.g., "agent:sales:main")
    let sessionKey: String
    
    /// SF Symbol name for the session icon
    var icon: String
    
    /// Hex color code for the session accent (e.g., "#0A84FF")
    var color: String
    
    /// Whether the session is pinned to the top of the list
    var isPinned: Bool
    
    /// When the session was created
    let createdAt: Date
    
    /// When the session was last used (updated on each message)
    var lastActivityAt: Date
    
    /// Cached message count (reconciled on app launch)
    var messageCount: Int
    
    /// Per-session settings (voice, thinking level, etc.)
    var settings: SessionSettings
    
    // MARK: - Computed Properties
    
    /// Base directory for all sessions: Documents/sessions/
    static var sessionsDirectoryURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("sessions", isDirectory: true)
    }
    
    /// Directory URL for this session: Documents/sessions/{id}/
    var directoryURL: URL {
        Self.sessionsDirectoryURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }
    
    /// Path to session metadata: Documents/sessions/{id}/metadata.json
    var metadataURL: URL {
        directoryURL.appendingPathComponent("metadata.json")
    }
    
    /// Path to session messages: Documents/sessions/{id}/messages.json
    var messagesURL: URL {
        directoryURL.appendingPathComponent("messages.json")
    }
    
    // MARK: - Initialization
    
    /// Create a new session with default settings
    init(
        id: UUID = UUID(),
        name: String,
        sessionKey: String,
        icon: String = "bubble.left.and.bubble.right.fill",
        color: String = "#0A84FF",
        isPinned: Bool = false,
        createdAt: Date = Date(),
        lastActivityAt: Date = Date(),
        messageCount: Int = 0,
        settings: SessionSettings = .default
    ) {
        self.id = id
        self.name = name
        self.sessionKey = sessionKey
        self.icon = icon
        self.color = color
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.messageCount = messageCount
        self.settings = settings
    }
    
    /// Create a session from a predefined agent
    init(agent: PredefinedAgent, name: String? = nil) {
        self.id = UUID()
        self.name = name ?? agent.displayName
        self.sessionKey = agent.rawValue
        self.icon = agent.defaultIcon
        self.color = agent.defaultColor
        self.isPinned = false
        self.createdAt = Date()
        self.lastActivityAt = Date()
        self.messageCount = 0
        self.settings = .default
    }
    
    // MARK: - Default Session
    
    /// Default session name for migration
    static let defaultSessionName = "Default"
    
    /// Create the default session (used for migration from old format)
    static func createDefault(id: UUID = UUID()) -> Session {
        Session(
            id: id,
            name: defaultSessionName,
            sessionKey: PredefinedAgent.main.rawValue,
            icon: PredefinedAgent.main.defaultIcon,
            color: PredefinedAgent.main.defaultColor,
            isPinned: true
        )
    }
}

// MARK: - Session Sorting

extension Session {
    /// Sort sessions by: pinned first, then by last activity (most recent first)
    static func sortedByActivity(_ sessions: [Session]) -> [Session] {
        sessions.sorted { lhs, rhs in
            // Pinned sessions come first
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            // Then sort by last activity (most recent first)
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
    }
}
