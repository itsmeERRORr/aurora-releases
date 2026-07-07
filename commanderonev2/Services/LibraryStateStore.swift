import Foundation

struct LibraryStateSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var migratedAt: Date = Date()

    var eventFolderBookmarks: [Data]
    var eventFolderDisplayNames: [String]
    var eventFolderIsLibrary: [Bool]
    var eventFolderManualDates: [Date?]
    var eventFolderPeakRawCounts: [Int]
    var eventFolderCachedCounts: [Int]
    var eventFolderCachedJPGCounts: [Int]
    var eventFolderCachedJPGCountsByDay: [[String: Int]]?
    var eventFolderCachedPaths: [String]
    var eventFolderPreviousCachedPaths: [String]
    var eventFolderBannerImagePaths: [String]
    var eventFolderBannerOffsets: [EventBannerOffset]
    var eventFolderFinalizedEventID: [UUID?]
    var eventFolderOrder: [Int]
    var eventSidebarNodes: [EventSidebarNode]
    var activeEventFolderIndex: Int?
    var eventFolderTags: [[String]]?

    var bookmarkCount: Int { eventFolderBookmarks.count }
    var libraryFolderCount: Int { eventFolderIsLibrary.filter { $0 }.count }
}

enum LibraryStateStore {
    private static let stateFileName = "library_state.json"
    private static let backupRootName = "migration_backups"

    private static var fileURL: URL {
        AppPaths.applicationSupportRoot.appendingPathComponent(stateFileName)
    }

    private static var backupRootURL: URL {
        AppPaths.applicationSupportRoot.appendingPathComponent(backupRootName, isDirectory: true)
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func load() -> LibraryStateSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(LibraryStateSnapshot.self, from: data),
              validate(snapshot) else {
            return nil
        }
        return snapshot
    }

    static func save(_ snapshot: LibraryStateSnapshot) {
        guard validate(snapshot),
              let data = try? prettyEncoder.encode(snapshot) else {
            return
        }
        try? FileManager.default.createDirectory(at: AppPaths.applicationSupportRoot, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic])
    }

    static func createPreMigrationBackup(librarySnapshot: LibraryStateSnapshot, importHistory: [ImportHistoryEntry]) {
        let fm = FileManager.default
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = backupRootURL.appendingPathComponent("pre-library-state-\(timestamp)", isDirectory: true)

        guard !fm.fileExists(atPath: backupURL.path) else { return }
        do {
            try fm.createDirectory(at: backupURL, withIntermediateDirectories: true)
            if let libraryData = try? prettyEncoder.encode(librarySnapshot) {
                try libraryData.write(to: backupURL.appendingPathComponent("library_state_legacy_snapshot.json"), options: [.atomic])
            }
            if let historyData = try? prettyEncoder.encode(importHistory) {
                try historyData.write(to: backupURL.appendingPathComponent("import_history_legacy_snapshot.json"), options: [.atomic])
            }
        } catch {
            return
        }
    }

    static func validate(_ snapshot: LibraryStateSnapshot) -> Bool {
        guard snapshot.schemaVersion == LibraryStateSnapshot.currentSchemaVersion else { return false }
        let count = snapshot.eventFolderBookmarks.count
        let sameSizeArrays = [
            snapshot.eventFolderDisplayNames.count,
            snapshot.eventFolderIsLibrary.count,
            snapshot.eventFolderManualDates.count,
            snapshot.eventFolderPeakRawCounts.count,
            snapshot.eventFolderCachedCounts.count,
            snapshot.eventFolderCachedJPGCounts.count,
            snapshot.eventFolderCachedJPGCountsByDay?.count ?? count,
            snapshot.eventFolderCachedPaths.count,
            snapshot.eventFolderPreviousCachedPaths.count,
            snapshot.eventFolderBannerImagePaths.count,
            snapshot.eventFolderBannerOffsets.count,
            snapshot.eventFolderFinalizedEventID.count
        ]
        guard sameSizeArrays.allSatisfy({ $0 == count }) else { return false }
        return snapshot.eventFolderOrder.allSatisfy { $0 >= 0 && $0 < count }
    }

    private static var prettyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
