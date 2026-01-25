import Foundation
import LocalAuthentication

/// Manager for biometric authentication (Face ID / Touch ID).
/// Requires successful authentication before accessing the app.
@MainActor
class AuthenticationManager: ObservableObject {
    // MARK: - Singleton

    static let shared = AuthenticationManager()

    // MARK: - Published State

    @Published var isAuthenticated = false
    @Published var authenticationError: String?

    // MARK: - Private Properties

    private let context = LAContext()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Check if biometric authentication is available on this device
    var biometricType: BiometricType {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            return .opticID
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }

    /// Check if any authentication method is available (biometric or passcode)
    var canAuthenticate: Bool {
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Prompt for biometric authentication
    func authenticate() async {
        // Reset any previous error
        authenticationError = nil

        // Create a new context for each authentication attempt
        let context = LAContext()

        // Check if biometric or passcode authentication is available
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationError = error?.localizedDescription ?? "Authentication not available"
            return
        }

        // Reason shown to user during authentication prompt
        let reason = "Authenticate to access Clawdy"

        do {
            // Use deviceOwnerAuthentication to allow passcode fallback if biometrics fail
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            isAuthenticated = success
        } catch let authError as LAError {
            handleAuthenticationError(authError)
        } catch {
            authenticationError = error.localizedDescription
        }
    }

    /// Lock the app (require re-authentication)
    func lock() {
        isAuthenticated = false
        authenticationError = nil
    }

    // MARK: - Private Methods

    private func handleAuthenticationError(_ error: LAError) {
        switch error.code {
        case .userCancel:
            // User cancelled, don't show error
            authenticationError = nil
        case .userFallback:
            // User chose passcode fallback - this is handled by deviceOwnerAuthentication
            authenticationError = nil
        case .biometryNotAvailable:
            authenticationError = "Biometric authentication not available"
        case .biometryNotEnrolled:
            authenticationError = "No biometrics enrolled. Please set up Face ID or Touch ID in Settings."
        case .biometryLockout:
            authenticationError = "Biometric authentication locked. Please use device passcode."
        case .authenticationFailed:
            authenticationError = "Authentication failed. Please try again."
        case .passcodeNotSet:
            authenticationError = "Device passcode not set. Please set a passcode in Settings."
        default:
            authenticationError = error.localizedDescription
        }
    }
}

// MARK: - Biometric Type

enum BiometricType {
    case none
    case faceID
    case touchID
    case opticID

    var displayName: String {
        switch self {
        case .none:
            return "Passcode"
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        }
    }

    var systemImage: String {
        switch self {
        case .none:
            return "lock.fill"
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        }
    }
}
