import Foundation
import SwiftUI

enum ImportState: Equatable {
    case idle
    case scanning
    case importing
    case paused
    case verifying
    case done
    case ejecting
    case ejectingDone
    case generatingStats
    case error(String)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .scanning: return "Scanning"
        case .importing: return "Importing"
        case .paused: return "Paused"
        case .verifying: return "Verifying"
        case .done: return "Import Complete"
        case .ejecting: return "Ejecting card..."
        case .ejectingDone: return "Ejecting card... Done"
        case .generatingStats: return "Generating Stats"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

struct VolumeInfo: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let path: URL
    var rawFileCount: Int = 0
    var isActive: Bool = false
}

@MainActor
@Observable
final class AppState {
    // MARK: - Volumes
    var mountedVolumes: [VolumeInfo] = []
    var activeVolume: VolumeInfo?
    var sortedSourceFiles: [URL] = []
    var isSortingSourceFiles = false
    var captureDateCache: [URL: Date] = [:]
    var photoRatings: [URL: Int] = [:]

    // MARK: - Destination
    var destinationURL: URL?
    var destinationBookmarkData: Data? {
        didSet {
            if let data = destinationBookmarkData {
                UserDefaults.standard.set(data, forKey: "destinationBookmark")
            }
        }
    }

    // MARK: - Toggles
    var autoImport: Bool = false {
        didSet { UserDefaults.standard.set(autoImport, forKey: "autoImport") }
    }
    var autoEject: Bool = true {
        didSet { UserDefaults.standard.set(autoEject, forKey: "autoEject") }
    }
    var importMode: ImportMode = .move {
        didSet { UserDefaults.standard.set(importMode.rawValue, forKey: "importMode") }
    }

    // MARK: - Import State
    var importState: ImportState = .idle
    var importProgress: ImportProgress = ImportProgress()
    var lastImportReport: ImportReport?

    // MARK: - Stats
    var statsReport: StatsReport? {
        didSet {
            if let stats = statsReport {
                StatsStorage.saveLastImport(stats)
            }
        }
    }
    var totalStatsReport: StatsReport? {
        didSet {
            if let stats = totalStatsReport {
                print("AppState: totalStatsReport updated with \(stats.totalFilesAnalyzed) files, saving...")
                StatsStorage.save(stats)
                // Force immediate persistence
                UserDefaults.standard.synchronize()
                print("AppState: Forced UserDefaults sync")
            } else {
                print("AppState: totalStatsReport set to nil")
                StatsStorage.clear()
            }
        }
    }

    // MARK: - Finalized Events

    /// Snapshots for events the user has marked as finalized.
    /// Persisted via `FinalizedEventsStore`. Source of truth for finalized events
    /// across the app (Top Events, Hero Card, sidebar row totals).
    var finalizedEvents: [FinalizedEvent] = [] {
        didSet { FinalizedEventsStore.saveAll(finalizedEvents) }
    }

    /// Per-bookmark link to a finalized snapshot. Same count as `eventFolderBookmarks`.
    /// `nil` = active event (live counts), non-nil = finalized (snapshot is source of truth).
    var eventFolderFinalizedEventID: [UUID?] = [] {
        didSet { saveFinalizedEventIDs() }
    }

    // MARK: - Import History
    var importHistory: [ImportHistoryEntry] = []

    /// All configured event folders, shown in the Events sidebar.
    /// Same set as "Most Photos per event" in Statistics — all bookmarked folders, regardless of
    /// whether they have import history. Sorted by most recent import date (folders without any
    /// import history appear last, sorted by index).
    var uniqueImportDestinations: [(path: String, name: String)] {
        var result: [(path: String, name: String, lastDate: Date, index: Int)] = []

        for index in eventFolderBookmarks.indices {
            let folderPath = index < eventFolderCachedPaths.count ? eventFolderCachedPaths[index] : ""

            // Build display name: custom > last path component > placeholder
            let customName = index < eventFolderDisplayNames.count ? eventFolderDisplayNames[index] : ""
            let folderName: String
            if !folderPath.isEmpty {
                folderName = URL(fileURLWithPath: folderPath).lastPathComponent
            } else {
                folderName = customName.isEmpty ? "Event \(index + 1)" : customName
            }
            let name = customName.isEmpty ? folderName : customName

            // Sort by most recent import (normalise trailing slashes to avoid mismatches)
            let lastDate: Date
            if !folderPath.isEmpty {
                let norm = folderPath.hasSuffix("/") ? String(folderPath.dropLast()) : folderPath
                let latest = importHistory
                    .filter { e in
                        let d = e.destinationPath.hasSuffix("/")
                            ? String(e.destinationPath.dropLast())
                            : e.destinationPath
                        return d == norm || d.hasPrefix(norm + "/")
                    }
                    .map(\.date).max()
                lastDate = latest ?? Date.distantPast
            } else {
                lastDate = Date.distantPast
            }

            result.append((path: folderPath, name: name, lastDate: lastDate, index: index))
        }

        // Most recently imported first; tie-break by original index
        return result
            .sorted { lhs, rhs in
                lhs.lastDate != rhs.lastDate ? lhs.lastDate > rhs.lastDate : lhs.index < rhs.index
            }
            .map { (path: $0.path, name: $0.name) }
    }

