import Foundation
import Contacts

/// Service for contacts operations on the device.
/// Provides authorization management and contacts access for Clawdy capabilities.
@MainActor
class ContactsService: ObservableObject {
    static let shared = ContactsService()
    
    // MARK: - Published Properties
    
    /// Current authorization status for contacts access
    @Published private(set) var authorizationStatus: CNAuthorizationStatus = .notDetermined
    
    /// Whether contacts access is authorized
    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }
    
    // MARK: - Properties
    
    private let contactStore = CNContactStore()
    
    // MARK: - Initialization
    
    private init() {
        refreshAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    /// Request contacts access authorization.
    /// - Returns: Whether authorization was granted
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await contactStore.requestAccess(for: .contacts)
            
            await MainActor.run {
                refreshAuthorizationStatus()
            }
            
            print("[ContactsService] Authorization \(granted ? "granted" : "denied")")
            return granted
        } catch {
            print("[ContactsService] Authorization error: \(error)")
            return false
        }
    }
    
    /// Refresh the current authorization status.
    func refreshAuthorizationStatus() {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }
    
    // MARK: - Contact Operations
    
    /// Search contacts by name.
    /// - Parameter name: Name to search for
    /// - Returns: Array of matching contacts
    func searchContacts(name: String) throws -> [CNContact] {
        guard isAuthorized else {
            throw ContactsError.notAuthorized
        }
        
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
        ]
        
        let predicate = CNContact.predicateForContacts(matchingName: name)
        let contacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
        
        print("[ContactsService] Found \(contacts.count) contacts matching '\(name)'")
        return contacts
    }
    
    /// Get all contacts.
    /// - Returns: Array of all contacts
    func getAllContacts() throws -> [CNContact] {
        guard isAuthorized else {
            throw ContactsError.notAuthorized
        }
        
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        
        var contacts: [CNContact] = []
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        
        try contactStore.enumerateContacts(with: request) { contact, _ in
            contacts.append(contact)
        }
        
        return contacts
    }
    
    /// Create a new contact.
    /// - Parameters:
    ///   - givenName: First name
    ///   - familyName: Last name
    ///   - phoneNumber: Phone number (optional)
    ///   - email: Email address (optional)
    /// - Returns: The created contact identifier
    func createContact(givenName: String, familyName: String, phoneNumber: String? = nil, email: String? = nil) throws -> String {
        guard isAuthorized else {
            throw ContactsError.notAuthorized
        }
        
        let contact = CNMutableContact()
        contact.givenName = givenName
        contact.familyName = familyName
        
        if let phone = phoneNumber {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone))]
        }
        
        if let emailAddress = email {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: emailAddress as NSString)]
        }
        
        let saveRequest = CNSaveRequest()
        saveRequest.add(contact, toContainerWithIdentifier: nil)
        
        try contactStore.execute(saveRequest)
        print("[ContactsService] Created contact: \(givenName) \(familyName)")
        return contact.identifier
    }
    
    /// Update an existing contact.
    /// - Parameters:
    ///   - contactId: The contact identifier to update
    ///   - givenName: New first name (nil to keep existing)
    ///   - familyName: New last name (nil to keep existing)
    ///   - phoneNumber: New phone number (nil to keep existing)
    ///   - email: New email address (nil to keep existing)
    func updateContact(contactId: String, givenName: String? = nil, familyName: String? = nil, phoneNumber: String? = nil, email: String? = nil) throws {
        guard isAuthorized else {
            throw ContactsError.notAuthorized
        }
        
        // Fetch the contact with mutable keys
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        
        let predicate = CNContact.predicateForContacts(withIdentifiers: [contactId])
        let contacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
        
        guard let contact = contacts.first else {
            throw ContactsError.contactNotFound
        }
        
        // Create mutable copy
        let mutableContact = contact.mutableCopy() as! CNMutableContact
        
        if let newGivenName = givenName {
            mutableContact.givenName = newGivenName
        }
        if let newFamilyName = familyName {
            mutableContact.familyName = newFamilyName
        }
        if let newPhone = phoneNumber {
            mutableContact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: newPhone))]
        }
        if let newEmail = email {
            mutableContact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: newEmail as NSString)]
        }
        
        let saveRequest = CNSaveRequest()
        saveRequest.update(mutableContact)
        
        do {
            try contactStore.execute(saveRequest)
            print("[ContactsService] Updated contact: \(mutableContact.givenName) \(mutableContact.familyName)")
        } catch {
            throw ContactsError.saveFailed(error)
        }
    }
    
    /// Get a contact by identifier.
    /// - Parameter contactId: The contact identifier
    /// - Returns: The contact if found, nil otherwise
    func getContact(contactId: String) throws -> CNContact? {
        guard isAuthorized else {
            throw ContactsError.notAuthorized
        }
        
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
        ]
        
        let predicate = CNContact.predicateForContacts(withIdentifiers: [contactId])
        let contacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
        
        return contacts.first
    }
    
    // MARK: - Errors
    
    enum ContactsError: LocalizedError {
        case notAuthorized
        case contactNotFound
        case saveFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Contacts access not authorized"
            case .contactNotFound:
                return "Contact not found"
            case .saveFailed(let error):
                return "Failed to save contact: \(error.localizedDescription)"
            }
        }
    }
}
