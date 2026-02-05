import Foundation

/// Initializes and coordinates all Clawdy services on app launch.
/// Provides centralized service management and lifecycle handling.
final class ServiceInitializer {
    
    /// Initialize all services.
    /// Called from ClawdyApp.init()
    func initializeServices() {
        print("[ServiceInitializer] Initializing services...")
        
        // Touch singletons to trigger lazy initialization
        // These services set up their internal state on first access
        
        // Core services (already initialized elsewhere)
        _ = NotificationManager.shared
        
        // Capability services
        _ = CalendarService.shared
        _ = ContactsService.shared
        _ = PhoneService.shared
        _ = EmailService.shared
        _ = LocationCapabilityService.shared
        
        // Infrastructure services
        _ = OfflineQueueService.shared
        
        // Set up notification observers for APNs events
        setupAPNsObservers()
        
        // Set up gateway connection observer
        setupGatewayConnectionObserver()
        
        print("[ServiceInitializer] Services initialized")
    }
    
    /// Set up observer for gateway connection.
    private func setupGatewayConnectionObserver() {
        // Monitor gateway connection status
        NotificationCenter.default.addObserver(
            forName: .gatewayDidConnect,
            object: nil,
            queue: .main
        ) { _ in
            print("[ServiceInitializer] Gateway connected")
        }
    }
    
    /// Set up observers for APNs-related notifications.
    private func setupAPNsObservers() {
        // Observer for background sync requests from silent push
        NotificationCenter.default.addObserver(
            forName: .apnsBackgroundSyncRequested,
            object: nil,
            queue: .main
        ) { notification in
            guard let sessionKey = notification.userInfo?["sessionKey"] as? String else { return }
            print("[ServiceInitializer] Background sync requested for session: \(sessionKey)")
            
            // Trigger a background sync if gateway is connected
            Task { @MainActor in
                if GatewayDualConnectionManager.shared.isConnected {
                    // The connection manager will handle the sync
                    print("[ServiceInitializer] Gateway connected, sync will happen automatically")
                } else {
                    print("[ServiceInitializer] Gateway not connected, queueing sync request")
                }
            }
        }
        
        // Observer for notification taps
        NotificationCenter.default.addObserver(
            forName: .apnsNotificationTapped,
            object: nil,
            queue: .main
        ) { notification in
            guard let sessionKey = notification.userInfo?["sessionKey"] as? String else { return }
            print("[ServiceInitializer] Notification tapped for session: \(sessionKey)")
            
            // Post notification for UI to navigate to the session
            // The ContentView or appropriate view will observe this
            NotificationCenter.default.post(
                name: .navigateToSession,
                object: nil,
                userInfo: ["sessionKey": sessionKey]
            )
        }
        
        // Observer for chat push reply
        NotificationCenter.default.addObserver(
            forName: .chatPushReplyReceived,
            object: nil,
            queue: .main
        ) { notification in
            guard let replyText = notification.userInfo?["text"] as? String else { return }
            print("[ServiceInitializer] Chat push reply received: \(replyText)")
            
            // Send the reply via chat
            Task { @MainActor in
                do {
                    _ = try await GatewayDualConnectionManager.shared.sendMessage(replyText, images: nil)
                    print("[ServiceInitializer] Reply sent successfully")
                } catch {
                    print("[ServiceInitializer] Failed to send reply: \(error)")
                    // Queue for offline send
                    OfflineQueueService.shared.enqueue(method: "chat.send", params: ["text": replyText])
                }
            }
        }
    }
}

// MARK: - Additional Notification Names

extension Notification.Name {
    /// Posted to request navigation to a specific session.
    /// userInfo contains "sessionKey" key.
    static let navigateToSession = Notification.Name("navigateToSession")
    
    /// Posted when gateway connection is established.
    static let gatewayDidConnect = Notification.Name("gatewayDidConnect")
}
