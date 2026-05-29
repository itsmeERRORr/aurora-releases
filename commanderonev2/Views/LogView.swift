import SwiftUI

struct LogView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(Color.accentGreen)
                Text("Logs")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button {
                    copyLogs()
                } label: {
                    Label("Copy Logs", systemImage: "doc.on.doc")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    appState.logEntries.removeAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.bgMedium)

            Divider()

            if appState.logEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.page")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.textTertiary)
                    Text("No log entries")
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgDark)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(appState.logEntries) { entry in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: iconForLevel(entry.level))
                                        .foregroundStyle(colorForLevel(entry.level))
                                        .font(.caption)
                                        .frame(width: 14)
                                    Text(entry.formatted)
                                        .font(.mono(11))
                                        .foregroundColor(.textPrimary)
                                        .textSelection(.enabled)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 2)
                                .id(entry.id)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .background(Color.bgDark)
                    .onChange(of: appState.logEntries.count) { _, _ in
                        if let last = appState.logEntries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func copyLogs() {
        let text = appState.logEntries.map(\.formatted).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func iconForLevel(_ level: LogEntry.Level) -> String {
        switch level {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private func colorForLevel(_ level: LogEntry.Level) -> Color {
        switch level {
        case .info: return .primaryPurple
        case .warning: return .orange
        case .error: return .red
        }
    }
}
