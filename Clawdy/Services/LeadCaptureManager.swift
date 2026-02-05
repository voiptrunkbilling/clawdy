import Foundation
import UIKit
import Vision
import Contacts
import EventKit

/// Orchestrates the complete lead capture workflow.
/// Supports multiple entry points: voice notes, business cards, and call follow-ups.
@MainActor
class LeadCaptureManager: ObservableObject {
    static let shared = LeadCaptureManager()
    
    // MARK: - Published Properties
    
    /// Current capture state for UI binding
    @Published private(set) var captureState: LeadCaptureState = .idle
    
    /// Current lead data being captured/edited
    @Published var currentLead: LeadData = LeadData()
    
    /// Whether the manual entry form is showing
    @Published var isShowingEntryForm: Bool = false
    
    /// Error message to display
    @Published var errorMessage: String?
    
    // MARK: - Dependencies
    
    private let contactsService: ContactsService
    private let calendarService: CalendarService
    private let emailService: EmailService
    
    /// Callback to send parsed voice text to gateway for AI extraction
    var onParseVoiceNote: ((_ transcription: String) async -> LeadData?)?
    
    /// Callback to send lead data to gateway
    var onSendToGateway: ((_ lead: LeadData, _ actions: LeadCaptureActions) async -> Bool)?
    
    // MARK: - Initialization
    
    private init(
        contactsService: ContactsService = .shared,
        calendarService: CalendarService = .shared,
        emailService: EmailService = .shared
    ) {
        self.contactsService = contactsService
        self.calendarService = calendarService
        self.emailService = emailService
    }
    
    // MARK: - Voice Note Entry
    
    /// Start lead capture from a voice transcription.
    /// Sends to gateway for AI parsing, then shows manual entry form.
    /// - Parameter transcription: The transcribed voice note text
    func captureFromVoiceNote(_ transcription: String) async {
        guard !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Voice note is empty"
            return
        }
        
        captureState = .parsingVoiceNote
        
        // Send to gateway for AI parsing
        if let parsedLead = await onParseVoiceNote?(transcription) {
            currentLead = parsedLead
            currentLead.captureMethod = .voiceNote
            currentLead.rawInput = transcription
        } else {
            // AI parsing failed, start with empty form
            currentLead = LeadData()
            currentLead.captureMethod = .voiceNote
            currentLead.rawInput = transcription
            currentLead.notes = "Voice note: \(transcription)"
        }
        
