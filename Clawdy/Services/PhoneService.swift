import Foundation
import UIKit
import MessageUI
import CallKit

/// Service for initiating phone calls and SMS on the device.
/// Provides phone and messaging capabilities for Clawdy using CallKit and MessageUI.
@MainActor
class PhoneService: NSObject, ObservableObject {
    static let shared = PhoneService()
    
    // MARK: - Published Properties
    
    /// Whether phone calls are available on this device
    @Published private(set) var isCallAvailable: Bool = false
    
    /// Whether SMS is available on this device
    @Published private(set) var isSMSAvailable: Bool = false
    
    /// Backward compatibility alias for isCallAvailable
    var isAvailable: Bool { isCallAvailable }
    
    // MARK: - Properties
    
    /// CallKit call controller for initiating calls
    private let callController = CXCallController()
    
    /// Completion handler for SMS compose result
    private var smsComposeCompletion: ((MessageComposeResult, Error?) -> Void)?
    
    /// Continuation for async SMS composition
    private var smsContinuation: CheckedContinuation<(Bool, MessageComposeResult?), Never>?
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        checkAvailability()
    }
    
    // MARK: - Availability Check
    
    /// Check if phone calls and SMS are available.
    func checkAvailability() {
        isCallAvailable = UIApplication.shared.canOpenURL(URL(string: "tel://")!)
        isSMSAvailable = MFMessageComposeViewController.canSendText()
    }
    
    // MARK: - Phone Number Validation
    
    /// Validate a phone number format.
    /// - Parameter number: The phone number to validate
    /// - Returns: Whether the number is valid
    func isValidPhoneNumber(_ number: String) -> Bool {
        let cleaned = number.components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "+")).inverted).joined()
        // Must have at least 3 digits (area code minimum) and no more than 15 (ITU max)
        return cleaned.count >= 3 && cleaned.count <= 15
    }
    
    /// Clean and normalize a phone number.
    /// - Parameter number: The phone number to clean
    /// - Returns: The cleaned phone number
    func cleanPhoneNumber(_ number: String) -> String {
        // Keep digits and leading + for international numbers
        let hasPlus = number.hasPrefix("+")
        let digits = number.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return hasPlus ? "+\(digits)" : digits
    }
    
    // MARK: - Phone Operations
    
    /// Initiate a phone call using CallKit.
    /// - Parameter phoneNumber: Phone number to call
    /// - Returns: Result indicating success or specific error
    func initiateCall(phoneNumber: String) async -> PhoneCallServiceResult {
        guard isCallAvailable else {
            print("[PhoneService] Phone calls not available on this device")
            return .notAvailable
        }
        
        guard isValidPhoneNumber(phoneNumber) else {
            print("[PhoneService] Invalid phone number: \(phoneNumber)")
            return .invalidNumber
        }
        
        let cleaned = cleanPhoneNumber(phoneNumber)
        
        // Create a CXHandle for the phone number
        let handle = CXHandle(type: .phoneNumber, value: cleaned)
        
        // Generate a unique call UUID
        let callUUID = UUID()
        
        // Create start call action
        let startCallAction = CXStartCallAction(call: callUUID, handle: handle)
        startCallAction.isVideo = false
        
        // Create a transaction with the action
        let transaction = CXTransaction(action: startCallAction)
        
        do {
            try await callController.request(transaction)
            print("[PhoneService] Call initiated to \(cleaned) via CallKit")
            return .success
        } catch {
            print("[PhoneService] CallKit error: \(error.localizedDescription)")
            // Fallback to URL scheme if CallKit fails (e.g., on simulator)
            return await fallbackToURLCall(phoneNumber: cleaned)
        }
    }
    
    /// Fallback to URL-based call initiation (for simulator or CallKit failures).
    private func fallbackToURLCall(phoneNumber: String) async -> PhoneCallServiceResult {
        guard let url = URL(string: "tel://\(phoneNumber)") else {
            return .callFailed
        }
        
        let success = await UIApplication.shared.open(url)
        if success {
            print("[PhoneService] Call initiated via URL fallback")
            return .success
        } else {
            return .callFailed
        }
    }
    
    /// Legacy method - Initiate a phone call.
    /// - Parameter phoneNumber: Phone number to call
    /// - Returns: Whether the call was initiated successfully
    @discardableResult
    func call(phoneNumber: String) async -> Bool {
        let result = await initiateCall(phoneNumber: phoneNumber)
        return result == .success
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
    
    // MARK: - SMS Operations
    
    /// Compose an SMS message using MessageUI.
    /// Presents the system SMS composer and waits for user action.
    /// - Parameters:
    ///   - to: Recipient phone number
    ///   - body: Message body (optional)
    /// - Returns: Result indicating success or specific error
    func composeSMS(to phoneNumber: String, body: String? = nil) async -> SMSComposeServiceResult {
        // Check availability first
        guard MFMessageComposeViewController.canSendText() else {
            print("[PhoneService] SMS not available on this device")
            return .notAvailable
        }
        
        // Validate phone number
        guard isValidPhoneNumber(phoneNumber) else {
            print("[PhoneService] Invalid phone number for SMS: \(phoneNumber)")
            return .invalidNumber
        }
        
        let cleaned = cleanPhoneNumber(phoneNumber)
        
        // Get the root view controller to present from
        guard let presenter = await getRootViewController() else {
            print("[PhoneService] No view controller available to present SMS composer")
            return .composeFailed
        }
        
        // Present the SMS composer and wait for result
        let (success, result) = await withCheckedContinuation { continuation in
            self.smsContinuation = continuation
            
            let messageVC = MFMessageComposeViewController()
            messageVC.messageComposeDelegate = self
            messageVC.recipients = [cleaned]
            
            if let body = body {
                messageVC.body = body
            }
            
            presenter.present(messageVC, animated: true)
        }
        
        if success {
            if result == .sent {
                return .sent
            } else if result == .cancelled {
                return .cancelled
            }
        }
        
        return .composeFailed
    }
    
    /// Legacy method - Send an SMS message by opening the Messages app.
    /// - Parameters:
    ///   - to: Recipient phone number
    ///   - body: Message body (optional)
    /// - Returns: Whether the Messages app was opened successfully
    @discardableResult
    func sendSMS(to phoneNumber: String, body: String? = nil) async -> Bool {
        let result = await composeSMS(to: phoneNumber, body: body)
        return result == .sent || result == .cancelled // Cancelled means composer was shown
    }
    
    /// Get the root view controller for presenting UI.
    private func getRootViewController() async -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return nil
        }
        
        // Find the topmost presented view controller
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
    
    /// Present the in-app SMS composer view controller.
    /// - Parameters:
    ///   - to: Recipient phone numbers
    ///   - body: Message body (optional)
    ///   - presenter: View controller to present from
    ///   - completion: Called with the result
    func presentSMSComposer(
        to phoneNumbers: [String],
        body: String? = nil,
        presenter: UIViewController,
        completion: @escaping (MessageComposeResult, Error?) -> Void
    ) {
        guard MFMessageComposeViewController.canSendText() else {
            completion(.failed, PhoneError.smsNotAvailable)
            return
        }
        
        // Validate and clean all phone numbers
        let cleanedNumbers = phoneNumbers.compactMap { number -> String? in
            guard isValidPhoneNumber(number) else { return nil }
            return cleanPhoneNumber(number)
        }
        
        guard !cleanedNumbers.isEmpty else {
            completion(.failed, PhoneError.invalidNumber)
            return
        }
        
        let messageVC = MFMessageComposeViewController()
        messageVC.messageComposeDelegate = self
        messageVC.recipients = cleanedNumbers
        
        if let body = body {
            messageVC.body = body
        }
        
        smsComposeCompletion = completion
        presenter.present(messageVC, animated: true)
    }
    
    // MARK: - Errors
    
    enum PhoneError: LocalizedError {
        case notAvailable
        case invalidNumber
        case callFailed
        case smsNotAvailable
        case smsFailed
        
        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Phone calls not available on this device"
            case .invalidNumber:
                return "Invalid phone number"
            case .callFailed:
                return "Failed to initiate call"
            case .smsNotAvailable:
                return "SMS not available on this device"
            case .smsFailed:
                return "Failed to send SMS"
            }
        }
    }
    
    // MARK: - Result Types
    
    /// Result of a phone call initiation attempt.
    enum PhoneCallServiceResult: Equatable {
        case success
        case notAvailable
        case invalidNumber
        case callFailed
        
        var errorMessage: String? {
            switch self {
            case .success: return nil
            case .notAvailable: return "Phone calls not available on this device"
            case .invalidNumber: return "Invalid phone number format"
            case .callFailed: return "Failed to initiate call"
            }
        }
    }
    
    /// Result of an SMS composition attempt.
    enum SMSComposeServiceResult: Equatable {
        case sent
        case cancelled
        case notAvailable
        case invalidNumber
        case composeFailed
        
        var errorMessage: String? {
            switch self {
            case .sent, .cancelled: return nil
            case .notAvailable: return "SMS not available on this device"
            case .invalidNumber: return "Invalid phone number format"
            case .composeFailed: return "Failed to compose SMS"
            }
        }
        
        var isSuccess: Bool {
            self == .sent || self == .cancelled
        }
    }
}

// MARK: - MFMessageComposeViewControllerDelegate

extension PhoneService: MFMessageComposeViewControllerDelegate {
    nonisolated func messageComposeViewController(
        _ controller: MFMessageComposeViewController,
        didFinishWith result: MessageComposeResult
    ) {
        controller.dismiss(animated: true)
        
        Task { @MainActor in
            // Handle async continuation if present
            if let continuation = smsContinuation {
                smsContinuation = nil
                let success = (result == .sent || result == .cancelled)
                continuation.resume(returning: (success, result))
            }
            
            // Handle legacy callback completion
            let completion = smsComposeCompletion
            smsComposeCompletion = nil
            
            var error: Error? = nil
            switch result {
            case .sent:
                print("[PhoneService] SMS sent successfully")
            case .cancelled:
                print("[PhoneService] SMS cancelled")
            case .failed:
                print("[PhoneService] SMS failed")
                error = PhoneError.smsFailed
            @unknown default:
                print("[PhoneService] SMS unknown result")
            }
            
            completion?(result, error)
        }
    }
}
