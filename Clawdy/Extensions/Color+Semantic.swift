import SwiftUI

/// Semantic color extensions for dark mode support.
/// These colors adapt automatically to light and dark mode using asset catalog definitions.
extension Color {
    // MARK: - Custom Asset Colors
    
    /// Semi-transparent overlay background for modals and sheets
    static let overlayBackground = Color("OverlayBackground")
    
    /// High contrast text color (white in both modes)
    static let contrastText = Color("ContrastText")
    
    /// Inactive indicator color with reduced opacity
    static let inactiveIndicator = Color("InactiveIndicator")
    
    /// Camera flash color (pure white)
    static let flashColor = Color("FlashColor")
    
    /// Destructive button background (red variants)
    static let buttonDestructive = Color("ButtonDestructive")
    
    /// Disabled button background (gray variants)
    static let buttonDisabled = Color("ButtonDisabled")
    
    // MARK: - Message Bubble Colors
    
    /// User message bubble background (blue variant)
    static let userBubbleBackground = Color("UserBubbleBackground")
    
    /// Text color on user message bubbles (white)
    static let onUserBubble = Color("OnUserBubble")
    
    // MARK: - Banner Colors
    
    /// Offline/error banner background (red variant)
    static let bannerBackground = Color("BannerBackground")
    
    /// Text color on banners (white)
    static let bannerText = Color("BannerText")
    
    // MARK: - PTT Button Colors
    
    /// PTT button idle state (accent blue)
    static let pttIdle = Color("PTTIdle")
    
    /// PTT button recording state (red)
    static let pttRecording = Color("PTTRecording")
    
    /// PTT button cancelled state (gray)
    static let pttCancelled = Color("PTTCancelled")
    
    /// PTT button thinking state (orange)
    static let pttThinking = Color("PTTThinking")
    
    /// PTT button responding state (green)
    static let pttResponding = Color("PTTResponding")
    
    /// Icon color on PTT button (white)
    static let onPTTButton = Color("OnPTTButton")
    
    // MARK: - Semantic Aliases
    
    /// For modal/overlay backgrounds - use this instead of Color.black.opacity()
    static let modalScrim: Color {
        overlayBackground
    }
    
    /// For text that needs to maintain contrast on colored backgrounds
    static let onAccent: Color {
        contrastText
    }
}

// MARK: - Convenience Modifiers

extension View {
    /// Apply a modal overlay background
    func modalOverlay() -> some View {
        self.background(Color.overlayBackground.ignoresSafeArea())
    }
}
