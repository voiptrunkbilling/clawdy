import UIKit
import CarPlay
import Combine
import AVFoundation

/// Manages voice interaction on CarPlay using CPVoiceControlTemplate.
/// Provides hands-free voice assistant with PTT functionality.
@MainActor
class CarPlayVoiceController: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    private let interfaceController: CPInterfaceController
    private var voiceTemplate: CPVoiceControlTemplate?
    private var cancellables = Set<AnyCancellable>()
    
    /// Reference to the main view model for voice recording
    private weak var viewModel: ClawdyViewModel?
    
    // MARK: - Voice Control States
    
    private lazy var listeningState: CPVoiceControlState = {
        CPVoiceControlState(
            identifier: "listening",
            titleVariants: ["Listening..."],
            image: UIImage(systemName: "mic.fill"),
            repeats: false
        )
    }()
    
    private lazy var thinkingState: CPVoiceControlState = {
        CPVoiceControlState(
            identifier: "thinking",
            titleVariants: ["Thinking..."],
            image: UIImage(systemName: "brain"),
            repeats: false
        )
    }()
    
    private lazy var speakingState: CPVoiceControlState = {
        CPVoiceControlState(
            identifier: "speaking",
            titleVariants: ["Speaking..."],
            image: UIImage(systemName: "speaker.wave.2.fill"),
            repeats: false
        )
    }()
    
    private lazy var idleState: CPVoiceControlState = {
        CPVoiceControlState(
            identifier: "idle",
            titleVariants: ["Tap to speak"],
            image: UIImage(systemName: "mic.circle"),
            repeats: false
        )
    }()
    
    // MARK: - Initialization
    
    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        super.init()
        
        setupViewModelBinding()
    }
    
    // MARK: - Configuration
    
    func configureRootTemplate() {
        // Create voice control template with states
        let template = CPVoiceControlTemplate(voiceControlStates: [
            idleState,
            listeningState,
            thinkingState,
            speakingState
        ])
        
        self.voiceTemplate = template
        
        // Set the root template
        interfaceController.setRootTemplate(template, animated: true) { success, error in
            if let error = error {
                print("[CarPlay] Failed to set root template: \(error)")
            } else {
                print("[CarPlay] Voice control template set successfully")
            }
        }
        
        // Start in idle state
        template.activateVoiceControlState(withIdentifier: "idle")
        
        // Create a Now Playing template as backup
        setupNowPlayingTemplate()
    }
    
    private func setupNowPlayingTemplate() {
        // Now Playing template shows during audio playback
        // This provides a minimal interface during voice responses
        
        let nowPlayingTemplate = CPNowPlayingTemplate.shared
        nowPlayingTemplate.isAlbumArtistButtonEnabled = false
        nowPlayingTemplate.isUpNextButtonEnabled = false
        
        // Add a PTT button
        let pttButton = CPNowPlayingImageButton(image: UIImage(systemName: "mic.fill")!) { [weak self] _ in
            self?.handlePTTPress()
        }
        
        let stopButton = CPNowPlayingImageButton(image: UIImage(systemName: "stop.fill")!) { [weak self] _ in
            self?.handleStopPress()
        }
        
        nowPlayingTemplate.updateNowPlayingButtons([pttButton, stopButton])
    }
    
    // MARK: - View Model Binding
    
    private func setupViewModelBinding() {
        // Observe app-wide notifications for state changes from the ViewModel
        NotificationCenter.default.publisher(for: .carPlayVoiceStateChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let state = notification.userInfo?["state"] as? String {
                    self?.updateVoiceState(state)
                }
            }
            .store(in: &cancellables)
        
        // Since CarPlay scene delegate runs separately, we observe the shared ViewModel
        // through NotificationCenter and update states accordingly
        setupSharedViewModelObservers()
    }
    
    /// Set up observers to watch for recording/speaking state changes from the shared ViewModel
    private func setupSharedViewModelObservers() {
        // Listen for recording state changes
        NotificationCenter.default.publisher(for: .init("ClawdyRecordingStateChanged"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let isRecording = notification.userInfo?["isRecording"] as? Bool {
                    if isRecording {
                        self?.voiceTemplate?.activateVoiceControlState(withIdentifier: "listening")
                    }
                }
            }
            .store(in: &cancellables)
        
        // Listen for processing state changes
        NotificationCenter.default.publisher(for: .init("ClawdyProcessingStateChanged"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let isProcessing = notification.userInfo?["isProcessing"] as? Bool, isProcessing {
                    self?.voiceTemplate?.activateVoiceControlState(withIdentifier: "thinking")
                }
            }
            .store(in: &cancellables)
        
        // Listen for speaking state changes
        NotificationCenter.default.publisher(for: .init("ClawdySpeakingStateChanged"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let isSpeaking = notification.userInfo?["isSpeaking"] as? Bool {
                    if isSpeaking {
                        self?.voiceTemplate?.activateVoiceControlState(withIdentifier: "speaking")
                    } else {
                        self?.voiceTemplate?.activateVoiceControlState(withIdentifier: "idle")
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func setViewModel(_ viewModel: ClawdyViewModel) {
        self.viewModel = viewModel
        
        // Observe view model state changes
        viewModel.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                if isRecording {
                    self?.voiceTemplate?.activateVoiceControlState(withIdentifier: "listening")
                }
            }
            .store(in: &cancellables)
        
        viewModel.$processingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if state.isActive {
                    self?.voiceTemplate?.activateVoiceControlState(withIdentifier: "thinking")
                }
            }
            .store(in: &cancellables)
        
        viewModel.$isSpeaking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isSpeaking in
                if isSpeaking {
                    self?.voiceTemplate?.activateVoiceControlState(withIdentifier: "speaking")
                } else {
                    self?.voiceTemplate?.activateVoiceControlState(withIdentifier: "idle")
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Voice State Management
    
    private func updateVoiceState(_ state: String) {
        voiceTemplate?.activateVoiceControlState(withIdentifier: state)
    }
    
    // MARK: - PTT Handling
    
    private func handlePTTPress() {
        print("[CarPlay] PTT button pressed")
        
        guard let viewModel = viewModel else {
            // Try to get the shared instance
            NotificationCenter.default.post(
                name: .carPlayPTTPressed,
                object: nil
            )
            return
        }
        
        if viewModel.isRecording {
            viewModel.stopRecording()
        } else if viewModel.isSpeaking {
            viewModel.stopSpeaking()
        } else {
            viewModel.startRecording()
        }
    }
    
    private func handleStopPress() {
        print("[CarPlay] Stop button pressed")
        
        guard let viewModel = viewModel else {
            NotificationCenter.default.post(
                name: .carPlayStopPressed,
                object: nil
            )
            return
        }
        
        if viewModel.isRecording {
            viewModel.cancelRecording()
        } else if viewModel.isSpeaking {
            viewModel.stopSpeaking()
        } else if viewModel.processingState.isActive {
            viewModel.abortGeneration()
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        cancellables.removeAll()
        viewModel = nil
        voiceTemplate = nil
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let carPlayVoiceStateChanged = Notification.Name("carPlayVoiceStateChanged")
    static let carPlayPTTPressed = Notification.Name("carPlayPTTPressed")
    static let carPlayStopPressed = Notification.Name("carPlayStopPressed")
}

// MARK: - CarPlay State Helpers

extension CarPlayVoiceController {
    /// Post a voice state change notification
    static func postVoiceStateChange(_ state: CarPlayVoiceState) {
        NotificationCenter.default.post(
            name: .carPlayVoiceStateChanged,
            object: nil,
            userInfo: ["state": state.rawValue]
        )
    }
}

/// Voice states for CarPlay
enum CarPlayVoiceState: String {
    case idle
    case listening
    case thinking
    case speaking
}
