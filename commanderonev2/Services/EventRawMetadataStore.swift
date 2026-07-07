import Foundation

/// Persists the complete per-file EXIF metadata for every import, keyed by event destination path.
/// Records accumulate across imports and survive event finalization — they are never deleted by Aurora.
/// The file format is a plain JSON array of exiftool entry objects.
enum EventRawMetadataStore {

    private static let reportCacheLock = NSLock()
    private static var reportCache: [String: StatsReport] = [:]

    /// Appends raw exiftool JSON records to the event's metadata file.
    /// Safe to call from any thread. Creates the file if it doesn't exist yet.
    static func append(_ rawJSON: String, forPath eventPath: String) {
        guard let newData = rawJSON.data(using: .utf8),
              let newEntries = try? JSONSerialization.jsonObject(with: newData) as? [[String: Any]],
              !newEntries.isEmpty else { return }

        let fileURL = storeURL(for: eventPath)
        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var existing: [[String: Any]] = []
        if let existingData = try? Data(contentsOf: fileURL),
           let decoded = try? JSONSerialization.jsonObject(with: existingData) as? [[String: Any]] {
            existing = decoded
        }

        existing.append(contentsOf: newEntries)

        if let combined = try? JSONSerialization.data(withJSONObject: existing, options: []) {
            try? combined.write(to: fileURL, options: .atomic)
        }
    }

    /// Returns the URL of the raw metadata file for an event path, or nil if it doesn't exist yet.
    static func fileURL(forPath eventPath: String) -> URL? {
        let url = storeURL(for: eventPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Builds a lightweight report from raw metadata files whose stored event path starts
    /// with the supplied folder path. Useful for enriching old event caches without a rescan.
    /// Thread-safe (NSLock-guarded cache, same pattern as `EventStatsCache`'s memory
    /// cache) so it can be called from a background thread — this does real
    /// directory enumeration + JSON reads, called once per event/folder from
    /// `AppState.aggregateDashboardTotalStatsReport`.
    nonisolated static func cameraMetadataReport(forEventPathPrefix eventPath: String) -> StatsReport? {
        let prefix = sanitizedPath(eventPath)
        guard !prefix.isEmpty else { return nil }
        if let cached = reportCacheLock.withLock({ reportCache[prefix] }) { return cached }

        let dir = metadataDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil), !files.isEmpty else {
            return nil
        }

        var cameraCounts: [String: Int] = [:]
        var cameraMaxShutterCounts: [String: Int] = [:]
        var cameraLastSeenDates: [String: Date] = [:]
        var totalFiles = 0

        for file in files where file.lastPathComponent.hasPrefix(prefix) && file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }

            totalFiles += entries.count
            for entry in entries {
                let make = entry["Make"] as? String ?? ""
                let model = entry["Model"] as? String ?? ""
                guard !model.isEmpty else { continue }
                let cameraKey = "\(make)|\(model)"
                cameraCounts[cameraKey, default: 0] += 1

                if let count = effectiveShutterCount(from: entry) {
                    cameraMaxShutterCounts[cameraKey] = max(cameraMaxShutterCounts[cameraKey] ?? 0, count)
                }
                if let date = captureDate(from: entry) {
                    cameraLastSeenDates[cameraKey] = max(cameraLastSeenDates[cameraKey] ?? .distantPast, date)
                }
            }
        }

        guard totalFiles > 0, (!cameraMaxShutterCounts.isEmpty || !cameraLastSeenDates.isEmpty) else { return nil }
        let report = StatsReport(
            topLenses: [],
            mostUsedCamera: nil,
            shutterSpeeds: [],
            totalFilesAnalyzed: totalFiles,
            rawOutput: "raw metadata camera enrichment",
            avgISO: nil,
            avgAperture: nil,
            avgFocalLength: nil,
            lensCounts: [:],
            cameraCounts: cameraCounts,
            shutterCounts: [:],
            isoSum: 0,
            isoCount: 0,
            apertureSum: 0,
            apertureCount: 0,
            focalSum: 0,
            focalCount: 0,
            monthCounts: [:],
            weekCounts: [:],
            yearCounts: [:],
            cameraMaxShutterCounts: cameraMaxShutterCounts,
            cameraLastSeenDates: cameraLastSeenDates
        )
        reportCacheLock.withLock { reportCache[prefix] = report }
        return report
    }

    private static func storeURL(for eventPath: String) -> URL {
        let dir = metadataDirectory()
        let sanitized = sanitizedPath(eventPath)
        return dir.appendingPathComponent(String(sanitized.suffix(80)) + "_raw.json")
    }

    private static func metadataDirectory() -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dirName = Bundle.main.bundleIdentifier?.contains(".beta") == true
            ? "commanderonev2-beta" : "commanderonev2"
        return appSupport
            .appendingPathComponent(dirName)
            .appendingPathComponent("event_raw_metadata")
    }

    private static func sanitizedPath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }

    private static func effectiveShutterCount(from entry: [String: Any]) -> Int? {
        let candidates: [Any?] = [entry["ShutterCount"], entry["ImageCount"], entry["ActuationCount"], entry["ReleaseCount"]]
        for candidate in candidates {
            if let i = candidate as? Int, i > 0 { return i }
            if let d = candidate as? Double, d > 0 { return Int(d) }
            if let s = candidate as? String, let i = Int(s), i > 0 { return i }
        }
        return nil
    }

    private static func captureDate(from entry: [String: Any]) -> Date? {
        parseExifDate(entry["DateTimeOriginal"], subsec: entry["SubSecTimeOriginal"])
            ?? parseExifDate(entry["CreateDate"], subsec: entry["SubSecCreateDate"])
            ?? parseExifDate(entry["DateCreated"], subsec: nil)
    }

    private static func parseExifDate(_ value: Any?, subsec: Any?) -> Date? {
        guard let raw = value as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard var date = formatter.date(from: String(raw.prefix(19))) else { return nil }
        if let fraction = parseSubsecond(subsec) {
            date = date.addingTimeInterval(fraction)
        }
        return date
    }

    private static func parseSubsecond(_ value: Any?) -> TimeInterval? {
        let string: String?
        if let intValue = value as? Int {
            string = String(intValue)
        } else if let doubleValue = value as? Double {
            string = String(Int(doubleValue))
        } else {
            string = value as? String
        }
        guard let string else { return nil }
        let digits = string.filter { $0.isNumber }
        guard !digits.isEmpty, let value = Double("0." + digits) else { return nil }
        return value
    }
}
