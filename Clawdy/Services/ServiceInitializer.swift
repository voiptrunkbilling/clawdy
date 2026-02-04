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
        _ = ContextDetectionService.shared
        
        // Set up context detection gateway integration
        setupContextDetectionCallbacks()
        
        // Set up notification observers for APNs events
        setupAPNsObservers()
        
        // Set up gateway connection observer for geofence sync
        setupGatewayConnectionObserver()
        
        print("[ServiceInitializer] Services initialized")
    }
    
    /// Set up ContextDetectionService callbacks for gateway integration.
    private func setupContextDetectionCallbacks() {
        Task { @MainActor in
            let contextService = ContextDetectionService.shared
            
            // Wire up context mode change callback to send updates to gateway
            contextService.onContextUpdate = { [weak contextService] mode in
                guard let _ = contextService else { return }
                print("[ServiceInitializer] Context mode changed to: \(mode.rawValue)")
                // The sendContextUpdateToGateway() is already called internally by ContextDetectionService
                // This callback is for any additional ViewModel-level handling if needed
            }
        }
    }
    
    /// Set up observer for gateway connection to sync geofence zones.
    private func setupGatewayConnectionObserver() {
        // Monitor gateway connection status and fetch geofence zones when connected
        NotificationCenter.default.addObserver(
            forName: .gatewayDidConnect,
            object: nil,
            queue: .main
        ) { _ in
            print("[ServiceInitializer] Gateway connected, fetching geofence zones...")
            Task { @MainActor in
                // Fetch preferences from gateway (includes geofence zones)
                await ContextPreferencesManager.shared.fetchFromGateway()
                
                // Sync geofence zones to ContextDetectionService
                await ContextDetectionService.shared.syncGeofenceZonesFromPreferences()
            }
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
