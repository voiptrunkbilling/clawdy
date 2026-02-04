import Foundation
import SwiftUI
import AVFoundation
import UserNotifications

/// Coordinates the first-launch onboarding flow, presenting permission explanations
/// before triggering system prompts. Persists completion state.
@MainActor
class OnboardingCoordinator: ObservableObject {
    static let shared = OnboardingCoordinator()
    
    // MARK: - Published Properties
    
    /// Whether onboarding has been completed
    @Published private(set) var hasCompletedOnboarding: Bool = false
    
    /// Current onboarding step (nil if complete)
    @Published private(set) var currentStep: OnboardingStep?
    
    /// Whether onboarding is currently in progress
    @Published private(set) var isOnboarding: Bool = false
    
    // MARK: - Types
    
    /// Steps in the onboarding flow
    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case notificationExplanation = 1
        case microphoneExplanation = 2
        case complete = 3
        
        var title: String {
            switch self {
            case .welcome: return "Welcome to Clawdy"
            case .notificationExplanation: return "Stay Updated"
            case .microphoneExplanation: return "Voice Control"
            case .complete: return "You're All Set!"
            }
        }
        
        var description: String {
            switch self {
            case .welcome:
                return "Clawdy is your AI assistant that connects to your gateway for powerful capabilities."
            case .notificationExplanation:
                return "Notifications let Clawdy alert you about important messages and scheduled tasks, even when the app is in the background."
            case .microphoneExplanation:
                return "Microphone access enables voice commands and hands-free interaction with Clawdy."
            case .complete:
                return "You're ready to start using Clawdy. You can adjust permissions anytime in Settings."
            }
        }
        
        var systemImageName: String {
            switch self {
            case .welcome: return "sparkles"
            case .notificationExplanation: return "bell.badge.fill"
            case .microphoneExplanation: return "mic.fill"
            case .complete: return "checkmark.circle.fill"
            }
        }
        
        var buttonTitle: String {
            switch self {
            case .welcome: return "Get Started"
            case .notificationExplanation: return "Enable Notifications"
            case .microphoneExplanation: return "Enable Microphone"
            case .complete: return "Start Using Clawdy"
            }
        }
        
        var skipButtonTitle: String? {
            switch self {
            case .notificationExplanation, .microphoneExplanation:
                return "Skip for Now"
            default:
                return nil
            }
        }
    }
    
    // MARK: - Constants
    
    private static let onboardingCompletedKey = "onboarding_completed_v1"
    private static let notificationPermissionRequestedKey = "notification_permission_requested"
    private static let microphonePermissionRequestedKey = "microphone_permission_requested"
    
    // MARK: - Initialization
    
    private init() {
        loadOnboardingState()
    }
    
    /// For testing - allows injection of initial state
    init(testMode: Bool) {
        if !testMode {
            loadOnboardingState()
        }
    }
    
    // MARK: - State Management
    
    private func loadOnboardingState() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey)
    }
    
    private func saveOnboardingCompleted() {
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
        hasCompletedOnboarding = true
    }
    
    /// Check if onboarding should be shown on app launch
    var shouldShowOnboarding: Bool {
        !hasCompletedOnboarding
    }
    
    // MARK: - Onboarding Flow
    
    /// Start the onboarding flow
    func startOnboarding() {
        guard !hasCompletedOnboarding else { return }
        isOnboarding = true
        currentStep = .welcome
    }
    
    /// Advance to the next onboarding step
    func advanceToNextStep() {
        guard let current = currentStep else { return }
        
        let allSteps = OnboardingStep.allCases
        guard let currentIndex = allSteps.firstIndex(of: current),
              currentIndex + 1 < allSteps.count else {
            completeOnboarding()
            return
        }
        
        currentStep = allSteps[currentIndex + 1]
    }
    
    /// Handle the primary action for the current step
    func handlePrimaryAction() async {
        guard let step = currentStep else { return }
        
        switch step {
        case .welcome:
            advanceToNextStep()
            
        case .notificationExplanation:
            // Request notification permission
            await requestNotificationPermission()
            advanceToNextStep()
            
        case .microphoneExplanation:
            // Request microphone permission
            await requestMicrophonePermission()
            advanceToNextStep()
            
        case .complete:
            completeOnboarding()
        }
    }
    
    /// Handle skip action for permission steps
    func handleSkipAction() {
        guard let step = currentStep else { return }
        
        switch step {
        case .notificationExplanation, .microphoneExplanation:
            advanceToNextStep()
        default:
            break
        }
    }
    
    /// Complete the onboarding flow
    func completeOnboarding() {
        saveOnboardingCompleted()
        isOnboarding = false
        currentStep = nil
    }
    
    /// Reset onboarding (for testing or re-onboarding)
    func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: Self.onboardingCompletedKey)
        UserDefaults.standard.removeObject(forKey: Self.notificationPermissionRequestedKey)
        UserDefaults.standard.removeObject(forKey: Self.microphonePermissionRequestedKey)
        hasCompletedOnboarding = false
        isOnboarding = false
        currentStep = nil
    }
    
    // MARK: - Permission Requests
    
    /// Request notification permission after showing explanation
    private func requestNotificationPermission() async {
        UserDefaults.standard.set(true, forKey: Self.notificationPermissionRequestedKey)
        
        // Request authorization through NotificationManager
        let granted = await NotificationManager.shared.requestAuthorization()
        
        if granted {
            // Now register for APNs
            await APNsManager.shared.requestRegistration()
        }
        
        print("[OnboardingCoordinator] Notification permission: \(granted ? "granted" : "denied")")
    }
    
    /// Request microphone permission after showing explanation
    private func requestMicrophonePermission() async {
        UserDefaults.standard.set(true, forKey: Self.microphonePermissionRequestedKey)
        
        let status = AVAudioSession.sharedInstance().recordPermission
        
        switch status {
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            print("[OnboardingCoordinator] Microphone permission: \(granted ? "granted" : "denied")")
            
        case .granted:
            print("[OnboardingCoordinator] Microphone permission already granted")
            
        case .denied:
            print("[OnboardingCoordinator] Microphone permission previously denied")
            
        @unknown default:
            break
        }
    }
    
    // MARK: - Permission Status Checks
    
    /// Whether notification permission was requested during onboarding
    var notificationPermissionRequested: Bool {
        UserDefaults.standard.bool(forKey: Self.notificationPermissionRequestedKey)
    }
    
    /// Whether microphone permission was requested during onboarding
    var microphonePermissionRequested: Bool {
        UserDefaults.standard.bool(forKey: Self.microphonePermissionRequestedKey)
    }
}
