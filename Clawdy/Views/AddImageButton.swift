import SwiftUI

/// "+" button with menu to select image source (Photo Library or Camera).
/// Displays as a blue circle with plus icon when enabled, gray when disabled.
///
/// The menu appears above the button when tapped, providing options for
/// "Photo Library" and "Take Photo".
///
/// Accessibility:
/// - Label announces "Add image"
/// - Hint dynamically changes based on enabled state
/// - Disabled trait applied when max images reached
struct AddImageButton: View {
    /// Whether the button is enabled (false when max images reached)
    let isEnabled: Bool
    
    /// Action to open photo library
    let onPhotoLibrary: () -> Void
    
    /// Action to open camera
    let onCamera: () -> Void
    
    var body: some View {
        // Wrap in ZStack to provide stable view hierarchy for Menu
        ZStack {
            Menu {
                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    onPhotoLibrary()
                }) {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                }
                
                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    onCamera()
                }) {
                    Label("Take Photo", systemImage: "camera")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(isEnabled ? .blue : .gray)
            }
            .menuOrder(.fixed)
            .disabled(!isEnabled)
        }
        .accessibilityLabel("Add image")
        .accessibilityHint(accessibilityHintText)
        .accessibilityAddTraits(.isButton)
        .accessibilityRemoveTraits(isEnabled ? [] : .isButton)
    }
    
    /// Dynamic accessibility hint based on enabled state
    private var accessibilityHintText: String {
        isEnabled
            ? "Add photo or take picture"
            : "Maximum 3 images reached"
    }
}

// MARK: - Previews

#Preview("Enabled") {
    AddImageButton(
        isEnabled: true,
        onPhotoLibrary: { print("Photo Library tapped") },
        onCamera: { print("Camera tapped") }
    )
    .padding()
}

#Preview("Disabled") {
    AddImageButton(
        isEnabled: false,
        onPhotoLibrary: { print("Photo Library tapped") },
        onCamera: { print("Camera tapped") }
    )
    .padding()
}
