import Foundation

actor ImportEngine {
    private var isCancelled = false
    private var isPaused = false
    private let fileManager = FileManager.default

    // Concurrency: number of parallel copy operations
    private let maxConcurrent = 4

    func cancel() {
        isCancelled = true
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    struct ProgressUpdate: Sendable {
        let completedFiles: Int
        let totalFiles: Int
        let transferredBytes: Int64
        let totalBytes: Int64
        let currentFileName: String
        let bytesPerSecond: Double
    }

    enum Mode: Sendable {
        case copy
        case move
    }

    func importFiles(
        from sourceFiles: [URL],
        to destinationBase: URL,
        mode: Mode = .move,
        createSubfolder: Bool = false,
        onProgress: @Sendable (ProgressUpdate) -> Void
    ) async throws -> ImportResult {
        isCancelled = false
        isPaused = false

        // Create date-stamped subfolder
        let destFolder: URL
        if createSubfolder {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd_HH-mm"
            let folderName = df.string(from: Date())
            destFolder = destinationBase.appendingPathComponent(folderName)
        } else {
            destFolder = destinationBase
        }

        if !fileManager.fileExists(atPath: destFolder.path) {
            try fileManager.createDirectory(at: destFolder, withIntermediateDirectories: true)
        }

        // Calculate total size
        var totalBytes: Int64 = 0
        var fileSizes: [Int64] = []
        for file in sourceFiles {
            let attrs = try? fileManager.attributesOfItem(atPath: file.path)
            let size = (attrs?[.size] as? Int64) ?? 0
            totalBytes += size
            fileSizes.append(size)
        }

        let startTime = Date()
        let transferredBytes = TransferCounter()
        let completedCount = TransferCounter()
        let importedFiles = ImportedFilesList()
        let lastFileName = LastFileName()

        // Process files concurrently in batches
        try await withThrowingTaskGroup(of: Void.self) { group in
            var index = 0

            for (fileIndex, sourceFile) in sourceFiles.enumerated() {
                // Check cancel before adding more work
                if isCancelled {
                    group.cancelAll()
                    throw ImportError.cancelled
                }

                // Wait while paused
                while isPaused {
                    try await Task.sleep(for: .milliseconds(100))
                    if isCancelled {
                        group.cancelAll()
                        throw ImportError.cancelled
                    }
                }

                // Limit concurrency by waiting for a slot
                if index >= maxConcurrent {
                    try await group.next()
                }

                let fileName = sourceFile.lastPathComponent
                let destFolderCopy = destFolder
                let fileSize = fileSizes[fileIndex]

                group.addTask { [fileManager] in
                    let destFile = Self.uniqueDestinationURL(fileManager: fileManager, destFolder: destFolderCopy, fileName: fileName)
                    do {
                        switch mode {
                        case .move:
                            try fileManager.moveItem(at: sourceFile, to: destFile)
                        case .copy:
                            try fileManager.copyItem(at: sourceFile, to: destFile)
                        }
                    } catch {
                        if mode == .move {
                            do {
                                try fileManager.copyItem(at: sourceFile, to: destFile)
                            } catch {
                                return
                            }
                        } else {
                            return
                        }
                    }

                    await transferredBytes.add(fileSize)
                    await completedCount.add(1)
                    await importedFiles.append(destFile.path)
                    await lastFileName.set(destFile.lastPathComponent)
                }

                index += 1

                // Report progress periodically (every 4 files to avoid UI flood)
                if index % 4 == 0 || index == sourceFiles.count {
                    let completed = await completedCount.value
                    let transferred = await transferredBytes.value
                    let currentName = await lastFileName.value
                    let elapsed = Date().timeIntervalSince(startTime)
                    let speed = elapsed > 0 ? Double(transferred) / elapsed : 0

                    onProgress(ProgressUpdate(
                        completedFiles: Int(completed),
                        totalFiles: sourceFiles.count,
                        transferredBytes: transferred,
                        totalBytes: totalBytes,
                        currentFileName: currentName,
                        bytesPerSecond: speed
                    ))
                }
            }

            // Wait for remaining tasks
            try await group.waitForAll()
        }

        // Final progress update
        let finalTransferred = await transferredBytes.value
        let finalCompleted = await completedCount.value
        let elapsed = Date().timeIntervalSince(startTime)
        let speed = elapsed > 0 ? Double(finalTransferred) / elapsed : 0

        onProgress(ProgressUpdate(
            completedFiles: Int(finalCompleted),
            totalFiles: sourceFiles.count,
            transferredBytes: finalTransferred,
            totalBytes: totalBytes,
            currentFileName: "Done",
            bytesPerSecond: speed
        ))

        let duration = Date().timeIntervalSince(startTime)
        let avgSpeed = duration > 0 ? Double(finalTransferred) / duration : 0
        let files = await importedFiles.values

        return ImportResult(
            fileCount: files.count,
            totalBytes: finalTransferred,
            duration: duration,
            averageSpeed: avgSpeed,
            destinationPath: destFolder.path,
            importedFiles: files
        )
    }

    /// Returns a destination URL that does not yet exist. If the base fileName exists, tries base_2.ext, base_3.ext, … until free.
    private static func uniqueDestinationURL(fileManager: FileManager, destFolder: URL, fileName: String) -> URL {
        let asURL = URL(fileURLWithPath: fileName)
        let base = asURL.deletingPathExtension().lastPathComponent
        let ext = asURL.pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"

        var candidate = destFolder.appendingPathComponent(fileName)
        var n = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = destFolder.appendingPathComponent("\(base)_\(n)\(suffix)")
            n += 1
        }
        return candidate
    }
}

// Thread-safe counters for concurrent progress tracking
private actor TransferCounter {
    var value: Int64 = 0
    func add(_ amount: Int64) { value += amount }
}

private actor ImportedFilesList {
    var values: [String] = []
    func append(_ path: String) { values.append(path) }
}

private actor LastFileName {
    var value: String = ""
    func set(_ name: String) { value = name }
}

struct ImportResult: Sendable {
    let fileCount: Int
    let totalBytes: Int64
    let duration: TimeInterval
    let averageSpeed: Double
    let destinationPath: String
    let importedFiles: [String]
}

enum ImportError: LocalizedError {
    case cancelled
    case noFiles
    case noDestination
    case fileFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Import was cancelled"
        case .noFiles: return "No files to import"
        case .noDestination: return "No destination selected"
        case .fileFailed(let name, let reason): return "Failed to import \(name): \(reason)"
        }
    }
}
