import Foundation
import UIKit

/// Handles node capability invocations from the Clawdbot gateway.
///
/// ## Unified WebSocket Architecture
/// All communication with the gateway flows through a single WebSocket connection
/// on port 18789. The gateway can invoke node capabilities via `node.invoke.request`
/// events, and this handler processes those invocations.
///
/// ## Supported Capabilities
/// | Capability           | Description                          |
/// |----------------------|--------------------------------------|
/// | chat.push            | Agent-initiated message delivery     |
/// | camera.list          | List available cameras               |
/// | camera.snap          | Capture a photo                      |
/// | camera.clip          | Record a video clip                  |
/// | location.get         | Get current GPS location             |
/// | system.notify        | Show a local notification            |
/// | calendar.create      | Create a calendar event              |
/// | calendar.read        | Read calendar events                 |
/// | calendar.update      | Update a calendar event              |
/// | calendar.delete      | Delete a calendar event              |
/// | contacts.search      | Search contacts                      |
/// | contacts.create      | Create a contact                     |
/// | contacts.update      | Update a contact                     |
/// | phone.call           | Initiate a phone call                |
/// | phone.sms            | Compose an SMS message               |
/// | email.compose        | Compose an email                     |
/// | lead.capture         | Capture lead data                    |
/// | lead.parseVoiceNote  | Parse voice note for lead data       |
@MainActor
class NodeCapabilityHandler {
    // MARK: - Capability Handler Types
    
    /// Handler for chat.push capability - appends agent messages to transcript.
    /// Used for agent-initiated message delivery (e.g., cron jobs, async notifications).
    var onChatPush: ((_ text: String, _ speak: Bool) async -> String?)?
    
    /// Handler for camera.list capability - returns available cameras
    var onCameraList: (() async -> CameraListResult)?
    
    /// Handler for camera.snap capability - captures a photo
    var onCameraSnap: ((_ params: CameraSnapParams) async -> CameraSnapResult)?
    
    /// Handler for camera.clip capability - records a video clip
    var onCameraClip: ((_ params: CameraClipParams) async -> CameraClipResult)?
    
    /// Handler for location.get capability - returns current location
    var onLocationGet: ((_ params: LocationGetParams) async -> LocationGetResult)?
    
    /// Handler for system.notify capability - shows a notification
    /// Returns result indicating success, permission denied, or error
    var onSystemNotify: ((_ params: SystemNotifyParams) async -> SystemNotifyResult)?
    
    // MARK: - Calendar Handlers
    
    /// Handler for calendar.create capability - creates a calendar event
    var onCalendarCreate: ((_ params: CalendarCreateParams) async -> CalendarCreateResult)?
    
    /// Handler for calendar.read capability - reads calendar events
    var onCalendarRead: ((_ params: CalendarReadParams) async -> CalendarReadResult)?
    
    /// Handler for calendar.update capability - updates a calendar event
    var onCalendarUpdate: ((_ params: CalendarUpdateParams) async -> CalendarUpdateResult)?
    
    /// Handler for calendar.delete capability - deletes a calendar event
    var onCalendarDelete: ((_ params: CalendarDeleteParams) async -> CalendarDeleteResult)?
    
    // MARK: - Contacts Handlers
    
    /// Handler for contacts.search capability - searches contacts
    var onContactsSearch: ((_ params: ContactsSearchParams) async -> ContactsSearchResult)?
    
    /// Handler for contacts.create capability - creates a contact
    var onContactsCreate: ((_ params: ContactsCreateParams) async -> ContactsCreateResult)?
    
    /// Handler for contacts.update capability - updates a contact
    var onContactsUpdate: ((_ params: ContactsUpdateParams) async -> ContactsUpdateResult)?
    
    // MARK: - Phone Handlers
    
    /// Handler for phone.call capability - initiates a phone call
    var onPhoneCall: ((_ params: PhoneCallParams) async -> PhoneCallResult)?
    
    /// Handler for phone.sms capability - sends an SMS message
    var onPhoneSMS: ((_ params: PhoneSMSParams) async -> PhoneSMSResult)?
    
    // MARK: - Email Handlers
    
    /// Handler for email.compose capability - composes an email
    var onEmailCompose: ((_ params: EmailComposeParams) async -> EmailComposeResult)?
    
    // MARK: - Lead Capture Handlers
    
    /// Handler for lead.capture capability - captures a lead
    var onLeadCapture: ((_ params: LeadCaptureParams) async -> LeadCaptureCapabilityResult)?
    
