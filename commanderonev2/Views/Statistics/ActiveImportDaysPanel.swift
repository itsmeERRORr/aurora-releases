import SwiftUI

struct ActiveImportDaysPanel: View {
    let report: StatsReport?
    let importHistory: [ImportHistoryEntry]
    @Bindable var appState: AppState

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var hoveredMonth: Int?
    @State private var animateBars = false

    /// When a Dashboard filter (tag and/or year) is active, this panel follows it
    /// instead of exposing its own year picker — "2024 Fashion days" should mean
    /// the same 2024 the top filter selected, not a second, independent year toggle.
    private var hasActiveDashboardFilter: Bool {
        appState.dashboardTagFilter != nil || appState.dashboardYearFilter != nil
    }

    /// Tag filtered, but no specific year chosen: there's no single year to lock to,
    /// so this panel aggregates active days across every year that tag has activity in,
    /// instead of guessing/locking to one (which could show an empty "current year").
    private var isAggregatingAllYears: Bool {
        appState.dashboardTagFilter != nil && appState.dashboardYearFilter == nil
    }

    private var effectiveSelectedYear: Int {
        appState.dashboardYearFilter ?? availableYears.first ?? selectedYear
    }

    private func syncSelectedYear() {
        selectedYear = effectiveSelectedYear
    }

    private var yearsPresent: [Int] {
        if let yearFilter = appState.dashboardYearFilter { return [yearFilter] }
        if isAggregatingAllYears {
            let years = Set(captureDayDates.map { calendar.component(.year, from: $0) })
            return years.isEmpty ? [selectedYear] : years.sorted()
        }
        return [selectedYear]
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }

    private var availableYears: [Int] {
        let captureYears = Set(captureDayDates.map { calendar.component(.year, from: $0) })
        let fallbackYears = Set(importHistory.map { calendar.component(.year, from: $0.date) })
        let current = calendar.component(.year, from: Date())
        return Array(captureYears.union(fallbackYears).union([current])).sorted(by: >)
    }

    private var activeDays: Set<Date> {
        let yearsToInclude = Set(yearsPresent)
        let captureDays = Set(captureDayDates.filter { day in
            isAggregatingAllYears || yearsToInclude.contains(calendar.component(.year, from: day))
        })
        if hasCaptureDays { return captureDays }

        return Set<Date>(importHistory.compactMap { entry in
            guard isAggregatingAllYears || yearsToInclude.contains(calendar.component(.year, from: entry.date)) else { return nil }
            return calendar.startOfDay(for: entry.date)
        })
    }

    private var captureDayDates: [Date] {
        guard let report else { return [] }
        return report.captureTimestampsByDay.keys.compactMap(Self.dayKeyFormatter.date(from:))
    }

    private var hasCaptureDays: Bool {
        !captureDayDates.isEmpty
    }

    private var hasAnyActivity: Bool {
        hasCaptureDays || !importHistory.isEmpty
    }

    private func daysInYear(_ year: Int) -> Int {
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let range = calendar.range(of: .day, in: .year, for: start) else { return 365 }
        return range.count
    }

    private var daysInYear: Int {
        yearsPresent.reduce(0) { $0 + daysInYear($1) }
    }

    private var monthEntries: [MonthEntry] {
        (1...12).map { month in
            let count = activeDays.filter { calendar.component(.month, from: $0) == month }.count
            let days = daysInMonth(month)
            return MonthEntry(month: month, activeDays: count, totalDays: days)
        }
    }

