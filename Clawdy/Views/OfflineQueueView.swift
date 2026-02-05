import SwiftUI

/// View for displaying and managing the offline message queue.
/// Shows pending and failed messages with manual retry capability.
struct OfflineQueueView: View {
    @ObservedObject var queue: OfflineMessageQueue
    var onRetry: ((UUID) async -> Bool)?
    var onDismiss: (() -> Void)?
    
    @State private var retryingMessageId: UUID?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Capacity warning banner
                if case .nearFull(let messagePercent, let sizePercent) = queue.capacityWarning {
                    CapacityWarningBanner(
                        messagePercent: messagePercent,
                        sizePercent: sizePercent
                    )
                }
                
                // Queue stats
                QueueStatsHeader(
                    messageCount: queue.messageCount,
                    sizeBytes: queue.queueSizeBytes,
                    failedCount: queue.failedMessages.count
                )
                
                if queue.messageCount == 0 {
                    EmptyQueueView()
                } else {
                    messageList
                }
            }
            .navigationTitle("Offline Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        onDismiss?()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !queue.failedMessages.isEmpty {
                        Button("Clear Failed") {
                            clearFailedMessages()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }
    
    private var messageList: some View {
        List {
            // Failed messages section
            if !queue.failedMessages.isEmpty {
                Section {
                    ForEach(queue.failedMessages) { message in
                        FailedMessageRow(
                            message: message,
                            isRetrying: retryingMessageId == message.id,
                            onRetry: {
                                Task {
                                    await retryMessage(message.id)
                                }
                            },
                            onRemove: {
                                queue.removeMessage(id: message.id)
                            }
                        )
                    }
                } header: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Failed Messages")
                    }
                } footer: {
                    Text("These messages could not be delivered. Tap retry to try again.")
                        .font(.caption)
                }
            }
            
            // Pending messages section
            let pendingMessages = queue.getPendingMessages()
            if !pendingMessages.isEmpty {
                Section {
                    ForEach(pendingMessages) { message in
                        PendingMessageRow(message: message)
                    }
                } header: {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                        Text("Pending")
                    }
                } footer: {
                    Text("These messages will be sent when you're back online.")
                        .font(.caption)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func retryMessage(_ id: UUID) async {
        retryingMessageId = id
        defer { retryingMessageId = nil }
        
        if let onRetry = onRetry {
            _ = await onRetry(id)
        }
    }
    
    private func clearFailedMessages() {
        for message in queue.failedMessages {
            queue.removeMessage(id: message.id)
        }
    }
}

// MARK: - Subviews

/// Banner shown when queue is nearing capacity
private struct CapacityWarningBanner: View {
    let messagePercent: Int
    let sizePercent: Int
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Queue Nearly Full")
                    .font(.subheadline.bold())
                Text("\(max(messagePercent, sizePercent))% capacity used")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.yellow.opacity(0.15))
    }
}

/// Header showing queue statistics
private struct QueueStatsHeader: View {
    let messageCount: Int
    let sizeBytes: Int
    let failedCount: Int
    
    private var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(sizeBytes))
    }
    
    var body: some View {
        HStack(spacing: 20) {
            StatItem(
                icon: "envelope.fill",
                value: "\(messageCount)",
                label: "Messages",
                color: .blue
            )
            
            StatItem(
                icon: "internaldrive",
                value: formattedSize,
                label: "Size",
                color: .purple
            )
            
            if failedCount > 0 {
                StatItem(
                    icon: "xmark.circle.fill",
                    value: "\(failedCount)",
                    label: "Failed",
                    color: .red
                )
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

/// Individual statistic item
private struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Empty state view
private struct EmptyQueueView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundColor(.green)
            
            Text("Queue is Empty")
                .font(.title2.bold())
            
            Text("All messages have been delivered")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

/// Row for a failed message with retry button
private struct FailedMessageRow: View {
    let message: OfflineMessageQueue.QueuedMessage
    let isRetrying: Bool
    let onRetry: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(message.content)
                    .font(.body)
                    .lineLimit(2)
                
                Spacer()
                
                if isRetrying {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            HStack {
                // Timestamp
                Text(message.ageDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Attachment indicator
                if let attachments = message.attachments, !attachments.isEmpty {
                    Image(systemName: "paperclip")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(attachments.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Error message
                if let error = message.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button {
                    onRetry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.footnote.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isRetrying)
                
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
                .disabled(isRetrying)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Row for a pending message
private struct PendingMessageRow: View {
    let message: OfflineMessageQueue.QueuedMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.content)
                .font(.body)
                .lineLimit(2)
            
            HStack {
                Text(message.ageDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let attachments = message.attachments, !attachments.isEmpty {
                    Image(systemName: "paperclip")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(attachments.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status badge
                Text(message.statusText)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.2))
                    .foregroundColor(statusColor)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch message.status {
        case .pending: return .orange
        case .sending: return .blue
        case .failed: return .red
        case .duplicate: return .green
        }
    }
}

// MARK: - Inline Queue Status Indicator

/// Compact inline indicator for queue status, suitable for toolbar or header
struct OfflineQueueStatusIndicator: View {
    @ObservedObject var queue: OfflineMessageQueue
    var onTap: (() -> Void)?
    
    var body: some View {
        if queue.messageCount > 0 {
            Button {
                onTap?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: queue.failedMessages.isEmpty ? "clock.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(queue.failedMessages.isEmpty ? .orange : .red)
                    
                    Text("\(queue.messageCount)")
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray5))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Offline Queue Banner

/// Banner showing offline queue status with tap to open queue view.
/// Shows count of pending and failed messages.
struct OfflineQueueBannerView: View {
    let pendingCount: Int
    let failedCount: Int
    var onTap: (() -> Void)?
    
    private var hasFailures: Bool { failedCount > 0 }
    
    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: hasFailures ? "exclamationmark.triangle.fill" : "clock.fill")
                    .font(.title3)
                    .foregroundColor(hasFailures ? .red : .orange)
                
                // Message counts
                VStack(alignment: .leading, spacing: 2) {
                    if hasFailures {
                        Text("\(failedCount) message\(failedCount == 1 ? "" : "s") failed")
                            .font(.subheadline.bold())
                            .foregroundColor(.red)
                    }
                    
                    if pendingCount > 0 {
                        Text("\(pendingCount) message\(pendingCount == 1 ? "" : "s") queued")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if !hasFailures {
                        Text("Queue empty")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Chevron to indicate tappable
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(hasFailures ? Color.red.opacity(0.1) : Color.orange.opacity(0.1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("With Messages") {
    let queue = OfflineMessageQueue(testMode: true)
    return OfflineQueueView(queue: queue)
}

#Preview("Empty") {
    let queue = OfflineMessageQueue(testMode: true)
    return OfflineQueueView(queue: queue)
}
