import Foundation

enum StatsStorage {
    private static let totalKey = "com.commander.totalStats"
    private static let lastImportKey = "com.commander.lastImportStats"

    // File-based storage for persistence across Xcode builds
    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("commanderonev2", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("totalStats.json")
    }

    private static var lastImportURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("commanderonev2", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("lastImportStats.json")
    }

    static func save(_ stats: StatsReport) {
        print("StatsStorage.save: Saving stats with \(stats.totalFilesAnalyzed) files to file")
        print("StatsStorage.save: File path: \(storageURL.path)")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(stats)
            try data.write(to: storageURL, options: .atomic)
            print("StatsStorage.save: ✅ Successfully saved \(data.count) bytes to file")
        } catch {
            print("StatsStorage.save: ❌ Failed to save - \(error)")
        }
    }

    static func load() -> StatsReport? {
        print("StatsStorage.load: Loading from file: \(storageURL.path)")

        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            print("StatsStorage.load: ❌ File does not exist")
            return nil
        }

        do {
            let data = try Data(contentsOf: storageURL)
            print("StatsStorage.load: ✅ Found data of \(data.count) bytes")

            let decoder = JSONDecoder()
            let stats = try decoder.decode(StatsReport.self, from: data)
            print("StatsStorage.load: ✅ Successfully loaded stats with \(stats.totalFilesAnalyzed) files")
            return stats
        } catch {
            print("StatsStorage.load: ❌ Failed to load - \(error)")
            // Clear corrupted file
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
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(stats)
            try data.write(to: lastImportURL, options: .atomic)
            print("StatsStorage.saveLastImport: Saved \(data.count) bytes")
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
            return try decoder.decode(StatsReport.self, from: data)
        } catch {
            print("StatsStorage.loadLastImport: Failed - \(error)")
            try? FileManager.default.removeItem(at: lastImportURL)
            return nil
        }
    }
}
