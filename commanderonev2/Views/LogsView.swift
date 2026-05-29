import SwiftUI

struct LogsView: View {
    @Bindable var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Import History (sem border nem fundo)
                importHistoryHeader

                if !appState.importHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(appState.importHistory.prefix(50)) { entry in
                            historyRow(entry: entry)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                } else {
                    emptyState
                }
            }
            .padding(.top, 48)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var importHistoryHeader: some View {
        HStack {
            Image(systemName: "list.bullet.rectangle")
                .foregroundStyle(Color.primaryPurple)
                .font(.title2)
            Text("Import History")
                .font(.title2.bold())
                .foregroundColor(.textPrimary)

            Button {
                showResetHistoryAlert()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(IconButtonStyle())

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 64))
                .foregroundStyle(Color.textTertiary)
            Text("No import history yet")
                .font(.title2)
                .foregroundColor(.textSecondary)
            Text("History will appear after your first import")
                .font(.caption)
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .glassPanel()
    }

    @ViewBuilder
    private func historyRow(entry: ImportHistoryEntry) -> some View {
        HStack(spacing: 12) {
            // Date
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.formattedDate)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textPrimary)
            }
            .frame(width: 140, alignment: .leading)

            Divider()
                .frame(height: 30)

            // Source → Destination
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentGreen)
                Text(entry.sourceName)
                    .font(.mono(11))
                    .foregroundColor(.textPrimary)

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)

                Image(systemName: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(Color.primaryPurple)
                Text(entry.destinationName)
                    .font(.mono(11))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            // File count and size
            HStack(spacing: 16) {
                Label("\(entry.fileCount) files", systemImage: "photo.stack")
                    .font(.caption)
                    .foregroundColor(.textSecondary)

                Label(entry.formattedSize, systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(12)
        .glassEffect()
    }

    private func showResetHistoryAlert() {
        let alert = NSAlert()
        alert.messageText = "Clear Import History?"
        alert.informativeText = "This will permanently delete all import history records. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear History")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            ImportHistoryStorage.clear()
            appState.importHistory = []
            appState.log("Import history cleared")
        }
    }
}
