import Foundation

/// Debug-only validation for TTS natural speech implementation.
/// Run these tests during development to verify the TTS behavior against
/// realistic Claude response patterns.
///
/// Usage: Call `TTSTestValidation.runAllTests()` from a debug context.
struct TTSTestValidation {
    
    // MARK: - Test Runner
    
    /// Run all TTS validation tests and print results.
    /// Only meaningful in debug builds.
    @MainActor
    static func runAllTests() {
        #if DEBUG
        print("=== TTS Natural Speech Validation ===\n")
        
        var passed = 0
        var failed = 0
        
        // Phase 6.1: Real Claude responses (varied content types)
        let results1 = runVariedContentTests()
        passed += results1.passed
        failed += results1.failed
        
        // Phase 6.2: Code-heavy responses (file edits, commands)
        let results2 = runCodeHeavyTests()
        passed += results2.passed
        failed += results2.failed
        
        print("\n=== Summary ===")
        print("Passed: \(passed), Failed: \(failed)")
        print("================\n")
        #endif
    }
    
    // MARK: - Phase 6.1: Varied Content Type Tests
    
    /// Test TTS with real Claude response patterns.
    /// These simulate actual Claude Code responses with varied content.
    @MainActor
    private static func runVariedContentTests() -> (passed: Int, failed: Int) {
        print("--- Phase 6.1: Varied Content Types ---\n")
        
        var passed = 0
        var failed = 0
        
        // Test 1: Conversational greeting response
        let test1 = testNormalization(
            name: "Conversational greeting",
            input: "Sure, I can help with that! Let me take a look at your code.",
            expectedToContain: ["Sure", "help", "look"],
            expectedNotToContain: []
        )
        test1 ? (passed += 1) : (failed += 1)
        
        // Test 2: Response with file path
        let test2 = testNormalization(
            name: "Response with file path",
            input: "I've updated the file at ./Clawdy/Services/IncrementalTTSManager.swift to fix the issue.",
            expectedToContain: ["file", "IncrementalTTSManager.swift"],
            expectedNotToContain: ["./Clawdy/Services/"]
        )
        test2 ? (passed += 1) : (failed += 1)
        
        // Test 3: Response with URL
        let test3 = testNormalization(
            name: "Response with URL",
            input: "You can find more information at https://developer.apple.com/documentation/avfoundation for the API details.",
            expectedToContain: ["link to", "developer.apple.com"],
            expectedNotToContain: ["https://"]
        )
        test3 ? (passed += 1) : (failed += 1)
        
        // Test 4: Response with inline code command
        let test4 = testNormalization(
            name: "Response with inline command",
            input: "Try running `npm install --save-dev typescript` to add the dependency.",
            expectedToContain: ["command", "npm install"],
            expectedNotToContain: ["`"]
        )
        test4 ? (passed += 1) : (failed += 1)
        
        // Test 5: Response with environment variable
        let test5 = testNormalization(
            name: "Response with env var",
            input: "Make sure you've set $OPENAI_API_KEY in your environment before running.",
            expectedToContain: ["variable", "openai api key"],
            expectedNotToContain: ["$OPENAI_API_KEY"]
        )
        test5 ? (passed += 1) : (failed += 1)
        
        // Test 6: Mixed technical content
        let test6 = testNormalization(
            name: "Mixed technical content",
            input: "I've created ~/Projects/app/src/utils/helper.swift. Run `swift build` to compile. Check https://swift.org for docs.",
            expectedToContain: ["file", "helper.swift", "command", "swift build", "link to", "swift.org"],
            expectedNotToContain: ["~/Projects/app/src/utils/", "https://", "`"]
        )
        test6 ? (passed += 1) : (failed += 1)
        
        // Test 7: Short affirmative response (should not break at comma)
        let test7 = testClauseDetection(
            name: "Short affirmative stays together",
            input: "Yes, I can do that.",
            expectedMinSegments: 1,
            expectedMaxSegments: 1
        )
        test7 ? (passed += 1) : (failed += 1)
        
        // Test 8: Medium response with natural break point
        let test8 = testClauseDetection(
            name: "Medium response natural break",
            input: "I've analyzed your request carefully, and I found that the configuration needs to be updated in the settings file.",
            expectedMinSegments: 1,
            expectedMaxSegments: 2
        )
        test8 ? (passed += 1) : (failed += 1)
        
        // Test 9: Long sentence without punctuation (should eventually break)
        let test9 = testClauseDetection(
            name: "Long unpunctuated text breaks",
            input: "The quick brown fox jumps over the lazy dog and continues running through the forest without stopping until reaching the river where it finally takes a rest near the old oak tree that has been standing there for centuries watching over all creatures",
            expectedMinSegments: 1,
            expectedMaxSegments: 3
        )
        test9 ? (passed += 1) : (failed += 1)
        
        // Test 10: Multiple short sentences (each should be its own segment)
        let test10 = testClauseDetection(
            name: "Multiple short sentences",
            input: "Done. I fixed it. The file is saved. You can test now.",
            expectedMinSegments: 2,
            expectedMaxSegments: 4
        )
        test10 ? (passed += 1) : (failed += 1)
        
        // Test 11: Explanation with colon introduction
        let test11 = testClauseDetection(
            name: "Colon introduction stays together when short",
            input: "Here's what I found: the error is in line 42.",
            expectedMinSegments: 1,
            expectedMaxSegments: 2
        )
        test11 ? (passed += 1) : (failed += 1)
        
        // Test 12: List-style response
        let test12 = testNormalization(
            name: "List with paths",
            input: "Modified files: ./src/App.swift, ./src/Utils.swift, and ./src/Config.swift for the refactor.",
            expectedToContain: ["file", "App.swift", "Utils.swift", "Config.swift"],
            expectedNotToContain: ["./src/"]
        )
        test12 ? (passed += 1) : (failed += 1)
        
        // Test 13: Error message response
        let test13 = testNormalization(
            name: "Error message with path",
            input: "Error in /Users/developer/Projects/app/Package.swift at line 15: missing dependency declaration.",
            expectedToContain: ["file", "Package.swift", "line 15"],
            expectedNotToContain: ["/Users/developer/Projects/app/"]
        )
        test13 ? (passed += 1) : (failed += 1)
        
        // Test 14: Git-related response
        let test14 = testNormalization(
            name: "Git command response",
            input: "I'll commit these changes. Running `git add .` and then `git commit -m \"Fix TTS\"` to save your work.",
            expectedToContain: ["command", "git add", "git commit"],
            expectedNotToContain: ["`"]
        )
        test14 ? (passed += 1) : (failed += 1)
        
        // Test 15: Package/dependency response
        let test15 = testNormalization(
            name: "Package installation",
            input: "Adding the package `@apple/swift-syntax` to your project. Run `swift package resolve` to fetch it.",
            expectedToContain: ["at apple", "swift syntax", "command", "swift package resolve"],
            expectedNotToContain: ["`@", "`swift"]
        )
        test15 ? (passed += 1) : (failed += 1)
        
        return (passed: passed, failed: failed)
    }
    
