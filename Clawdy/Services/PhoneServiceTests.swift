import Foundation
import UIKit
import MessageUI
import XCTest

/// Unit tests for PhoneService operations.
/// These tests validate the phone and SMS capability service functionality.
///
/// Test Categories:
/// 1. Service initialization (singleton pattern)
/// 2. Phone number validation
/// 3. Phone number cleaning/normalization
/// 4. Availability checking
class PhoneServiceTests: XCTestCase {
    
    private var service: PhoneService!
    
    @MainActor
    override func setUp() {
        super.setUp()
        service = PhoneService.shared
    }
    
    override func tearDown() {
        service = nil
        super.tearDown()
    }
    
    // MARK: - Singleton Tests
    
    @MainActor
    func testSingletonPattern() {
        let service2 = PhoneService.shared
        XCTAssertTrue(service === service2, "PhoneService should use singleton pattern")
    }
    
    // MARK: - Availability Tests
    
    @MainActor
    func testAvailabilityCheck() {
        // Just verify the check doesn't crash
        service.checkAvailability()
        // isCallAvailable and isSMSAvailable should be set
        _ = service.isCallAvailable
        _ = service.isSMSAvailable
    }
    
    @MainActor
    func testIsAvailableAliasMatchesIsCallAvailable() {
        XCTAssertEqual(service.isAvailable, service.isCallAvailable,
                       "isAvailable should be an alias for isCallAvailable")
    }
    
    // MARK: - Phone Number Validation Tests
    
    @MainActor
    func testValidPhoneNumbers() {
        // US format
        XCTAssertTrue(service.isValidPhoneNumber("1234567890"), "10 digits should be valid")
        XCTAssertTrue(service.isValidPhoneNumber("123-456-7890"), "Dashes should be valid")
        XCTAssertTrue(service.isValidPhoneNumber("(123) 456-7890"), "Parentheses should be valid")
        XCTAssertTrue(service.isValidPhoneNumber("+1 123 456 7890"), "International format should be valid")
        
        // International numbers
        XCTAssertTrue(service.isValidPhoneNumber("+44 20 7946 0958"), "UK format should be valid")
        XCTAssertTrue(service.isValidPhoneNumber("+81 3 1234 5678"), "Japan format should be valid")
        
        // Short codes (area code minimum)
        XCTAssertTrue(service.isValidPhoneNumber("911"), "Emergency codes should be valid")
        XCTAssertTrue(service.isValidPhoneNumber("411"), "Info codes should be valid")
    }
    
    @MainActor
    func testInvalidPhoneNumbers() {
        // Too short
        XCTAssertFalse(service.isValidPhoneNumber("12"), "2 digits should be invalid")
        XCTAssertFalse(service.isValidPhoneNumber("1"), "1 digit should be invalid")
        XCTAssertFalse(service.isValidPhoneNumber(""), "Empty should be invalid")
        
        // Too long (ITU max is 15 digits)
        XCTAssertFalse(service.isValidPhoneNumber("1234567890123456"), "16 digits should be invalid")
        
        // Non-numeric only (after cleanup becomes empty)
        XCTAssertFalse(service.isValidPhoneNumber("abc"), "Letters only should be invalid")
        XCTAssertFalse(service.isValidPhoneNumber("---"), "Dashes only should be invalid")
    }
    
    // MARK: - Phone Number Cleaning Tests
    
    @MainActor
    func testPhoneNumberCleaning() {
        // Basic cleaning
        XCTAssertEqual(service.cleanPhoneNumber("123-456-7890"), "1234567890")
        XCTAssertEqual(service.cleanPhoneNumber("(123) 456-7890"), "1234567890")
        XCTAssertEqual(service.cleanPhoneNumber("123 456 7890"), "1234567890")
        
        // Preserve leading +
        XCTAssertEqual(service.cleanPhoneNumber("+1 123 456 7890"), "+11234567890")
        XCTAssertEqual(service.cleanPhoneNumber("+44 20 7946 0958"), "+442079460958")
        
        // Remove all non-digits (except leading +)
        XCTAssertEqual(service.cleanPhoneNumber("abc123def456"), "123456")
    }
    
    // MARK: - Error Type Tests
    
    func testNotAvailableErrorDescription() {
        let error = PhoneService.PhoneError.notAvailable
        XCTAssertTrue(error.errorDescription?.contains("not available") == true,
                      "notAvailable error should have correct description")
    }
    
    func testInvalidNumberErrorDescription() {
        let error = PhoneService.PhoneError.invalidNumber
        XCTAssertTrue(error.errorDescription?.contains("Invalid phone number") == true,
                      "invalidNumber error should have correct description")
    }
    
