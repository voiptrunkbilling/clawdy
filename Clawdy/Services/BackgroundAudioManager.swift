import Foundation
import AVFoundation

/// Manages background audio state to allow TTS to continue when app enters background.
/// Tracks whether audio is actively playing to prevent premature app locking.
@MainActor
class BackgroundAudioManager: ObservableObject {
    // MARK: - Singleton

    static let shared = BackgroundAudioManager()

    // MARK: - Published State

    /// Indicates whether audio is currently playing (TTS or other)
    @Published var isAudioPlaying = false

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Call when audio playback starts
    func audioStarted() {
        isAudioPlaying = true
    }

    /// Call when audio playback ends
    func audioEnded() {
        isAudioPlaying = false
    }

    /// Check if the app should lock when entering background
    /// Returns false if audio is playing (allow background continuation)
    var shouldLockOnBackground: Bool {
        return !isAudioPlaying
    }
}
