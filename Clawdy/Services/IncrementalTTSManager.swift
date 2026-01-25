import Foundation
import AVFoundation

/// Manages incremental text-to-speech for streaming responses.
/// Buffers incoming text chunks and speaks complete sentences as they arrive.
/// This enables a more conversational experience where the user doesn't have to wait
/// for the full response before hearing anything.
///
/// Integrates with UnifiedTTSManager to support both Kokoro (neural) and system TTS,
/// automatically using the user's preferred TTS engine.
@MainActor
class IncrementalTTSManager: NSObject, ObservableObject {
    // MARK: - Published State
    
    @Published private(set) var isSpeaking = false
    @Published private(set) var queuedSentenceCount = 0
    @Published private(set) var isGeneratingAudio = false
    
    // MARK: - Private Properties
    
    /// Voice settings for speech rate and engine selection
    private let voiceSettings = VoiceSettingsManager.shared
    
    /// Kokoro TTS manager for neural TTS
    private let kokoroManager = KokoroTTSManager.shared
    
    /// System synthesizer (fallback when not using Kokoro)
    private let systemSynthesizer = AVSpeechSynthesizer()
    
    /// Buffer for accumulating text until sentence boundary is detected
    private var sentenceBuffer = ""
    
    /// Queue of sentences waiting to be spoken
    private var speechQueue: [String] = []
    
    /// Flag to track if we're currently speaking an utterance
    private var currentlySpeaking = false
    
    /// Full accumulated text (for reference/display)
    private var fullText = ""
    
    /// Task for Kokoro speech generation (for cancellation)
    private var kokoroSpeechTask: Task<Void, Never>?
    
    // MARK: - Code Block Tracking
    
    /// Tracks whether we're currently inside a code block (between ``` markers).
    /// Code block content is skipped from TTS since reading code aloud is not useful.
    private var inCodeBlock = false
    
    /// Buffer for detecting code block markers that might be split across text chunks.
    /// We need to handle cases where "``" arrives in one chunk and "`" in the next.
    private var codeMarkerBuffer = ""
    
    // MARK: - Short Clause Batching (Phase 5)
    
    /// Holds a pending clause that was extracted but not yet queued for speech.
    /// When we extract a short clause, we hold it here to potentially merge with
    /// the next extracted segment. If the next segment is also short, we combine them
    /// for more natural speech flow.
    /// Example: "Yes, of course." → extracted as "Yes," (pending) + "of course." → merged to "Yes, of course."
    private var pendingClause: String?
    
    // MARK: - Clause Detection
    
    /// Characters that mark the end of a sentence
    private static let sentenceEndingPunctuation = CharacterSet(charactersIn: ".!?")
    
    /// Regex pattern for sentence boundaries: sentence-ending punctuation followed by space or end of string
    /// These are strong boundaries where we always prefer to break.
    private static let sentenceBoundaryPattern = #"[.!?](?:\s|$)"#
    
    /// Regex pattern for clause boundaries: clause markers followed by space
    /// These are weaker boundaries only used when sentence boundary isn't available
    /// and only after accumulating enough words for natural speech flow.
    private static let clauseBoundaryPattern = #"[,;:](?:\s)"#
    
    /// Minimum words before considering a clause boundary (comma, colon, semicolon).
    /// This prevents unnatural breaks like "Sure," [pause] "I can help with that."
    /// By requiring at least 8 words before a clause break, we ensure speech flows naturally.
    /// Example: "Sure, I can help" (4 words) → waits for more text or sentence boundary
    /// Example: "I've checked the configuration file, and it looks correct" (10 words) → can break at comma
    private static let minWordsBeforeClauseBreak = 8
    
    /// Minimum words that should remain after extracting a clause (orphan prevention).
    /// If breaking at a clause boundary would leave fewer than this many words in the buffer,
    /// we wait for more text or a sentence boundary instead. This prevents speaking most of
    /// a sentence then leaving a tiny orphaned fragment.
    /// Example: "I checked the file, okay" (after comma, 1 word remains) → don't break, wait for more
    /// Example: "I checked the file, and it looks correct" (4+ words remain) → safe to break
    private static let minOrphanWords = 4
    
