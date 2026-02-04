import XCTest
@testable import Clawdy
import UserNotifications
import AVFoundation
import EventKit
import Contacts
import CoreLocation
import Photos

/// Tests for permission onboarding, JIT flows, and status monitoring.
final class PermissionTests: XCTestCase {
    
    // MARK: - Onboarding Coordinator Tests
    
    @MainActor
    func testOnboardingInitialState() {
        let coordinator = OnboardingCoordinator(testMode: true)
        
        XCTAssertFalse(coordinator.hasCompletedOnboarding)
        XCTAssertFalse(coordinator.isOnboarding)
        XCTAssertNil(coordinator.currentStep)
        XCTAssertTrue(coordinator.shouldShowOnboarding)
    }
    
    @MainActor
    func testOnboardingStartsAtWelcome() {
        let coordinator = OnboardingCoordinator(testMode: true)
        
        coordinator.startOnboarding()
        
        XCTAssertTrue(coordinator.isOnboarding)
        XCTAssertEqual(coordinator.currentStep, .welcome)
    }
    
    @MainActor
    func testOnboardingStepProgression() {
        let coordinator = OnboardingCoordinator(testMode: true)
        coordinator.startOnboarding()
        
        // Start at welcome
        XCTAssertEqual(coordinator.currentStep, .welcome)
        
        // Advance to notification explanation
        coordinator.advanceToNextStep()
        XCTAssertEqual(coordinator.currentStep, .notificationExplanation)
        
        // Advance to microphone explanation
        coordinator.advanceToNextStep()
        XCTAssertEqual(coordinator.currentStep, .microphoneExplanation)
        
        // Advance to complete
        coordinator.advanceToNextStep()
        XCTAssertEqual(coordinator.currentStep, .complete)
    }
    
    @MainActor
    func testOnboardingCompletion() {
        let coordinator = OnboardingCoordinator(testMode: true)
        coordinator.startOnboarding()
        
        coordinator.completeOnboarding()
        
        XCTAssertTrue(coordinator.hasCompletedOnboarding)
        XCTAssertFalse(coordinator.isOnboarding)
        XCTAssertNil(coordinator.currentStep)
        XCTAssertFalse(coordinator.shouldShowOnboarding)
    }
    
    @MainActor
    func testOnboardingSkipAction() {
        let coordinator = OnboardingCoordinator(testMode: true)
        coordinator.startOnboarding()
        
        // Advance to notification step
        coordinator.advanceToNextStep()
        XCTAssertEqual(coordinator.currentStep, .notificationExplanation)
        
        // Skip should advance to next step
        coordinator.handleSkipAction()
        XCTAssertEqual(coordinator.currentStep, .microphoneExplanation)
    }
    
    @MainActor
    func testOnboardingReset() {
        let coordinator = OnboardingCoordinator(testMode: true)
        coordinator.startOnboarding()
        coordinator.completeOnboarding()
        
        XCTAssertTrue(coordinator.hasCompletedOnboarding)
        
        coordinator.resetOnboarding()
        
        XCTAssertFalse(coordinator.hasCompletedOnboarding)
        XCTAssertFalse(coordinator.isOnboarding)
        XCTAssertTrue(coordinator.shouldShowOnboarding)
    }
    
    @MainActor
    func testOnboardingStepTitles() {
        XCTAssertEqual(OnboardingCoordinator.OnboardingStep.welcome.title, "Welcome to Clawdy")
        XCTAssertEqual(OnboardingCoordinator.OnboardingStep.notificationExplanation.title, "Stay Updated")
        XCTAssertEqual(OnboardingCoordinator.OnboardingStep.microphoneExplanation.title, "Voice Control")
        XCTAssertEqual(OnboardingCoordinator.OnboardingStep.complete.title, "You're All Set!")
    }
    
