import SwiftUI

/// A view that renders markdown text using iOS 15+ AttributedString.
/// Supports bold, italic, inline code, code blocks, and lists.
/// Falls back to plain text if markdown parsing fails.
struct MarkdownTextView: View {
    let text: String
    let foregroundColor: Color
    
    /// Cache for parsed attributed strings to improve scroll performance
    private static var attributedStringCache = NSCache<NSString, NSAttributedString>()
    
    init(_ text: String, foregroundColor: Color = .primary) {
        self.text = text
        self.foregroundColor = foregroundColor
    }
    
    var body: some View {
        if let attributedText = parseMarkdown() {
            Text(attributedText)
                .textSelection(.enabled)
        } else {
            // Fallback to plain text if parsing fails
            Text(text)
                .foregroundStyle(foregroundColor)
                .textSelection(.enabled)
        }
    }
    
    /// Parse markdown text to AttributedString.
    /// Returns nil if parsing fails (caller should fall back to plain text).
    private func parseMarkdown() -> AttributedString? {
        // Check cache first
        let cacheKey = text as NSString
        if let cached = Self.attributedStringCache.object(forKey: cacheKey) {
            // Convert NSAttributedString back to AttributedString
            do {
                var attributed = try AttributedString(cached, including: \.swiftUI)
                // Apply foreground color
                attributed.foregroundColor = foregroundColor
                return attributed
            } catch {
                // Fall through to re-parse
            }
        }
        
        do {
            // Parse markdown using iOS 15+ native support
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            
            var attributed = try AttributedString(markdown: text, options: options)
            
            // Apply base foreground color
            attributed.foregroundColor = foregroundColor
            
            // Process inline code styling
            attributed = processInlineCode(in: attributed)
            
            // Cache the result (convert to NSAttributedString for caching)
            let nsAttributed = try NSAttributedString(attributed, including: \.uiKit)
            Self.attributedStringCache.setObject(nsAttributed, forKey: cacheKey)
            
            return attributed
        } catch {
            print("[MarkdownTextView] Failed to parse markdown: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Apply monospace font styling to inline code spans.
    private func processInlineCode(in text: AttributedString) -> AttributedString {
        var result = text
        
        // Find and style inline code (marked with InlineCode presentation intent)
        for (range, intent) in result.runs[\.inlinePresentationIntent] {
            if let intent = intent, intent.contains(.code) {
                result[range].font = .system(.body, design: .monospaced)
                result[range].backgroundColor = Color.inlineCodeBackground
            }
        }
        
        return result
    }
}

// MARK: - Code Block View

/// A dedicated view for rendering fenced code blocks with proper styling.
struct CodeBlockView: View {
    let code: String
    let language: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label if specified
            if let lang = language, !lang.isEmpty {
                Text(lang)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }
            
            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
            }
        }
        .background(Color.codeBlockBackground)
        .cornerRadius(8)
        .accessibilityLabel("Code block: \(code)")
    }
}

// MARK: - Rich Markdown View

/// A view that handles complex markdown including code blocks.
/// Use this for messages that may contain fenced code blocks.
struct RichMarkdownView: View {
    let text: String
    let foregroundColor: Color
    
    init(_ text: String, foregroundColor: Color = .primary) {
        self.text = text
        self.foregroundColor = foregroundColor
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseBlocks(), id: \.id) { block in
                switch block.type {
                case .text:
                    MarkdownTextView(block.content, foregroundColor: foregroundColor)
                case .codeBlock:
                    CodeBlockView(code: block.content, language: block.language)
                }
            }
        }
    }
    
    /// Block types for markdown parsing
    private enum BlockType {
        case text
        case codeBlock
    }
    
    /// Parsed block with type and content
    private struct ParsedBlock: Identifiable {
        let id = UUID()
        let type: BlockType
        let content: String
        let language: String?
    }
    
    /// Parse text into alternating text and code blocks.
    private func parseBlocks() -> [ParsedBlock] {
        var blocks: [ParsedBlock] = []
        
        // Regex to find fenced code blocks: ```language\ncode\n```
        let codeBlockPattern = #"```(\w*)\n?([\s\S]*?)```"#
        
        guard let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) else {
            // If regex fails, return entire text as a single block
            return [ParsedBlock(type: .text, content: text, language: nil)]
        }
        
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)
        
        var currentIndex = 0
        
        for match in matches {
            // Add text before this code block
            if match.range.location > currentIndex {
                let textRange = NSRange(location: currentIndex, length: match.range.location - currentIndex)
                let textContent = nsText.substring(with: textRange).trimmingCharacters(in: .whitespacesAndNewlines)
                if !textContent.isEmpty {
                    blocks.append(ParsedBlock(type: .text, content: textContent, language: nil))
                }
            }
            
            // Extract language and code content
            let language = match.numberOfRanges > 1 ? nsText.substring(with: match.range(at: 1)) : nil
            let codeContent = match.numberOfRanges > 2 ? nsText.substring(with: match.range(at: 2)) : ""
            
            blocks.append(ParsedBlock(
                type: .codeBlock,
                content: codeContent.trimmingCharacters(in: .whitespacesAndNewlines),
                language: language?.isEmpty == true ? nil : language
            ))
            
            currentIndex = match.range.location + match.range.length
        }
        
        // Add remaining text after last code block
        if currentIndex < nsText.length {
            let remainingText = nsText.substring(from: currentIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remainingText.isEmpty {
                blocks.append(ParsedBlock(type: .text, content: remainingText, language: nil))
            }
        }
        
        // If no blocks were created, return the entire text
        if blocks.isEmpty {
            blocks.append(ParsedBlock(type: .text, content: text, language: nil))
        }
        
        return blocks
    }
}