    /// Handler for lead.parseVoiceNote capability - parses voice note for lead data
    var onLeadParseVoiceNote: ((_ params: LeadParseVoiceNoteParams) async -> LeadParseVoiceNoteResult)?
    
    // MARK: - JSON Coding
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Invoke Routing
    
    /// Handle an invoke request from the gateway.
    /// Parses the command and params, routes to the appropriate handler, and returns a response.
    /// - Parameter request: The invoke request from the gateway
    /// - Returns: The invoke response to send back to the gateway
    func handleInvoke(_ request: BridgeInvokeRequest) async -> BridgeInvokeResponse {
        print("[NodeCapabilityHandler] Handling invoke: \(request.command)")
        
        // Check if app is in background (many capabilities require foreground)
        let isBackground = UIApplication.shared.applicationState == .background
        
        switch request.command {
        case "chat.push":
            return await handleChatPush(request: request)
            
        case "camera.list":
            return await handleCameraList(request: request, isBackground: isBackground)
            
        case "camera.snap":
            return await handleCameraSnap(request: request, isBackground: isBackground)
            
        case "camera.clip":
            return await handleCameraClip(request: request, isBackground: isBackground)
            
        case "location.get":
            return await handleLocationGet(request: request, isBackground: isBackground)
            
        case "system.notify":
            return await handleSystemNotify(request: request)
            
        case "calendar.create":
            return await handleCalendarCreate(request: request)
            
        case "calendar.read":
            return await handleCalendarRead(request: request)
            
        case "calendar.update":
            return await handleCalendarUpdate(request: request)
            
        case "calendar.delete":
            return await handleCalendarDelete(request: request)
            
        case "contacts.search":
            return await handleContactsSearch(request: request)
            
        case "contacts.create":
            return await handleContactsCreate(request: request)
            
        case "contacts.update":
            return await handleContactsUpdate(request: request)
            
        case "phone.call":
            return await handlePhoneCall(request: request, isBackground: isBackground)
            
        case "phone.sms":
            return await handlePhoneSMS(request: request, isBackground: isBackground)
            
        case "email.compose":
            return await handleEmailCompose(request: request, isBackground: isBackground)
            
        case "lead.capture":
            return await handleLeadCapture(request: request, isBackground: isBackground)
            
        case "lead.parseVoiceNote":
            return await handleLeadParseVoiceNote(request: request)
            
        default:
            return makeErrorResponse(
                id: request.id,
                code: .invalidRequest,
                message: "Unknown command: \(request.command)"
            )
        }
    }
    
    // MARK: - Chat Push Handler (Fallback Only)
    
