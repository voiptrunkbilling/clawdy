import SwiftUI

/// A chat message bubble with proper styling for user and assistant messages.
/// Supports markdown rendering, images, tool calls, and streaming indicators.
///
/// ## Styling per ticket 19b9d00b:
/// - 16pt corner radius
/// - 12pt horizontal, 8pt vertical padding
/// - User: blue background (#0A84FF), white text, subtle shadow
/// - Assistant: gray background (#F2F2F7 light / #3A3A3C dark), black text
/// - Max width: 80% of container width (supports Split View/landscape)
struct MessageBubble: View {
    let message: TranscriptMessage
    
    /// Image store for resolving image attachment IDs to actual images
    let imageStore: ImageAttachmentStore
    
    /// Callback when an image thumbnail is tapped (for Quick Look full-screen view)
    let onImageTap: (ImageAttachment) -> Void
    
    /// Whether to show the sender label (You/Clawdy) - shown at start of message groups
    var showSenderLabel: Bool = true
    
    /// Whether to show the timestamp - shown at end of message groups
    var showTimestamp: Bool = false
    
    /// Container width for calculating max bubble width (supports Split View/landscape)
    /// If nil, falls back to UIScreen width for backward compatibility
    var containerWidth: CGFloat? = nil
    
    // MARK: - Constants
    
    private let cornerRadius: CGFloat = 16
    private let horizontalPadding: CGFloat = 12
    private let verticalPadding: CGFloat = 8
    private let maxWidthRatio: CGFloat = 0.8
    
    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
            // Sender label only shown at start of message group
            if showSenderLabel {
                Text(message.isUser ? "You" : "Clawdy")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true) // Included in combined label below
            }
            
            // Message content bubble
            bubbleContent
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(
                    color: message.isUser ? .black.opacity(0.1) : .clear,
                    radius: message.isUser ? 2 : 0,
                    x: 0,
                    y: message.isUser ? 1 : 0
                )
                .overlay(
                    StreamingBorderOverlay(isStreaming: message.isStreaming)
                )
            
            // Timestamp at end of message group
            if showTimestamp {
                Text(MessageTimestamp.format(message.timestamp))
                    .font(.caption2)
                    .foregroundStyle(Color(.systemGray))
                    .accessibilityLabel("Sent \(MessageTimestamp.format(message.timestamp))")
            }
        }
        .frame(maxWidth: maxBubbleWidth, alignment: message.isUser ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }
    
    /// Calculate max bubble width based on container width (supports Split View/landscape)
    private var maxBubbleWidth: CGFloat {
        let baseWidth = containerWidth ?? UIScreen.main.bounds.width
        return baseWidth * maxWidthRatio
    }
    
    // MARK: - Bubble Content
    
    @ViewBuilder
    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Images first (iMessage style - images appear above text)
            if !message.imageAttachmentIds.isEmpty {
                MessageImageGrid(
                    attachmentIds: message.imageAttachmentIds,
                    imageStore: imageStore,
                    onTap: onImageTap
                )
            }
            
            // Main message text with markdown rendering
            if !message.text.isEmpty {
                RichMarkdownView(
                    message.text,
                    foregroundColor: message.isUser ? .onUserBubble : .primary
                )
            }
            
            // Inline tool calls (only for Claude's messages)
            if !message.isUser && !message.toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(message.toolCalls) { toolCall in
                        CollapsibleToolCallView(toolCall: toolCall)
                    }
                }
            }
        }
    }
    
    // MARK: - Styling
    
    /// Background color for the message bubble
    private var bubbleBackground: Color {
        if message.isUser {
            return Color.userBubbleBackground
        } else {
            return Color.assistantBubbleBackground
        }
    }
    
    // MARK: - Accessibility
    
    /// Builds an accessibility label that includes message text, images, and tool call summary
    private var accessibilityLabel: String {
        var label = message.isUser ? "You said" : "Claude said"
        
        // Include image count if present
        let imageCount = message.imageAttachmentIds.count
        if imageCount > 0 {
            label += " with \(imageCount) image\(imageCount == 1 ? "" : "s")"
        }
        
        if !message.text.isEmpty {
            label += ": \(message.text)"
        }
        
        if !message.toolCalls.isEmpty {
            let toolNames = message.toolCalls.map { $0.name }.joined(separator: ", ")
            let toolCount = message.toolCalls.count
            label += ". Used \(toolCount) tool\(toolCount == 1 ? "" : "s"): \(toolNames)"
        }
        
        if showTimestamp {
            label += ". \(MessageTimestamp.format(message.timestamp))"
        }
        
        return label
    }
}

