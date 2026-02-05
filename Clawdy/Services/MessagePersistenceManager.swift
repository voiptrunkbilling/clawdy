import Foundation

/// Manages persistent storage of chat messages using JSON file-based storage.
/// Messages are stored in the Documents directory and retained for one week.
///
/// ## Thread Safety
/// This actor ensures all file operations are thread-safe and serialized.
///
/// ## Storage Format
/// Messages are stored as a JSON array in `Documents/message_history.json`.
/// Each message includes: id, text, isUser, timestamp, isStreaming, wasInterrupted, toolCalls.
///
/// ## Retention Policy
/// Messages older than 7 days are automatically pruned on app launch.
actor MessagePersistenceManager {
    
    // MARK: - Singleton
    
    /// Shared instance for app-wide message persistence
    static let shared = MessagePersistenceManager()
    
    // MARK: - Constants
    
    /// Storage file name
    private static let fileName = "message_history.json"
    
    /// Retention period: 7 days
    private static let retentionDays: TimeInterval = 7 * 24 * 60 * 60
    
    // MARK: - Properties
    
    /// Full path to the storage file
    private let storageURL: URL
    
    /// JSON encoder configured for message serialization
    private let encoder: JSONEncoder
    
    /// JSON decoder configured for message deserialization
    private let decoder: JSONDecoder
    
    // MARK: - Initialization
    
    private init() {
        // Get Documents directory (guaranteed to exist on iOS)
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Documents directory not available - this should never happen on iOS")
        }
        storageURL = documentsPath.appendingPathComponent(Self.fileName)
        
        // Configure encoder/decoder with date handling
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        print("[MessagePersistence] Storage path: \(storageURL.path)")
    }
    
    // MARK: - Public API
    
    /// Save a single message to persistent storage.
    /// Appends the message to the existing message array.
    /// - Parameter message: The message to save
    func saveMessage(_ message: TranscriptMessage) async {
        var messages = await loadMessages()
        messages.append(message)
        await saveAllMessages(messages)
        print("[MessagePersistence] Saved message: \(message.id)")
    }
    
    /// Save multiple messages at once (more efficient for batch operations).
    /// - Parameter messages: Array of messages to save
    func saveMessages(_ messages: [TranscriptMessage]) async {
        var existingMessages = await loadMessages()
        existingMessages.append(contentsOf: messages)
        await saveAllMessages(existingMessages)
        print("[MessagePersistence] Saved \(messages.count) messages")
    }
    
    /// Load all persisted messages from storage.
    /// - Returns: Array of messages, empty if file doesn't exist or is invalid
    func loadMessages() async -> [TranscriptMessage] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            print("[MessagePersistence] No message file found")
            return []
        }
        
        do {
            let data = try Data(contentsOf: storageURL)
            let messages = try decoder.decode([TranscriptMessage].self, from: data)
            print("[MessagePersistence] Loaded \(messages.count) messages")
            return messages
        } catch {
            print("[MessagePersistence] Failed to load messages: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Clear all persisted messages (delete the storage file).
    func clearAllMessages() async {
        do {
            if FileManager.default.fileExists(atPath: storageURL.path) {
                try FileManager.default.removeItem(at: storageURL)
                print("[MessagePersistence] Cleared all messages")
            }
        } catch {
            print("[MessagePersistence] Failed to clear messages: \(error.localizedDescription)")
        }
    }
    
    /// Remove messages older than the retention period (7 days).
    /// Should be called on app launch.
    /// - Returns: Number of messages pruned
    @discardableResult
    func pruneOldMessages() async -> Int {
        let messages = await loadMessages()
        let cutoffDate = Date().addingTimeInterval(-Self.retentionDays)
        
        let filteredMessages = messages.filter { $0.timestamp > cutoffDate }
        let prunedCount = messages.count - filteredMessages.count
        
        if prunedCount > 0 {
            await saveAllMessages(filteredMessages)
            print("[MessagePersistence] Pruned \(prunedCount) old messages")
        } else {
            print("[MessagePersistence] No messages to prune")
        }
        
        return prunedCount
    }
    
    /// Update an existing message (e.g., when streaming completes).
    /// Finds message by ID and replaces it.
    /// - Parameter message: The updated message
    func updateMessage(_ message: TranscriptMessage) async {
        var messages = await loadMessages()
        
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
            await saveAllMessages(messages)
            print("[MessagePersistence] Updated message: \(message.id)")
        } else {
            // Message not found, append as new
            messages.append(message)
            await saveAllMessages(messages)
            print("[MessagePersistence] Message not found for update, saved as new: \(message.id)")
        }
    }
    
    /// Get the count of persisted messages.
    /// - Returns: Number of messages in storage
    func messageCount() async -> Int {
        let messages = await loadMessages()
        return messages.count
    }
    
    /// Check if there are any persisted messages.
    /// - Returns: True if storage file exists and contains messages
    func hasMessages() async -> Bool {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return false
        }
        let messages = await loadMessages()
        return !messages.isEmpty
    }
    
    // MARK: - Private Helpers
    
    /// Save all messages to the storage file (replaces existing content).
    /// - Parameter messages: Complete array of messages to save
    private func saveAllMessages(_ messages: [TranscriptMessage]) async {
        do {
            let data = try encoder.encode(messages)
            try data.write(to: storageURL, options: [.atomic])
            print("[MessagePersistence] Wrote \(messages.count) messages to disk")
        } catch {
            print("[MessagePersistence] Failed to save messages: \(error.localizedDescription)")
        }
    }
}
