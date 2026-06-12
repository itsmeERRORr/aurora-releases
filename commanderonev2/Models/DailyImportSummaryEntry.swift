import Foundation

struct DailyImportSummaryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let sourceName: String
    let eventName: String
    let destinationPath: String
    let rawCount: Int
    let totalBytes: Int64
    let duration: Int
    let cameraCounts: [String: Int]
    let lensCounts: [String: Int]
    let isoCounts: [String: Int]
    let shutterCounts: [String: Int]

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        sourceName: String,
        eventName: String,
        destinationPath: String,
        rawCount: Int,
        totalBytes: Int64,
        duration: Int,
        cameraCounts: [String: Int],
        lensCounts: [String: Int],
        isoCounts: [String: Int],
        shutterCounts: [String: Int]
    ) {
        self.id = id
        self.date = date
        self.sourceName = sourceName
        self.eventName = eventName
        self.destinationPath = destinationPath
        self.rawCount = rawCount
        self.totalBytes = totalBytes
        self.duration = duration
        self.cameraCounts = cameraCounts
        self.lensCounts = lensCounts
        self.isoCounts = isoCounts
        self.shutterCounts = shutterCounts
    }
}
