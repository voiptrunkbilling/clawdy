import SwiftUI
import AppIntents

/// Settings section for managing Siri Shortcuts integration.
struct ShortcutsSettingsSection: View {
    @StateObject private var donationManager = ShortcutsDonationManager.shared
    @State private var showingShortcutsApp = false
    
    var body: some View {
        Section {
            // Available shortcuts
            ForEach(ShortcutsDonationManager.ShortcutType.allCases) { shortcutType in
                ShortcutRow(
                    type: shortcutType,
                    usageCount: donationManager.usageCount(for: shortcutType),
                    isDonated: donationManager.isDonated(shortcutType),
                    onToggle: { enabled in
                        if enabled {
                            donationManager.donateShortcut(shortcutType)
                        } else {
                            donationManager.removeShortcut(shortcutType)
                        }
                    }
                )
            }
            
            // Open Shortcuts app button
            Button {
                openShortcutsApp()
            } label: {
                HStack {
                    Image(systemName: "square.stack.3d.up")
                    Text("Open Shortcuts App")
                }
            }
            
            // Add to Siri button
            NavigationLink {
                SiriPhrasesView()
            } label: {
                HStack {
                    Image(systemName: "waveform")
                    Text("Siri Phrases")
                }
            }
        } header: {
            Text("Siri & Shortcuts")
        } footer: {
            Text("Shortcuts are automatically suggested after using features 3+ times. You can also add them manually in the Shortcuts app.")
        }
    }
    
    /// Open the Shortcuts app
    private func openShortcutsApp() {
        if let url = URL(string: "shortcuts://") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Shortcut Row

/// Row displaying a single shortcut with enable/disable toggle.
private struct ShortcutRow: View {
    let type: ShortcutsDonationManager.ShortcutType
    let usageCount: Int
    let isDonated: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack {
            Image(systemName: type.systemImage)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(type.displayName)
                Text(type.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Show usage count or donated status
            if isDonated {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if usageCount > 0 {
                Text("\(usageCount)/3")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDonated {
                onToggle(true)
            }
        }
        .contextMenu {
            if isDonated {
                Button(role: .destructive) {
                    onToggle(false)
                } label: {
                    Label("Remove from Siri", systemImage: "trash")
                }
            } else {
                Button {
                    onToggle(true)
                } label: {
                    Label("Add to Siri", systemImage: "plus")
                }
            }
        }
    }
}

// MARK: - Siri Phrases View

/// View showing example Siri phrases for each shortcut.
struct SiriPhrasesView: View {
    var body: some View {
        List {
            Section {
                PhrasesGroup(
                    title: "Ask Clawdy",
                    phrases: [
                        "\"Hey Siri, ask Clawdy what's the weather?\"",
                        "\"Hey Siri, ask Clawdy about my schedule\"",
                        "\"Hey Siri, tell Clawdy to set a reminder\""
                    ]
                )
            } header: {
                Text("Text Queries")
            }
            
            Section {
                PhrasesGroup(
                    title: "Voice Chat",
                    phrases: [
                        "\"Hey Siri, start voice chat with Clawdy\"",
                        "\"Hey Siri, talk to Clawdy\"",
                        "\"Hey Siri, open Clawdy voice mode\""
                    ]
                )
            } header: {
                Text("Voice Mode")
            }
            
            Section {
                PhrasesGroup(
                    title: "Manage Context",
                    phrases: [
                        "\"Hey Siri, clear Clawdy context\"",
                        "\"Hey Siri, reset Clawdy conversation\"",
                        "\"Hey Siri, start fresh with Clawdy\""
                    ]
                )
            } header: {
                Text("Session Management")
            }
            
            Section {
                Text("You can also create custom automations in the Shortcuts app that run Clawdy actions automatically based on time, location, or other triggers.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Automations")
            }
        }
        .navigationTitle("Siri Phrases")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Phrases Group

/// Group of example phrases for a shortcut type.
private struct PhrasesGroup: View {
    let title: String
    let phrases: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            
            ForEach(phrases, id: \.self) { phrase in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    
                    Text(phrase.replacingOccurrences(of: "\"", with: ""))
                        .font(.subheadline)
                        .italic()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        Form {
            ShortcutsSettingsSection()
        }
        .navigationTitle("Settings")
    }
}