        captureState = .manualEntry
        isShowingEntryForm = true
    }
    
    // MARK: - Business Card OCR
    
    /// Start lead capture from a business card image.
    /// Uses Vision framework for OCR, parses text, then shows manual entry form.
    /// - Parameter image: The captured business card image
    func captureFromBusinessCard(_ image: UIImage) async {
        captureState = .processingBusinessCard
        
        do {
            // Perform OCR using Vision framework
            let extractedText = try await performOCR(on: image)
            
            // Parse extracted text into lead data
            let parsedLead = parseBusinessCardText(extractedText)
            currentLead = parsedLead
            currentLead.captureMethod = .businessCard
            currentLead.rawInput = extractedText
            
            captureState = .manualEntry
            isShowingEntryForm = true
        } catch {
            print("[LeadCaptureManager] OCR failed: \(error)")
            errorMessage = "Failed to read business card: \(error.localizedDescription)"
            captureState = .error(error.localizedDescription)
            
            // Still allow manual entry
            currentLead = LeadData()
            currentLead.captureMethod = .businessCard
            isShowingEntryForm = true
        }
    }
    
    /// Perform OCR on an image using Vision framework.
    private func performOCR(on image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw LeadCaptureError.ocrFailed("Invalid image")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: LeadCaptureError.ocrFailed(error.localizedDescription))
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                // Extract all recognized text
                let recognizedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")
                
                continuation.resume(returning: recognizedText)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: LeadCaptureError.ocrFailed(error.localizedDescription))
            }
        }
    }
    
    /// Parse business card text into structured lead data.
    private func parseBusinessCardText(_ text: String) -> LeadData {
        var lead = LeadData()
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        // Email pattern (RFC 5322 simplified)
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        if let emailMatch = text.range(of: emailPattern, options: .regularExpression) {
            lead.email = String(text[emailMatch])
        }
        
        // Phone patterns (various formats)
        let phonePatterns = [
            #"\+?1?[-.\s]?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}"#,  // US
            #"\+[0-9]{1,3}[-.\s]?[0-9]{1,4}[-.\s]?[0-9]{3,4}[-.\s]?[0-9]{3,4}"#  // International
        ]
        for pattern in phonePatterns {
            if let phoneMatch = text.range(of: pattern, options: .regularExpression) {
                let phone = String(text[phoneMatch])
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: "(", with: "")
                    .replacingOccurrences(of: ")", with: "")
                lead.phone = phone
                break
            }
        }
        
        // The first line that doesn't look like email/phone/URL is likely the name
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.contains("@") &&
               !trimmed.contains("www.") &&
               !trimmed.contains("http") &&
               trimmed.range(of: #"^\+?[0-9\s\-\(\)\.]+$"#, options: .regularExpression) == nil &&
               trimmed.count > 2 && trimmed.count < 50 {
                // Likely a name
                if lead.name.isEmpty {
                    lead.name = trimmed
                } else if lead.company.isEmpty && trimmed != lead.name {
                    // Second "name-like" line might be company
                    lead.company = trimmed
                }
            }
        }
        
        // Look for job titles
        let titleKeywords = ["CEO", "CTO", "Manager", "Director", "VP", "President", "Founder", "Engineer", "Developer", "Sales", "Marketing"]
        for line in lines {
            for keyword in titleKeywords {
                if line.localizedCaseInsensitiveContains(keyword) && line != lead.name && line != lead.company {
                    lead.title = line.trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            if !lead.title.isEmpty { break }
        }
        
        return lead
    }
    
    // MARK: - Call Follow-up
    
    /// Start lead capture after a phone call.
    /// - Parameter phoneNumber: The phone number from the call
    func captureFromCallFollowUp(phoneNumber: String?) async {
        currentLead = LeadData()
        currentLead.captureMethod = .callFollowUp
        if let phone = phoneNumber {
            currentLead.phone = phone
        }
        
        captureState = .manualEntry
        isShowingEntryForm = true
    }
    
    // MARK: - Manual Entry
    
    /// Start a fresh manual entry lead capture.
    func startManualEntry() {
        currentLead = LeadData()
        currentLead.captureMethod = .manual
        captureState = .manualEntry
        isShowingEntryForm = true
    }
    
    /// Cancel the current capture session.
    func cancelCapture() {
        currentLead = LeadData()
        captureState = .idle
        isShowingEntryForm = false
        errorMessage = nil
    }
    
    // MARK: - Save Lead
    
    /// Validate and save the lead.
    /// Creates contact, schedules reminder, composes email summary, and sends to gateway.
    /// - Returns: Result of the save operation
    func saveLead() async -> LeadCaptureResult {
        // Validate minimum fields
        guard !currentLead.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Name is required"
            return .failed(.missingName)
        }
        
        captureState = .saving
        var actions = LeadCaptureActions()
        
        // 1. Create Contact
        if currentLead.shouldCreateContact {
            do {
                let contactId = try await createContact()
                currentLead.createdContactId = contactId
                actions.contactCreated = true
                print("[LeadCaptureManager] Contact created: \(contactId ?? "unknown")")
            } catch {
                print("[LeadCaptureManager] Failed to create contact: \(error)")
                actions.contactError = error.localizedDescription
            }
        }
        
        // 2. Schedule Calendar Reminder
        if currentLead.shouldScheduleReminder, let followUpDate = currentLead.followUpDate {
            do {
                let eventId = try await scheduleReminder(date: followUpDate)
                currentLead.createdEventId = eventId
                actions.reminderScheduled = true
                print("[LeadCaptureManager] Reminder scheduled: \(eventId ?? "unknown")")
            } catch {
                print("[LeadCaptureManager] Failed to schedule reminder: \(error)")
                actions.reminderError = error.localizedDescription
            }
        }
        
        // 3. Compose Email Summary
        if currentLead.shouldSendEmailSummary, let summaryEmail = currentLead.emailSummaryRecipient {
            let result = await composeEmailSummary(to: summaryEmail)
            actions.emailComposed = result.isSuccess
            if !result.isSuccess {
                actions.emailError = result.errorMessage
            }
        }
        
        // 4. Send to Gateway
        if let sendToGateway = onSendToGateway {
            let gatewaySuccess = await sendToGateway(currentLead, actions)
            actions.sentToGateway = gatewaySuccess
        } else {
            // No gateway callback configured - mark as not sent
            actions.sentToGateway = false
        }
        
        // Check for critical failures - don't clear state if errors occurred so user can retry
        var errorMessages: [String] = []
        
        if currentLead.shouldCreateContact, let error = actions.contactError {
            errorMessages.append("Contact: \(error)")
        }
        if currentLead.shouldScheduleReminder, let error = actions.reminderError {
            errorMessages.append("Reminder: \(error)")
        }
        if currentLead.shouldSendEmailSummary, let error = actions.emailError {
            errorMessages.append("Email: \(error)")
        }
        if onSendToGateway != nil && !actions.sentToGateway {
            errorMessages.append("Failed to sync with gateway")
        }
        
        if !errorMessages.isEmpty {
            // Keep state so user can retry
            captureState = .manualEntry
            errorMessage = errorMessages.joined(separator: "\n")
            return .failed(.saveFailed(errorMessages.joined(separator: "; ")))
        }
        
        // Success - reset state
        captureState = .idle
        isShowingEntryForm = false
        errorMessage = nil
        
        let savedLead = currentLead
        currentLead = LeadData()
        
        return .success(savedLead, actions)
    }
    
    // MARK: - Contact Creation
    
    private func createContact() async throws -> String? {
        // Request authorization if needed
        if !contactsService.isAuthorized {
            let granted = await contactsService.requestAuthorization()
            if !granted {
                throw LeadCaptureError.permissionDenied("Contacts access denied")
            }
        }
        
        // Parse name into first/last
        let nameParts = currentLead.name.split(separator: " ", maxSplits: 1)
        let firstName = String(nameParts.first ?? "")
        let lastName = nameParts.count > 1 ? String(nameParts[1]) : nil
        
        // Create contact
        let contactId = try contactsService.createContact(
            givenName: firstName,
            familyName: lastName,
            phoneNumber: currentLead.phone.isEmpty ? nil : currentLead.phone,
            email: currentLead.email.isEmpty ? nil : currentLead.email,
            company: currentLead.company.isEmpty ? nil : currentLead.company,
            notes: currentLead.notes.isEmpty ? nil : currentLead.notes
        )
        
        return contactId
    }
    
    // MARK: - Calendar Reminder
    
    private func scheduleReminder(date: Date) async throws -> String? {
        // Request authorization if needed
        if !calendarService.isAuthorized {
            let granted = await calendarService.requestAuthorization()
            if !granted {
                throw LeadCaptureError.permissionDenied("Calendar access denied")
            }
        }
        
        // Create event
        let title = "Follow up with \(currentLead.name)"
        let notes = "Lead captured via \(currentLead.captureMethod.displayName)\n\n\(currentLead.notes)"
        
        let eventId = try calendarService.createEvent(
            title: title,
            startDate: date,
            endDate: date.addingTimeInterval(30 * 60), // 30 minute event
            notes: notes
        )
        
        return eventId
    }
    
    // MARK: - Email Summary
    
    private func composeEmailSummary(to recipient: String) async -> EmailService.EmailComposeServiceResult {
        let subject = "Lead Captured: \(currentLead.name)"
        
        var body = """
        <h2>New Lead Captured</h2>
        <p><strong>Name:</strong> \(currentLead.name)</p>
        """
        
        if !currentLead.company.isEmpty {
            body += "<p><strong>Company:</strong> \(currentLead.company)</p>"
        }
        if !currentLead.title.isEmpty {
            body += "<p><strong>Title:</strong> \(currentLead.title)</p>"
        }
        if !currentLead.phone.isEmpty {
            body += "<p><strong>Phone:</strong> \(currentLead.phone)</p>"
        }
        if !currentLead.email.isEmpty {
            body += "<p><strong>Email:</strong> \(currentLead.email)</p>"
        }
        if !currentLead.notes.isEmpty {
            body += "<p><strong>Notes:</strong><br>\(currentLead.notes.replacingOccurrences(of: "\n", with: "<br>"))</p>"
        }
        
        body += "<p><em>Captured via \(currentLead.captureMethod.displayName) on \(Date().formatted())</em></p>"
        
        return await emailService.composeEmailAsync(
            to: [recipient],
            subject: subject,
            body: body,
            isHTML: true
        )
    }
}