    func testCallFailedErrorDescription() {
        let error = PhoneService.PhoneError.callFailed
        XCTAssertTrue(error.errorDescription?.contains("Failed to initiate") == true,
                      "callFailed error should have correct description")
    }
    
    func testSmsNotAvailableErrorDescription() {
        let error = PhoneService.PhoneError.smsNotAvailable
        XCTAssertTrue(error.errorDescription?.contains("SMS not available") == true,
                      "smsNotAvailable error should have correct description")
    }
    
    func testSmsFailedErrorDescription() {
        let error = PhoneService.PhoneError.smsFailed
        XCTAssertTrue(error.errorDescription?.contains("Failed to send SMS") == true,
                      "smsFailed error should have correct description")
    }
    
    // MARK: - Call/SMS Operations Tests (Simulator-safe)
    
    @MainActor
    func testCallWithInvalidNumberReturnsFalse() async {
        // Invalid number should fail validation before attempting call
        let result = await service.call(phoneNumber: "ab")
        XCTAssertFalse(result, "Call with invalid number should return false")
    }
    
    @MainActor
    func testSMSWithInvalidNumberReturnsFalse() async {
        // Invalid number should fail validation before attempting SMS
        let result = await service.sendSMS(to: "ab", body: "Test")
        XCTAssertFalse(result, "SMS with invalid number should return false")
    }
    
    // MARK: - PhoneCallServiceResult Tests
    
    func testPhoneCallServiceResultSuccess() {
        let result = PhoneService.PhoneCallServiceResult.success
        XCTAssertNil(result.errorMessage, "success should have no error message")
    }
    
    func testPhoneCallServiceResultNotAvailable() {
        let result = PhoneService.PhoneCallServiceResult.notAvailable
        XCTAssertEqual(result.errorMessage, "Phone calls not available on this device")
    }
    
    func testPhoneCallServiceResultInvalidNumber() {
        let result = PhoneService.PhoneCallServiceResult.invalidNumber
        XCTAssertEqual(result.errorMessage, "Invalid phone number format")
    }
    
    func testPhoneCallServiceResultCallFailed() {
        let result = PhoneService.PhoneCallServiceResult.callFailed
        XCTAssertEqual(result.errorMessage, "Failed to initiate call")
    }
    
    // MARK: - SMSComposeServiceResult Tests
    
    func testSMSComposeServiceResultSent() {
        let result = PhoneService.SMSComposeServiceResult.sent
        XCTAssertNil(result.errorMessage, "sent should have no error message")
    }
    
    func testSMSComposeServiceResultCancelled() {
        let result = PhoneService.SMSComposeServiceResult.cancelled
        XCTAssertNil(result.errorMessage, "cancelled should have no error message")
    }
    
    func testSMSComposeServiceResultNotAvailable() {
        let result = PhoneService.SMSComposeServiceResult.notAvailable
        XCTAssertEqual(result.errorMessage, "SMS not available on this device")
    }
    
    func testSMSComposeServiceResultInvalidNumber() {
        let result = PhoneService.SMSComposeServiceResult.invalidNumber
        XCTAssertEqual(result.errorMessage, "Invalid phone number format")
    }
    
    func testSMSComposeServiceResultComposeFailed() {
        let result = PhoneService.SMSComposeServiceResult.composeFailed
        XCTAssertEqual(result.errorMessage, "Failed to compose SMS")
    }
    
    // MARK: - InitiateCall Tests (Simulator-safe)
    
    @MainActor
    func testInitiateCallWithInvalidNumber() async {
        // Invalid number should return .invalidNumber
        let result = await service.initiateCall(phoneNumber: "ab")
        XCTAssertEqual(result, .invalidNumber, "Invalid number should return .invalidNumber")
    }
    
    @MainActor
    func testInitiateCallWithEmptyNumber() async {
        // Empty number should return .invalidNumber
        let result = await service.initiateCall(phoneNumber: "")
        XCTAssertEqual(result, .invalidNumber, "Empty number should return .invalidNumber")
    }
    
    // MARK: - ComposeSMS Tests (Simulator-safe)
    
    @MainActor
    func testComposeSMSWithInvalidNumber() async {
        // Invalid number should return .invalidNumber
        let result = await service.composeSMS(to: "ab", body: "Test")
        XCTAssertEqual(result, .invalidNumber, "Invalid number should return .invalidNumber")
    }
    
    @MainActor
    func testComposeSMSWithEmptyNumber() async {
        // Empty number should return .invalidNumber
        let result = await service.composeSMS(to: "", body: nil)
        XCTAssertEqual(result, .invalidNumber, "Empty number should return .invalidNumber")
    }
}
