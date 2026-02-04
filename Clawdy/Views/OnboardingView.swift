import SwiftUI

/// Full-screen onboarding view with permission explanation screens.
/// Presents before main app content on first launch.
struct OnboardingView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var isProcessingAction = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.4)]),
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
                        .foregroundColor(.white)
                        .padding(.bottom, 30)
                    
                    // Title
                    Text(step.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 16)
                    
                    // Description
                    Text(step.description)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                    
                    // Progress indicator
                    HStack(spacing: 8) {
                        ForEach(OnboardingCoordinator.OnboardingStep.allCases, id: \.rawValue) { s in
                            Circle()
                                .fill(s == step ? Color.white : Color.white.opacity(0.4))
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
                                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                        .padding(.trailing, 8)
                                }
                                Text(step.buttonTitle)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .foregroundColor(.blue)
                            .cornerRadius(12)
                        }
                        .disabled(isProcessingAction)
                        
                        // Skip button (for permission steps)
                        if let skipTitle = step.skipButtonTitle {
                            Button(action: {
                                coordinator.handleSkipAction()
                            }) {
                                Text(skipTitle)
                                    .foregroundColor(.white.opacity(0.8))
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
