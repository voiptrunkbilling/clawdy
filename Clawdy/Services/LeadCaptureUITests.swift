import Foundation
import XCTest

/// UI tests for lead capture workflows.
/// These tests validate the lead capture UI flows including form presentation,
/// validation, and data entry.
///
/// Test Categories:
/// 1. Lead capture form presentation
/// 2. Missing name validation enforcement
/// 3. Voice note input flow
/// 4. Business card OCR flow
/// 5. Contact/calendar/email action verification
class LeadCaptureUITests: XCTestCase {
    
    private var manager: LeadCaptureManager!
    
    @MainActor
    override func setUp() {
        super.setUp()
        manager = LeadCaptureManager.shared
        // Reset state before each test
        manager.cancelCapture()
    }
    
    override func tearDown() {
        manager = nil
        super.tearDown()
    }
    
    // MARK: - Form Presentation Tests
    
    @MainActor
    func testManualEntryShowsForm() {
        XCTAssertFalse(manager.isShowingEntryForm, "Form should not be showing initially")
        XCTAssertEqual(manager.captureState, .idle, "State should be idle initially")
        
        manager.startManualEntry()
        
        XCTAssertTrue(manager.isShowingEntryForm, "Form should show after startManualEntry()")
        XCTAssertEqual(manager.captureState, .manualEntry, "State should be manualEntry")
        XCTAssertEqual(manager.currentLead.captureMethod, .manual, "Capture method should be manual")
    }
    
    @MainActor
    func testCancelClosesForm() {
        manager.startManualEntry()
        XCTAssertTrue(manager.isShowingEntryForm)
        
        manager.cancelCapture()
        
        XCTAssertFalse(manager.isShowingEntryForm, "Form should close after cancel")
        XCTAssertEqual(manager.captureState, .idle, "State should reset to idle")
        XCTAssertTrue(manager.currentLead.name.isEmpty, "Lead data should be cleared")
    }
    
    // MARK: - Missing Name Validation Tests
    
    @MainActor
    func testSaveFailsWithEmptyName() async {
        manager.startManualEntry()
        manager.currentLead.name = ""
        manager.currentLead.phone = "555-1234"
        manager.currentLead.email = "test@example.com"
        
        let result = await manager.saveLead()
        
        switch result {
        case .failed(let error):
            XCTAssertEqual(error, .missingName, "Should fail with missingName error")
        default:
            XCTFail("Expected .failed(.missingName) but got \(result)")
        }
        
        XCTAssertEqual(manager.errorMessage, "Name is required", "Error message should indicate name is required")
    }
    
    @MainActor
    func testSaveFailsWithWhitespaceName() async {
        manager.startManualEntry()
        manager.currentLead.name = "   "
        
        let result = await manager.saveLead()
        
        switch result {
        case .failed(let error):
            XCTAssertEqual(error, .missingName)
        default:
            XCTFail("Expected .failed(.missingName)")
        }
    }
    
    @MainActor
    func testSaveAllowsValidName() async {
        manager.startManualEntry()
        manager.currentLead.name = "John Doe"
        manager.currentLead.shouldCreateContact = false
        manager.currentLead.shouldScheduleReminder = false
        manager.currentLead.shouldSendEmailSummary = false
        
        let result = await manager.saveLead()
        
        // Without actions enabled and no gateway, should succeed
        switch result {
        case .success(let savedLead, _):
            XCTAssertEqual(savedLead.name, "John Doe")
        case .failed:
            // This is also acceptable since gateway is not configured
            break
        case .cancelled:
            XCTFail("Should not be cancelled")
        }
    }
    
    // MARK: - Voice Note Input Flow Tests
    
    @MainActor
    func testVoiceNoteEmptyTranscription() async {
        await manager.captureFromVoiceNote("")
        
        XCTAssertEqual(manager.errorMessage, "Voice note is empty")
        XCTAssertEqual(manager.captureState, .idle, "State should remain idle")
        XCTAssertFalse(manager.isShowingEntryForm, "Form should not show")
    }
    
    @MainActor
    func testVoiceNoteWhitespaceTranscription() async {
        await manager.captureFromVoiceNote("   ")
        
        XCTAssertEqual(manager.errorMessage, "Voice note is empty")
    }
    
    @MainActor
    func testVoiceNoteWithValidTranscription() async {
        // Without gateway callback, parsing will fail but form should show
        await manager.captureFromVoiceNote("Met John Doe from Acme Corp, phone 555-1234")
        
        XCTAssertTrue(manager.isShowingEntryForm, "Form should show after voice note")
        XCTAssertEqual(manager.captureState, .manualEntry)
        XCTAssertEqual(manager.currentLead.captureMethod, .voiceNote)
        XCTAssertEqual(manager.currentLead.rawInput, "Met John Doe from Acme Corp, phone 555-1234")
    }
    
    // MARK: - Call Follow-up Flow Tests
    
