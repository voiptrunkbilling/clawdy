import Foundation
import UIKit
import MessageUI

/// Service for composing and sending emails on the device.
/// Provides email capabilities for Clawdy using MessageUI.
@MainActor
class EmailService: NSObject, ObservableObject {
    static let shared = EmailService()
    
    // MARK: - Published Properties
    
    /// Whether email is available on this device
    @Published private(set) var isAvailable: Bool = false
    
    // MARK: - Properties
    
    /// Completion handler for mail compose result
    private var mailComposeCompletion: ((MFMailComposeResult, Error?) -> Void)?
    
    /// Continuation for async email composition
    private var mailContinuation: CheckedContinuation<(Bool, MFMailComposeResult?), Never>?
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        checkAvailability()
    }
    
    // MARK: - Availability Check
    
    /// Check if email is available.
    func checkAvailability() {
        isAvailable = MFMailComposeViewController.canSendMail()
    }
    
    // MARK: - Email Operations
    
    /// Compose an email using MFMailComposeViewController.
    /// Presents the system email composer and waits for user action.
    /// - Parameters:
    ///   - to: Recipient email addresses
    ///   - subject: Email subject
    ///   - body: Email body
    ///   - isHTML: Whether the body is HTML formatted
    /// - Returns: Result indicating success or specific error
    func composeEmailAsync(
        to recipients: [String],
        subject: String? = nil,
        body: String? = nil,
        isHTML: Bool = false
    ) async -> EmailComposeServiceResult {
        // Check availability first
        guard MFMailComposeViewController.canSendMail() else {
            print("[EmailService] Email not available on this device")
            return .notAvailable
        }
        
        // Validate recipients
        guard !recipients.isEmpty else {
            print("[EmailService] No recipients provided")
            return .invalidRecipients
        }
        
        // Get the root view controller to present from
        guard let presenter = await getRootViewController() else {
            print("[EmailService] No view controller available to present email composer")
            return .composeFailed
        }
        
        // Present the mail composer and wait for result
        let (success, result) = await withCheckedContinuation { continuation in
            self.mailContinuation = continuation
            
            let mailVC = MFMailComposeViewController()
            mailVC.mailComposeDelegate = self
            mailVC.setToRecipients(recipients)
            
            if let subject = subject {
                mailVC.setSubject(subject)
            }
            
            if let body = body {
                mailVC.setMessageBody(body, isHTML: isHTML)
            }
            
            presenter.present(mailVC, animated: true)
        }
        
        if success, let result = result {
            switch result {
            case .sent:
                return .sent
            case .saved:
                return .saved
            case .cancelled:
                return .cancelled
            case .failed:
                return .composeFailed
            @unknown default:
                return .composeFailed
            }
        }
        
        return .composeFailed
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
    
    /// Legacy method - Open the default email app to compose an email.
    /// - Parameters:
    ///   - to: Recipient email addresses
    ///   - subject: Email subject
    ///   - body: Email body
    /// - Returns: Whether the email composer was opened successfully
    @discardableResult
    func composeEmail(to: [String], subject: String? = nil, body: String? = nil) async -> Bool {
        let result = await composeEmailAsync(to: to, subject: subject, body: body, isHTML: false)
        return result.isSuccess
    }
    
    /// Present the in-app mail composer view controller.
    /// - Parameters:
    ///   - to: Recipient email addresses
    ///   - subject: Email subject
    ///   - body: Email body
    ///   - isHTML: Whether body is HTML
    ///   - presenter: View controller to present from
    ///   - completion: Called with the result
    func presentMailComposer(
        to: [String],
        subject: String? = nil,
        body: String? = nil,
        isHTML: Bool = false,
        presenter: UIViewController,
        completion: @escaping (MFMailComposeResult, Error?) -> Void
    ) {
        guard MFMailComposeViewController.canSendMail() else {
            completion(.failed, EmailError.notAvailable)
            return
        }
        
        let mailVC = MFMailComposeViewController()
        mailVC.mailComposeDelegate = self
        mailVC.setToRecipients(to)
        
        if let subject = subject {
            mailVC.setSubject(subject)
        }
        
        if let body = body {
            mailVC.setMessageBody(body, isHTML: isHTML)
        }
        
        mailComposeCompletion = completion
        presenter.present(mailVC, animated: true)
    }
    
    // MARK: - Errors
    
    enum EmailError: LocalizedError {
        case notAvailable
        case composeFailed
        case sendFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Email not available on this device"
            case .composeFailed:
                return "Failed to compose email"
            case .sendFailed(let error):
                return "Failed to send email: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Result Types
    
    /// Result of an email composition attempt.
    enum EmailComposeServiceResult: Equatable {
        case sent
        case saved
        case cancelled
        case notAvailable
        case invalidRecipients
        case composeFailed
        
        var errorMessage: String? {
            switch self {
            case .sent, .saved, .cancelled: return nil
            case .notAvailable: return "Email not available on this device"
            case .invalidRecipients: return "At least one recipient is required"
            case .composeFailed: return "Failed to compose email"
            }
        }
        
        var isSuccess: Bool {
            self == .sent || self == .saved || self == .cancelled
        }
    }
}

// MARK: - MFMailComposeViewControllerDelegate

extension EmailService: MFMailComposeViewControllerDelegate {
    nonisolated func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: Error?
    ) {
        controller.dismiss(animated: true)
        
        Task { @MainActor in
            // Handle async continuation if present
            if let continuation = mailContinuation {
                mailContinuation = nil
                let success = (result == .sent || result == .saved || result == .cancelled)
                continuation.resume(returning: (success, result))
            }
            
            // Handle legacy callback completion
            let completion = mailComposeCompletion
            mailComposeCompletion = nil
            completion?(result, error)
            
            switch result {
            case .sent:
                print("[EmailService] Email sent successfully")
            case .saved:
                print("[EmailService] Email saved to drafts")
            case .cancelled:
                print("[EmailService] Email cancelled")
            case .failed:
                print("[EmailService] Email failed: \(error?.localizedDescription ?? "unknown")")
            @unknown default:
                print("[EmailService] Email unknown result")
            }
        }
    }
}
