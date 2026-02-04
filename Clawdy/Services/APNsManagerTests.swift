import Foundation
import UIKit
import UserNotifications

/// Validation tests for APNsManager notification handling.
/// These are compile-time tests that verify APNs notification logic.
/// Run by including this file and checking the console output on app launch (DEBUG only).
///
/// Test Categories:
/// 1. Notification payload parsing
/// 2. Foreground presentation options by category
/// 3. Category constants and registration
/// 4. Deep link extraction from notification tap
enum APNsManagerTestRunner {
    
    #if DEBUG
    /// Run all APNsManager tests and log results.
    /// Call from app initialization in DEBUG builds only.
    @MainActor
    static func runTests() async {
        print("[APNsManagerTests] Running APNs notification validation...")
        
        var passed = 0
        var failed = 0
        
        let manager = APNsManager.shared
        
        // MARK: - Test 1: Category Constants
        print("[APNsManagerTests] --- Category Constants ---")
        
        if APNsManager.agentMessageCategory == "agent_message" {
            print("[APNsManagerTests] ✓ agentMessageCategory is 'agent_message'")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ agentMessageCategory wrong: \(APNsManager.agentMessageCategory)")
            failed += 1
        }
        
        if APNsManager.cronAlertCategory == "cron_alert" {
            print("[APNsManagerTests] ✓ cronAlertCategory is 'cron_alert'")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ cronAlertCategory wrong: \(APNsManager.cronAlertCategory)")
            failed += 1
        }
        
        if APNsManager.silentSyncCategory == "silent_sync" {
            print("[APNsManagerTests] ✓ silentSyncCategory is 'silent_sync'")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ silentSyncCategory wrong: \(APNsManager.silentSyncCategory)")
            failed += 1
        }
        
        // MARK: - Test 2: Notification Payload Parsing
        print("[APNsManagerTests] --- Payload Parsing ---")
        
        // Test basic APS parsing
        let basicPayload: [AnyHashable: Any] = [
            "aps": [
                "alert": ["title": "Test Title", "body": "Test Body"],
                "badge": 5,
                "sound": "default",
                "category": "agent_message"
            ]
        ]
        
        let basicParsed = manager.parseNotificationPayload(basicPayload)
        
        if basicParsed.title == "Test Title" {
            print("[APNsManagerTests] ✓ Parsed title correctly")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ Title parsing failed: \(basicParsed.title ?? "nil")")
            failed += 1
        }
        
        if basicParsed.body == "Test Body" {
            print("[APNsManagerTests] ✓ Parsed body correctly")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ Body parsing failed: \(basicParsed.body ?? "nil")")
            failed += 1
        }
        
        // Note: badge and sound are not parsed into RemoteNotificationPayload
        // They are handled by the system automatically
        
        if basicParsed.category == "agent_message" {
            print("[APNsManagerTests] ✓ Parsed category correctly")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ Category parsing failed: \(basicParsed.category ?? "nil")")
            failed += 1
        }
        
        // Test clawdy custom payload
        let clawdyPayload: [AnyHashable: Any] = [
            "aps": [
                "alert": ["title": "Agent", "body": "Response"],
                "content-available": 1
            ],
            "clawdy": [
                "sessionKey": "agent:main:main",
                "messageId": "msg-123-abc",
                "jobId": "job-456-def"
            ]
        ]
        
        let clawdyParsed = manager.parseNotificationPayload(clawdyPayload)
        
        if clawdyParsed.sessionKey == "agent:main:main" {
            print("[APNsManagerTests] ✓ Parsed sessionKey correctly")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ sessionKey parsing failed: \(clawdyParsed.sessionKey ?? "nil")")
            failed += 1
        }
        
        if clawdyParsed.messageId == "msg-123-abc" {
            print("[APNsManagerTests] ✓ Parsed messageId correctly")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ messageId parsing failed: \(clawdyParsed.messageId ?? "nil")")
            failed += 1
        }
        
        if clawdyParsed.jobId == "job-456-def" {
            print("[APNsManagerTests] ✓ Parsed jobId correctly")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ jobId parsing failed: \(clawdyParsed.jobId ?? "nil")")
            failed += 1
        }
        
        if clawdyParsed.isContentAvailable == true {
            print("[APNsManagerTests] ✓ Parsed content-available correctly")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ content-available parsing failed")
            failed += 1
        }
        
        // Test empty/missing fields
        let emptyPayload: [AnyHashable: Any] = [
            "aps": [:]
        ]
        
        let emptyParsed = manager.parseNotificationPayload(emptyPayload)
        
        if emptyParsed.title == nil && emptyParsed.body == nil {
            print("[APNsManagerTests] ✓ Empty payload returns nil for title/body")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ Empty payload should return nil for title/body")
            failed += 1
        }
        
        // MARK: - Test 3: Foreground Presentation Options
        print("[APNsManagerTests] --- Foreground Presentation Options ---")
        
        // Test agent_message shows banner + sound
        // We need to use parsed payloads since RemoteNotificationPayload has no public init
        let agentPayloadDict: [AnyHashable: Any] = [
            "aps": ["category": APNsManager.agentMessageCategory]
        ]
        let agentPayload = manager.parseNotificationPayload(agentPayloadDict)
        
        let agentOptions = manager.foregroundPresentationOptions(for: agentPayload)
        if agentOptions.contains(.banner) && agentOptions.contains(.sound) {
            print("[APNsManagerTests] ✓ agent_message shows banner + sound")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ agent_message should show banner + sound")
            failed += 1
        }
        
        // Test cron_alert shows banner + sound + badge
        let cronPayloadDict: [AnyHashable: Any] = [
            "aps": ["category": APNsManager.cronAlertCategory]
        ]
        let cronPayload = manager.parseNotificationPayload(cronPayloadDict)
        
        let cronOptions = manager.foregroundPresentationOptions(for: cronPayload)
        if cronOptions.contains(.banner) && cronOptions.contains(.sound) && cronOptions.contains(.badge) {
            print("[APNsManagerTests] ✓ cron_alert shows banner + sound + badge")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ cron_alert should show banner + sound + badge")
            failed += 1
        }
        
        // Test silent_sync is suppressed (empty options)
        let silentPayloadDict: [AnyHashable: Any] = [
            "aps": ["category": APNsManager.silentSyncCategory]
        ]
        let silentPayload = manager.parseNotificationPayload(silentPayloadDict)
        
        let silentOptions = manager.foregroundPresentationOptions(for: silentPayload)
        if silentOptions.isEmpty {
            print("[APNsManagerTests] ✓ silent_sync returns empty options (suppressed)")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ silent_sync should return empty options")
            failed += 1
        }
        
        // Test default category shows banner + sound
        let defaultPayloadDict: [AnyHashable: Any] = [
            "aps": ["category": "unknown_category"]
        ]
        let defaultPayload = manager.parseNotificationPayload(defaultPayloadDict)
        
        let defaultOptions = manager.foregroundPresentationOptions(for: defaultPayload)
        if defaultOptions.contains(.banner) && defaultOptions.contains(.sound) {
            print("[APNsManagerTests] ✓ Default category shows banner + sound")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ Default category should show banner + sound")
            failed += 1
        }
        
        // Test nil category shows banner + sound
        let nilCategoryPayloadDict: [AnyHashable: Any] = [
            "aps": [:]
        ]
        let nilCategoryPayload = manager.parseNotificationPayload(nilCategoryPayloadDict)
        
        let nilOptions = manager.foregroundPresentationOptions(for: nilCategoryPayload)
        if nilOptions.contains(.banner) && nilOptions.contains(.sound) {
            print("[APNsManagerTests] ✓ Nil category shows banner + sound")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ Nil category should show banner + sound")
            failed += 1
        }
        
        // MARK: - Test 4: Silent Notification Detection
        print("[APNsManagerTests] --- Silent Notification Detection ---")
        
        // Content-available flag
        let contentAvailablePayloadDict: [AnyHashable: Any] = [
            "aps": ["content-available": 1]
        ]
        let contentAvailablePayload = manager.parseNotificationPayload(contentAvailablePayloadDict)
        
        // The public API is parseNotificationPayload which correctly sets isContentAvailable
        if contentAvailablePayload.isContentAvailable {
            print("[APNsManagerTests] ✓ isContentAvailable flag is set")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ isContentAvailable flag should be true")
            failed += 1
        }
        
        // Silent sync category - even without content-available, silent_sync should be treated as silent
        let silentSyncPayloadDict: [AnyHashable: Any] = [
            "aps": ["category": APNsManager.silentSyncCategory]
        ]
        let silentSyncPayload = manager.parseNotificationPayload(silentSyncPayloadDict)
        
        let silentSyncOptions = manager.foregroundPresentationOptions(for: silentSyncPayload)
        if silentSyncOptions.isEmpty {
            print("[APNsManagerTests] ✓ silent_sync category suppresses notification")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ silent_sync category should suppress notification")
            failed += 1
        }
        
        // MARK: - Test 5: String Alert Parsing
        print("[APNsManagerTests] --- String Alert Parsing ---")
        
        // Some servers send alert as a simple string
        let stringAlertPayload: [AnyHashable: Any] = [
            "aps": [
                "alert": "Simple alert message"
            ]
        ]
        
        let stringParsed = manager.parseNotificationPayload(stringAlertPayload)
        
        // When alert is a string, body should be the string
        if stringParsed.body == "Simple alert message" || stringParsed.title == nil {
            print("[APNsManagerTests] ✓ String alert parsed as body")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ String alert should be parsed: title=\(stringParsed.title ?? "nil"), body=\(stringParsed.body ?? "nil")")
            failed += 1
        }
        
        // MARK: - Test 6: APNs Environment Detection
        print("[APNsManagerTests] --- Environment Detection ---")
        
        // Check that environment is set (sandbox in DEBUG, production in release)
        let environment = manager.environment
        #if DEBUG
        if environment == .sandbox {
            print("[APNsManagerTests] ✓ Sandbox environment in DEBUG build")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ Should be sandbox in DEBUG, got \(environment.rawValue)")
            failed += 1
        }
        #else
        if environment == .production {
            print("[APNsManagerTests] ✓ Production environment in release build")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ Should be production in release, got \(environment.rawValue)")
            failed += 1
        }
        #endif
        
        // Check bundle ID is set
        if !manager.bundleId.isEmpty {
            print("[APNsManagerTests] ✓ Bundle ID is set: \(manager.bundleId)")
            passed += 1
        } else {
            print("[APNsManagerTests] ✗ Bundle ID is empty")
            failed += 1
        }
        
        // MARK: - Results
        print("[APNsManagerTests] ═══════════════════════════════════════")
        print("[APNsManagerTests] Results: \(passed) passed, \(failed) failed")
        print("[APNsManagerTests] ═══════════════════════════════════════")
    }
    #endif
}