    /// Handle chat.push - agent-initiated message delivery.
    /// Called when the gateway pushes a message to the device without a user prompt
    /// (e.g., cron jobs, background tasks, async notifications).
    private func handleChatPush(request: BridgeInvokeRequest) async -> BridgeInvokeResponse {
        // Parse params
        struct ChatPushParams: Codable {
            let text: String
            let speak: Bool?
        }
        
        guard let paramsJSON = request.paramsJSON,
              let paramsData = paramsJSON.data(using: .utf8),
              let params = try? decoder.decode(ChatPushParams.self, from: paramsData) else {
            return makeErrorResponse(
                id: request.id,
                code: .invalidRequest,
                message: "Invalid chat.push params: expected {text: string, speak?: boolean}"
            )
        }
        
        guard let handler = onChatPush else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "chat.push handler not registered"
            )
        }
        
        let speak = params.speak ?? true
        let messageId = await handler(params.text, speak)
        
        // Return success with message ID
        struct ChatPushResult: Codable {
            let messageId: String?
        }
        let result = ChatPushResult(messageId: messageId)
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    // MARK: - Camera Handlers
    
    private func handleCameraList(request: BridgeInvokeRequest, isBackground: Bool) async -> BridgeInvokeResponse {
        // camera.list can work in background (doesn't use camera hardware)
        
        guard let handler = onCameraList else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "camera.list handler not registered"
            )
        }
        
        let result = await handler()
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    private func handleCameraSnap(request: BridgeInvokeRequest, isBackground: Bool) async -> BridgeInvokeResponse {
        if isBackground {
            return makeErrorResponse(
                id: request.id,
                code: .backgroundUnavailable,
                message: "Camera requires app to be in foreground"
            )
        }
        
        let params: CameraSnapParams
        if let paramsJSON = request.paramsJSON,
           let paramsData = paramsJSON.data(using: .utf8),
           let decoded = try? decoder.decode(CameraSnapParams.self, from: paramsData) {
            params = decoded
        } else {
            params = CameraSnapParams(facing: nil, maxWidth: nil, quality: nil, delayMs: nil)
        }
        
        guard let handler = onCameraSnap else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "camera.snap handler not registered"
            )
        }
        
        let result = await handler(params)
        
        if let error = result.error {
            return makeErrorResponse(id: request.id, code: .unavailable, message: error)
        }
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    private func handleCameraClip(request: BridgeInvokeRequest, isBackground: Bool) async -> BridgeInvokeResponse {
        if isBackground {
            return makeErrorResponse(
                id: request.id,
                code: .backgroundUnavailable,
                message: "Camera requires app to be in foreground"
            )
        }
        
        let params: CameraClipParams
        if let paramsJSON = request.paramsJSON,
           let paramsData = paramsJSON.data(using: .utf8),
           let decoded = try? decoder.decode(CameraClipParams.self, from: paramsData) {
            params = decoded
        } else {
            params = CameraClipParams(facing: nil, durationMs: nil, includeAudio: nil)
        }
        
        guard let handler = onCameraClip else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "camera.clip handler not registered"
            )
        }
        
        let result = await handler(params)
        
        if let error = result.error {
            return makeErrorResponse(id: request.id, code: .unavailable, message: error)
        }
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    // MARK: - Location Handler
    
    private func handleLocationGet(request: BridgeInvokeRequest, isBackground: Bool) async -> BridgeInvokeResponse {
        // Location can work in background if "always" permission is granted
        // The handler will check permissions and return appropriate error
        
        let params: LocationGetParams
        if let paramsJSON = request.paramsJSON,
           let paramsData = paramsJSON.data(using: .utf8),
           let decoded = try? decoder.decode(LocationGetParams.self, from: paramsData) {
            params = decoded
        } else {
            // Use defaults if no params provided
            params = LocationGetParams()
        }
        
        guard let handler = onLocationGet else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "location.get handler not registered"
            )
        }
        
        let result = await handler(params)
        
        if let error = result.error {
            return makeErrorResponse(id: request.id, code: .unavailable, message: error)
        }
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    // MARK: - System Notify Handler
    
    private func handleSystemNotify(request: BridgeInvokeRequest) async -> BridgeInvokeResponse {
        guard let paramsJSON = request.paramsJSON,
              let paramsData = paramsJSON.data(using: .utf8),
              let params = try? decoder.decode(SystemNotifyParams.self, from: paramsData) else {
            return makeErrorResponse(
                id: request.id,
                code: .invalidRequest,
                message: "Invalid system.notify params: expected {title: string, body: string, sound?: boolean, priority?: string}"
            )
        }
        
        guard let handler = onSystemNotify else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "system.notify handler not registered"
            )
        }
        
        let result = await handler(params)
        
        // Return appropriate response based on result
        if result.permissionDenied {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "Notification permission denied. Enable notifications in Settings."
            )
        }
        
        if let error = result.error {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: error
            )
        }
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    // MARK: - Calendar Handlers
    
    private func handleCalendarCreate(request: BridgeInvokeRequest) async -> BridgeInvokeResponse {
        guard let paramsJSON = request.paramsJSON,
              let paramsData = paramsJSON.data(using: .utf8),
              let params = try? decoder.decode(CalendarCreateParams.self, from: paramsData) else {
            return makeErrorResponse(
                id: request.id,
                code: .invalidRequest,
                message: "Invalid calendar.create params: expected {title: string, startDate: string, endDate: string, notes?: string, calendarId?: string}"
            )
        }
        
        guard let handler = onCalendarCreate else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "calendar.create handler not registered"
            )
        }
        
        let result = await handler(params)
        
        if let error = result.error {
            return makeErrorResponse(id: request.id, code: .unavailable, message: error)
        }
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    private func handleCalendarRead(request: BridgeInvokeRequest) async -> BridgeInvokeResponse {
        guard let paramsJSON = request.paramsJSON,
              let paramsData = paramsJSON.data(using: .utf8),
              let params = try? decoder.decode(CalendarReadParams.self, from: paramsData) else {
            return makeErrorResponse(
                id: request.id,
                code: .invalidRequest,
                message: "Invalid calendar.read params: expected {startDate: string, endDate: string, calendarId?: string}"
            )
        }
        
        guard let handler = onCalendarRead else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "calendar.read handler not registered"
            )
        }
        
        let result = await handler(params)
        
        if let error = result.error {
            return makeErrorResponse(id: request.id, code: .unavailable, message: error)
        }
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    private func handleCalendarUpdate(request: BridgeInvokeRequest) async -> BridgeInvokeResponse {
        guard let paramsJSON = request.paramsJSON,
              let paramsData = paramsJSON.data(using: .utf8),
              let params = try? decoder.decode(CalendarUpdateParams.self, from: paramsData) else {
            return makeErrorResponse(
                id: request.id,
                code: .invalidRequest,
                message: "Invalid calendar.update params: expected {eventId: string, title?: string, startDate?: string, endDate?: string, notes?: string}"
            )
        }
        
        guard let handler = onCalendarUpdate else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "calendar.update handler not registered"
            )
        }
        
        let result = await handler(params)
        
        if let error = result.error {
            return makeErrorResponse(id: request.id, code: .unavailable, message: error)
        }
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    private func handleCalendarDelete(request: BridgeInvokeRequest) async -> BridgeInvokeResponse {
        guard let paramsJSON = request.paramsJSON,
              let paramsData = paramsJSON.data(using: .utf8),
              let params = try? decoder.decode(CalendarDeleteParams.self, from: paramsData) else {
            return makeErrorResponse(
                id: request.id,
                code: .invalidRequest,
                message: "Invalid calendar.delete params: expected {eventId: string, confirmationToken?: string}"
            )
        }
        
        guard let handler = onCalendarDelete else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "calendar.delete handler not registered"
            )
        }
        
        let result = await handler(params)
        
        if let error = result.error {
            return makeErrorResponse(id: request.id, code: .unavailable, message: error)
        }
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    // MARK: - Contacts Handlers
    
    private func handleContactsSearch(request: BridgeInvokeRequest) async -> BridgeInvokeResponse {
        guard let paramsJSON = request.paramsJSON,
              let paramsData = paramsJSON.data(using: .utf8),
              let params = try? decoder.decode(ContactsSearchParams.self, from: paramsData) else {
            return makeErrorResponse(
                id: request.id,
                code: .invalidRequest,
                message: "Invalid contacts.search params: expected {query: string}"
            )
        }
        
        guard let handler = onContactsSearch else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "contacts.search handler not registered"
            )
        }
        
        let result = await handler(params)
        
        if let error = result.error {
            return makeErrorResponse(id: request.id, code: .unavailable, message: error)
        }
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    private func handleContactsCreate(request: BridgeInvokeRequest) async -> BridgeInvokeResponse {
        guard let paramsJSON = request.paramsJSON,
              let paramsData = paramsJSON.data(using: .utf8),
              let params = try? decoder.decode(ContactsCreateParams.self, from: paramsData) else {
            return makeErrorResponse(
                id: request.id,
                code: .invalidRequest,
                message: "Invalid contacts.create params: expected {givenName: string, familyName: string, phoneNumber?: string, email?: string}"
            )
        }
        
        guard let handler = onContactsCreate else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "contacts.create handler not registered"
            )
        }
        
        let result = await handler(params)
        
        if let error = result.error {
            return makeErrorResponse(id: request.id, code: .unavailable, message: error)
        }
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    private func handleContactsUpdate(request: BridgeInvokeRequest) async -> BridgeInvokeResponse {
        guard let paramsJSON = request.paramsJSON,
              let paramsData = paramsJSON.data(using: .utf8),
              let params = try? decoder.decode(ContactsUpdateParams.self, from: paramsData) else {
            return makeErrorResponse(
                id: request.id,
                code: .invalidRequest,
                message: "Invalid contacts.update params: expected {contactId: string, givenName?: string, familyName?: string, phoneNumber?: string, email?: string}"
            )
        }
        
        guard let handler = onContactsUpdate else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "contacts.update handler not registered"
            )
        }
        
        let result = await handler(params)
        
        if let error = result.error {
            return makeErrorResponse(id: request.id, code: .unavailable, message: error)
        }
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    // MARK: - Phone Handlers
    
    private func handlePhoneCall(request: BridgeInvokeRequest, isBackground: Bool) async -> BridgeInvokeResponse {
        if isBackground {
            return makeErrorResponse(
                id: request.id,
                code: .backgroundUnavailable,
                message: "Phone calls require app to be in foreground"
            )
        }
        
        guard let paramsJSON = request.paramsJSON,
              let paramsData = paramsJSON.data(using: .utf8),
              let params = try? decoder.decode(PhoneCallParams.self, from: paramsData) else {
            return makeErrorResponse(
                id: request.id,
                code: .invalidRequest,
                message: "Invalid phone.call params: expected {number: string}"
            )
        }
        
        guard let handler = onPhoneCall else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "phone.call handler not registered"
            )
        }
        
        let result = await handler(params)
        
        if let error = result.error {
            return makeErrorResponse(id: request.id, code: .unavailable, message: error)
        }
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    private func handlePhoneSMS(request: BridgeInvokeRequest, isBackground: Bool) async -> BridgeInvokeResponse {
        if isBackground {
            return makeErrorResponse(
                id: request.id,
                code: .backgroundUnavailable,
                message: "SMS requires app to be in foreground"
            )
        }
        
        guard let paramsJSON = request.paramsJSON,
              let paramsData = paramsJSON.data(using: .utf8),
              let params = try? decoder.decode(PhoneSMSParams.self, from: paramsData) else {
            return makeErrorResponse(
                id: request.id,
                code: .invalidRequest,
                message: "Invalid phone.sms params: expected {number: string, body?: string}"
            )
        }
        
        guard let handler = onPhoneSMS else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "phone.sms handler not registered"
            )
        }
        
        let result = await handler(params)
        
        if let error = result.error {
            return makeErrorResponse(id: request.id, code: .unavailable, message: error)
        }
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    // MARK: - Email Handlers
    
    private func handleEmailCompose(request: BridgeInvokeRequest, isBackground: Bool) async -> BridgeInvokeResponse {
        if isBackground {
            return makeErrorResponse(
                id: request.id,
                code: .backgroundUnavailable,
                message: "Email compose requires app to be in foreground"
            )
        }
        
        guard let paramsJSON = request.paramsJSON,
              let paramsData = paramsJSON.data(using: .utf8),
              let params = try? decoder.decode(EmailComposeParams.self, from: paramsData) else {
            return makeErrorResponse(
                id: request.id,
                code: .invalidRequest,
                message: "Invalid email.compose params: expected {to: string[], subject?: string, body?: string}"
            )
        }
        
        guard let handler = onEmailCompose else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "email.compose handler not registered"
            )
        }
        
        let result = await handler(params)
        
        if let error = result.error {
            return makeErrorResponse(id: request.id, code: .unavailable, message: error)
        }
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    // MARK: - Lead Capture Handler
    
    private func handleLeadCapture(request: BridgeInvokeRequest, isBackground: Bool) async -> BridgeInvokeResponse {
        if isBackground {
            return makeErrorResponse(
                id: request.id,
                code: .backgroundUnavailable,
                message: "Lead capture requires app to be in foreground"
            )
        }
        
        guard let paramsJSON = request.paramsJSON,
              let paramsData = paramsJSON.data(using: .utf8),
              let params = try? decoder.decode(LeadCaptureParams.self, from: paramsData) else {
            return makeErrorResponse(
                id: request.id,
                code: .invalidRequest,
                message: "Invalid lead.capture params: expected {name: string, ...}"
            )
        }
        
        guard let handler = onLeadCapture else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "lead.capture handler not registered"
            )
        }
        
        let result = await handler(params)
        
        if let error = result.error {
            return makeErrorResponse(id: request.id, code: .unavailable, message: error)
        }
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    private func handleLeadParseVoiceNote(request: BridgeInvokeRequest) async -> BridgeInvokeResponse {
        guard let paramsJSON = request.paramsJSON,
              let paramsData = paramsJSON.data(using: .utf8),
              let params = try? decoder.decode(LeadParseVoiceNoteParams.self, from: paramsData) else {
            return makeErrorResponse(
                id: request.id,
                code: .invalidRequest,
                message: "Invalid lead.parseVoiceNote params: expected {transcription: string}"
            )
        }
        
        guard let handler = onLeadParseVoiceNote else {
            return makeErrorResponse(
                id: request.id,
                code: .unavailable,
                message: "lead.parseVoiceNote handler not registered"
            )
        }
        
        let result = await handler(params)
        
        if let error = result.error {
            return makeErrorResponse(id: request.id, code: .unavailable, message: error)
        }
        
        return makeSuccessResponse(id: request.id, payload: result)
    }
    
    // MARK: - Response Helpers
    
    private func makeSuccessResponse<T: Codable>(id: String, payload: T) -> BridgeInvokeResponse {
        let payloadJSON: String?
        if let data = try? encoder.encode(payload),
           let json = String(data: data, encoding: .utf8) {
            payloadJSON = json
        } else {
            payloadJSON = nil
        }
        
        return BridgeInvokeResponse(
            type: "invoke-res",
            id: id,
            ok: true,
            payloadJSON: payloadJSON,
            error: nil
        )
    }
    
    private func makeErrorResponse(
        id: String,
        code: BridgeNodeErrorCode,
        message: String
    ) -> BridgeInvokeResponse {
        return BridgeInvokeResponse(
            type: "invoke-res",
            id: id,
            ok: false,
            payloadJSON: nil,
            error: BridgeNodeError(code: code, message: message)
        )
    }
}

