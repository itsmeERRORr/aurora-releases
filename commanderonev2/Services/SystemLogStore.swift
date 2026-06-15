import Foundation

enum SystemLogStore {
    private static var storageURL: URL {
        AppPaths.applicationSupportRoot.appendingPathComponent("system.log.jsonl")
    }

    static func append(_ entry: LogEntry) {
        do {
            let data = try JSONEncoder().encode(entry)
            if FileManager.default.fileExists(atPath: storageURL.path) {
                let handle = try FileHandle(forWritingTo: storageURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.write(contentsOf: Data("\n".utf8))
                try handle.close()
            } else {
                try (data + Data("\n".utf8)).write(to: storageURL, options: .atomic)
            }
        } catch {
            print("SystemLogStore.append failed: \(error)")
        }
    }

    static func loadAll() -> [LogEntry] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return [] }

        do {
            let data = try Data(contentsOf: storageURL)
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            let decoder = JSONDecoder()
            return text
                .split(separator: "\n")
                .compactMap { line in
                    guard let lineData = String(line).data(using: .utf8) else { return nil }
                    return try? decoder.decode(LogEntry.self, from: lineData)
                }
        } catch {
            print("SystemLogStore.loadAll failed: \(error)")
            return []
        }
    }

    static var fileURL: URL {
        storageURL
    }
}
