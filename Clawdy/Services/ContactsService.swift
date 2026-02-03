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