// MARK: - Capability Parameter & Result Types

/// Parameters for camera.snap capability
struct CameraSnapParams: Codable {
    let facing: String?  // "front" or "back", default "back"
    let maxWidth: Int?   // Maximum width in pixels
    let quality: Double? // JPEG quality 0.0-1.0, default 0.8
    let delayMs: Int?    // Delay before capture in milliseconds
    
    var facingValue: CameraFacing {
        switch facing?.lowercased() {
        case "front": return .front
        default: return .back
        }
    }
}

/// Camera facing direction
enum CameraFacing: String, Codable {
    case front
    case back
}

/// Result of camera.snap capability
struct CameraSnapResult: Codable {
    let format: String?
    let base64: String?
    let width: Int?
    let height: Int?
    let error: String?
}

/// Parameters for camera.clip capability
struct CameraClipParams: Codable {
    let facing: String?      // "front" or "back", default "back"
    let durationMs: Int?     // Duration in milliseconds, default 5000
    let includeAudio: Bool?  // Whether to include audio, default true
    
    var facingValue: CameraFacing {
        switch facing?.lowercased() {
        case "front": return .front
        default: return .back
        }
    }
    
    var durationSeconds: TimeInterval {
        let ms = durationMs ?? 5000
        return TimeInterval(ms) / 1000.0
    }
}

