import SwiftUI

/// Settings section for managing gateway profiles
struct GatewayProfilesSection: View {
    @ObservedObject var profileManager = GatewayProfileManager.shared
    @State private var showingAddProfile = false
    @State private var editingProfile: GatewayProfile?
    @State private var profileToDelete: GatewayProfile?
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        Section {
            // Profile list
            ForEach(profileManager.profiles) { profile in
                ProfileRow(
                    profile: profile,
                    isActive: profile.id == profileManager.activeProfile?.id,
                    onTap: { handleProfileTap(profile) },
                    onEdit: { editingProfile = profile },
                    onDelete: { confirmDelete(profile) }
                )
            }
            
            // Add profile button
            Button {
                showingAddProfile = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("Add Profile")
                }
            }
        } header: {
            Text("Gateway Profiles")
        } footer: {
            Text("Long-press the connection status indicator for quick profile switching.")
        }
        .sheet(isPresented: $showingAddProfile) {
            ProfileFormView(mode: .add) { newProfile in
                profileManager.addProfile(newProfile)
            }
        }
        .sheet(item: $editingProfile) { profile in
            ProfileFormView(mode: .edit(profile)) { updatedProfile in
                profileManager.updateProfile(updatedProfile)
            }
        }
        .alert("Delete Profile?", isPresented: $showingDeleteConfirmation, presenting: profileToDelete) { profile in
            Button("Delete", role: .destructive) {
                profileManager.deleteProfile(profile)
            }
            Button("Cancel", role: .cancel) {}
        } message: { profile in
            Text("Are you sure you want to delete \"\(profile.name)\"? This will also remove stored credentials for this profile.")
        }
    }
    
    private func handleProfileTap(_ profile: GatewayProfile) {
        guard profile.id != profileManager.activeProfile?.id else { return }
        Task {
            await profileManager.switchToProfile(profile)
        }
    }
    
    private func confirmDelete(_ profile: GatewayProfile) {
        // Don't allow deleting the last profile
        guard profileManager.profiles.count > 1 else { return }
        profileToDelete = profile
        showingDeleteConfirmation = true
    }
}

// MARK: - Profile Row

struct ProfileRow: View {
    let profile: GatewayProfile
    let isActive: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @ObservedObject private var profileManager = GatewayProfileManager.shared
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                // Active indicator
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(profile.name)
                            .fontWeight(isActive ? .semibold : .regular)
                            .foregroundColor(.primary)
                        
