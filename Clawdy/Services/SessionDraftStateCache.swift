import Foundation

/// Manages draft state persistence for sessions.
/// Provides in-memory caching for fast access during session switching,
/// and UserDefaults persistence for app lifecycle management.
///
/// ## Overview
/// When users switch sessions, their current draft (text input, input mode)
/// is preserved so they can return to it later. This cache provides:
/// - Fast in-memory access (<10ms) during session switching
/// - UserDefaults persistence for app background/termination
/// - Automatic restoration on app launch
///
/// ## Limitations
/// - Pending images are NOT persisted (temp files may not survive termination)
/// - Only text input and input mode are preserved
@MainActor
final class SessionDraftStateCache: ObservableObject {
    
    // MARK: - Singleton
    
    /// Shared instance for app-wide draft state management
    static let shared = SessionDraftStateCache()
    
    // MARK: - Constants
    
    /// UserDefaults key prefix for draft states
    private static let draftKeyPrefix = "session.draft."
    
    /// Key for storing the list of session IDs with drafts
    private static let draftSessionIdsKey = "session.draft.sessionIds"
    
    // MARK: - Properties
    
    /// In-memory cache of draft states per session ID
    private var cache: [UUID: SessionDraftState] = [:]
    
    /// JSON encoder for draft serialization
    private let encoder: JSONEncoder
    
    /// JSON decoder for draft deserialization
    private let decoder: JSONDecoder
    
    // MARK: - Initialization
    
    private init() {
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        
        // Restore drafts from UserDefaults on init
        restoreAllDrafts()
        
        print("[DraftStateCache] Initialized with \(cache.count) cached drafts")
    }
    
    // MARK: - Public API
    
    /// Save draft state for a session.
    /// - Parameters:
    ///   - sessionId: The session to save draft for
    ///   - state: The draft state to save
    func saveDraft(for sessionId: UUID, state: SessionDraftState) {
        // Only cache if there's content worth saving
        if state.hasContent {
            cache[sessionId] = state
            print("[DraftStateCache] Saved draft for session \(sessionId.uuidString.prefix(8)): '\(state.textInput.prefix(30))...'")
        } else {
            // Clear empty drafts
            cache.removeValue(forKey: sessionId)
            print("[DraftStateCache] Cleared empty draft for session \(sessionId.uuidString.prefix(8))")
        }
    }
    
    /// Save draft state with images (images are ignored for persistence).
    /// - Parameters:
    ///   - sessionId: The session to save draft for
    ///   - state: The draft state including images
    func saveDraft(for sessionId: UUID, state: SessionDraftStateWithImages) {
        saveDraft(for: sessionId, state: state.draft)
    }
    
    /// Load draft state for a session.
    /// - Parameter sessionId: The session to load draft for
    /// - Returns: The saved draft state, or empty state if none exists
    func loadDraft(for sessionId: UUID) -> SessionDraftState {
        let draft = cache[sessionId] ?? .empty
        if draft.hasContent {
            print("[DraftStateCache] Loaded draft for session \(sessionId.uuidString.prefix(8)): '\(draft.textInput.prefix(30))...'")
        }
        return draft
    }
    
    /// Load draft state with empty images array.
    /// - Parameter sessionId: The session to load draft for
    /// - Returns: Draft state with empty images (images are not persisted)
    func loadDraftWithImages(for sessionId: UUID) -> SessionDraftStateWithImages {
        SessionDraftStateWithImages(
            draft: loadDraft(for: sessionId),
            pendingImageIds: [] // Images are not persisted
        )
    }
    
    /// Clear draft state for a session.
    /// Call this when a message is sent.
    /// - Parameter sessionId: The session to clear draft for
    func clearDraft(for sessionId: UUID) {
        cache.removeValue(forKey: sessionId)
        print("[DraftStateCache] Cleared draft for session \(sessionId.uuidString.prefix(8))")
    }
    
    /// Check if a session has a draft with content.
    /// - Parameter sessionId: The session to check
    /// - Returns: True if draft exists and has content
    func hasDraft(for sessionId: UUID) -> Bool {
        cache[sessionId]?.hasContent ?? false
    }
    
    // MARK: - Persistence
    
