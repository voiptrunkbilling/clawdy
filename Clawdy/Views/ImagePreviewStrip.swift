import SwiftUI

/// Horizontal strip of image thumbnails displayed above the text input bar.
/// Shows pending images that will be attached to the next message.
///
/// Layout:
/// - Horizontal ScrollView (no scroll indicators)
/// - HStack of ImageThumbnailView with 8pt spacing
/// - 16pt horizontal padding, 8pt vertical padding
/// - Only shown when there are pending images
///
/// Accessibility:
/// - Each thumbnail announces its position (e.g., "Image 1 of 3")
/// - Remove buttons are accessible with clear labels
/// - Strip is grouped as "Pending images" for VoiceOver navigation
struct ImagePreviewStrip: View {
    /// Images pending attachment to the next message
    let images: [ImageAttachment]
    
    /// Callback when an image's remove button is tapped
    let onRemove: (UUID) -> Void
    
    /// Spacing between thumbnails
    private let thumbnailSpacing: CGFloat = 8
    
    /// Horizontal padding for the strip
    private let horizontalPadding: CGFloat = 16
    
    /// Vertical padding for the strip
    private let verticalPadding: CGFloat = 8
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: thumbnailSpacing) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, attachment in
                    ImageThumbnailView(
                        attachment: attachment,
                        position: index + 1,
                        total: images.count,
                        onRemove: { onRemove(attachment.id) }
                    )
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pending images")
        .accessibilityHint("\(images.count) \(images.count == 1 ? "image" : "images") will be sent with your message")
    }
}

// MARK: - Conditional Wrapper

extension ImagePreviewStrip {
    /// Returns the preview strip only if there are images, otherwise returns nil.
    /// This allows for cleaner conditional rendering in parent views.
    @ViewBuilder
    static func ifNotEmpty(
        images: [ImageAttachment],
        onRemove: @escaping (UUID) -> Void
    ) -> some View {
        if !images.isEmpty {
            ImagePreviewStrip(images: images, onRemove: onRemove)
        }
    }
}

// MARK: - Previews

#Preview("Single Image") {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.jpg")
    let attachment = ImageAttachment(
        tempFileURL: tempURL,
        mediaType: "image/jpeg",
        originalSize: 1000,
        dimensions: CGSize(width: 100, height: 100)
    )
    
    return VStack {
        Spacer()
        ImagePreviewStrip(
            images: [attachment],
            onRemove: { id in print("Remove: \(id)") }
        )
        .background(Color(.systemBackground))
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Multiple Images") {
    let tempURL = FileManager.default.temporaryDirectory
    let attachments = (1...3).map { index in
        ImageAttachment(
            tempFileURL: tempURL.appendingPathComponent("test\(index).jpg"),
            mediaType: "image/jpeg",
            originalSize: 1000 * index,
            dimensions: CGSize(width: 100, height: 100)
        )
    }
    
    return VStack {
        Spacer()
        ImagePreviewStrip(
            images: attachments,
            onRemove: { id in print("Remove: \(id)") }
        )
        .background(Color(.systemBackground))
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Empty State") {
    VStack {
        Spacer()
        ImagePreviewStrip.ifNotEmpty(
            images: [],
            onRemove: { _ in }
        )
        Text("No images - preview strip hidden")
            .foregroundColor(.secondary)
    }
}