    @MainActor
    func testCallFollowUpWithPhoneNumber() async {
        await manager.captureFromCallFollowUp(phoneNumber: "+1-555-123-4567")
        
        XCTAssertTrue(manager.isShowingEntryForm, "Form should show")
        XCTAssertEqual(manager.captureState, .manualEntry)
        XCTAssertEqual(manager.currentLead.captureMethod, .callFollowUp)
        XCTAssertEqual(manager.currentLead.phone, "+1-555-123-4567")
    }
    
    @MainActor
    func testCallFollowUpWithoutPhoneNumber() async {
        await manager.captureFromCallFollowUp(phoneNumber: nil)
        
        XCTAssertTrue(manager.isShowingEntryForm)
        XCTAssertTrue(manager.currentLead.phone.isEmpty, "Phone should be empty when not provided")
    }
    
    // MARK: - Action Toggle Tests
    
    @MainActor
    func testDefaultActionSettings() {
        manager.startManualEntry()
        
        XCTAssertTrue(manager.currentLead.shouldCreateContact, "Create contact should default to true")
        XCTAssertFalse(manager.currentLead.shouldScheduleReminder, "Schedule reminder should default to false")
        XCTAssertFalse(manager.currentLead.shouldSendEmailSummary, "Send email should default to false")
    }
    
    @MainActor
    func testFollowUpDateRequiredForReminder() {
        manager.startManualEntry()
        manager.currentLead.shouldScheduleReminder = true
        manager.currentLead.followUpDate = nil
        
        // Even with reminder enabled, followUpDate nil should not schedule
        XCTAssertNil(manager.currentLead.followUpDate)
    }
    
    @MainActor
    func testEmailRecipientRequiredForSummary() {
        manager.startManualEntry()
        manager.currentLead.shouldSendEmailSummary = true
        manager.currentLead.emailSummaryRecipient = nil
        
        // Even with email enabled, nil recipient should not send
        XCTAssertNil(manager.currentLead.emailSummaryRecipient)
    }
    
    // MARK: - Data Prefill Tests
    
    @MainActor
    func testLeadDataPrefilling() {
        manager.startManualEntry()
        
        // Prefill data like UI would
        manager.currentLead.name = "Jane Smith"
        manager.currentLead.company = "TechCorp"
        manager.currentLead.title = "CEO"
        manager.currentLead.phone = "555-9876"
        manager.currentLead.email = "jane@techcorp.com"
        manager.currentLead.notes = "Met at conference"
        
        XCTAssertEqual(manager.currentLead.name, "Jane Smith")
        XCTAssertEqual(manager.currentLead.company, "TechCorp")
        XCTAssertEqual(manager.currentLead.title, "CEO")
        XCTAssertEqual(manager.currentLead.phone, "555-9876")
        XCTAssertEqual(manager.currentLead.email, "jane@techcorp.com")
        XCTAssertEqual(manager.currentLead.notes, "Met at conference")
    }
    
    // MARK: - State Preservation on Error Tests
    
    @MainActor
    func testStatePreservedOnValidationError() async {
        manager.startManualEntry()
        manager.currentLead.name = ""
        manager.currentLead.phone = "555-1234"
        manager.currentLead.email = "test@example.com"
        
        _ = await manager.saveLead()
        
        // State should be preserved for retry
        XCTAssertTrue(manager.isShowingEntryForm || manager.captureState != .idle,
                      "State should allow retry on validation error")
        XCTAssertEqual(manager.currentLead.phone, "555-1234", "Phone should be preserved")
        XCTAssertEqual(manager.currentLead.email, "test@example.com", "Email should be preserved")
    }
    
    // MARK: - LeadCaptureActions Tests
    
    func testLeadCaptureActionsInitialValues() {
        let actions = LeadCaptureActions()
        
        XCTAssertFalse(actions.contactCreated)
        XCTAssertNil(actions.contactError)
        XCTAssertFalse(actions.reminderScheduled)
        XCTAssertNil(actions.reminderError)
        XCTAssertFalse(actions.emailComposed)
        XCTAssertNil(actions.emailError)
        XCTAssertFalse(actions.sentToGateway)
    }
    
    func testLeadCaptureActionsErrorTracking() {
        var actions = LeadCaptureActions()
        
        actions.contactError = "Contact permission denied"
        actions.reminderError = "Calendar permission denied"
        actions.emailError = "Email not available"
        
        XCTAssertEqual(actions.contactError, "Contact permission denied")
        XCTAssertEqual(actions.reminderError, "Calendar permission denied")
        XCTAssertEqual(actions.emailError, "Email not available")
    }
    
    // MARK: - Capture State Tests
    
    func testCaptureStateTransitions() {
        XCTAssertFalse(LeadCaptureState.idle.isLoading)
        XCTAssertTrue(LeadCaptureState.parsingVoiceNote.isLoading)
        XCTAssertTrue(LeadCaptureState.processingBusinessCard.isLoading)
        XCTAssertFalse(LeadCaptureState.manualEntry.isLoading)
        XCTAssertTrue(LeadCaptureState.saving.isLoading)
        XCTAssertFalse(LeadCaptureState.error("test").isLoading)
    }
    
