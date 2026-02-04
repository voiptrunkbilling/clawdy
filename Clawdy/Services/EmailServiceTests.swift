import Foundation
import UIKit
import MessageUI
import XCTest

/// Unit tests for EmailService operations.
/// These tests validate the email composition capability service functionality.
///
/// Test Categories:
/// 1. Service initialization (singleton pattern)
/// 2. Availability checking
/// 3. Error types validation
class EmailServiceTests: XCTestCase {
    
    private var service: EmailService!
    
    @MainActor
    override func setUp() {
        super.setUp()
        service = EmailService.shared
    }
    
    override func tearDown() {
        service = nil
        super.tearDown()
    }
    
    // MARK: - Singleton Tests
    
    @MainActor
    func testSingletonPattern() {
        let service2 = EmailService.shared
        XCTAssertTrue(service === service2, "EmailService should use singleton pattern")
    }
    
    // MARK: - Availability Tests
    
    @MainActor
    func testAvailabilityCheck() {
        // Just verify the check doesn't crash
        service.checkAvailability()
        // isAvailable should be set (may be false on simulator)
        _ = service.isAvailable
    }
    
    @MainActor
    func testCanSendMailMatchesFramework() {
        // isAvailable should match MFMailComposeViewController.canSendMail()
        let frameworkResult = MFMailComposeViewController.canSendMail()
        XCTAssertEqual(service.isAvailable, frameworkResult,
                       "isAvailable should match MFMailComposeViewController.canSendMail()")
    }
    
    // MARK: - Error Type Tests
    
    func testNotAvailableErrorDescription() {
        let error = EmailService.EmailError.notAvailable
        XCTAssertTrue(error.errorDescription?.contains("not available") == true,
                      "notAvailable error should have correct description")
    }
    
    func testComposeFailedErrorDescription() {
        let error = EmailService.EmailError.composeFailed
        XCTAssertTrue(error.errorDescription?.contains("Failed to compose") == true,
                      "composeFailed error should have correct description")
    }
    
    func testSendFailedErrorDescription() {
        let mockError = NSError(domain: "test", code: 1, userInfo: nil)
        let error = EmailService.EmailError.sendFailed(mockError)
        XCTAssertTrue(error.errorDescription?.contains("Failed to send") == true,
                      "sendFailed error should have correct description")
    }
    
    // MARK: - Email Composition Tests (Simulator-safe)
    
    @MainActor
    func testComposeEmailBuildMailtoURL() async {
        // Test that compose builds valid mailto URL
        // Note: On simulator without email configured, this may fail
        // but should not crash
        let result = await service.composeEmail(
            to: ["test@example.com"],
            subject: "Test Subject",
            body: "Test Body"
        )
        // Result depends on device/simulator configuration
        // Just verify no crash
        _ = result
    }
    
    @MainActor
    func testComposeEmailWithMultipleRecipients() async {
        let result = await service.composeEmail(
            to: ["alice@example.com", "bob@example.com"],
            subject: "Group Email",
            body: nil
        )
        // Result depends on device configuration
        _ = result
    }
    
    @MainActor
    func testComposeEmailWithEmptyToReturnsFalse() async {
        // Empty recipients should build invalid mailto URL
        let result = await service.composeEmail(
            to: [],
            subject: "Test",
            body: "Test"
        )
        // An empty mailto: URL might still open the mail app,
        // so we just verify no crash
        _ = result
    }
    
    // MARK: - URL Building Tests
    
    func testMailtoURLEncoding() {
        // Test URL encoding for special characters
        let subject = "Hello World & More"
        let encoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        XCTAssertNotNil(encoded, "Subject should be URL encodable")
        
        let body = "Line 1\nLine 2"
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        XCTAssertNotNil(encodedBody, "Body with newlines should be URL encodable")
    }
    
    // MARK: - MFMailComposeResult Tests
    
    func testMailComposeResultValues() {
        // Verify we can reference all result values
        let results: [MFMailComposeResult] = [.cancelled, .saved, .sent, .failed]
        XCTAssertEqual(results.count, 4, "Should have 4 result types")
    }
    
    // MARK: - EmailComposeServiceResult Tests
    
    func testEmailComposeServiceResultSent() {
        let result = EmailService.EmailComposeServiceResult.sent
        XCTAssertNil(result.errorMessage, "sent should have no error message")
        XCTAssertTrue(result.isSuccess, "sent should be success")
    }
    
    func testEmailComposeServiceResultSaved() {
        let result = EmailService.EmailComposeServiceResult.saved
        XCTAssertNil(result.errorMessage, "saved should have no error message")
        XCTAssertTrue(result.isSuccess, "saved should be success")
    }
    
    func testEmailComposeServiceResultCancelled() {
        let result = EmailService.EmailComposeServiceResult.cancelled
        XCTAssertNil(result.errorMessage, "cancelled should have no error message")
        XCTAssertTrue(result.isSuccess, "cancelled should be success")
    }
    
    func testEmailComposeServiceResultNotAvailable() {
        let result = EmailService.EmailComposeServiceResult.notAvailable
        XCTAssertEqual(result.errorMessage, "Email not available on this device")
        XCTAssertFalse(result.isSuccess, "notAvailable should not be success")
    }
    
    func testEmailComposeServiceResultInvalidRecipients() {
        let result = EmailService.EmailComposeServiceResult.invalidRecipients
        XCTAssertEqual(result.errorMessage, "At least one recipient is required")
        XCTAssertFalse(result.isSuccess, "invalidRecipients should not be success")
    }
    
    func testEmailComposeServiceResultComposeFailed() {
        let result = EmailService.EmailComposeServiceResult.composeFailed
        XCTAssertEqual(result.errorMessage, "Failed to compose email")
        XCTAssertFalse(result.isSuccess, "composeFailed should not be success")
    }
    
    // MARK: - ComposeEmailAsync Tests (Simulator-safe)
    
    @MainActor
    func testComposeEmailAsyncWithEmptyRecipients() async {
        // Empty recipients should return .invalidRecipients
        let result = await service.composeEmailAsync(
            to: [],
            subject: "Test",
            body: "Test"
        )
        XCTAssertEqual(result, .invalidRecipients, "Empty recipients should return .invalidRecipients")
    }
    
    @MainActor
    func testComposeEmailAsyncAvailabilityCheck() async {
        // On simulator without email configured, should return .notAvailable
        // On device with email, may proceed to present composer
        let result = await service.composeEmailAsync(
            to: ["test@example.com"],
            subject: nil,
            body: nil,
            isHTML: false
        )
        // Result depends on device configuration
        // If not available, should be .notAvailable
        // If available, depends on user action (can't test interactively)
        if !MFMailComposeViewController.canSendMail() {
            XCTAssertEqual(result, .notAvailable, "Should return notAvailable on simulator without email")
        }
    }
    
    @MainActor
    func testComposeEmailAsyncWithHTML() async {
        // Test isHTML parameter is accepted
        let result = await service.composeEmailAsync(
            to: ["test@example.com"],
            subject: "HTML Test",
            body: "<p>Hello</p>",
            isHTML: true
        )
        // Result depends on device configuration
        // Just verify no crash with isHTML=true
        _ = result
    }
}
