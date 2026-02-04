import Foundation
import UIKit
import UserNotifications
import OSLog
import Combine

/// Manages Apple Push Notification service (APNs) registration and token handling.
/// Works alongside NotificationManager for remote push notification support.
@MainActor
class APNsManager: NSObject, ObservableObject {
    static let shared = APNsManager()
    
    // MARK: - Notification Categories
    
    /// Category for agent/chat messages
    static let agentMessageCategory = "agent_message"
    
    /// Category for cron job alerts
    static let cronAlertCategory = "cron_alert"
    
    /// Category for silent sync (background refresh)
    static let silentSyncCategory = "silent_sync"
    
    private let logger = Logger(subsystem: "com.clawdy", category: "apns")
    
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
            logger.info("Registration already in progress")
            return
        }
        
        isRegistering = true
        lastError = nil
        
        // First ensure notification permission is granted
        let notificationManager = NotificationManager.shared
        let granted = await notificationManager.requestAuthorization()
        
        guard granted else {
            logger.warning("Notification permission denied, cannot register for APNs")
            lastError = APNsError.permissionDenied
            isRegistering = false
            return
        }
        
        // Register notification categories for custom actions
        await registerNotificationCategories()
        
        // Request remote notification registration
        // This triggers a call to AppDelegate's didRegisterForRemoteNotificationsWithDeviceToken
        logger.info("Requesting remote notification registration...")
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    /// Register notification categories for different notification types.
    private func registerNotificationCategories() async {
        let agentMessageCategory = UNNotificationCategory(
            identifier: Self.agentMessageCategory,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        let cronAlertCategory = UNNotificationCategory(
            identifier: Self.cronAlertCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        
        let silentSyncCategory = UNNotificationCategory(
            identifier: Self.silentSyncCategory,
            actions: [],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "",
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            agentMessageCategory,
            cronAlertCategory,
            silentSyncCategory
        ])
        
        logger.debug("Registered notification categories")
    }
    
    /// Called when the app receives the APNs device token.
    /// This is invoked from AppDelegate.
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        logger.info("Received APNs token: \(tokenString.prefix(16), privacy: .public)...")
        
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
        logger.error("Failed to register for APNs: \(error.localizedDescription, privacy: .public)")
        
        self.lastError = error
        self.isRegistering = false
        self.deviceToken = nil
    }
    
    // MARK: - Gateway Registration
    
    /// Register the APNs token with the gateway.
    /// Call this after receiving the token and when connected to the gateway.
    func registerTokenWithGateway() async {
        guard let token = deviceToken else {
            logger.debug("No token to register")
            return
        }
        
        let identity = DeviceIdentityStore.loadOrCreate()
        let deviceId = identity.deviceId
        
        // Check if gateway is connected
        let connectionManager = GatewayDualConnectionManager.shared
        guard connectionManager.status.isConnected || connectionManager.status.isPartiallyConnected else {
            logger.info("Gateway not connected, will retry token registration later")
            return
        }
        
        do {
            let params: [String: Any] = [
                "deviceId": deviceId,
                "apnsToken": token,
                "environment": environment.rawValue,
                "bundleId": bundleId
            ]
            
            logger.info("Registering APNs token with gateway...")
            _ = try await connectionManager.request(method: "device.register", params: params)
            
            logger.info("Successfully registered APNs token with gateway")
            isRegisteredWithGateway = true
        } catch {
            logger.error("Failed to register APNs token with gateway: \(error.localizedDescription, privacy: .public)")
            isRegisteredWithGateway = false
        }
    }
    
    // MARK: - Notification Handling
    
    /// Handle incoming remote notification.
    /// This is called from AppDelegate or SceneDelegate when a push is received.
    func handleRemoteNotification(userInfo: [AnyHashable: Any], completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        logger.info("Received remote notification")
        
        let payload = parseNotificationPayload(userInfo)
        
        // Check if this is a silent notification (background fetch)
        if payload.isContentAvailable || payload.category == Self.silentSyncCategory {
            logger.debug("Processing silent notification")
            handleSilentNotification(payload: payload, completionHandler: completionHandler)
            return
        }
        
        // Handle regular notification
        onRemoteNotificationReceived?(payload)
        completionHandler(.newData)
    }
    
    /// Determine if a notification should be shown in foreground based on its category.
    /// - Returns: Presentation options for the notification, or empty set to suppress.
    func foregroundPresentationOptions(for payload: RemoteNotificationPayload) -> UNNotificationPresentationOptions {
        switch payload.category {
        case Self.silentSyncCategory:
            // Never show silent sync notifications
            return []
        case Self.agentMessageCategory:
            // Show agent messages as banners with sound
            return [.banner, .sound]
        case Self.cronAlertCategory:
            // Show cron alerts as banners with sound and badge
            return [.banner, .sound, .badge]
        default:
            // Default: show as banner with sound
            return [.banner, .sound]
        }
    }
    
    /// Parse the notification payload from userInfo.
    /// - Parameter userInfo: The raw notification payload dictionary.
    /// - Returns: A parsed RemoteNotificationPayload struct.
    func parseNotificationPayload(_ userInfo: [AnyHashable: Any]) -> RemoteNotificationPayload {
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
            logger.info("Silent notification for session: \(sessionKey, privacy: .public)")
            
            // Notify observers about the background sync request
            NotificationCenter.default.post(
                name: .apnsBackgroundSyncRequested,
                object: nil,
                userInfo: ["sessionKey": sessionKey]
            )
        }
        
        completionHandler(.newData)
    }
    
    /// Handle notification tap - extracts deep link info and posts notification.
    /// - Parameter payload: The parsed notification payload
    func handleNotificationTap(_ payload: RemoteNotificationPayload) {
        logger.info("Notification tapped: category=\(payload.category ?? "none", privacy: .public)")
        
        var userInfo: [String: Any] = [:]
        
        if let sessionKey = payload.sessionKey {
            userInfo["sessionKey"] = sessionKey
        }
        
        if let messageId = payload.messageId {
            userInfo["messageId"] = messageId
        }
        
        if let jobId = payload.jobId {
            userInfo["jobId"] = jobId
        }
        
        NotificationCenter.default.post(
            name: .apnsNotificationTapped,
            object: nil,
            userInfo: userInfo
        )
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
        Task { @MainActor in
            // Check if onboarding has been completed
            let onboardingCompleted = OnboardingCoordinator.shared.hasCompletedOnboarding
            
            if onboardingCompleted {
                // Only request registration if notification permission was already granted
                // This handles returning users who already completed onboarding
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                if settings.authorizationStatus == .authorized ||
                   settings.authorizationStatus == .provisional {
                    await requestRegistration()
                }
            }
            // For new users, onboarding will handle the permission request
            
            // Set up connection state listener to re-register token when gateway connects
            setupConnectionStateListener()
        }
    }
    
    /// Set up a listener on gateway connection state to register token when connected.
    private func setupConnectionStateListener() {
        // Use Combine to observe connection status changes
        let manager = GatewayDualConnectionManager.shared
        
        // Re-register token whenever gateway becomes connected
        manager.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                
                // Check if we just became connected
                if status.isConnected || status.isPartiallyConnected {
                    // Only re-register if we have a token but haven't registered with gateway yet
                    if self.deviceToken != nil && !self.isRegisteredWithGateway {
                        Task {
                            await self.registerTokenWithGateway()
                        }
                    }
                } else {
                    // Gateway disconnected, mark as not registered
                    self.isRegisteredWithGateway = false
                }
            }
            .store(in: &connectionCancellables)
    }
    
    /// Cancellables for connection state observation
    private static var _connectionCancellables: Set<AnyCancellable> = []
    private var connectionCancellables: Set<AnyCancellable> {
        get { Self._connectionCancellables }
        set { Self._connectionCancellables = newValue }
    }
}
