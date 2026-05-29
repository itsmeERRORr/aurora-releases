import Foundation

struct ImportReport: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let sourceVolumeName: String
    let sourcePath: String
    let destinationPath: String
    let fileCount: Int
    let totalBytes: Int64
    let duration: TimeInterval
    let averageSpeed: Double
    let importedFiles: [String]

    var summary: String {
        let mbTotal = Double(totalBytes) / (1024 * 1024)
        let mbps = averageSpeed / (1024 * 1024)
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return "\(fileCount) files (\(String(format: "%.0f", mbTotal)) MB) in \(mins)m \(secs)s — \(String(format: "%.1f", mbps)) MB/s"
    }

    init(
        sourceVolumeName: String,
        sourcePath: String,
        destinationPath: String,
        fileCount: Int,
        totalBytes: Int64,
        duration: TimeInterval,
        averageSpeed: Double,
        importedFiles: [String]
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.sourceVolumeName = sourceVolumeName
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.duration = duration
        self.averageSpeed = averageSpeed
        self.importedFiles = importedFiles
    }
}
