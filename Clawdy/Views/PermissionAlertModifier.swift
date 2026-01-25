import SwiftUI
import UIKit

/// View modifier that displays permission alerts for camera and photo library access.
/// Shows an alert with an "Open Settings" button when permissions are denied.
struct PermissionAlertModifier: ViewModifier {
    @Binding var alertType: ImagePickerCoordinator.PermissionAlertType?
    
    func body(content: Content) -> some View {
        content
            .alert(item: $alertType) { type in
                Alert(
                    title: Text(type.title),
                    message: Text(type.message),
                    primaryButton: .default(Text("Open Settings")) {
                        openSettings()
                    },
                    secondaryButton: .cancel()
                )
            }
    }
    
    /// Opens the app's Settings page in the iOS Settings app.
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies the permission alert modifier to handle camera and photo library permission alerts.
    /// - Parameter alertType: Binding to the alert type to display
    /// - Returns: Modified view with permission alert handling
    func permissionAlert(_ alertType: Binding<ImagePickerCoordinator.PermissionAlertType?>) -> some View {
        self.modifier(PermissionAlertModifier(alertType: alertType))
    }
}
