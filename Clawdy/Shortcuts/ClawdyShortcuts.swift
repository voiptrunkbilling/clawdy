import AppIntents
import SwiftUI

// MARK: - Ask Clawdy Intent

/// Shortcut intent for sending a text query to Clawdy and getting a response.
/// Supports both Siri invocation and Shortcuts app automation.
struct AskClawdyIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Clawdy"
    static var description = IntentDescription("Send a question to Clawdy and get a response")
    
    /// The question or message to send
    @Parameter(title: "Question", description: "The question or message to ask Clawdy")
    var question: String
    
    /// Optional thinking level for the response
    @Parameter(title: "Thinking Level", default: .low)
    var thinkingLevel: ThinkingLevel
    
    static var parameterSummary: some ParameterSummary {
        Summary("Ask Clawdy \(\.$question)") {
            \.$thinkingLevel
        }
    }
    
    /// Siri phrases that trigger this intent
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        // Track usage for shortcuts donation
        ShortcutsDonationManager.shared.trackUsage(for: .askClawdy)
        
        // Get the gateway connection
        let connectionManager = GatewayDualConnectionManager.shared
        
        // Attempt to connect if not already connected
        if !connectionManager.status.hasChatCapability {
            await connectionManager.connectIfNeeded()
            
            // Wait briefly for connection to establish
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        // Check if connected after attempting connection
        guard connectionManager.status.hasChatCapability else {
            throw ShortcutError.gatewayNotConnected
        }
        
        // Send the message and wait for response
        do {
            let response = try await ShortcutsGatewayBridge.shared.sendMessageAndWaitForResponse(
                text: question,
                thinking: thinkingLevel.rawValue
            )
            
            return .result(
                value: response,
                dialog: IntentDialog(stringLiteral: response)
            )
        } catch {
            throw ShortcutError.requestFailed(error.localizedDescription)
        }
    }
}

// MARK: - Start Voice Chat Intent

/// Shortcut intent for opening the app in voice mode and starting recording.
struct StartVoiceChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Voice Chat"
    static var description = IntentDescription("Open Clawdy and start a voice conversation")
    
    /// This intent needs to open the app
    static var openAppWhenRun: Bool = true
    
    @MainActor
    func perform() async throws -> some IntentResult {
        // Track usage for shortcuts donation
        ShortcutsDonationManager.shared.trackUsage(for: .startVoiceChat)
        
        // Post notification to start voice recording when app opens
        NotificationCenter.default.post(
            name: .shortcutStartVoiceChat,
            object: nil
        )
        
        return .result()
    }
}

// MARK: - Clear Context Intent

/// Shortcut intent for clearing the conversation context.
struct ClearContextIntent: AppIntent {
    static var title: LocalizedStringResource = "Clear Clawdy Context"
    static var description = IntentDescription("Clear the conversation history with Clawdy")
    
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Track usage
        ShortcutsDonationManager.shared.trackUsage(for: .clearContext)
        
        // Post notification to clear context
        NotificationCenter.default.post(
            name: .shortcutClearContext,
            object: nil
        )
        
        return .result(dialog: "Clawdy's conversation context has been cleared.")
    }
}

// MARK: - Thinking Level Enum

/// Thinking level options for the Ask Clawdy intent
enum ThinkingLevel: String, AppEnum {
    case none = "none"
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Thinking Level"
    
    static var caseDisplayRepresentations: [ThinkingLevel: DisplayRepresentation] = [
        .none: "None (Fastest)",
        .low: "Low",
        .medium: "Medium",
        .high: "High (Most Thorough)"
    ]
}

// MARK: - Shortcut Errors

/// Errors that can occur during shortcut execution
enum ShortcutError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case gatewayNotConnected
    case requestFailed(String)
    case timeout
    case permissionDenied
    
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .gatewayNotConnected:
            return "Clawdy is not connected to the gateway. Please open the app and check your connection."
        case .requestFailed(let message):
            return "Request failed: \(message)"
        case .timeout:
            return "The request timed out. Please try again."
        case .permissionDenied:
            return "Permission denied. Please check app permissions."
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the Start Voice Chat shortcut is triggered
    static let shortcutStartVoiceChat = Notification.Name("shortcutStartVoiceChat")
    
    /// Posted when the Clear Context shortcut is triggered
    static let shortcutClearContext = Notification.Name("shortcutClearContext")
}

// MARK: - App Shortcuts Provider

/// Provides app shortcuts to the system for Siri and Shortcuts app integration.
struct ClawdyShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: AskClawdyIntent(),
                phrases: [
                    "Ask \(.applicationName) \(\.$question)",
                    "Ask \(.applicationName) about \(\.$question)",
                    "Hey \(.applicationName), \(\.$question)",
                    "Tell \(.applicationName) \(\.$question)"
                ],
                shortTitle: "Ask Clawdy",
                systemImageName: "bubble.left.and.bubble.right"
            ),
            AppShortcut(
                intent: StartVoiceChatIntent(),
                phrases: [
                    "Start voice chat with \(.applicationName)",
                    "Talk to \(.applicationName)",
                    "Open \(.applicationName) voice mode"
                ],
                shortTitle: "Voice Chat",
                systemImageName: "mic.fill"
            ),
            AppShortcut(
                intent: ClearContextIntent(),
                phrases: [
                    "Clear \(.applicationName) context",
                    "Reset \(.applicationName) conversation",
                    "Start fresh with \(.applicationName)"
                ],
                shortTitle: "Clear Context",
                systemImageName: "trash"
            )
        ]
    }
}
