import Foundation
import UserNotifications
import UIKit

/// Manages local notifications for Clawdy.
/// Handles permission requests, scheduling notifications, and notification actions.
@MainActor
class NotificationManager: NSObject {
    static let shared = NotificationManager()
    
    // MARK: - Notification Categories & Actions
    
    /// Category identifier for chat push notifications (agent-initiated messages)
    nonisolated static let chatPushCategory = "CHAT_PUSH"
    
    /// Action identifier for replying to a chat push notification
    nonisolated static let replyAction = "REPLY_ACTION"
    
    // MARK: - Properties
    
    /// Current notification authorization status
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    /// Whether notifications are authorized
    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        // Note: We do NOT set ourselves as the notification delegate here.
        // AppDelegate is the single delegate for UNUserNotificationCenter to ensure
        // APNs callbacks are properly invoked for remote notifications.
        // Local notification logic is handled via AppDelegate forwarding.
        
        // Check current authorization status on init
        Task {
            await refreshAuthorizationStatus()
        }
    }
    
    // MARK: - Authorization
    
    /// Request notification permissions.
    /// - Returns: Whether authorization was granted
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            // Request alert, sound, and badge permissions
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            
            // Refresh status after request
            await refreshAuthorizationStatus()
            
            if granted {
                print("[NotificationManager] Notification permission granted")
                
                // Set up notification categories with actions
                setupNotificationCategories()
            } else {
                print("[NotificationManager] Notification permission denied")
            }
            
            return granted
        } catch {
            print("[NotificationManager] Failed to request authorization: \(error)")
            return false
        }
    }
    
    /// Refresh the current authorization status from the system.
    func refreshAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }
    
    // MARK: - Notification Categories
    
    /// Set up notification categories with actions (e.g., reply action for chat messages).
    private func setupNotificationCategories() {
        // Define the reply action - allows user to reply directly from notification
        let replyAction = UNTextInputNotificationAction(
            identifier: Self.replyAction,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Your reply..."
        )
        
        // Define the chat push category with the reply action
        let chatPushCategory = UNNotificationCategory(
            identifier: Self.chatPushCategory,
            actions: [replyAction],
            intentIdentifiers: [],
            options: [] // Note: .allowAnnouncement was deprecated in iOS 15
        )
        
        // Register the categories
        notificationCenter.setNotificationCategories([chatPushCategory])
        print("[NotificationManager] Notification categories configured")
    }
    
    // MARK: - Schedule Notifications
    
    /// Schedule a notification for a chat push message from the agent.
    /// - Parameters:
    ///   - text: The message text to display
    ///   - messageId: Unique identifier for the message (used as notification ID)
    func scheduleChatPushNotification(text: String, messageId: String) async {
        // Check authorization - request if not determined
        if authorizationStatus == .notDetermined {
            await requestAuthorization()
        }
        
        guard isAuthorized else {
            print("[NotificationManager] Cannot schedule notification - not authorized")
            return
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Clawdbot"
        content.body = text
        content.sound = .default
        content.categoryIdentifier = Self.chatPushCategory
        
        // Store message ID in userInfo for handling taps
        content.userInfo = ["messageId": messageId]
        
        // Create a trigger that fires immediately
        // We use a small delay to ensure the notification is delivered
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        
        // Create the request
        let request = UNNotificationRequest(
            identifier: messageId,
            content: content,
            trigger: trigger
        )
        
        do {
            try await notificationCenter.add(request)
            print("[NotificationManager] Scheduled chat push notification: \(messageId)")
        } catch {
            print("[NotificationManager] Failed to schedule notification: \(error)")
        }
    }
    
    /// Result of scheduling a notification
    enum ScheduleResult {
        case success
        case permissionDenied
        case failed(Error)
    }
    
    /// Schedule a system notification (from system.notify capability).
    /// - Parameters:
    ///   - title: Notification title
    ///   - body: Notification body text
    ///   - sound: Whether to play a sound
    ///   - priority: Notification priority (passive, active, timeSensitive)
    /// - Returns: The result of scheduling (success, permission denied, or error)
    @discardableResult
    func scheduleSystemNotification(
        title: String,
        body: String,
        sound: Bool = true,
        priority: String = "active"
    ) async -> ScheduleResult {
        // Check authorization - request if not determined
        if authorizationStatus == .notDetermined {
            await requestAuthorization()
        }
        
        guard isAuthorized else {
            print("[NotificationManager] Cannot schedule notification - not authorized")
            return .permissionDenied
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        
        if sound {
            content.sound = .default
        }
        
        // Set interruption level based on priority
        switch priority.lowercased() {
        case "passive":
            content.interruptionLevel = .passive
        case "timesensitive":
            content.interruptionLevel = .timeSensitive
        case "active":
            fallthrough
        default:
            content.interruptionLevel = .active
        }
        
        // Create trigger (immediate)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        
        // Create request with unique ID
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        do {
            try await notificationCenter.add(request)
            print("[NotificationManager] Scheduled system notification")
            return .success
        } catch {
            print("[NotificationManager] Failed to schedule notification: \(error)")
            return .failed(error)
        }
    }
    
    /// Cancel a pending notification by ID.
    func cancelNotification(id: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [id])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [id])
    }
    
    /// Cancel all pending notifications.
    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
    }
}

// MARK: - Local Notification Handling (called from AppDelegate)

extension NotificationManager {
    /// Check if a local notification should be shown in foreground.
    /// Called by AppDelegate when it receives a local notification.
    /// - Returns: Presentation options for the notification.
    nonisolated func foregroundPresentationOptions(for notification: UNNotification) -> UNNotificationPresentationOptions {
        // Don't show chat push notifications in foreground (message is already in chat)
        if notification.request.content.categoryIdentifier == Self.chatPushCategory {
            return []
        } else {
            // Show other notifications (system.notify) even in foreground
            return [.banner, .sound, .badge]
        }
    }
    
    /// Handle local notification response (tap or action).
    /// Called by AppDelegate when user interacts with a local notification.
    nonisolated func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle reply action
        if response.actionIdentifier == Self.replyAction,
           let textResponse = response as? UNTextInputNotificationResponse {
            let replyText = textResponse.userText
            print("[NotificationManager] User replied: \(replyText)")
            
            // Post notification for ViewModel to handle
            NotificationCenter.default.post(
                name: .chatPushReplyReceived,
                object: nil,
                userInfo: ["text": replyText]
            )
        }
        
        // Handle tap on notification (default action)
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            if let messageId = userInfo["messageId"] as? String {
                print("[NotificationManager] User tapped notification for message: \(messageId)")
                // App will open and show the chat - no additional action needed
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when user replies to a chat push notification.
    /// userInfo contains "text" key with the reply text.
    static let chatPushReplyReceived = Notification.Name("chatPushReplyReceived")
}