    // MARK: - Phase 6.2: Code-Heavy Tests
    
    /// Test TTS with code-heavy responses.
    /// These simulate Claude Code responses with file edits and commands.
    @MainActor
    private static func runCodeHeavyTests() -> (passed: Int, failed: Int) {
        print("\n--- Phase 6.2: Code-Heavy Responses ---\n")
        
        var passed = 0
        var failed = 0
        
        // Test 1: File edit response with path
        let test1 = testNormalization(
            name: "File edit notification",
            input: "I've edited ./src/components/Button.tsx to add the onClick handler.",
            expectedToContain: ["file", "Button.tsx", "onClick"],
            expectedNotToContain: ["./src/components/"]
        )
        test1 ? (passed += 1) : (failed += 1)
        
        // Test 2: Multiple file edits
        let test2 = testNormalization(
            name: "Multiple file edits",
            input: "Updated three files: ./lib/utils.ts, ./lib/helpers.ts, and ./lib/constants.ts with the new types.",
            expectedToContain: ["file", "utils.ts", "helpers.ts", "constants.ts"],
            expectedNotToContain: ["./lib/"]
        )
        test2 ? (passed += 1) : (failed += 1)
        
        // Test 3: npm/yarn command execution
        let test3 = testNormalization(
            name: "npm install command",
            input: "Running `npm install react-query @tanstack/react-query` to add the dependency.",
            expectedToContain: ["command", "npm install", "react query", "at tanstack"],
            expectedNotToContain: ["`npm", "`@"]
        )
        test3 ? (passed += 1) : (failed += 1)
        
        // Test 4: Git workflow commands
        let test4 = testNormalization(
            name: "Git workflow",
            input: "I'll stage and commit: `git add -A`, then `git commit -m \"feat: add button\"`, and `git push origin main`.",
            expectedToContain: ["command", "git add", "git commit", "git push"],
            expectedNotToContain: ["`git"]
        )
        test4 ? (passed += 1) : (failed += 1)
        
        // Test 5: File creation with directory path
        let test5 = testNormalization(
            name: "File creation",
            input: "Created new file at ~/Projects/app/src/hooks/useAuth.ts with the authentication logic.",
            expectedToContain: ["file", "useAuth.ts"],
            expectedNotToContain: ["~/Projects/app/src/hooks/"]
        )
        test5 ? (passed += 1) : (failed += 1)
        
        // Test 6: Build command output
        let test6 = testNormalization(
            name: "Build command",
            input: "Running `swift build` now. The output will be in ./.build/debug/MyApp.",
            expectedToContain: ["command", "swift build", "file", "MyApp"],
            expectedNotToContain: ["`swift", "./.build/debug/"]
        )
        test6 ? (passed += 1) : (failed += 1)
        
        // Test 7: Error with file path and line number
        let test7 = testNormalization(
            name: "Error with path and line",
            input: "Found an error in /Users/dev/project/src/main.swift at line 42: missing return statement.",
            expectedToContain: ["file", "main.swift", "line 42", "missing return"],
            expectedNotToContain: ["/Users/dev/project/src/"]
        )
        test7 ? (passed += 1) : (failed += 1)
        
        // Test 8: Config file reference
        let test8 = testNormalization(
            name: "Config file reference",
            input: "The issue is in your ./package.json file. You need to add the scripts section.",
            expectedToContain: ["file", "package.json", "scripts"],
            expectedNotToContain: ["./package"]
        )
        test8 ? (passed += 1) : (failed += 1)
        
        // Test 9: Docker command
        let test9 = testNormalization(
            name: "Docker commands",
            input: "Run `docker build -t myapp .` to build the image, then `docker run -p 3000:3000 myapp` to start.",
            expectedToContain: ["command", "docker build", "docker run"],
            expectedNotToContain: ["`docker"]
        )
        test9 ? (passed += 1) : (failed += 1)
        
        // Test 10: Environment setup
        let test10 = testNormalization(
            name: "Environment setup",
            input: "Set $DATABASE_URL and $API_SECRET in your ./.env file before running the server.",
            expectedToContain: ["variable", "database url", "api secret", "file", ".env"],
            expectedNotToContain: ["$DATABASE", "$API", "./.env"]
        )
        test10 ? (passed += 1) : (failed += 1)
        
        // Test 11: Test command with path
        let test11 = testNormalization(
            name: "Test command",
            input: "Running `npm test -- --coverage` on ./src/__tests__/Button.test.tsx to verify the changes.",
            expectedToContain: ["command", "npm test", "file", "Button.test.tsx"],
            expectedNotToContain: ["`npm", "./src/__tests__/"]
        )
        test11 ? (passed += 1) : (failed += 1)
        
        // Test 12: Xcode/Swift specific
        let test12 = testNormalization(
            name: "Xcode build",
            input: "Run `xcodebuild -scheme MyApp -destination 'platform=iOS'` to build. Output in ./build/Debug-iphoneos/MyApp.app.",
            expectedToContain: ["command", "xcodebuild", "file", "MyApp.app"],
            expectedNotToContain: ["`xcodebuild", "./build/Debug-iphoneos/"]
        )
        test12 ? (passed += 1) : (failed += 1)
        
        // Test 13: Long code-heavy response (clause detection)
        let test13 = testClauseDetection(
            name: "Code explanation stays coherent",
            input: "The function in ./src/utils/parser.ts takes the input string and processes it through multiple stages: tokenization, validation, and transformation before returning the final result.",
            expectedMinSegments: 1,
            expectedMaxSegments: 2
        )
        test13 ? (passed += 1) : (failed += 1)
        
        // Test 14: Sequential commands
        let test14 = testNormalization(
            name: "Sequential commands",
            input: "First `cd ~/Projects`, then `mkdir newapp`, then `cd newapp`, and finally `npm init -y`.",
            expectedToContain: ["command", "cd", "mkdir", "npm init"],
            expectedNotToContain: ["`cd", "`mkdir", "`npm"]
        )
        test14 ? (passed += 1) : (failed += 1)
        
        // Test 15: Import statement reference
        let test15 = testNormalization(
            name: "Import reference",
            input: "Add `import { useState } from 'react'` at the top of ./components/Form.tsx.",
            expectedToContain: ["useState", "file", "Form.tsx"],
            expectedNotToContain: ["./components/"]
        )
        test15 ? (passed += 1) : (failed += 1)
        
        // Test 16: Complex path with special characters
        let test16 = testNormalization(
            name: "Complex path",
            input: "Check the config at ~/.config/claude-code/settings.json for your preferences.",
            expectedToContain: ["file", "settings.json"],
            expectedNotToContain: ["~/.config/claude-code/"]
        )
        test16 ? (passed += 1) : (failed += 1)
        
        // Test 17: Relative path navigation
        let test17 = testNormalization(
            name: "Relative path",
            input: "Move up one level with `cd ..` then edit ../shared/types.ts for the interface.",
            expectedToContain: ["command", "cd", "file", "types.ts"],
            expectedNotToContain: ["../shared/"]
        )
        test17 ? (passed += 1) : (failed += 1)
        
        // Test 18: Bundle/package path
        let test18 = testNormalization(
            name: "Bundle path",
            input: "The resource is at ./MyApp.app/Contents/Resources/config.plist inside the bundle.",
            expectedToContain: ["file", "config.plist"],
            expectedNotToContain: ["./MyApp.app/Contents/Resources/"]
        )
        test18 ? (passed += 1) : (failed += 1)
        
        // Test 19: Brew command
        let test19 = testNormalization(
            name: "Homebrew command",
            input: "Install the tool with `brew install swiftlint` and configure it in ./.swiftlint.yml.",
            expectedToContain: ["command", "brew install", "file", ".swiftlint.yml"],
            expectedNotToContain: ["`brew", "./.swiftlint"]
        )
        test19 ? (passed += 1) : (failed += 1)
        
        // Test 20: Curl/wget command with URL
        let test20 = testNormalization(
            name: "Download command",
            input: "Download it with `curl -O https://example.com/file.zip` to your current directory.",
            expectedToContain: ["command", "curl", "link to", "example.com"],
            expectedNotToContain: ["`curl", "https://"]
        )
        test20 ? (passed += 1) : (failed += 1)
        
        return (passed: passed, failed: failed)
    }
    
