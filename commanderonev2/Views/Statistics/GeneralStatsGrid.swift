import SwiftUI

struct GeneralStatsGrid: View {
    @Bindable var appState: AppState
    let mode: StatsMode

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: AuroraSpacing.gridGap), count: 4),
            spacing: AuroraSpacing.gridGap
        ) {
            GeneralStatCard(
                icon: "arrow.down.circle.fill",
                accent: .auroraCyan,
                strokeStops: [.auroraCyan, .auroraCyanDeep],
                label: "Data Transferred",
                value: data.value, unit: data.unit,
                sparkValues: dataSpark
            )
            GeneralStatCard(
                icon: "bolt.fill",
                accent: .auroraViolet,
                strokeStops: [.auroraViolet, .auroraVioletDeep],
                label: "Avg Speed",
                value: speed.value, unit: speed.unit,
                sparkValues: speedSpark
            )
            GeneralStatCard(
                icon: "clock",
                accent: .auroraMagenta,
                strokeStops: [.auroraMagenta, .auroraMagentaDeep],
                label: "Time Wasted Importing",
                value: time.value, unit: time.unit,
                sparkValues: timeSpark
            )
            GeneralStatCard(
                icon: "arrow.up.circle.fill",
                accent: .auroraBlue,
                strokeStops: [.auroraBlue, .auroraBlueDeep],
                label: "Total Imports",
                value: imports.value, unit: imports.unit,
                sparkValues: importsSpark
            )
        }
    }

    // MARK: - Data

    private var data: (value: String, unit: String) {
        switch mode {
        case .lastImport:
            guard let r = appState.lastImportReport else { return ("—", "") }
            return AuroraFormat.bytesParts(r.totalBytes)
        case .total:
            let bytes = appState.totalStatsReport?.totalBytes
                ?? appState.importHistory.reduce(0) { $0 + $1.totalBytes }
            if bytes == 0 { return ("—", "") }
            return AuroraFormat.bytesParts(bytes)
        }
    }

    private var speed: (value: String, unit: String) {
        switch mode {
        case .lastImport:
            guard let r = appState.lastImportReport else { return ("—", "") }
            return AuroraFormat.speedParts(r.averageSpeed)
        case .total:
            guard let r = appState.totalStatsReport, r.averageSpeed > 0 else { return ("—", "") }
            return AuroraFormat.speedParts(r.averageSpeed)
        }
    }

    private var time: (value: String, unit: String) {
        switch mode {
        case .lastImport:
            guard let r = appState.lastImportReport else { return ("—", "") }
            return AuroraFormat.durationParts(Int(r.duration))
        case .total:
            guard let r = appState.totalStatsReport, r.totalDuration > 0 else { return ("—", "") }
            return AuroraFormat.durationParts(r.totalDuration)
        }
    }

    private var imports: (value: String, unit: String) {
        switch mode {
        case .lastImport:
            return (appState.lastImportReport == nil ? "—" : "1", "")
        case .total:
            let n = appState.importHistory.count
            if n == 0 { return ("—", "") }
            return ("\(n)", "")
        }
    }

    // MARK: - Sparklines from history

    /// History sorted newest → oldest, capped at 10 entries.
    private var historyWindow: [ImportHistoryEntry] {
        Array(appState.importHistory.suffix(10))
    }

    private var dataSpark: [Double] {
        historyWindow.map { Double($0.totalBytes) }
    }

    private var speedSpark: [Double] {
        // No bytes/s in history → approximate with bytes / fileCount as proxy
        historyWindow.map { e in
            let count = max(e.fileCount, 1)
            return Double(e.totalBytes) / Double(count)
        }
    }

    private var timeSpark: [Double] {
        historyWindow.map { Double($0.fileCount) }
    }

    private var importsSpark: [Double] {
        // Imports per day in the last 10 days
        let calendar = Calendar.current
        let now = Date()
        var counts: [Date: Int] = [:]
        for entry in appState.importHistory {
            let day = calendar.startOfDay(for: entry.date)
            counts[day, default: 0] += 1
        }
        let days = (0..<10).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: now))
        }
        return days.map { Double(counts[$0] ?? 0) }
    }
}

// MARK: - Card

struct GeneralStatCard: View {
    let icon: String
    let accent: Color
    let strokeStops: [Color]
    let label: String
    let value: String
    let unit: String
    let sparkValues: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                IconChip(systemName: icon, color: accent)
                Spacer()
            }
            Text(label)
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraMuted)
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(value)
                    .font(.auroraStatValue)
                    .tracking(-0.5)
                    .foregroundStyle(Color.auroraTxt)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.auroraStatUnit)
                        .foregroundStyle(Color.auroraMuted)
                }
            }
            if !sparkValues.isEmpty, sparkValues.max() ?? 0 > 0 {
                Sparkline(values: sparkValues, stroke: strokeStops, fill: accent)
                    .frame(height: 30)
                    .padding(.top, 4)
            } else {
                Spacer().frame(height: 30 + 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .auroraCard()
    }
}
