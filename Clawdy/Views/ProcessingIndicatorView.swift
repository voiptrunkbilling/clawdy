import SwiftUI

/// Displays the current processing state (thinking, tool use, responding)
/// with animated indicators for visual feedback during RPC streaming.
/// Note: Streaming text is now displayed directly in the TranscriptView
/// via the streamingMessage bubble, not here.
struct ProcessingIndicatorView: View {
    let state: ProcessingState
    
    /// Action to call when cancel button is tapped
    var onCancel: (() -> Void)? = nil
    
    /// Whether cancel is currently in progress
    var isCancelling: Bool = false
    
    /// Animation state for the dots
    @State private var animatingDots = false
    
    var body: some View {
        if state.isActive {
            // Processing state indicator with cancel button
            HStack(spacing: 12) {
                // State indicator pill
                HStack(spacing: 8) {
                    // Animated icon based on state
                    stateIcon
                        .font(.system(size: 14))
                        .foregroundColor(stateColor)
                    
                    // State description with animated dots
                    HStack(spacing: 2) {
                        Text(stateLabel)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        // Animated ellipsis
                        AnimatedDots()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(stateBackgroundColor)
                .cornerRadius(20)
                
                // Cancel button
                if let onCancel = onCancel {
                    CancelButton(
                        isCancelling: isCancelling,
                        action: onCancel
                    )
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.easeInOut(duration: 0.2), value: state)
        }
    }
    
    // MARK: - State-specific styling
    
    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .idle:
            EmptyView()
        case .thinking:
            Image(systemName: "brain")
        case .responding:
            Image(systemName: "text.bubble")
        case .usingTool:
            Image(systemName: "hammer.fill")
        }
    }
    
    private var stateLabel: String {
        switch state {
        case .idle:
            return ""
        case .thinking:
            return "Thinking"
        case .responding:
            return "Responding"
        case .usingTool(let name):
            return formatToolName(name)
        }
    }
    
    private var stateColor: Color {
        switch state {
        case .idle:
            return .clear
        case .thinking:
            return .purple
        case .responding:
            return .blue
        case .usingTool:
            return .orange
        }
    }
    
    private var stateBackgroundColor: Color {
        stateColor.opacity(0.15)
    }
    
    /// Format tool name for display (e.g., "Bash" instead of "bash")
    private func formatToolName(_ name: String) -> String {
        // Map common tool names to user-friendly versions
        let toolDisplayNames: [String: String] = [
            "bash": "Running command",
            "Bash": "Running command",
            "read": "Reading file",
            "Read": "Reading file",
            "write": "Writing file",
            "Write": "Writing file",
            "edit": "Editing file",
            "Edit": "Editing file",
            "mcp": "Using tool",
        ]
        
        return toolDisplayNames[name] ?? "Using \(name.capitalized)"
    }
}

// MARK: - Cancel Button

/// A cancel button that appears during generation
struct CancelButton: View {
    let isCancelling: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            action()
        }) {
            HStack(spacing: 6) {
                if isCancelling {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                }
                
                Text(isCancelling ? "Stopping" : "Cancel")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isCancelling ? Color.gray : Color.red)
            .cornerRadius(20)
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .disabled(isCancelling)
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .animation(.easeInOut(duration: 0.2), value: isCancelling)
    }
}

// MARK: - Animated Dots

/// Animated ellipsis that cycles through dots
struct AnimatedDots: View {
    @State private var dotCount = 0
    
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<3) { index in
                Text(".")
                    .opacity(index < dotCount ? 1.0 : 0.3)
            }
        }
        .font(.subheadline)
        .fontWeight(.medium)
        .onReceive(timer) { _ in
            dotCount = (dotCount % 3) + 1
        }
    }
}



// MARK: - Tool Progress View

/// Detailed view for tool execution progress (can be used for expanded display)
struct ToolProgressView: View {
    let toolName: String
    let isComplete: Bool
    
    @State private var rotation: Double = 0
    
    var body: some View {
        HStack(spacing: 12) {
            // Spinning gear or checkmark
            ZStack {
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.orange)
                        .rotationEffect(.degrees(rotation))
                        .onAppear {
                            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                                rotation = 360
                            }
                        }
                }
            }
            .font(.system(size: 20))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(toolName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(isComplete ? "Complete" : "Running...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview("Processing States") {
    VStack(spacing: 20) {
        ProcessingIndicatorView(
            state: .thinking,
            onCancel: { print("Cancel tapped") },
            isCancelling: false
        )
        
        ProcessingIndicatorView(
            state: .responding,
            onCancel: { print("Cancel tapped") },
            isCancelling: false
        )
        
        ProcessingIndicatorView(
            state: .usingTool(name: "bash"),
            onCancel: { print("Cancel tapped") },
            isCancelling: true
        )
        
        ProcessingIndicatorView(
            state: .usingTool(name: "read")
        )
        
        CancelButton(isCancelling: false, action: { print("Cancel") })
        
        CancelButton(isCancelling: true, action: { print("Cancel") })
        
        ToolProgressView(toolName: "Running bash command", isComplete: false)
        
        ToolProgressView(toolName: "Read file", isComplete: true)
    }
    .padding()
}