// MARK: - Lead Data Model

/// Structured data for a captured lead.
struct LeadData: Codable, Equatable {
    var name: String = ""
    var company: String = ""
    var title: String = ""
    var phone: String = ""
    var email: String = ""
    var notes: String = ""
    
    /// Follow-up date for calendar reminder
    var followUpDate: Date?
    
    /// How the lead was captured
    var captureMethod: LeadCaptureMethod = .manual
    
    /// Raw input (transcription, OCR text, etc.)
    var rawInput: String?
    
    // User preferences for save actions
    var shouldCreateContact: Bool = true
    var shouldScheduleReminder: Bool = false
    var shouldSendEmailSummary: Bool = false
    var emailSummaryRecipient: String?
    
    // Result tracking
    var createdContactId: String?
    var createdEventId: String?
    
    /// Convert to dictionary for gateway transmission
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "company": company,
            "title": title,
            "phone": phone,
            "email": email,
            "notes": notes,
            "captureMethod": captureMethod.rawValue
        ]
        
        if let followUpDate = followUpDate {
            dict["followUpDate"] = ISO8601DateFormatter().string(from: followUpDate)
        }
        if let rawInput = rawInput {
            dict["rawInput"] = rawInput
        }
        if let contactId = createdContactId {
            dict["createdContactId"] = contactId
        }
        if let eventId = createdEventId {
            dict["createdEventId"] = eventId
        }
        
        return dict
    }
}