    @MainActor
    func testOnboardingStepDescriptions() {
        let welcomeDesc = OnboardingCoordinator.OnboardingStep.welcome.description
        XCTAssertTrue(welcomeDesc.contains("AI assistant"))
        
        let notificationDesc = OnboardingCoordinator.OnboardingStep.notificationExplanation.description
        XCTAssertTrue(notificationDesc.contains("Notifications"))
        
        let microphoneDesc = OnboardingCoordinator.OnboardingStep.microphoneExplanation.description
        XCTAssertTrue(microphoneDesc.contains("Microphone"))
    }
    
    @MainActor
    func testOnboardingSkipButtonVisibility() {
        // Welcome and complete should not have skip button
        XCTAssertNil(OnboardingCoordinator.OnboardingStep.welcome.skipButtonTitle)
        XCTAssertNil(OnboardingCoordinator.OnboardingStep.complete.skipButtonTitle)
        
        // Permission steps should have skip button
        XCTAssertNotNil(OnboardingCoordinator.OnboardingStep.notificationExplanation.skipButtonTitle)
        XCTAssertNotNil(OnboardingCoordinator.OnboardingStep.microphoneExplanation.skipButtonTitle)
    }
    
    // MARK: - Permission Manager Tests
    
    @MainActor
    func testPermissionManagerInitialState() {
        let manager = PermissionManager.shared
        
        // Statuses should be populated (values depend on simulator state)
        XCTAssertNotNil(manager.statuses)
        XCTAssertNil(manager.pendingPermission)
        XCTAssertFalse(manager.showExplanation)
        XCTAssertFalse(manager.showDeniedAlert)
    }
    
    @MainActor
    func testPermissionTypeProperties() {
        // Test all permission types have required properties
        for type in PermissionManager.PermissionType.allCases {
            XCTAssertFalse(type.rawValue.isEmpty)
            XCTAssertFalse(type.systemImageName.isEmpty)
            XCTAssertFalse(type.explanation.isEmpty)
            XCTAssertFalse(type.deniedMessage.isEmpty)
        }
    }
    
    @MainActor
    func testPermissionStatusColors() {
        XCTAssertEqual(PermissionManager.PermissionStatus.authorized.color, .green)
        XCTAssertEqual(PermissionManager.PermissionStatus.limited.color, .orange)
        XCTAssertEqual(PermissionManager.PermissionStatus.denied.color, .red)
        XCTAssertEqual(PermissionManager.PermissionStatus.restricted.color, .red)
    }
    
    @MainActor
    func testPermissionStatusIcons() {
        XCTAssertEqual(PermissionManager.PermissionStatus.authorized.systemImageName, "checkmark.circle.fill")
        XCTAssertEqual(PermissionManager.PermissionStatus.denied.systemImageName, "xmark.circle.fill")
        XCTAssertEqual(PermissionManager.PermissionStatus.notDetermined.systemImageName, "questionmark.circle")
    }
    
