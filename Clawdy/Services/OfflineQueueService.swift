import Foundation

/// Service for queuing RPC requests when offline and replaying them when connection is restored.
/// Provides offline capability support for Clawdy.
@MainActor
class OfflineQueueService: ObservableObject {
    static let shared = OfflineQueueService()
    
    // MARK: - Types
    
    /// A queued RPC request
    struct QueuedRequest: Codable, Identifiable {
        let id: UUID
        let method: String
        let params: [String: AnyCodable]
        let createdAt: Date
        var retryCount: Int
        
        init(id: UUID = UUID(), method: String, params: [String: Any], createdAt: Date = Date(), retryCount: Int = 0) {
            self.id = id
            self.method = method
            self.params = params.mapValues { AnyCodable($0) }
            self.createdAt = createdAt
            self.retryCount = retryCount
        }
    }
    
    /// Result of replaying queued requests
    struct ReplayResult {
        let succeeded: Int
        let failed: Int
        let remaining: Int
    }
    
    // MARK: - Published Properties
    
    /// Number of queued requests
    @Published private(set) var queueCount: Int = 0
    
    /// Whether replay is in progress
    @Published private(set) var isReplaying: Bool = false
    
    // MARK: - Properties
    
    /// Maximum number of retries before dropping a request
    private let maxRetries = 3
    
    /// Maximum age of a queued request before dropping (24 hours)
    private let maxAge: TimeInterval = 24 * 60 * 60
    
    /// Queued requests
    private var queue: [QueuedRequest] = []
    
    /// File URL for persistent storage
    private var storageURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("offline_queue.json")
    }
    
    // MARK: - Initialization
    
    private init() {
        loadQueue()
    }
    
    // MARK: - Queue Operations
    
    /// Enqueue a request for later execution.
    /// - Parameters:
    ///   - method: RPC method name
    ///   - params: RPC parameters
    func enqueue(method: String, params: [String: Any]) {
        let request = QueuedRequest(method: method, params: params)
        queue.append(request)
        queueCount = queue.count
        saveQueue()
        print("[OfflineQueueService] Queued request: \(method) (queue size: \(queueCount))")
    }
    
    /// Replay all queued requests.
    /// - Parameter sender: Function to send RPC requests
    /// - Returns: Result of the replay operation
    func replayAll(sender: @escaping (String, [String: Any]) async throws -> Void) async -> ReplayResult {
        guard !isReplaying else {
            return ReplayResult(succeeded: 0, failed: 0, remaining: queue.count)
        }
        
        isReplaying = true
        defer { isReplaying = false }
        
        var succeeded = 0
        var failed = 0
        var remaining: [QueuedRequest] = []
        
        // Prune old requests first
        let now = Date()
        let validQueue = queue.filter { now.timeIntervalSince($0.createdAt) < maxAge }
        let pruned = queue.count - validQueue.count
        if pruned > 0 {
            print("[OfflineQueueService] Pruned \(pruned) expired requests")
        }
        
        for var request in validQueue {
            do {
                let params = request.params.mapValues { $0.value }
                try await sender(request.method, params)
                succeeded += 1
                print("[OfflineQueueService] Replayed request: \(request.method)")
            } catch {
                request.retryCount += 1
                if request.retryCount < maxRetries {
                    remaining.append(request)
                    print("[OfflineQueueService] Request failed, will retry: \(request.method) (attempt \(request.retryCount))")
                } else {
                    failed += 1
                    print("[OfflineQueueService] Request failed permanently: \(request.method)")
                }
            }
        }
        
        queue = remaining
        queueCount = queue.count
        saveQueue()
        
        let result = ReplayResult(succeeded: succeeded, failed: failed, remaining: remaining.count)
        print("[OfflineQueueService] Replay complete: \(result)")
        return result
    }
    
    /// Clear all queued requests.
    func clearQueue() {
        queue.removeAll()
        queueCount = 0
        saveQueue()
        print("[OfflineQueueService] Queue cleared")
    }
    
    // MARK: - Persistence
    
    private func loadQueue() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return
        }
        
        do {
            let data = try Data(contentsOf: storageURL)
            queue = try JSONDecoder().decode([QueuedRequest].self, from: data)
            queueCount = queue.count
            print("[OfflineQueueService] Loaded \(queueCount) queued requests")
        } catch {
            print("[OfflineQueueService] Failed to load queue: \(error)")
        }
    }
    
    private func saveQueue() {
        do {
            let data = try JSONEncoder().encode(queue)
            try data.write(to: storageURL)
        } catch {
            print("[OfflineQueueService] Failed to save queue: \(error)")
        }
    }
}

// MARK: - AnyCodable Helper

/// A type-erased Codable wrapper for storing heterogeneous values.
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Unsupported type"))
        }
    }
}
