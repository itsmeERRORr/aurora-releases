import SwiftUI

struct StatusBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 14) {
            // Watcher state indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.7), radius: 6, y: 0)
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }

            Divider()
                .frame(height: 14)
                .background(Color.glassBorder)

            // Last import summary
            if let report = appState.lastImportReport {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentGreen)
                    .font(.caption)
                Text("Last import: \(report.summary)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // File count
            if let vol = appState.activeVolume, vol.rawFileCount > 0 {
                Text("\(vol.rawFileCount) files ready")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Color(hex: "06101F").opacity(0.92))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.importBorder),
            alignment: .top
        )
    }

    private var statusColor: Color {
        switch appState.importState {
        case .idle:
            return appState.activeVolume != nil ? .accentGreen : Color.importCyan
        case .scanning, .verifying:
            return .importAmber
        case .importing:
            return .importBlue
        case .paused:
            return .orange
        case .done:
            return .accentGreen
        case .ejecting, .ejectingDone:
            return .orange
        case .generatingStats:
            return .importPurple
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch appState.importState {
        case .idle:
            if appState.activeVolume != nil {
                return "Card detected — ready"
            }
            return "Waiting for card..."
        case .scanning:
            return "Scanning files..."
        case .importing:
            return "Importing \(appState.importProgress.completedFiles)/\(appState.importProgress.totalFiles)..."
        case .paused:
            return "Import paused"
        case .verifying:
            return "Verifying..."
        case .done:
            return "Import complete"
        case .ejecting:
            return "Ejecting card..."
        case .ejectingDone:
            return "Ejecting card... Done"
        case .generatingStats:
            return "Generating stats..."
        case .error(let msg):
            return "Error: \(msg)"
        }
    }
}
