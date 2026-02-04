import Foundation
import XCTest

/// Unit tests for OfflineMessageQueue.
/// Tests queue operations, overflow handling, retry logic, and duplicate detection.
class OfflineMessageQueueTests: XCTestCase {
    
    private var queue: OfflineMessageQueue!
    
    @MainActor
    override func setUp() {
        super.setUp()
        queue = OfflineMessageQueue(testMode: true)
    }
    
    override func tearDown() {
        queue = nil
        super.tearDown()
    }
    
    // MARK: - Basic Queue Operations
    
    @MainActor
    func testEnqueueMessage() {
        let id = queue.enqueue(content: "Test message")
        
        XCTAssertEqual(queue.messageCount, 1)
        XCTAssertFalse(id.uuidString.isEmpty)
        
        let messages = queue.getAllMessages()
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.content, "Test message")
        XCTAssertEqual(messages.first?.status, .pending)
    }
    
    @MainActor
    func testEnqueueMultipleMessages() {
        _ = queue.enqueue(content: "Message 1")
        _ = queue.enqueue(content: "Message 2")
        _ = queue.enqueue(content: "Message 3")
        
        XCTAssertEqual(queue.messageCount, 3)
        
        let messages = queue.getAllMessages()
        XCTAssertEqual(messages[0].content, "Message 1")
        XCTAssertEqual(messages[1].content, "Message 2")
        XCTAssertEqual(messages[2].content, "Message 3")
    }
    
    @MainActor
    func testEnqueueWithAttachments() {
        let testData = "test image data".data(using: .utf8)!
        let attachment = OfflineMessageQueue.AttachmentData(
            mimeType: "image/jpeg",
            fileName: "test.jpg",
            data: testData
        )
        
        _ = queue.enqueue(content: "Message with image", attachments: [attachment])
        
        let messages = queue.getAllMessages()
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.attachments?.count, 1)
        XCTAssertEqual(messages.first?.attachments?.first?.mimeType, "image/jpeg")
        XCTAssertEqual(messages.first?.attachments?.first?.fileName, "test.jpg")
        XCTAssertEqual(messages.first?.attachments?.first?.decodeData(), testData)
    }
    
    @MainActor
    func testRemoveMessage() {
        let id1 = queue.enqueue(content: "Message 1")
        let id2 = queue.enqueue(content: "Message 2")
        
        XCTAssertEqual(queue.messageCount, 2)
        
        let removed = queue.removeMessage(id: id1)
        XCTAssertTrue(removed)
        XCTAssertEqual(queue.messageCount, 1)
        
        let messages = queue.getAllMessages()
        XCTAssertEqual(messages.first?.id, id2)
    }
    
    @MainActor
    func testRemoveNonExistentMessage() {
        _ = queue.enqueue(content: "Message 1")
        
        let removed = queue.removeMessage(id: UUID())
        XCTAssertFalse(removed)
        XCTAssertEqual(queue.messageCount, 1)
    }
    
    @MainActor
    func testClearQueue() {
        _ = queue.enqueue(content: "Message 1")
        _ = queue.enqueue(content: "Message 2")
        _ = queue.enqueue(content: "Message 3")
        
        XCTAssertEqual(queue.messageCount, 3)
        
        queue.clearQueue()
        
        XCTAssertEqual(queue.messageCount, 0)
        XCTAssertTrue(queue.getAllMessages().isEmpty)
    }
    
    // MARK: - Queue Size Limits
    
    @MainActor
    func testMessageCountLimit() {
        // Enqueue 105 messages (over the 100 limit)
        for i in 0..<105 {
            _ = queue.enqueue(content: "Message \(i)")
        }
        
        // Should be capped at 100
        XCTAssertLessThanOrEqual(queue.messageCount, 100)
    }
    
    @MainActor
    func testFIFOOverflow() {
        // Enqueue messages with identifiable content
        for i in 0..<102 {
            _ = queue.enqueue(content: "Message \(i)")
        }
        
        // First messages should have been dropped
        let messages = queue.getAllMessages()
        
        // Should not contain the first few messages
        let contents = messages.map { $0.content }
        XCTAssertFalse(contents.contains("Message 0"), "Oldest message should be dropped")
        XCTAssertFalse(contents.contains("Message 1"), "Second oldest should be dropped")
        
        // Should contain the newer messages
        XCTAssertTrue(contents.contains("Message 101"), "Newest message should remain")
    }
    
    // MARK: - Capacity Warning
    
    @MainActor
    func testCapacityWarningAt80Percent() {
        var warningReceived: OfflineMessageQueue.CapacityWarning?
        queue.onCapacityWarning = { warning in
            warningReceived = warning
        }
        
        // Enqueue 80 messages (at 80% threshold)
        for i in 0..<80 {
            _ = queue.enqueue(content: "Message \(i)")
        }
        
        // Warning should be triggered
        if case .nearFull(let messagePercent, _) = warningReceived {
            XCTAssertGreaterThanOrEqual(messagePercent, 80)
        } else {
            XCTFail("Expected capacity warning at 80 messages")
        }
    }
    
    @MainActor
    func testNoWarningBelow80Percent() {
        var warningReceived = false
        queue.onCapacityWarning = { _ in
            warningReceived = true
        }
        
        // Enqueue 79 messages (below threshold)
        for i in 0..<79 {
            _ = queue.enqueue(content: "Message \(i)")
        }
        
        XCTAssertFalse(warningReceived, "Should not warn below 80%")
    }
    
    // MARK: - Queue Size Calculation
    
    @MainActor
    func testCalculateQueueSize() {
        _ = queue.enqueue(content: "Test message")
        
        let (count, bytes) = queue.calculateQueueSize()
        
        XCTAssertEqual(count, 1)
        XCTAssertGreaterThan(bytes, 0)
    }
    
    @MainActor
    func testQueueSizeIncludesAttachments() {
        let smallData = "small".data(using: .utf8)!
        let attachment = OfflineMessageQueue.AttachmentData(
            mimeType: "text/plain",
            fileName: "small.txt",
            data: smallData
        )
        
        _ = queue.enqueue(content: "Message without attachment")
        let (_, bytesWithout) = queue.calculateQueueSize()
        
        _ = queue.enqueue(content: "Message with attachment", attachments: [attachment])
        let (_, bytesWith) = queue.calculateQueueSize()
        
        XCTAssertGreaterThan(bytesWith, bytesWithout, "Attachments should increase queue size")
    }
    
    // MARK: - Sync Tests
    
    @MainActor
    func testSyncAllSuccess() async {
        _ = queue.enqueue(content: "Message 1")
        _ = queue.enqueue(content: "Message 2")
        
        let result = await queue.syncAll { _ in
            return OfflineMessageQueue.GatewaySendResponse(status: .success, runId: "run1", errorMessage: nil)
        }
        
        XCTAssertEqual(result.sent, 2)
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(result.remaining, 0)
        XCTAssertEqual(queue.messageCount, 0)
    }
    
    @MainActor
    func testSyncAllWithFailures() async {
        var callCount = 0
        
        _ = queue.enqueue(content: "Message 1")
        _ = queue.enqueue(content: "Message 2")
        _ = queue.enqueue(content: "Message 3")
        
        // First call succeeds, others fail
        let result = await queue.syncAll { _ in
            callCount += 1
            if callCount == 1 {
                return OfflineMessageQueue.GatewaySendResponse(status: .success, runId: "run1", errorMessage: nil)
            }
            return OfflineMessageQueue.GatewaySendResponse(status: .error, runId: nil, errorMessage: "Network error")
        }
        
        XCTAssertEqual(result.sent, 1)
        XCTAssertGreaterThanOrEqual(result.remaining, 2, "Failed messages should remain in queue for retry")
    }
    
    // MARK: - Duplicate Detection
    
    @MainActor
    func testDuplicateDetection() async {
        let id = queue.enqueue(content: "Duplicate message")
        
        let result = await queue.syncAll { _ in
            return OfflineMessageQueue.GatewaySendResponse(status: .duplicate, runId: nil, errorMessage: nil)
        }
        
        XCTAssertEqual(result.duplicatesRemoved, 1)
        XCTAssertEqual(result.sent, 0)
        XCTAssertEqual(queue.messageCount, 0, "Duplicate should be removed silently")
        
        // Verify message was removed
        XCTAssertNil(queue.getAllMessages().first(where: { $0.id == id }))
    }
    
    // MARK: - Retry Logic
    
    @MainActor
    func testExponentialBackoff() async {
        _ = queue.enqueue(content: "Retry message")
        
        // First sync - will fail
        var result = await queue.syncAll { _ in
            return OfflineMessageQueue.GatewaySendResponse(status: .error, runId: nil, errorMessage: "Error")
        }
        
        XCTAssertEqual(result.sent, 0)
        XCTAssertEqual(result.remaining, 1, "Message should remain for retry")
        
        // Check retry count was incremented
        let messages = queue.getAllMessages()
        XCTAssertEqual(messages.first?.retryCount, 1)
    }
    
    @MainActor
    func testMaxRetryAttemptsMarksFailed() async {
        _ = queue.enqueue(content: "Fail message")
        
        // Simulate 3 failed attempts
        for _ in 0..<3 {
            _ = await queue.syncAll { _ in
                return OfflineMessageQueue.GatewaySendResponse(status: .error, runId: nil, errorMessage: "Error")
            }
            // Small delay to allow backoff cooldown
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // Message should be marked as failed
        XCTAssertEqual(queue.failedMessages.count, 1)
        XCTAssertEqual(queue.failedMessages.first?.status, .failed)
    }
    
    // MARK: - Manual Retry
    
    @MainActor
    func testManualRetrySuccess() async {
        // Create a failed message by enqueueing and failing it
        let id = queue.enqueue(content: "Manual retry message")
        
        // Fail it 3 times to mark as failed
        for _ in 0..<3 {
            _ = await queue.syncAll { _ in
                return OfflineMessageQueue.GatewaySendResponse(status: .error, runId: nil, errorMessage: "Error")
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        XCTAssertEqual(queue.failedMessages.count, 1)
        
        // Manual retry with success
        let success = await queue.retryMessage(id: id) { _ in
            return OfflineMessageQueue.GatewaySendResponse(status: .success, runId: "run1", errorMessage: nil)
        }
        
        XCTAssertTrue(success)
        XCTAssertEqual(queue.failedMessages.count, 0)
        XCTAssertEqual(queue.messageCount, 0)
    }
    
    @MainActor
    func testManualRetryNonExistent() async {
        let success = await queue.retryMessage(id: UUID()) { _ in
            return OfflineMessageQueue.GatewaySendResponse(status: .success, runId: nil, errorMessage: nil)
        }
        
        XCTAssertFalse(success, "Should return false for non-existent message")
    }
    
    // MARK: - Message Status
    
    @MainActor
    func testPendingMessagesFilter() {
        _ = queue.enqueue(content: "Pending 1")
        _ = queue.enqueue(content: "Pending 2")
        
        let pending = queue.getPendingMessages()
        
        XCTAssertEqual(pending.count, 2)
        XCTAssertTrue(pending.allSatisfy { $0.status == .pending })
    }
    
    // MARK: - Message Properties
    
    @MainActor
    func testMessageTimestamp() {
        let beforeEnqueue = Date()
        _ = queue.enqueue(content: "Timestamped message")
        let afterEnqueue = Date()
        
        let message = queue.getAllMessages().first!
        
        XCTAssertGreaterThanOrEqual(message.timestamp, beforeEnqueue)
        XCTAssertLessThanOrEqual(message.timestamp, afterEnqueue)
    }
    
    @MainActor
    func testMessageThinkingLevel() {
        _ = queue.enqueue(content: "Message with thinking", thinking: "high")
        
        let message = queue.getAllMessages().first!
        XCTAssertEqual(message.thinking, "high")
    }
    
    // MARK: - Age Description
    
    func testAgeDescriptionJustNow() {
        let message = OfflineMessageQueue.QueuedMessage(
            timestamp: Date(),
            content: "Test"
        )
        
        XCTAssertEqual(message.ageDescription, "Just now")
    }
    
    func testAgeDescriptionMinutes() {
        let message = OfflineMessageQueue.QueuedMessage(
            timestamp: Date().addingTimeInterval(-120), // 2 minutes ago
            content: "Test"
        )
        
        XCTAssertEqual(message.ageDescription, "2 min ago")
    }
    
    func testAgeDescriptionHours() {
        let message = OfflineMessageQueue.QueuedMessage(
            timestamp: Date().addingTimeInterval(-7200), // 2 hours ago
            content: "Test"
        )
        
        XCTAssertEqual(message.ageDescription, "2 hr ago")
    }
    
    func testAgeDescriptionDays() {
        let message = OfflineMessageQueue.QueuedMessage(
            timestamp: Date().addingTimeInterval(-172800), // 2 days ago
            content: "Test"
        )
        
        XCTAssertEqual(message.ageDescription, "2 days ago")
    }
    
    // MARK: - Status Text
    
    func testStatusText() {
        var message = OfflineMessageQueue.QueuedMessage(content: "Test")
        
        message.status = .pending
        XCTAssertEqual(message.statusText, "Waiting")
        
        message.status = .sending
        XCTAssertEqual(message.statusText, "Sending...")
        
        message.status = .failed
        XCTAssertEqual(message.statusText, "Failed")
        
        message.status = .duplicate
        XCTAssertEqual(message.statusText, "Already sent")
    }
    
    // MARK: - Attachment Data Tests
    
    func testAttachmentDataEncodeDecode() {
        let originalData = "Test attachment content".data(using: .utf8)!
        let attachment = OfflineMessageQueue.AttachmentData(
            mimeType: "text/plain",
            fileName: "test.txt",
            data: originalData
        )
        
        XCTAssertEqual(attachment.mimeType, "text/plain")
        XCTAssertEqual(attachment.fileName, "test.txt")
        XCTAssertEqual(attachment.decodeData(), originalData)
    }
    
    func testAttachmentDataCodable() throws {
        let originalData = "Image data here".data(using: .utf8)!
        let attachment = OfflineMessageQueue.AttachmentData(
            mimeType: "image/png",
            fileName: "image.png",
            data: originalData
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(attachment)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OfflineMessageQueue.AttachmentData.self, from: data)
        
        XCTAssertEqual(decoded.mimeType, "image/png")
        XCTAssertEqual(decoded.fileName, "image.png")
        XCTAssertEqual(decoded.decodeData(), originalData)
    }
    
    // MARK: - Persistence Round-Trip Tests
    
    func testQueuedMessageRoundTrip() throws {
        // Create a message with all fields populated
        var message = OfflineMessageQueue.QueuedMessage(
            id: UUID(),
            timestamp: Date(),
            content: "Test content",
            attachments: [
                OfflineMessageQueue.AttachmentData(
                    mimeType: "image/jpeg",
                    fileName: "test.jpg",
                    data: "test data".data(using: .utf8)!
                )
            ],
            thinking: "high"
        )
        message.retryCount = 2
        message.lastRetryAt = Date()
        message.status = .pending
        message.lastError = "Network error"
        
        // Encode with ISO8601 dates (matching save logic)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode([message])
        
        // Decode with ISO8601 dates (matching load logic)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([OfflineMessageQueue.QueuedMessage].self, from: encoded)
        
        XCTAssertEqual(decoded.count, 1)
        let result = decoded[0]
        
        XCTAssertEqual(result.id, message.id)
        XCTAssertEqual(result.content, message.content)
        XCTAssertEqual(result.thinking, message.thinking)
        XCTAssertEqual(result.retryCount, message.retryCount)
        XCTAssertEqual(result.status, message.status)
        XCTAssertEqual(result.lastError, message.lastError)
        XCTAssertEqual(result.attachments?.count, 1)
        XCTAssertEqual(result.attachments?.first?.mimeType, "image/jpeg")
        
        // Verify timestamps are preserved (within 1 second tolerance for encoding precision)
        XCTAssertEqual(result.timestamp.timeIntervalSince1970, message.timestamp.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(result.lastRetryAt?.timeIntervalSince1970 ?? 0, message.lastRetryAt?.timeIntervalSince1970 ?? 0, accuracy: 1.0)
    }
    
    func testMultipleMessagesRoundTrip() throws {
        let messages = [
            OfflineMessageQueue.QueuedMessage(content: "Message 1"),
            OfflineMessageQueue.QueuedMessage(content: "Message 2", thinking: "low"),
            OfflineMessageQueue.QueuedMessage(content: "Message 3", attachments: [
                OfflineMessageQueue.AttachmentData(mimeType: "image/png", fileName: "img.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
            ])
        ]
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(messages)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([OfflineMessageQueue.QueuedMessage].self, from: encoded)
        
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].content, "Message 1")
        XCTAssertEqual(decoded[1].content, "Message 2")
        XCTAssertEqual(decoded[1].thinking, "low")
        XCTAssertEqual(decoded[2].content, "Message 3")
        XCTAssertEqual(decoded[2].attachments?.count, 1)
    }
}
