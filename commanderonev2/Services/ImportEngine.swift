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
        let skippedFiles: Int
        let statusMessage: String?
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
        renameOptions: ImportRenameOptions? = nil,
        reservationCoordinator: DestinationReservationCoordinator? = nil,
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

        let sources = sourceFiles.enumerated().map { index, sourceFile in
            ImportSource(
                url: sourceFile,
                fileName: renameOptions?.destinationFileName(for: sourceFile, index: index) ?? sourceFile.lastPathComponent,
                size: fileSizes[index]
            )
        }
        let jobs: [ImportJob]
        if let reservationCoordinator {
            jobs = await Self.importJobs(
                fileManager: fileManager,
                destFolder: destFolder,
                sources: sources,
                mode: mode,
                reservationCoordinator: reservationCoordinator
            )
        } else {
            jobs = Self.importJobs(
                fileManager: fileManager,
                destFolder: destFolder,
                sources: sources,
                mode: mode
            )
        }
        let skippedFiles = sourceFiles.count - jobs.count
        let importTotalBytes = jobs.reduce(Int64(0)) { $0 + $1.size }

        if jobs.isEmpty {
            onProgress(ProgressUpdate(
                completedFiles: 0,
                totalFiles: 0,
                transferredBytes: 0,
                totalBytes: 0,
                currentFileName: "No new files",
                bytesPerSecond: 0,
                skippedFiles: skippedFiles,
                statusMessage: skippedFiles > 0 ? "Skipped \(skippedFiles) duplicate file\(skippedFiles == 1 ? "" : "s") already present in destination." : nil
            ))
            return ImportResult(
                fileCount: 0,
                totalBytes: 0,
                duration: 0,
                averageSpeed: 0,
                destinationPath: destFolder.path,
                importedFiles: [],
                skippedFiles: skippedFiles
            )
        }

        let startTime = Date()
        let transferredBytes = TransferCounter()
        let completedCount = TransferCounter()
        let importedFiles = ImportedFilesList()
        let lastFileName = LastFileName()

        // Process files concurrently in batches
        try await withThrowingTaskGroup(of: Void.self) { group in
            var index = 0

            for job in jobs {
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

                let sourceFile = job.url
                let destFile = job.destination
                let fileSize = job.size

                group.addTask { [fileManager] in
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
                                throw ImportError.fileFailed(sourceFile.lastPathComponent, error.localizedDescription)
                            }
                        } else {
                            throw ImportError.fileFailed(sourceFile.lastPathComponent, error.localizedDescription)
                        }
                    }

                    await transferredBytes.add(fileSize)
                    await completedCount.add(1)
                    await importedFiles.append(destFile.path)
                    await lastFileName.set(destFile.lastPathComponent)
                }

                index += 1

                // Report progress periodically (every 4 files to avoid UI flood)
                if index % 4 == 0 || index == jobs.count {
                    let completed = await completedCount.value
                    let transferred = await transferredBytes.value
                    let currentName = await lastFileName.value
                    let elapsed = Date().timeIntervalSince(startTime)
                    let speed = elapsed > 0 ? Double(transferred) / elapsed : 0

                    onProgress(ProgressUpdate(
                        completedFiles: Int(completed),
                        totalFiles: jobs.count,
                        transferredBytes: transferred,
                        totalBytes: importTotalBytes,
                        currentFileName: currentName,
                        bytesPerSecond: speed,
                        skippedFiles: skippedFiles,
                        statusMessage: skippedFiles > 0 ? "Skipped \(skippedFiles) duplicate file\(skippedFiles == 1 ? "" : "s") already present in destination." : nil
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
            totalFiles: jobs.count,
            transferredBytes: finalTransferred,
            totalBytes: importTotalBytes,
            currentFileName: "Done",
            bytesPerSecond: speed,
            skippedFiles: skippedFiles,
            statusMessage: skippedFiles > 0 ? "Skipped \(skippedFiles) duplicate file\(skippedFiles == 1 ? "" : "s") already present in destination." : nil
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
            importedFiles: files,
            skippedFiles: skippedFiles
        )
    }

    private struct ImportSource {
        let url: URL
        let fileName: String
        let size: Int64
    }

    private struct ImportJob {
        let url: URL
        let destination: URL
        let size: Int64
    }

    private static func importJobs(
        fileManager: FileManager,
        destFolder: URL,
        sources: [ImportSource],
        mode: Mode
    ) -> [ImportJob] {
        var reservedFileNames = Set<String>()
        var actualReservedFileNames = Set<String>()

        return sources.compactMap { source in
            let intendedDestination = uniqueDestinationURL(
                fileManager: fileManager,
                destFolder: destFolder,
                fileName: source.fileName,
                reservedFileNames: &reservedFileNames,
                avoidExistingFiles: false
            )

            if mode == .copy,
               existingFileMatchesSource(at: intendedDestination, sourceSize: source.size, fileManager: fileManager) {
                return nil
            }

            var destination = intendedDestination
            if fileManager.fileExists(atPath: destination.path)
                || actualReservedFileNames.contains(destination.lastPathComponent.lowercased()) {
                destination = uniqueDestinationURL(
                    fileManager: fileManager,
                    destFolder: destFolder,
                    fileName: source.fileName,
                    reservedFileNames: &actualReservedFileNames,
                    avoidExistingFiles: true
                )
            } else {
                actualReservedFileNames.insert(destination.lastPathComponent.lowercased())
            }

            return ImportJob(url: source.url, destination: destination, size: source.size)
        }
    }

    private static func importJobs(
        fileManager: FileManager,
        destFolder: URL,
        sources: [ImportSource],
        mode: Mode,
        reservationCoordinator: DestinationReservationCoordinator
    ) async -> [ImportJob] {
        var jobs: [ImportJob] = []
        for source in sources {
            guard let destination = await reservationCoordinator.reserveDestination(
                fileManager: fileManager,
                destFolder: destFolder,
                fileName: source.fileName,
                sourceSize: source.size,
                mode: mode
            ) else { continue }
            jobs.append(ImportJob(url: source.url, destination: destination, size: source.size))
        }
        return jobs
    }

    private static func existingFileMatchesSource(at destination: URL, sourceSize: Int64, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: destination.path),
              let attrs = try? fileManager.attributesOfItem(atPath: destination.path),
              let size = attrs[.size] as? Int64 else { return false }
        return size == sourceSize
    }

    /// Returns a destination URL that does not yet exist or isn't already reserved for this import.
    /// If the base fileName conflicts, tries baseB.ext, baseC.ext, … until free.
    private static func uniqueDestinationURL(
        fileManager: FileManager,
        destFolder: URL,
        fileName: String,
        reservedFileNames: inout Set<String>,
        avoidExistingFiles: Bool
    ) -> URL {
        let asURL = URL(fileURLWithPath: fileName)
        let base = asURL.deletingPathExtension().lastPathComponent
        let ext = asURL.pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"

        var candidate = destFolder.appendingPathComponent(fileName)
        var n = 2
        while (avoidExistingFiles && fileManager.fileExists(atPath: candidate.path))
            || reservedFileNames.contains(candidate.lastPathComponent.lowercased()) {
            candidate = destFolder.appendingPathComponent("\(base)\(duplicateLetterSuffix(for: n))\(suffix)")
            n += 1
        }
        reservedFileNames.insert(candidate.lastPathComponent.lowercased())
        return candidate
    }

    private static func duplicateLetterSuffix(for duplicateIndex: Int) -> String {
        var value = max(duplicateIndex, 1)
        var result = ""
        while value > 0 {
            value -= 1
            let scalar = UnicodeScalar(65 + (value % 26))!
            result = String(Character(scalar)) + result
            value /= 26
        }
        return result
    }
}

