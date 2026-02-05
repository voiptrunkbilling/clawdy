import SwiftUI

/// Text input bar for text-based interaction mode.
/// Provides a text field with send button, mic toggle, and image attachment support.
///
/// Layout (vertical stack):
/// ┌─────────────────────────────────────────┐
/// │ [thumb1 X] [thumb2 X] [thumb3 X]        │  ← ImagePreviewStrip (conditional)
/// ├─────────────────────────────────────────┤
/// │ [+] [____Text Field____] [🎤] [Send]    │  ← Input row
/// └─────────────────────────────────────────┘
///
/// Accessibility: Full VoiceOver support with labeled buttons, hints,
/// and proper navigation order. The text field announces its state
/// (enabled/disabled) and the send button provides clear feedback.
struct TextInputBar: View {
    @Binding var text: String
    @Binding var pendingImages: [ImageAttachment]
    let onSend: () -> Void
    let onSwitchToVoice: () -> Void
    let onPhotoLibrary: () -> Void
    let onCamera: () -> Void
    let onRemoveImage: (UUID) -> Void
    let isEnabled: Bool
    
    /// Focus binding from parent view - allows external control of keyboard
    var isFocused: FocusState<Bool>.Binding
    
    /// Maximum images allowed per message
    private let maxImages = 3
    
    /// Whether more images can be added
    private var canAddMoreImages: Bool {
        pendingImages.count < maxImages
    }
    
    /// Whether the send button should be enabled
    /// Allows sending with text only, images only, or both
    private var canSend: Bool {
        isEnabled && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Image preview strip (shown only when there are pending images)
            if !pendingImages.isEmpty {
                ImagePreviewStrip(images: pendingImages, onRemove: onRemoveImage)
            }
            
            // Input row: [+] [TextField] [Mic] [Send]
            HStack(alignment: .bottom, spacing: 8) {
                // Add image button with menu - 44pt touch target
                AddImageButton(
                    isEnabled: canAddMoreImages && isEnabled,
                    onPhotoLibrary: onPhotoLibrary,
                    onCamera: onCamera
                )
                .frame(minWidth: 44, minHeight: 44)
                
                // Text field with rounded border
                TextField("Message", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(20)
                    .lineLimit(1...5)
                    .focused(isFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        if canSend {
                            sendWithHaptic()
                        }
                    }
                    .disabled(!isEnabled)
                    .opacity(isEnabled ? 1.0 : 0.6)
                    .accessibilityLabel(textFieldAccessibilityLabel)
                    .accessibilityHint(textFieldAccessibilityHint)
                    .accessibilityValue(text.isEmpty ? "Empty" : "\(text.count) characters")
                
                // Mic button to switch back to voice mode - 44pt touch target
                Button(action: {
                    // Haptic feedback on mode switch
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    // Announce mode change for VoiceOver users
                    UIAccessibility.post(notification: .announcement, argument: "Switching to voice input mode")
                    onSwitchToVoice()
                }) {
                    Image(systemName: "mic.fill")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Voice mode")
                .accessibilityHint("Double tap to switch to voice input mode")
                .accessibilityAddTraits(.isButton)
                
                // Send button - 44pt touch target
                Button(action: sendWithHaptic) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(canSend ? .blue : .gray)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .accessibilityHint(sendButtonAccessibilityHint)
                .accessibilityAddTraits(.isButton)
                .accessibilityRemoveTraits(canSend ? [] : .isButton)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .padding(.bottom, 8) // Extra bottom padding for safe area
        .background(Color(.systemBackground))
        .background(
            // Extend background to cover keyboard area
            Color(.systemBackground)
                .ignoresSafeArea(.container, edges: .bottom)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Text input area")
    }
    
    // MARK: - Accessibility Helpers
    
    private var textFieldAccessibilityLabel: String {
        if !isEnabled {
            return "Message input, disabled"
        }
        return "Message input"
    }
    
    private var textFieldAccessibilityHint: String {
        if !isEnabled {
            return "Connection required to send messages"
        }
        return "Type your message to Claude"
    }
    
    private var sendButtonAccessibilityHint: String {
        if !isEnabled {
            return "Connection required to send"
        }
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImages = !pendingImages.isEmpty
        
        if !hasText && !hasImages {
            return "Type a message or add images first"
        }
        
        if hasImages && hasText {
            return "Double tap to send message with \(pendingImages.count) \(pendingImages.count == 1 ? "image" : "images")"
        } else if hasImages {
            return "Double tap to send \(pendingImages.count) \(pendingImages.count == 1 ? "image" : "images")"
        }
        return "Double tap to send message"
    }
    
    /// Send the message with haptic feedback and VoiceOver announcement
    private func sendWithHaptic() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        // Announce for VoiceOver users
        UIAccessibility.post(notification: .announcement, argument: "Sending message")
        onSend()
    }
}

// MARK: - Mode Toggle Button

/// Small button to toggle from voice mode to text mode
///
/// Accessibility: Announces mode change when activated for VoiceOver users.
struct TextModeToggleButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            // Haptic feedback on mode switch
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            // Announce mode change for VoiceOver users
            UIAccessibility.post(notification: .announcement, argument: "Switching to text input mode")
            action()
        }) {
            Image(systemName: "keyboard")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(10)
                .background(Color(.tertiarySystemBackground))
                .clipShape(Circle())
        }
        .accessibilityLabel("Text mode")
        .accessibilityHint("Double tap to switch to keyboard input mode")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Preview Wrapper

/// Wrapper view for previewing TextInputBar with FocusState
private struct TextInputBarPreview: View {
    @State var text: String
    @State var pendingImages: [ImageAttachment]
    let isEnabled: Bool
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack {
            Spacer()
            TextInputBar(
                text: $text,
                pendingImages: $pendingImages,
                onSend: { print("Send tapped") },
                onSwitchToVoice: { print("Switch to voice") },
                onPhotoLibrary: { print("Photo library tapped") },
                onCamera: { print("Camera tapped") },
                onRemoveImage: { id in print("Remove image: \(id)") },
                isEnabled: isEnabled,
                isFocused: $isFocused
            )
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Previews

#Preview("Text Input Bar - Enabled") {
    TextInputBarPreview(text: "Hello, world!", pendingImages: [], isEnabled: true)
}

#Preview("Text Input Bar - Empty") {
    TextInputBarPreview(text: "", pendingImages: [], isEnabled: true)
}

#Preview("Text Input Bar - Disabled") {
    TextInputBarPreview(text: "Can't send this", pendingImages: [], isEnabled: false)
}

#Preview("Text Input Bar - With Images") {
    let tempURL = FileManager.default.temporaryDirectory
    let mockImages = (1...2).map { index in
        ImageAttachment(
            tempFileURL: tempURL.appendingPathComponent("test\(index).jpg"),
            mediaType: "image/jpeg",
            originalSize: 1000 * index,
            dimensions: CGSize(width: 100, height: 100)
        )
    }
    return TextInputBarPreview(text: "Check out these images", pendingImages: mockImages, isEnabled: true)
}

#Preview("Text Input Bar - Max Images") {
    let tempURL = FileManager.default.temporaryDirectory
    let mockImages = (1...3).map { index in
        ImageAttachment(
            tempFileURL: tempURL.appendingPathComponent("test\(index).jpg"),
            mediaType: "image/jpeg",
            originalSize: 1000 * index,
            dimensions: CGSize(width: 100, height: 100)
        )
    }
    return TextInputBarPreview(text: "", pendingImages: mockImages, isEnabled: true)
}

#Preview("Text Mode Toggle Button") {
    TextModeToggleButton(action: { print("Toggle tapped") })
        .padding()
}
