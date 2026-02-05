import Foundation

/// Captures the draft input state when switching sessions.
/// Text and input mode are persisted; pending images are NOT persisted
/// (images are session-only and exist only in ImageAttachmentStore during the session).
struct SessionDraftState: Codable, Equatable {
    /// Text currently in the input field
    var textInput: String
    
    /// Current input mode (voice or text)
    var inputMode: InputMode
    
    // Note: pendingImageIds are NOT persisted across sessions or app launches.
    // Images are session-only and live in ImageAttachmentStore.
    
    // MARK: - Static Properties
    
    /// Empty draft state (default for new sessions)
    static let empty = SessionDraftState(
        textInput: "",
        inputMode: .text
    )
    
    // MARK: - Convenience
    
    /// Returns true if the draft has any content worth preserving
    var hasContent: Bool {
        !textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Returns true if the draft is empty
    var isEmpty: Bool {
        textInput.isEmpty
    }
}

// MARK: - Draft State with Pending Images (Runtime Only)

/// Extended draft state that includes pending image IDs.
/// This is used at runtime but images are NOT persisted.
struct SessionDraftStateWithImages {
    /// The persistable draft state
    var draft: SessionDraftState
    
    /// Pending image attachment IDs (runtime only, not persisted)
    var pendingImageIds: [UUID]
    
    /// Empty state
    static let empty = SessionDraftStateWithImages(
        draft: .empty,
        pendingImageIds: []
    )
    
    /// Returns true if there's any content (text or images)
    var hasContent: Bool {
        draft.hasContent || !pendingImageIds.isEmpty
    }
}
