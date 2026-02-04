import SwiftUI
import Combine

/// Visual states for the waveform display
enum WaveformState {
    case idle
    case recording
    case thinking
    case responding
}

/// Real-time audio level visualization for voice interactions.
/// Displays animated bars during recording, pulsing animation during thinking,
/// and typing indicator during responding.
struct VoiceWaveformView: View {
    /// Current audio amplitude level (0.0 - 1.0)
    let amplitude: CGFloat
    
    /// Current state of the waveform
    let state: WaveformState
    
    /// Number of waveform bars
    var barCount: Int = 5
    
    /// Bar width
    var barWidth: CGFloat = 4
    
    /// Bar spacing
    var barSpacing: CGFloat = 3
    
    /// Maximum bar height
    var maxBarHeight: CGFloat = 32
    
    /// Minimum bar height
    var minBarHeight: CGFloat = 4
    
    /// Animation state for pulsing/thinking
    @State private var animationPhase: CGFloat = 0
    
    /// Timer for continuous animation
    @State private var animationTimer: Timer?
    
    var body: some View {
        Group {
            switch state {
            case .idle:
                idleView
            case .recording:
                recordingView
            case .thinking:
                thinkingView
            case .responding:
                respondingView
            }
        }
        .onAppear {
            startAnimationIfNeeded()
        }
        .onDisappear {
            stopAnimation()
        }
        .onChange(of: state) { _, newState in
            if newState == .thinking || newState == .responding {
                startAnimationIfNeeded()
            } else if newState == .idle {
                stopAnimation()
            }
        }
    }
    
    // MARK: - State Views
    
    /// Idle state - subtle static bars
    private var idleView: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: barWidth, height: minBarHeight)
            }
        }
    }
    
    /// Recording state - bars respond to audio amplitude
    private var recordingView: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let height = barHeight(for: index, amplitude: amplitude)
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(Color.accentColor)
                    .frame(width: barWidth, height: height)
                    .animation(.easeOut(duration: 0.1), value: amplitude)
            }
        }
    }
    
    /// Thinking state - pulsing dots/bars
    private var thinkingView: some View {
        HStack(spacing: barSpacing * 2) {
            ForEach(0..<3, id: \.self) { index in
                let delay = Double(index) * 0.15
                let scale = pulseScale(delay: delay)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(scale)
                    .opacity(0.5 + scale * 0.5)
            }
        }
    }
    
    /// Responding state - typing indicator animation
    private var respondingView: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let delay = Double(index) * 0.1
                let height = typingBarHeight(delay: delay)
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(Color.green)
                    .frame(width: barWidth, height: height)
            }
        }
    }
    
    // MARK: - Height Calculations
    
    /// Calculate bar height based on amplitude and bar position
    private func barHeight(for index: Int, amplitude: CGFloat) -> CGFloat {
        // Create a natural wave pattern - center bars are taller
        let centerIndex = CGFloat(barCount - 1) / 2
        let distanceFromCenter = abs(CGFloat(index) - centerIndex)
        let positionFactor = 1.0 - (distanceFromCenter / centerIndex) * 0.4
        
        // Add some randomness for natural look
        let randomFactor = 0.8 + CGFloat.random(in: 0...0.4)
        
        let heightFactor = amplitude * positionFactor * randomFactor
        let height = minBarHeight + (maxBarHeight - minBarHeight) * heightFactor
        
        return max(minBarHeight, min(maxBarHeight, height))
    }
    
    /// Calculate pulse scale for thinking animation
    private func pulseScale(delay: Double) -> CGFloat {
        let phase = animationPhase - delay
        let sine = sin(phase * .pi * 2)
        return 0.8 + 0.4 * CGFloat((sine + 1) / 2)
    }
    
    /// Calculate typing bar height for responding animation
    private func typingBarHeight(delay: Double) -> CGFloat {
        let phase = animationPhase - delay
        let sine = sin(phase * .pi * 2)
        let factor = CGFloat((sine + 1) / 2)
        return minBarHeight + (maxBarHeight * 0.6 - minBarHeight) * factor
    }
    
    // MARK: - Animation
    
    private func startAnimationIfNeeded() {
        guard animationTimer == nil else { return }
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { _ in
            withAnimation(.linear(duration: 1/30)) {
                animationPhase += 0.05
                if animationPhase > 100 {
                    animationPhase = 0
                }
            }
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

// MARK: - Audio Amplitude Helper

/// Utility to convert audio power (dB) to normalized amplitude (0-1)
struct AudioAmplitudeConverter {
    /// Convert decibel power level to normalized 0-1 amplitude
    /// - Parameter power: The power level in decibels (typically -160 to 0)
    /// - Returns: Normalized amplitude from 0.0 to 1.0
    static func normalize(power: Float) -> CGFloat {
        // Clamp power to reasonable range
        let clampedPower = max(-60, min(0, power))
        
        // Convert dB to linear scale
        // Formula: amplitude = 10^(dB/20)
        let linearAmplitude = pow(10, clampedPower / 20)
        
        // Scale to 0-1 range with some boost for better visualization
        let scaled = CGFloat(linearAmplitude) * 2.0
        
        return min(1.0, max(0.0, scaled))
    }
}

// MARK: - Preview

#Preview("Idle") {
    VoiceWaveformView(amplitude: 0, state: .idle)
        .padding()
}

#Preview("Recording Low") {
    VoiceWaveformView(amplitude: 0.2, state: .recording)
        .padding()
}

#Preview("Recording High") {
    VoiceWaveformView(amplitude: 0.8, state: .recording)
        .padding()
}

#Preview("Thinking") {
    VoiceWaveformView(amplitude: 0, state: .thinking)
        .padding()
}

#Preview("Responding") {
    VoiceWaveformView(amplitude: 0, state: .responding)
        .padding()
}
