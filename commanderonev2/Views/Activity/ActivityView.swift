import SwiftUI

struct ActivityView: View {
    @Bindable var appState: AppState

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
    }

    private var topbar: some View {
        HStack(spacing: 14) {
            IconChip(systemName: "waveform.path.ecg", color: .auroraMagenta, size: 36, iconScale: 0.5)
            Text("Activity")
                .font(.auroraTopbarH2)
                .tracking(-0.4)
                .foregroundStyle(Color.auroraTxt)
            Spacer()
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Recent Activity")

            let merged = mergedTimeline()
            if merged.isEmpty {
                emptyState
            } else {
                VStack(spacing: 4) {
                    ForEach(merged) { item in
                        timelineRow(item)
                    }
                }
            }
        }
        .auroraStaticCard()
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Nothing has happened yet")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            Text("Activity from imports and log events appears here.")
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func timelineRow(_ item: TimelineItem) -> some View {
        HStack(spacing: 12) {
            IconChip(systemName: item.icon, color: item.color, size: 28, iconScale: 0.52)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.manrope(13, weight: .semibold))
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(2)
                if let sub = item.subtitle {
                    Text(sub)
                        .font(.manrope(11, weight: .medium))
                        .foregroundStyle(Color.auroraFaint)
                }
            }
            Spacer(minLength: 4)
            Text(AuroraFormat.dateMedium(item.date))
                .font(.manrope(11, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    // MARK: - Timeline

    private struct TimelineItem: Identifiable {
        let id = UUID()
        let date: Date
        let title: String
        let subtitle: String?
        let icon: String
        let color: Color
    }

    private func mergedTimeline() -> [TimelineItem] {
        var items: [TimelineItem] = appState.importHistory.map { entry in
            let bytes = AuroraFormat.bytesParts(entry.totalBytes)
            return TimelineItem(
                date: entry.date,
                title: "Imported \(AuroraFormat.count(entry.fileCount)) photos into \(entry.destinationName)",
                subtitle: "from \(entry.sourceName) · \(bytes.value) \(bytes.unit)",
                icon: "tray.and.arrow.down.fill",
                color: .auroraCyan
            )
        }
        let recentLogs = appState.logEntries.suffix(20).map { entry in
            TimelineItem(
                date: entry.timestamp,
                title: entry.message,
                subtitle: nil,
                icon: iconFor(level: entry.level),
                color: colorFor(level: entry.level)
            )
        }
        items.append(contentsOf: recentLogs)
        items.sort { $0.date > $1.date }
        return Array(items.prefix(40))
    }

    private func iconFor(level: LogEntry.Level) -> String {
        switch level {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func colorFor(level: LogEntry.Level) -> Color {
        switch level {
        case .info: return .auroraViolet
        case .warning: return .auroraGold
        case .error: return .auroraLive
        }
    }

}
