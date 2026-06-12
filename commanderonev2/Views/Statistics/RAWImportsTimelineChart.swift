import SwiftUI

struct RAWImportsTimelineChart: View {
    @Bindable var appState: AppState

    @State private var period: ImportTimelinePeriod = .day
    @State private var animateBars = false

    var body: some View {
        let entries = ImportTimelineAggregator.entries(
            from: appState.importHistory,
            monthlyStats: appState.photosByMonth,
            period: period
        )
        let peak = entries.max { $0.rawCount < $1.rawCount }
        let totalRAWs = entries.reduce(0) { $0 + $1.rawCount }
        let totalImports = entries.reduce(0) { $0 + $1.importCount }
        let averageRAWs = average(totalRAWs, over: entries.count)
        let averageImports = average(totalImports, over: entries.count)

        VStack(alignment: .leading, spacing: 14) {
            header

            if entries.isEmpty {
                emptyState
            } else {
                HStack(spacing: 10) {
                    timelineSummaryCard(label: "Peak", value: peak.map { AuroraFormat.count($0.rawCount) } ?? "—", subtitle: peak?.label ?? "—", tint: .auroraCyan)
                    timelineSummaryCard(label: "Total RAWs", value: AuroraFormat.count(averageRAWs), subtitle: period.averageRAWSubtitle, tint: .auroraViolet)
                    timelineSummaryCard(label: "Imports", value: AuroraFormat.count(averageImports), subtitle: period.averageImportSubtitle, tint: .auroraMagenta)
                }

                TimelineBars(entries: entries, period: period, animateBars: animateBars)
                    .frame(height: 260)
                    .padding(.top, 2)
            }
        }
        .auroraStaticCard()
        .onAppear { restartAnimation() }
        .onChange(of: period) { _, _ in restartAnimation() }
        .onChange(of: appState.importHistory.count) { _, _ in restartAnimation() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("RAW Imports Timeline")
                    .font(.auroraSectionLabel)
                    .tracking(1.6)
                    .foregroundStyle(Color.auroraFaint)
                Text("Imported RAW files by day, week and month")
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
            }
            Spacer()
            SegmentedToggle(
                options: ImportTimelinePeriod.allCases.map { ($0, $0.label) },
                selection: $period
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No import history yet")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            Text("RAW import trends appear here once imports complete.")
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func timelineSummaryCard(label: String, value: String, subtitle: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            IconChip(systemName: "chart.bar.fill", color: tint, size: 34, iconScale: 0.48)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.manrope(9.5, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color.auroraFaint)
                Text(value)
                    .font(.sora(21, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundStyle(Color.auroraTxt)
                Text(subtitle)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.auroraPanel2.opacity(0.66))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.2), lineWidth: 1)
        )
    }

    private func restartAnimation() {
        animateBars = false
        withAnimation(.timingCurve(0.18, 0.86, 0.22, 1, duration: 0.95)) {
            animateBars = true
        }
    }

    private func average(_ total: Int, over bucketCount: Int) -> Int {
        guard bucketCount > 0 else { return 0 }
        return Int((Double(total) / Double(bucketCount)).rounded())
    }
}

enum ImportTimelinePeriod: String, CaseIterable, Hashable {
    case day
    case week
    case month

    var label: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }

    var averageRAWSubtitle: String {
        switch self {
        case .day: return "Average Daily RAWs"
        case .week: return "Average Weekly RAWs"
        case .month: return "Average Monthly RAWs"
        }
    }

    var averageImportSubtitle: String {
        switch self {
        case .day: return "Average Daily Imports"
        case .week: return "Average Weekly Imports"
        case .month: return "Average Monthly Imports"
        }
    }

    var minBarWidth: CGFloat {
        switch self {
        case .day: return 10
        case .week: return 28
        case .month: return 44
        }
    }
}

struct ImportTimelineEntry: Identifiable, Hashable {
    let id: Date
    let startDate: Date
    let label: String
    let shortLabel: String
    let rawCount: Int
    let importCount: Int
    let totalBytes: Int64
}

