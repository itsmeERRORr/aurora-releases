import Foundation

enum ImportHistoryStorage {
    private static let storageKey = "importHistory"
    private static let maxEntries = 1000

    static func save(_ history: [ImportHistoryEntry]) {
        // Keep only the most recent entries
        let trimmedHistory = Array(history.prefix(maxEntries))

        if let data = try? JSONEncoder().encode(trimmedHistory) {
            UserDefaults.standard.set(data, forKey: storageKey)
            try? FileManager.default.createDirectory(at: AppPaths.applicationSupportRoot, withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    static func load() -> [ImportHistoryEntry] {
        let legacyHistory = loadLegacyDefaults()
        if let data = try? Data(contentsOf: fileURL),
           let history = try? JSONDecoder().decode([ImportHistoryEntry].self, from: data) {
            if history.count >= legacyHistory.count {
                return history
            }
            save(legacyHistory)
            return legacyHistory
        }
        save(legacyHistory)
        return legacyHistory
    }

    private static func loadLegacyDefaults() -> [ImportHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let history = try? JSONDecoder().decode([ImportHistoryEntry].self, from: data) else {
            return []
        }
        return history
    }

    static func add(_ entry: ImportHistoryEntry) {
        var history = load()
        history.insert(entry, at: 0) // Add to beginning
        save(history)
    }

    @discardableResult
    static func removeEntries(matchingAnyOf paths: [String]) -> [ImportHistoryEntry] {
        let normalizedPaths = Set(paths.map(normalizePath).filter { !$0.isEmpty })
        guard !normalizedPaths.isEmpty else { return [] }

        let history = load()
        var removed: [ImportHistoryEntry] = []
        let kept = history.filter { entry in
            let destination = normalizePath(entry.destinationPath)
            let matches = normalizedPaths.contains { path in
                destination == path || destination.hasPrefix(path + "/")
            }
            if matches { removed.append(entry) }
            return !matches
        }
        save(kept)
        return removed
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var fileURL: URL {
        AppPaths.applicationSupportRoot.appendingPathComponent("import_history.json")
    }

    private static func normalizePath(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
