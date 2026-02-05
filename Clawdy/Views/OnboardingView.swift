import SwiftUI

/// Full-screen onboarding view with permission explanation screens.
/// Presents before main app content on first launch.
struct OnboardingView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var isProcessingAction = false
    @Environment(\.colorScheme) private var colorScheme
    
    /// Adaptive gradient colors for dark mode support
    private var gradientColors: [Color] {
        if colorScheme == .dark {
            return [Color.blue.opacity(0.35), Color.purple.opacity(0.25)]
        } else {
            return [Color.blue.opacity(0.6), Color.purple.opacity(0.4)]
        }
    }
    
    /// Adaptive text color for contrast
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .white
    }
    
    /// Adaptive secondary text color
    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.85) : .white.opacity(0.9)
    }
    
    /// Adaptive button background
    private var buttonBackground: Color {
        colorScheme == .dark ? Color(.systemBackground) : .white
    }
    
    /// Adaptive button text color
    private var buttonTextColor: Color {
        colorScheme == .dark ? .accentColor : .blue
    }
    
    var body: some View {
        ZStack {
            // Background gradient - adaptive for dark mode
            LinearGradient(
                gradient: Gradient(colors: gradientColors),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                if let step = coordinator.currentStep {
                    // Icon
                    Image(systemName: step.systemImageName)
                        .font(.largeTitle)
                        .foregroundColor(primaryTextColor)
                        .padding(.bottom, 30)
                    
                    // Title
                    Text(step.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(primaryTextColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 16)
                    
                    // Description
                    Text(step.description)
                        .font(.body)
                        .foregroundColor(secondaryTextColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                    
                    // Progress indicator
                    HStack(spacing: 8) {
                        ForEach(OnboardingCoordinator.OnboardingStep.allCases, id: \.rawValue) { s in
                            Circle()
                                .fill(s == step ? primaryTextColor : primaryTextColor.opacity(0.4))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.bottom, 40)
                }
                
                Spacer()
                
                // Buttons
                if let step = coordinator.currentStep {
                    VStack(spacing: 12) {
                        // Primary action button
                        Button(action: {
                            handlePrimaryAction()
                        }) {
                            HStack {
                                if isProcessingAction {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: buttonTextColor))
                                        .padding(.trailing, 8)
                                }
                                Text(step.buttonTitle)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(buttonBackground)
                            .foregroundColor(buttonTextColor)
                            .cornerRadius(12)
                        }
                        .disabled(isProcessingAction)
                        
                        // Skip button (for permission steps)
                        if let skipTitle = step.skipButtonTitle {
                            Button(action: {
                                coordinator.handleSkipAction()
                            }) {
                                Text(skipTitle)
                                    .foregroundColor(primaryTextColor.opacity(0.8))
                            }
                            .disabled(isProcessingAction)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 60)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: coordinator.currentStep)
    }
    
    private func handlePrimaryAction() {
        isProcessingAction = true
        Task {
            await coordinator.handlePrimaryAction()
            await MainActor.run {
                isProcessingAction = false
            }
        }
    }
}

#Preview {
    OnboardingView(coordinator: OnboardingCoordinator.shared)
}
