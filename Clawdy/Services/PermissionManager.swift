import Foundation
import SwiftUI
import AVFoundation
import EventKit
import Contacts
import CoreLocation
import Photos
import UserNotifications
import UIKit

/// Centralized permission manager providing just-in-time (JIT) permission flows
/// with pre-prompt explanations and Settings deep-link on denial.
@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    // MARK: - Published Properties
    
    /// Current permission statuses
    @Published private(set) var statuses: PermissionStatuses = PermissionStatuses()
    
    /// Permission being requested (for JIT UI)
    @Published var pendingPermission: PermissionType?
    
    /// Whether to show the pre-prompt explanation
    @Published var showExplanation: Bool = false
    
    /// Whether to show the denied alert
    @Published var showDeniedAlert: Bool = false
    
    /// The permission that was denied (for alert)
    @Published var deniedPermission: PermissionType?
    
    // MARK: - Types
    
    /// All permission types managed by the app
    enum PermissionType: String, CaseIterable, Identifiable {
        case notifications = "Notifications"
        case microphone = "Microphone"
        case calendar = "Calendar"
        case contacts = "Contacts"
        case location = "Location"
        case camera = "Camera"
        case photos = "Photos"
        
        var id: String { rawValue }
        
        var systemImageName: String {
            switch self {
            case .notifications: return "bell.badge.fill"
            case .microphone: return "mic.fill"
            case .calendar: return "calendar"
            case .contacts: return "person.crop.circle.fill"
            case .location: return "location.fill"
            case .camera: return "camera.fill"
            case .photos: return "photo.fill"
            }
        }
        
        var explanation: String {
            switch self {
            case .notifications:
                return "Clawdy uses notifications to alert you about incoming messages and scheduled tasks."
            case .microphone:
                return "Microphone access enables voice commands and hands-free interaction with your assistant."
            case .calendar:
                return "Calendar access lets Clawdy create, view, and manage your events and reminders."
            case .contacts:
                return "Contacts access allows Clawdy to help you find and communicate with people in your address book."
            case .location:
                return "Location access enables location-based features and contextual awareness."
            case .camera:
                return "Camera access lets you capture photos and videos to share with your assistant."
            case .photos:
                return "Photo library access allows you to share existing photos and save images from conversations."
            }
        }
        
        var deniedMessage: String {
            switch self {
            case .notifications:
                return "Notifications are disabled. Enable them in Settings to receive alerts from Clawdy."
            case .microphone:
                return "Microphone access is disabled. Enable it in Settings to use voice commands."
            case .calendar:
                return "Calendar access is disabled. Enable it in Settings to manage your events."
            case .contacts:
                return "Contacts access is disabled. Enable it in Settings to access your address book."
            case .location:
                return "Location access is disabled. Enable it in Settings for location-based features."
            case .camera:
                return "Camera access is disabled. Enable it in Settings to take photos."
            case .photos:
                return "Photo library access is disabled. Enable it in Settings to share photos."
            }
        }
    }
    
    /// Status for a single permission
    enum PermissionStatus: String {
        case notDetermined = "Not Set"
        case authorized = "Enabled"
        case denied = "Disabled"
        case restricted = "Restricted"
        case limited = "Limited"
        
        var color: Color {
            switch self {
            case .authorized: return .green
            case .limited: return .orange
            case .notDetermined: return .secondary
            case .denied, .restricted: return .red
            }
        }
        
        var systemImageName: String {
            switch self {
            case .authorized: return "checkmark.circle.fill"
            case .limited: return "minus.circle.fill"
            case .notDetermined: return "questionmark.circle"
            case .denied, .restricted: return "xmark.circle.fill"
            }
        }
    }
    
    /// Container for all permission statuses
    struct PermissionStatuses {
        var notifications: PermissionStatus = .notDetermined
        var microphone: PermissionStatus = .notDetermined
        var calendar: PermissionStatus = .notDetermined
        var contacts: PermissionStatus = .notDetermined
        var location: PermissionStatus = .notDetermined
        var camera: PermissionStatus = .notDetermined
        var photos: PermissionStatus = .notDetermined
        
        func status(for type: PermissionType) -> PermissionStatus {
            switch type {
            case .notifications: return notifications
            case .microphone: return microphone
            case .calendar: return calendar
            case .contacts: return contacts
            case .location: return location
            case .camera: return camera
            case .photos: return photos
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        refreshAllStatuses()
    }
    
    // MARK: - Status Refresh
    
    /// Refresh all permission statuses
    func refreshAllStatuses() {
        Task {
            await refreshNotificationStatus()
            refreshMicrophoneStatus()
            refreshCalendarStatus()
            refreshContactsStatus()
            refreshLocationStatus()
            refreshCameraStatus()
            refreshPhotosStatus()
        }
    }
    
    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            switch settings.authorizationStatus {
            case .notDetermined:
                statuses.notifications = .notDetermined
            case .authorized, .provisional, .ephemeral:
                statuses.notifications = .authorized
            case .denied:
                statuses.notifications = .denied
            @unknown default:
                statuses.notifications = .notDetermined
            }
        }
    }
    
    private func refreshMicrophoneStatus() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .undetermined:
            statuses.microphone = .notDetermined
        case .granted:
            statuses.microphone = .authorized
        case .denied:
            statuses.microphone = .denied
        @unknown default:
            statuses.microphone = .notDetermined
        }
    }
    
    private func refreshCalendarStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined:
            statuses.calendar = .notDetermined
        case .fullAccess, .authorized:
            statuses.calendar = .authorized
        case .writeOnly:
            statuses.calendar = .limited
        case .denied:
            statuses.calendar = .denied
        case .restricted:
            statuses.calendar = .restricted
        @unknown default:
            statuses.calendar = .notDetermined
        }
    }
    
    private func refreshContactsStatus() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .notDetermined:
            statuses.contacts = .notDetermined
        case .authorized:
            statuses.contacts = .authorized
        case .limited:
            statuses.contacts = .limited
        case .denied:
            statuses.contacts = .denied
        case .restricted:
            statuses.contacts = .restricted
        @unknown default:
            statuses.contacts = .notDetermined
        }
    }
    
    private func refreshLocationStatus() {
        let status = CLLocationManager().authorizationStatus
        switch status {
        case .notDetermined:
            statuses.location = .notDetermined
        case .authorizedAlways, .authorizedWhenInUse:
            statuses.location = .authorized
        case .denied:
            statuses.location = .denied
        case .restricted:
            statuses.location = .restricted
        @unknown default:
            statuses.location = .notDetermined
        }
    }
    
    private func refreshCameraStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            statuses.camera = .notDetermined
        case .authorized:
            statuses.camera = .authorized
        case .denied:
            statuses.camera = .denied
        case .restricted:
            statuses.camera = .restricted
        @unknown default:
            statuses.camera = .notDetermined
        }
    }
    
    private func refreshPhotosStatus() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .notDetermined:
            statuses.photos = .notDetermined
        case .authorized:
            statuses.photos = .authorized
        case .limited:
            statuses.photos = .limited
        case .denied:
            statuses.photos = .denied
        case .restricted:
            statuses.photos = .restricted
        @unknown default:
            statuses.photos = .notDetermined
        }
    }
    
    // MARK: - JIT Permission Flow
    
    /// Request permission with JIT explanation flow.
    /// Shows explanation before system prompt, and offers Settings link on denial.
    /// - Parameter type: The permission to request
    /// - Returns: Whether permission was granted
    @discardableResult
    func requestPermission(_ type: PermissionType) async -> Bool {
        let currentStatus = statuses.status(for: type)
        
        // If already denied/restricted, show Settings alert directly
        if currentStatus == .denied || currentStatus == .restricted {
            await MainActor.run {
                deniedPermission = type
                showDeniedAlert = true
            }
            return false
        }
        
        // If not determined, show explanation first
        if currentStatus == .notDetermined {
            // Show explanation and wait for user action
            await MainActor.run {
                pendingPermission = type
                showExplanation = true
            }
            
            // Wait for explanation to be dismissed (user tapped continue)
            // This is handled by the UI calling confirmPermissionRequest()
            return false // The actual request happens in confirmPermissionRequest()
        }
        
        // Already authorized
        return currentStatus == .authorized || currentStatus == .limited
    }
    
    /// Continue with permission request after user sees explanation
    func confirmPermissionRequest() async -> Bool {
        guard let type = pendingPermission else { return false }
        
        await MainActor.run {
            showExplanation = false
        }
        
        let granted = await performPermissionRequest(type)
        
        await MainActor.run {
            pendingPermission = nil
            
            if !granted {
                deniedPermission = type
                showDeniedAlert = true
            }
        }
        
        return granted
    }
    
    /// Cancel the permission request
    func cancelPermissionRequest() {
        showExplanation = false
        pendingPermission = nil
    }
    
    /// Dismiss the denied alert
    func dismissDeniedAlert() {
        showDeniedAlert = false
        deniedPermission = nil
    }
    
    /// Open app settings
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Direct Permission Requests
    
    /// Perform the actual permission request
    private func performPermissionRequest(_ type: PermissionType) async -> Bool {
        switch type {
        case .notifications:
            let granted = await NotificationManager.shared.requestAuthorization()
            await refreshNotificationStatus()
            return granted
            
        case .microphone:
            let granted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            await MainActor.run { refreshMicrophoneStatus() }
            return granted
            
        case .calendar:
            let granted = await CalendarService.shared.requestAuthorization()
            await MainActor.run { refreshCalendarStatus() }
            return granted
            
        case .contacts:
            let granted = await ContactsService.shared.requestAuthorization()
            await MainActor.run { refreshContactsStatus() }
            return granted
            
        case .location:
            // Location requires special handling via delegate
            ContextDetectionService.shared.requestLocationAuthorization()
            // Wait a moment for the system dialog
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run { refreshLocationStatus() }
            return statuses.location == .authorized
            
        case .camera:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run { refreshCameraStatus() }
            return granted
            
        case .photos:
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            await MainActor.run { refreshPhotosStatus() }
            return status == .authorized || status == .limited
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Request calendar permission with JIT flow
    func requestCalendarPermission() async -> Bool {
        let status = statuses.calendar
        if status == .denied || status == .restricted {
            deniedPermission = .calendar
            showDeniedAlert = true
            return false
        }
        if status == .notDetermined {
            pendingPermission = .calendar
            showExplanation = true
            return false
        }
        return status == .authorized || status == .limited
    }
    
    /// Request contacts permission with JIT flow
    func requestContactsPermission() async -> Bool {
        let status = statuses.contacts
        if status == .denied || status == .restricted {
            deniedPermission = .contacts
            showDeniedAlert = true
            return false
        }
        if status == .notDetermined {
            pendingPermission = .contacts
            showExplanation = true
            return false
        }
        return status == .authorized || status == .limited
    }
    
    /// Request location permission with JIT flow
    func requestLocationPermission() async -> Bool {
        let status = statuses.location
        if status == .denied || status == .restricted {
            deniedPermission = .location
            showDeniedAlert = true
            return false
        }
        if status == .notDetermined {
            pendingPermission = .location
            showExplanation = true
            return false
        }
        return status == .authorized
    }
    
    /// Request camera permission with JIT flow
    func requestCameraPermission() async -> Bool {
        let status = statuses.camera
        if status == .denied || status == .restricted {
            deniedPermission = .camera
            showDeniedAlert = true
            return false
        }
        if status == .notDetermined {
            pendingPermission = .camera
            showExplanation = true
            return false
        }
        return status == .authorized
    }
    
    /// Request photos permission with JIT flow
    func requestPhotosPermission() async -> Bool {
        let status = statuses.photos
        if status == .denied || status == .restricted {
            deniedPermission = .photos
            showDeniedAlert = true
            return false
        }
        if status == .notDetermined {
            pendingPermission = .photos
            showExplanation = true
            return false
        }
        return status == .authorized || status == .limited
    }
}