// MARK: - Streaming Border Overlay

/// Pulsing border overlay shown during message streaming.
/// Uses its own view identity to ensure animation state resets when streaming ends.
struct StreamingBorderOverlay: View {
    let isStreaming: Bool
    @State private var isPulsing = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                Color.blue.opacity(isStreaming ? (isPulsing ? 0.8 : 0.3) : 0),
                lineWidth: isStreaming ? 2 : 0
            )
            .animation(
                isStreaming ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: isPulsing
            )
            .onAppear {
                if isStreaming {
                    isPulsing = true
                }
            }
            .onChange(of: isStreaming) { _, streaming in
                isPulsing = streaming
            }
    }
}

// MARK: - Previews

#Preview("User Message") {
    VStack(spacing: 16) {
        MessageBubble(
            message: TranscriptMessage(
                text: "Hello! How are you today?",
                isUser: true
            ),
            imageStore: ImageAttachmentStore(),
            onImageTap: { _ in },
            showSenderLabel: true,
            showTimestamp: true
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding()
}

#Preview("Assistant Message") {
    VStack(spacing: 16) {
        MessageBubble(
            message: TranscriptMessage(
                text: "I'm doing great! Here's some **bold** text and `inline code`.",
                isUser: false
            ),
            imageStore: ImageAttachmentStore(),
            onImageTap: { _ in },
            showSenderLabel: true,
            showTimestamp: true
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding()
}

#Preview("Markdown Code Block") {
    VStack(spacing: 16) {
        MessageBubble(
            message: TranscriptMessage(
                text: """
                Here's a code example:
                
                ```swift
                func greet() {
                    print("Hello!")
                }
                ```
                
                Hope that helps!
                """,
                isUser: false
            ),
            imageStore: ImageAttachmentStore(),
            onImageTap: { _ in },
            showSenderLabel: true,
            showTimestamp: false
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding()
}

#Preview("Message Group") {
    VStack(spacing: 4) {
        // First message in group - show sender label
        MessageBubble(
            message: TranscriptMessage(text: "First message", isUser: true),
            imageStore: ImageAttachmentStore(),
            onImageTap: { _ in },
            showSenderLabel: true,
            showTimestamp: false
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
        
        // Middle message - no sender, no timestamp
        MessageBubble(
            message: TranscriptMessage(text: "Second message", isUser: true),
            imageStore: ImageAttachmentStore(),
            onImageTap: { _ in },
            showSenderLabel: false,
            showTimestamp: false
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
        
        // Last message in group - show timestamp
        MessageBubble(
            message: TranscriptMessage(text: "Third message", isUser: true),
            imageStore: ImageAttachmentStore(),
            onImageTap: { _ in },
            showSenderLabel: false,
            showTimestamp: true
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding()
}

#Preview("Dark Mode") {
    VStack(spacing: 16) {
        MessageBubble(
            message: TranscriptMessage(text: "User message in dark mode", isUser: true),
            imageStore: ImageAttachmentStore(),
            onImageTap: { _ in },
            showTimestamp: true
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
        
        MessageBubble(
            message: TranscriptMessage(text: "Assistant message in dark mode with **bold** and `code`", isUser: false),
            imageStore: ImageAttachmentStore(),
            onImageTap: { _ in },
            showTimestamp: true
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Dynamic Type - Large") {
    VStack(spacing: 16) {
        MessageBubble(
            message: TranscriptMessage(text: "Large text accessibility", isUser: true),
            imageStore: ImageAttachmentStore(),
            onImageTap: { _ in },
            showTimestamp: true
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
        
        MessageBubble(
            message: TranscriptMessage(text: "Assistant with large text", isUser: false),
            imageStore: ImageAttachmentStore(),
            onImageTap: { _ in },
            showTimestamp: true
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding()
    .environment(\.sizeCategory, .accessibilityLarge)
}
