import Foundation

/// Per-session settings that can override global voice and thinking preferences.
/// Each session can have its own speech rate, thinking level, and voice selection.
struct SessionSettings: Codable, Equatable {
    /// Speech rate multiplier (0.5 = half speed, 1.0 = normal, 2.0 = double speed)
    var speechRate: Float
    
    /// Thinking level for AI responses: "none", "low", "medium", "high"
    var thinkingLevel: String
    
    /// Voice identifier for system TTS (nil = use global default)
    var voiceIdentifier: String?
    
    /// TTS engine selection (nil = use global default)
    var ttsEngine: TTSEngine?
    
    // MARK: - Defaults
    
    /// Default session settings (use global voice settings)
    static let `default` = SessionSettings(
        speechRate: 1.0,
        thinkingLevel: "low",
        voiceIdentifier: nil,
        ttsEngine: nil
    )
    
    // MARK: - Validation
    
    /// Valid thinking level values
    static let validThinkingLevels = ["none", "low", "medium", "high"]
    
    /// Validate and normalize settings
    mutating func validate() {
        // Clamp speech rate to valid range
        speechRate = max(VoiceSettings.minRate, min(VoiceSettings.maxRate, speechRate))
        
        // Ensure thinking level is valid
        if !Self.validThinkingLevels.contains(thinkingLevel) {
            thinkingLevel = "low"
        }
    }
    
    /// Returns a validated copy of these settings
    func validated() -> SessionSettings {
        var copy = self
        copy.validate()
        return copy
    }
}

// MARK: - Convenience Initializers

extension SessionSettings {
    /// Create settings from global voice settings
    init(from voiceSettings: VoiceSettings) {
        self.speechRate = voiceSettings.speechRate
        self.thinkingLevel = "low" // Default thinking level
        self.voiceIdentifier = voiceSettings.voiceIdentifier
        self.ttsEngine = voiceSettings.ttsEngine
    }
}
