import SwiftUI
import UIKit

/// Push-to-talk button state
enum PTTState {
    case idle
    case pressed
    case recording
    case cancelled
    case thinking
    case responding
}

/// View model for PTT button state management (exposed for testing)
class PTTButtonViewModel: ObservableObject {
    /// Time when press started (nil when not pressed)
    @Published var pressStart: Date?
    
    /// Initial press location
    @Published var pressOrigin: CGPoint = .zero
    
    /// Current drag distance from origin
    @Published var currentDragDistance: CGFloat = 0
    
    /// Whether recording has actually started
    @Published var hasRecordingStarted: Bool = false
    
    /// Minimum recording duration (seconds)
    let minimumRecordingDuration: TimeInterval = 0.5
    
    /// Distance to drag to cancel (points)
    let cancelThreshold: CGFloat = 80
    
    /// Reset all state
    func reset() {
        pressStart = nil
        pressOrigin = .zero
        currentDragDistance = 0
        hasRecordingStarted = false
    }
}

/// Push-to-talk button with hold-to-record, release-to-send, and cancel gestures.
/// Provides haptic feedback and integrates with VoiceWaveformView for visual feedback.
struct PushToTalkButton: View {
    /// Current audio amplitude for waveform (0.0 - 1.0)
    let amplitude: CGFloat
    
    /// Current PTT state
    @Binding var state: PTTState
    
    /// Callback when recording should start
    let onRecordingStart: () -> Void
    
    /// Callback when recording should stop and send
    let onRecordingEnd: () -> Void
    
    /// Callback when recording is cancelled
    let onRecordingCancel: () -> Void
    
    /// Callback to stop/interrupt current response
    let onStopResponse: () -> Void
    
    /// Internal state tracking
    @State private var pressStartTime: Date?
    @State private var initialPressLocation: CGPoint = .zero
    @State private var currentDragOffset: CGSize = .zero
    @State private var showCancelHint: Bool = false
    
    /// Minimum recording duration (seconds)
    private let minimumRecordingDuration: TimeInterval = 0.5
    
    /// Distance to drag to cancel (points)
    private let cancelThreshold: CGFloat = 80
    
    /// Button size
    private let buttonSize: CGFloat = 72
    
    /// Haptic feedback generators
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    var body: some View {
        ZStack {
            // Cancel hint (appears when dragging)
            if showCancelHint {
                Text("Release to cancel")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .offset(y: -60)
                    .transition(.opacity)
            }
            
            // Main button content
            buttonContent
                .offset(currentDragOffset)
                .gesture(pttGesture)
        }
        .animation(.easeOut(duration: 0.15), value: showCancelHint)
        .animation(.spring(response: 0.3), value: currentDragOffset)
    }
    
    // MARK: - Button Content
    
    @ViewBuilder
    private var buttonContent: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(buttonBackgroundColor)
                .frame(width: buttonSize, height: buttonSize)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                .scaleEffect(state == .pressed || state == .recording ? 1.1 : 1.0)
            
