import SwiftUI

/// Grid layout for displaying image thumbnails within a message bubble.
/// Uses a 1-column layout for single images, 2-column for 2-3 images.
/// Each thumbnail is tappable to view full-screen via Quick Look.
struct MessageImageGrid: View {
    /// UUIDs of the images to display
    let attachmentIds: [UUID]
    
    /// The image store containing the actual image data
    let imageStore: ImageAttachmentStore
    
    /// Callback when a thumbnail is tapped (for Quick Look)
    let onTap: (ImageAttachment) -> Void
    
    /// Thumbnail size in points
    private let thumbnailSize: CGFloat = 80
    
    /// Spacing between thumbnails
    private let spacing: CGFloat = 4
    
    /// Corner radius for thumbnails
    private let cornerRadius: CGFloat = 6
    
    var body: some View {
        let columns = gridColumns(for: attachmentIds.count)
        
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            ForEach(attachmentIds, id: \.self) { id in
                if let attachment = imageStore.attachment(for: id) {
                    Button(action: { onTap(attachment) }) {
                        AsyncThumbnailImage(attachment: attachment)
                            .frame(width: thumbnailSize, height: thumbnailSize)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Image")
                    .accessibilityHint("Double tap to view full screen")
                }
            }
        }
    }
    
    /// Determine grid columns based on number of images.
    /// - Parameter count: Number of images
    /// - Returns: Array of GridItem for LazyVGrid
    private func gridColumns(for count: Int) -> [GridItem] {
        // 1 image: 1 column, 2-3 images: 2 columns
        let columnCount = count == 1 ? 1 : 2
        return Array(
            repeating: GridItem(.fixed(thumbnailSize), spacing: spacing),
            count: columnCount
        )
    }
}

// MARK: - AsyncThumbnailImage

/// Asynchronously loads and displays a thumbnail image from an attachment.
/// Shows a placeholder while loading and handles loading failures gracefully.
struct AsyncThumbnailImage: View {
    let attachment: ImageAttachment
    
    /// The loaded thumbnail image (nil while loading or if failed)
    @State private var loadedImage: UIImage?
    
    /// Whether the image is currently loading
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectFill()
            } else if isLoading {
                // Loading placeholder
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
            } else {
                // Failed to load placeholder
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    }
            }
        }
        .task {
            await loadThumbnail()
        }
    }
    
    /// Load the thumbnail image on a background thread
    private func loadThumbnail() async {
        // Load on background thread to avoid blocking UI
        let image = await Task.detached(priority: .userInitiated) {
            return attachment.loadThumbnail()
        }.value
        
        await MainActor.run {
            self.loadedImage = image
            self.isLoading = false
        }
    }
}

// MARK: - Image Aspect Fill Extension

extension Image {
    /// Scales the image to fill the available space while maintaining aspect ratio.
    /// The image will be clipped if it exceeds the bounds.
    func aspectFill() -> some View {
        self
            .scaledToFill()
            .clipped()
    }
}

// MARK: - Preview

#if DEBUG
struct MessageImageGrid_Previews: PreviewProvider {
    static var previews: some View {
        // Preview with mock data would go here
        Text("MessageImageGrid Preview")
            .previewDisplayName("MessageImageGrid")
    }
}
#endif
