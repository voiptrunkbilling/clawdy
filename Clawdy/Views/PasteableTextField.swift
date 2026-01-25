import SwiftUI
import UIKit

/// A UITextField wrapper that intercepts paste operations to detect images from clipboard.
///
/// When the user pastes content, this component checks if there's an image on the clipboard.
/// If an image is found, it calls `onImagePaste` instead of the normal paste behavior.
/// If no image is found, normal text paste proceeds.
///
/// Usage:
/// ```swift
/// PasteableTextField(
///     text: $textInput,
///     placeholder: "Message",
///     onImagePaste: { image in
///         Task { await viewModel.addImageFromClipboard(image) }
///     },
///     onSubmit: { viewModel.sendTextInput() },
///     isFocused: $isTextFieldFocused
/// )
/// ```
///
/// Accessibility: Inherits UITextField's native VoiceOver support.
/// Custom paste behavior is transparent to assistive technologies.
struct PasteableTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onImagePaste: (UIImage) -> Void
    let onSubmit: () -> Void
    var isFocused: FocusState<Bool>.Binding
    let isEnabled: Bool
    
    func makeUIView(context: Context) -> PasteableUITextField {
        let textField = PasteableUITextField()
        textField.placeholder = placeholder
        textField.delegate = context.coordinator
        textField.onImagePaste = onImagePaste
        textField.returnKeyType = .send
        textField.borderStyle = .none
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        
        // Add target for text changes
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textFieldDidChange(_:)),
            for: .editingChanged
        )
        
        return textField
    }
    
    func updateUIView(_ uiView: PasteableUITextField, context: Context) {
        // Only update text if it's different to avoid cursor jumping
        if uiView.text != text {
            uiView.text = text
        }
        uiView.isEnabled = isEnabled
        uiView.alpha = isEnabled ? 1.0 : 0.6
        
        // Handle focus state
        DispatchQueue.main.async {
            if isFocused.wrappedValue && !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            } else if !isFocused.wrappedValue && uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        let parent: PasteableTextField
        
        init(_ parent: PasteableTextField) {
            self.parent = parent
        }
        
        @objc func textFieldDidChange(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
        
        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                self.parent.isFocused.wrappedValue = true
            }
        }
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                self.parent.isFocused.wrappedValue = false
            }
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false // Don't insert newline
        }
    }
}

// MARK: - Custom UITextField with Image Paste Support

/// UITextField subclass that intercepts paste operations to detect clipboard images.
///
/// Overrides `paste(_:)` to check for images before falling back to default behavior.
/// Also overrides `canPerformAction` to show paste option when either images or text
/// are available on the clipboard.
class PasteableUITextField: UITextField {
    /// Callback when an image is pasted from clipboard
    var onImagePaste: ((UIImage) -> Void)?
    
    override func paste(_ sender: Any?) {
        // Check for image first
        if let image = UIPasteboard.general.image {
            // Provide haptic feedback for image paste
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            
            // Announce for VoiceOver
            UIAccessibility.post(notification: .announcement, argument: "Image pasted")
            
            onImagePaste?(image)
        } else {
            // Fall back to normal text paste
            super.paste(sender)
        }
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            // Enable paste if either images or strings are available
            return UIPasteboard.general.hasImages || UIPasteboard.general.hasStrings
        }
        return super.canPerformAction(action, withSender: sender)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State var text = ""
        @FocusState var isFocused: Bool
        
        var body: some View {
            VStack {
                Spacer()
                
                PasteableTextField(
                    text: $text,
                    placeholder: "Type a message or paste an image",
                    onImagePaste: { image in
                        print("Image pasted: \(image.size)")
                    },
                    onSubmit: {
                        print("Submit: \(text)")
                    },
                    isFocused: $isFocused,
                    isEnabled: true
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(20)
                .padding()
            }
        }
    }
    
    return PreviewWrapper()
}