    // MARK: - Test Helpers
    
    /// Test that normalization produces expected output.
    private static func testNormalization(
        name: String,
        input: String,
        expectedToContain: [String],
        expectedNotToContain: [String]
    ) -> Bool {
        let normalized = TTSTextNormalizer.normalize(input)
        
        var allPassed = true
        var issues: [String] = []
        
        // Check expected content is present
        for expected in expectedToContain {
            if !normalized.localizedCaseInsensitiveContains(expected) {
                allPassed = false
                issues.append("Missing: '\(expected)'")
            }
        }
        
        // Check unwanted content is absent
        for unwanted in expectedNotToContain {
            if normalized.contains(unwanted) {
                allPassed = false
                issues.append("Unexpected: '\(unwanted)'")
            }
        }
        
        let status = allPassed ? "✅ PASS" : "❌ FAIL"
        print("\(status): \(name)")
        if !allPassed {
            print("  Input: \(input)")
            print("  Output: \(normalized)")
            issues.forEach { print("  Issue: \($0)") }
        }
        
        return allPassed
    }
    
    /// Test that clause detection produces expected segment count.
    /// Uses a simplified simulation since we can't easily test the full async TTS flow.
    @MainActor
    private static func testClauseDetection(
        name: String,
        input: String,
        expectedMinSegments: Int,
        expectedMaxSegments: Int
    ) -> Bool {
        // Simulate segmentation using TTSTestSimulator
        let segments = TTSTestSimulator.simulateSegmentation(input)
        let segmentCount = segments.count
        
        let inRange = segmentCount >= expectedMinSegments && segmentCount <= expectedMaxSegments
        let status = inRange ? "✅ PASS" : "❌ FAIL"
        
        print("\(status): \(name)")
        if !inRange {
            print("  Input: \(input)")
            print("  Segments (\(segmentCount)): \(segments)")
            print("  Expected: \(expectedMinSegments)-\(expectedMaxSegments) segments")
        }
        
        return inRange
    }
}

