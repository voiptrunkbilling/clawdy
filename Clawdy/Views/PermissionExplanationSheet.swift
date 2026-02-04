import SwiftUI

/// Sheet view displaying pre-permission explanation with continue/skip options.
struct PermissionExplanationSheet: View {
    let permission: PermissionManager.PermissionType
    let onContinue: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: permission.systemImageName)
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
                .padding(.top, 40)
            
            // Title
            Text("\(permission.rawValue) Access")
                .font(.title)
                .fontWeight(.bold)
            
            // Explanation
            Text(permission.explanation)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
            
            // Buttons
            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text("Continue")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Button(action: onSkip) {
                    Text("Not Now")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }
}

/// Alert view for denied permissions with Settings deep-link.
struct PermissionDeniedAlert: ViewModifier {
    @ObservedObject var permissionManager: PermissionManager
    
    func body(content: Content) -> some View {
        content
            .alert(
                "Permission Required",
                isPresented: $permissionManager.showDeniedAlert,
                presenting: permissionManager.deniedPermission
            ) { permission in
                Button("Open Settings") {
                    permissionManager.openSettings()
                    permissionManager.dismissDeniedAlert()
                }
                Button("Cancel", role: .cancel) {
                    permissionManager.dismissDeniedAlert()
                }
            } message: { permission in
                Text(permission.deniedMessage)
            }
    }
}

/// View modifier for permission explanation sheet.
struct PermissionExplanationModifier: ViewModifier {
    @ObservedObject var permissionManager: PermissionManager
    let onGranted: ((PermissionManager.PermissionType) -> Void)?
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $permissionManager.showExplanation) {
                if let permission = permissionManager.pendingPermission {
                    PermissionExplanationSheet(
                        permission: permission,
                        onContinue: {
                            Task {
                                let granted = await permissionManager.confirmPermissionRequest()
                                if granted, let type = permissionManager.pendingPermission {
                                    onGranted?(type)
                                }
                            }
                        },
                        onSkip: {
                            permissionManager.cancelPermissionRequest()
                        }
                    )
                    .presentationDetents([.medium])
                }
            }
    }
}

extension View {
    /// Attach permission explanation sheet and denied alert handlers
    func permissionHandling(
        permissionManager: PermissionManager = .shared,
        onGranted: ((PermissionManager.PermissionType) -> Void)? = nil
    ) -> some View {
        self
            .modifier(PermissionExplanationModifier(permissionManager: permissionManager, onGranted: onGranted))
            .modifier(PermissionDeniedAlert(permissionManager: permissionManager))
    }
}

#Preview {
    PermissionExplanationSheet(
        permission: .calendar,
        onContinue: {},
        onSkip: {}
    )
}