// MARK: - Timestamp Formatting

/// Formats timestamps for message display.
struct MessageTimestamp {
    
    /// Format a timestamp for display.
    /// - Returns: "2:34 PM" for today, "Yesterday 2:34 PM", or "Jan 15 2:34 PM"
    static func format(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let timeString = timeFormatter.string(from: date)
        
        if calendar.isDateInToday(date) {
            return timeString
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday \(timeString)"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEEE"
            return "\(dayFormatter.string(from: date)) \(timeString)"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            return "\(dateFormatter.string(from: date)) \(timeString)"
        }
    }
}

// MARK: - Message Grouping

/// Logic for grouping messages and determining spacing.
struct MessageGrouping {
    
    /// Threshold for grouping messages (5 minutes in seconds)
    static let groupingThreshold: TimeInterval = 300
    
    /// Determines if a timestamp should be shown for this message.
    /// Show timestamp when:
    /// - First message in transcript
    /// - Different sender than previous
    /// - More than 5 minutes since previous message
    static func shouldShowTimestamp(for message: TranscriptMessage, previous: TranscriptMessage?) -> Bool {
        guard let prev = previous else { return true }
        let timeDiff = message.timestamp.timeIntervalSince(prev.timestamp)
        return message.isUser != prev.isUser || timeDiff > groupingThreshold
    }
    
    /// Determines if this message is the last in a group (next message starts a new group).
    /// Used to know when to actually display the timestamp.
    static func isLastInGroup(current: TranscriptMessage, next: TranscriptMessage?) -> Bool {
        guard let next = next else { return true }
        let timeDiff = next.timestamp.timeIntervalSince(current.timestamp)
        return current.isUser != next.isUser || timeDiff > groupingThreshold
    }
    
    /// Determines the vertical spacing before this message.
    /// - 4pt: Same sender and <5min gap (tight grouping)
    /// - 12pt: Different sender or >5min gap
    static func spacing(for message: TranscriptMessage, previous: TranscriptMessage?) -> CGFloat {
        guard let prev = previous else { return 8 }
        let timeDiff = message.timestamp.timeIntervalSince(prev.timestamp)
        
        if message.isUser == prev.isUser && timeDiff <= groupingThreshold {
            return 4 // Tight spacing within groups
        } else {
            return 12 // Wider spacing between groups
        }
    }
}

// MARK: - Preview

#Preview("Markdown Examples") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            RichMarkdownView("**Bold text** and *italic text*")
            
            RichMarkdownView("Here is some `inline code` in a sentence.")
            
            RichMarkdownView("""
            Here's a code example:
            
            ```swift
            func hello() {
                print("Hello, world!")
            }
            ```
            
            That's how it works!
            """)
            
            RichMarkdownView("""
            A list:
            - First item
            - Second item
            - Third item
            """)
        }
        .padding()
    }
}

#Preview("Timestamps") {
    VStack(alignment: .leading, spacing: 8) {
        Text(MessageTimestamp.format(Date()))
        Text(MessageTimestamp.format(Date().addingTimeInterval(-86400)))
        Text(MessageTimestamp.format(Date().addingTimeInterval(-172800)))
        Text(MessageTimestamp.format(Date().addingTimeInterval(-604800)))
    }
    .padding()
}
