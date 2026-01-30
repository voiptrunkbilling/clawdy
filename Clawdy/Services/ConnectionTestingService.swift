import Foundation

/// Service for testing the gateway WebSocket connection.
///
/// NOTE: This service is kept for potential future debugging use.
/// The Settings UI now uses GatewayDualConnectionManager.testConnection() directly.
///
/// This service helps validate that:
/// 1. WebSocket connection establishes successfully
/// 2. Chat operations work correctly over WebSocket
/// 3. Connection handshake completes properly
actor ConnectionTestingService {
    
    // MARK: - Test Results
    
    struct TestResult: Sendable {
        let testName: String
        let success: Bool
        let duration: TimeInterval
        let error: String?
        let data: String?
    }
    
    struct TestReport: Sendable {
        let timestamp: Date
        let host: String
        let results: [TestResult]
        let overallSuccess: Bool
        
        var summary: String {
            let passCount = results.filter { $0.success }.count
            return "\(passCount)/\(results.count) tests passed"
        }
    }
    
    // MARK: - Properties
    
    private let host: String
    private let sessionKey: String
    
    // MARK: - Initialization
    
    /// Create a testing service for the given gateway configuration.
    /// - Parameters:
    ///   - host: Gateway hostname or IP
    ///   - sessionKey: Chat session key (default "agent:main:main")
    init(host: String, sessionKey: String = "agent:main:main") {
        self.host = host
        self.sessionKey = sessionKey
    }
    
    // MARK: - Test Execution
    
    /// Run a connection test to verify WebSocket connectivity.
    /// Tests connection, history loading, and basic operations.
    /// - Returns: TestReport with results for each test
    func runConnectionTest() async -> TestReport {
        print("[ConnectionTesting] Starting connection test for \(host)")
        
        var results: [TestResult] = []
        
        // Test 1: Connection establishment
        let connectionResult = await testConnection()
        results.append(connectionResult)
        
        // Only proceed with other tests if connection succeeded
        if connectionResult.success {
            // Test 2: Load history
            let historyResult = await testHistory()
            results.append(historyResult)
        }
        
        let allPassed = results.allSatisfy { $0.success }
        
        let report = TestReport(
            timestamp: Date(),
            host: host,
            results: results,
            overallSuccess: allPassed
        )
        
        print("[ConnectionTesting] Test complete: \(report.summary)")
        return report
    }
    
    /// Test WebSocket connection only.
    /// Use this for quick validation that the connection works.
    /// - Returns: True if connection succeeds
    func testWebSocketOnly() async -> Bool {
        print("[ConnectionTesting] Testing WebSocket connection to \(host):18789")
        
        let connectionManager = await MainActor.run { GatewayDualConnectionManager.shared }
        let isConnected = await MainActor.run { connectionManager.status.isConnected }
        
        print("[ConnectionTesting] WebSocket isConnected: \(isConnected)")
        return isConnected
    }
    
    // MARK: - Individual Tests
    
    private func testConnection() async -> TestResult {
        print("[ConnectionTesting] Test 1: Connection establishment")
        
        let start = Date()
        let connectionManager = await MainActor.run { GatewayDualConnectionManager.shared }
        let isConnected = await MainActor.run { connectionManager.status.isConnected }
        
        if isConnected {
            // Extract server name if available
            let serverName = await MainActor.run { connectionManager.serverName ?? "Gateway" }
            
            return TestResult(
                testName: "Connection",
                success: true,
                duration: Date().timeIntervalSince(start),
                error: nil,
                data: "Connected to \(serverName)"
            )
        } else {
            let status = await MainActor.run { connectionManager.status }
            return TestResult(
                testName: "Connection",
                success: false,
                duration: Date().timeIntervalSince(start),
                error: status.displayText,
                data: nil
            )
        }
    }
    
    private func testHistory() async -> TestResult {
        print("[ConnectionTesting] Test 2: Load chat history")
        
        let start = Date()
        let connectionManager = await MainActor.run { GatewayDualConnectionManager.shared }
        
        do {
            let data = try await connectionManager.loadHistory(limit: 10)
            
            // Try to parse message count
            var messageCount: Int?
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let messages = json["messages"] as? [[String: Any]] {
                messageCount = messages.count
            }
            
            return TestResult(
                testName: "History",
                success: true,
                duration: Date().timeIntervalSince(start),
                error: nil,
                data: messageCount.map { "\($0) messages" } ?? "History loaded"
            )
        } catch {
            return TestResult(
                testName: "History",
                success: false,
                duration: Date().timeIntervalSince(start),
                error: error.localizedDescription,
                data: nil
            )
        }
    }
}

// MARK: - Debug View Support

extension ConnectionTestingService {
    
    /// Format a test report for display in a debug UI.
    static func formatReport(_ report: TestReport) -> String {
        var lines: [String] = []
        
        lines.append("Connection Test Report")
        lines.append("======================")
        lines.append("Host: \(report.host)")
        lines.append("Time: \(report.timestamp)")
        lines.append("Result: \(report.overallSuccess ? "✅ PASS" : "❌ FAIL")")
        lines.append("")
        
        for result in report.results {
            let icon = result.success ? "✅" : "❌"
            lines.append("\(icon) \(result.testName)")
            lines.append("   Duration: \(String(format: "%.2f", result.duration))s")
            if let data = result.data {
                lines.append("   \(data)")
            }
            if let error = result.error {
                lines.append("   Error: \(error)")
            }
            lines.append("")
        }
        
        lines.append(report.summary)
        
        return lines.joined(separator: "\n")
    }
}
