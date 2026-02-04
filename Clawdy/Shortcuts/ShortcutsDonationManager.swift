import Foundation
import AppIntents
import Intents

/// Manages shortcut donations based on user activity.
/// Donates shortcuts to Siri after a feature is used multiple times.
@MainActor
final class ShortcutsDonationManager: ObservableObject {
    static let shared = ShortcutsDonationManager()
    
    /// Minimum number of uses before donating a shortcut
    private let donationThreshold = 3
    
    /// UserDefaults keys for tracking usage
    private enum UserDefaultsKey {
        static let usagePrefix = "com.clawdy.shortcuts.usage."
        static let donatedPrefix = "com.clawdy.shortcuts.donated."
    }
    
    /// Shortcut types that can be donated
    enum ShortcutType: String, CaseIterable, Identifiable {
        case askClawdy = "askClawdy"
        case startVoiceChat = "startVoiceChat"
        case clearContext = "clearContext"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .askClawdy: return "Ask Clawdy"
            case .startVoiceChat: return "Start Voice Chat"
            case .clearContext: return "Clear Context"
            }
        }
        
        var systemImage: String {
            switch self {
            case .askClawdy: return "bubble.left.and.bubble.right"
            case .startVoiceChat: return "mic.fill"
            case .clearContext: return "trash"
            }
        }
        
        var description: String {
            switch self {
            case .askClawdy: return "Send a text message to Clawdy"
            case .startVoiceChat: return "Open app and start recording"
            case .clearContext: return "Clear conversation history"
            }
        }
    }
    
    /// Published state for UI
    @Published private(set) var donatedShortcuts: Set<ShortcutType> = []
    @Published private(set) var usageCounts: [ShortcutType: Int] = [:]
    
    private init() {
        loadState()
    }
    
    /// Track usage of a feature for potential shortcut donation
    func trackUsage(for type: ShortcutType) {
        let key = UserDefaultsKey.usagePrefix + type.rawValue
        var count = UserDefaults.standard.integer(forKey: key)
        count += 1
        UserDefaults.standard.set(count, forKey: key)
        usageCounts[type] = count
        
        print("[ShortcutsDonation] Usage tracked for \(type.rawValue): \(count) uses")
        
        // Check if we should donate
        if count >= donationThreshold && !donatedShortcuts.contains(type) {
            donateShortcut(type)
        }
    }
    
    /// Manually donate a shortcut to Siri
    func donateShortcut(_ type: ShortcutType) {
        let donatedKey = UserDefaultsKey.donatedPrefix + type.rawValue
        
        // Mark as donated
        UserDefaults.standard.set(true, forKey: donatedKey)
        donatedShortcuts.insert(type)
        
        print("[ShortcutsDonation] Donated shortcut: \(type.rawValue)")
        
        // Note: With App Intents framework (iOS 16+), shortcuts are automatically
        // available through the AppShortcutsProvider. The "donation" concept is
        // mainly for suggesting shortcuts to users in Siri Suggestions.
        // The actual donation happens through INInteraction for Siri suggestions.
        
        Task {
            await donateToSiriSuggestions(type)
        }
    }
    
    /// Donate to Siri Suggestions for proactive display
    private func donateToSiriSuggestions(_ type: ShortcutType) async {
        // Create an INInteraction for Siri Suggestions
        // This helps the system learn when to suggest this shortcut
        let intent: INIntent
        
        switch type {
        case .askClawdy:
            let sendIntent = INSendMessageIntent(
                recipients: nil,
                outgoingMessageType: .outgoingMessageText,
                content: nil,
                speakableGroupName: INSpeakableString(spokenPhrase: "Clawdy"),
                conversationIdentifier: "clawdy-main",
                serviceName: "Clawdy",
                sender: nil,
                attachments: nil
            )
            intent = sendIntent
            
        case .startVoiceChat:
            let startCallIntent = INStartCallIntent(
                callRecordFilter: nil,
                callRecordToCallBack: nil,
                audioRoute: .speakerphoneAudioRoute,
                destinationType: .normal,
                contacts: nil,
                callCapability: .audioCall
            )
            intent = startCallIntent
            
        case .clearContext:
            // No specific SiriKit intent for this - skip
            return
        }
        
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.identifier = "clawdy-\(type.rawValue)"
        
        do {
            try await interaction.donate()
            print("[ShortcutsDonation] Donated to Siri Suggestions: \(type.rawValue)")
        } catch {
            print("[ShortcutsDonation] Failed to donate to Siri: \(error)")
        }
    }
    
    /// Remove a donated shortcut
    func removeShortcut(_ type: ShortcutType) {
        let donatedKey = UserDefaultsKey.donatedPrefix + type.rawValue
        UserDefaults.standard.set(false, forKey: donatedKey)
        donatedShortcuts.remove(type)
        
        // Delete the interaction
        INInteraction.delete(with: "clawdy-\(type.rawValue)") { error in
            if let error = error {
                print("[ShortcutsDonation] Failed to delete interaction: \(error)")
            } else {
                print("[ShortcutsDonation] Removed shortcut: \(type.rawValue)")
            }
        }
    }
    
    /// Clear all donated shortcuts
    func clearAllShortcuts() {
        for type in ShortcutType.allCases {
            let donatedKey = UserDefaultsKey.donatedPrefix + type.rawValue
            UserDefaults.standard.set(false, forKey: donatedKey)
        }
        donatedShortcuts.removeAll()
        
        // Delete all interactions
        INInteraction.deleteAll { error in
            if let error = error {
                print("[ShortcutsDonation] Failed to delete all interactions: \(error)")
            } else {
                print("[ShortcutsDonation] Cleared all shortcuts")
            }
        }
    }
    
    /// Reset usage counts (for testing)
    func resetUsageCounts() {
        for type in ShortcutType.allCases {
            let key = UserDefaultsKey.usagePrefix + type.rawValue
            UserDefaults.standard.set(0, forKey: key)
        }
        usageCounts.removeAll()
        print("[ShortcutsDonation] Reset all usage counts")
    }
    
    /// Load saved state from UserDefaults
    private func loadState() {
        for type in ShortcutType.allCases {
            // Load usage count
            let usageKey = UserDefaultsKey.usagePrefix + type.rawValue
            let count = UserDefaults.standard.integer(forKey: usageKey)
            if count > 0 {
                usageCounts[type] = count
            }
            
            // Load donation status
            let donatedKey = UserDefaultsKey.donatedPrefix + type.rawValue
            if UserDefaults.standard.bool(forKey: donatedKey) {
                donatedShortcuts.insert(type)
            }
        }
    }
    
    /// Get the usage count for a shortcut type
    func usageCount(for type: ShortcutType) -> Int {
        usageCounts[type] ?? 0
    }
    
    /// Check if a shortcut has been donated
    func isDonated(_ type: ShortcutType) -> Bool {
        donatedShortcuts.contains(type)
    }
}
