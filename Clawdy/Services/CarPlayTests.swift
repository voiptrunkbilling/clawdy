import XCTest
@testable import Clawdy

/// Unit tests for CarPlay support
final class CarPlayTests: XCTestCase {
    
    // MARK: - CarPlayVoiceState Tests
    
    func testVoiceStateRawValues() {
        XCTAssertEqual(CarPlayVoiceState.idle.rawValue, "idle")
        XCTAssertEqual(CarPlayVoiceState.listening.rawValue, "listening")
        XCTAssertEqual(CarPlayVoiceState.thinking.rawValue, "thinking")
        XCTAssertEqual(CarPlayVoiceState.speaking.rawValue, "speaking")
    }
    
    func testVoiceStateFromRawValue() {
        XCTAssertEqual(CarPlayVoiceState(rawValue: "idle"), .idle)
        XCTAssertEqual(CarPlayVoiceState(rawValue: "listening"), .listening)
        XCTAssertEqual(CarPlayVoiceState(rawValue: "thinking"), .thinking)
        XCTAssertEqual(CarPlayVoiceState(rawValue: "speaking"), .speaking)
        XCTAssertNil(CarPlayVoiceState(rawValue: "invalid"))
    }
    
    // MARK: - Notification Tests
    
    func testCarPlayPTTNotificationName() {
        XCTAssertEqual(
            Notification.Name.carPlayPTTPressed.rawValue,
            "carPlayPTTPressed"
        )
    }
    
    func testCarPlayStopNotificationName() {
        XCTAssertEqual(
            Notification.Name.carPlayStopPressed.rawValue,
            "carPlayStopPressed"
        )
    }
    
    func testCarPlayVoiceStateChangedNotificationName() {
        XCTAssertEqual(
            Notification.Name.carPlayVoiceStateChanged.rawValue,
            "carPlayVoiceStateChanged"
        )
    }
    
    func testVoiceStateChangeNotification() {
        let expectation = expectation(description: "Voice state notification received")
        
        var receivedState: String?
        
        let observer = NotificationCenter.default.addObserver(
            forName: .carPlayVoiceStateChanged,
            object: nil,
            queue: .main
        ) { notification in
            receivedState = notification.userInfo?["state"] as? String
            expectation.fulfill()
        }
        
        CarPlayVoiceController.postVoiceStateChange(.listening)
        
        waitForExpectations(timeout: 1.0)
        
        XCTAssertEqual(receivedState, "listening")
        
        NotificationCenter.default.removeObserver(observer)
    }
    
    // MARK: - PTT Notification Handler Tests
    
    func testPTTNotificationPostsCorrectly() {
        let expectation = expectation(description: "PTT notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .carPlayPTTPressed,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        
        NotificationCenter.default.post(name: .carPlayPTTPressed, object: nil)
        
        waitForExpectations(timeout: 1.0)
        
        NotificationCenter.default.removeObserver(observer)
    }
    
    func testStopNotificationPostsCorrectly() {
        let expectation = expectation(description: "Stop notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .carPlayStopPressed,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        
        NotificationCenter.default.post(name: .carPlayStopPressed, object: nil)
        
        waitForExpectations(timeout: 1.0)
        
        NotificationCenter.default.removeObserver(observer)
    }
}