    private var weekEntries: [WeekEntry] {
        let weeks = Dictionary(grouping: activeDays) { day in
            calendar.component(.weekOfYear, from: day)
        }
        return weeks.map { week, days in
            WeekEntry(week: week, activeDays: days.count)
        }
        .sorted { $0.week < $1.week }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !hasAnyActivity {
                emptyState
            } else {
                summaryGrid
                monthBars
            }
        }
        .auroraCollapsibleStaticCard(storageKey: "dashboard.activeImportDays", collapsedVisibleHeight: 31)
        .onAppear {
            syncSelectedYear()
            animateBars = true
        }
        .onChange(of: selectedYear) { _, _ in
            animateBars = false
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.9)) {
                animateBars = true
            }
        }
        .onChange(of: appState.dashboardYearFilter) { _, _ in syncSelectedYear() }
        .onChange(of: appState.dashboardTagFilter) { _, _ in syncSelectedYear() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                ActiveDaysHeaderTitle()
                Text(subtitle)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
            }
            Spacer()
            if isAggregatingAllYears {
                EmptyView()
            } else if appState.dashboardYearFilter != nil {
                Text(String(selectedYear))
                    .font(.manrope(11, weight: .heavy))
                    .foregroundStyle(Color.auroraCyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule(style: .continuous).fill(Color.auroraCyan.opacity(0.12)))
            } else {
                ActiveDaysYearPicker(
                    selectedYear: $selectedYear,
                    availableYears: availableYears
                )
            }
        }
    }

    private var subtitle: String {
        let base = hasCaptureDays ? "Days with photos captured, grouped by month" : "Days with at least one import, grouped by month"
        var suffix = ""
        if let tag = appState.dashboardTagFilter { suffix += " · \(tag.rawValue)" }
        if isAggregatingAllYears { suffix += " · all years" }
        return base + suffix
    }

    private var summaryGrid: some View {
        let activeDays = activeDays
        let daysInYear = daysInYear
        let monthEntries = monthEntries
        let weekEntries = weekEntries
        let bestMonth = monthEntries.filter { $0.activeDays > 0 }.max { $0.activeDays < $1.activeDays }
        let bestWeek = weekEntries.filter { $0.activeDays > 0 }.max { $0.activeDays < $1.activeDays }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            metricCard(
                icon: "calendar.badge.clock",
                label: "Days Worked",
                value: AuroraFormat.count(activeDays.count),
                detail: isAggregatingAllYears ? "of \(daysInYear) days across \(yearsPresent.count) yr\(yearsPresent.count == 1 ? "" : "s")" : "of \(daysInYear) days",
                tint: .auroraCyan
            )
            metricCard(
                icon: "percent",
                label: isAggregatingAllYears ? "% of Period" : "% of Year",
                value: percent(activeDays.count, of: daysInYear),
                detail: hasCaptureDays ? "based on capture days" : "based on import days",
                tint: .auroraMagenta
            )
            metricCard(
                icon: "calendar",
                label: "Best Month",
                value: bestMonth.map { monthName($0.month) } ?? "-",
                detail: bestMonth.map { "\($0.activeDays) active day\($0.activeDays == 1 ? "" : "s")" } ?? "No activity",
                tint: .auroraBlue
            )
            metricCard(
                icon: "calendar.day.timeline.left",
                label: "Best Week",
                value: bestWeek.map(weekRangeText) ?? "-",
                detail: bestWeek.map { "\($0.activeDays) active day\($0.activeDays == 1 ? "" : "s")" } ?? "No activity",
                tint: .auroraViolet
            )
        }
    }

    private var monthBars: some View {
        let entries = monthEntries
        let maxDays = max(entries.map(\.activeDays).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 9) {
            Text("MONTHLY ACTIVE DAYS")
                .font(.manrope(10, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Color.auroraFaint)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 12), spacing: 8) {
                ForEach(entries) { entry in
                    monthColumn(entry, maxDays: maxDays)
                }
            }
        }
        .padding(.top, 2)
    }

    private func metricCard(icon: String, label: String, value: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            IconChip(systemName: icon, color: tint, size: 34, iconScale: 0.48)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.manrope(9.5, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(Color.auroraFaint)
                Text(value)
                    .font(.sora(20, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(detail)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .auroraCard(paddingH: 13, paddingV: 13)
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.medium, style: .continuous)
                .strokeBorder(tint.opacity(0.2), lineWidth: 1)
        )
    }

    private func monthColumn(_ entry: MonthEntry, maxDays: Int) -> some View {
        let isHovered = hoveredMonth == entry.month
        let fraction = animateBars ? Double(entry.activeDays) / Double(maxDays) : 0
        return VStack(spacing: 7) {
            GeometryReader { geo in
                let height = max(4, geo.size.height * min(max(fraction, 0), 1))
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.auroraPanel2.opacity(0.6))
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(LinearGradient(colors: [.auroraCyan, .auroraViolet, .auroraMagenta], startPoint: .bottom, endPoint: .top))
                        .frame(height: entry.activeDays > 0 ? height : 0)
                        .shadow(color: Color.auroraCyan.opacity(isHovered ? 0.38 : 0), radius: isHovered ? 8 : 0)
                }
            }
            .frame(height: 74)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )

            Text(shortMonth(entry.month))
                .font(.manrope(10, weight: .heavy))
                .foregroundStyle(isHovered ? Color.auroraTxt : Color.auroraMuted)
            Text("\(entry.activeDays)")
                .font(.sora(11, weight: .bold))
                .foregroundStyle(isHovered ? Color.auroraCyan : Color.auroraFaint)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredMonth = hovering ? entry.month : nil
        }
        .help("\(monthName(entry.month)): \(entry.activeDays) active day\(entry.activeDays == 1 ? "" : "s") (\(percent(entry.activeDays, of: entry.totalDays)))")
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No active days yet")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            Text("Run an EXIF scan/import so Aurora can show active capture days by year and month.")
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func daysInMonth(_ month: Int) -> Int {
        yearsPresent.reduce(0) { total, year in
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let range = calendar.range(of: .day, in: .month, for: date) else { return total + 30 }
            return total + range.count
        }
    }

    private func shortMonth(_ month: Int) -> String {
        Self.shortMonthSymbols[max(0, min(month - 1, 11))]
    }

    private func monthName(_ month: Int) -> String {
        Self.monthSymbols[max(0, min(month - 1, 11))]
    }

    private func weekRangeText(_ entry: WeekEntry) -> String {
        guard let start = calendar.date(from: DateComponents(weekOfYear: entry.week, yearForWeekOfYear: selectedYear)),
              let end = calendar.date(byAdding: .day, value: 6, to: start) else {
            return "Week \(entry.week)"
        }
        if calendar.component(.month, from: start) == calendar.component(.month, from: end) {
            return "\(shortDate(start))-\(calendar.component(.day, from: end))"
        }
        return "\(shortDate(start))-\(shortDate(end))"
    }

    private func shortDate(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
    }

    private func percent(_ value: Int, of total: Int) -> String {
        guard total > 0 else { return "0%" }
        return String(format: "%.1f%%", Double(value) / Double(total) * 100)
    }

    private static let shortMonthSymbols = DateFormatter().shortMonthSymbols ?? []
    private static let monthSymbols = DateFormatter().monthSymbols ?? []
    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

private struct MonthEntry: Identifiable {
    let month: Int
    let activeDays: Int
    let totalDays: Int

    var id: Int { month }
}

private struct WeekEntry: Identifiable {
    let week: Int
    let activeDays: Int

    var id: Int { week }
}

private struct ActiveDaysHeaderTitle: View {
    @Environment(\.auroraToggleCardCollapse) private var toggleCardCollapse

    var body: some View {
        Text("ACTIVE DAYS")
            .font(.auroraSectionLabel)
            .tracking(1.6)
            .foregroundStyle(Color.auroraFaint)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleCardCollapse?()
            }
    }
}

private struct ActiveDaysYearPicker: View {
    @Environment(\.auroraCardIsCollapsed) private var cardIsCollapsed
    @Binding var selectedYear: Int
    let availableYears: [Int]

    var body: some View {
        if !cardIsCollapsed {
            Menu {
                ForEach(availableYears, id: \.self) { year in
                    Button(String(year)) { selectedYear = year }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(String(selectedYear))
                        .font(.manrope(11, weight: .heavy))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Color.auroraCyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule(style: .continuous).fill(Color.auroraCyan.opacity(0.12)))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.auroraCyan.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}