                        if profile.isPrimary {
                            Text("Primary")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(profile.shortDisplayString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if profileManager.isSwitching && isActive {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if profileManager.profiles.count > 1 {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            
            if !isActive {
                Button {
                    onTap()
                } label: {
                    Label("Switch to Profile", systemImage: "arrow.right.circle")
                }
            }
            
            if !profile.isPrimary {
                Button {
                    var updated = profile
                    updated.isPrimary = true
                    profileManager.updateProfile(updated)
                } label: {
                    Label("Set as Primary", systemImage: "star")
                }
            }
            
            if profileManager.profiles.count > 1 {
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Profile Form

struct ProfileFormView: View {
    enum Mode {
        case add
        case edit(GatewayProfile)
        
        var title: String {
            switch self {
            case .add: return "New Profile"
            case .edit: return "Edit Profile"
            }
        }
        
        var saveButtonTitle: String {
            switch self {
            case .add: return "Add"
            case .edit: return "Save"
            }
        }
    }
    
    @Environment(\.dismiss) private var dismiss
    
    let mode: Mode
    let onSave: (GatewayProfile) -> Void
    
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var portString: String = ""
    @State private var useTLS: Bool = false
    @State private var isPrimary: Bool = false
    @State private var authToken: String = ""
    @State private var validationError: String?
    
    private var profileId: UUID
    
    init(mode: Mode, onSave: @escaping (GatewayProfile) -> Void) {
        self.mode = mode
        self.onSave = onSave
        
        switch mode {
        case .add:
            self.profileId = UUID()
        case .edit(let profile):
            self.profileId = profile.id
            _name = State(initialValue: profile.name)
            _host = State(initialValue: profile.host)
            _portString = State(initialValue: profile.port != 18789 ? String(profile.port) : "")
            _useTLS = State(initialValue: profile.useTLS)
            _isPrimary = State(initialValue: profile.isPrimary)
            // Load auth token
            if let token = GatewayProfileManager.shared.loadAuthToken(for: profile) {
                _authToken = State(initialValue: token)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Profile Name", text: $name)
                        .autocapitalization(.words)
                } header: {
                    Text("Name")
                } footer: {
                    Text("A friendly name for this profile (e.g., \"Production\", \"Dev Server\")")
                }
                
                Section {
                    TextField("Hostname or IP", text: $host)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: host) { _, _ in validate() }
                    
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("18789", text: $portString)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onChange(of: portString) { _, _ in validate() }
                    }
                    
                    Toggle("Use TLS (wss://)", isOn: $useTLS)
                    
                    if let error = validationError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Gateway host and port. Default port is 18789.")
                }
                
                Section {
                    SecureField("Auth Token (optional)", text: $authToken)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("Optional shared auth token. Device tokens are managed separately per profile.")
                }
                
                Section {
                    Toggle("Set as Primary", isOn: $isPrimary)
                } footer: {
                    Text("The primary profile is used by default when the app starts.")
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.saveButtonTitle) {
                        saveProfile()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
    
    private var port: Int {
        Int(portString) ?? 18789
    }
    
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        validationError == nil
    }
    
    private func validate() {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedHost.isEmpty else {
            validationError = nil
            return
        }
        
        // Validate port
        if !portString.isEmpty {
            if let portNum = Int(portString) {
                if portNum <= 0 || portNum > 65535 {
                    validationError = "Port must be 1-65535"
                    return
                }
            } else {
                validationError = "Invalid port number"
                return
            }
        }
        
        validationError = nil
    }
    
    private func saveProfile() {
        let profile = GatewayProfile(
            id: profileId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            useTLS: useTLS,
            isPrimary: isPrimary
        )
        
        // Save auth token
        if !authToken.isEmpty {
            GatewayProfileManager.shared.saveAuthToken(authToken, for: profile)
        } else {
            GatewayProfileManager.shared.saveAuthToken(nil, for: profile)
        }
        
        onSave(profile)
        dismiss()
    }
}

// MARK: - Quick Switch Picker

/// Action sheet-style picker for quick profile switching (shown on long-press of status indicator)
struct ProfileQuickSwitchSheet: View {
    @ObservedObject var profileManager = GatewayProfileManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(profileManager.profiles) { profile in
                    Button {
                        switchTo(profile)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(profile.name)
                                        .fontWeight(isActive(profile) ? .semibold : .regular)
                                        .foregroundColor(.primary)
                                    
                                    if profile.isPrimary {
                                        Text("Primary")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.2))
                                            .cornerRadius(3)
                                    }
                                }
                                
                                Text(profile.shortDisplayString)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if isActive(profile) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .disabled(profileManager.isSwitching)
                }
            }
            .navigationTitle("Switch Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if profileManager.isSwitching {
                    Color.overlayBackground
                        .ignoresSafeArea()
                    ProgressView("Switching...")
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                }
            }
        }
    }
    
    private func isActive(_ profile: GatewayProfile) -> Bool {
        profile.id == profileManager.activeProfile?.id
    }
    
    private func switchTo(_ profile: GatewayProfile) {
        guard !isActive(profile) else { return }
        Task {
            await profileManager.switchToProfile(profile)
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview("Profile Section") {
    Form {
        GatewayProfilesSection()
    }
}

#Preview("Add Profile") {
    ProfileFormView(mode: .add) { _ in }
}

#Preview("Quick Switch") {
    ProfileQuickSwitchSheet()
}
