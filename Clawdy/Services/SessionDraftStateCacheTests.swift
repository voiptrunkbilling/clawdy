import Foundation
import XCTest

/// Unit tests for SessionDraftStateCache.
/// Tests draft state management, persistence, and lifecycle.
class SessionDraftStateCacheTests: XCTestCase {
    
    // MARK: - In-Memory Cache Tests
    
    @MainActor
    func testSaveDraftStoresInCache() {
        let cache = SessionDraftStateCache.shared
        let sessionId = UUID()
        let draft = SessionDraftState(textInput: "Test draft", inputMode: .text)
        
        cache.saveDraft(for: sessionId, state: draft)
        
        let loaded = cache.loadDraft(for: sessionId)
        XCTAssertEqual(loaded.textInput, "Test draft")
        XCTAssertEqual(loaded.inputMode, .text)
        
        // Cleanup
        cache.clearDraft(for: sessionId)
    }
    
    @MainActor
    func testLoadDraftReturnsEmptyForUnknownSession() {
        let cache = SessionDraftStateCache.shared
        let unknownId = UUID()
        
        let loaded = cache.loadDraft(for: unknownId)
        
        XCTAssertTrue(loaded.isEmpty)
        XCTAssertEqual(loaded.textInput, "")
    }
    
    @MainActor
    func testClearDraftRemovesFromCache() {
        let cache = SessionDraftStateCache.shared
        let sessionId = UUID()
        let draft = SessionDraftState(textInput: "To be cleared", inputMode: .voice)
        
        cache.saveDraft(for: sessionId, state: draft)
        XCTAssertTrue(cache.hasDraft(for: sessionId))
        
        cache.clearDraft(for: sessionId)
        
        XCTAssertFalse(cache.hasDraft(for: sessionId))
        XCTAssertTrue(cache.loadDraft(for: sessionId).isEmpty)
    }
    
    @MainActor
    func testSaveEmptyDraftClearsCache() {
        let cache = SessionDraftStateCache.shared
        let sessionId = UUID()
        
        // First save a draft with content
        cache.saveDraft(for: sessionId, state: SessionDraftState(textInput: "Has content", inputMode: .text))
        XCTAssertTrue(cache.hasDraft(for: sessionId))
        
        // Now save an empty draft
        cache.saveDraft(for: sessionId, state: .empty)
        
        XCTAssertFalse(cache.hasDraft(for: sessionId))
    }
    
    @MainActor
    func testLoadDraftWithImagesReturnsEmptyImages() {
        let cache = SessionDraftStateCache.shared
        let sessionId = UUID()
        let draft = SessionDraftState(textInput: "Draft with text", inputMode: .text)
        
        cache.saveDraft(for: sessionId, state: draft)
        
        let loaded = cache.loadDraftWithImages(for: sessionId)
        
        XCTAssertEqual(loaded.draft.textInput, "Draft with text")
        XCTAssertTrue(loaded.pendingImageIds.isEmpty, "Images should not be persisted")
        
        // Cleanup
        cache.clearDraft(for: sessionId)
    }
    
    @MainActor
    func testSaveDraftWithImagesIgnoresImages() {
        let cache = SessionDraftStateCache.shared
        let sessionId = UUID()
        let draftWithImages = SessionDraftStateWithImages(
            draft: SessionDraftState(textInput: "Draft", inputMode: .text),
            pendingImageIds: [UUID(), UUID()]
        )
        
        cache.saveDraft(for: sessionId, state: draftWithImages)
        
        let loaded = cache.loadDraftWithImages(for: sessionId)
        XCTAssertEqual(loaded.draft.textInput, "Draft")
        XCTAssertTrue(loaded.pendingImageIds.isEmpty, "Images should not be restored")
        
        // Cleanup
        cache.clearDraft(for: sessionId)
    }
    
    // MARK: - HasDraft Tests
    
    @MainActor
    func testHasDraftReturnsTrueForNonEmptyDraft() {
        let cache = SessionDraftStateCache.shared
        let sessionId = UUID()
        
        cache.saveDraft(for: sessionId, state: SessionDraftState(textInput: "Content", inputMode: .text))
        
        XCTAssertTrue(cache.hasDraft(for: sessionId))
        
        // Cleanup
        cache.clearDraft(for: sessionId)
    }
    
    @MainActor
    func testHasDraftReturnsFalseForEmptyDraft() {
        let cache = SessionDraftStateCache.shared
        let sessionId = UUID()
        
        cache.saveDraft(for: sessionId, state: .empty)
        
        XCTAssertFalse(cache.hasDraft(for: sessionId))
    }
    
