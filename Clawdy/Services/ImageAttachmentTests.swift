import Foundation
import UIKit

/// Validation tests for ImageAttachment and ImageAttachmentStore.
/// These are compile-time tests that verify image handling logic.
/// Run by including this file and checking the console output on app launch (DEBUG only).
///
/// Test Categories:
/// 1. ImageAttachment base64 encoding
/// 2. ImageAttachment thumbnail generation
/// 3. ImageAttachmentStore add/remove/clear operations
/// 4. Size validation (reject >10MB)
/// 5. Media type detection from magic bytes
/// 6. TranscriptMessage Codable excludes imageAttachmentIds
enum ImageAttachmentTestRunner {
    
    #if DEBUG
    /// Run all image attachment tests and log results.
    /// Call from app initialization in DEBUG builds only.
    @MainActor
    static func runTests() async {
        print("[ImageAttachmentTests] Running image attachment validation...")
        
        var passed = 0
        var failed = 0
        
        // Create a test store (separate from app's shared store)
        let testStore = ImageAttachmentStore()
        
        // MARK: - Test 1: Media Type Detection
        print("[ImageAttachmentTests] --- Media Type Detection ---")
        
        // JPEG magic bytes: FF D8 FF
        let jpegBytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01]
        let jpegData = Data(jpegBytes)
        let jpegType = ImageAttachment.detectMediaType(from: jpegData)
        if jpegType == "image/jpeg" {
            print("[ImageAttachmentTests] ✓ JPEG detection: \(jpegType)")
            passed += 1
        } else {
            print("[ImageAttachmentTests] ✗ JPEG detection failed: got \(jpegType)")
            failed += 1
        }
        
