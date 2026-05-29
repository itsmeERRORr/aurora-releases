import SwiftUI
import AppKit

struct LogsView: View {
    @Bindable var appState: AppState

    @State private var showHistoryReset = false
    @State private var tab: Tab = .history

    enum Tab: Hashable { case history, system }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topbar
                content
            }
            .padding(.horizontal, AuroraSpacing.mainPaddingH)
            .padding(.vertical, AuroraSpacing.mainPaddingV)
        }
        .scrollIndicators(.hidden)
        .alert("Clear import history?", isPresented: $showHistoryReset) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                ImportHistoryStorage.clear()
                appState.importHistory = []
                appState.log("Import history cleared", level: .warning)
            }
        } message: {
            Text("This permanently deletes the import history. The action cannot be undone.")
        }
    }

    private var topbar: some View {
        HStack(spacing: 14) {
            IconChip(systemName: "list.bullet.rectangle", color: .auroraMagenta, size: 36, iconScale: 0.5)
            Text("Logs")
                .font(.auroraTopbarH2)
                .tracking(-0.4)
                .foregroundStyle(Color.auroraTxt)
            Spacer()
            SegmentedToggle(
                options: [(Tab.history, "Import History"), (.system, "System")],
                selection: $tab
            )
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .history: historyPanel
        case .system: systemPanel
        }
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                AuroraPanelHeader(title: "Import History",
                                  actionLabel: appState.importHistory.isEmpty ? nil : "Clear all") {
                    showHistoryReset = true
                }
            }

            if appState.importHistory.isEmpty {
                empty(title: "No import history yet",
                      sub: "History appears once you complete imports.")
            } else {
                VStack(spacing: 4) {
                    ForEach(appState.importHistory.sorted(by: { $0.date > $1.date }).prefix(80)) { entry in
                        historyRow(entry)
                    }
                }
            }
        }
        .auroraStaticCard()
    }

    private func historyRow(_ entry: ImportHistoryEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AuroraFormat.dateMedium(entry.date))
                    .font(.manrope(12, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Text(AuroraFormat.dateShort(entry.date))
                    .font(.manrope(10.5, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
            }
            .frame(width: 130, alignment: .leading)

            Rectangle().fill(Color.auroraStroke).frame(width: 1, height: 28)

            HStack(spacing: 8) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.auroraHealthy)
                Text(entry.sourceName)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.auroraTxt)

                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.auroraFaint)

                Image(systemName: "folder.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.auroraViolet)
                Text(entry.destinationName)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(spacing: 14) {
                stat(icon: "photo.stack", text: "\(AuroraFormat.count(entry.fileCount)) files")
                let parts = AuroraFormat.bytesParts(entry.totalBytes)
                stat(icon: "arrow.down.circle", text: "\(parts.value) \(parts.unit)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private func stat(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.manrope(11, weight: .semibold))
        }
        .foregroundStyle(Color.auroraMuted)
    }

    // MARK: - System

    private var systemPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "System Logs",
                              actionLabel: appState.logEntries.isEmpty ? nil : "Copy") {
                let text = appState.logEntries.map(\.formatted).joined(separator: "\n")
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                appState.log("Logs copied to clipboard")
            }

            if appState.logEntries.isEmpty {
                empty(title: "No logs yet",
                      sub: "Internal events are logged here.")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.logEntries.suffix(200).reversed()) { entry in
                        logRow(entry)
                    }
                }
            }
        }
        .auroraStaticCard()
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.formatted.prefix(10))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.auroraFaint)
                .frame(width: 84, alignment: .leading)
            Image(systemName: iconForLevel(entry.level))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(colorForLevel(entry.level))
                .frame(width: 14)
            Text(entry.message)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.auroraTxt)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func iconForLevel(_ level: LogEntry.Level) -> String {
        switch level {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func colorForLevel(_ level: LogEntry.Level) -> Color {
        switch level {
        case .info: return .auroraViolet
        case .warning: return .auroraGold
        case .error: return .auroraLive
        }
    }

    private func empty(title: String, sub: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            Text(sub)
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}
