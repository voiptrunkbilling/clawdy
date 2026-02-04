import Foundation
import EventKit

/// Service for calendar operations on the device.
/// Provides authorization management and calendar access for Clawdy capabilities.
@MainActor
class CalendarService: ObservableObject {
    static let shared = CalendarService()
    
    // MARK: - Published Properties
    
    /// Current authorization status for calendar access
    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    
    /// Whether calendar access is authorized
    var isAuthorized: Bool {
        authorizationStatus == .fullAccess || authorizationStatus == .authorized
    }
    
    // MARK: - Properties
    
    private let eventStore = EKEventStore()
    
    // MARK: - Initialization
    
    private init() {
        refreshAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    /// Request calendar access authorization.
    /// - Returns: Whether authorization was granted
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }
            
            await MainActor.run {
                refreshAuthorizationStatus()
            }
            
            print("[CalendarService] Authorization \(granted ? "granted" : "denied")")
            return granted
        } catch {
            print("[CalendarService] Authorization error: \(error)")
            return false
        }
    }
    
    /// Refresh the current authorization status.
    func refreshAuthorizationStatus() {
        if #available(iOS 17.0, *) {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        } else {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }
    }
    
    // MARK: - Calendar Operations
    
    /// Get calendars available for events.
    func getCalendars() -> [EKCalendar] {
        guard isAuthorized else { return [] }
        return eventStore.calendars(for: .event)
    }
    
    /// Get a calendar by its identifier.
    /// - Parameter identifier: The calendar identifier
    /// - Returns: The calendar if found
    func getCalendar(byIdentifier identifier: String) -> EKCalendar? {
        guard isAuthorized else { return nil }
        return eventStore.calendar(withIdentifier: identifier)
    }
    
    /// Get events within a date range.
    func getEvents(from startDate: Date, to endDate: Date, calendars: [EKCalendar]? = nil) -> [EKEvent] {
        guard isAuthorized else { return [] }
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        return eventStore.events(matching: predicate)
    }
    
    /// Create a new event.
    /// - Parameters:
    ///   - title: Event title
    ///   - startDate: Event start date
    ///   - endDate: Event end date
    ///   - notes: Optional notes
    ///   - calendar: Target calendar (uses default if nil)
    /// - Returns: The created event identifier, or nil if failed
    func createEvent(title: String, startDate: Date, endDate: Date, notes: String? = nil, calendar: EKCalendar? = nil) throws -> String? {
        guard isAuthorized else {
            throw CalendarError.notAuthorized
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        event.calendar = calendar ?? eventStore.defaultCalendarForNewEvents
        
        try eventStore.save(event, span: .thisEvent)
        print("[CalendarService] Created event: \(title)")
        return event.eventIdentifier
    }
    
    /// Update an existing event.
    /// - Parameters:
    ///   - eventId: The event identifier to update
    ///   - title: New title (nil to keep existing)
    ///   - startDate: New start date (nil to keep existing)
    ///   - endDate: New end date (nil to keep existing)
    ///   - notes: New notes (nil to keep existing)
    func updateEvent(eventId: String, title: String? = nil, startDate: Date? = nil, endDate: Date? = nil, notes: String? = nil) throws {
        guard isAuthorized else {
            throw CalendarError.notAuthorized
        }
        
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarError.eventNotFound
        }
        
        if let newTitle = title {
            event.title = newTitle
        }
        if let newStart = startDate {
            event.startDate = newStart
        }
        if let newEnd = endDate {
            event.endDate = newEnd
        }
        if let newNotes = notes {
            event.notes = newNotes
        }
        
        do {
            try eventStore.save(event, span: .thisEvent)
            print("[CalendarService] Updated event: \(event.title ?? eventId)")
        } catch {
            throw CalendarError.saveFailed(error)
        }
    }
    
    /// Delete an event.
    /// - Parameter eventId: The event identifier to delete
    func deleteEvent(eventId: String) throws {
        guard isAuthorized else {
            throw CalendarError.notAuthorized
        }
        
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarError.eventNotFound
        }
        
        do {
            try eventStore.remove(event, span: .thisEvent)
            print("[CalendarService] Deleted event: \(event.title ?? eventId)")
        } catch {
            throw CalendarError.saveFailed(error)
        }
    }
    
    /// Get a single event by identifier.
    /// - Parameter eventId: The event identifier
    /// - Returns: The event if found
    func getEvent(eventId: String) -> EKEvent? {
        guard isAuthorized else { return nil }
        return eventStore.event(withIdentifier: eventId)
    }
    
    // MARK: - Errors
    
    enum CalendarError: LocalizedError {
        case notAuthorized
        case eventNotFound
        case saveFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Calendar access not authorized"
            case .eventNotFound:
                return "Event not found"
            case .saveFailed(let error):
                return "Failed to save event: \(error.localizedDescription)"
            }
        }
    }
}
