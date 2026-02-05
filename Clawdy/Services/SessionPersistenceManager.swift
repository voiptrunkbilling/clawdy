import Foundation

/// Manages persistent storage of sessions and their messages using file-based storage.
/// Each session has its own directory containing metadata and message history.
///
/// ## Thread Safety
/// This actor ensures all file operations are thread-safe and serialized.
///
/// ## Storage Layout
/// ```
/// Documents/
///   sessions/
///     {session-uuid}/
///       metadata.json      // Session configuration
///       messages.json      // Message history
/// ```
///
/// ## Migration
/// Migrates old `message_history.json` format to the new per-session format.
actor SessionPersistenceManager {
    
    // MARK: - Singleton
    
    /// Shared instance for app-wide session persistence
    static let shared = SessionPersistenceManager()
    
    // MARK: - Constants
    
    /// Current storage version (increment when format changes)
    private static let currentStorageVersion = 2
    
    /// UserDefaults key for storage version tracking
    private static let storageVersionKey = "message_storage_version"
    
    /// Old message history file name (for migration)
    private static let oldMessageFileName = "message_history.json"
    
    /// Retention period for messages: 7 days
    private static let retentionDays: TimeInterval = 7 * 24 * 60 * 60
    
    // MARK: - Properties
    
    /// JSON encoder configured for session serialization
    private let encoder: JSONEncoder
    
    /// JSON decoder configured for session deserialization
    private let decoder: JSONDecoder
    
    /// File manager instance
    private let fileManager: FileManager
    
    // MARK: - Initialization
    
    private init() {
        self.fileManager = FileManager.default
        
        // Configure encoder with date handling
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        // Configure decoder with date handling
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        print("[SessionPersistence] Sessions directory: \(Session.sessionsDirectoryURL.path)")
    }
    
    // MARK: - Session Loading
    
    /// Load all sessions from disk.
    /// Only loads metadata, not messages (lazy loading for performance).
    /// - Returns: Array of all sessions, sorted by activity
    func loadAllSessions() async -> [Session] {
        let sessionsDir = Session.sessionsDirectoryURL
        
        // Ensure sessions directory exists
        createDirectoryIfNeeded(at: sessionsDir)
        
        // Get all subdirectories (each is a session)
        guard let sessionDirs = try? fileManager.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("[SessionPersistence] No sessions found or failed to read directory")
            return []
        }
        
        var sessions: [Session] = []
        
        for sessionDir in sessionDirs {
            // Verify it's a directory
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: sessionDir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            
            // Try to load session metadata
            let metadataURL = sessionDir.appendingPathComponent("metadata.json")
            if let session = loadSession(from: metadataURL) {
                sessions.append(session)
            } else {
                print("[SessionPersistence] Skipping corrupted session at: \(sessionDir.lastPathComponent)")
            }
        }
        
        print("[SessionPersistence] Loaded \(sessions.count) sessions")
        return Session.sortedByActivity(sessions)
    }
    
    /// Load a single session from its metadata file
    private func loadSession(from url: URL) -> Session? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(Session.self, from: data)
        } catch {
            print("[SessionPersistence] Failed to load session from \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Session Saving
    
    /// Save session metadata to disk.
    /// Creates the session directory if it doesn't exist.
    /// - Parameter session: The session to save
    func saveSession(_ session: Session) async {
        // Ensure session directory exists
        createDirectoryIfNeeded(at: session.directoryURL)
        
        do {
            let data = try encoder.encode(session)
            try data.write(to: session.metadataURL, options: [.atomic])
            print("[SessionPersistence] Saved session: \(session.name) (\(session.id))")
        } catch {
            print("[SessionPersistence] Failed to save session \(session.id): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Message Loading/Saving
    
    /// Load messages for a specific session.
    /// - Parameter session: The session to load messages for
    /// - Returns: Array of messages, empty if file doesn't exist
    func loadMessages(for session: Session) async -> [TranscriptMessage] {
        guard fileManager.fileExists(atPath: session.messagesURL.path) else {
            print("[SessionPersistence] No messages file for session: \(session.name)")
            return []
        }
        
        do {
            let data = try Data(contentsOf: session.messagesURL)
            let messages = try decoder.decode([TranscriptMessage].self, from: data)
            print("[SessionPersistence] Loaded \(messages.count) messages for session: \(session.name)")
            return messages
        } catch {
            print("[SessionPersistence] Failed to load messages for session \(session.id): \(error.localizedDescription)")
            return []
        }
    }
    
    /// Save messages for a specific session.
    /// - Parameters:
    ///   - messages: Array of messages to save
    ///   - session: The session to save messages for
    func saveMessages(_ messages: [TranscriptMessage], for session: Session) async {
        // Ensure session directory exists
        createDirectoryIfNeeded(at: session.directoryURL)
        
        do {
            let data = try encoder.encode(messages)
            try data.write(to: session.messagesURL, options: [.atomic])
            print("[SessionPersistence] Saved \(messages.count) messages for session: \(session.name)")
        } catch {
            print("[SessionPersistence] Failed to save messages for session \(session.id): \(error.localizedDescription)")
        }
    }
    
    /// Append a single message to a session's message history.
    /// - Parameters:
    ///   - message: The message to append
    ///   - session: The session to append to
    func appendMessage(_ message: TranscriptMessage, to session: Session) async {
        var messages = await loadMessages(for: session)
        messages.append(message)
        await saveMessages(messages, for: session)
    }
    
    /// Update an existing message in a session's history.
    /// - Parameters:
    ///   - message: The updated message (matched by ID)
    ///   - session: The session containing the message
    func updateMessage(_ message: TranscriptMessage, in session: Session) async {
        var messages = await loadMessages(for: session)
        
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
            await saveMessages(messages, for: session)
            print("[SessionPersistence] Updated message: \(message.id)")
        } else {
            // Message not found, append as new
            messages.append(message)
            await saveMessages(messages, for: session)
            print("[SessionPersistence] Message not found for update, saved as new: \(message.id)")
        }
    }
    
    // MARK: - Session Deletion
    
    /// Delete a session and all its data from disk.
    /// - Parameter session: The session to delete
    func deleteSession(_ session: Session) async {
        do {
            if fileManager.fileExists(atPath: session.directoryURL.path) {
                try fileManager.removeItem(at: session.directoryURL)
                print("[SessionPersistence] Deleted session: \(session.name) (\(session.id))")
            }
        } catch {
            print("[SessionPersistence] Failed to delete session \(session.id): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Migration
    
    /// Check if migration from old format is needed and perform it.
    /// - Returns: The migrated default session, or nil if no migration needed
    func migrateIfNeeded() async -> Session? {
        let currentVersion = UserDefaults.standard.integer(forKey: Self.storageVersionKey)
        
        if currentVersion >= Self.currentStorageVersion {
            print("[SessionPersistence] Storage already at version \(currentVersion), no migration needed")
            return nil
        }
        
        print("[SessionPersistence] Storage version \(currentVersion) < \(Self.currentStorageVersion), checking for migration")
        
        // Check if old message file exists
        let oldMessageURL = documentsDirectory.appendingPathComponent(Self.oldMessageFileName)
        
        if fileManager.fileExists(atPath: oldMessageURL.path) {
            // Migrate old messages to Default session
            let defaultSession = await migrateOldFormat(from: oldMessageURL)
            
            // Update storage version
            UserDefaults.standard.set(Self.currentStorageVersion, forKey: Self.storageVersionKey)
            
            return defaultSession
        } else {
            // No old file, just create empty Default session
            print("[SessionPersistence] No old message file found, creating empty Default session")
            
            let defaultSession = Session.createDefault()
            await saveSession(defaultSession)
            
            // Update storage version
            UserDefaults.standard.set(Self.currentStorageVersion, forKey: Self.storageVersionKey)
            
            return defaultSession
        }
    }
    
    /// Migrate messages from old format to new Default session.
    /// - Parameter oldURL: URL of the old message_history.json file
    /// - Returns: The newly created Default session
    private func migrateOldFormat(from oldURL: URL) async -> Session {
        print("[SessionPersistence] Migrating old message format from: \(oldURL.path)")
        
        // Create default session
        let defaultSession = Session.createDefault()
        
        // Try to load old messages
        do {
            let data = try Data(contentsOf: oldURL)
            let oldMessages = try decoder.decode([TranscriptMessage].self, from: data)
            
            print("[SessionPersistence] Found \(oldMessages.count) messages to migrate")
            
            // Update messages with session ID
            let migratedMessages = oldMessages.map { message -> TranscriptMessage in
                var updated = message
                updated.sessionId = defaultSession.id
                return updated
            }
            
            // Save to new location
            await saveSession(defaultSession)
            await saveMessages(migratedMessages, for: defaultSession)
            
            // Update session message count
            var updatedSession = defaultSession
            updatedSession.messageCount = migratedMessages.count
            if let lastMessage = migratedMessages.last {
                updatedSession.lastActivityAt = lastMessage.timestamp
            }
            await saveSession(updatedSession)
            
            print("[SessionPersistence] Migration complete: \(migratedMessages.count) messages moved to Default session")
            
            // Keep old file as backup (don't delete)
            print("[SessionPersistence] Old message file preserved as backup")
            
            return updatedSession
        } catch {
            print("[SessionPersistence] Failed to migrate old messages: \(error.localizedDescription)")
            print("[SessionPersistence] Creating empty Default session instead")
            
            // Save empty default session
            await saveSession(defaultSession)
            
            return defaultSession
        }
    }
    
    // MARK: - Message Count Reconciliation
    
    /// Reconcile message counts for all sessions.
    /// Compares cached count with actual message count and fixes discrepancies.
    /// Should be called on app launch for self-healing.
    /// - Parameter sessions: Sessions to reconcile
    /// - Returns: Updated sessions with corrected counts
    func reconcileMessageCounts(for sessions: [Session]) async -> [Session] {
        var updatedSessions: [Session] = []
        
        for session in sessions {
            let messages = await loadMessages(for: session)
            let actualCount = messages.count
            
            if session.messageCount != actualCount {
                print("[SessionPersistence] Reconciling count for '\(session.name)': \(session.messageCount) -> \(actualCount)")
                
                var updatedSession = session
                updatedSession.messageCount = actualCount
                await saveSession(updatedSession)
                updatedSessions.append(updatedSession)
            } else {
                updatedSessions.append(session)
            }
        }
        
        return updatedSessions
    }
    
    // MARK: - Message Pruning
    
    /// Remove messages older than the retention period for a session.
    /// - Parameter session: The session to prune
    /// - Returns: Number of messages pruned
    @discardableResult
    func pruneOldMessages(for session: Session) async -> Int {
        let messages = await loadMessages(for: session)
        let cutoffDate = Date().addingTimeInterval(-Self.retentionDays)
        
        let filteredMessages = messages.filter { $0.timestamp > cutoffDate }
        let prunedCount = messages.count - filteredMessages.count
        
        if prunedCount > 0 {
            await saveMessages(filteredMessages, for: session)
            
            // Update session message count
            var updatedSession = session
            updatedSession.messageCount = filteredMessages.count
            await saveSession(updatedSession)
            
            print("[SessionPersistence] Pruned \(prunedCount) old messages from session: \(session.name)")
        }
        
        return prunedCount
    }
    
    /// Prune old messages from all sessions.
    /// - Parameter sessions: Sessions to prune
    /// - Returns: Total number of messages pruned
    @discardableResult
    func pruneOldMessagesFromAllSessions(_ sessions: [Session]) async -> Int {
        var totalPruned = 0
        
        for session in sessions {
            totalPruned += await pruneOldMessages(for: session)
        }
        
        if totalPruned > 0 {
            print("[SessionPersistence] Total pruned: \(totalPruned) messages across \(sessions.count) sessions")
        }
        
        return totalPruned
    }
    
    // MARK: - Helpers
    
    /// Documents directory URL (guaranteed to exist on iOS)
    private var documentsDirectory: URL {
        guard let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Documents directory not available - this should never happen on iOS")
        }
        return dir
    }
    
    /// Create a directory if it doesn't exist
    private func createDirectoryIfNeeded(at url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                print("[SessionPersistence] Created directory: \(url.lastPathComponent)")
            } catch {
                print("[SessionPersistence] Failed to create directory \(url.path): \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Disk Space Check
    
    /// Check if there's enough disk space for session operations.
    /// - Returns: True if at least 10MB is available
    func hasAvailableDiskSpace() -> Bool {
        do {
            let attrs = try fileManager.attributesOfFileSystem(forPath: documentsDirectory.path)
            if let freeSpace = attrs[.systemFreeSize] as? Int64 {
                let minRequired: Int64 = 10 * 1024 * 1024 // 10 MB
                return freeSpace > minRequired
            }
        } catch {
            print("[SessionPersistence] Failed to check disk space: \(error.localizedDescription)")
        }
        return true // Assume space is available if check fails
    }
}
