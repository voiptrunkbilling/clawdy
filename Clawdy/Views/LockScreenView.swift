import SwiftUI
import UIKit

/// Lock screen shown when app requires authentication.
/// Displays Face ID / Touch ID prompt with option to retry.
struct LockScreenView: View {
    @ObservedObject var authManager: AuthenticationManager

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon/logo area
            appIconView
                .frame(width: 96, height: 96)

            Text("Clawdy")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Locked")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            // Biometric button
            Button(action: {
                Task {
                    await authManager.authenticate()
                }
            }) {
                VStack(spacing: 12) {
                    Image(systemName: authManager.biometricType.systemImage)
                        .font(.title)
                        .foregroundColor(.blue)

                    Text("Unlock with \(authManager.biometricType.displayName)")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
            }
            .accessibilityLabel("Unlock with \(authManager.biometricType.displayName)")
            .accessibilityHint("Double tap to authenticate and unlock the app")
            .padding(.horizontal, 40)

            // Error message if present
            if let error = authManager.authenticationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
                .frame(height: 60)
        }
        .background(Color(.systemBackground))
        .onAppear {
            // Automatically prompt for authentication when view appears
            Task {
                await authManager.authenticate()
            }
        }
    }

    @ViewBuilder
    private var appIconView: some View {
        if let appIconImage {
            Image(uiImage: appIconImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            Image(systemName: "app.dashed")
                .font(.largeTitle)
                .foregroundColor(.blue)
        }
    }

    private var appIconImage: UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let iconName = iconFiles.last else {
            return nil
        }

        return UIImage(named: iconName)
    }
}

#Preview {
    LockScreenView(authManager: AuthenticationManager.shared)
}
