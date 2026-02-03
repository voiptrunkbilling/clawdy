import Foundation
import UIKit
import UserNotifications

/// Manages Apple Push Notification service (APNs) registration and token handling.
/// Works alongside NotificationManager for remote push notification support.
@MainActor
class APNsManager: NSObject, ObservableObject {
    static let shared = APNsManager()
    
    // MARK: - Published Properties
    
    /// Current APNs device token (hex string)
    @Published private(set) var deviceToken: String?
    
    /// Whether APNs registration is in progress
    @Published private(set) var isRegistering: Bool = false
    
    /// Last registration error
    @Published private(set) var lastError: Error?
    
    /// Whether the token is registered with the gateway
    @Published private(set) var isRegisteredWithGateway: Bool = false
    
    // MARK: - Properties
    
    /// Current APNs environment (sandbox or production)
    var environment: APNsEnvironment {
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
    }
    
    /// App bundle identifier
    private let bundleId: String
    
    /// Callback for when a remote notification is received
    var onRemoteNotificationReceived: ((RemoteNotificationPayload) -> Void)?
    
    // MARK: - Types
    
    enum APNsEnvironment: String, Codable {
        case sandbox
        case production
    }
    
    /// Parsed payload from Clawdy push notifications
    struct RemoteNotificationPayload {
        let title: String?
        let body: String?
        let category: String?
        let sessionKey: String?
        let messageId: String?
        let jobId: String?
        let isContentAvailable: Bool
        let rawPayload: [AnyHashable: Any]
    }
    
    // MARK: - Initialization
    
    private override init() {
        self.bundleId = Bundle.main.bundleIdentifier ?? "ai.openclaw.clawdy"
        super.init()
    }
    
    // MARK: - Registration
    
    /// Request APNs registration.
    /// This will trigger the system to request permission and register for remote notifications.
    /// The actual token is received via AppDelegate callbacks.
    func requestRegistration() async {
        guard !isRegistering else {
            print("[APNsManager] Registration already in progress")
            return
        }
        
        isRegistering = true
        lastError = nil
        
        // First ensure notification permission is granted
        let notificationManager = NotificationManager.shared
        let granted = await notificationManager.requestAuthorization()
        
        guard granted else {
            print("[APNsManager] Notification permission denied, cannot register for APNs")
            lastError = APNsError.permissionDenied
            isRegistering = false
            return
        }
        
        // Request remote notification registration
        // This triggers a call to AppDelegate's didRegisterForRemoteNotificationsWithDeviceToken
        print("[APNsManager] Requesting remote notification registration...")
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    /// Called when the app receives the APNs device token.
    /// This is invoked from AppDelegate.
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[APNsManager] Received APNs token: \(tokenString.prefix(16))...")
        
        self.deviceToken = tokenString
        self.isRegistering = false
        self.lastError = nil
        
        // Automatically register with gateway if connected
        Task {
            await registerTokenWithGateway()
        }
    }
    
    /// Called when APNs registration fails.
    /// This is invoked from AppDelegate.
    func didFailToRegisterForRemoteNotifications(withError error: Error) {
        print("[APNsManager] Failed to register for APNs: \(error.localizedDescription)")
        
        self.lastError = error
        self.isRegistering = false
        self.deviceToken = nil
    }
    
    // MARK: - Gateway Registration
    
    /// Register the APNs token with the gateway.
    /// Call this after receiving the token and when connected to the gateway.
    func registerTokenWithGateway() async {
        guard let token = deviceToken else {
            print("[APNsManager] No token to register")
            return
        }
        
        guard let deviceId = DeviceIdentityStore.shared.persistentDeviceID else {
            print("[APNsManager] No device ID available")
            return
        }
        
        // Get the gateway connection
        guard let connection = GatewayDualConnectionManager.shared.primaryConnection else {
            print("[APNsManager] No gateway connection available")
            return
        }
        
        do {
            let params: [String: Any] = [
                "deviceId": deviceId,
                "apnsToken": token,
                "environment": environment.rawValue,
                "bundleId": bundleId
            ]
            
            print("[APNsManager] Registering APNs token with gateway...")
            let response = try await connection.sendRequest(method: "device.apns.register", params: params)
            
            if response.success {
                print("[APNsManager] Successfully registered APNs token with gateway")
                isRegisteredWithGateway = true
            } else {
                print("[APNsManager] Gateway rejected APNs registration: \(response.error?.message ?? "unknown error")")
                isRegisteredWithGateway = false
            }
        } catch {
            print("[APNsManager] Failed to register APNs token with gateway: \(error)")
            isRegisteredWithGateway = false
        }
    }
    