    @MainActor
    func testHasDraftReturnsFalseForWhitespaceOnlyDraft() {
        let cache = SessionDraftStateCache.shared
        let sessionId = UUID()
        
        // Whitespace-only drafts should not be considered as having content
        cache.saveDraft(for: sessionId, state: SessionDraftState(textInput: "   ", inputMode: .text))
        
        XCTAssertFalse(cache.hasDraft(for: sessionId), "Whitespace-only drafts should not be persisted")
    }
    
    // MARK: - Input Mode Tests
    
    @MainActor
    func testVoiceInputModeIsPersisted() {
        let cache = SessionDraftStateCache.shared
        let sessionId = UUID()
        let draft = SessionDraftState(textInput: "Voice draft", inputMode: .voice)
        
        cache.saveDraft(for: sessionId, state: draft)
        
        let loaded = cache.loadDraft(for: sessionId)
        XCTAssertEqual(loaded.inputMode, .voice)
        
        // Cleanup
        cache.clearDraft(for: sessionId)
    }
    
    @MainActor
    func testTextInputModeIsPersisted() {
        let cache = SessionDraftStateCache.shared
        let sessionId = UUID()
        let draft = SessionDraftState(textInput: "Text draft", inputMode: .text)
        
        cache.saveDraft(for: sessionId, state: draft)
        
        let loaded = cache.loadDraft(for: sessionId)
        XCTAssertEqual(loaded.inputMode, .text)
        
        // Cleanup
        cache.clearDraft(for: sessionId)
    }
    
    // MARK: - Multiple Sessions Tests
    
    @MainActor
    func testMultipleSessionDraftsAreIsolated() {
        let cache = SessionDraftStateCache.shared
        let session1 = UUID()
        let session2 = UUID()
        let session3 = UUID()
        
        cache.saveDraft(for: session1, state: SessionDraftState(textInput: "Draft 1", inputMode: .text))
        cache.saveDraft(for: session2, state: SessionDraftState(textInput: "Draft 2", inputMode: .voice))
        cache.saveDraft(for: session3, state: SessionDraftState(textInput: "Draft 3", inputMode: .text))
        
        XCTAssertEqual(cache.loadDraft(for: session1).textInput, "Draft 1")
        XCTAssertEqual(cache.loadDraft(for: session2).textInput, "Draft 2")
        XCTAssertEqual(cache.loadDraft(for: session3).textInput, "Draft 3")
        
        // Clear one, others should remain
        cache.clearDraft(for: session2)
        
        XCTAssertTrue(cache.hasDraft(for: session1))
        XCTAssertFalse(cache.hasDraft(for: session2))
        XCTAssertTrue(cache.hasDraft(for: session3))
        
        // Cleanup
        cache.clearDraft(for: session1)
        cache.clearDraft(for: session3)
    }
    
    // MARK: - SessionDraftState Model Tests
    
    func testSessionDraftStateHasContentWithText() {
        let draft = SessionDraftState(textInput: "Some content", inputMode: .text)
        XCTAssertTrue(draft.hasContent)
    }
    
    func testSessionDraftStateHasNoContentWhenEmpty() {
        let draft = SessionDraftState.empty
        XCTAssertFalse(draft.hasContent)
    }
    
    func testSessionDraftStateHasNoContentWithWhitespace() {
        let draft = SessionDraftState(textInput: "   \n\t  ", inputMode: .text)
        XCTAssertFalse(draft.hasContent)
    }
    
    func testSessionDraftStateIsEmpty() {
        let empty = SessionDraftState.empty
        XCTAssertTrue(empty.isEmpty)
        
        let nonEmpty = SessionDraftState(textInput: "content", inputMode: .text)
        XCTAssertFalse(nonEmpty.isEmpty)
    }
    
    // MARK: - SessionDraftStateWithImages Model Tests
    
    func testSessionDraftStateWithImagesHasContent() {
        let withText = SessionDraftStateWithImages(
            draft: SessionDraftState(textInput: "Text", inputMode: .text),
            pendingImageIds: []
        )
        XCTAssertTrue(withText.hasContent)
        
        let withImages = SessionDraftStateWithImages(
            draft: .empty,
            pendingImageIds: [UUID()]
        )
        XCTAssertTrue(withImages.hasContent)
        
        let empty = SessionDraftStateWithImages.empty
        XCTAssertFalse(empty.hasContent)
    }
}