/// Result of camera.clip capability
struct CameraClipResult: Codable {
    let format: String?
    let base64: String?
    let durationMs: Int?
    let hasAudio: Bool?
    let error: String?
}

/// Result of camera.list capability
struct CameraListResult: Codable {
    let cameras: [CameraInfo]
}

/// Information about an available camera
struct CameraInfo: Codable {
    let id: String       // Device unique ID
    let name: String     // Human-readable name
    let facing: String   // "front" or "back"
    let isDefault: Bool
}

/// Parameters for location.get capability
struct LocationGetParams: Codable {
    let desiredAccuracy: String?  // "best", "nearestTenMeters", "hundredMeters", "kilometer", "threeKilometers"
    let maxAgeMs: Int?            // Maximum age of cached location in milliseconds
    let timeoutMs: Int?           // Timeout for location request in milliseconds
    
    init(desiredAccuracy: String? = nil, maxAgeMs: Int? = nil, timeoutMs: Int? = nil) {
        self.desiredAccuracy = desiredAccuracy
        self.maxAgeMs = maxAgeMs
        self.timeoutMs = timeoutMs
    }
}

/// Result of location.get capability
struct LocationGetResult: Codable {
    let latitude: Double?
    let longitude: Double?
    let accuracy: Double?         // Horizontal accuracy in meters
    let altitude: Double?
    let altitudeAccuracy: Double? // Vertical accuracy in meters
    let speed: Double?            // Speed in m/s
    let heading: Double?          // Heading in degrees (0-360)
    let timestamp: String?        // ISO 8601 timestamp
    let error: String?
}