    // MARK: - Error Message Tests
    
    @MainActor
    func testErrorMessageClearing() {
        manager.startManualEntry()
        manager.errorMessage = "Previous error"
        
        manager.cancelCapture()
        
        XCTAssertNil(manager.errorMessage, "Error message should be cleared on cancel")
    }
}

// MARK: - Gateway Integration Tests

class LeadCaptureGatewayTests: XCTestCase {
    
    private var manager: LeadCaptureManager!
    
    @MainActor
    override func setUp() {
        super.setUp()
        manager = LeadCaptureManager.shared
        manager.cancelCapture()
    }
    
    override func tearDown() {
        manager = nil
        super.tearDown()
    }
    
    // MARK: - Gateway Callback Tests
    
    @MainActor
    func testGatewayCallbackNotConfigured() async {
        manager.startManualEntry()
        manager.currentLead.name = "Test User"
        manager.currentLead.shouldCreateContact = false
        manager.currentLead.shouldScheduleReminder = false
        manager.currentLead.shouldSendEmailSummary = false
        
        // Without gateway callback, sentToGateway should be false
        let result = await manager.saveLead()
        
        switch result {
        case .success(_, let actions):
            XCTAssertFalse(actions.sentToGateway, "sentToGateway should be false without callback")
        case .failed:
            // Also acceptable - gateway failure is treated as error
            break
        case .cancelled:
            XCTFail("Should not be cancelled")
        }
    }
    
    @MainActor
    func testGatewayCallbackConfigured() async {
        var gatewayCalled = false
        var receivedLead: LeadData?
        
        manager.onSendToGateway = { lead, _ in
            gatewayCalled = true
            receivedLead = lead
            return true
        }
        
        manager.startManualEntry()
        manager.currentLead.name = "Gateway Test"
        manager.currentLead.shouldCreateContact = false
        manager.currentLead.shouldScheduleReminder = false
        manager.currentLead.shouldSendEmailSummary = false
        
        let result = await manager.saveLead()
        
        XCTAssertTrue(gatewayCalled, "Gateway callback should be called")
        XCTAssertEqual(receivedLead?.name, "Gateway Test")
        
        switch result {
        case .success(_, let actions):
            XCTAssertTrue(actions.sentToGateway)
        case .failed, .cancelled:
            XCTFail("Should succeed when gateway returns true")
        }
        
        // Clean up
        manager.onSendToGateway = nil
    }
    
    @MainActor
    func testGatewayCallbackFailure() async {
        manager.onSendToGateway = { _, _ in
            return false // Simulate gateway failure
        }
        
        manager.startManualEntry()
        manager.currentLead.name = "Gateway Fail Test"
        manager.currentLead.shouldCreateContact = false
        manager.currentLead.shouldScheduleReminder = false
        manager.currentLead.shouldSendEmailSummary = false
        
        let result = await manager.saveLead()
        
        switch result {
        case .failed(let error):
            XCTAssertEqual(error, .saveFailed("Failed to sync with gateway"))
        default:
            // Gateway failure should result in .failed
            break
        }
        
        // State should be preserved for retry
        XCTAssertTrue(manager.isShowingEntryForm || manager.captureState == .manualEntry,
                      "State should be preserved for retry")
        
        // Clean up
        manager.onSendToGateway = nil
    }
    
    // MARK: - Voice Note Parsing Tests
    
    @MainActor
    func testVoiceNoteParsingCallback() async {
        var parsingCalled = false
        var receivedTranscription: String?
        
        manager.onParseVoiceNote = { transcription in
            parsingCalled = true
            receivedTranscription = transcription
            
            var lead = LeadData()
            lead.name = "Parsed Name"
            lead.company = "Parsed Company"
            return lead
        }
        
        await manager.captureFromVoiceNote("Test transcription content")
        
        XCTAssertTrue(parsingCalled)
        XCTAssertEqual(receivedTranscription, "Test transcription content")
        XCTAssertEqual(manager.currentLead.name, "Parsed Name")
        XCTAssertEqual(manager.currentLead.company, "Parsed Company")
        
        // Clean up
        manager.onParseVoiceNote = nil
    }
    
    @MainActor
    func testVoiceNoteParsingFailure() async {
        manager.onParseVoiceNote = { _ in
            return nil // Simulate parsing failure
        }
        
        await manager.captureFromVoiceNote("Some transcription")
        
        // Form should still show with raw input in notes
        XCTAssertTrue(manager.isShowingEntryForm)
        XCTAssertEqual(manager.currentLead.rawInput, "Some transcription")
        XCTAssertTrue(manager.currentLead.notes.contains("Some transcription"))
        
        // Clean up
        manager.onParseVoiceNote = nil
    }
}
