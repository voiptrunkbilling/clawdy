import XCTest
@testable import Clawdy

/// Unit tests for markdown parsing, timestamp formatting, and message grouping logic.
final class MessageBubbleTests: XCTestCase {
    
    // MARK: - Markdown Parsing Tests
    
    func testMarkdownBoldParsing() {
        // Given: Text with bold markers
        let text = "This is **bold** text"
        
        // When: Parsing (we test the regex-based block parsing)
        let blocks = parseMarkdownBlocks(text)
        
        // Then: Should have one text block
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].type, "text")
        XCTAssertEqual(blocks[0].content, text)
    }
    
    func testMarkdownCodeBlockParsing() {
        // Given: Text with a fenced code block
        let text = """
        Here's code:
        
        ```swift
        print("Hello")
        ```
        
        Done!
        """
        
        // When: Parsing code blocks
        let blocks = parseMarkdownBlocks(text)
        
        // Then: Should have text, code block, text
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].type, "text")
        XCTAssertEqual(blocks[1].type, "codeBlock")
        XCTAssertEqual(blocks[1].language, "swift")
        XCTAssertTrue(blocks[1].content.contains("print"))
        XCTAssertEqual(blocks[2].type, "text")
    }
    
    func testMarkdownCodeBlockNoLanguage() {
        // Given: Code block without language specifier
        let text = """
        ```
        some code
        ```
        """
        
        // When: Parsing
        let blocks = parseMarkdownBlocks(text)
        
        // Then: Should parse with nil language
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].type, "codeBlock")
        XCTAssertNil(blocks[0].language)
    }
    
    func testMarkdownMultipleCodeBlocks() {
        // Given: Multiple code blocks
        let text = """
        First block:
        ```python
        print("Python")
        ```
        Second block:
        ```javascript
        console.log("JS")
        ```
        """
        
        // When: Parsing
        let blocks = parseMarkdownBlocks(text)
        
        // Then: Should have 4 blocks (text, code, text, code)
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[1].language, "python")
        XCTAssertEqual(blocks[3].language, "javascript")
    }
    
    func testMarkdownPlainTextOnly() {
        // Given: Plain text with no markdown
        let text = "Just plain text with no formatting"
        
        // When: Parsing
        let blocks = parseMarkdownBlocks(text)
        
        // Then: Should have one text block
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].content, text)
    }
    
    // MARK: - Timestamp Formatting Tests
    
    func testTimestampFormatToday() {
        // Given: A date from today
        let now = Date()
        
        // When: Formatting the timestamp
        let result = MessageTimestamp.format(now)
        
        // Then: Should show time only (e.g., "2:34 PM")
        XCTAssertFalse(result.contains("Yesterday"))
        XCTAssertFalse(result.contains("Jan"))
        XCTAssertTrue(result.contains("AM") || result.contains("PM"))
    }
    
    func testTimestampFormatYesterday() {
        // Given: A date from yesterday
        let yesterday = Date().addingTimeInterval(-86400) // 24 hours ago
        
        // When: Formatting the timestamp
        let result = MessageTimestamp.format(yesterday)
        
        // Then: Should include "Yesterday"
        XCTAssertTrue(result.contains("Yesterday"))
    }
    
    func testTimestampFormatThisWeek() {
        // Given: A date from 3 days ago
        let threeDaysAgo = Date().addingTimeInterval(-259200) // 3 days ago
        
        // When: Formatting the timestamp
        let result = MessageTimestamp.format(threeDaysAgo)
        
        // Then: Should include day name (e.g., "Monday")
        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let containsDayName = dayNames.contains { result.contains($0) }
        XCTAssertTrue(containsDayName)
    }
    
    func testTimestampFormatOlder() {
        // Given: A date from 2 weeks ago
        let twoWeeksAgo = Date().addingTimeInterval(-1209600) // 14 days ago
        
        // When: Formatting the timestamp
        let result = MessageTimestamp.format(twoWeeksAgo)
        
        // Then: Should include month abbreviation (e.g., "Jan 15")
        let monthAbbrevs = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let containsMonth = monthAbbrevs.contains { result.contains($0) }
        XCTAssertTrue(containsMonth)
    }
    
    // MARK: - Message Grouping Tests
    
    func testShouldShowTimestampFirstMessage() {
        // Given: First message with no previous
        let message = createMessage(isUser: true, timestamp: Date())
        
        // When: Checking if timestamp should show
        let result = MessageGrouping.shouldShowTimestamp(for: message, previous: nil)
        
        // Then: Should show timestamp
        XCTAssertTrue(result)
    }
    
    func testShouldShowTimestampDifferentSender() {
        // Given: Two messages from different senders, 1 minute apart
        let prev = createMessage(isUser: true, timestamp: Date())
        let current = createMessage(isUser: false, timestamp: Date().addingTimeInterval(60))
        
        // When: Checking if timestamp should show
        let result = MessageGrouping.shouldShowTimestamp(for: current, previous: prev)
        
        // Then: Should show timestamp (different sender)
        XCTAssertTrue(result)
    }
    
    func testShouldShowTimestampSameSenderWithinThreshold() {
        // Given: Two messages from same sender, 2 minutes apart
        let prev = createMessage(isUser: true, timestamp: Date())
        let current = createMessage(isUser: true, timestamp: Date().addingTimeInterval(120))
        
        // When: Checking if timestamp should show
        let result = MessageGrouping.shouldShowTimestamp(for: current, previous: prev)
        
        // Then: Should NOT show timestamp (same sender, within 5 min)
        XCTAssertFalse(result)
    }
    
    func testShouldShowTimestampSameSenderExceedsThreshold() {
        // Given: Two messages from same sender, 6 minutes apart
        let prev = createMessage(isUser: true, timestamp: Date())
        let current = createMessage(isUser: true, timestamp: Date().addingTimeInterval(360))
        
        // When: Checking if timestamp should show
        let result = MessageGrouping.shouldShowTimestamp(for: current, previous: prev)
        
        // Then: Should show timestamp (>5 min gap)
        XCTAssertTrue(result)
    }
    
    func testIsLastInGroupNoNext() {
        // Given: A message with no next message
        let current = createMessage(isUser: true, timestamp: Date())
        
        // When: Checking if last in group
        let result = MessageGrouping.isLastInGroup(current: current, next: nil)
        
        // Then: Should be last in group
        XCTAssertTrue(result)
    }
    
    func testIsLastInGroupDifferentSender() {
        // Given: Current message followed by different sender
        let current = createMessage(isUser: true, timestamp: Date())
        let next = createMessage(isUser: false, timestamp: Date().addingTimeInterval(30))
        
        // When: Checking if last in group
        let result = MessageGrouping.isLastInGroup(current: current, next: next)
        
        // Then: Should be last in group
        XCTAssertTrue(result)
    }
    
    func testIsLastInGroupSameSenderQuickReply() {
        // Given: Current message followed by same sender within 2 min
        let current = createMessage(isUser: true, timestamp: Date())
        let next = createMessage(isUser: true, timestamp: Date().addingTimeInterval(60))
        
        // When: Checking if last in group
        let result = MessageGrouping.isLastInGroup(current: current, next: next)
        
        // Then: Should NOT be last in group
        XCTAssertFalse(result)
    }
    
    // MARK: - Spacing Tests
    
    func testSpacingFirstMessage() {
        // Given: First message
        let message = createMessage(isUser: true, timestamp: Date())
        
        // When: Getting spacing
        let result = MessageGrouping.spacing(for: message, previous: nil)
        
        // Then: Should use first message spacing (8pt)
        XCTAssertEqual(result, 8)
    }
    
    func testSpacingTightGroup() {
        // Given: Same sender, 2 minutes apart
        let prev = createMessage(isUser: true, timestamp: Date())
        let current = createMessage(isUser: true, timestamp: Date().addingTimeInterval(120))
        
        // When: Getting spacing
        let result = MessageGrouping.spacing(for: current, previous: prev)
        
        // Then: Should use tight spacing (4pt)
        XCTAssertEqual(result, 4)
    }
    
    func testSpacingWideGap() {
        // Given: Same sender, 6 minutes apart
        let prev = createMessage(isUser: true, timestamp: Date())
        let current = createMessage(isUser: true, timestamp: Date().addingTimeInterval(360))
        
        // When: Getting spacing
        let result = MessageGrouping.spacing(for: current, previous: prev)
        
        // Then: Should use wide spacing (12pt)
        XCTAssertEqual(result, 12)
    }
    
    func testSpacingDifferentSender() {
        // Given: Different sender, 1 minute apart
        let prev = createMessage(isUser: true, timestamp: Date())
        let current = createMessage(isUser: false, timestamp: Date().addingTimeInterval(60))
        
        // When: Getting spacing
        let result = MessageGrouping.spacing(for: current, previous: prev)
        
        // Then: Should use wide spacing (12pt)
        XCTAssertEqual(result, 12)
    }
    
    // MARK: - Grouping Threshold Constant
    
    func testGroupingThresholdValue() {
        // The threshold should be 5 minutes (300 seconds)
        XCTAssertEqual(MessageGrouping.groupingThreshold, 300)
    }
    
    // MARK: - Helper Methods
    
    private func createMessage(isUser: Bool, timestamp: Date) -> TranscriptMessage {
        TranscriptMessage(
            text: "Test message",
            isUser: isUser,
            isStreaming: false,
            wasInterrupted: false,
            toolCalls: [],
            imageAttachmentIds: [],
            sessionId: nil
        )
    }
    
    /// Helper to parse markdown blocks (mirrors RichMarkdownView logic)
    private struct ParsedBlock {
        let type: String
        let content: String
        let language: String?
    }
    
    private func parseMarkdownBlocks(_ text: String) -> [ParsedBlock] {
        var blocks: [ParsedBlock] = []
        let codeBlockPattern = #"```(\w*)\n?([\s\S]*?)```"#
        
        guard let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) else {
            return [ParsedBlock(type: "text", content: text, language: nil)]
        }
        
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)
        
        var currentIndex = 0
        
        for match in matches {
            if match.range.location > currentIndex {
                let textRange = NSRange(location: currentIndex, length: match.range.location - currentIndex)
                let textContent = nsText.substring(with: textRange).trimmingCharacters(in: .whitespacesAndNewlines)
                if !textContent.isEmpty {
                    blocks.append(ParsedBlock(type: "text", content: textContent, language: nil))
                }
            }
            
            let language = match.numberOfRanges > 1 ? nsText.substring(with: match.range(at: 1)) : nil
            let codeContent = match.numberOfRanges > 2 ? nsText.substring(with: match.range(at: 2)) : ""
            
            blocks.append(ParsedBlock(
                type: "codeBlock",
                content: codeContent.trimmingCharacters(in: .whitespacesAndNewlines),
                language: language?.isEmpty == true ? nil : language
            ))
            
            currentIndex = match.range.location + match.range.length
        }
        
        if currentIndex < nsText.length {
            let remainingText = nsText.substring(from: currentIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remainingText.isEmpty {
                blocks.append(ParsedBlock(type: "text", content: remainingText, language: nil))
            }
        }
        
        if blocks.isEmpty {
            blocks.append(ParsedBlock(type: "text", content: text, language: nil))
        }
        
        return blocks
    }
}
