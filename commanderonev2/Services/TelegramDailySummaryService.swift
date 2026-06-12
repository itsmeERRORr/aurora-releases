import Foundation

enum TelegramDailySummaryService {
    private static let sendHour = 22

    enum SummaryError: LocalizedError {
        case disabledOrIncomplete
        case noImportsToday
        case alreadySent
        case tooEarly
        case invalidURL
        case telegramRejected(String)

        var errorDescription: String? {
            switch self {
            case .disabledOrIncomplete: return "Telegram notifications are disabled or incomplete."
            case .noImportsToday: return "No imports found for today's summary."
            case .alreadySent: return "Today's Telegram summary was already sent."
            case .tooEarly: return "Daily summary is scheduled for 22:00."
            case .invalidURL: return "Telegram Bot Token is invalid."
            case .telegramRejected(let message): return message
            }
        }
    }

    static func sendDailySummaryIfDue(now: Date = Date()) async throws {
        let calendar = Calendar.current
        let summaryDay = dayToSummarize(now: now, calendar: calendar)
        guard !DailyImportSummaryStore.hasSentSummary(for: summaryDay, calendar: calendar) else { throw SummaryError.alreadySent }
        let entries = DailyImportSummaryStore.entries(for: summaryDay, calendar: calendar)
        guard !entries.isEmpty else { throw SummaryError.noImportsToday }

        let settings = TelegramNotificationSettingsStore.load()
        guard settings.isConfigured else { throw SummaryError.disabledOrIncomplete }

        let message = makeMessage(entries: entries, day: summaryDay, calendar: calendar)
        try await sendMessage(message, settings: settings)
        DailyImportSummaryStore.markSummarySent(for: summaryDay, calendar: calendar)
    }

    static func sendTestMessage(settings: TelegramNotificationSettings) async throws {
        guard settings.isConfigured else { throw SummaryError.disabledOrIncomplete }
        let message = [
            "🌌 Aurora Telegram Test",
            "",
            "✅ Bot connection is working.",
            "📸 Daily summaries will be sent here after 22:00 when Aurora imports photos."
        ].joined(separator: "\n")
        try await sendMessage(message, settings: settings)
    }

    private static func dayToSummarize(now: Date, calendar: Calendar) -> Date {
        if calendar.component(.hour, from: now) >= sendHour { return now }
        return calendar.date(byAdding: .day, value: -1, to: now) ?? now
    }

    static func makeMessage(entries: [DailyImportSummaryEntry], day: Date = Date(), calendar: Calendar = .current) -> String {
        let imports = entries.count
        let rawCount = entries.reduce(0) { $0 + $1.rawCount }
        let totalBytes = entries.reduce(Int64(0)) { $0 + $1.totalBytes }
        let events = Set(entries.map(\.eventName).filter { !$0.isEmpty })
        let topEvents = topEventLines(entries)
        let topCameras = topLines(aggregate(entries.map(\.cameraCounts)), formatter: displayCamera)
        let topLenses = topLines(aggregate(entries.map(\.lensCounts)), formatter: displayLens)
        let mostUsedISO = aggregate(entries.map(\.isoCounts)).max { $0.value < $1.value }?.key ?? "—"
        let avgShutter = averageShutter(entries)
        let bytes = AuroraFormat.bytesParts(totalBytes)
        let sessionLabel = imports == 1 ? "session" : "sessions"

        var lines: [String] = [
            "🌌 Aurora Daily Summary — \(AuroraFormat.dateMedium(day))",
            "",
            "📥 Imports: \(imports) \(sessionLabel)",
            "📸 RAWs imported: \(AuroraFormat.count(rawCount))",
            "💾 Data imported: \(bytes.value) \(bytes.unit)",
            "📁 Events touched: \(events.count)",
            ""
        ]

        lines.append("🏆 Top event:")
        lines.append(contentsOf: topEvents.isEmpty ? ["—"] : topEvents)
        lines.append("")

        lines.append("📷 Top cameras:")
        lines.append(contentsOf: topCameras.isEmpty ? ["—"] : topCameras)
        lines.append("")

        lines.append("🔭 Top lenses:")
        lines.append(contentsOf: topLenses.isEmpty ? ["—"] : topLenses)
        lines.append("")

        lines.append("🎚 Most used ISO: \(mostUsedISO)")
        lines.append("⚡ Avg shutter: \(avgShutter)")
        lines.append("✅ Keep rate: —")

        return lines.joined(separator: "\n")
    }

    private static func sendMessage(_ message: String, settings: TelegramNotificationSettings) async throws {
        let token = settings.botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else {
            throw SummaryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "chat_id": settings.chatID.trimmingCharacters(in: .whitespacesAndNewlines),
            "text": message,
            "disable_web_page_preview": true
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode), telegramOK(data) else {
            let details = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
            throw SummaryError.telegramRejected("Telegram rejected the message: \(details)")
        }
    }

    private static func telegramOK(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["ok"] as? Bool == true
    }

    private static func topEventLines(_ entries: [DailyImportSummaryEntry]) -> [String] {
        let grouped = Dictionary(grouping: entries, by: \.eventName)
        return grouped
            .map { name, values in (name: name, count: values.reduce(0) { $0 + $1.rawCount }) }
            .sorted { $0.count > $1.count }
            .prefix(1)
            .map { "\($0.name) — \(AuroraFormat.count($0.count)) RAWs" }
    }

    private static func topLines(_ values: [String: Int], formatter: (String) -> String) -> [String] {
        values
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(2)
            .map { "\(formatter($0.key)) — \(AuroraFormat.count($0.value))" }
    }

    private static func aggregate(_ dictionaries: [[String: Int]]) -> [String: Int] {
        dictionaries.reduce(into: [:]) { result, dict in
            for (key, value) in dict where value > 0 {
                result[key, default: 0] += value
            }
        }
    }

    private static func displayCamera(_ key: String) -> String {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return key }
        return [parts[0], parts[1]].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func displayLens(_ key: String) -> String {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return key }
        return parts[1].isEmpty ? parts[0] : parts[1]
    }

    private static func averageShutter(_ entries: [DailyImportSummaryEntry]) -> String {
        var weightedSum = 0.0
        var total = 0

        for entry in entries {
            for (key, count) in entry.shutterCounts {
                guard let value = Double(key), count > 0 else { continue }
                weightedSum += value * Double(count)
                total += count
            }
        }

        guard total > 0 else { return "—" }
        return AuroraFormat.shutter(weightedSum / Double(total))
    }
}