/// Parameters for system.notify capability
struct SystemNotifyParams: Codable {
    let title: String
    let body: String
    let sound: Bool?              // Play sound, default true
    let priority: String?         // "passive", "active", "timeSensitive"
}

/// Result of system.notify capability
struct SystemNotifyResult: Codable {
    let scheduled: Bool
    let permissionDenied: Bool
    let error: String?
    
    static let success = SystemNotifyResult(scheduled: true, permissionDenied: false, error: nil)
    static let permissionDenied = SystemNotifyResult(scheduled: false, permissionDenied: true, error: nil)
    static func failed(_ message: String) -> SystemNotifyResult {
        SystemNotifyResult(scheduled: false, permissionDenied: false, error: message)
    }
}

// MARK: - Calendar Capability Types

/// Parameters for calendar.create capability
struct CalendarCreateParams: Codable {
    let title: String
    let startDate: String  // ISO 8601 format
    let endDate: String    // ISO 8601 format
    let notes: String?
    let calendarId: String?
}

/// Result of calendar.create capability
struct CalendarCreateResult: Codable {
    let eventId: String?
    let error: String?
    
    static func success(eventId: String) -> CalendarCreateResult {
        CalendarCreateResult(eventId: eventId, error: nil)
    }
    
    static func failed(_ message: String) -> CalendarCreateResult {
        CalendarCreateResult(eventId: nil, error: message)
    }
}