            // Button content based on state
            Group {
                switch state {
                case .idle:
                    idleContent
                case .pressed, .recording:
                    recordingContent
                case .cancelled:
                    cancelledContent
                case .thinking:
                    thinkingContent
                case .responding:
                    respondingContent
                }
            }
        }
    }
    
    private var idleContent: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 28))
            .foregroundColor(.white)
    }
    
    private var recordingContent: some View {
        VStack(spacing: 4) {
            VoiceWaveformView(
                amplitude: amplitude,
                state: .recording,
                barCount: 5,
                barWidth: 3,
                maxBarHeight: 24,
                minBarHeight: 4
            )
        }
    }
    
    private var cancelledContent: some View {
        Image(systemName: "xmark")
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(.white)
    }
    
    private var thinkingContent: some View {
        VoiceWaveformView(
            amplitude: 0,
            state: .thinking,
            barCount: 3,
            barWidth: 4,
            maxBarHeight: 20,
            minBarHeight: 4
        )
    }
    
    private var respondingContent: some View {
        // Stop button during response
        Button(action: onStopResponse) {
            Image(systemName: "stop.fill")
                .font(.system(size: 24))
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Colors
    
    private var buttonBackgroundColor: Color {
        switch state {
        case .idle:
            return .accentColor
        case .pressed, .recording:
            return .red
        case .cancelled:
            return .gray
        case .thinking:
            return .orange
        case .responding:
            return .green
        }
    }
    
    // MARK: - Gesture
    
    private var pttGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handleGestureChanged(value)
            }
            .onEnded { value in
                handleGestureEnded(value)
            }
    }
    
    private func handleGestureChanged(_ value: DragGesture.Value) {
        // Ignore during thinking/responding states
        guard state == .idle || state == .pressed || state == .recording else { return }
        
        // Initial press
        if pressStartTime == nil {
            pressStartTime = Date()
            initialPressLocation = value.startLocation
            state = .pressed
            
            // Haptic feedback on press
            impactMedium.impactOccurred()
            
            // Start recording after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if state == .pressed {
                    state = .recording
                    onRecordingStart()
                }
            }
        }
        
        // Track drag for cancel gesture
        currentDragOffset = value.translation
        
        // Check if dragged far enough to show cancel hint
        let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
        showCancelHint = distance > cancelThreshold / 2
    }
    
    private func handleGestureEnded(_ value: DragGesture.Value) {
        // Ignore during thinking/responding states
        guard state == .pressed || state == .recording else {
            resetGestureState()
            return
        }
        
        // Check if cancelled (dragged too far)
        let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
        
        if distance > cancelThreshold {
            // Cancelled
            state = .cancelled
            notificationFeedback.notificationOccurred(.warning)
            onRecordingCancel()
            
            // Reset to idle after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                state = .idle
            }
        } else {
            // Check minimum duration
            let duration = pressStartTime.map { Date().timeIntervalSince($0) } ?? 0
            
            if duration >= minimumRecordingDuration {
                // Valid recording - send
                impactLight.impactOccurred()
                onRecordingEnd()
                // State will be set to .thinking by parent
            } else {
                // Too short - cancel
                notificationFeedback.notificationOccurred(.error)
                onRecordingCancel()
                state = .idle
            }
        }
        
        resetGestureState()
    }
    
    private func resetGestureState() {
        pressStartTime = nil
        currentDragOffset = .zero
        showCancelHint = false
    }
}

// MARK: - Floating PTT Container

/// Container view that positions the PTT button as a floating overlay
struct FloatingPTTOverlay: View {
    /// Current audio amplitude
    let amplitude: CGFloat
    
    /// Current PTT state
    @Binding var state: PTTState
    
    /// Callbacks
    let onRecordingStart: () -> Void
    let onRecordingEnd: () -> Void
    let onRecordingCancel: () -> Void
    let onStopResponse: () -> Void
    
    /// Whether to show the overlay
    var isVisible: Bool = true
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                
                PushToTalkButton(
                    amplitude: amplitude,
                    state: $state,
                    onRecordingStart: onRecordingStart,
                    onRecordingEnd: onRecordingEnd,
                    onRecordingCancel: onRecordingCancel,
                    onStopResponse: onStopResponse
                )
                
                Spacer()
            }
            .padding(.bottom, 32)
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isVisible)
    }
}

// MARK: - Preview

#Preview("Idle") {
    VStack {
        Spacer()
        PushToTalkButton(
            amplitude: 0,
            state: .constant(.idle),
            onRecordingStart: {},
            onRecordingEnd: {},
            onRecordingCancel: {},
            onStopResponse: {}
        )
        Spacer()
    }
    .background(Color(.systemBackground))
}

#Preview("Recording") {
    VStack {
        Spacer()
        PushToTalkButton(
            amplitude: 0.6,
            state: .constant(.recording),
            onRecordingStart: {},
            onRecordingEnd: {},
            onRecordingCancel: {},
            onStopResponse: {}
        )
        Spacer()
    }
    .background(Color(.systemBackground))
}

#Preview("Thinking") {
    VStack {
        Spacer()
        PushToTalkButton(
            amplitude: 0,
            state: .constant(.thinking),
            onRecordingStart: {},
            onRecordingEnd: {},
            onRecordingCancel: {},
            onStopResponse: {}
        )
        Spacer()
    }
    .background(Color(.systemBackground))
}

#Preview("Responding") {
    VStack {
        Spacer()
        PushToTalkButton(
            amplitude: 0,
            state: .constant(.responding),
            onRecordingStart: {},
            onRecordingEnd: {},
            onRecordingCancel: {},
            onStopResponse: {}
        )
        Spacer()
    }
    .background(Color(.systemBackground))
}
