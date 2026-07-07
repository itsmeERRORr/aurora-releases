import Foundation

enum StatsStorage {
    private static let totalKey = "com.commander.totalStats"
    private static let lastImportKey = "com.commander.lastImportStats"

    // File-based storage for persistence across Xcode builds.
    // Path is routed through AppPaths so Production and Beta builds keep
    // their own isolated files (commanderonev2/ vs commanderonev2-beta/).
    private static var storageURL: URL {
        AppPaths.applicationSupportRoot.appendingPathComponent("totalStats.json")
    }

    private static var lastImportURL: URL {
        AppPaths.applicationSupportRoot.appendingPathComponent("lastImportStats.json")
    }

    static func save(_ stats: StatsReport) {
        do {
            let data = try JSONEncoder().encode(stats)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("StatsStorage.save: ❌ Failed to save - \(error)")
        }
    }

    static func load() -> StatsReport? {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: storageURL)
            return try JSONDecoder().decode(StatsReport.self, from: data).recalculatingISOFromRawOutput()
        } catch {
            print("StatsStorage.load: ❌ Failed to load - \(error)")
            try? FileManager.default.removeItem(at: storageURL)
            return nil
        }
    }

    static func clear() {
        print("StatsStorage.clear: Deleting file at \(storageURL.path)")
        try? FileManager.default.removeItem(at: storageURL)
    }

    // Last import stats
    static func saveLastImport(_ stats: StatsReport) {
        do {
            let data = try JSONEncoder().encode(stats)
            try data.write(to: lastImportURL, options: .atomic)
        } catch {
            print("StatsStorage.saveLastImport: Failed - \(error)")
        }
    }

    static func loadLastImport() -> StatsReport? {
        guard FileManager.default.fileExists(atPath: lastImportURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: lastImportURL)
            let decoder = JSONDecoder()
            return try decoder.decode(StatsReport.self, from: data).recalculatingISOFromRawOutput()
        } catch {
            print("StatsStorage.loadLastImport: Failed - \(error)")
            try? FileManager.default.removeItem(at: lastImportURL)
            return nil
        }
    }

    static func clearLastImport() {
        try? FileManager.default.removeItem(at: lastImportURL)
    }
}
