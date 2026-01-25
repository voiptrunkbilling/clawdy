import SwiftUI

/// Individual thumbnail image with optional remove button overlay.
/// Used in both the image preview strip (with remove button) and 
/// transcript message bubbles (without remove button, tappable for Quick Look).
///
/// Layout:
/// - 80x80pt thumbnail with 8pt corner radius
/// - Optional X button in top-right corner
/// - Lazy thumbnail loading from ImageAttachment
///
/// Accessibility:
/// - Preview mode: "Image {n} of {total}, double tap to remove"
/// - Transcript mode: "Image, double tap to view full screen"
struct ImageThumbnailView: View {
    /// The image attachment to display
    let attachment: ImageAttachment
    
    /// Optional callback when remove button is tapped (nil hides remove button)
    let onRemove: (() -> Void)?
    
    /// Optional position info for accessibility (1-indexed)
    var position: Int? = nil
    var total: Int? = nil
    
    /// Thumbnail size in points
    private let thumbnailSize: CGFloat = 80
    
    /// Corner radius for thumbnail
    private let cornerRadius: CGFloat = 8
    
    /// Loaded thumbnail image (lazy)
    @State private var thumbnailImage: UIImage?
    
    /// Whether the image is currently loading
    @State private var isLoading = true
    
    // MARK: - Initialization
    
    /// Create thumbnail with remove button (for preview strip)
    init(attachment: ImageAttachment, onRemove: @escaping () -> Void) {
        self.attachment = attachment
        self.onRemove = onRemove
    }
    
    /// Create thumbnail for transcript (tappable, no remove button)
    init(attachment: ImageAttachment) {
        self.attachment = attachment
        self.onRemove = nil
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail image
            thumbnailImageView
            
            // Remove button overlay (only if onRemove callback provided)
            if onRemove != nil {
                removeButton
            }
        }
        .frame(width: thumbnailSize, height: thumbnailSize)
        .onAppear {
            loadThumbnail()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
        .accessibilityAddTraits(.isImage)
    }
    
    // MARK: - Subviews
    
    /// The thumbnail image or placeholder
    @ViewBuilder
    private var thumbnailImageView: some View {
        if let image = thumbnailImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipped()
                .cornerRadius(cornerRadius)
        } else {
            // Loading/placeholder state
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.tertiarySystemFill))
                .frame(width: thumbnailSize, height: thumbnailSize)
                .overlay {
                    if isLoading {
                        ProgressView()
                            .tint(.secondary)
                    } else {
                        // Failed to load
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    }
                }
        }
    }
    
    /// Remove button overlay
    private var removeButton: some View {
        Button(action: {
            // Light haptic feedback on remove
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            
            // Announce for VoiceOver users
            UIAccessibility.post(notification: .announcement, argument: "Image removed")
            
            onRemove?()
        }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.black.opacity(0.6))
        }
        .offset(x: 4, y: -4)
        .accessibilityLabel("Remove image")
        .accessibilityHint("Double tap to remove this image")
    }
    
    // MARK: - Loading
    
    /// Load thumbnail asynchronously
    private func loadThumbnail() {
        isLoading = true
        
        // Load thumbnail off main thread
        Task.detached(priority: .userInitiated) {
            let thumbnail = attachment.loadThumbnail()
            
            await MainActor.run {
                self.thumbnailImage = thumbnail
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Accessibility
    
    /// Accessibility label for the thumbnail
    private var accessibilityLabelText: String {
        if let position = position, let total = total {
            return "Image \(position) of \(total)"
        }
        return "Image"
    }
    
    /// Accessibility hint for the thumbnail
    private var accessibilityHintText: String {
        if onRemove != nil {
            return "Double tap to remove"
        }
        return "Double tap to view full screen"
    }
}

// MARK: - Preview Strip Variant

extension ImageThumbnailView {
    /// Convenience initializer for preview strip with position info
    init(
        attachment: ImageAttachment,
        position: Int,
        total: Int,
        onRemove: @escaping () -> Void
    ) {
        self.attachment = attachment
        self.onRemove = onRemove
        self.position = position
        self.total = total
    }
}

// MARK: - Previews

#Preview("With Remove Button") {
    // Create a mock attachment for preview
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.jpg")
    let attachment = ImageAttachment(
        tempFileURL: tempURL,
        mediaType: "image/jpeg",
        originalSize: 1000,
        dimensions: CGSize(width: 100, height: 100)
    )
    
    return ImageThumbnailView(
        attachment: attachment,
        onRemove: { print("Remove tapped") }
    )
    .padding()
}

#Preview("Without Remove Button") {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.jpg")
    let attachment = ImageAttachment(
        tempFileURL: tempURL,
        mediaType: "image/jpeg",
        originalSize: 1000,
        dimensions: CGSize(width: 100, height: 100)
    )
    
    return ImageThumbnailView(attachment: attachment)
        .padding()
}

#Preview("Loading State") {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent.jpg")
    let attachment = ImageAttachment(
        tempFileURL: tempURL,
        mediaType: "image/jpeg",
        originalSize: 1000,
        dimensions: CGSize(width: 100, height: 100)
    )
    
    return ImageThumbnailView(
        attachment: attachment,
        onRemove: { print("Remove tapped") }
    )
    .padding()
}
