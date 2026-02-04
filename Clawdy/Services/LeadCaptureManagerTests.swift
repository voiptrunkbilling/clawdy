import Foundation
import XCTest

/// Unit tests for LeadCaptureManager operations.
/// These tests validate the lead capture workflow functionality.
///
/// Test Categories:
/// 1. Service initialization (singleton pattern)
/// 2. Lead data validation
/// 3. Business card text parsing
/// 4. Capture state transitions
/// 5. Error handling
class LeadCaptureManagerTests: XCTestCase {
    
    private var manager: LeadCaptureManager!
    
    @MainActor
    override func setUp() {
        super.setUp()
        manager = LeadCaptureManager.shared
        // Reset state
        manager.cancelCapture()
    }
    
    override func tearDown() {
        manager = nil
        super.tearDown()
    }
    
    // MARK: - Singleton Tests
    
    @MainActor
    func testSingletonPattern() {
        let manager2 = LeadCaptureManager.shared
        XCTAssertTrue(manager === manager2, "LeadCaptureManager should use singleton pattern")
    }
    
    // MARK: - Initial State Tests
    
    @MainActor
    func testInitialStateIsIdle() {
        XCTAssertEqual(manager.captureState, .idle)
        XCTAssertFalse(manager.isShowingEntryForm)
        XCTAssertNil(manager.errorMessage)
    }
    
    // MARK: - Manual Entry Tests
    
    @MainActor
    func testStartManualEntry() {
        manager.startManualEntry()
        
        XCTAssertEqual(manager.captureState, .manualEntry)
        XCTAssertTrue(manager.isShowingEntryForm)
        XCTAssertEqual(manager.currentLead.captureMethod, .manual)
    }
    
    @MainActor
    func testCancelCapture() {
        manager.startManualEntry()
        manager.currentLead.name = "Test Name"
        
        manager.cancelCapture()
        
        XCTAssertEqual(manager.captureState, .idle)
        XCTAssertFalse(manager.isShowingEntryForm)
        XCTAssertTrue(manager.currentLead.name.isEmpty)
    }
    
    // MARK: - Validation Tests
    
    @MainActor
    func testSaveLeadRequiresName() async {
        manager.startManualEntry()
        manager.currentLead.name = ""
        
        let result = await manager.saveLead()
        
        if case .failed(let error) = result {
            XCTAssertEqual(error, .missingName)
        } else {
            XCTFail("Expected .failed(.missingName)")
        }
    }
    
    @MainActor
    func testSaveLeadRequiresNonWhitespaceName() async {
        manager.startManualEntry()
        manager.currentLead.name = "   "
        
        let result = await manager.saveLead()
        
        if case .failed(let error) = result {
            XCTAssertEqual(error, .missingName)
        } else {
            XCTFail("Expected .failed(.missingName)")
        }
    }
    
    // MARK: - LeadData Tests
    
    func testLeadDataToDictionary() {
        var lead = LeadData()
        lead.name = "John Doe"
        lead.company = "Acme Inc"
        lead.phone = "+15551234567"
        lead.email = "john@example.com"
        lead.captureMethod = .businessCard
        
        let dict = lead.toDictionary()
        
        XCTAssertEqual(dict["name"] as? String, "John Doe")
        XCTAssertEqual(dict["company"] as? String, "Acme Inc")
        XCTAssertEqual(dict["phone"] as? String, "+15551234567")
        XCTAssertEqual(dict["email"] as? String, "john@example.com")
        XCTAssertEqual(dict["captureMethod"] as? String, "business_card")
    }
    
    func testLeadDataToDictionaryWithFollowUpDate() {
        var lead = LeadData()
        lead.name = "Jane Doe"
        let followUpDate = Date()
        lead.followUpDate = followUpDate
        
        let dict = lead.toDictionary()
        
        XCTAssertNotNil(dict["followUpDate"] as? String)
    }
    
    // MARK: - LeadCaptureMethod Tests
    
    func testLeadCaptureMethodRawValues() {
        XCTAssertEqual(LeadCaptureMethod.voiceNote.rawValue, "voice_note")
        XCTAssertEqual(LeadCaptureMethod.businessCard.rawValue, "business_card")
        XCTAssertEqual(LeadCaptureMethod.callFollowUp.rawValue, "call_follow_up")
        XCTAssertEqual(LeadCaptureMethod.manual.rawValue, "manual")
    }
    
    func testLeadCaptureMethodDisplayNames() {
        XCTAssertEqual(LeadCaptureMethod.voiceNote.displayName, "Voice Note")
        XCTAssertEqual(LeadCaptureMethod.businessCard.displayName, "Business Card")
        XCTAssertEqual(LeadCaptureMethod.callFollowUp.displayName, "Call Follow-up")
        XCTAssertEqual(LeadCaptureMethod.manual.displayName, "Manual Entry")
    }
    
    // MARK: - LeadCaptureState Tests
    
    func testLeadCaptureStateIsLoading() {
        XCTAssertFalse(LeadCaptureState.idle.isLoading)
        XCTAssertTrue(LeadCaptureState.parsingVoiceNote.isLoading)
        XCTAssertTrue(LeadCaptureState.processingBusinessCard.isLoading)
        XCTAssertFalse(LeadCaptureState.manualEntry.isLoading)
        XCTAssertTrue(LeadCaptureState.saving.isLoading)
        XCTAssertFalse(LeadCaptureState.error("test").isLoading)
    }
    
    // MARK: - LeadCaptureError Tests
    
