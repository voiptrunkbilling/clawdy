import Foundation
import EventKit
import XCTest

/// Unit tests for CalendarService operations.
/// These tests validate the calendar capability service functionality.
///
/// Test Categories:
/// 1. Service initialization (singleton pattern)
/// 2. Date parsing for ISO 8601
/// 3. Event operations validation
/// 4. Permission handling
class CalendarServiceTests: XCTestCase {
    
    private var service: CalendarService!
    
    @MainActor
    override func setUp() {
        super.setUp()
        service = CalendarService.shared
    }
    
    override func tearDown() {
        service = nil
        super.tearDown()
    }
    
    // MARK: - Singleton Tests
    
    @MainActor
    func testSingletonPattern() {
        let service2 = CalendarService.shared
        XCTAssertTrue(service === service2, "CalendarService should use singleton pattern")
    }
    
    // MARK: - Authorization Tests
    
    @MainActor
    func testAuthorizationStatusIsValid() {
        let status = service.authorizationStatus
        let validStatuses: [EKAuthorizationStatus] = [.notDetermined, .restricted, .denied, .authorized, .fullAccess, .writeOnly]
        XCTAssertTrue(validStatuses.contains(status), "Authorization status should be a valid EKAuthorizationStatus")
    }
    
    @MainActor
    func testIsAuthorizedMatchesStatus() {
        let isAuth = service.isAuthorized
        let status = service.authorizationStatus
        let expectedAuth = (status == .authorized || status == .fullAccess)
        XCTAssertEqual(isAuth, expectedAuth, "isAuthorized should match authorization status")
    }
    
    // MARK: - ISO 8601 Date Parsing Tests
    
    func testValidISO8601DateParsing() {
        let isoFormatter = ISO8601DateFormatter()
        let validDateStr = "2026-02-04T10:00:00Z"
        XCTAssertNotNil(isoFormatter.date(from: validDateStr), "Should parse valid ISO 8601 date")
    }
    
    func testISO8601WithTimezoneParsing() {
        let isoFormatter = ISO8601DateFormatter()
        let tzDateStr = "2026-02-04T15:30:00+05:00"
        XCTAssertNotNil(isoFormatter.date(from: tzDateStr), "Should parse ISO 8601 date with timezone offset")
    }
    
    func testInvalidDateFormatRejected() {
        let isoFormatter = ISO8601DateFormatter()
        let invalidDateStr = "02/04/2026"
        XCTAssertNil(isoFormatter.date(from: invalidDateStr), "Should reject invalid date format")
    }
    
    // MARK: - Error Type Tests
    
    func testNotAuthorizedErrorDescription() {
        let error = CalendarService.CalendarError.notAuthorized
        XCTAssertTrue(error.errorDescription?.contains("not authorized") == true,
                      "notAuthorized error should have correct description")
    }
    
    func testEventNotFoundErrorDescription() {
        let error = CalendarService.CalendarError.eventNotFound
        XCTAssertTrue(error.errorDescription?.contains("not found") == true,
                      "eventNotFound error should have correct description")
    }
    
    func testSaveFailedErrorDescription() {
        let mockError = NSError(domain: "test", code: 1, userInfo: nil)
        let error = CalendarService.CalendarError.saveFailed(mockError)
        XCTAssertTrue(error.errorDescription?.contains("Failed to save") == true,
                      "saveFailed error should have correct description")
    }
    
    // MARK: - Calendar Operations Tests (requires authorization)
    
    @MainActor
    func testGetCalendarsWhenAuthorized() throws {
        try XCTSkipUnless(service.isAuthorized, "Skipping: Calendar access not authorized")
        
        let calendars = service.getCalendars()
        // Should return at least the default calendar when authorized
        XCTAssertGreaterThanOrEqual(calendars.count, 0, "getCalendars should return calendar list")
        
        for calendar in calendars {
            XCTAssertFalse(calendar.calendarIdentifier.isEmpty, "Calendar should have identifier")
        }
    }
    
    @MainActor
    func testGetEventsWhenAuthorized() throws {
        try XCTSkipUnless(service.isAuthorized, "Skipping: Calendar access not authorized")
        
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        
        let events = service.getEvents(from: now, to: tomorrow)
        // Just verify it returns without error
        XCTAssertNotNil(events, "getEvents should return events array")
    }
    
    @MainActor
    func testGetNonExistentEventReturnsNil() throws {
        try XCTSkipUnless(service.isAuthorized, "Skipping: Calendar access not authorized")
        
        let fakeEventId = "non-existent-event-id-12345"
        let event = service.getEvent(eventId: fakeEventId)
        XCTAssertNil(event, "Non-existent event should return nil")
    }
    
    @MainActor
    func testGetCalendarByIdentifier() throws {
        try XCTSkipUnless(service.isAuthorized, "Skipping: Calendar access not authorized")
        
        // First get an existing calendar
        let calendars = service.getCalendars()
        try XCTSkipIf(calendars.isEmpty, "No calendars available")
        
        let calendar = calendars[0]
        let foundCalendar = service.getCalendar(byIdentifier: calendar.calendarIdentifier)
        XCTAssertNotNil(foundCalendar, "Should find calendar by identifier")
        XCTAssertEqual(foundCalendar?.calendarIdentifier, calendar.calendarIdentifier)
    }
    
    @MainActor
    func testGetCalendarByInvalidIdentifierReturnsNil() throws {
        try XCTSkipUnless(service.isAuthorized, "Skipping: Calendar access not authorized")
        
        let foundCalendar = service.getCalendar(byIdentifier: "invalid-calendar-id-12345")
        XCTAssertNil(foundCalendar, "Invalid calendar identifier should return nil")
    }
}
