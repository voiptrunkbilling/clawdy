import SwiftUI

/// A full-screen white flash overlay that provides visual feedback when a photo is captured.
/// This mimics the iOS camera shutter effect to indicate that a photo was taken,
/// particularly useful for the camera.snap node capability when the agent takes a photo.
///
/// The overlay appears briefly (typically 150ms) and fades out quickly.
/// It covers the entire screen to provide clear visual feedback regardless of the current UI state.
struct CameraFlashOverlay: View {
    var body: some View {
        Rectangle()
            .fill(Color.white)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        // Sample background to show flash effect
        VStack {
            Text("Camera Flash Preview")
                .font(.title)
            Spacer()
            Text("The screen will flash white")
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        
        // Flash overlay
        CameraFlashOverlay()
            .opacity(0.8)
    }
}
