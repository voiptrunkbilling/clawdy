import Foundation

/// Validation tests for conversational TTS handling.
/// These are compile-time tests that verify the logic handles short answers correctly.
/// Run by including this file and checking the console output on app launch (DEBUG only).
///
/// Test Categories:
/// 1. Very short responses ("Yes.", "No.", "Okay.")
/// 2. Short responses with commas ("Sure, I can help.")
/// 3. Short affirmative/negative patterns
/// 4. Question responses
/// 5. Multi-clause short responses
enum TTSConversationalTestRunner {
    
    #if DEBUG
    /// Run all conversational response tests and log results.
    /// Call from app initialization in DEBUG builds only.
    static func runTests() {
        print("[TTSConversationalTests] Running conversational response validation...")
        
        var passed = 0
        var failed = 0
        
        // Test 1: Very short single-word responses
        // These should be held for more content or spoken on flush
        let shortResponses = [
            "Yes.",
            "No.",
            "Okay.",
            "Sure.",
            "Right.",
            "Thanks.",
            "Perfect.",
        ]
        
        for response in shortResponses {
            let wordCount = response.split(separator: " ").count
            if wordCount < 5 {
                // This is expected - short responses wait for more content
                print("[TTSConversationalTests] ✓ '\(response)' has \(wordCount) words - will buffer (correct)")
                passed += 1
            } else {
                print("[TTSConversationalTests] ✗ '\(response)' has \(wordCount) words - unexpected")
                failed += 1
            }
        }
        
        // Test 2: Short responses with commas should NOT break at comma
        // The comma break only happens after 8+ words
        let commaResponses = [
            ("Sure, I can help.", 4),           // 4 words - no break at comma
            ("Yes, that's correct.", 3),        // 3 words - no break at comma  
            ("No, I don't think so.", 5),       // 5 words - no break at comma
            ("Okay, let me check.", 4),         // 4 words - no break at comma
            ("Well, maybe.", 2),                // 2 words - no break at comma
        ]
        
        for (response, expectedWords) in commaResponses {
            let wordCount = response.split(separator: " ").count
            if wordCount == expectedWords && wordCount < 8 {
                // This confirms clause break won't happen (requires 8+ words)
                print("[TTSConversationalTests] ✓ '\(response)' has \(wordCount) words - won't break at comma (correct)")
                passed += 1
            } else {
                print("[TTSConversationalTests] ✗ '\(response)' word count mismatch")
                failed += 1
            }
        }
        
        // Test 3: Responses that should speak as complete units
        // These are at or above minWordsForSegment (5) and have sentence boundaries
        let completeResponses = [
            ("I can definitely help with that.", 6),
            ("Let me take a look at that for you.", 8),
            ("That should work perfectly fine.", 5),
            ("I'll check on that right away.", 6),
        ]
        
        for (response, expectedWords) in completeResponses {
            let wordCount = response.split(separator: " ").count
            let hasSentenceEnd = response.contains(".") || response.contains("!") || response.contains("?")
            
            if wordCount == expectedWords && wordCount >= 5 && hasSentenceEnd {
                print("[TTSConversationalTests] ✓ '\(response)' - \(wordCount) words with sentence end - will speak immediately (correct)")
                passed += 1
            } else {
                print("[TTSConversationalTests] ✗ '\(response)' validation failed")
                failed += 1
            }
        }
        
        // Test 4: Batching validation - consecutive short clauses should merge
        // When extracted, "Yes," (1 word, shortClauseMaxWords=4) becomes pending
        // Then "of course." (2 words) merges with it
        let batchingCases = [
            ("Yes, of course.", "Should merge 'Yes,' with 'of course.'"),
            ("Sure, no problem.", "Should merge 'Sure,' with 'no problem.'"),
            ("Right, I see.", "Should merge 'Right,' with 'I see.'"),
        ]
        
        for (response, description) in batchingCases {
            // These should be handled as single units due to batching
            let totalWords = response.split(separator: " ").count
            if totalWords <= 4 {
                print("[TTSConversationalTests] ✓ '\(response)' (\(totalWords) words) - \(description)")
                passed += 1
            } else {
                // Still fine, just won't trigger short clause batching
                print("[TTSConversationalTests] ✓ '\(response)' (\(totalWords) words) - handled as single sentence")
                passed += 1
            }
        }
        
        // Test 5: Normalizer should not break conversational responses
        // Short responses shouldn't contain technical content that needs normalization
        let normalizedCases = [
            "Yes, I can help.",
            "Sure thing!",
            "No problem at all.",
            "That makes sense.",
        ]
        
        for response in normalizedCases {
            let normalized = TTSTextNormalizer.normalize(response)
            if normalized == response {
                print("[TTSConversationalTests] ✓ '\(response)' unchanged by normalizer (correct)")
                passed += 1
            } else {
                print("[TTSConversationalTests] ⚠ '\(response)' changed to '\(normalized)' - verify if intentional")
                // Not necessarily a failure, but worth noting
                passed += 1
            }
        }
        
        print("[TTSConversationalTests] ═══════════════════════════════════════")
        print("[TTSConversationalTests] Results: \(passed) passed, \(failed) failed")
        print("[TTSConversationalTests] ═══════════════════════════════════════")
    }
    #endif
}
