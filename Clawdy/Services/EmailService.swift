import Foundation
import UIKit
import MessageUI

/// Service for composing and sending emails on the device.
/// Provides email capabilities for Clawdy.
@MainActor
class EmailService: NSObject, ObservableObject {
    static let shared = EmailService()
    
    // MARK: - Published Properties
    
    /// Whether email is available on this device
    @Published private(set) var isAvailable: Bool = false
    
    // MARK: - Properties
    
    /// Completion handler for mail compose result
    private var mailComposeCompletion: ((MFMailComposeResult, Error?) -> Void)?
    
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
    
    /// Open the default email app to compose an email.
    /// - Parameters:
    ///   - to: Recipient email addresses
    ///   - subject: Email subject
    ///   - body: Email body
    /// - Returns: Whether the email composer was opened successfully
    @discardableResult
    func composeEmail(to: [String], subject: String? = nil, body: String? = nil) async -> Bool {
        // Build mailto URL
        var urlString = "mailto:\(to.joined(separator: ","))"
        var queryItems: [String] = []
        
        if let subject = subject?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryItems.append("subject=\(subject)")
        }
        
        if let body = body?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryItems.append("body=\(body)")
        }
        
        if !queryItems.isEmpty {
            urlString += "?\(queryItems.joined(separator: "&"))"
        }
        
        guard let url = URL(string: urlString) else {
            print("[EmailService] Failed to create mailto URL")
            return false
        }
        
        guard UIApplication.shared.canOpenURL(url) else {
            print("[EmailService] Cannot open mailto URL")
            return false
        }
        
        let success = await UIApplication.shared.open(url)
        print("[EmailService] Email composer opened for \(to): \(success)")
        return success
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