    var photosByMonth: [(month: String, count: Int)] {
        // Use the total stats report which contains photo capture dates from metadata
        guard let report = totalStatsReport else {
            #if DEBUG
            print("AppState.photosByMonth: No totalStatsReport available")
            #endif
            return []
        }

        #if DEBUG
        print("AppState.photosByMonth: report.monthCounts has \(report.monthCounts.count) entries")
        print("AppState.photosByMonth: monthCounts = \(report.monthCounts)")
        #endif

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM yyyy"

        // Parse all month strings to dates for proper sorting
        var monthDates: [String: Date] = [:]
        for monthKey in report.monthCounts.keys {
            if let date = dateFormatter.date(from: monthKey) {
                monthDates[monthKey] = date
            }
        }

        // Sort by date (newest to oldest) and take last 12 months
        let sorted = report.monthCounts
            .compactMap { month, count -> (month: String, count: Int, date: Date)? in
                guard let date = monthDates[month] else { return nil }
                return (month: month, count: count, date: date)
            }
            .sorted { $0.date > $1.date } // newest first
            .prefix(12) // last 12 months
            .map { (month: $0.month, count: $0.count) }

        #if DEBUG
        print("AppState.photosByMonth: returning \(sorted.count) months")
        #endif

        return sorted
    }

