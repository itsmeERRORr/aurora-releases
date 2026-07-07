import Foundation

enum EventStatsScanQuality: String, Codable, Equatable {
    case quick
    case partial
    case full

    var label: String {
        switch self {
        case .quick: return "Quick"
        case .partial: return "Partial"
        case .full: return "Full"
        }
    }
}

/// Persists per-event EXIF scan results so they survive disk disconnections and app restarts.
final class EventStatsCache {

    private static let storageDir: URL = AppPaths.subdirectory("event_stats_cache")
    private static let productionStorageDir: URL = {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("commanderonev2", isDirectory: true)
            .appendingPathComponent("event_stats_cache", isDirectory: true)
    }()
    private static let jpgOnlyRawOutput = "jpg day cache only"
    private static let memoryCacheLock = NSLock()
    private static var memoryCache: [String: CacheEntry] = [:]

    private struct CacheEntry: Codable {
        let report: StatsReport
        let scanDate: Date
        let folderPath: String
        let rawFileCountAtScan: Int?
        let scanQuality: EventStatsScanQuality?
        let jpgCountsByDay: [String: Int]?
    }

    static func save(_ report: StatsReport, forPath path: String, scanDate: Date = Date(), rawFileCountAtScan: Int? = nil, scanQuality: EventStatsScanQuality = .full, jpgCountsByDay: [String: Int]? = nil) {
        let fm = FileManager.default
        try? fm.createDirectory(at: storageDir, withIntermediateDirectories: true)
        let url = storageDir.appendingPathComponent(cacheFilename(for: path))
        let existingJPGCountsByDay = loadCacheEntry(forPath: path)?.jpgCountsByDay
        let entry = CacheEntry(
            report: report,
            scanDate: scanDate,
            folderPath: path,
            rawFileCountAtScan: rawFileCountAtScan,
            scanQuality: scanQuality,
            jpgCountsByDay: jpgCountsByDay ?? existingJPGCountsByDay
        )
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: url, options: .atomic)
            setMemoryCacheEntry(entry, forPath: path)
        }
    }

    static func saveJPGCountsByDay(_ counts: [String: Int], forPath path: String) {
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        var entry = loadCacheEntry(forPath: path) ?? CacheEntry(
            report: StatsReport.instantFolderScan(fileCount: 0),
            scanDate: Date(),
            folderPath: path,
            rawFileCountAtScan: nil,
            scanQuality: nil,
            jpgCountsByDay: nil
        )
        let url = storageDir.appendingPathComponent(cacheFilename(for: path))
        var report = entry.report
        if report.rawOutput == "instant folder scan" && report.totalFilesAnalyzed == 0 {
            report.rawOutput = jpgOnlyRawOutput
        }
        entry = CacheEntry(
            report: report,
            scanDate: entry.scanDate,
            folderPath: entry.folderPath,
            rawFileCountAtScan: entry.rawFileCountAtScan,
            scanQuality: entry.scanQuality,
            jpgCountsByDay: counts
        )
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: url, options: .atomic)
            setMemoryCacheEntry(entry, forPath: path)
        }
    }

    static func loadJPGCountsByDay(forPath path: String) -> [String: Int]? {
        loadCacheEntry(forPath: path)?.jpgCountsByDay
    }

    static func load(forPath path: String) -> (report: StatsReport, scanDate: Date, rawFileCountAtScan: Int?)? {
        guard let entry = loadEntry(forPath: path) else { return nil }
        return (
            report: entry.report,
            scanDate: entry.scanDate,
            rawFileCountAtScan: entry.rawFileCountAtScan
        )
    }

    static func loadWithQuality(forPath path: String) -> (report: StatsReport, scanDate: Date, rawFileCountAtScan: Int?, scanQuality: EventStatsScanQuality)? {
        guard let entry = loadEntry(forPath: path) else { return nil }
        return (
            report: entry.report,
            scanDate: entry.scanDate,
            rawFileCountAtScan: entry.rawFileCountAtScan,
            scanQuality: entry.scanQuality
        )
    }

    private static func loadEntry(forPath path: String) -> (report: StatsReport, scanDate: Date, rawFileCountAtScan: Int?, scanQuality: EventStatsScanQuality)? {
        guard let entry = loadCacheEntry(forPath: path) else { return nil }
        guard entry.report.rawOutput != jpgOnlyRawOutput else { return nil }
        return (
            report: entry.report.recalculatingISOFromRawOutput(),
            scanDate: entry.scanDate,
            rawFileCountAtScan: entry.rawFileCountAtScan,
            scanQuality: entry.scanQuality ?? .full
        )
    }

    private static func loadCacheEntry(forPath path: String) -> CacheEntry? {
        if let cached = memoryCacheEntry(forPath: path) {
            return cached
        }

        let filename = cacheFilename(for: path)
        let localEntry = loadCacheEntry(at: storageDir.appendingPathComponent(filename))

        if AppPaths.isBeta,
           let productionEntry = loadCacheEntry(at: productionStorageDir.appendingPathComponent(filename)),
           shouldPreferProductionEntry(productionEntry, over: localEntry) {
            setMemoryCacheEntry(productionEntry, forPath: path)
            return productionEntry
        }

        guard let localEntry else {
            return nil
        }
        setMemoryCacheEntry(localEntry, forPath: path)
        return localEntry
    }

    static func clear(forPath path: String) {
        let url = storageDir.appendingPathComponent(cacheFilename(for: path))
        try? FileManager.default.removeItem(at: url)
        removeMemoryCacheEntry(forPath: path)
    }

    private static func memoryCacheEntry(forPath path: String) -> CacheEntry? {
        let key = cacheFilename(for: path)
        memoryCacheLock.lock()
        defer { memoryCacheLock.unlock() }
        return memoryCache[key]
    }

    private static func setMemoryCacheEntry(_ entry: CacheEntry, forPath path: String) {
        let key = cacheFilename(for: path)
        memoryCacheLock.lock()
        memoryCache[key] = entry
        memoryCacheLock.unlock()
    }

    private static func removeMemoryCacheEntry(forPath path: String) {
        let key = cacheFilename(for: path)
        memoryCacheLock.lock()
        memoryCache.removeValue(forKey: key)
        memoryCacheLock.unlock()
    }

    private static func loadCacheEntry(at url: URL) -> CacheEntry? {
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else {
            return nil
        }
        return entry
    }

    private static func shouldPreferProductionEntry(_ production: CacheEntry, over local: CacheEntry?) -> Bool {
        guard let local else { return true }
        if local.report.totalBytes == 0, production.report.totalBytes > 0 { return true }
        if production.report.totalFilesAnalyzed > local.report.totalFilesAnalyzed,
           production.report.totalBytes >= local.report.totalBytes {
            return true
        }
        return false
    }

    private static func cacheFilename(for path: String) -> String {
        // Stable filename derived from the path — keep last 80 chars to avoid too-long filenames
        let sanitized = path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return String(sanitized.suffix(80)) + ".json"
    }
}