enum ImportTimelineAggregator {
    static func entries(
        from history: [ImportHistoryEntry],
        monthlyStats: [(month: String, count: Int)] = [],
        period: ImportTimelinePeriod
    ) -> [ImportTimelineEntry] {
        if period == .month, !monthlyStats.isEmpty {
            return monthlyEntries(from: monthlyStats, importHistory: history)
        }

        guard !history.isEmpty else { return [] }

        var grouped: [Date: (rawCount: Int, importCount: Int, totalBytes: Int64)] = [:]
        var calendar = Calendar.current
        calendar.firstWeekday = 2

        for entry in history {
            let key = bucketStart(for: entry.date, period: period, calendar: calendar)
            let previous = grouped[key] ?? (0, 0, 0)
            grouped[key] = (
                previous.rawCount + entry.fileCount,
                previous.importCount + 1,
                previous.totalBytes + entry.totalBytes
            )
        }

        return grouped
            .map { key, value in
                ImportTimelineEntry(
                    id: key,
                    startDate: key,
                    label: label(for: key, period: period, calendar: calendar),
                    shortLabel: shortLabel(for: key, period: period, calendar: calendar),
                    rawCount: value.rawCount,
                    importCount: value.importCount,
                    totalBytes: value.totalBytes
                )
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private static func monthlyEntries(from monthlyStats: [(month: String, count: Int)], importHistory: [ImportHistoryEntry]) -> [ImportTimelineEntry] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"

        let importCountsByMonth = Dictionary(grouping: importHistory) { entry in
            formatter.string(from: entry.date)
        }.mapValues { $0.count }

        return monthlyStats.compactMap { item in
            guard let date = formatter.date(from: item.month) else { return nil }
            return ImportTimelineEntry(
                id: date,
                startDate: date,
                label: item.month,
                shortLabel: shortLabel(for: date, period: .month, calendar: .current),
                rawCount: item.count,
                importCount: importCountsByMonth[item.month] ?? 0,
                totalBytes: 0
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }

    private static func bucketStart(for date: Date, period: ImportTimelinePeriod, calendar: Calendar) -> Date {
        switch period {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month:
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
        }
    }

    private static func label(for date: Date, period: ImportTimelinePeriod, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        switch period {
        case .day:
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        case .week:
            let end = calendar.date(byAdding: .day, value: 6, to: date) ?? date
            return "\(AuroraFormat.dateShort(date)) — \(AuroraFormat.dateShort(end))"
        case .month:
            formatter.dateFormat = "MMM yyyy"
            return formatter.string(from: date)
        }
    }

    private static func shortLabel(for date: Date, period: ImportTimelinePeriod, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        switch period {
        case .day:
            formatter.dateFormat = "MMM d"
        case .week:
            return shortWeekLabel(for: date, calendar: calendar)
        case .month:
            formatter.dateFormat = "MMM"
        }
        return formatter.string(from: date)
    }

    private static func shortWeekLabel(for date: Date, calendar: Calendar) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: date) ?? date
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "d"
        let startMonth = monthFormatter.string(from: date)
        let endMonth = monthFormatter.string(from: end)
        let startDay = dayFormatter.string(from: date)
        let endDay = dayFormatter.string(from: end)
        if startMonth == endMonth {
            return "\(startMonth) \(startDay)-\(endDay)"
        }
        return "\(startMonth) \(startDay)-\(endMonth) \(endDay)"
    }
}

private struct TimelineBars: View {
    let entries: [ImportTimelineEntry]
    let period: ImportTimelinePeriod
    let animateBars: Bool

    @State private var hoveredID: Date?
    @State private var isHoveringChart = false

    private var maxValue: Int { max(entries.map(\.rawCount).max() ?? 1, 1) }
    private var peakID: Date? { entries.max { $0.rawCount < $1.rawCount }?.id }

    var body: some View {
        GeometryReader { geo in
            let chartHeight = geo.size.height - 42
            let contentWidth = max(geo.size.width, CGFloat(entries.count) * period.minBarWidth)
            ScrollView(.horizontal) {
                ZStack(alignment: .bottomLeading) {
                    grid(width: contentWidth, height: chartHeight)
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(entries) { entry in
                            let activeID = hoveredID ?? (isHoveringChart ? nil : peakID)
                            TimelineBar(
                                entry: entry,
                                fraction: animateBars ? CGFloat(entry.rawCount) / CGFloat(maxValue) : 0,
                                isHighlighted: entry.id == activeID,
                                period: period,
                                chartHeight: chartHeight
                            )
                            .frame(width: barWidth(totalWidth: contentWidth))
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                guard hovering else { return }
                                withAnimation(.easeOut(duration: 0.12)) {
                                    hoveredID = entry.id
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(width: contentWidth, height: geo.size.height, alignment: .bottomLeading)
                }
                .frame(width: contentWidth, height: geo.size.height)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHoveringChart = hovering
                        if !hovering { hoveredID = nil }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func barWidth(totalWidth: CGFloat) -> CGFloat {
        let totalSpacing = CGFloat(max(entries.count - 1, 0)) * 6 + 12
        return max(period.minBarWidth, (totalWidth - totalSpacing) / CGFloat(max(entries.count, 1)))
    }

    private func grid(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<4) { index in
                Rectangle()
                    .fill(index == 3 ? Color.auroraStroke.opacity(0.7) : Color.auroraStroke.opacity(0.28))
                    .frame(height: 1)
                if index < 3 { Spacer() }
            }
        }
        .frame(width: width, height: height)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
    }
}

private struct TimelineBar: View {
    let entry: ImportTimelineEntry
    let fraction: CGFloat
    let isHighlighted: Bool
    let period: ImportTimelinePeriod
    let chartHeight: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            if isHighlighted {
                Text(AuroraFormat.count(entry.rawCount))
                    .font(.sora(10.5, weight: .heavy))
                    .foregroundStyle(Color.auroraCyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(height: 14)
            } else {
                Spacer().frame(height: 14)
            }

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.auroraPanel2.opacity(0.55))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(barGradient)
                    .frame(height: max(6, chartHeight * min(max(fraction, 0), 1)))
                    .shadow(color: barTint.opacity(isHighlighted ? 0.55 : 0.24), radius: isHighlighted ? 12 : 5, x: 0, y: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: chartHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )

            Text(label)
                .font(.manrope(10, weight: .bold))
                .foregroundStyle(isHighlighted ? Color.auroraTxt : Color.auroraFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(height: 18)
        }
        .help("\(entry.label): \(AuroraFormat.count(entry.rawCount)) RAWs across \(entry.importCount) imports")
    }

    private var label: String {
        switch period {
        case .day:
            return isHighlighted ? entry.shortLabel : ""
        case .week, .month:
            return entry.shortLabel
        }
    }

    private var barTint: Color {
        isHighlighted ? .auroraCyan : .auroraViolet
    }

    private var barGradient: LinearGradient {
        LinearGradient(
            colors: isHighlighted
                ? [Color.auroraCyan, Color.auroraBlue]
                : [Color.auroraViolet.opacity(0.92), Color.auroraMagenta.opacity(0.8)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