    func testLeadCaptureErrorDescriptions() {
        XCTAssertEqual(
            LeadCaptureError.missingName.errorDescription,
            "Name is required to save a lead"
        )
        
        XCTAssertEqual(
            LeadCaptureError.ocrFailed("test").errorDescription,
            "Failed to read business card: test"
        )
        
        XCTAssertEqual(
            LeadCaptureError.aiParsingFailed("test").errorDescription,
            "Failed to parse voice note: test"
        )
        
        XCTAssertEqual(
            LeadCaptureError.permissionDenied("test").errorDescription,
            "Permission denied: test"
        )
        
        XCTAssertEqual(
            LeadCaptureError.saveFailed("test").errorDescription,
            "Failed to save lead: test"
        )
    }
    
    // MARK: - LeadCaptureActions Tests
    
    func testLeadCaptureActionsDefaults() {
        let actions = LeadCaptureActions()
        
        XCTAssertFalse(actions.contactCreated)
        XCTAssertNil(actions.contactError)
        XCTAssertFalse(actions.reminderScheduled)
        XCTAssertNil(actions.reminderError)
        XCTAssertFalse(actions.emailComposed)
        XCTAssertNil(actions.emailError)
        XCTAssertFalse(actions.sentToGateway)
    }
    
    // MARK: - Voice Note Entry Tests
    
    @MainActor
    func testCaptureFromVoiceNoteWithEmptyTranscription() async {
        await manager.captureFromVoiceNote("")
        
        XCTAssertEqual(manager.errorMessage, "Voice note is empty")
        XCTAssertEqual(manager.captureState, .idle)
    }
    
    @MainActor
    func testCaptureFromVoiceNoteWithWhitespaceOnly() async {
        await manager.captureFromVoiceNote("   ")
        
        XCTAssertEqual(manager.errorMessage, "Voice note is empty")
    }
    
    // MARK: - Call Follow-up Tests
    
    @MainActor
    func testCaptureFromCallFollowUp() async {
        await manager.captureFromCallFollowUp(phoneNumber: "+15551234567")
        
        XCTAssertEqual(manager.captureState, .manualEntry)
        XCTAssertTrue(manager.isShowingEntryForm)
        XCTAssertEqual(manager.currentLead.captureMethod, .callFollowUp)
        XCTAssertEqual(manager.currentLead.phone, "+15551234567")
    }
    
    @MainActor
    func testCaptureFromCallFollowUpWithNilPhone() async {
        await manager.captureFromCallFollowUp(phoneNumber: nil)
        
        XCTAssertEqual(manager.captureState, .manualEntry)
        XCTAssertTrue(manager.currentLead.phone.isEmpty)
    }
}

// MARK: - Business Card Parsing Tests

class BusinessCardParsingTests: XCTestCase {
    
    // MARK: - Email Pattern Tests
    
    func testEmailPatternMatching() {
        let pattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        
        let validEmails = [
            "test@example.com",
            "john.doe@company.org",
            "user+tag@domain.co.uk",
            "name123@test-domain.io"
        ]
        
        for email in validEmails {
            let range = email.range(of: pattern, options: .regularExpression)
            XCTAssertNotNil(range, "Should match valid email: \(email)")
        }
        
        let invalidEmails = [
            "notanemail",
            "@nodomain.com",
            "no@domain"
        ]
        
        for email in invalidEmails {
            let range = email.range(of: pattern, options: .regularExpression)
            XCTAssertNil(range, "Should not match invalid email: \(email)")
        }
    }
    
    // MARK: - Phone Pattern Tests
    
    func testPhonePatternMatching() {
        let patterns = [
            #"\+?1?[-.\s]?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}"#,
            #"\+[0-9]{1,3}[-.\s]?[0-9]{1,4}[-.\s]?[0-9]{3,4}[-.\s]?[0-9]{3,4}"#
        ]
        
        let validPhones = [
            "1234567890",
            "123-456-7890",
            "(123) 456-7890",
            "+1 123 456 7890"
        ]
        
        for phone in validPhones {
            var matched = false
            for pattern in patterns {
                if phone.range(of: pattern, options: .regularExpression) != nil {
                    matched = true
                    break
                }
            }
            XCTAssertTrue(matched, "Should match valid phone: \(phone)")
        }
    }
}

// MARK: - Lead Capture Capability Types Tests

class LeadCaptureCapabilityTypesTests: XCTestCase {
    
    func testLeadCaptureCapabilityResultSuccess() {
        let result = LeadCaptureCapabilityResult.success(
            leadId: "123",
            contactCreated: true,
            reminderScheduled: true,
            emailComposed: false
        )
        
        XCTAssertTrue(result.captured)
        XCTAssertEqual(result.leadId, "123")
        XCTAssertEqual(result.contactCreated, true)
        XCTAssertEqual(result.reminderScheduled, true)
        XCTAssertEqual(result.emailComposed, false)
        XCTAssertNil(result.error)
    }
    
    func testLeadCaptureCapabilityResultFailed() {
        let result = LeadCaptureCapabilityResult.failed("Test error")
        
        XCTAssertFalse(result.captured)
        XCTAssertNil(result.leadId)
        XCTAssertEqual(result.error, "Test error")
    }
    
    func testLeadParseVoiceNoteResultSuccess() {
        let result = LeadParseVoiceNoteResult.success(
            name: "John",
            company: "Acme",
            title: "CEO",
            phone: "123",
            email: "j@a.com",
            notes: "Met at conference"
        )
        
        XCTAssertTrue(result.parsed)
        XCTAssertEqual(result.name, "John")
        XCTAssertEqual(result.company, "Acme")
        XCTAssertEqual(result.title, "CEO")
        XCTAssertNil(result.error)
    }
    
    func testLeadParseVoiceNoteResultFailed() {
        let result = LeadParseVoiceNoteResult.failed("Parsing failed")
        
        XCTAssertFalse(result.parsed)
        XCTAssertNil(result.name)
        XCTAssertEqual(result.error, "Parsing failed")
    }
}