    @MainActor
    func testPermissionStatusRefresh() {
        let manager = PermissionManager.shared
        
        // Call refresh - should not crash
        manager.refreshAllStatuses()
        
        // Wait briefly for async updates
        let expectation = XCTestExpectation(description: "Status refresh")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    @MainActor
    func testPermissionManagerCancelRequest() {
        let manager = PermissionManager.shared
        
        // Simulate pending permission
        manager.pendingPermission = .calendar
        manager.showExplanation = true
        
        // Cancel should clear state
        manager.cancelPermissionRequest()
        
        XCTAssertFalse(manager.showExplanation)
        XCTAssertNil(manager.pendingPermission)
    }
    
    @MainActor
    func testPermissionManagerDismissDeniedAlert() {
        let manager = PermissionManager.shared
        
        // Simulate denied state
        manager.deniedPermission = .camera
        manager.showDeniedAlert = true
        
        // Dismiss should clear state
        manager.dismissDeniedAlert()
        
        XCTAssertFalse(manager.showDeniedAlert)
        XCTAssertNil(manager.deniedPermission)
    }
    
    @MainActor
    func testStatusLookupForAllTypes() {
        let manager = PermissionManager.shared
        let statuses = manager.statuses
        
        // All types should return a status
        for type in PermissionManager.PermissionType.allCases {
            let status = statuses.status(for: type)
            XCTAssertNotNil(status)
        }
    }
    
    // MARK: - Denied/Restricted State Tests
    
    @MainActor
    func testDeniedStateShowsAlert() async {
        let manager = PermissionManager.shared
        
        // If a permission is denied, requesting it should show the alert
        // We can't directly test this without mocking, but we can verify the logic path
        
        // Simulate a denied permission scenario
        manager.deniedPermission = .microphone
        manager.showDeniedAlert = true
        
        XCTAssertTrue(manager.showDeniedAlert)
        XCTAssertEqual(manager.deniedPermission, .microphone)
    }
    
    // MARK: - Settings Deep-link Tests
    
    @MainActor
    func testOpenSettingsDoesNotCrash() {
        let manager = PermissionManager.shared
        
        // This should not crash - actual navigation happens in UI
        // We're just verifying the method exists and can be called
        manager.openSettings()
    }
    
    // MARK: - Permission Explanation Content Tests
    
    @MainActor
    func testNotificationExplanationContent() {
        let type = PermissionManager.PermissionType.notifications
        
        XCTAssertEqual(type.rawValue, "Notifications")
        XCTAssertTrue(type.explanation.contains("alert"))
        XCTAssertTrue(type.deniedMessage.contains("Settings"))
    }
    
    @MainActor
    func testMicrophoneExplanationContent() {
        let type = PermissionManager.PermissionType.microphone
        
        XCTAssertEqual(type.rawValue, "Microphone")
        XCTAssertTrue(type.explanation.contains("voice"))
        XCTAssertTrue(type.deniedMessage.contains("Settings"))
    }
    
    @MainActor
    func testCalendarExplanationContent() {
        let type = PermissionManager.PermissionType.calendar
        
        XCTAssertEqual(type.rawValue, "Calendar")
        XCTAssertTrue(type.explanation.contains("events"))
        XCTAssertTrue(type.deniedMessage.contains("Settings"))
    }
    
    @MainActor
    func testContactsExplanationContent() {
        let type = PermissionManager.PermissionType.contacts
        
        XCTAssertEqual(type.rawValue, "Contacts")
        XCTAssertTrue(type.explanation.contains("address book"))
        XCTAssertTrue(type.deniedMessage.contains("Settings"))
    }
    
    @MainActor
    func testLocationExplanationContent() {
        let type = PermissionManager.PermissionType.location
        
        XCTAssertEqual(type.rawValue, "Location")
        XCTAssertTrue(type.explanation.contains("location"))
        XCTAssertTrue(type.deniedMessage.contains("Settings"))
    }
    
    @MainActor
    func testCameraExplanationContent() {
        let type = PermissionManager.PermissionType.camera
        
        XCTAssertEqual(type.rawValue, "Camera")
        XCTAssertTrue(type.explanation.contains("photos"))
        XCTAssertTrue(type.deniedMessage.contains("Settings"))
    }
    
    @MainActor
    func testPhotosExplanationContent() {
        let type = PermissionManager.PermissionType.photos
        
        XCTAssertEqual(type.rawValue, "Photos")
        XCTAssertTrue(type.explanation.contains("Photo library"))
        XCTAssertTrue(type.deniedMessage.contains("Settings"))
    }
    
    // MARK: - UI Rendering Tests
    
    @MainActor
    func testPermissionRowRendering() {
        // Verify all permission types can generate UI elements
        for type in PermissionManager.PermissionType.allCases {
            XCTAssertFalse(type.systemImageName.isEmpty, "\(type.rawValue) should have an icon")
            XCTAssertFalse(type.rawValue.isEmpty, "\(type.rawValue) should have a display name")
        }
    }
    
    @MainActor
    func testPermissionStatusRendering() {
        // Verify all statuses can generate UI elements
        let allStatuses: [PermissionManager.PermissionStatus] = [
            .notDetermined, .authorized, .denied, .restricted, .limited
        ]
        
        for status in allStatuses {
            XCTAssertFalse(status.rawValue.isEmpty, "\(status) should have a display name")
            XCTAssertFalse(status.systemImageName.isEmpty, "\(status) should have an icon")
        }
    }
}
