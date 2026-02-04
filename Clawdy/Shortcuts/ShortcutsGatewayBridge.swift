import Foundation
import Combine

/// Bridge for Shortcuts to interact with the gateway without opening the app UI.
/// Handles sending messages and collecting responses for background execution.
@MainActor
final class ShortcutsGatewayBridge {
    static let shared = ShortcutsGatewayBridge()
    
    private var responseText: String = ""
    private var responseContinuation: CheckedContinuation<String, Error>?
    private var previousChatEventHandler: (@Sendable (GatewayChatEvent) -> Void)?
    
    /// Timeout for waiting for a response (60 seconds)
    private let responseTimeout: TimeInterval = 60
    
    private init() {}
    
    /// Send a message to the gateway and wait for the complete response.
    /// - Parameters:
    ///   - text: The message text to send
    ///   - thinking: Thinking level ("none", "low", "medium", "high")
    /// - Returns: The complete response text
    /// - Throws: ShortcutError if not connected or request fails
    func sendMessageAndWaitForResponse(text: String, thinking: String = "low") async throws -> String {
        // Reset state
        responseText = ""
        
        // Ensure gateway is connected
        let connectionManager = GatewayDualConnectionManager.shared
        guard connectionManager.status.hasChatCapability else {
            // Try to connect
            await connectionManager.connectIfNeeded()
            
            // Wait a bit for connection
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            guard connectionManager.status.hasChatCapability else {
                throw ShortcutError.gatewayNotConnected
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.responseContinuation = continuation
            
            // Store previous handler to restore later
            self.previousChatEventHandler = connectionManager.onChatEvent
            
            // Set up event handler for response
            connectionManager.onChatEvent = { [weak self] event in
                Task { @MainActor in
                    self?.handleGatewayEvent(event)
                }
            }
            
            // Send the message
            Task {
                do {
                    _ = try await connectionManager.sendMessage(text, attachments: nil, thinking: thinking, idempotencyKey: nil)
                } catch {
                    self.completeContinuation(with: .failure(ShortcutError.requestFailed(error.localizedDescription)))
                }
            }
            
            // Set up timeout
            Task {
                try await Task.sleep(nanoseconds: UInt64(self.responseTimeout * 1_000_000_000))
                self.completeContinuation(with: .failure(ShortcutError.timeout))
            }
        }
    }
    
    /// Handle gateway events and collect response text
    private func handleGatewayEvent(_ event: GatewayChatEvent) {
        // Also forward to previous handler if any
        if let previousHandler = previousChatEventHandler {
            previousHandler(event)
        }
        
        switch event {
        case .textDelta(let text, _):
            responseText += text
            
        case .done(_, _, let finalText, _):
            // Response complete - use final text if available, otherwise use collected deltas
            let text = finalText ?? responseText
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            completeContinuation(with: .success(trimmedText.isEmpty ? "No response received." : trimmedText))
            
        case .error(_, let message, _):
            completeContinuation(with: .failure(ShortcutError.requestFailed(message)))
            
        case .thinkingDelta, .toolCallStart, .toolCallEnd, .agentStatus:
            // Ignore these events for shortcuts
            break
        }
    }
    
    /// Complete the continuation and clean up
    private func completeContinuation(with result: Result<String, Error>) {
        // Restore previous event handler
        GatewayDualConnectionManager.shared.onChatEvent = previousChatEventHandler
        previousChatEventHandler = nil
        
        guard let continuation = responseContinuation else { return }
        responseContinuation = nil
        
        switch result {
        case .success(let text):
            continuation.resume(returning: text)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
