import Foundation
import UIKit

/// Service for initiating phone calls on the device.
/// Provides phone call capabilities for Clawdy.
@MainActor
class PhoneService: ObservableObject {
    static let shared = PhoneService()
    
    // MARK: - Published Properties
    
    /// Whether phone calls are available on this device
    @Published private(set) var isAvailable: Bool = false
    
    // MARK: - Initialization
    
    private init() {
        checkAvailability()
    }
    
    // MARK: - Availability Check
    
    /// Check if phone calls are available.
    func checkAvailability() {
        isAvailable = UIApplication.shared.canOpenURL(URL(string: "tel://")!)
    }
    
    // MARK: - Phone Operations
    
    /// Initiate a phone call.
    /// - Parameter phoneNumber: Phone number to call
    /// - Returns: Whether the call was initiated successfully
    @discardableResult
    func call(phoneNumber: String) async -> Bool {
        guard isAvailable else {
            print("[PhoneService] Phone calls not available on this device")
            return false
        }
        
        // Clean the phone number - remove spaces, parentheses, dashes
        let cleaned = phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        guard !cleaned.isEmpty else {
            print("[PhoneService] Invalid phone number: \(phoneNumber)")
            return false
        }
        
        guard let url = URL(string: "tel://\(cleaned)") else {
            print("[PhoneService] Failed to create URL for phone number: \(cleaned)")
            return false
        }
        
        let success = await UIApplication.shared.open(url)
        print("[PhoneService] Call initiated to \(cleaned): \(success)")
        return success
    }
    
    /// Initiate a FaceTime audio call.
    /// - Parameter phoneNumber: Phone number or email to call
    /// - Returns: Whether the call was initiated successfully
    @discardableResult
    func facetimeAudio(contact: String) async -> Bool {
        guard let url = URL(string: "facetime-audio://\(contact)") else {
            print("[PhoneService] Failed to create FaceTime URL for: \(contact)")
            return false
        }
        
        guard UIApplication.shared.canOpenURL(url) else {
            print("[PhoneService] FaceTime audio not available")
            return false
        }
        
        let success = await UIApplication.shared.open(url)
        print("[PhoneService] FaceTime audio initiated to \(contact): \(success)")
        return success
    }
    
    /// Initiate a FaceTime video call.
    /// - Parameter contact: Phone number or email to call
    /// - Returns: Whether the call was initiated successfully
    @discardableResult
    func facetimeVideo(contact: String) async -> Bool {
        guard let url = URL(string: "facetime://\(contact)") else {
            print("[PhoneService] Failed to create FaceTime video URL for: \(contact)")
            return false
        }
        
        guard UIApplication.shared.canOpenURL(url) else {
            print("[PhoneService] FaceTime video not available")
            return false
        }
        
        let success = await UIApplication.shared.open(url)
        print("[PhoneService] FaceTime video initiated to \(contact): \(success)")
        return success
    }
    
    // MARK: - Errors
    
    enum PhoneError: LocalizedError {
        case notAvailable
        case invalidNumber
        case callFailed
        
        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Phone calls not available on this device"
            case .invalidNumber:
                return "Invalid phone number"
            case .callFailed:
                return "Failed to initiate call"
            }
        }
    }
}