// MARK: - TTS Segmentation Simulator

/// Simulates TTS segmentation logic for testing purposes.
/// This mirrors the IncrementalTTSManager's clause detection logic.
struct TTSTestSimulator {
    
    private static let sentenceBoundaryPattern = #"[.!?](?:\s|$)"#
    private static let clauseBoundaryPattern = #"[,;:](?:\s)"#
    private static let minWordsBeforeClauseBreak = 8
    private static let minOrphanWords = 4
    private static let minWordsForSegment = 5
    private static let softMaxWords = 25
    private static let hardMaxWords = 40
    private static let shortClauseMaxWords = 4
    
    /// Simulate how IncrementalTTSManager would segment the input text.
    static func simulateSegmentation(_ text: String) -> [String] {
        var buffer = text
        var segments: [String] = []
        var pendingClause: String?
        
        while !buffer.isEmpty {
            // Try to extract a segment
            if let segment = extractNextSegment(from: &buffer) {
                let segmentWordCount = segment.split(separator: " ").count
                
                // Handle pending clause merging
                if let pending = pendingClause {
                    let pendingWordCount = pending.split(separator: " ").count
                    let combinedWordCount = pendingWordCount + segmentWordCount
                    
                    if segmentWordCount <= shortClauseMaxWords && combinedWordCount <= minWordsBeforeClauseBreak {
                        pendingClause = pending + " " + segment
                        continue
                    } else {
                        if pendingWordCount + segmentWordCount <= softMaxWords {
                            segments.append(pending + " " + segment)
                            pendingClause = nil
                            continue
                        } else {
                            segments.append(pending)
                            pendingClause = nil
                        }
                    }
                }
                
                if segmentWordCount <= shortClauseMaxWords {
                    pendingClause = segment
                } else {
                    segments.append(segment)
                }
            } else {
                // No segment extracted, flush remaining
                break
            }
        }
        
        // Flush pending and remaining buffer
        if let pending = pendingClause {
            let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                segments.append(pending + " " + remaining)
            } else {
                segments.append(pending)
            }
        } else if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        return segments
    }
    
    private static func extractNextSegment(from buffer: inout String) -> String? {
        let wordCount = buffer.split(separator: " ").count
        
        guard wordCount >= minWordsForSegment else { return nil }
        
        // Priority 1: Sentence boundary
        if let segment = extractAtSentenceBoundary(from: &buffer) {
            return segment
        }
        
        // Priority 2: Clause boundary (if enough words)
        if let segment = extractAtClauseBoundary(from: &buffer) {
            return segment
        }
        
        // Priority 3: Hard max fallback
        if wordCount >= hardMaxWords {
            return extractAtWordBoundary(from: &buffer)
        }
        
        return nil
    }
    
    private static func extractAtSentenceBoundary(from buffer: inout String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: sentenceBoundaryPattern, options: []) else {
            return nil
        }
        
        let nsRange = NSRange(buffer.startIndex..<buffer.endIndex, in: buffer)
        
        if let match = regex.firstMatch(in: buffer, options: [], range: nsRange) {
            guard let range = Range(match.range, in: buffer) else { return nil }
            
            let sentenceEndIndex = range.lowerBound
            let sentence = String(buffer[..<buffer.index(after: sentenceEndIndex)])
                .trimmingCharacters(in: .whitespaces)
            
            let newStartIndex = buffer.index(after: sentenceEndIndex)
            if newStartIndex < buffer.endIndex {
                buffer = String(buffer[newStartIndex...]).trimmingCharacters(in: .whitespaces)
            } else {
                buffer = ""
            }
            
            return sentence
        }
        
        return nil
    }
    
    private static func extractAtClauseBoundary(from buffer: inout String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: clauseBoundaryPattern, options: []) else {
            return nil
        }
        
        let nsRange = NSRange(buffer.startIndex..<buffer.endIndex, in: buffer)
        
        if let match = regex.firstMatch(in: buffer, options: [], range: nsRange) {
            guard let range = Range(match.range, in: buffer) else { return nil }
            
            let clauseEndIndex = range.lowerBound
            let clause = String(buffer[..<buffer.index(after: clauseEndIndex)])
                .trimmingCharacters(in: .whitespaces)
            
            // Check minimum word threshold
            let wordCount = clause.split(separator: " ").count
            guard wordCount >= minWordsBeforeClauseBreak else { return nil }
            
            // Check orphan prevention
            let newStartIndex = buffer.index(after: clauseEndIndex)
            if newStartIndex < buffer.endIndex {
                let remaining = String(buffer[newStartIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let remainingWordCount = remaining.split(separator: " ").count
                
                if remainingWordCount > 0 && remainingWordCount < minOrphanWords {
                    return nil
                }
            }
            
            // Update buffer
            if newStartIndex < buffer.endIndex {
                buffer = String(buffer[newStartIndex...]).trimmingCharacters(in: .whitespaces)
            } else {
                buffer = ""
            }
            
            return clause
        }
        
        return nil
    }
    
    private static func extractAtWordBoundary(from buffer: inout String) -> String? {
        let words = buffer.split(separator: " ", omittingEmptySubsequences: true)
        
        guard words.count >= softMaxWords else { return nil }
        
        let segmentWords = words.prefix(softMaxWords)
        let segment = segmentWords.joined(separator: " ")
        
        // Find where to cut in original buffer
        var wordsSeen = 0
        var endIndex = buffer.startIndex
        var inWord = false
        
        for i in buffer.indices {
            let char = buffer[i]
            let isWhitespace = char.isWhitespace
            
            if inWord && isWhitespace {
                wordsSeen += 1
                inWord = false
                if wordsSeen == softMaxWords {
                    endIndex = i
                    break
                }
            } else if !inWord && !isWhitespace {
                inWord = true
            }
        }
        
        if endIndex < buffer.endIndex {
            buffer = String(buffer[endIndex...]).trimmingCharacters(in: .whitespaces)
        } else {
            buffer = ""
        }
        
        return segment
    }
}
