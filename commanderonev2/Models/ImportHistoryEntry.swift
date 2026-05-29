import Foundation

struct ImportHistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let sourceName: String
    let destinationPath: String
    let fileCount: Int
    let totalBytes: Int64

    init(id: UUID = UUID(), date: Date = Date(), sourceName: String, destinationPath: String, fileCount: Int, totalBytes: Int64) {
        self.id = id
        self.date = date
        self.sourceName = sourceName
        self.destinationPath = destinationPath
        self.fileCount = fileCount
        self.totalBytes = totalBytes
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var formattedSize: String {
        let gb = Double(totalBytes) / (1024 * 1024 * 1024)
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(totalBytes) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }

    var destinationName: String {
        URL(fileURLWithPath: destinationPath).lastPathComponent
    }
}