/// Parameters for calendar.read capability
struct CalendarReadParams: Codable {
    let startDate: String  // ISO 8601 format
    let endDate: String    // ISO 8601 format
    let calendarId: String?
}

/// Result of calendar.read capability
struct CalendarReadResult: Codable {
    let events: [CalendarEventInfo]
    let error: String?
    
    static func success(events: [CalendarEventInfo]) -> CalendarReadResult {
        CalendarReadResult(events: events, error: nil)
    }
    
    static func failed(_ message: String) -> CalendarReadResult {
        CalendarReadResult(events: [], error: message)
    }
}

/// Information about a calendar event
struct CalendarEventInfo: Codable {
    let eventId: String
    let title: String
    let startDate: String  // ISO 8601 format
    let endDate: String    // ISO 8601 format
    let notes: String?
    let calendarId: String
    let calendarTitle: String
}

/// Parameters for calendar.update capability
struct CalendarUpdateParams: Codable {
    let eventId: String
    let title: String?
    let startDate: String?  // ISO 8601 format
    let endDate: String?    // ISO 8601 format
    let notes: String?
}

/// Result of calendar.update capability
struct CalendarUpdateResult: Codable {
    let updated: Bool
    let error: String?
    
    static let success = CalendarUpdateResult(updated: true, error: nil)
    
    static func failed(_ message: String) -> CalendarUpdateResult {
        CalendarUpdateResult(updated: false, error: message)
    }
}

/// Parameters for calendar.delete capability
struct CalendarDeleteParams: Codable {
    let eventId: String
    let confirmationToken: String?  // Required for destructive operations
}

/// Result of calendar.delete capability
struct CalendarDeleteResult: Codable {
    let deleted: Bool
    let requiresConfirmation: Bool
    let confirmationToken: String?
    let error: String?
    
    static let success = CalendarDeleteResult(deleted: true, requiresConfirmation: false, confirmationToken: nil, error: nil)
    
    static func requiresConfirmation(token: String) -> CalendarDeleteResult {
        CalendarDeleteResult(deleted: false, requiresConfirmation: true, confirmationToken: token, error: nil)
    }
    
    static func failed(_ message: String) -> CalendarDeleteResult {
        CalendarDeleteResult(deleted: false, requiresConfirmation: false, confirmationToken: nil, error: message)
    }
}

// MARK: - Contacts Capability Types

/// Parameters for contacts.search capability
struct ContactsSearchParams: Codable {
    let query: String
}

/// Result of contacts.search capability
struct ContactsSearchResult: Codable {
    let contacts: [ContactInfo]
    let error: String?
    
    static func success(contacts: [ContactInfo]) -> ContactsSearchResult {
        ContactsSearchResult(contacts: contacts, error: nil)
    }
    
    static func failed(_ message: String) -> ContactsSearchResult {
        ContactsSearchResult(contacts: [], error: message)
    }
}

/// Information about a contact
struct ContactInfo: Codable {
    let contactId: String
    let givenName: String
    let familyName: String
    let phoneNumbers: [String]
    let emails: [String]
    let organization: String?
}

/// Parameters for contacts.create capability
struct ContactsCreateParams: Codable {
    let givenName: String
    let familyName: String
    let phoneNumber: String?
    let email: String?
}

/// Result of contacts.create capability
struct ContactsCreateResult: Codable {
    let contactId: String?
    let error: String?
    
    static func success(contactId: String) -> ContactsCreateResult {
        ContactsCreateResult(contactId: contactId, error: nil)
    }
    
    static func failed(_ message: String) -> ContactsCreateResult {
        ContactsCreateResult(contactId: nil, error: message)
    }
}

/// Parameters for contacts.update capability
struct ContactsUpdateParams: Codable {
    let contactId: String
    let givenName: String?
    let familyName: String?
    let phoneNumber: String?
    let email: String?
}

