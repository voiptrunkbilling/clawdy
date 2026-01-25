import SwiftUI
import QuickLook

/// A full-screen image viewer using QuickLook.
/// Provides pinch-to-zoom, swipe navigation between images, and standard QuickLook controls.
struct QuickLookView: UIViewControllerRepresentable {
    /// URLs of images to display
    let imageURLs: [URL]
    
    /// Index of the initially displayed image
    let initialIndex: Int
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.currentPreviewItemIndex = initialIndex
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        // Update data source if URLs change
        context.coordinator.imageURLs = imageURLs
        uiViewController.reloadData()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(imageURLs: imageURLs)
    }
    
    // MARK: - Coordinator
    
    /// Coordinator that serves as the data source for QLPreviewController.
    /// Provides the image URLs as preview items for QuickLook.
    class Coordinator: NSObject, QLPreviewControllerDataSource {
        var imageURLs: [URL]
        
        init(imageURLs: [URL]) {
            self.imageURLs = imageURLs
            super.init()
        }
        
        // MARK: - QLPreviewControllerDataSource
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            imageURLs.count
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            // NSURL conforms to QLPreviewItem, so we can return it directly
            imageURLs[index] as NSURL
        }
    }
}

// MARK: - Preview

#if DEBUG
struct QuickLookView_Previews: PreviewProvider {
    static var previews: some View {
        // QuickLookView requires actual file URLs to display
        // In preview, we just show a placeholder
        Text("QuickLookView - Requires actual image URLs")
            .previewDisplayName("QuickLookView")
    }
}
#endif
