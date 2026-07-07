import SwiftUI

struct GeneralStatsGrid: View {
    @Bindable var appState: AppState
    let mode: StatsMode

    // `body`/the computed properties below never call `appState.dashboardStatsReport`
    // directly — SwiftUI evaluates `body` synchronously on mount, before any `.task`
    // has a chance to run, so reading the (potentially expensive, on a cache miss)
    // property straight from a computed property re-created the exact hang a shared
    // cache + prewarm was supposed to fix (see the comment in TopEventsPanel.swift
    // for the full explanation). This starts `nil` and pops in once populated.
    @State private var cachedTotalReport: StatsReport?

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
                secondaryStats: dataSecondaryStats,
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
                secondaryStats: timeSecondaryStats,
                sparkValues: timeSpark
            )

            GeneralStatCard(
                icon: "arrow.up.circle.fill",
                accent: .auroraBlue,
                strokeStops: [.auroraBlue, .auroraBlueDeep],
                label: "Total Imports",
                value: imports.value, unit: imports.unit,
                secondaryStats: importsSecondaryStats,
                sparkValues: importsSpark
            )
        }
        .task(id: appState.eventStatsCacheRevision) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await refreshTotalReport()
        }
        .task(id: "\(appState.dashboardTagFilter?.rawValue ?? "-")|\(appState.dashboardYearFilter.map(String.init) ?? "-")") {
            await refreshTotalReport()
        }
    }

    private func refreshTotalReport() async {
        guard mode == .total else { return }
        await appState.prewarmStatsReport(forTag: appState.dashboardTagFilter, year: appState.dashboardYearFilter)
        cachedTotalReport = appState.statsReport(forTag: appState.dashboardTagFilter, year: appState.dashboardYearFilter)
    }

    // MARK: - Data

    private var data: (value: String, unit: String) {
        switch mode {
        case .lastImport:
            guard let r = appState.lastImportReport else { return ("—", "") }
            return AuroraFormat.bytesParts(r.totalBytes)
        case .total:
            let bytes = cachedTotalReport?.totalBytes
                ?? appState.filteredImportHistory.reduce(0) { $0 + $1.totalBytes }
            if bytes == 0 { return ("—", "") }
            return AuroraFormat.bytesParts(bytes)
        }
    }

    private var dataSecondaryStats: [(label: String, value: String)] {
        switch mode {
        case .lastImport:
            guard let report = appState.lastImportReport else { return [] }
            let parts = AuroraFormat.bytesParts(report.totalBytes)
            return [
                (label: "Avg / Import", value: "\(parts.value) \(parts.unit)"),
                (label: "Avg / Day", value: "\(parts.value) \(parts.unit)")
            ]
        case .total:
            let history = appState.filteredImportHistory
            guard !history.isEmpty else { return [] }

            let totalBytes = cachedTotalReport?.totalBytes
                ?? history.reduce(Int64(0)) { $0 + $1.totalBytes }
            guard totalBytes > 0 else { return [] }

            let avgImport = AuroraFormat.bytesParts(totalBytes / Int64(max(history.count, 1)))
            let days = Set(history.map { Calendar.current.startOfDay(for: $0.date) })
            let avgDay = AuroraFormat.bytesParts(totalBytes / Int64(max(days.count, 1)))

            return [
                (label: "Avg / Import", value: "\(avgImport.value) \(avgImport.unit)"),
                (label: "Avg / Day", value: "\(avgDay.value) \(avgDay.unit)")
            ]
        }
    }

    private var speed: (value: String, unit: String) {
        switch mode {
        case .lastImport:
            guard let r = appState.lastImportReport else { return ("—", "") }
            return AuroraFormat.speedParts(r.averageSpeed)
        case .total:
            guard let r = cachedTotalReport, r.averageSpeed > 0 else { return ("—", "") }
            return AuroraFormat.speedParts(r.averageSpeed)
        }
    }

    private var time: (value: String, unit: String) {
        switch mode {
        case .lastImport:
            guard let r = appState.lastImportReport else { return ("—", "") }
            return AuroraFormat.durationParts(Int(r.duration))
        case .total:
            guard let r = cachedTotalReport, r.totalDuration > 0 else { return ("—", "") }
            return AuroraFormat.durationParts(r.totalDuration)
        }
    }

    private var timeSecondaryStats: [(label: String, value: String)] {
        switch mode {
        case .lastImport:
            guard let report = appState.lastImportReport else { return [] }
            let parts = AuroraFormat.durationParts(Int(report.duration))
            return [(label: "Avg / Import", value: "\(parts.value) \(parts.unit)")]
        case .total:
            guard let report = cachedTotalReport,
                  report.totalDuration > 0,
                  !appState.filteredImportHistory.isEmpty else { return [] }
            let parts = AuroraFormat.durationParts(report.totalDuration / max(appState.filteredImportHistory.count, 1))
            return [(label: "Avg / Import", value: "\(parts.value) \(parts.unit)")]
        }
    }

    private var imports: (value: String, unit: String) {
        switch mode {
        case .lastImport:
            return (appState.lastImportReport == nil ? "—" : "1", "")
        case .total:
            let n = appState.filteredImportHistory.count
            if n == 0 { return ("—", "") }
            return ("\(n)", "")
        }
    }

    private var importsSecondaryStats: [(label: String, value: String)] {
        switch mode {
        case .lastImport:
            return appState.lastImportReport == nil ? [] : [(label: "Avg / Day", value: "1")]
        case .total:
            let history = appState.filteredImportHistory
            guard !history.isEmpty else { return [] }
            let days = Set(history.map { Calendar.current.startOfDay(for: $0.date) })
            let avg = Double(history.count) / Double(max(days.count, 1))
            let value = avg >= 10 ? String(format: "%.0f", avg) : String(format: "%.1f", avg)
            return [(label: "Avg / Day", value: value)]
        }
    }

    // MARK: - Sparklines from history

    /// History sorted newest → oldest, capped at 10 entries.
    private var historyWindow: [ImportHistoryEntry] {
        Array(appState.filteredImportHistory.suffix(10))
    }

    private var dataSpark: [Double] {
        guard mode == .total else { return [] }
        return historyWindow.map { Double($0.totalBytes) }
    }

    private var speedSpark: [Double] {
        guard mode == .total else { return [] }
        // No bytes/s in history → approximate with bytes / fileCount as proxy
        return historyWindow.map { e in
            let count = max(e.fileCount, 1)
            return Double(e.totalBytes) / Double(count)
        }
    }

    private var timeSpark: [Double] {
        guard mode == .total else { return [] }
        return historyWindow.map { Double($0.fileCount) }
    }

    private var importsSpark: [Double] {
        guard mode == .total else { return [] }
        // Imports per day in the last 10 days
        let calendar = Calendar.current
        let now = Date()
        var counts: [Date: Int] = [:]
        for entry in appState.filteredImportHistory {
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
    var secondaryStats: [(label: String, value: String)] = []
    let sparkValues: [Double]

    @State private var updatePulse = false

    var body: some View {
        let updateKey = ([value, unit] + secondaryStats.flatMap { [$0.label, $0.value] }).joined(separator: "|")

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
            .contentTransition(.numericText())
            HStack(spacing: 10) {
                ForEach(secondaryStats, id: \.label) { stat in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stat.value)
                            .font(.sora(11.5, weight: .bold))
                            .foregroundStyle(Color.auroraTxt)
                            .lineLimit(1)
                        Text(stat.label)
                            .font(.manrope(9.5, weight: .semibold))
                            .foregroundStyle(Color.auroraFaint)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 30, alignment: .topLeading)
            .opacity(secondaryStats.isEmpty ? 0 : 1)
            if !sparkValues.isEmpty, sparkValues.max() ?? 0 > 0 {
                Sparkline(values: sparkValues, stroke: strokeStops, fill: accent)
                    .frame(height: 30)
                    .padding(.top, 4)
            } else {
                Spacer().frame(height: 30 + 4)
            }
        }
        .scaleEffect(updatePulse ? 1.01 : 1.0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 200, alignment: .topLeading)
        .auroraCard()
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.medium, style: .continuous)
                .strokeBorder(updatePulse ? accent.opacity(0.7) : accent.opacity(0.22), lineWidth: updatePulse ? 1.4 : 1)
        )
        .shadow(color: updatePulse ? accent.opacity(0.24) : .clear, radius: updatePulse ? 16 : 0, x: 0, y: 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: updatePulse)
        .animation(.easeInOut(duration: 0.22), value: updateKey)
        .onChange(of: updateKey) { _, _ in
            pulseUpdate()
        }
    }

    private func pulseUpdate() {
        updatePulse = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            updatePulse = false
        }
    }
}