    // MARK: - Notification Handling
    
    /// Handle incoming remote notification.
    /// This is called from AppDelegate or SceneDelegate when a push is received.
    func handleRemoteNotification(userInfo: [AnyHashable: Any], completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("[APNsManager] Received remote notification")
        
        let payload = parseNotificationPayload(userInfo)
        
        // Check if this is a silent notification (background fetch)
        if payload.isContentAvailable {
            print("[APNsManager] Processing silent notification")
            handleSilentNotification(payload: payload, completionHandler: completionHandler)
            return
        }
        
        // Handle regular notification
        onRemoteNotificationReceived?(payload)
        completionHandler(.newData)
    }
    
    /// Parse the notification payload from userInfo.
    private func parseNotificationPayload(_ userInfo: [AnyHashable: Any]) -> RemoteNotificationPayload {
        // Parse aps dictionary
        let aps = userInfo["aps"] as? [String: Any] ?? [:]
        let alert = aps["alert"] as? [String: Any]
        
        let title = alert?["title"] as? String
        let body = alert?["body"] as? String
        let category = aps["category"] as? String
        let isContentAvailable = (aps["content-available"] as? Int ?? 0) == 1
        
        // Parse clawdy custom payload
        let clawdy = userInfo["clawdy"] as? [String: Any] ?? [:]
        let sessionKey = clawdy["sessionKey"] as? String
        let messageId = clawdy["messageId"] as? String
        let jobId = clawdy["jobId"] as? String
        
        return RemoteNotificationPayload(
            title: title,
            body: body,
            category: category,
            sessionKey: sessionKey,
            messageId: messageId,
            jobId: jobId,
            isContentAvailable: isContentAvailable,
            rawPayload: userInfo
        )
    }
    
    /// Handle silent (background) notifications.
    private func handleSilentNotification(payload: RemoteNotificationPayload, completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // If there's a session key, trigger a background sync
        if let sessionKey = payload.sessionKey {
            print("[APNsManager] Silent notification for session: \(sessionKey)")
            
            // Notify observers about the background sync request
            NotificationCenter.default.post(
                name: .apnsBackgroundSyncRequested,
                object: nil,
                userInfo: ["sessionKey": sessionKey]
            )
        }
        
        completionHandler(.newData)
    }
    
    // MARK: - Errors
    
    enum APNsError: LocalizedError {
        case permissionDenied
        case notRegistered
        case gatewayNotConnected
        
        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Notification permission was denied"
            case .notRegistered:
                return "Not registered for push notifications"
            case .gatewayNotConnected:
                return "Gateway is not connected"
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a silent notification requests a background sync.
    /// userInfo contains "sessionKey" key.
    static let apnsBackgroundSyncRequested = Notification.Name("apnsBackgroundSyncRequested")
    
    /// Posted when a remote push notification is received.
    /// userInfo contains the parsed payload.
    static let apnsRemoteNotificationReceived = Notification.Name("apnsRemoteNotificationReceived")
}

// MARK: - AppDelegate Integration

/// Extension providing helper methods for AppDelegate integration.
extension APNsManager {
    /// Call this from AppDelegate's application(_:didFinishLaunchingWithOptions:)
    /// to set up APNs registration on app launch.
    func applicationDidFinishLaunching() {
        // Check if we have a token stored and re-register if needed
        Task { @MainActor in
            // If we already have notification permission, register for APNs
            if NotificationManager.shared.isAuthorized {
                await requestRegistration()
            }
        }
    }
}