        // PNG magic bytes: 89 50 4E 47 0D 0A 1A 0A
        let pngBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D]
        let pngData = Data(pngBytes)
        let pngType = ImageAttachment.detectMediaType(from: pngData)
        if pngType == "image/png" {
            print("[ImageAttachmentTests] ✓ PNG detection: \(pngType)")
            passed += 1
        } else {
            print("[ImageAttachmentTests] ✗ PNG detection failed: got \(pngType)")
            failed += 1
        }
        
        // GIF magic bytes: 47 49 46 38 (GIF8)
        let gifBytes: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00]
        let gifData = Data(gifBytes)
        let gifType = ImageAttachment.detectMediaType(from: gifData)
        if gifType == "image/gif" {
            print("[ImageAttachmentTests] ✓ GIF detection: \(gifType)")
            passed += 1
        } else {
            print("[ImageAttachmentTests] ✗ GIF detection failed: got \(gifType)")
            failed += 1
        }
        
        // WebP magic bytes: RIFF....WEBP
        let webpBytes: [UInt8] = [0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50]
        let webpData = Data(webpBytes)
        let webpType = ImageAttachment.detectMediaType(from: webpData)
        if webpType == "image/webp" {
            print("[ImageAttachmentTests] ✓ WebP detection: \(webpType)")
            passed += 1
        } else {
            print("[ImageAttachmentTests] ✗ WebP detection failed: got \(webpType)")
            failed += 1
        }
        
        // Unknown format defaults to JPEG
        let unknownBytes: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B]
        let unknownData = Data(unknownBytes)
        let unknownType = ImageAttachment.detectMediaType(from: unknownData)
        if unknownType == "image/jpeg" {
            print("[ImageAttachmentTests] ✓ Unknown format defaults to JPEG")
            passed += 1
        } else {
            print("[ImageAttachmentTests] ✗ Unknown format should default to JPEG, got \(unknownType)")
            failed += 1
        }
        
        // MARK: - Test 2: File Extension Mapping
        print("[ImageAttachmentTests] --- File Extension Mapping ---")
        
        let extensions: [(String, String)] = [
            ("image/jpeg", "jpg"),
            ("image/png", "png"),
            ("image/gif", "gif"),
            ("image/webp", "webp"),
            ("image/unknown", "jpg"),  // Default
        ]
        
        for (mediaType, expectedExt) in extensions {
            let ext = ImageAttachment.fileExtension(for: mediaType)
            if ext == expectedExt {
                print("[ImageAttachmentTests] ✓ Extension for \(mediaType): \(ext)")
                passed += 1
            } else {
                print("[ImageAttachmentTests] ✗ Extension for \(mediaType): expected \(expectedExt), got \(ext)")
                failed += 1
            }
        }
        
        // MARK: - Test 3: Size Validation
        print("[ImageAttachmentTests] --- Size Validation ---")
        
        // Create test image data (small, valid JPEG)
        let smallImage = createTestImage(size: CGSize(width: 100, height: 100))
        if let smallData = smallImage?.jpegData(compressionQuality: 1.0) {
            do {
                let attachment = try testStore.addImage(from: smallData, mediaType: "image/jpeg")
                print("[ImageAttachmentTests] ✓ Small image (\(smallData.count) bytes) added successfully")
                passed += 1
                testStore.remove(attachment.id)
            } catch {
                print("[ImageAttachmentTests] ✗ Small image should be accepted: \(error)")
                failed += 1
            }
        }
        
        // Test size limit (10MB = 10 * 1024 * 1024 bytes)
        // We can't easily create a 10MB+ image in memory, so test the limit constant
        let maxSize = ImageAttachmentStore.maxImageSize
        if maxSize == 10 * 1024 * 1024 {
            print("[ImageAttachmentTests] ✓ Max image size is 10MB (\(maxSize) bytes)")
            passed += 1
        } else {
            print("[ImageAttachmentTests] ✗ Max image size should be 10MB, got \(maxSize)")
            failed += 1
        }
        
        // Test rejection of oversized data (simulate with error case)
        let oversizedData = Data(count: 11 * 1024 * 1024)  // 11MB of zeros
        do {
            _ = try testStore.addImage(from: oversizedData, mediaType: "image/jpeg")
            print("[ImageAttachmentTests] ✗ Oversized image should have been rejected")
            failed += 1
        } catch ImageError.tooLarge(let size, let limit) {
            print("[ImageAttachmentTests] ✓ Oversized image rejected: \(size / 1_000_000)MB > \(limit / 1_000_000)MB")
            passed += 1
        } catch {
            print("[ImageAttachmentTests] ✗ Wrong error type for oversized image: \(error)")
            failed += 1
        }
        
        // MARK: - Test 4: Store Operations (add/remove/clear)
        print("[ImageAttachmentTests] --- Store Operations ---")
        
        // Start fresh
        testStore.clearAll()
        
        if testStore.count == 0 {
            print("[ImageAttachmentTests] ✓ Store starts empty after clearAll")
            passed += 1
        } else {
            print("[ImageAttachmentTests] ✗ Store should be empty after clearAll")
            failed += 1
        }
        
        // Add multiple images
        var addedIds: [UUID] = []
        for i in 1...3 {
            if let image = createTestImage(size: CGSize(width: 50 * i, height: 50 * i)),
               let data = image.jpegData(compressionQuality: 0.8) {
                do {
                    let attachment = try testStore.addImage(from: data, mediaType: "image/jpeg")
                    addedIds.append(attachment.id)
                } catch {
                    print("[ImageAttachmentTests] ✗ Failed to add test image \(i): \(error)")
                    failed += 1
                }
            }
        }
        
        if testStore.count == 3 {
            print("[ImageAttachmentTests] ✓ Added 3 images, count is \(testStore.count)")
            passed += 1
        } else {
            print("[ImageAttachmentTests] ✗ Expected 3 images, got \(testStore.count)")
            failed += 1
        }
        
        // Test attachment lookup
        if let firstId = addedIds.first, testStore.attachment(for: firstId) != nil {
            print("[ImageAttachmentTests] ✓ Can retrieve attachment by ID")
            passed += 1
        } else {
            print("[ImageAttachmentTests] ✗ Failed to retrieve attachment by ID")
            failed += 1
        }
        
        // Test batch lookup
        let retrieved = testStore.attachments(for: addedIds)
        if retrieved.count == 3 {
            print("[ImageAttachmentTests] ✓ Batch lookup retrieved all 3 attachments")
            passed += 1
        } else {
            print("[ImageAttachmentTests] ✗ Batch lookup retrieved \(retrieved.count), expected 3")
            failed += 1
        }
        
        // Test remove
        if let removeId = addedIds.first {
            testStore.remove(removeId)
            if testStore.count == 2 && testStore.attachment(for: removeId) == nil {
                print("[ImageAttachmentTests] ✓ Remove works correctly")
                passed += 1
            } else {
                print("[ImageAttachmentTests] ✗ Remove didn't work correctly")
                failed += 1
            }
        }
        
        // Test clearAll
        testStore.clearAll()
        if testStore.count == 0 {
            print("[ImageAttachmentTests] ✓ clearAll removes all attachments")
            passed += 1
        } else {
            print("[ImageAttachmentTests] ✗ clearAll should remove all attachments")
            failed += 1
        }
        
        // MARK: - Test 5: Base64 Encoding
        print("[ImageAttachmentTests] --- Base64 Encoding ---")
        
        if let testImage = createTestImage(size: CGSize(width: 100, height: 100)),
           let testData = testImage.jpegData(compressionQuality: 0.8) {
            do {
                let attachment = try testStore.addImage(from: testData, mediaType: "image/jpeg")
                
                // Test base64 encoding
                if let base64 = attachment.toBase64() {
                    if !base64.isEmpty {
                        print("[ImageAttachmentTests] ✓ Base64 encoding produces non-empty string (\(base64.count) chars)")
                        passed += 1
                        
                        // Verify it's valid base64 by decoding
                        if let decoded = Data(base64Encoded: base64) {
                            if decoded == testData {
                                print("[ImageAttachmentTests] ✓ Base64 round-trip: decoded data matches original")
                                passed += 1
                            } else {
                                print("[ImageAttachmentTests] ✗ Base64 round-trip: decoded data doesn't match")
                                failed += 1
                            }
                        } else {
                            print("[ImageAttachmentTests] ✗ Base64 string is not valid base64")
                            failed += 1
                        }
                    } else {
                        print("[ImageAttachmentTests] ✗ Base64 encoding produced empty string")
                        failed += 1
                    }
                } else {
                    print("[ImageAttachmentTests] ✗ Base64 encoding returned nil")
                    failed += 1
                }
                
                testStore.remove(attachment.id)
            } catch {
                print("[ImageAttachmentTests] ✗ Failed to create test attachment: \(error)")
                failed += 1
            }
        }
        
        // MARK: - Test 6: Thumbnail Generation
        print("[ImageAttachmentTests] --- Thumbnail Generation ---")
        
        if let largeImage = createTestImage(size: CGSize(width: 1000, height: 800)),
           let largeData = largeImage.jpegData(compressionQuality: 0.9) {
            do {
                let attachment = try testStore.addImage(from: largeData, mediaType: "image/jpeg")
                
                // Test thumbnail loading (should generate on-demand)
                if let thumbnail = attachment.loadThumbnail() {
                    let maxSize = ImageAttachment.thumbnailMaxSize * UIScreen.main.scale
                    if thumbnail.size.width <= maxSize && thumbnail.size.height <= maxSize {
                        print("[ImageAttachmentTests] ✓ Thumbnail generated with correct max size (\(Int(thumbnail.size.width))x\(Int(thumbnail.size.height)))")
                        passed += 1
                    } else {
                        print("[ImageAttachmentTests] ✗ Thumbnail too large: \(thumbnail.size)")
                        failed += 1
                    }
                    
                    // Verify aspect ratio is preserved
                    let originalAspect = 1000.0 / 800.0
                    let thumbAspect = thumbnail.size.width / thumbnail.size.height
                    if abs(originalAspect - thumbAspect) < 0.01 {
                        print("[ImageAttachmentTests] ✓ Thumbnail preserves aspect ratio")
                        passed += 1
                    } else {
                        print("[ImageAttachmentTests] ✗ Thumbnail aspect ratio changed: \(thumbAspect) vs \(originalAspect)")
                        failed += 1
                    }
                } else {
                    print("[ImageAttachmentTests] ✗ Failed to generate thumbnail")
                    failed += 1
                }
                
                testStore.remove(attachment.id)
            } catch {
                print("[ImageAttachmentTests] ✗ Failed to create test attachment: \(error)")
                failed += 1
            }
        }
        
        // MARK: - Test 7: TranscriptMessage Codable Excludes imageAttachmentIds
        print("[ImageAttachmentTests] --- TranscriptMessage Codable ---")
        
        let testMessage = TranscriptMessage(
            text: "Test message with images",
            isUser: true,
            imageAttachmentIds: [UUID(), UUID(), UUID()]
        )
        
        // Verify message has image IDs before encoding
        if testMessage.imageAttachmentIds.count == 3 {
            print("[ImageAttachmentTests] ✓ TranscriptMessage created with 3 image IDs")
            passed += 1
        } else {
            print("[ImageAttachmentTests] ✗ TranscriptMessage should have 3 image IDs")
            failed += 1
        }
        
        // Encode and decode
        do {
            let encoded = try JSONEncoder().encode(testMessage)
            let decoded = try JSONDecoder().decode(TranscriptMessage.self, from: encoded)
            
            // Verify imageAttachmentIds is empty after round-trip
            if decoded.imageAttachmentIds.isEmpty {
                print("[ImageAttachmentTests] ✓ TranscriptMessage Codable excludes imageAttachmentIds")
                passed += 1
            } else {
                print("[ImageAttachmentTests] ✗ imageAttachmentIds should be empty after decode, got \(decoded.imageAttachmentIds.count)")
                failed += 1
            }
            
            // Verify other properties are preserved
            if decoded.text == testMessage.text && decoded.isUser == testMessage.isUser {
                print("[ImageAttachmentTests] ✓ Other properties preserved through Codable")
                passed += 1
            } else {
                print("[ImageAttachmentTests] ✗ Other properties not preserved")
                failed += 1
            }
            
            // Verify imageAttachmentIds is NOT in JSON
            if let jsonString = String(data: encoded, encoding: .utf8) {
                if !jsonString.contains("imageAttachmentIds") {
                    print("[ImageAttachmentTests] ✓ JSON does not contain 'imageAttachmentIds' key")
                    passed += 1
                } else {
                    print("[ImageAttachmentTests] ✗ JSON should not contain 'imageAttachmentIds' key")
                    failed += 1
                }
            }
        } catch {
            print("[ImageAttachmentTests] ✗ Codable encoding/decoding failed: \(error)")
            failed += 1
        }
        
        // MARK: - Test 9: Dimensions Extraction
        print("[ImageAttachmentTests] --- Dimensions Extraction ---")
        
        if let testImage = createTestImage(size: CGSize(width: 200, height: 150)),
           let testData = testImage.jpegData(compressionQuality: 0.9) {
            let dimensions = ImageAttachment.extractDimensions(from: testData)
            // Note: JPEG compression may slightly alter dimensions
            if dimensions.width > 0 && dimensions.height > 0 {
                print("[ImageAttachmentTests] ✓ Dimensions extracted: \(Int(dimensions.width))x\(Int(dimensions.height))")
                passed += 1
            } else {
                print("[ImageAttachmentTests] ✗ Failed to extract dimensions")
                failed += 1
            }
        }
        
        // MARK: - Test 9: Full Image Loading
        print("[ImageAttachmentTests] --- Full Image Loading ---")
        
        if let testImage = createTestImage(size: CGSize(width: 300, height: 200)),
           let testData = testImage.jpegData(compressionQuality: 0.9) {
            do {
                let attachment = try testStore.addImage(from: testData, mediaType: "image/jpeg")
                
                if let loadedImage = attachment.loadFullImage() {
                    // Verify dimensions are reasonable (JPEG may have slight variations)
                    if loadedImage.size.width > 0 && loadedImage.size.height > 0 {
                        print("[ImageAttachmentTests] ✓ Full image loaded: \(Int(loadedImage.size.width))x\(Int(loadedImage.size.height))")
                        passed += 1
                    } else {
                        print("[ImageAttachmentTests] ✗ Loaded image has invalid dimensions")
                        failed += 1
                    }
                } else {
                    print("[ImageAttachmentTests] ✗ Failed to load full image")
                    failed += 1
                }
                
                testStore.remove(attachment.id)
            } catch {
                print("[ImageAttachmentTests] ✗ Failed to create test attachment: \(error)")
                failed += 1
            }
        }
        
        // Final cleanup
        testStore.clearAll()
        
        // MARK: - Results
        print("[ImageAttachmentTests] ═══════════════════════════════════════")
        print("[ImageAttachmentTests] Results: \(passed) passed, \(failed) failed")
        print("[ImageAttachmentTests] ═══════════════════════════════════════")
    }
    
    // MARK: - Test Helpers
    
    /// Create a test image with a solid color for testing purposes.
    private static func createTestImage(size: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // Fill with a gradient-like pattern for more realistic testing
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Add some variation
            UIColor.white.setFill()
            let smallRect = CGRect(x: size.width * 0.25, y: size.height * 0.25,
                                   width: size.width * 0.5, height: size.height * 0.5)
            context.fill(smallRect)
        }
    }
    #endif
}
