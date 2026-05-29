import Foundation

/// Frozen snapshot of an event's statistics, persisted independently of the
/// sidebar bookmark so the totals survive file deletion, folder moves, and
/// offline volumes.
struct FinalizedEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var snapshot: StatsReport
    var totalBytes: Int64
    var photoCount: Int
    var firstImportDate: Date?
    var lastImportDate: Date?
    let finalizedAt: Date
    var lastKnownPath: String
    var originalBookmark: Data?

    init(
        id: UUID = UUID(),
        name: String,
        snapshot: StatsReport,
        totalBytes: Int64,
        photoCount: Int,
        firstImportDate: Date? = nil,
        lastImportDate: Date? = nil,
        finalizedAt: Date = Date(),
        lastKnownPath: String,
        originalBookmark: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.snapshot = snapshot
        self.totalBytes = totalBytes
        self.photoCount = photoCount
        self.firstImportDate = firstImportDate
        self.lastImportDate = lastImportDate
        self.finalizedAt = finalizedAt
        self.lastKnownPath = lastKnownPath
        self.originalBookmark = originalBookmark
    }
}
