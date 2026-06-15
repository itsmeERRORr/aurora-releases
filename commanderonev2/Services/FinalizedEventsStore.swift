import Foundation

/// JSON-backed store for `FinalizedEvent` snapshots.
/// Persists the entire collection as one file in Application Support.
enum FinalizedEventsStore {

    private static var storageURL: URL {
        AppPaths.applicationSupportRoot.appendingPathComponent("finalized_events.json")
    }

    static func loadAll() -> [FinalizedEvent] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: storageURL)
            return try JSONDecoder().decode([FinalizedEvent].self, from: data)
        } catch {
            print("FinalizedEventsStore.loadAll: failed – \(error)")
            return []
        }
    }

    static func saveAll(_ events: [FinalizedEvent]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(events)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("FinalizedEventsStore.saveAll: failed – \(error)")
        }
    }
}
