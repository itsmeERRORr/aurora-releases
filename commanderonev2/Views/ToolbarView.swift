import SwiftUI

struct ToolbarView: View {
    @Bindable var appState: AppState
    let onImportNow: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onNewEvent: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Auto-Import toggle
            Toggle(isOn: $appState.autoImport) {
                Label("Auto-Import", systemImage: "bolt.fill")
                    .foregroundColor(.textPrimary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(.accentGreen)

            // Auto-Eject toggle
            Toggle(isOn: $appState.autoEject) {
                Label("Auto-Eject", systemImage: "eject.fill")
                    .foregroundColor(.textPrimary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(.accentGreen)

            Divider()
                .frame(height: 20)

            // Copy / Move picker
            Picker("Mode", selection: $appState.importMode) {
                ForEach(ImportMode.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Spacer()

            // Status indicators
            if let vol = appState.activeVolume {
                StatusBadge(text: vol.name, color: .accentGreen)
            }

            Divider()
                .frame(height: 20)

            // Import controls
            switch appState.importState {
            case .idle, .done, .error:
                Button {
                    onNewEvent()
                } label: {
                    Label("New Event", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    onImportNow()
                } label: {
                    Label("Import Now", systemImage: "square.and.arrow.down.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(appState.activeVolume == nil || appState.destinationURL == nil)

            case .scanning:
                ProgressView()
                    .controlSize(.small)
                    .tint(.primaryPurple)
                Text("Scanning...")
                    .foregroundStyle(Color.textSecondary)

            case .importing:
                Button {
                    onPause()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(PrimaryButtonStyle(isDestructive: true))

            case .paused:
                Button {
                    onResume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(PrimaryButtonStyle(isDestructive: true))

            case .verifying:
                ProgressView()
                    .controlSize(.small)
                    .tint(.primaryPurple)
                Text("Verifying...")
                    .foregroundStyle(Color.textSecondary)

            case .ejecting, .ejectingDone:
                Text(appState.importState.label)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)

            case .generatingStats:
                ProgressView()
                    .controlSize(.small)
                    .tint(.primaryPurple)
                Text("Generating Stats...")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