    /// Current week by day (Mon–Sun / Seg–Dom). Uses import history; always returns 7 points.
    var photosByWeek: [(label: String, count: Int)] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday = first day of week
        let now = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else {
            return emptyWeekdayLabels(calendar: calendar)
        }
        // Fim da semana = início da semana seguinte (exclusive), para incluir todo o Domingo
        guard let weekEndExclusive = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return emptyWeekdayLabels(calendar: calendar)
        }

        var dayCounts: [Int: Int] = [:] // 0=Mon … 6=Sun
        for entry in importHistory {
            let d = entry.date
            if d >= weekStart && d < weekEndExclusive {
                let weekday = calendar.component(.weekday, from: d) // 1=Sun, 2=Mon, …, 7=Sat
                let index = weekday == 1 ? 6 : weekday - 2
                dayCounts[index, default: 0] += entry.fileCount
            }
        }

        let symbols = calendar.shortWeekdaySymbols // [Sun, Mon, Tue, …] — locale-aware
        let order = [1, 2, 3, 4, 5, 6, 0] // Mon, Tue, …, Sun indices
        return (0..<7).map { i in
            let label = symbols[order[i]]
            let count = dayCounts[i] ?? 0
            return (label: label, count: count)
        }
    }

    private func emptyWeekdayLabels(calendar: Calendar) -> [(label: String, count: Int)] {
        let symbols = calendar.shortWeekdaySymbols
        let order = [1, 2, 3, 4, 5, 6, 0]
        return order.map { (label: symbols[$0], count: 0) }
    }

    /// All years that have photo data, sorted descending (most recent first).
    /// Derived from totalStatsReport.monthCounts keys ("MMM yyyy") + current year always included.
    var availableYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        var years: Set<Int> = [currentYear]
        if let report = totalStatsReport {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM yyyy"
            for key in report.monthCounts.keys {
                if let date = formatter.date(from: key) {
                    years.insert(Calendar.current.component(.year, from: date))
                }
            }
        }
        return years.sorted().reversed()
    }

    /// Months Jan–Dec for a specific year.
    /// Uses totalStatsReport.monthCounts (EXIF-based, unlimited accumulation).
    /// Falls back to importHistory when no stats are available.
    func photosByYear(_ year: Int) -> [(label: String, count: Int)] {
        let calendar = Calendar.current
        let symbols = calendar.shortMonthSymbols // Jan, Feb, … — locale-aware
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM yyyy"

        // Primary: EXIF-accumulated monthCounts — keys are "MMM yyyy" (e.g. "Feb 2026")
        if let report = totalStatsReport, !report.monthCounts.isEmpty {
            return (1...12).map { month in
                var comps = DateComponents()
                comps.year = year
                comps.month = month
                comps.day = 1
                let key = calendar.date(from: comps).map { dateFormatter.string(from: $0) } ?? ""
                return (label: symbols[month - 1], count: report.monthCounts[key] ?? 0)
            }
        }

        // Fallback: importHistory (first-launch / no stats yet)
        var monthlyCounts: [Int: Int] = [:]
        for entry in importHistory {
            if calendar.component(.year, from: entry.date) == year {
                let month = calendar.component(.month, from: entry.date)
                monthlyCounts[month, default: 0] += entry.fileCount
            }
        }
        return (1...12).map { month in
            (label: symbols[month - 1], count: monthlyCounts[month] ?? 0)
        }
    }

    /// Convenience: current year (for backward compat).
    var photosByYear: [(label: String, count: Int)] {
        photosByYear(Calendar.current.component(.year, from: Date()))
    }

    /// Current month by day (1…last day). Uses import history.
    var photosByMonthChart: [(label: String, count: Int)] {
        let calendar = Calendar.current
        let now = Date()
        guard let range = calendar.range(of: .day, in: .month, for: now),
              let _ = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return []
        }
        let lastDay = range.count

        var dayCounts: [Int: Int] = [:]
        for entry in importHistory {
            let d = entry.date
            if calendar.isDate(d, equalTo: now, toGranularity: .month) {
                let day = calendar.component(.day, from: d)
                dayCounts[day, default: 0] += entry.fileCount
            }
        }

        return (1...lastDay).map { day in
            (label: "\(day)", count: dayCounts[day] ?? 0)
        }
    }

    // MARK: - Logs
    var logEntries: [LogEntry] = []

    // MARK: - Event folders (RAW count per folder)
    /// Indices of event folders currently being EXIF-scanned in the background.
    /// StatisticsView observes this to show a "Scanning…" indicator on the card.
    var eventFolderScanningIndices: Set<Int> = []

    /// Live results for the "Most photos per event" card.
    /// Stored in AppState so that navigating away and back never triggers a re-scan.
    struct EventFolderResult {
        var name: String
        var count: Int
        var offline: Bool
    }
    var eventFolderResults: [Int: EventFolderResult] = [:]
    /// True while a background rescan is in progress.
    var isRefreshingEventFolders = false

    /// Bookmark data for "event" folders; RAW count is computed when displayed.
    var eventFolderBookmarks: [Data] = [] {
        didSet { syncDisplayNamesCount(); syncPeakCounts(); syncCachedCounts(); syncFinalizedEventIDs(); saveEventFolderBookmarks() }
    }
    /// Custom display names per folder; same count as eventFolderBookmarks. Empty string = use folder name.
    var eventFolderDisplayNames: [String] = [] {
        didSet { saveEventFolderDisplayNames() }
    }
    /// Peak (maximum) RAW count per folder; only ever increases, so deleting files doesn't reduce the displayed total.
    var eventFolderPeakRawCounts: [Int] = [] {
        didSet { saveEventFolderPeakRawCounts() }
    }
    /// Last known RAW count per folder — shown when disk is offline.
    var eventFolderCachedCounts: [Int] = [] {
        didSet { saveCachedCounts() }
    }
    /// Resolved folder paths (last known) — used to detect if destination overlaps with an event folder.
    var eventFolderCachedPaths: [String] = [] {
        didSet { saveCachedPaths() }
    }

    // MARK: - Configuration
    /// RAW extensions: Sony ARW, Canon CR2/CR3, Adobe/Leica/Ricoh DNG
    var supportedExtensions: Set<String> = ["arw", "cr2", "cr3", "dng"]

    // MARK: - Selected Tab (removed - now using NavigationItem in sidebar)

    // MARK: - Init
    init() {
        autoImport = UserDefaults.standard.bool(forKey: "autoImport")
        autoEject = UserDefaults.standard.object(forKey: "autoEject") as? Bool ?? true
        if let raw = UserDefaults.standard.string(forKey: "importMode"),
           let mode = ImportMode(rawValue: raw) {
            importMode = mode
        }
        if let data = UserDefaults.standard.data(forKey: "destinationBookmark") {
            destinationBookmarkData = data
            destinationURL = BookmarkManager.resolveBookmark(data)
        }

        // Load stats from storage
        print("AppState.init: Loading stats from storage...")
        statsReport = StatsStorage.loadLastImport()
        totalStatsReport = StatsStorage.load()
        print("AppState.init: Loaded totalStatsReport with \(totalStatsReport?.totalFilesAnalyzed ?? 0) files")

        // One-time repair: zero min values were written by old no-lens shots (FNumber=0,
        // FocalLength=0). Convert them to nil so they don't show as "f/0.0" / "0mm".
        // Future imports use the > 0 guard in StatsRunner so they populate correctly.
        if var report = totalStatsReport {
            var repaired = false
            if report.minAperture == 0 { report.minAperture = nil; repaired = true }
            if report.minFocalLength == 0 { report.minFocalLength = nil; repaired = true }
            if repaired {
                totalStatsReport = report
                StatsStorage.save(report)
                print("AppState.init: Repaired corrupted zero min values in totalStatsReport")
            }
        }

        // Load import history from storage
        importHistory = ImportHistoryStorage.load()

        // Load event folder display names FIRST (antes dos bookmarks)
        if let data = UserDefaults.standard.data(forKey: "eventFolderDisplayNamesData"),
           let decoded = try? PropertyListDecoder().decode([String].self, from: data) {
            eventFolderDisplayNames = decoded
        }
        // Load event folder peak counts (antes dos bookmarks)
        if let data = UserDefaults.standard.data(forKey: "eventFolderPeakRawCountsData"),
           let decoded = try? PropertyListDecoder().decode([Int].self, from: data) {
            eventFolderPeakRawCounts = decoded
        }
        // Load cached counts and paths (offline cache)
        if let data = UserDefaults.standard.data(forKey: "eventFolderCachedCountsData"),
           let decoded = try? PropertyListDecoder().decode([Int].self, from: data) {
            eventFolderCachedCounts = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "eventFolderCachedPathsData"),
           let decoded = try? PropertyListDecoder().decode([String].self, from: data) {
            eventFolderCachedPaths = decoded
        }
        // Load event folder bookmarks (o didSet chama syncDisplayNamesCount e syncPeakCounts)
        if let data = UserDefaults.standard.data(forKey: "eventFolderBookmarksData"),
           let decoded = try? PropertyListDecoder().decode([Data].self, from: data) {
            eventFolderBookmarks = decoded
        }
        // Load finalized snapshots
        finalizedEvents = FinalizedEventsStore.loadAll()

        // Load per-bookmark finalized IDs
        if let data = UserDefaults.standard.data(forKey: "eventFolderFinalizedEventIDData"),
           let decoded = try? PropertyListDecoder().decode([String].self, from: data) {
            eventFolderFinalizedEventID = decoded.map { $0.isEmpty ? nil : UUID(uuidString: $0) }
        }

        syncDisplayNamesCount()
        syncPeakCounts()
        syncCachedCounts()
        syncFinalizedEventIDs()
    }

    private func syncDisplayNamesCount() {
        let n = eventFolderBookmarks.count
        if eventFolderDisplayNames.count > n {
            eventFolderDisplayNames = Array(eventFolderDisplayNames.prefix(n))
        } else if eventFolderDisplayNames.count < n {
            eventFolderDisplayNames += Array(repeating: "", count: n - eventFolderDisplayNames.count)
        }
    }

    private func syncPeakCounts() {
        let n = eventFolderBookmarks.count
        if eventFolderPeakRawCounts.count > n {
            eventFolderPeakRawCounts = Array(eventFolderPeakRawCounts.prefix(n))
        } else if eventFolderPeakRawCounts.count < n {
            eventFolderPeakRawCounts += Array(repeating: 0, count: n - eventFolderPeakRawCounts.count)
        }
    }

    private func syncCachedCounts() {
        let n = eventFolderBookmarks.count
        if eventFolderCachedCounts.count > n {
            eventFolderCachedCounts = Array(eventFolderCachedCounts.prefix(n))
        } else if eventFolderCachedCounts.count < n {
            eventFolderCachedCounts += Array(repeating: -1, count: n - eventFolderCachedCounts.count)
        }
        if eventFolderCachedPaths.count > n {
            eventFolderCachedPaths = Array(eventFolderCachedPaths.prefix(n))
        } else if eventFolderCachedPaths.count < n {
            eventFolderCachedPaths += Array(repeating: "", count: n - eventFolderCachedPaths.count)
        }
    }

    private func syncFinalizedEventIDs() {
        let n = eventFolderBookmarks.count
        if eventFolderFinalizedEventID.count > n {
            eventFolderFinalizedEventID = Array(eventFolderFinalizedEventID.prefix(n))
        } else if eventFolderFinalizedEventID.count < n {
            eventFolderFinalizedEventID += Array(repeating: nil, count: n - eventFolderFinalizedEventID.count)
        }
    }

    private func saveFinalizedEventIDs() {
        let strings: [String] = eventFolderFinalizedEventID.map { $0?.uuidString ?? "" }
        guard let data = try? PropertyListEncoder().encode(strings) else { return }
        UserDefaults.standard.set(data, forKey: "eventFolderFinalizedEventIDData")
    }

    private func saveEventFolderBookmarks() {
        guard let data = try? PropertyListEncoder().encode(eventFolderBookmarks) else { return }
        UserDefaults.standard.set(data, forKey: "eventFolderBookmarksData")
    }

    private func saveEventFolderDisplayNames() {
        guard let data = try? PropertyListEncoder().encode(eventFolderDisplayNames) else { return }
        UserDefaults.standard.set(data, forKey: "eventFolderDisplayNamesData")
    }

    private func saveEventFolderPeakRawCounts() {
        guard let data = try? PropertyListEncoder().encode(eventFolderPeakRawCounts) else { return }
        UserDefaults.standard.set(data, forKey: "eventFolderPeakRawCountsData")
    }

    private func saveCachedCounts() {
        guard let data = try? PropertyListEncoder().encode(eventFolderCachedCounts) else { return }
        UserDefaults.standard.set(data, forKey: "eventFolderCachedCountsData")
    }

    private func saveCachedPaths() {
        guard let data = try? PropertyListEncoder().encode(eventFolderCachedPaths) else { return }
        UserDefaults.standard.set(data, forKey: "eventFolderCachedPathsData")
    }

    /// Atualiza o cache de count e path para um folder (chamado quando o disco está online).
    func updateEventFolderCache(at index: Int, count: Int, path: String) {
        guard index >= 0, index < eventFolderCachedCounts.count else { return }
        eventFolderCachedCounts[index] = count
        if index < eventFolderCachedPaths.count {
            eventFolderCachedPaths[index] = path
        }
    }

    /// Returns aggregated import stats for a specific event folder path.
    /// Matches all ImportHistoryEntry records where destinationPath equals or is inside the event folder.
    func importStats(forEventPath eventPath: String) -> (photoCount: Int, totalBytes: Int64, sessionCount: Int, firstDate: Date?, lastDate: Date?)? {
        guard !eventPath.isEmpty else { return nil }
        // Normalise trailing slashes so "/path/to/folder" and "/path/to/folder/" both match
        let norm = eventPath.hasSuffix("/") ? String(eventPath.dropLast()) : eventPath
        let matching = importHistory.filter { entry in
            let d = entry.destinationPath.hasSuffix("/")
                ? String(entry.destinationPath.dropLast())
                : entry.destinationPath
            return d == norm || d.hasPrefix(norm + "/")
        }
        guard !matching.isEmpty else { return nil }
        let photoCount = matching.reduce(0) { $0 + $1.fileCount }
        let totalBytes = matching.reduce(Int64(0)) { $0 + $1.totalBytes }
        let dates = matching.map(\.date)
        return (
            photoCount: photoCount,
            totalBytes: totalBytes,
            sessionCount: matching.count,
            firstDate: dates.min(),
            lastDate: dates.max()
        )
    }

    /// Atualiza o pico de RAWs da pasta se o novo valor for maior (para não baixar ao apagar ficheiros).
    func setEventFolderPeakIfHigher(at index: Int, count: Int) {
        guard index >= 0, index < eventFolderPeakRawCounts.count else { return }
        let current = eventFolderPeakRawCounts[index]
        if count > current {
            eventFolderPeakRawCounts[index] = count
        }
    }

    func addEventFolder(bookmark: Data) {
        eventFolderBookmarks.append(bookmark)
        // syncDisplayNamesCount() in didSet will append "" for the new folder
    }

    func removeEventFolder(at index: Int) {
        guard index >= 0, index < eventFolderBookmarks.count else { return }
        // Remove from all parallel arrays at the correct index BEFORE removing the bookmark,
        // so that when eventFolderBookmarks.didSet fires syncCachedCounts the arrays are already
        // the right length (no-op). This also fixes multi-folder removal correctness.
        if index < eventFolderCachedCounts.count { eventFolderCachedCounts.remove(at: index) }
        if index < eventFolderCachedPaths.count  { eventFolderCachedPaths.remove(at: index)  }
        if index < eventFolderDisplayNames.count { eventFolderDisplayNames.remove(at: index) }
        if index < eventFolderPeakRawCounts.count { eventFolderPeakRawCounts.remove(at: index) }
        if index < eventFolderFinalizedEventID.count { eventFolderFinalizedEventID.remove(at: index) }
        // Clean up scanning indicator: remove the deleted index and shift higher indices down by 1
        eventFolderScanningIndices.remove(index)
        eventFolderScanningIndices = Set(eventFolderScanningIndices.map { $0 > index ? $0 - 1 : $0 })
        // Triggers didSet → syncDisplayNamesCount / syncPeakCounts / syncCachedCounts (all no-ops now)
        eventFolderBookmarks.remove(at: index)
    }

    func setEventFolderDisplayName(at index: Int, name: String) {
        guard index >= 0, index < eventFolderDisplayNames.count else { return }
        eventFolderDisplayNames[index] = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Source File Ordering
    func updateSourceFiles(_ files: [URL]) {
        sortedSourceFiles = files

        guard !files.isEmpty else {
            captureDateCache = [:]
            return
        }

        sortSourceFilesByCaptureDate(files)
    }

    private func sortSourceFilesByCaptureDate(_ files: [URL]) {
        guard !isSortingSourceFiles else { return }
        isSortingSourceFiles = true

        let cacheSnapshot = captureDateCache

        Task.detached {
            let pairs = await withTaskGroup(of: (URL, Date).self) { group in
                for fileURL in files {
                    if let cached = cacheSnapshot[fileURL] {
                        group.addTask {
                            (fileURL, cached)
                        }
                    } else {
                        group.addTask {
                            let date = await Self.extractCaptureDate(for: fileURL)
                            return (fileURL, date)
                        }
                    }
                }

                var results: [(URL, Date)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            let sorted = pairs.sorted { $0.1 > $1.1 }.map { $0.0 }

            await MainActor.run {
                for (url, date) in pairs {
                    self.captureDateCache[url] = date
                }
                self.sortedSourceFiles = sorted
                self.isSortingSourceFiles = false
            }
        }
    }

    private nonisolated static func extractCaptureDate(for url: URL) async -> Date {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/exiftool")
                process.arguments = ["-DateTimeOriginal", "-s3", "-d", "%Y:%m:%d %H:%M:%S", url.path]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    if process.terminationStatus == 0,
                       let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !output.isEmpty {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                        if let date = formatter.date(from: output) {
                            continuation.resume(returning: date)
                            return
                        }
                    }
                } catch {
                    // Silently fail
                }

                if let creationDate = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate {
                    continuation.resume(returning: creationDate)
                } else {
                    continuation.resume(returning: Date.distantPast)
                }
            }
        }
    }

    // MARK: - Logging
    func log(_ message: String, level: LogEntry.Level = .info) {
        let entry = LogEntry(timestamp: Date(), message: message, level: level)
        logEntries.append(entry)
        #if DEBUG
        print("[\(level.rawValue.uppercased())] \(message)")
        #endif
    }
}

struct ImportProgress {
    var totalFiles: Int = 0
    var completedFiles: Int = 0
    var totalBytes: Int64 = 0
    var transferredBytes: Int64 = 0
    var currentFileName: String = ""
    var startTime: Date?
    var bytesPerSecond: Double = 0

    var fraction: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(completedFiles) / Double(totalFiles)
    }

    var speedFormatted: String {
        let mbps = bytesPerSecond / (1024 * 1024)
        return String(format: "%.1f MB/s", mbps)
    }

    var elapsedFormatted: String {
        guard let start = startTime else { return "--" }
        let elapsed = Date().timeIntervalSince(start)
        let mins = Int(elapsed) / 60
        let secs = Int(elapsed) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let level: Level

    enum Level: String {
        case info, warning, error
    }

    var formatted: String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return "[\(df.string(from: timestamp))] \(message)"
    }
}

enum AppTab {
    case main
    case stats
    case logs
}

enum ImportMode: String, CaseIterable {
    case copy = "copy"
    case move = "move"

    var label: String {
        switch self {
        case .copy: return "Copy"
        case .move: return "Move"
        }
    }

    var icon: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .move: return "arrow.right.doc.on.clipboard"
        }
    }
}
