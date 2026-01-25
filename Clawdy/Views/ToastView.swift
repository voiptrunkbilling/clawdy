import SwiftUI

/// A toast notification view that displays a brief message with an optional icon.
/// Designed to appear at the bottom of the screen and auto-dismiss.
///
/// Usage:
/// ```swift
/// .overlay(alignment: .bottom) {
///     if let message = viewModel.toastMessage {
///         ToastView(message: message)
///             .padding(.bottom, 100)
///             .transition(.move(edge: .bottom).combined(with: .opacity))
///     }
/// }
/// ```
struct ToastView: View {
    let message: String
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: 10) {
            if let iconName = icon {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }
            
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(Color(.systemGray).opacity(0.95))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        .accessibilityAddTraits(.isStaticText)
    }
}

#Preview {
    VStack(spacing: 20) {
        ToastView(message: "Context cleared")
        ToastView(message: "Context cleared", icon: "checkmark.circle.fill")
        ToastView(message: "Connection restored", icon: "wifi")
    }
    .padding()
}
