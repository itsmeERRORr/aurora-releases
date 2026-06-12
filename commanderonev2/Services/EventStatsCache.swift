import Foundation

/// Persists per-event EXIF scan results so they survive disk disconnections and app restarts.
final class EventStatsCache {

    private static let storageDir: URL = {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("commanderonev2/event_stats_cache", isDirectory: true)
    }()

    private struct CacheEntry: Codable {
        let report: StatsReport
        let scanDate: Date
        let folderPath: String
        let rawFileCountAtScan: Int?
    }

    static func save(_ report: StatsReport, forPath path: String, scanDate: Date = Date(), rawFileCountAtScan: Int? = nil) {
        let fm = FileManager.default
        try? fm.createDirectory(at: storageDir, withIntermediateDirectories: true)
        let url = storageDir.appendingPathComponent(cacheFilename(for: path))
        let entry = CacheEntry(
            report: report,
            scanDate: scanDate,
            folderPath: path,
            rawFileCountAtScan: rawFileCountAtScan
        )
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load(forPath path: String) -> (report: StatsReport, scanDate: Date, rawFileCountAtScan: Int?)? {
        let url = storageDir.appendingPathComponent(cacheFilename(for: path))
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else {
            return nil
        }
        return (
            report: entry.report.recalculatingISOFromRawOutput(),
            scanDate: entry.scanDate,
            rawFileCountAtScan: entry.rawFileCountAtScan
        )
    }

    static func clear(forPath path: String) {
        let url = storageDir.appendingPathComponent(cacheFilename(for: path))
        try? FileManager.default.removeItem(at: url)
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