    /// Maximum words for a clause to be considered "short" and eligible for merging.
    /// Clauses with this many words or fewer may be held as pending and merged with
    /// the next clause if it's also short. This creates more natural speech units.
    /// Example: "Yes," (1 word) + "of course." (2 words) = "Yes, of course." (3 words total, under threshold)
    /// Example: "I understand," (2 words) + "that makes sense." (3 words) = merged (5 words total)
    /// Tuned to 5 (from 4) to allow slightly more batching of short conversational clauses.
    private static let shortClauseMaxWords = 5
    
    // MARK: - Segment Size Bounds (Phase 3)
    
    /// Minimum words before speaking a segment.
    /// Segments with fewer words than this are held for more content, unless flushed.
    /// This prevents tiny fragments like "Yes," or "Sure," from being spoken alone.
    /// Example: "Yes, I can help" (4 words) → waits for sentence end or more content
    /// Example: "I've updated the configuration file." (5 words) → speaks immediately
    private static let minWordsForSegment = 5
    
    /// Soft maximum words - after reaching this, we actively look for next boundary.
    /// When buffer exceeds this count, we prefer to break at the next available
    /// punctuation point (even clause boundaries) rather than continuing to buffer.
    /// This balances naturalness with latency for long unpunctuated content.
    /// Tuned to 20 (from 25) for more natural speech rhythm and reduced latency.
    /// 20 words is roughly 10-15 seconds of speech, a comfortable listening unit.
    private static let softMaxWords = 20
    
    /// Hard maximum words - force break at word boundary if no punctuation found.
    /// This is a safety fallback for pathological cases (completely unpunctuated text).
    /// We break at a word boundary near softMaxWords to maintain some naturalness.
    /// Tuned to 35 (from 40) to match the reduced softMaxWords and ensure reasonable
    /// segment sizes even for completely unpunctuated text.
    /// Example: 35+ words with no punctuation → break after ~20 words
    private static let hardMaxWords = 35
    
    // MARK: - Speech Pace Configuration
    
