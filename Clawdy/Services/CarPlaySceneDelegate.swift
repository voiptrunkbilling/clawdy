import UIKit
import CarPlay

/// CarPlay scene delegate for handling CarPlay lifecycle and voice interaction.
/// Provides hands-free voice assistant interface with minimal UI for driving safety.
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    
    // MARK: - Properties
    
    /// The CarPlay interface controller
    private var interfaceController: CPInterfaceController?
    
    /// Voice controller for managing voice states and interactions
    private var voiceController: CarPlayVoiceController?
    
    // MARK: - CPTemplateApplicationSceneDelegate
    
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        print("[CarPlay] Connected to CarPlay interface")
        
        self.interfaceController = interfaceController
        
        // Create voice controller with the interface controller
        let controller = CarPlayVoiceController(interfaceController: interfaceController)
        self.voiceController = controller
        
        // Set the root template
        controller.configureRootTemplate()
        
        // Configure audio session for CarPlay
        configureAudioSessionForCarPlay()
    }
    
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        print("[CarPlay] Disconnected from CarPlay interface")
        
        // Cleanup
        voiceController?.cleanup()
        voiceController = nil
        self.interfaceController = nil
    }
    
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        print("[CarPlay] Interface controller disconnected from window")
    }
    
    // MARK: - Audio Session
    
    private func configureAudioSessionForCarPlay() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Configure for voice chat with recording capability and ducking for Siri
            // Use playAndRecord to enable microphone input for PTT recording
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.duckOthers, .allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            
            try audioSession.setActive(true)
            
            print("[CarPlay] Audio session configured for voice chat with recording")
        } catch {
            print("[CarPlay] Failed to configure audio session: \(error)")
        }
    }
}

// MARK: - AVAudioSession Import

import AVFoundation
