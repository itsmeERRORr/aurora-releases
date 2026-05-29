import SwiftUI

struct ProgressOverlayView: View {
    @Bindable var appState: AppState
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Title
            HStack {
                Image(systemName: stateIcon)
                    .font(.title2)
                    .foregroundStyle(Color.primaryPurple)
                Text(stateTitle)
                    .font(.title2.bold())
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: appState.importProgress.fraction) {
                    HStack {
                        Text("\(appState.importProgress.completedFiles) / \(appState.importProgress.totalFiles) files")
                        Spacer()
                        Text("\(Int(appState.importProgress.fraction * 100))%")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                }
                .tint(progressColor)
            }

            // Details grid
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Label("Current File", systemImage: "doc")
                        .foregroundStyle(Color.textSecondary)
                    Text(appState.importProgress.currentFileName)
                        .font(.mono(13))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                GridRow {
                    Label("Speed", systemImage: "gauge.with.dots.needle.67percent")
                        .foregroundStyle(Color.textSecondary)
                    Text(appState.importProgress.speedFormatted)
                        .font(.mono(13))
                        .foregroundColor(.textPrimary)
                }

                GridRow {
                    Label("Elapsed", systemImage: "clock")
                        .foregroundStyle(Color.textSecondary)
                    Text(appState.importProgress.elapsedFormatted)
                        .font(.mono(13))
                        .foregroundColor(.textPrimary)
                }

                GridRow {
                    Label("Transferred", systemImage: "arrow.down.circle")
                        .foregroundStyle(Color.textSecondary)
                    Text(bytesFormatted)
                        .font(.mono(13))
                        .foregroundColor(.textPrimary)
                }
            }

            Divider()

            // Controls
            HStack {
                Spacer()

                if appState.importState == .importing {
                    Button("Pause") { onPause() }
                        .buttonStyle(SecondaryButtonStyle())
                } else if appState.importState == .paused {
                    Button("Resume") { onResume() }
                        .buttonStyle(PrimaryButtonStyle())
                }

                Button("Cancel") { onCancel() }
                    .buttonStyle(PrimaryButtonStyle(isDestructive: true))
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.glassStrong)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.glassBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
    }

    private var stateIcon: String {
        switch appState.importState {
        case .scanning: return "magnifyingglass"
        case .importing: return "square.and.arrow.down"
        case .paused: return "pause.circle"
        case .verifying: return "checkmark.shield"
        case .done: return "checkmark.circle"
        case .ejecting, .ejectingDone: return "eject.fill"
        case .generatingStats: return "chart.bar.fill"
        default: return "square.and.arrow.down"
        }
    }

    private var stateTitle: String {
        switch appState.importState {
        case .scanning: return "Scanning..."
        case .importing: return "Importing..."
        case .paused: return "Paused"
        case .verifying: return "Verifying..."
        case .done: return "Import Complete"
        case .ejecting: return "Ejecting card..."
        case .ejectingDone: return "Ejecting card... Done"
        case .generatingStats: return "Generating Stats"
        default: return "Importing"
        }
    }

    private var progressColor: Color {
        switch appState.importState {
        case .paused: return .orange
        case .error: return .red
        default: return .accentGreen
        }
    }

    private var bytesFormatted: String {
        let transferred = Double(appState.importProgress.transferredBytes) / (1024 * 1024)
        let total = Double(appState.importProgress.totalBytes) / (1024 * 1024)
        return String(format: "%.0f / %.0f MB", transferred, total)
    }
}