    /// Speech rate is intentionally kept consistent regardless of queue depth.
    /// We deliberately do NOT speed up to "catch up" when the queue grows large.
    /// This maintains a natural, comfortable listening experience even when text
    /// streams faster than it can be spoken.
    ///
    /// The queue acts as a buffer, and excess queued sentences are spoken at
    /// the same natural pace. Users can interrupt at any time if they want to
    /// move on before the queue is emptied.
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        systemSynthesizer.delegate = self
    }
    
    // MARK: - Public API
    
    /// Append incoming text to the buffer and speak complete sentences.
    /// Call this repeatedly as streaming text arrives.
    /// Code blocks (content between ``` markers) are tracked but not spoken.
    /// - Parameter text: The new text chunk to append
    func appendText(_ text: String) {
        fullText += text
        
        // Process text character by character to handle code block detection
        // This handles cases where ``` might be split across chunks
        let textToProcess = codeMarkerBuffer + text
        codeMarkerBuffer = ""
        
        var index = textToProcess.startIndex
        while index < textToProcess.endIndex {
            // Check if we're at a potential code block marker
            if textToProcess[index] == "`" {
                // Look ahead for triple backticks
                let remaining = textToProcess[index...]
                
                if remaining.hasPrefix("```") {
                    // Found complete code block marker, toggle state
                    inCodeBlock.toggle()
                    
                    // Skip past the marker
                    index = textToProcess.index(index, offsetBy: 3)
                    
                    // If we just entered a code block, flush any pending text first
                    // so it gets spoken before we start skipping
                    if inCodeBlock && !sentenceBuffer.isEmpty {
                        processSentenceBuffer()
                    }
                    continue
                } else if remaining.count < 3 {
                    // Possible incomplete marker at end of chunk, buffer it
                    codeMarkerBuffer = String(remaining)
                    break
                }
            }
            
            // Only add non-code content to speech buffer
            if !inCodeBlock {
                sentenceBuffer.append(textToProcess[index])
            }
            
            index = textToProcess.index(after: index)
        }
        
        // Process buffer for complete sentences (only if not in code block)
        if !inCodeBlock {
            processSentenceBuffer()
        }
    }
    
    /// Flush any remaining buffered text and speak it.
    /// Call this when the stream is complete.
    func flush() {
        // Flush any pending clause first (merge with remaining buffer if possible)
        if let pending = pendingClause {
            let remaining = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                // Merge pending clause with remaining buffer
                enqueueSentence(pending + " " + remaining)
            } else {
                // No remaining text, just speak the pending clause
                enqueueSentence(pending)
            }
            pendingClause = nil
            sentenceBuffer = ""
            return
        }
        
        // Trim and speak any remaining content
        let remaining = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            enqueueSentence(remaining)
        }
        sentenceBuffer = ""
    }
    
    /// Stop all speech immediately and clear the queue.
    func stop() {
        // Cancel any Kokoro speech task
        kokoroSpeechTask?.cancel()
        kokoroSpeechTask = nil
        
        // Stop system synthesizer
        systemSynthesizer.stopSpeaking(at: .immediate)
        
        // Stop Kokoro playback
        Task {
            await kokoroManager.stopPlayback()
        }
        
        speechQueue.removeAll()
        sentenceBuffer = ""
        fullText = ""
        currentlySpeaking = false
        isGeneratingAudio = false
        inCodeBlock = false
        codeMarkerBuffer = ""
        pendingClause = nil
        updateState()
        BackgroundAudioManager.shared.audioEnded()
        deactivateAudioSession()
    }
    
    /// Reset the manager for a new response.
    /// Clears all buffers and state.
    func reset() {
        stop()
    }
    
    /// Get the full accumulated text so far.
    var accumulatedText: String {
        return fullText
    }
    
    /// Check if there's text in the buffer waiting to be spoken.
    var hasBufferedText: Bool {
        return pendingClause != nil || !sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Private Helpers
    
    /// Process the sentence buffer, extracting and queueing complete sentences.
    /// Implements short clause batching: consecutive short clauses are merged
    /// for more natural speech flow (e.g., "Yes, of course." speaks as one unit).
    private func processSentenceBuffer() {
        // Keep processing while we find sentence boundaries
        while let segment = extractNextSentence() {
            let segmentWordCount = segment.split(separator: " ").count
            
            // Check if we have a pending clause to potentially merge
            if let pending = pendingClause {
                let pendingWordCount = pending.split(separator: " ").count
                let combinedWordCount = pendingWordCount + segmentWordCount
                
                // If the new segment is short enough and combined length is reasonable,
                // merge them for more natural speech flow
                if segmentWordCount <= Self.shortClauseMaxWords && combinedWordCount <= Self.minWordsBeforeClauseBreak {
                    // Merge and continue holding as pending (might merge with more)
                    pendingClause = pending + " " + segment
                    continue
                } else {
                    // New segment is too long or combined would be too long
                    // Enqueue what we have and decide what to do with new segment
                    if pendingWordCount + segmentWordCount <= Self.softMaxWords {
                        // Merge and speak together
                        enqueueSentence(pending + " " + segment)
                        pendingClause = nil
                        continue
                    } else {
                        // Speak pending first, then handle new segment
                        enqueueSentence(pending)
                        pendingClause = nil
                        // Fall through to handle new segment below
                    }
                }
            }
            
            // No pending clause or we just cleared it - handle new segment
            if segmentWordCount <= Self.shortClauseMaxWords {
                // This is a short clause - hold it as pending for potential merging
                pendingClause = segment
            } else {
                // Long enough segment - speak it directly
                enqueueSentence(segment)
            }
        }
    }
    
    /// Extract the next complete segment from the buffer.
    /// Prioritizes sentence boundaries (.!?) over clause boundaries (,;:).
    /// Uses segment size bounds to balance naturalness with latency.
    ///
    /// **Latency optimization**: Short complete sentences (< minWordsForSegment) are
    /// spoken immediately at sentence boundaries to avoid delaying responses like
    /// "Yes." or "Got it!" This ensures first speech starts as quickly as possible.
    /// - Returns: A complete segment if one is found, nil otherwise
    private func extractNextSentence() -> String? {
        let wordCount = sentenceBuffer.split(separator: " ").count
        
        // Priority 0: Short complete sentence fast-path (latency optimization)
        // If we have a short sentence with a sentence boundary, speak it immediately
        // rather than waiting for more words. This prevents delaying responses like
        // "Yes." "Got it!" "Sure!" which are complete thoughts under minWordsForSegment.
        // This is critical for first-speech latency on short responses.
        if wordCount < Self.minWordsForSegment && wordCount > 0 {
            if let sentence = extractAtSentenceBoundary() {
                return sentence
            }
            // No sentence boundary yet - wait for more content
            return nil
        }
        
        // Not enough content yet - wait for more (unless flushed)
        guard wordCount >= Self.minWordsForSegment else {
            return nil
        }
        
        // Priority 1: Extract at sentence boundary (. ! ?)
        // Sentence boundaries are always preferred for natural speech flow
        if let sentence = extractAtSentenceBoundary() {
            return sentence
        }
        
        // Priority 2: Extract at clause boundary (, ; :)
        // Only used when no sentence boundary is available
        if let clause = extractAtClauseBoundary() {
            return clause
        }
        
        // Priority 3: Hard max fallback - force break at word boundary
        // Only triggers for pathological cases (40+ words, no punctuation)
        // This ensures we eventually speak even without any punctuation
        if wordCount >= Self.hardMaxWords {
            return extractAtWordBoundary()
        }
        
        // Wait for more text or a natural boundary
        return nil
    }
    
    /// Extract text at a word boundary, breaking around the soft max word count.
    /// This is a fallback for pathological cases where no punctuation arrives.
    /// We break at softMaxWords to maintain some naturalness while ensuring
    /// the buffer doesn't grow indefinitely.
    /// - Returns: A segment of approximately softMaxWords, nil if buffer too short
    private func extractAtWordBoundary() -> String? {
        let words = sentenceBuffer.split(separator: " ", omittingEmptySubsequences: true)
        
        // Shouldn't happen, but guard against it
        guard words.count >= Self.softMaxWords else {
            return nil
        }
        
        // Take softMaxWords and join them back
        let segmentWords = words.prefix(Self.softMaxWords)
        let segment = segmentWords.joined(separator: " ")
        
        // Calculate the position after the extracted segment in the original buffer
        // Find where the Nth word ends in the original string
        var wordsSeen = 0
        var endIndex = sentenceBuffer.startIndex
        var inWord = false
        
        for i in sentenceBuffer.indices {
            let char = sentenceBuffer[i]
            let isWhitespace = char.isWhitespace
            
            if inWord && isWhitespace {
                // Just finished a word
                wordsSeen += 1
                inWord = false
                if wordsSeen == Self.softMaxWords {
                    endIndex = i
                    break
                }
            } else if !inWord && !isWhitespace {
                // Starting a new word
                inWord = true
            }
        }
        
        // Update buffer to remove the extracted segment
        if endIndex < sentenceBuffer.endIndex {
            sentenceBuffer = String(sentenceBuffer[endIndex...])
                .trimmingCharacters(in: .whitespaces)
        } else {
            sentenceBuffer = ""
        }
        
        return segment
    }
    
    /// Extract text at a sentence boundary (. ! ? followed by space or end).
    /// These are strong boundaries where speech should always break.
    /// - Returns: A complete sentence if one is found, nil otherwise
    private func extractAtSentenceBoundary() -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: Self.sentenceBoundaryPattern,
            options: []
        ) else {
            return nil
        }
        
        let nsRange = NSRange(sentenceBuffer.startIndex..<sentenceBuffer.endIndex, in: sentenceBuffer)
        
        if let match = regex.firstMatch(in: sentenceBuffer, options: [], range: nsRange) {
            guard let range = Range(match.range, in: sentenceBuffer) else {
                return nil
            }
            
            // Get the position of the punctuation mark
            let sentenceEndIndex = range.lowerBound
            
            // Extract sentence including the punctuation
            let potentialSentence = String(sentenceBuffer[..<sentenceBuffer.index(after: sentenceEndIndex)])
            let sentence = potentialSentence.trimmingCharacters(in: .whitespaces)
            
            // Update buffer to remove the extracted sentence
            let newStartIndex = sentenceBuffer.index(after: sentenceEndIndex)
            if newStartIndex < sentenceBuffer.endIndex {
                sentenceBuffer = String(sentenceBuffer[newStartIndex...])
                    .trimmingCharacters(in: .init(charactersIn: " "))
            } else {
                sentenceBuffer = ""
            }
            
            return sentence
        }
        
        return nil
    }
    
    /// Extract text at a clause boundary (punctuation followed by space or end).
    /// Only extracts if we have accumulated enough words for natural speech flow.
    /// This prevents choppy breaks like "Sure," [pause] "I can help with that."
    /// Also prevents orphaned fragments (fewer than minOrphanWords left in buffer).
    /// - Returns: A complete clause if one is found and thresholds are met, nil otherwise
    private func extractAtClauseBoundary() -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: Self.clauseBoundaryPattern,
            options: []
        ) else {
            return nil
        }
        
        let nsRange = NSRange(sentenceBuffer.startIndex..<sentenceBuffer.endIndex, in: sentenceBuffer)
        
        if let match = regex.firstMatch(in: sentenceBuffer, options: [], range: nsRange) {
            // Get the position just after the punctuation mark
            guard let range = Range(match.range, in: sentenceBuffer) else {
                return nil
            }
            
            // Calculate the end of the sentence (including punctuation)
            let sentenceEndIndex = range.lowerBound
            
            // Extract the potential clause text (up to and including the punctuation)
            let potentialClause = String(sentenceBuffer[..<sentenceBuffer.index(after: sentenceEndIndex)])
            let clause = potentialClause.trimmingCharacters(in: .whitespaces)
            
            // Check minimum word threshold before breaking at clause boundary.
            // This prevents unnatural breaks like "Sure," [pause] "I can help."
            // We count words in the clause that would be extracted.
            let wordCount = clause.split(separator: " ").count
            guard wordCount >= Self.minWordsBeforeClauseBreak else {
                // Not enough words yet - wait for more text or a sentence boundary
                return nil
            }
            
            // Check what would remain in the buffer after extraction (orphan prevention).
            // If extracting this clause would leave a tiny orphaned fragment (fewer than
            // minOrphanWords), we wait for more text or a sentence boundary instead.
            // This prevents speaking "I checked the configuration file," then leaving
            // an awkward orphan like "okay" or "sure" hanging.
            let newStartIndex = sentenceBuffer.index(after: sentenceEndIndex)
            if newStartIndex < sentenceBuffer.endIndex {
                let remainingText = String(sentenceBuffer[newStartIndex...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let remainingWordCount = remainingText.split(separator: " ").count
                
                // If remaining text is non-empty but too short, don't break here.
                // Empty remaining text (remainingWordCount == 0) is fine - we're at end.
                if remainingWordCount > 0 && remainingWordCount < Self.minOrphanWords {
                    // Would leave an orphan - wait for more text or sentence boundary
                    return nil
                }
            }
            
            // Safe to extract - update buffer to remove the extracted clause
            if newStartIndex < sentenceBuffer.endIndex {
                sentenceBuffer = String(sentenceBuffer[newStartIndex...])
                    .trimmingCharacters(in: .init(charactersIn: " "))
            } else {
                sentenceBuffer = ""
            }
            
            return clause
        }
        
        return nil
    }
    
    /// Add a sentence to the speech queue and start speaking if not already.
    /// Normalizes technical content (file paths, URLs, inline code) for natural speech.
    private func enqueueSentence(_ sentence: String) {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Normalize technical content for natural speech rendering.
        // This transforms file paths, URLs, inline code, and environment variables
        // into human-friendly spoken forms before queueing for TTS.
        let normalized = TTSTextNormalizer.normalize(trimmed)
        
        speechQueue.append(normalized)
        updateState()
        
        // Start speaking if not already
        if !currentlySpeaking {
            speakNext()
        }
    }
    
    /// Speak the next sentence in the queue.
    /// Routes to either Kokoro or system TTS based on user preference.
    private func speakNext() {
        guard !speechQueue.isEmpty else {
            currentlySpeaking = false
            updateState()
            // Keep audio session active for a moment in case more text is coming
            return
        }
        
        let sentence = speechQueue.removeFirst()
        currentlySpeaking = true
        updateState()
        
        // Determine which TTS engine to use
        let preferredEngine = voiceSettings.settings.ttsEngine
        
        if preferredEngine == .kokoro {
            speakWithKokoro(sentence)
        } else {
            speakWithSystem(sentence)
        }
    }
    
    /// Speak a sentence using Kokoro neural TTS.
    /// Falls back to system TTS if Kokoro is not ready.
    /// Speech rate is kept consistent regardless of queue size - we do NOT speed up to catch up.
    private func speakWithKokoro(_ sentence: String) {
        kokoroSpeechTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Check if Kokoro is ready
            let isReady = await kokoroManager.modelDownloaded
            
            guard isReady else {
                // Fall back to system TTS if Kokoro not downloaded
                print("[IncrementalTTSManager] Kokoro not ready, falling back to system TTS")
                await MainActor.run {
                    self.speakWithSystem(sentence)
                }
                return
            }
            
            do {
                // Configure audio session
                await MainActor.run {
                    self.configureAudioSession()
                    self.isGeneratingAudio = true
                }
                
                BackgroundAudioManager.shared.audioStarted()
                
                // Speech rate is consistent regardless of queue depth.
                // This maintains natural pacing; users can interrupt if they want to skip ahead.
                let speed = voiceSettings.settings.speechRate
                try await kokoroManager.speakText(sentence, speed: speed)
                
                // Brief pause between Kokoro utterances for natural pacing.
                // This is intentionally not shortened when queue is large.
                try await Task.sleep(for: .milliseconds(100))
                
                // On completion, speak the next sentence
                await MainActor.run {
                    self.isGeneratingAudio = false
                    self.handleSpeechComplete()
                }
                
            } catch {
                // Handle errors - try to continue with next sentence or fall back
                print("[IncrementalTTSManager] Kokoro error: \(error.localizedDescription)")
                
                await MainActor.run {
                    self.isGeneratingAudio = false
                }
                
                // Check if it was a cancellation
                if Task.isCancelled {
                    return
                }
                
                // Fall back to system TTS for this sentence
                await MainActor.run {
                    self.speakWithSystem(sentence)
                }
            }
        }
    }
    
    /// Speak a sentence using system TTS (AVSpeechSynthesizer).
    /// Speech rate is kept consistent regardless of queue size - we do NOT speed up to catch up.
    private func speakWithSystem(_ sentence: String) {
        // Configure audio session for playback
        configureAudioSession()
        
        // Create and configure utterance
        let utterance = AVSpeechUtterance(string: sentence)
        
        // Use configured voice
        if let voice = selectSystemVoice() {
            utterance.voice = voice
        }
        
        // Apply configured speech rate - consistent regardless of queue depth.
        // This maintains natural pacing; users can interrupt if they want to skip ahead.
        // Slightly slower for more natural pacing with premium/enhanced voices.
        let rateMultiplier = voiceSettings.settings.speechRate
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rateMultiplier * 0.92
        
        // Slightly lower pitch for warmer, more natural sound
        utterance.pitchMultiplier = 0.95
        utterance.volume = 1.0
        
        // Natural pauses between utterances for comfortable listening.
        // Pre-utterance delay: brief pause before starting new sentence.
        // Post-utterance delay: natural breathing room at end of sentence.
        // These pauses are intentionally not shortened when queue is large.
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.15
        
        BackgroundAudioManager.shared.audioStarted()
        systemSynthesizer.speak(utterance)
    }
    
    /// Handle completion of a spoken sentence (from either engine).
    private func handleSpeechComplete() {
        // Speak the next sentence in queue
        speakNext()
        
        // If queue is empty and no more text coming, we're done
        if speechQueue.isEmpty && !currentlySpeaking {
            BackgroundAudioManager.shared.audioEnded()
            // Delay deactivation slightly to handle back-to-back sentences
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                if !self.currentlySpeaking && self.speechQueue.isEmpty {
                    self.deactivateAudioSession()
                }
            }
        }
    }
    
    /// Update published state properties
    private func updateState() {
        queuedSentenceCount = speechQueue.count
        isSpeaking = currentlySpeaking || !speechQueue.isEmpty
    }
    
    /// Select the system voice based on user settings or auto-select the best available
    private func selectSystemVoice() -> AVSpeechSynthesisVoice? {
        // If user has selected a specific voice, use it
        if let identifier = voiceSettings.settings.voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            print("[IncrementalTTSManager] Using user-selected voice: \(voice.name) (quality: \(voice.quality.rawValue))")
            return voice
        }
        
        // Use the shared best voice finder
        if let voice = SpeechSynthesizer.findBestVoice() {
            print("[IncrementalTTSManager] Auto-selected voice: \(voice.name) (quality: \(voice.quality.rawValue))")
            return voice
        }
        
        print("[IncrementalTTSManager] Falling back to default en-US voice")
        return AVSpeechSynthesisVoice(language: "en-US")
    }
    
    /// Configure audio session for speech playback
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try audioSession.setActive(true)
        } catch {
            print("[IncrementalTTSManager] Audio session error: \(error)")
        }
    }
    
    /// Deactivate audio session when speech is complete
    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        } catch {
            print("[IncrementalTTSManager] Audio session deactivation error: \(error)")
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension IncrementalTTSManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            handleSpeechComplete()
        }
    }
    
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            currentlySpeaking = false
            updateState()
            BackgroundAudioManager.shared.audioEnded()
            deactivateAudioSession()
        }
    }
}