// MARK: - Supporting Types

/// How a lead was captured.
/// Raw values must match backend VALID_CAPTURE_METHODS in ios-lead.ts
enum LeadCaptureMethod: String, Codable {
    case voiceNote = "voice_note"
    case businessCard = "business_card"
    case callFollowUp = "call_followup"  // Note: no underscore before "up" to match backend
    case manual = "manual"
    
    var displayName: String {
        switch self {
        case .voiceNote: return "Voice Note"
        case .businessCard: return "Business Card"
        case .callFollowUp: return "Call Follow-up"
        case .manual: return "Manual Entry"
        }
    }
}

/// Current state of the lead capture workflow.
enum LeadCaptureState: Equatable {
    case idle
    case parsingVoiceNote
    case processingBusinessCard
    case manualEntry
    case saving
    case error(String)
    
    var isLoading: Bool {
        switch self {
        case .parsingVoiceNote, .processingBusinessCard, .saving:
            return true
        default:
            return false
        }
    }
}

/// Result of a lead capture operation.
enum LeadCaptureResult: Equatable {
    case success(LeadData, LeadCaptureActions)
    case failed(LeadCaptureError)
    case cancelled
}

/// Actions taken during lead save.
struct LeadCaptureActions: Codable, Equatable {
    var contactCreated: Bool = false
    var contactError: String?
    var reminderScheduled: Bool = false
    var reminderError: String?
    var emailComposed: Bool = false
    var emailError: String?
    var sentToGateway: Bool = false
}

/// Errors that can occur during lead capture.
enum LeadCaptureError: Error, Equatable, LocalizedError {
    case missingName
    case ocrFailed(String)
    case aiParsingFailed(String)
    case permissionDenied(String)
    case saveFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .missingName:
            return "Name is required to save a lead"
        case .ocrFailed(let detail):
            return "Failed to read business card: \(detail)"
        case .aiParsingFailed(let detail):
            return "Failed to parse voice note: \(detail)"
        case .permissionDenied(let detail):
            return "Permission denied: \(detail)"
        case .saveFailed(let detail):
            return "Failed to save lead: \(detail)"
        }
    }
}
