import Foundation
import Combine

/// Manages session lifecycle, state, and switching.
/// Coordinates with SessionPersistenceManager for storage and ClawdyViewModel for UI updates.
@MainActor
class SessionManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SessionManager()
    
    // MARK: - Published Properties
    
    /// All sessions, sorted by pinned first then by last activity
    @Published private(set) var sessions: [Session] = []
    
    /// Currently active session
    @Published private(set) var activeSession: Session?
    
    /// Whether the sidebar is visible
    @Published var isSidebarOpen: Bool = false
    
    /// Whether the create session sheet is visible
    @Published var isCreateSheetPresented: Bool = false
    
    /// Loading state for session operations
    @Published private(set) var isLoading: Bool = false
    
    /// Error message to display (nil = no error)
    @Published var errorMessage: String?
    
    // MARK: - Draft State Cache
    
    /// Session draft state cache for persistence across app lifecycle
    private let draftStateCache = SessionDraftStateCache.shared
    
    // MARK: - Dependencies
    
    private let persistenceManager = SessionPersistenceManager.shared
    
    // MARK: - Callbacks
    
    /// Called when active session changes - ClawdyViewModel should observe this
    var onSessionChanged: ((Session) -> Void)?
    
    /// Called when draft state should be saved for current session
    var onSaveDraftState: (() -> SessionDraftStateWithImages)?
    
    /// Called when draft state should be restored for new session
    var onRestoreDraftState: ((SessionDraftStateWithImages) -> Void)?
    
    // MARK: - Initialization
    
    private init() {
        Task {
            await loadSessions()
        }
    }
    
    /// For testing - allows initialization without loading
    init(testMode: Bool) {
        if !testMode {
            Task {
                await loadSessions()
            }
        }
    }
    
    // MARK: - Session Loading
    
    /// Load all sessions from disk and set up initial state.
    func loadSessions() async {
        isLoading = true
        defer { isLoading = false }
        
        // Check for migration from old format
        if let migratedSession = await persistenceManager.migrateIfNeeded() {
            sessions = [migratedSession]
            activeSession = migratedSession
            onSessionChanged?(migratedSession)
            return
        }
        
        // Load existing sessions
        var loadedSessions = await persistenceManager.loadAllSessions()
        
        // If no sessions exist, create a default one
        if loadedSessions.isEmpty {
            let defaultSession = Session.createDefault()
            await persistenceManager.saveSession(defaultSession)
            loadedSessions = [defaultSession]
        }
        
        // Reconcile message counts
        loadedSessions = await persistenceManager.reconcileMessageCounts(for: loadedSessions)
        
        // Sort and store
        sessions = Session.sortedByActivity(loadedSessions)
        
        // Set active session to first (most recent pinned or most recent)
        if let first = sessions.first {
            activeSession = first
            onSessionChanged?(first)
        }
        
        print("[SessionManager] Loaded \(sessions.count) sessions")
    }
    
    // MARK: - Session Creation
    
    /// Create a new session with the specified parameters.
    /// - Parameters:
    ///   - name: Session name (required, min 1 character)
    ///   - agent: Predefined agent type
    ///   - icon: SF Symbol name
    ///   - color: Hex color code
    func createSession(
        name: String,
        agent: PredefinedAgent,
        icon: String,
        color: String
    ) async {
        // Validate name
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Session name is required"
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Create new session
        let newSession = Session(
            name: trimmedName,
            sessionKey: agent.rawValue,
            icon: icon,
            color: color
        )
        
        // Save to disk
        await persistenceManager.saveSession(newSession)
        
        // Add to list and sort
        var updatedSessions = sessions
        updatedSessions.append(newSession)
        sessions = Session.sortedByActivity(updatedSessions)
        
        // Switch to new session
        await switchToSession(newSession)
        
        // Close create sheet
        isCreateSheetPresented = false
        
        print("[SessionManager] Created session: \(newSession.name)")
    }
    
    // MARK: - Session Deletion
    
    /// Delete a session (if not the last one).
    /// - Parameter session: Session to delete
    func deleteSession(_ session: Session) async {
        // Prevent deleting last session
        guard sessions.count > 1 else {
            errorMessage = "Cannot delete last session"
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Remove from disk
        await persistenceManager.deleteSession(session)
        
        // Remove from draft cache
        draftStateCache.clearDraft(for: session.id)
        
        // Remove from list
        sessions.removeAll { $0.id == session.id }
        
        // If deleted session was active, switch to first available
        if activeSession?.id == session.id {
            if let first = sessions.first {
                await switchToSession(first)
            }
        }
        
        print("[SessionManager] Deleted session: \(session.name)")
    }
    
    /// Check if a session can be deleted.
    func canDeleteSession(_ session: Session) -> Bool {
        sessions.count > 1
    }
    
    // MARK: - Session Updates
    
    /// Update a session's metadata.
    /// - Parameter session: Updated session
    func updateSession(_ session: Session) async {
        // Save to disk
        await persistenceManager.saveSession(session)
        
        // Update in list
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
            sessions = Session.sortedByActivity(sessions)
        }
        
        // Update active session if it was modified
        if activeSession?.id == session.id {
            activeSession = session
        }
        
        print("[SessionManager] Updated session: \(session.name)")
    }
    
    /// Rename a session.
    /// - Parameters:
    ///   - session: Session to rename
    ///   - newName: New name
    func renameSession(_ session: Session, to newName: String) async {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Session name cannot be empty"
            return
        }
        
        var updated = session
        updated.name = trimmedName
        await updateSession(updated)
    }
    
    /// Update a session's icon.
    func updateSessionIcon(_ session: Session, icon: String) async {
        var updated = session
        updated.icon = icon
        await updateSession(updated)
    }
    
    /// Update a session's color.
    func updateSessionColor(_ session: Session, color: String) async {
        var updated = session
        updated.color = color
        await updateSession(updated)
    }
    
    // MARK: - Session Switching
    
    /// Switch to a different session.
    /// Saves current draft, loads new session's messages, restores draft.
    /// - Parameter session: Session to switch to
    func switchToSession(_ session: Session) async {
        guard session.id != activeSession?.id else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        // Save current session's draft state
        if let currentSession = activeSession,
           let saveDraft = onSaveDraftState {
            let draftState = saveDraft()
            draftStateCache.saveDraft(for: currentSession.id, state: draftState)
        }
        
        // Update active session
        activeSession = session
        
        // Notify ClawdyViewModel to switch
        onSessionChanged?(session)
        
        // Restore draft state for new session
        let draftState = draftStateCache.loadDraftWithImages(for: session.id)
        onRestoreDraftState?(draftState)
        
        // Close sidebar
        isSidebarOpen = false
        
        print("[SessionManager] Switched to session: \(session.name)")
    }
    
    // MARK: - Pin/Unpin
    
    /// Pin a session to the top of the list.
    func pinSession(_ session: Session) async {
        var updated = session
        updated.isPinned = true
        await updateSession(updated)
    }
    
    /// Unpin a session.
    func unpinSession(_ session: Session) async {
        var updated = session
        updated.isPinned = false
        await updateSession(updated)
    }
    
    /// Toggle pin state for a session.
    func togglePin(_ session: Session) async {
        if session.isPinned {
            await unpinSession(session)
        } else {
            await pinSession(session)
        }
    }
    
    // MARK: - Activity Tracking
    
    /// Update last activity timestamp for a session.
    /// Called when a message is sent/received.
    func updateLastActivity(for session: Session) async {
        var updated = session
        updated.lastActivityAt = Date()
        await updateSession(updated)
    }
    
    /// Increment message count for a session.
    func incrementMessageCount(for session: Session) async {
        var updated = session
        updated.messageCount += 1
        updated.lastActivityAt = Date()
        await updateSession(updated)
    }
    
    // MARK: - Sidebar Actions
    
    /// Open the session sidebar.
    func openSidebar() {
        isSidebarOpen = true
    }
    
    /// Close the session sidebar.
    func closeSidebar() {
        isSidebarOpen = false
    }
    
    /// Toggle sidebar visibility.
    func toggleSidebar() {
        isSidebarOpen.toggle()
    }
    
    // MARK: - Computed Properties
    
    /// Sessions that are pinned, sorted by last activity.
    var pinnedSessions: [Session] {
        sessions.filter { $0.isPinned }
    }
    
    /// Sessions that are not pinned, sorted by last activity.
    var unpinnedSessions: [Session] {
        sessions.filter { !$0.isPinned }
    }
    
    /// Whether delete action should be disabled.
    var isDeleteDisabled: Bool {
        sessions.count <= 1
    }
}

// MARK: - Time Formatting

extension SessionManager {
    /// Format a date as relative time for session row display.
    /// - <1 hour: "5m ago"
    /// - <24 hours: "2h ago"
    /// - <7 days: "3d ago"
    /// - ≥7 days: "Jan 15"
    static func formatRelativeTime(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
