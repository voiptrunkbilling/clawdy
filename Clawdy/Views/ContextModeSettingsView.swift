import SwiftUI

/// Settings view for managing context detection mode.
/// Allows users to manually override the automatic context detection
/// or view the current detection signals.
struct ContextModeSettingsView: View {
    @ObservedObject var contextService: ContextDetectionService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // Current Mode Section
                Section {
                    HStack {
                        Label("Current Mode", systemImage: currentModeIcon)
                        Spacer()
                        Text(contextService.currentContextMode.displayName)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Status")
                }
                
                // Manual Override Section
                Section {
                    Toggle("Manual Override", isOn: manualOverrideBinding)
                    
                    if contextService.manualOverride != nil {
                        Picker("Mode", selection: modePickerBinding) {
                            ForEach(ContextDetectionService.ContextMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("Manual Control")
                } footer: {
                    Text("When enabled, automatic context detection is disabled and the selected mode is always used.")
                }
                
                // Detection Signals Section
                Section {
                    HStack {
                        Label("CarPlay", systemImage: "car.fill")
                        Spacer()
                        StatusIndicator(isActive: contextService.isCarPlayConnected)
                    }
                    
                    HStack {
                        Label("Car Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        StatusIndicator(isActive: contextService.isCarBluetoothConnected)
                    }
                    
                    if let geofence = contextService.activeGeofence {
                        HStack {
                            Label("Geofence", systemImage: "location.fill")
                            Spacer()
                            Text(geofence.name)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            Label("Geofence", systemImage: "location")
                            Spacer()
                            Text("None")
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("Detection Signals")
                } footer: {
                    Text("These signals are used to automatically detect your context. Priority: Manual > CarPlay > Bluetooth > Geofence.")
                }
                
                // Geofence Zones Section
                Section {
                    if contextService.geofenceZones.isEmpty {
                        Text("No geofence zones configured")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(contextService.geofenceZones) { zone in
                            GeofenceZoneRow(zone: zone)
                        }
                        .onDelete(perform: deleteGeofenceZones)
                    }
                } header: {
                    Text("Geofence Zones")
                } footer: {
                    Text("Geofence zones trigger context mode changes when you enter or exit them. Configure zones via the gateway.")
                }
            }
            .navigationTitle("Context Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var currentModeIcon: String {
        switch contextService.currentContextMode {
        case .default:
            return "person.fill"
        case .driving:
            return "car.fill"
        case .home:
            return "house.fill"
        case .office:
            return "building.2.fill"
        }
    }
    
    private var manualOverrideBinding: Binding<Bool> {
        Binding(
            get: { contextService.manualOverride != nil },
            set: { enabled in
                if enabled {
                    contextService.setManualOverride(.default)
                } else {
                    contextService.clearManualOverride()
                }
            }
        )
    }
    
    private var modePickerBinding: Binding<ContextDetectionService.ContextMode> {
        Binding(
            get: { contextService.manualOverride ?? .default },
            set: { contextService.setManualOverride($0) }
        )
    }
    
    // MARK: - Actions
    
    private func deleteGeofenceZones(at offsets: IndexSet) {
        for index in offsets {
            let zone = contextService.geofenceZones[index]
            contextService.removeGeofenceZone(zone)
        }
    }
}

// MARK: - Supporting Views

private struct StatusIndicator: View {
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? Color.green : Color.inactiveIndicator)
                .frame(width: 8, height: 8)
            Text(isActive ? "Connected" : "Not Connected")
                .font(.caption)
                .foregroundStyle(isActive ? .primary : .tertiary)
        }
    }
}

private struct GeofenceZoneRow: View {
    let zone: ContextDetectionService.GeofenceZone
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(zone.name)
                    .font(.body)
                Spacer()
                Text(zone.contextMode.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(modeColor.opacity(0.2))
                    .foregroundStyle(modeColor)
                    .clipShape(Capsule())
            }
            
            Text("Radius: \(Int(zone.radius))m")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var modeColor: Color {
        switch zone.contextMode {
        case .default: return .gray
        case .driving: return .blue
        case .home: return .green
        case .office: return .orange
        }
    }
}

// MARK: - Preview

#Preview {
    ContextModeSettingsView(contextService: ContextDetectionService.shared)
}