actor DestinationReservationCoordinator {
    private var reservedFileNamesByFolder: [String: Set<String>] = [:]

    func reserveDestination(
        fileManager: FileManager,
        destFolder: URL,
        fileName: String,
        sourceSize: Int64,
        mode: ImportEngine.Mode
    ) -> URL? {
        var reservedFileNames = reservedFileNamesByFolder[destFolder.path] ?? []
        let intendedDestination = destFolder.appendingPathComponent(fileName)

        if mode == .copy,
           Self.existingFileMatchesSource(at: intendedDestination, sourceSize: sourceSize, fileManager: fileManager) {
            return nil
        }

        let destination: URL
        if fileManager.fileExists(atPath: intendedDestination.path)
            || reservedFileNames.contains(intendedDestination.lastPathComponent.lowercased()) {
            destination = Self.uniqueDestinationURL(
                fileManager: fileManager,
                destFolder: destFolder,
                fileName: fileName,
                reservedFileNames: &reservedFileNames,
                avoidExistingFiles: true
            )
        } else {
            destination = intendedDestination
            reservedFileNames.insert(destination.lastPathComponent.lowercased())
        }

        reservedFileNamesByFolder[destFolder.path] = reservedFileNames
        return destination
    }

    private static func existingFileMatchesSource(at destination: URL, sourceSize: Int64, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: destination.path),
              let attrs = try? fileManager.attributesOfItem(atPath: destination.path),
              let size = attrs[.size] as? Int64 else { return false }
        return size == sourceSize
    }

    private static func uniqueDestinationURL(
        fileManager: FileManager,
        destFolder: URL,
        fileName: String,
        reservedFileNames: inout Set<String>,
        avoidExistingFiles: Bool
    ) -> URL {
        let asURL = URL(fileURLWithPath: fileName)
        let base = asURL.deletingPathExtension().lastPathComponent
        let ext = asURL.pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"

        var candidate = destFolder.appendingPathComponent(fileName)
        var n = 2
        while (avoidExistingFiles && fileManager.fileExists(atPath: candidate.path))
            || reservedFileNames.contains(candidate.lastPathComponent.lowercased()) {
            candidate = destFolder.appendingPathComponent("\(base)\(duplicateLetterSuffix(for: n))\(suffix)")
            n += 1
        }
        reservedFileNames.insert(candidate.lastPathComponent.lowercased())
        return candidate
    }

    private static func duplicateLetterSuffix(for duplicateIndex: Int) -> String {
        var value = max(duplicateIndex, 1)
        var result = ""
        while value > 0 {
            value -= 1
            let scalar = UnicodeScalar(65 + (value % 26))!
            result = String(Character(scalar)) + result
            value /= 26
        }
        return result
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
    let skippedFiles: Int

    static let empty = ImportResult(
        fileCount: 0,
        totalBytes: 0,
        duration: 0,
        averageSpeed: 0,
        destinationPath: "",
        importedFiles: [],
        skippedFiles: 0
    )
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
