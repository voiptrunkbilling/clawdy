import SwiftUI

/// Manual entry form for lead capture.
/// Pre-filled with parsed data from voice notes, business cards, or call follow-ups.
struct LeadCaptureFormView: View {
    @ObservedObject var manager: LeadCaptureManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingDatePicker = false
    @State private var isSaving = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Contact Info Section
                Section {
                    TextField("Name *", text: $manager.currentLead.name)
                        .textContentType(.name)
                        .autocapitalization(.words)
                    
                    TextField("Company", text: $manager.currentLead.company)
                        .textContentType(.organizationName)
                        .autocapitalization(.words)
                    
                    TextField("Title", text: $manager.currentLead.title)
                        .textContentType(.jobTitle)
                        .autocapitalization(.words)
                    
                    TextField("Phone", text: $manager.currentLead.phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    
                    TextField("Email", text: $manager.currentLead.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                } header: {
                    Text("Contact Information")
                } footer: {
                    Text("* Name is required")
                        .foregroundColor(.secondary)
                }
                
                // MARK: - Notes Section
                Section("Notes") {
                    TextEditor(text: $manager.currentLead.notes)
                        .frame(minHeight: 100)
                }
                
                // MARK: - Actions Section
                Section("Actions") {
                    Toggle("Create Contact", isOn: $manager.currentLead.shouldCreateContact)
                    
                    Toggle("Schedule Follow-up Reminder", isOn: $manager.currentLead.shouldScheduleReminder)
                    
                    if manager.currentLead.shouldScheduleReminder {
                        DatePicker(
                            "Follow-up Date",
                            selection: Binding(
                                get: { manager.currentLead.followUpDate ?? Date().addingTimeInterval(24 * 60 * 60) },
                                set: { manager.currentLead.followUpDate = $0 }
                            ),
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                    
                    Toggle("Send Email Summary", isOn: $manager.currentLead.shouldSendEmailSummary)
                    
                    if manager.currentLead.shouldSendEmailSummary {
                        TextField("Summary Email Address", text: Binding(
                            get: { manager.currentLead.emailSummaryRecipient ?? "" },
                            set: { manager.currentLead.emailSummaryRecipient = $0.isEmpty ? nil : $0 }
                        ))
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    }
                }
                
                // MARK: - Capture Info Section
                if manager.currentLead.rawInput != nil {
                    Section("Capture Details") {
                        HStack {
                            Text("Method")
                            Spacer()
                            Text(manager.currentLead.captureMethod.displayName)
                                .foregroundColor(.secondary)
                        }
                        
                        if let rawInput = manager.currentLead.rawInput {
                            DisclosureGroup("Raw Input") {
                                Text(rawInput)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Capture Lead")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        manager.cancelCapture()
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveLead()
                        }
                    }
                    .disabled(isSaving || manager.currentLead.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Saving...")
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(10)
                }
            }
            .alert("Save Failed", isPresented: $showingSaveError) {
                Button("OK") {}
            } message: {
                Text(saveErrorMessage)
            }
        }
    }
    
    private func saveLead() async {
        isSaving = true
        
        let result = await manager.saveLead()
        
        isSaving = false
        
        switch result {
        case .success:
            dismiss()
        case .failed(let error):
            saveErrorMessage = error.localizedDescription ?? "Unknown error"
            showingSaveError = true
        case .cancelled:
            dismiss()
        }
    }
}

/// Quick action buttons for lead capture entry points.
struct LeadCaptureQuickActionsView: View {
    @ObservedObject var manager: LeadCaptureManager
    var onVoiceNote: () -> Void
    var onBusinessCard: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Capture Lead")
                .font(.headline)
            
            HStack(spacing: 20) {
                LeadCaptureActionButton(
                    icon: "mic.fill",
                    title: "Voice Note",
                    color: .blue
                ) {
                    onVoiceNote()
                }
                
                LeadCaptureActionButton(
                    icon: "camera.fill",
                    title: "Business Card",
                    color: .green
                ) {
                    onBusinessCard()
                }
                
                LeadCaptureActionButton(
                    icon: "pencil",
                    title: "Manual",
                    color: .orange
                ) {
                    manager.startManualEntry()
                }
            }
        }
        .padding()
    }
}

/// Individual action button for lead capture.
struct LeadCaptureActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(color)
                    .clipShape(Circle())
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Call follow-up prompt shown after a call ends.
struct CallFollowUpPromptView: View {
    let phoneNumber: String?
    let onCapture: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "phone.badge.checkmark")
                .font(.title)
                .foregroundColor(.green)
            
            Text("Call Ended")
                .font(.headline)
            
            if let phone = phoneNumber {
                Text(phone)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text("Would you like to capture lead info?")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 20) {
                Button("Not Now") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Capture Lead") {
                    onCapture()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(radius: 10)
    }
}

/// Business card camera capture view.
struct BusinessCardCaptureView: View {
    @ObservedObject var manager: LeadCaptureManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var capturedImage: UIImage?
    @State private var showingCamera = true
    
    var body: some View {
        NavigationStack {
            VStack {
                if showingCamera {
                    BusinessCardCameraView(capturedImage: $capturedImage)
                        .ignoresSafeArea()
                } else if let image = capturedImage {
                    VStack(spacing: 20) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                            .padding()
                        
                        if manager.captureState == .processingBusinessCard {
                            ProgressView("Reading business card...")
                        } else {
                            HStack(spacing: 20) {
                                Button("Retake") {
                                    capturedImage = nil
                                    showingCamera = true
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Use Photo") {
                                    Task {
                                        await manager.captureFromBusinessCard(image)
                                        if manager.captureState == .manualEntry {
                                            dismiss()
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Scan Business Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: capturedImage) { newImage in
                if newImage != nil {
                    showingCamera = false
                }
            }
        }
    }
}

/// Simple camera view for business card capture.
struct BusinessCardCameraView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: BusinessCardCameraView
        
        init(_ parent: BusinessCardCameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.capturedImage = image
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            // Let parent handle dismissal
        }
    }
}

// MARK: - Previews

#Preview("Lead Capture Form") {
    LeadCaptureFormView(manager: LeadCaptureManager.shared)
}

#Preview("Quick Actions") {
    LeadCaptureQuickActionsView(
        manager: LeadCaptureManager.shared,
        onVoiceNote: {},
        onBusinessCard: {}
    )
}

#Preview("Call Follow-up Prompt") {
    CallFollowUpPromptView(
        phoneNumber: "+1 (555) 123-4567",
        onCapture: {},
        onDismiss: {}
    )
}
