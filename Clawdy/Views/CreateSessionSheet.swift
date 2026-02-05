import SwiftUI

/// Sheet for creating a new chat session.
/// Includes agent selection, name input, icon picker, and color picker.
struct CreateSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sessionManager: SessionManager
    
    // Form state
    @State private var sessionName: String = ""
    @State private var selectedAgent: PredefinedAgent = .main
    @State private var selectedIcon: String = "bubble.left.and.bubble.right.fill"
    @State private var selectedColor: String = "#0A84FF"
    @State private var isCreating: Bool = false
    @State private var showValidationError: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Agent selection
                Section {
                    Picker("Agent Type", selection: $selectedAgent) {
                        ForEach(PredefinedAgent.allCases) { agent in
                            HStack {
                                Image(systemName: agent.defaultIcon)
                                    .foregroundStyle(Color(hex: agent.defaultColor) ?? .blue)
                                Text(agent.displayName)
                            }
                            .tag(agent)
                        }
                    }
                    .onChange(of: selectedAgent) { _, newAgent in
                        // Auto-fill icon and color from agent if not customized
                        selectedIcon = newAgent.defaultIcon
                        selectedColor = newAgent.defaultColor
                        if sessionName.isEmpty {
                            sessionName = newAgent.displayName
                        }
                    }
                } header: {
                    Text("Agent")
                } footer: {
                    Text(selectedAgent.description)
                }
                
                // Name input
                Section {
                    TextField("Session Name", text: $sessionName)
                        .autocorrectionDisabled()
                    
                    if showValidationError && sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Session name is required")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("Name")
                }
                
                // Icon picker
                Section {
                    IconPickerGrid(selectedIcon: $selectedIcon, accentColor: Color(hex: selectedColor) ?? .blue)
                } header: {
                    Text("Icon")
                }
                
                // Color picker
                Section {
                    ColorPickerPalette(selectedColor: $selectedColor)
                } header: {
                    Text("Color")
                }
                
                // Preview
                Section {
                    HStack(spacing: 12) {
                        SessionIcon(
                            icon: selectedIcon,
                            color: Color(hex: selectedColor) ?? .blue,
                            size: 48
                        )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sessionName.isEmpty ? "New Session" : sessionName)
                                .font(.body)
                                .fontWeight(.semibold)
                            
                            Text(selectedAgent.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Preview")
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createSession()
                    }
                    .disabled(isCreating)
                }
            }
        }
    }
    
    private func createSession() {
        // Validate
        let trimmedName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            showValidationError = true
            return
        }
        
        isCreating = true
        
        Task {
            await sessionManager.createSession(
                name: trimmedName,
                agent: selectedAgent,
                icon: selectedIcon,
                color: selectedColor
            )
            
            await MainActor.run {
                isCreating = false
                dismiss()
            }
        }
    }
}

// MARK: - Icon Picker Grid

private struct IconPickerGrid: View {
    @Binding var selectedIcon: String
    let accentColor: Color
    
    /// Available icons for session customization (6×4 grid = 24 icons)
    private let icons: [String] = [
        // Row 1: Communication
        "bubble.left.and.bubble.right.fill",
        "message.fill",
        "phone.fill",
        "envelope.fill",
        "paperplane.fill",
        "megaphone.fill",
        
        // Row 2: Work
        "briefcase.fill",
        "doc.text.fill",
        "folder.fill",
        "chart.bar.fill",
        "chart.pie.fill",
        "calendar",
        
        // Row 3: Tools & Tech
        "wrench.and.screwdriver.fill",
        "gear",
        "hammer.fill",
        "paintbrush.fill",
        "cpu.fill",
        "terminal.fill",
        
        // Row 4: Personal & Ideas
        "person.fill",
        "star.fill",
        "lightbulb.fill",
        "target",
        "flag.fill",
        "bookmark.fill"
    ]
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(icons, id: \.self) { icon in
                IconPickerItem(
                    icon: icon,
                    isSelected: icon == selectedIcon,
                    accentColor: accentColor,
                    onTap: {
                        selectedIcon = icon
                    }
                )
            }
        }
        .padding(.vertical, 8)
    }
}

private struct IconPickerItem: View {
    let icon: String
    let isSelected: Bool
    let accentColor: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(isSelected ? accentColor : Color(.systemGray5))
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Color Picker Palette

private struct ColorPickerPalette: View {
    @Binding var selectedColor: String
    
    /// Available colors for session customization
    private let colors: [(name: String, hex: String)] = [
        ("Blue", "#0A84FF"),
        ("Purple", "#5E5CE6"),
        ("Orange", "#FF9F0A"),
        ("Green", "#32D74B"),
        ("Red", "#FF375F"),
        ("Pink", "#BF5AF2"),
        ("Yellow", "#FFD60A"),
        ("Gray", "#8E8E93")
    ]
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(colors, id: \.hex) { colorItem in
                ColorPickerItem(
                    color: Color(hex: colorItem.hex) ?? .gray,
                    isSelected: colorItem.hex == selectedColor,
                    onTap: {
                        selectedColor = colorItem.hex
                    }
                )
                .accessibilityLabel(colorItem.name)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct ColorPickerItem: View {
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 36, height: 36)
                
                if isSelected {
                    Circle()
                        .strokeBorder(.white, lineWidth: 3)
                        .frame(width: 36, height: 36)
                    
                    Circle()
                        .strokeBorder(color, lineWidth: 2)
                        .frame(width: 42, height: 42)
                }
            }
            .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Preview

#Preview {
    CreateSessionSheet(sessionManager: SessionManager(testMode: true))
}
