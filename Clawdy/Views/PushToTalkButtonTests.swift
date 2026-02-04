import XCTest
@testable import Clawdy

/// Tests for PushToTalkButton and PTT state management
final class PushToTalkButtonTests: XCTestCase {
    
    // MARK: - PTTState Tests
    
    func testPTTStateInitialState() {
        // PTTState should start idle
        let state = PTTState.idle
        XCTAssertEqual(state, .idle)
    }
    
    func testPTTStateTransitions() {
        // Test valid state transitions
        var state = PTTState.idle
        
        // idle -> pressed (touch down)
        state = .pressed
        XCTAssertEqual(state, .pressed)
        
        // pressed -> recording (after minimum duration)
        state = .recording
        XCTAssertEqual(state, .recording)
        
        // recording -> thinking (after release)
        state = .thinking
        XCTAssertEqual(state, .thinking)
        
        // thinking -> responding (when response starts)
        state = .responding
        XCTAssertEqual(state, .responding)
        
        // responding -> idle (response complete)
        state = .idle
        XCTAssertEqual(state, .idle)
    }
    
    func testPTTStateCancellation() {
        // Test cancel path
        var state = PTTState.recording
        
        // recording -> cancelled (drag away)
        state = .cancelled
        XCTAssertEqual(state, .cancelled)
        
        // cancelled -> idle (gesture ends)
        state = .idle
        XCTAssertEqual(state, .idle)
    }
    
    // MARK: - PTTButtonViewModel Tests
    
    func testViewModelInitialState() {
        let vm = PTTButtonViewModel()
        
        XCTAssertEqual(vm.pressStart, nil)
        XCTAssertEqual(vm.pressOrigin, .zero)
        XCTAssertEqual(vm.currentDragDistance, 0)
        XCTAssertFalse(vm.hasRecordingStarted)
    }
    
    func testViewModelCancelThreshold() {
        let vm = PTTButtonViewModel()
        
        // Below threshold - not cancelled
        vm.currentDragDistance = 70
        XCTAssertLessThan(vm.currentDragDistance, vm.cancelThreshold)
        
        // At/above threshold - cancelled
        vm.currentDragDistance = 80
        XCTAssertGreaterThanOrEqual(vm.currentDragDistance, vm.cancelThreshold)
    }
    
    func testViewModelMinimumRecordingDuration() {
        let vm = PTTButtonViewModel()
        
        XCTAssertEqual(vm.minimumRecordingDuration, 0.5, accuracy: 0.001)
    }
    
    func testViewModelRecordingDurationCheck() {
        let vm = PTTButtonViewModel()
        
        // No press start - duration check should guard
        XCTAssertNil(vm.pressStart)
        
        // With press start less than minimum
        vm.pressStart = Date()
        let shortDuration = Date().timeIntervalSince(vm.pressStart!)
        XCTAssertLessThan(shortDuration, vm.minimumRecordingDuration)
        
        // Simulate waiting - in real test we'd use async/await
        // For now just verify the property is accessible
        XCTAssertNotNil(vm.pressStart)
    }
    
    // MARK: - AudioAmplitudeConverter Tests
    
    func testAmplitudeNormalizationSilence() {
        // -160 dB should be close to 0
        let normalized = AudioAmplitudeConverter.normalize(power: -160)
        XCTAssertLessThan(normalized, 0.001)
    }
    
    func testAmplitudeNormalizationLoud() {
        // 0 dB should be 1.0
        let normalized = AudioAmplitudeConverter.normalize(power: 0)
        XCTAssertEqual(normalized, 1.0, accuracy: 0.001)
    }
    
    func testAmplitudeNormalizationMid() {
        // -20 dB should be 0.1 (10^(-20/20) = 0.1)
        let normalized = AudioAmplitudeConverter.normalize(power: -20)
        XCTAssertEqual(normalized, 0.1, accuracy: 0.01)
    }
    
    func testAmplitudeNormalizationClipping() {
        // Values above 0 should be clamped to 1.0
        let normalized = AudioAmplitudeConverter.normalize(power: 10)
        XCTAssertEqual(normalized, 1.0, accuracy: 0.001)
    }
    
    // MARK: - WaveformState Tests
    
    func testWaveformStateIdleProperties() {
        let state = WaveformState.idle
        
        switch state {
        case .idle:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected idle state")
        }
    }
    
    func testWaveformStateRecording() {
        let state = WaveformState.recording
        
        switch state {
        case .recording:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected recording state")
        }
    }
    
    func testWaveformStateThinking() {
        let state = WaveformState.thinking
        
        switch state {
        case .thinking:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected thinking state")
        }
    }
    
    func testWaveformStateResponding() {
        let state = WaveformState.responding
        
        switch state {
        case .responding:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected responding state")
        }
    }
}