    /// Persist all in-memory drafts to UserDefaults.
    /// Call this when app enters background or terminates.
    func persistAllDrafts() {
        // Get all session IDs with drafts
        let sessionIds = Array(cache.keys)
        
        // Save mapping of session IDs
        let sessionIdStrings = sessionIds.map { $0.uuidString }
        UserDefaults.standard.set(sessionIdStrings, forKey: Self.draftSessionIdsKey)
        
        // Save each draft
        var savedCount = 0
        for (sessionId, draft) in cache {
            if saveDraftToUserDefaults(draft, for: sessionId) {
                savedCount += 1
            }
        }
        
        // Clean up old drafts that are no longer in cache
        cleanupOrphanedDrafts(currentSessionIds: Set(sessionIds))
        
        print("[DraftStateCache] Persisted \(savedCount) drafts to UserDefaults")
    }
    
    /// Restore all drafts from UserDefaults to in-memory cache.
    /// Called during initialization and can be called on app launch.
    func restoreAllDrafts() {
        // Get list of session IDs with drafts
        guard let sessionIdStrings = UserDefaults.standard.stringArray(forKey: Self.draftSessionIdsKey) else {
            print("[DraftStateCache] No persisted drafts found")
            return
        }
        
        var restoredCount = 0
        for sessionIdString in sessionIdStrings {
            guard let sessionId = UUID(uuidString: sessionIdString) else {
                continue
            }
            
            if let draft = loadDraftFromUserDefaults(for: sessionId) {
                cache[sessionId] = draft
                restoredCount += 1
            }
        }
        
        print("[DraftStateCache] Restored \(restoredCount) drafts from UserDefaults")
    }
    
    /// Clear all drafts (both in-memory and persisted).
    /// Use with caution - typically only for testing or reset.
    func clearAllDrafts() {
        // Clear in-memory cache
        let sessionIds = Array(cache.keys)
        cache.removeAll()
        
        // Clear from UserDefaults
        UserDefaults.standard.removeObject(forKey: Self.draftSessionIdsKey)
        for sessionId in sessionIds {
            let key = Self.draftKeyPrefix + sessionId.uuidString
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        print("[DraftStateCache] Cleared all drafts")
    }
    
    // MARK: - Private Helpers
    
    /// Save a single draft to UserDefaults.
    /// - Parameters:
    ///   - draft: The draft to save
    ///   - sessionId: The session ID
    /// - Returns: True if save succeeded
    @discardableResult
    private func saveDraftToUserDefaults(_ draft: SessionDraftState, for sessionId: UUID) -> Bool {
        let key = Self.draftKeyPrefix + sessionId.uuidString
        
        do {
            let data = try encoder.encode(draft)
            UserDefaults.standard.set(data, forKey: key)
            return true
        } catch {
            print("[DraftStateCache] Failed to encode draft for \(sessionId.uuidString.prefix(8)): \(error.localizedDescription)")
            return false
        }
    }
    
    /// Load a single draft from UserDefaults.
    /// - Parameter sessionId: The session ID
    /// - Returns: The draft, or nil if not found or decode fails
    private func loadDraftFromUserDefaults(for sessionId: UUID) -> SessionDraftState? {
        let key = Self.draftKeyPrefix + sessionId.uuidString
        
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        
        do {
            return try decoder.decode(SessionDraftState.self, from: data)
        } catch {
            print("[DraftStateCache] Failed to decode draft for \(sessionId.uuidString.prefix(8)): \(error.localizedDescription)")
            // Clean up corrupted data
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
    }
    
    /// Remove drafts from UserDefaults that are no longer in the cache.
    /// - Parameter currentSessionIds: Set of session IDs currently in cache
    private func cleanupOrphanedDrafts(currentSessionIds: Set<UUID>) {
        // Get previously stored session IDs
        guard let storedIdStrings = UserDefaults.standard.stringArray(forKey: Self.draftSessionIdsKey) else {
            return
        }
        
        let storedIds = Set(storedIdStrings.compactMap { UUID(uuidString: $0) })
        let orphanedIds = storedIds.subtracting(currentSessionIds)
        
        for sessionId in orphanedIds {
            let key = Self.draftKeyPrefix + sessionId.uuidString
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        if !orphanedIds.isEmpty {
            print("[DraftStateCache] Cleaned up \(orphanedIds.count) orphaned drafts")
        }
    }
}

// MARK: - Testing Support

extension SessionDraftStateCache {
    /// Number of cached drafts (for testing)
    var count: Int {
        cache.count
    }
    
    /// All session IDs with cached drafts (for testing)
    var cachedSessionIds: [UUID] {
        Array(cache.keys)
    }
}