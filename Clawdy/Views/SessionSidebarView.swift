import SwiftUI

/// Session sidebar overlay that slides from the left edge.
/// Displays session list with pinned and all sections.
struct SessionSidebarView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var dragOffset: CGFloat = 0
    
    /// Animation durations
    private let slideInDuration: Double = 0.3
    private let slideOutDuration: Double = 0.25
    private let dimDuration: Double = 0.2
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Dimmed background
                if sessionManager.isSidebarOpen {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            closeSidebar()
                        }
                        .gesture(
                            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                                .onEnded { value in
                                    // Swipe right to close
                                    if value.translation.width < -50 {
                                        closeSidebar()
                                    }
                                }
                        )
                }
                
                // Sidebar panel
                if sessionManager.isSidebarOpen {
                    SidebarContent(
                        sessionManager: sessionManager,
                        width: geometry.size.width * 0.75,
                        onClose: closeSidebar
                    )
                    .offset(x: dragOffset)
                    .transition(.move(edge: .leading))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Only allow dragging left (to close)
                                if value.translation.width < 0 {
                                    dragOffset = value.translation.width
                                }
                            }
                            .onEnded { value in
                                if value.translation.width < -100 {
                                    closeSidebar()
                                }
                                withAnimation(.easeOut(duration: slideOutDuration)) {
                                    dragOffset = 0
                                }
                            }
                    )
                }
            }
            .animation(.easeOut(duration: slideInDuration), value: sessionManager.isSidebarOpen)
        }
    }
    
    private func closeSidebar() {
        withAnimation(.easeIn(duration: slideOutDuration)) {
            sessionManager.closeSidebar()
            dragOffset = 0
        }
    }
}

// MARK: - Sidebar Content

private struct SidebarContent: View {
    @ObservedObject var sessionManager: SessionManager
    let width: CGFloat
    let onClose: () -> Void
    
    @State private var sessionToRename: Session?
    @State private var renameText: String = ""
    @State private var sessionToDelete: Session?
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            SidebarHeader(
                onAdd: {
                    sessionManager.isCreateSheetPresented = true
                },
                onClose: onClose
            )
            
            // Session list
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Pinned section
                    if !sessionManager.pinnedSessions.isEmpty {
                        SectionHeader(title: "Pinned")
                        
                        ForEach(sessionManager.pinnedSessions) { session in
                            SessionRow(
                                session: session,
                                isActive: session.id == sessionManager.activeSession?.id,
                                onTap: {
                                    Task {
                                        await sessionManager.switchToSession(session)
                                    }
                                },
                                onPin: {
                                    Task {
                                        await sessionManager.togglePin(session)
                                    }
                                },
                                onDelete: {
                                    if sessionManager.canDeleteSession(session) {
                                        sessionToDelete = session
                                        showDeleteConfirmation = true
                                    }
                                },
                                onRename: {
                                    sessionToRename = session
                                    renameText = session.name
                                },
                                canDelete: sessionManager.canDeleteSession(session)
                            )
                        }
                    }
                    
                    // All sessions section
                    SectionHeader(title: sessionManager.pinnedSessions.isEmpty ? "Sessions" : "All Sessions")
                    
                    ForEach(sessionManager.unpinnedSessions) { session in
                        SessionRow(
                            session: session,
                            isActive: session.id == sessionManager.activeSession?.id,
                            onTap: {
                                Task {
                                    await sessionManager.switchToSession(session)
                                }
                            },
                            onPin: {
                                Task {
                                    await sessionManager.togglePin(session)
                                }
                            },
                            onDelete: {
                                if sessionManager.canDeleteSession(session) {
                                    sessionToDelete = session
                                    showDeleteConfirmation = true
                                }
                            },
                            onRename: {
                                sessionToRename = session
                                renameText = session.name
                            },
                            canDelete: sessionManager.canDeleteSession(session)
                        )
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .frame(width: width)
        .background(Color(.systemBackground))
        .alert("Rename Session", isPresented: Binding(
            get: { sessionToRename != nil },
            set: { if !$0 { sessionToRename = nil } }
        )) {
            TextField("Session Name", text: $renameText)
            Button("Cancel", role: .cancel) {
                sessionToRename = nil
            }
            Button("Rename") {
                if let session = sessionToRename {
                    Task {
                        await sessionManager.renameSession(session, to: renameText)
                        sessionToRename = nil
                    }
                }
            }
        }
        .alert("Delete Session?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                sessionToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    Task {
                        await sessionManager.deleteSession(session)
                        sessionToDelete = nil
                    }
                }
            }
        } message: {
            if let session = sessionToDelete {
                Text("Are you sure you want to delete '\(session.name)'? This cannot be undone.")
            }
        }
    }
}

// MARK: - Sidebar Header

private struct SidebarHeader: View {
    let onAdd: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        HStack {
            Text("Sessions")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            .accessibilityLabel("Create new session")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: Session
    let isActive: Bool
    let onTap: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    let onRename: () -> Void
    let canDelete: Bool
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                SessionIcon(
                    icon: session.icon,
                    color: Color(hex: session.color) ?? .blue,
                    size: 40
                )
                
                // Name and stats
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(session.name)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        if session.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    Text(sessionStats)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Active indicator
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isActive ? Color(.systemGray5) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onPin) {
                Label(session.isPinned ? "Unpin" : "Pin", systemImage: session.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
            
            Button(action: onPin) {
                Label(session.isPinned ? "Unpin" : "Pin", systemImage: session.isPinned ? "pin.slash" : "pin")
            }
            
            Divider()
            
            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Button(action: {}) {
                    Label("Cannot delete last session", systemImage: "exclamationmark.triangle")
                }
                .disabled(true)
            }
        }
    }
    
    private var sessionStats: String {
        let messageText = session.messageCount == 1 ? "1 message" : "\(session.messageCount) messages"
        let timeText = SessionManager.formatRelativeTime(session.lastActivityAt)
        return "\(messageText) • \(timeText)"
    }
}

// MARK: - Session Icon

struct SessionIcon: View {
    let icon: String
    let color: Color
    let size: CGFloat
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
            
            Image(systemName: icon)
                .font(.system(size: size * 0.45))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Session Indicator Button

/// Tappable session indicator for the status bar.
struct SessionIndicatorButton: View {
    let session: Session?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if let session = session {
                    SessionIcon(
                        icon: session.icon,
                        color: Color(hex: session.color) ?? .blue,
                        size: 24
                    )
                    
                    Text(session.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text("No Session")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Current session: \(session?.name ?? "None"). Tap to switch sessions.")
    }
}

// MARK: - Color Extension

extension Color {
    /// Initialize a Color from a hex string (e.g., "#0A84FF" or "0A84FF").
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        guard hexSanitized.count == 6 else { return nil }
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue)
    }
}

// MARK: - Preview

#Preview {
    SessionSidebarView(sessionManager: SessionManager(testMode: true))
}
