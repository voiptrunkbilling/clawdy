import Foundation
import Contacts
import XCTest

/// Unit tests for ContactsService operations.
/// These tests validate the contacts capability service functionality.
///
/// Test Categories:
/// 1. Service initialization (singleton pattern)
/// 2. Authorization handling
/// 3. Error types validation
/// 4. Search operations validation
class ContactsServiceTests: XCTestCase {
    
    private var service: ContactsService!
    
    @MainActor
    override func setUp() {
        super.setUp()
        service = ContactsService.shared
    }
    
    override func tearDown() {
        service = nil
        super.tearDown()
    }
    
    // MARK: - Singleton Tests
    
    @MainActor
    func testSingletonPattern() {
        let service2 = ContactsService.shared
        XCTAssertTrue(service === service2, "ContactsService should use singleton pattern")
    }
    
    // MARK: - Authorization Tests
    
    @MainActor
    func testAuthorizationStatusIsValid() {
        let status = service.authorizationStatus
        let validStatuses: [CNAuthorizationStatus] = [.notDetermined, .restricted, .denied, .authorized]
        XCTAssertTrue(validStatuses.contains(status), "Authorization status should be a valid CNAuthorizationStatus")
    }
    
    @MainActor
    func testIsAuthorizedMatchesStatus() {
        let isAuth = service.isAuthorized
        let status = service.authorizationStatus
        let expectedAuth = (status == .authorized)
        XCTAssertEqual(isAuth, expectedAuth, "isAuthorized should match authorization status")
    }
    
    // MARK: - Error Type Tests
    
    func testNotAuthorizedErrorDescription() {
        let error = ContactsService.ContactsError.notAuthorized
        XCTAssertTrue(error.errorDescription?.contains("not authorized") == true,
                      "notAuthorized error should have correct description")
    }
    
    func testContactNotFoundErrorDescription() {
        let error = ContactsService.ContactsError.contactNotFound
        XCTAssertTrue(error.errorDescription?.contains("not found") == true,
                      "contactNotFound error should have correct description")
    }
    
    func testSaveFailedErrorDescription() {
        let mockError = NSError(domain: "test", code: 1, userInfo: nil)
        let error = ContactsService.ContactsError.saveFailed(mockError)
        XCTAssertTrue(error.errorDescription?.contains("Failed to save") == true,
                      "saveFailed error should have correct description")
    }
    
    // MARK: - Contact Operations Tests (requires authorization)
    
    @MainActor
    func testSearchContactsWhenAuthorized() throws {
        try XCTSkipUnless(service.isAuthorized, "Skipping: Contacts access not authorized")
        
        // Search for a common name - should not throw
        XCTAssertNoThrow(try service.searchContacts(name: "John"))
    }
    
    @MainActor
    func testGetAllContactsWhenAuthorized() throws {
        try XCTSkipUnless(service.isAuthorized, "Skipping: Contacts access not authorized")
        
        XCTAssertNoThrow(try service.getAllContacts())
    }
    
    @MainActor
    func testGetNonExistentContactReturnsNil() throws {
        try XCTSkipUnless(service.isAuthorized, "Skipping: Contacts access not authorized")
        
        let fakeContactId = "non-existent-contact-id-12345"
        let contact = try service.getContact(contactId: fakeContactId)
        XCTAssertNil(contact, "Non-existent contact should return nil")
    }
    
    @MainActor
    func testUpdateContactThrowsWhenNotAuthorized() throws {
        try XCTSkipIf(service.isAuthorized, "Skipping: Already authorized")
        
        XCTAssertThrowsError(try service.updateContact(contactId: "test", givenName: "Test")) { error in
            guard case ContactsService.ContactsError.notAuthorized = error else {
                XCTFail("Expected notAuthorized error, got \(error)")
                return
            }
        }
    }
    
    @MainActor
    func testCreateContactThrowsWhenNotAuthorized() throws {
        try XCTSkipIf(service.isAuthorized, "Skipping: Already authorized")
        
        XCTAssertThrowsError(try service.createContact(givenName: "Test", familyName: "User")) { error in
            guard case ContactsService.ContactsError.notAuthorized = error else {
                XCTFail("Expected notAuthorized error, got \(error)")
                return
            }
        }
    }
    
    // MARK: - Search Results Validation
    
    @MainActor
    func testSearchResultsHaveRequiredFields() throws {
        try XCTSkipUnless(service.isAuthorized, "Skipping: Contacts access not authorized")
        
        let results = try service.searchContacts(name: "")  // Empty search returns all
        
        // If there are any contacts, verify they have proper structure
        for contact in results.prefix(5) {
            // identifier should never be empty
            XCTAssertFalse(contact.identifier.isEmpty, "Contact should have identifier")
            // givenName and familyName can be empty but should be accessible
            _ = contact.givenName
            _ = contact.familyName
        }
    }
}
