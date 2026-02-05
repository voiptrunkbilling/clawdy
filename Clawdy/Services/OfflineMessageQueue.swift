import Foundation
import Combine

/// Offline message queue with persistent storage and idempotency-based sync.
///
/// Features:
/// - JSON file persistence in Documents directory
/// - Queue size limits (100 messages OR 50MB, whichever first)
/// - FIFO overflow handling (oldest messages dropped)
/// - User alerts at 80% capacity
/// - Exponential backoff retry (1s, 2s, 4s, 8s, 16s), max 3 attempts
/// - UUID idempotency tokens per message
/// - Duplicate detection handling from gateway
/// - Manual retry UI support
///
/// ## Usage
/// ```swift
/// let queue = OfflineMessageQueue.shared
///
/// // Enqueue when offline
/// queue.enqueue(content: "Hello", attachments: nil)
///
/// // Sync when online
/// await queue.syncAll(sender: myGatewayClient.send)
/// ```
@MainActor
class OfflineMessageQueue: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = OfflineMessageQueue()
    
    // MARK: - Constants
    
    /// Maximum number of messages in the queue
    private static let maxMessageCount = 100
    
    /// Maximum queue size in bytes (50MB)
    private static let maxQueueBytes = 50_000_000
    
    /// Warning threshold for message count (80%)
    private static let warningMessageCount = 80
    
    /// Warning threshold for queue size (80% = 40MB)
    private static let warningQueueBytes = 40_000_000
    
    /// Base delay for exponential backoff (1 second)
    private static let baseRetryDelay: TimeInterval = 1.0
    
    /// Maximum retry attempts before marking as failed
    private static let maxRetryAttempts = 3
    
    // MARK: - Types
    
    /// Attachment data for queued messages
    struct AttachmentData: Codable, Sendable {
        let id: UUID
        let mimeType: String
        let fileName: String
        /// Base64-encoded data
        let content: String
        
        init(id: UUID = UUID(), mimeType: String, fileName: String, data: Data) {
            self.id = id
            self.mimeType = mimeType
            self.fileName = fileName
            self.content = data.base64EncodedString()
        }
        
        /// Decode the base64 content back to Data
        func decodeData() -> Data? {
            Data(base64Encoded: content)
        }
    }
    
    /// Message status in the queue
    enum MessageStatus: String, Codable, Sendable {
        case pending      // Waiting to be sent
        case sending      // Currently being sent
        case failed       // Failed after max retries
        case duplicate    // Server reported as duplicate (silently removed)
    }
    
    /// A queued message with idempotency token and retry tracking
    struct QueuedMessage: Codable, Identifiable, Sendable {
        /// Idempotency token (UUID)
        let id: UUID
        /// Message creation timestamp
        let timestamp: Date
        /// Message content
        let content: String
        /// Optional attachments
        let attachments: [AttachmentData]?
        /// Number of retry attempts
        var retryCount: Int
        /// Timestamp of last retry attempt
        var lastRetryAt: Date?
        /// Current status
        var status: MessageStatus
        /// Error message from last failure
        var lastError: String?
        /// Optional thinking level for AI messages
        let thinking: String?
        
        init(
            id: UUID = UUID(),
            timestamp: Date = Date(),
            content: String,
            attachments: [AttachmentData]? = nil,
            thinking: String? = nil
        ) {
            self.id = id
            self.timestamp = timestamp
            self.content = content
            self.attachments = attachments
            self.retryCount = 0
            self.lastRetryAt = nil
            self.status = .pending
            self.lastError = nil
            self.thinking = thinking
        }
    }
    
    /// Response status from gateway when sending a message
    enum GatewayResponseStatus: String, Codable, Sendable {
        case success    // Message delivered successfully
        case duplicate  // Message already processed (idempotency check)
        case error      // Message failed
    }
    
    /// Response from gateway for a queued message send
    struct GatewaySendResponse: Sendable {
        let status: GatewayResponseStatus
        let runId: String?
        let errorMessage: String?
    }
    
    /// Sync result summary
    struct SyncResult: Sendable {
        let sent: Int
        let failed: Int
        let duplicatesRemoved: Int
        let remaining: Int
    }
    
    /// Capacity warning threshold reached
    enum CapacityWarning: Equatable, Sendable {
        case none
        case nearFull(messagePercent: Int, sizePercent: Int)
    }
    
    // MARK: - Published State
    
    /// Number of messages in the queue
    @Published private(set) var messageCount: Int = 0
    
    /// Total size of the queue in bytes
    @Published private(set) var queueSizeBytes: Int = 0
    
    /// Messages that have failed and need manual retry
    @Published private(set) var failedMessages: [QueuedMessage] = []
    
    /// Whether sync is currently in progress
    @Published private(set) var isSyncing: Bool = false
    
    /// Current capacity warning status
    @Published private(set) var capacityWarning: CapacityWarning = .none
    
    /// Last sync result
    @Published private(set) var lastSyncResult: SyncResult?
    
    // MARK: - Callbacks
    
    /// Called when capacity warning threshold is reached
    var onCapacityWarning: ((CapacityWarning) -> Void)?
    
    // MARK: - Private State
    
    /// The message queue
    private var queue: [QueuedMessage] = []
    
    /// File URL for persistent storage
    private var storageURL: URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Documents directory not available - this should never happen on iOS")
        }
        return docs.appendingPathComponent("offline_queue.json")
    }
    
    // MARK: - Initialization
    
    private init() {
        loadQueue()
        updatePublishedState()
    }
    
    // For testing
    init(testMode: Bool) {
        if !testMode {
            loadQueue()
            updatePublishedState()
        }
    }
    
    // MARK: - Queue Operations
    
    /// Enqueue a message for later delivery.
    /// - Parameters:
    ///   - content: Message content
    ///   - attachments: Optional attachments
    ///   - thinking: Optional thinking level
    /// - Returns: The queued message's idempotency token (UUID)
    @discardableResult
    func enqueue(content: String, attachments: [AttachmentData]? = nil, thinking: String? = nil) -> UUID {
        let message = QueuedMessage(
            content: content,
            attachments: attachments,
            thinking: thinking
        )
        
        queue.append(message)
        
        // Check and enforce limits with FIFO overflow
        enforceQueueLimits()
        
        // Check for capacity warning
        checkCapacityWarning()
        
        // Persist and update state
        saveQueue()
        updatePublishedState()
        
        print("[OfflineMessageQueue] Enqueued message \(message.id) (queue: \(queue.count) messages)")
        
        return message.id
    }
    
    /// Sync all pending messages with the gateway.
    /// - Parameter sender: Async function to send a message to the gateway
    /// - Returns: Summary of the sync operation
    func syncAll(sender: @escaping (QueuedMessage) async throws -> GatewaySendResponse) async -> SyncResult {
        guard !isSyncing else {
            return SyncResult(sent: 0, failed: 0, duplicatesRemoved: 0, remaining: queue.count)
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        var sent = 0
        var failed = 0
        var duplicatesRemoved = 0
        var newQueue: [QueuedMessage] = []
        
        for var message in queue where message.status != .failed {
            // Skip messages we just tried that haven't cooled down
            if let lastRetry = message.lastRetryAt {
                let delay = calculateBackoffDelay(for: message.retryCount)
                if Date().timeIntervalSince(lastRetry) < delay {
                    newQueue.append(message)
                    continue
                }
            }
            
            message.status = .sending
            message.lastRetryAt = Date()
            
            do {
                let response = try await sender(message)
                
                switch response.status {
                case .success:
                    sent += 1
                    print("[OfflineMessageQueue] Sent message \(message.id)")
                    // Don't add to new queue - it's sent
                    
                case .duplicate:
                    duplicatesRemoved += 1
                    print("[OfflineMessageQueue] Duplicate detected for \(message.id), removing silently")
                    // Don't add to new queue - it was already processed
                    
                case .error:
                    message.retryCount += 1
                    message.lastError = response.errorMessage
                    
                    if message.retryCount >= Self.maxRetryAttempts {
                        message.status = .failed
                        failed += 1
                        print("[OfflineMessageQueue] Message \(message.id) failed after \(message.retryCount) attempts")
                    } else {
                        message.status = .pending
                        print("[OfflineMessageQueue] Message \(message.id) will retry (attempt \(message.retryCount))")
                    }
                    newQueue.append(message)
                }
            } catch {
                message.retryCount += 1
                message.lastError = error.localizedDescription
                
                if message.retryCount >= Self.maxRetryAttempts {
                    message.status = .failed
                    failed += 1
                    print("[OfflineMessageQueue] Message \(message.id) failed after \(message.retryCount) attempts: \(error)")
                } else {
                    message.status = .pending
                    print("[OfflineMessageQueue] Message \(message.id) will retry (attempt \(message.retryCount)): \(error)")
                }
                newQueue.append(message)
            }
        }
        
        // Keep failed messages in the queue
        let failedOnes = queue.filter { $0.status == .failed }
        queue = newQueue + failedOnes.filter { msg in !newQueue.contains(where: { $0.id == msg.id }) }
        
        saveQueue()
        updatePublishedState()
        
        let result = SyncResult(
            sent: sent,
            failed: failed,
            duplicatesRemoved: duplicatesRemoved,
            remaining: queue.count
        )
        lastSyncResult = result
        
        print("[OfflineMessageQueue] Sync complete: sent=\(sent), failed=\(failed), duplicates=\(duplicatesRemoved), remaining=\(queue.count)")
        
        return result
    }
    
    /// Manually retry a specific failed message.
    /// - Parameters:
    ///   - messageId: The message ID to retry
    ///   - sender: Async function to send a message to the gateway
    /// - Returns: Whether the retry was successful
    func retryMessage(id messageId: UUID, sender: @escaping (QueuedMessage) async throws -> GatewaySendResponse) async -> Bool {
        guard let index = queue.firstIndex(where: { $0.id == messageId && $0.status == .failed }) else {
            print("[OfflineMessageQueue] Message \(messageId) not found or not in failed state")
            return false
        }
        
        var message = queue[index]
        message.status = .sending
        message.retryCount = 0  // Reset retry count for manual retry
        message.lastRetryAt = Date()
        message.lastError = nil
        queue[index] = message
        
        do {
            let response = try await sender(message)
            
            switch response.status {
            case .success:
                queue.remove(at: index)
                print("[OfflineMessageQueue] Manual retry succeeded for \(messageId)")
                saveQueue()
                updatePublishedState()
                return true
                
            case .duplicate:
                queue.remove(at: index)
                print("[OfflineMessageQueue] Manual retry found duplicate for \(messageId)")
                saveQueue()
                updatePublishedState()
                return true
                
            case .error:
                message.status = .failed
                message.lastError = response.errorMessage
                message.retryCount = 1
                queue[index] = message
                print("[OfflineMessageQueue] Manual retry failed for \(messageId): \(response.errorMessage ?? "unknown")")
                saveQueue()
                updatePublishedState()
                return false
            }
        } catch {
            message.status = .failed
            message.lastError = error.localizedDescription
            message.retryCount = 1
            if index < queue.count {
                queue[index] = message
            }
            print("[OfflineMessageQueue] Manual retry failed for \(messageId): \(error)")
            saveQueue()
            updatePublishedState()
            return false
        }
    }
    
    /// Remove a message from the queue (e.g., user cancels a failed message).
    /// - Parameter messageId: The message ID to remove
    /// - Returns: Whether the message was removed
    @discardableResult
    func removeMessage(id messageId: UUID) -> Bool {
        guard let index = queue.firstIndex(where: { $0.id == messageId }) else {
            return false
        }
        queue.remove(at: index)
        saveQueue()
        updatePublishedState()
        print("[OfflineMessageQueue] Removed message \(messageId)")
        return true
    }
    
    /// Clear all messages from the queue.
    func clearQueue() {
        queue.removeAll()
        saveQueue()
        updatePublishedState()
        print("[OfflineMessageQueue] Queue cleared")
    }
    
    /// Get all pending messages (for display).
    func getPendingMessages() -> [QueuedMessage] {
        queue.filter { $0.status == .pending || $0.status == .sending }
    }
    
    /// Get all messages in the queue.
    func getAllMessages() -> [QueuedMessage] {
        queue
    }
    
    /// Calculate current queue size in bytes.
    func calculateQueueSize() -> (count: Int, bytes: Int) {
        let data = try? JSONEncoder().encode(queue)
        return (queue.count, data?.count ?? 0)
    }
    
    // MARK: - Private Methods
    
    /// Enforce queue limits with FIFO overflow handling.
    private func enforceQueueLimits() {
        var removed = 0
        
        while true {
            let (count, bytes) = calculateQueueSize()
            
            // Check if within limits
            if count <= Self.maxMessageCount && bytes <= Self.maxQueueBytes {
                break
            }
            
            // Remove oldest (first) non-failed message
            if let oldestIndex = queue.firstIndex(where: { $0.status != .failed }) {
                let removedMessage = queue.remove(at: oldestIndex)
                removed += 1
                print("[OfflineMessageQueue] FIFO overflow: dropped message \(removedMessage.id) from \(removedMessage.timestamp)")
            } else {
                // All messages are failed, need to drop oldest failed
                if !queue.isEmpty {
                    let removedMessage = queue.removeFirst()
                    removed += 1
                    print("[OfflineMessageQueue] FIFO overflow: dropped failed message \(removedMessage.id)")
                } else {
                    break
                }
            }
        }
        
        if removed > 0 {
            print("[OfflineMessageQueue] Removed \(removed) messages due to queue limits")
        }
    }
    
    /// Check and update capacity warning status.
    private func checkCapacityWarning() {
        let (count, bytes) = calculateQueueSize()
        
        let messagePercent = (count * 100) / Self.maxMessageCount
        let sizePercent = (bytes * 100) / Self.maxQueueBytes
        
        if count >= Self.warningMessageCount || bytes >= Self.warningQueueBytes {
            let warning = CapacityWarning.nearFull(
                messagePercent: min(messagePercent, 100),
                sizePercent: min(sizePercent, 100)
            )
            
            if capacityWarning != warning {
                capacityWarning = warning
                onCapacityWarning?(warning)
                print("[OfflineMessageQueue] Capacity warning: \(messagePercent)% messages, \(sizePercent)% size")
            }
        } else {
            capacityWarning = .none
        }
    }
    
    /// Calculate exponential backoff delay for a given retry count.
    /// Returns delay in seconds: 1, 2, 4, 8, 16
    private func calculateBackoffDelay(for retryCount: Int) -> TimeInterval {
        let exponent = min(retryCount, 4)  // Cap at 16 seconds
        return Self.baseRetryDelay * pow(2.0, Double(exponent))
    }
    
    /// Update all published state properties.
    private func updatePublishedState() {
        let (count, bytes) = calculateQueueSize()
        messageCount = count
        queueSizeBytes = bytes
        failedMessages = queue.filter { $0.status == .failed }
    }
    
    // MARK: - Persistence
    
    private func loadQueue() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            print("[OfflineMessageQueue] No existing queue file")
            return
        }
        
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            queue = try decoder.decode([QueuedMessage].self, from: data)
            print("[OfflineMessageQueue] Loaded \(queue.count) messages from disk")
        } catch {
            print("[OfflineMessageQueue] Failed to load queue: \(error)")
            // Start with empty queue on error
            queue = []
        }
    }
    
    private func saveQueue() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(queue)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[OfflineMessageQueue] Failed to save queue: \(error)")
        }
    }
}

// MARK: - Helper Extensions

extension OfflineMessageQueue.QueuedMessage {
    /// Human-readable age of the message
    var ageDescription: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hr ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
    
    /// Status display text
    var statusText: String {
        switch status {
        case .pending: return "Waiting"
        case .sending: return "Sending..."
        case .failed: return "Failed"
        case .duplicate: return "Already sent"
        }
    }
}
