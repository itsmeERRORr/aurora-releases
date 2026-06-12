import Foundation

enum DailyImportSummaryStore {
    private static let entriesKey = "telegramDailySummaryEntries"
    private static let sentDaysKey = "telegramDailySummarySentDays"
    private static let retentionDays = 90

    static func add(_ entry: DailyImportSummaryEntry) {
        var entries = loadEntries()
        entries.insert(entry, at: 0)
        saveEntries(trim(entries))
    }

    static func entries(for day: Date, calendar: Calendar = .current) -> [DailyImportSummaryEntry] {
        loadEntries().filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    static func hasSentSummary(for day: Date, calendar: Calendar = .current) -> Bool {
        sentDayKeys().contains(dayKey(for: day, calendar: calendar))
    }

    static func markSummarySent(for day: Date, calendar: Calendar = .current) {
        var keys = sentDayKeys()
        keys.insert(dayKey(for: day, calendar: calendar))
        UserDefaults.standard.set(Array(keys).sorted(), forKey: sentDaysKey)
    }

    private static func loadEntries() -> [DailyImportSummaryEntry] {
        guard let data = UserDefaults.standard.data(forKey: entriesKey),
              let entries = try? JSONDecoder().decode([DailyImportSummaryEntry].self, from: data) else {
            return []
        }
        return trim(entries)
    }

    private static func saveEntries(_ entries: [DailyImportSummaryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: entriesKey)
    }

    private static func trim(_ entries: [DailyImportSummaryEntry]) -> [DailyImportSummaryEntry] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else { return entries }
        return entries.filter { $0.date >= cutoff }
    }

    private static func sentDayKeys() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: sentDaysKey) ?? [])
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