/// Result of contacts.update capability
struct ContactsUpdateResult: Codable {
    let updated: Bool
    let error: String?
    
    static let success = ContactsUpdateResult(updated: true, error: nil)
    
    static func failed(_ message: String) -> ContactsUpdateResult {
        ContactsUpdateResult(updated: false, error: message)
    }
}

// MARK: - Phone Capability Types

/// Parameters for phone.call capability
struct PhoneCallParams: Codable {
    let number: String
}

/// Result of phone.call capability
struct PhoneCallResult: Codable {
    let initiated: Bool
    let error: String?
    
    static func success() -> PhoneCallResult {
        PhoneCallResult(initiated: true, error: nil)
    }
    
    static func failed(_ message: String) -> PhoneCallResult {
        PhoneCallResult(initiated: false, error: message)
    }
}

/// Parameters for phone.sms capability
struct PhoneSMSParams: Codable {
    let number: String
    let body: String?
}

/// Result of phone.sms capability
struct PhoneSMSResult: Codable {
    let composed: Bool
    let error: String?
    
    static func success() -> PhoneSMSResult {
        PhoneSMSResult(composed: true, error: nil)
    }
    
    static func failed(_ message: String) -> PhoneSMSResult {
        PhoneSMSResult(composed: false, error: message)
    }
}

// MARK: - Email Capability Types

/// Parameters for email.compose capability
struct EmailComposeParams: Codable {
    let to: [String]
    let subject: String?
    let body: String?
    let isHTML: Bool?
}

/// Result of email.compose capability
struct EmailComposeResult: Codable {
    let composed: Bool
    let error: String?
    
    static func success() -> EmailComposeResult {
        EmailComposeResult(composed: true, error: nil)
    }
    
    static func failed(_ message: String) -> EmailComposeResult {
        EmailComposeResult(composed: false, error: message)
    }
}

// MARK: - Lead Capture Capability Types

/// Parameters for lead.capture capability
struct LeadCaptureParams: Codable {
    let name: String
    let company: String?
    let title: String?
    let phone: String?
    let email: String?
    let notes: String?
    let followUpDate: String?
    let captureMethod: String?
    let rawInput: String?
    let createContact: Bool?
    let scheduleReminder: Bool?
    let sendEmailSummary: Bool?
    let emailSummaryRecipient: String?
}

/// Result of lead.capture capability
struct LeadCaptureCapabilityResult: Codable {
    let captured: Bool
    let leadId: String?
    let contactCreated: Bool?
    let reminderScheduled: Bool?
    let emailComposed: Bool?
    let error: String?
    
    static func success(
        leadId: String? = nil,
        contactCreated: Bool = false,
        reminderScheduled: Bool = false,
        emailComposed: Bool = false
    ) -> LeadCaptureCapabilityResult {
        LeadCaptureCapabilityResult(
            captured: true,
            leadId: leadId,
            contactCreated: contactCreated,
            reminderScheduled: reminderScheduled,
            emailComposed: emailComposed,
            error: nil
        )
    }
    
    static func failed(_ message: String) -> LeadCaptureCapabilityResult {
        LeadCaptureCapabilityResult(
            captured: false,
            leadId: nil,
            contactCreated: nil,
            reminderScheduled: nil,
            emailComposed: nil,
            error: message
        )
    }
}

/// Parameters for lead.parseVoiceNote capability
struct LeadParseVoiceNoteParams: Codable {
    let transcription: String
}

/// Result of lead.parseVoiceNote capability
struct LeadParseVoiceNoteResult: Codable {
    let parsed: Bool
    let name: String?
    let company: String?
    let title: String?
    let phone: String?
    let email: String?
    let notes: String?
    let error: String?
    
    static func success(
        name: String?,
        company: String?,
        title: String?,
        phone: String?,
        email: String?,
        notes: String?
    ) -> LeadParseVoiceNoteResult {
        LeadParseVoiceNoteResult(
            parsed: true,
            name: name,
            company: company,
            title: title,
            phone: phone,
            email: email,
            notes: notes,
            error: nil
        )
    }
    
    static func failed(_ message: String) -> LeadParseVoiceNoteResult {
        LeadParseVoiceNoteResult(
            parsed: false,
            name: nil,
            company: nil,
            title: nil,
            phone: nil,
            email: nil,
            notes: nil,
            error: message
        )
    }
}
