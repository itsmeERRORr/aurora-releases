import Foundation

@MainActor
final class StatsRunner {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func runStats(importedFiles: [String], destinationPath: String, duration: TimeInterval) async {
        appState.log("Starting EXIF stats analysis...")

        // Calculate total bytes
        let totalBytes = await Task.detached {
            Self.calculateTotalBytes(files: importedFiles)
        }.value

        // Write file list for compatibility with existing workflow
        let fileListContent = importedFiles.joined(separator: "\n")
        let fileListPath = NSTemporaryDirectory() + "last_import_files.txt"
        try? fileListContent.write(toFile: fileListPath, atomically: true, encoding: .utf8)

        let docsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
            .appendingPathComponent("exif_report_final")
        try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        let docsFileList = docsDir.appendingPathComponent("last_import_files.txt")
        try? fileListContent.write(to: docsFileList, atomically: true, encoding: .utf8)

        let exiftoolPath = findExiftool()

        if let exiftoolPath {
            appState.log("Using exiftool at: \(exiftoolPath)")
            appState.log("Scanning destination: \(destinationPath)")
            appState.log("Processing \(importedFiles.count) imported files")

            // Run exiftool OFF the main thread to avoid blocking UI
            var report = await Task.detached {
                Self.runExiftoolStats(
                    exiftoolPath: exiftoolPath,
                    files: importedFiles,
                    destinationPath: destinationPath
                )
            }.value

            report.totalBytes = totalBytes
            report.totalDuration = Int(duration)
            report.firstImportDate = Date()
            appState.statsReport = report
            appState.log("Stats complete: \(report.totalFilesAnalyzed) files analyzed")

            if report.totalFilesAnalyzed == 0 {
                appState.log("⚠️ No files analyzed - check that exiftool can read your RAW files", level: .warning)
            } else {
                appState.log("✅ Stats: \(report.topLenses.count) lenses, ISO avg: \(report.avgISO.map { String(format: "%.0f", $0) } ?? "N/A")")
            }
        } else {
            appState.log("exiftool not found, using mdls fallback", level: .warning)

            var report = await Task.detached {
                Self.runMdlsStats(files: importedFiles)
            }.value

            report.totalBytes = totalBytes
            report.totalDuration = Int(duration)
            report.firstImportDate = Date()
            appState.statsReport = report
            appState.log("Stats complete (mdls): \(report.totalFilesAnalyzed) files analyzed")
        }
    }

    /// Run EXIF stats for files in an event folder. Returns the report without updating appState.
    /// Uses exiftool -r (recursive) to avoid ARG_MAX limits and unnecessary file-listing on NAS.
    func runStatsForEventFolder(at url: URL) async -> StatsReport? {
        let extensions = appState.supportedExtensions

        guard let exiftoolPath = findExiftool() else {
            // Fallback: list files manually and use mdls (limited metadata, max 200 files)
            let fileURLs = VolumeWatcher.listRawFiles(at: url, extensions: extensions)
            let filePaths = fileURLs.map(\.path)
            guard !filePaths.isEmpty else { return nil }
            var report = await Task.detached {
                Self.runMdlsStats(files: Array(filePaths.prefix(200)))
            }.value
            // Skip totalBytes calculation for fallback - too slow
            report.totalBytes = 0
            report.totalDuration = 0
            report.firstImportDate = nil
            return report
        }

        let report = await Task.detached {
            Self.runExiftoolStatsForFolder(
                exiftoolPath: exiftoolPath,
                folderURL: url,
                extensions: extensions
            )
        }.value

        var r = report

        // Skip totalBytes calculation - it's too slow for large NAS folders
        r.totalBytes = 0
        r.totalDuration = 0
        r.firstImportDate = nil
        guard r.totalFilesAnalyzed > 0 else { return nil }
        return r
    }

    private func findExiftool() -> String? {
        let paths = ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool"]
        for p in paths {
            if FileManager.default.fileExists(atPath: p) {
                return p
            }
        }
        return nil
    }

    // MARK: - Static methods (run off main thread)

    private nonisolated static func calculateTotalBytes(files: [String]) -> Int64 {
        var totalBytes: Int64 = 0
        for file in files {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file),
               let fileSize = attrs[.size] as? Int64 {
                totalBytes += fileSize
            }
        }
        return totalBytes
    }

    private nonisolated static func calculateTotalBytesForFolder(at url: URL, extensions: Set<String>) -> Int64 {
        var totalBytes: Int64 = 0
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        for case let fileURL as URL in enumerator {
            guard let ext = fileURL.pathExtension.lowercased() as String?,
                  extensions.contains(ext) else { continue }
            guard let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  attrs.isRegularFile == true,
                  let fileSize = attrs.fileSize else { continue }
            totalBytes += Int64(fileSize)
        }
        return totalBytes
    }

    /// Runs exiftool recursively on a folder. Avoids ARG_MAX limits and is far more efficient
    /// on NAS/slow volumes than passing tens of thousands of individual file paths.
    private nonisolated static func runExiftoolStatsForFolder(
        exiftoolPath: String,
        folderURL: URL,
        extensions: Set<String>
    ) -> StatsReport {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exiftoolPath)

        // Build extension filter - include RAW extensions only
        // Use both lowercase and uppercase versions to handle all cases
        var extArgs: [String] = []
        for ext in extensions.sorted() {
            extArgs += ["-ext", ext.lowercased(), "-ext", ext.uppercased()]
        }

        // Create a temporary filelist with only RAW files to avoid exiftool processing non-RAW files
        let fm = FileManager.default
        var rawFiles: [String] = []
        let lowercaseExtensions = extensions.map { $0.lowercased() }
        if let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                if lowercaseExtensions.contains(ext) {
                    rawFiles.append(fileURL.path)
                }
            }
        }
        
        var arguments: [String]
        var filelistPath: String?
        if !rawFiles.isEmpty {
            // Write an argfile for exiftool (-@ flag): flags first, then file paths, one per line.
            // This is the correct way to pass a large file list without hitting ARG_MAX.
            filelistPath = NSTemporaryDirectory() + "exiftool_argfile_\(UUID().uuidString).txt"
            let flags = [
                "-json",
                "-q",
                "-fast",
                "-m",
                "-ignoreMinorErrors",
                "-LensModel", "-LensID",
                "-Make", "-Model",
                "-ExposureTime", "-ShutterSpeedValue",
                "-FocalLength", "-FNumber", "-ISO",
                "-DateTimeOriginal", "-CreateDate", "-DateCreated"
            ]
            let argfileContents = (flags + rawFiles).joined(separator: "\n")
            try? argfileContents.write(toFile: filelistPath!, atomically: true, encoding: .utf8)
            arguments = ["-@", filelistPath!]
        } else {
            // No RAW files found - return empty result without running exiftool
            return StatsReport(topLenses: [], mostUsedCamera: nil, shutterSpeeds: [], totalFilesAnalyzed: 0, rawOutput: "No RAW files found in folder", avgISO: nil, avgAperture: nil, avgFocalLength: nil, lensCounts: [:], cameraCounts: [:], shutterCounts: [:], isoSum: 0, isoCount: 0, apertureSum: 0, apertureCount: 0, focalSum: 0, focalCount: 0, monthCounts: [:], weekCounts: [:], yearCounts: [:])
        }

        process.arguments = arguments

        let stdoutPipe = Pipe()
        // Discard stderr entirely — avoids the classic two-pipe deadlock where exiftool fills
        // the 64 KB stderr kernel buffer while we are still blocked reading stdout.
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return StatsReport(topLenses: [], mostUsedCamera: nil, shutterSpeeds: [], totalFilesAnalyzed: 0, rawOutput: "exiftool launch error: \(error)", avgISO: nil, avgAperture: nil, avgFocalLength: nil, lensCounts: [:], cameraCounts: [:], shutterCounts: [:], isoSum: 0, isoCount: 0, apertureSum: 0, apertureCount: 0, focalSum: 0, focalCount: 0, monthCounts: [:], weekCounts: [:], yearCounts: [:])
        }

        // Safety timeout: kill exiftool if it hangs on a network file (e.g. NAS with a bad file).
        // 10 minutes should be generous even for very large NAS folders.
        let timeoutSeconds: Double = 600
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds) {
            if process.isRunning { process.terminate() }
        }

        // Read all stdout data. Since stderr is /dev/null there is no second pipe to deadlock on.
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let exitCode = process.terminationStatus

        // Clean up temp filelist if used
        if let path = filelistPath {
            try? FileManager.default.removeItem(atPath: path)
        }

        let rawOutput = String(data: stdoutData, encoding: .utf8) ?? ""

        if rawOutput.isEmpty {
            return StatsReport(topLenses: [], mostUsedCamera: nil, shutterSpeeds: [], totalFilesAnalyzed: 0, rawOutput: "exiftool empty output (exit \(exitCode))", avgISO: nil, avgAperture: nil, avgFocalLength: nil, lensCounts: [:], cameraCounts: [:], shutterCounts: [:], isoSum: 0, isoCount: 0, apertureSum: 0, apertureCount: 0, focalSum: 0, focalCount: 0, monthCounts: [:], weekCounts: [:], yearCounts: [:])
        }

        return parseExiftoolJSON(rawOutput, fileCount: rawFiles.count)
    }

    private nonisolated static func runExiftoolStats(exiftoolPath: String, files: [String], destinationPath: String) -> StatsReport {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exiftoolPath)

        // Build arguments: exiftool -json [fields] file1 file2 file3...
        var arguments = [
            "-json",
            "-LensModel", "-LensID",
            "-Make", "-Model",
            "-ExposureTime", "-ShutterSpeedValue",
            "-FocalLength", "-FNumber", "-ISO",
            "-DateTimeOriginal", "-CreateDate", "-DateCreated"
        ]

        // Add all imported files as arguments
        arguments.append(contentsOf: files)

        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return StatsReport(topLenses: [], mostUsedCamera: nil, shutterSpeeds: [], totalFilesAnalyzed: 0, rawOutput: "exiftool launch error: \(error)", avgISO: nil, avgAperture: nil, avgFocalLength: nil, lensCounts: [:], cameraCounts: [:], shutterCounts: [:], isoSum: 0, isoCount: 0, apertureSum: 0, apertureCount: 0, focalSum: 0, focalCount: 0, monthCounts: [:], weekCounts: [:], yearCounts: [:])
        }

        // IMPORTANT: Read pipe data BEFORE waitUntilExit to avoid deadlock.
        // If the pipe buffer fills up (64KB), the child process blocks on write,
        // and waitUntilExit would wait forever.
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()
        let exitCode = process.terminationStatus

        let rawOutput = String(data: stdoutData, encoding: .utf8) ?? ""
        let errOutput = String(data: stderrData, encoding: .utf8) ?? ""

        if rawOutput.isEmpty {
            return StatsReport(topLenses: [], mostUsedCamera: nil, shutterSpeeds: [], totalFilesAnalyzed: 0, rawOutput: "exiftool empty output. exit=\(exitCode) stderr: \(errOutput.prefix(300))", avgISO: nil, avgAperture: nil, avgFocalLength: nil, lensCounts: [:], cameraCounts: [:], shutterCounts: [:], isoSum: 0, isoCount: 0, apertureSum: 0, apertureCount: 0, focalSum: 0, focalCount: 0, monthCounts: [:], weekCounts: [:], yearCounts: [:])
        }

        return parseExiftoolJSON(rawOutput, fileCount: files.count)
    }

    private nonisolated static func parseExiftoolJSON(_ json: String, fileCount: Int) -> StatsReport {
        guard let data = json.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return StatsReport(topLenses: [], mostUsedCamera: nil, shutterSpeeds: [], totalFilesAnalyzed: 0, rawOutput: "JSON parse failed. Raw: \(json.prefix(500))", avgISO: nil, avgAperture: nil, avgFocalLength: nil, lensCounts: [:], cameraCounts: [:], shutterCounts: [:], isoSum: 0, isoCount: 0, apertureSum: 0, apertureCount: 0, focalSum: 0, focalCount: 0, monthCounts: [:], weekCounts: [:], yearCounts: [:])
        }

        var lensCounts: [String: Int] = [:]
        var cameraCounts: [String: Int] = [:]
        var shutterCounts: [Double: Int] = [:]
        var monthCounts: [String: Int] = [:]
        var weekCounts: [String: Int] = [:]
        var yearCounts: [String: Int] = [:]
        var isoSum = 0.0
        var isoCount = 0
        var maxISO: Double?
        var minISO: Double?
        var apertureSum = 0.0
        var apertureCount = 0
        var maxAperture: Double?
        var minAperture: Double?
        var focalSum = 0.0
        var focalCount = 0
        var maxFocalLength: Double?
        var minFocalLength: Double?
        var maxShutterSpeed: Double?
        var minShutterSpeed: Double?

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss" // exiftool format
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM yyyy"
        let isoCalendar = Calendar(identifier: .iso8601)

        // Helper: returns true for "---", "----", etc. (Sony no-lens accidental shots)
        let isNoLens: (String) -> Bool = { model in
            let trimmed = model.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && trimmed.allSatisfy { $0 == "-" }
        }

        for entry in entries {
            let make = entry["Make"] as? String ?? ""

            // Skip photos taken without a lens entirely (Sony --- accidental shots)
            // These have LensModel consisting entirely of dashes
            if let lens = entry["LensModel"] as? String, isNoLens(lens) {
                continue
            }
            if let lensID = entry["LensID"] as? String, isNoLens(lensID) {
                continue
            }

            // Store lens with make|model format
            if let lens = entry["LensModel"] as? String, !lens.isEmpty, lens != "Unknown" {
                let key = "\(make)|\(lens)"
                lensCounts[key, default: 0] += 1
            } else if let lensID = entry["LensID"] as? String, !lensID.isEmpty, lensID != "Unknown" {
                let key = "\(make)|\(lensID)"
                lensCounts[key, default: 0] += 1
            }

            let model = entry["Model"] as? String ?? ""
            if !model.isEmpty {
                let key = "\(make)|\(model)"
                cameraCounts[key, default: 0] += 1
            }

            let shutterValue: Double? = {
                if let val = entry["ExposureTime"] as? Double {
                    return val
                }
                if let str = entry["ExposureTime"] as? String {
                    return parseFraction(str)
                }
                if let val = entry["ShutterSpeedValue"] as? Double {
                    return 1.0 / pow(2.0, val)
                }
                if let str = entry["ShutterSpeedValue"] as? String {
                    return parseFraction(str)
                }
                return nil
            }()

            if let shutter = shutterValue {
                let rounded = (shutter * 10000).rounded() / 10000
                shutterCounts[rounded, default: 0] += 1
                maxShutterSpeed = max(maxShutterSpeed ?? shutter, shutter)
                minShutterSpeed = min(minShutterSpeed ?? shutter, shutter)
            }

            // ISO
            if let iso = entry["ISO"] as? Int {
                let isoDouble = Double(iso)
                isoSum += isoDouble
                isoCount += 1
                maxISO = max(maxISO ?? isoDouble, isoDouble)
                minISO = min(minISO ?? isoDouble, isoDouble)
            } else if let isoStr = entry["ISO"] as? String, let iso = Int(isoStr) {
                let isoDouble = Double(iso)
                isoSum += isoDouble
                isoCount += 1
                maxISO = max(maxISO ?? isoDouble, isoDouble)
                minISO = min(minISO ?? isoDouble, isoDouble)
            }

            // Aperture (FNumber) — skip 0 (no-lens shots report FNumber=0)
            if let fnum = entry["FNumber"] as? Double, fnum > 0 {
                apertureSum += fnum
                apertureCount += 1
                maxAperture = max(maxAperture ?? fnum, fnum)
                minAperture = min(minAperture ?? fnum, fnum)
            } else if let fnumStr = entry["FNumber"] as? String, let fnum = Double(fnumStr), fnum > 0 {
                apertureSum += fnum
                apertureCount += 1
                maxAperture = max(maxAperture ?? fnum, fnum)
                minAperture = min(minAperture ?? fnum, fnum)
            }

            // Focal Length — skip 0 (no-lens shots report FocalLength=0)
            if let focal = entry["FocalLength"] as? Double, focal > 0 {
                focalSum += focal
                focalCount += 1
                maxFocalLength = max(maxFocalLength ?? focal, focal)
                minFocalLength = min(minFocalLength ?? focal, focal)
            } else if let focalStr = entry["FocalLength"] as? String {
                // Parse "24.0 mm" -> 24.0
                let cleaned = focalStr.replacingOccurrences(of: " mm", with: "").trimmingCharacters(in: .whitespaces)
                if let focal = Double(cleaned), focal > 0 {
                    focalSum += focal
                    focalCount += 1
                    maxFocalLength = max(maxFocalLength ?? focal, focal)
                    minFocalLength = min(minFocalLength ?? focal, focal)
                }
            }

            // Date Taken (try multiple date fields)
            var dateFound = false

            // Try DateTimeOriginal first (most common for photos)
            if let dateStr = entry["DateTimeOriginal"] as? String {
                #if DEBUG
                if monthCounts.isEmpty {
                    print("StatsRunner: First DateTimeOriginal found: '\(dateStr)'")
                }
                #endif
                if let date = dateFormatter.date(from: dateStr) {
                    let monthKey = monthFormatter.string(from: date)
                    monthCounts[monthKey, default: 0] += 1
                    let weekOfYear = isoCalendar.component(.weekOfYear, from: date)
                    let weekYear = isoCalendar.component(.yearForWeekOfYear, from: date)
                    let weekKey = String(format: "%d-W%02d", weekYear, weekOfYear)
                    weekCounts[weekKey, default: 0] += 1
                    let yearKey = String(isoCalendar.component(.year, from: date))
                    yearCounts[yearKey, default: 0] += 1
                    dateFound = true
                }
            }

            // Try CreateDate as fallback
            if !dateFound, let dateStr = entry["CreateDate"] as? String {
                #if DEBUG
                if monthCounts.isEmpty {
                    print("StatsRunner: First CreateDate found: '\(dateStr)'")
                }
                #endif
                if let date = dateFormatter.date(from: dateStr) {
                    let monthKey = monthFormatter.string(from: date)
                    monthCounts[monthKey, default: 0] += 1
                    let weekOfYear = isoCalendar.component(.weekOfYear, from: date)
                    let weekYear = isoCalendar.component(.yearForWeekOfYear, from: date)
                    let weekKey = String(format: "%d-W%02d", weekYear, weekOfYear)
                    weekCounts[weekKey, default: 0] += 1
                    let yearKey = String(isoCalendar.component(.year, from: date))
                    yearCounts[yearKey, default: 0] += 1
                    dateFound = true
                }
            }

            // Try DateCreated as another fallback
            if !dateFound, let dateStr = entry["DateCreated"] as? String {
                if let date = dateFormatter.date(from: dateStr) {
                    let monthKey = monthFormatter.string(from: date)
                    monthCounts[monthKey, default: 0] += 1
                    let weekOfYear = isoCalendar.component(.weekOfYear, from: date)
                    let weekYear = isoCalendar.component(.yearForWeekOfYear, from: date)
                    let weekKey = String(format: "%d-W%02d", weekYear, weekOfYear)
                    weekCounts[weekKey, default: 0] += 1
                    let yearKey = String(isoCalendar.component(.year, from: date))
                    yearCounts[yearKey, default: 0] += 1
                    dateFound = true
                }
            }

            #if DEBUG
            if !dateFound && monthCounts.isEmpty {
                // Print all date-related keys for first entry to debug
                let dateKeys = entry.keys.filter { $0.lowercased().contains("date") || $0.lowercased().contains("time") }
                if !dateKeys.isEmpty {
                    print("StatsRunner: Available date keys in first entry: \(dateKeys)")
                    for key in dateKeys {
                        print("  - \(key): \(entry[key] ?? "nil")")
                    }
                }
            }
            #endif
        }

        #if DEBUG
        print("StatsRunner: Extracted \(monthCounts.count) unique months from \(entries.count) photos")
        if !monthCounts.isEmpty {
            print("StatsRunner: Month distribution: \(monthCounts)")
        } else {
            print("StatsRunner: WARNING - No dates were extracted from any photo!")
        }
        #endif

        let sortedLenses = lensCounts.sorted { $0.value > $1.value }
        let topLenses = sortedLenses.prefix(3).enumerated().map { idx, pair in
            let parts = pair.key.split(separator: "|", maxSplits: 1)
            return StatsReport.LensStat(
                make: String(parts.first ?? ""),
                model: String(parts.last ?? ""),
                count: pair.value,
                rank: idx + 1
            )
        }

        let topCamera = cameraCounts.max(by: { $0.value < $1.value })
        let cameraStat: StatsReport.CameraStat?
        if let topCamera {
            let parts = topCamera.key.split(separator: "|", maxSplits: 1)
            cameraStat = StatsReport.CameraStat(
                make: String(parts.first ?? ""),
                model: String(parts.last ?? ""),
                count: topCamera.value
            )
        } else {
            cameraStat = nil
        }

        let sortedShutters = shutterCounts.sorted { $0.value > $1.value }
        let topShutters = sortedShutters.prefix(5).map { pair in
            StatsReport.ShutterStat(rawValue: pair.key, count: pair.value)
        }

        let avgISO = isoCount > 0 ? isoSum / Double(isoCount) : nil
        let avgAperture = apertureCount > 0 ? apertureSum / Double(apertureCount) : nil
        let avgFocalLength = focalCount > 0 ? focalSum / Double(focalCount) : nil

        return StatsReport(
            topLenses: topLenses,
            mostUsedCamera: cameraStat,
            shutterSpeeds: topShutters,
            totalFilesAnalyzed: entries.count,
            rawOutput: String(json.prefix(2000)),
            avgISO: avgISO,
            maxISO: maxISO,
            minISO: minISO,
            avgAperture: avgAperture,
            maxAperture: maxAperture,
            minAperture: minAperture,
            avgFocalLength: avgFocalLength,
            maxFocalLength: maxFocalLength,
            minFocalLength: minFocalLength,
            lensCounts: lensCounts,
            cameraCounts: cameraCounts,
            shutterCounts: shutterCounts,
            maxShutterSpeed: maxShutterSpeed,
            minShutterSpeed: minShutterSpeed,
            isoSum: isoSum,
            isoCount: isoCount,
            apertureSum: apertureSum,
            apertureCount: apertureCount,
            focalSum: focalSum,
            focalCount: focalCount,
            monthCounts: monthCounts,
            weekCounts: weekCounts,
            yearCounts: yearCounts
        )
    }

    private nonisolated static func parseFraction(_ str: String) -> Double? {
        if str.contains("/") {
            let parts = str.split(separator: "/")
            if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den != 0 {
                return num / den
            }
        }
        return Double(str)
    }

    private nonisolated static func runMdlsStats(files: [String]) -> StatsReport {
        var cameraCounts: [String: Int] = [:]

        for file in files.prefix(200) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
            process.arguments = ["-name", "kMDItemAcquisitionMake", "-name", "kMDItemAcquisitionModel", file]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                var make = ""
                var model = ""
                for line in output.components(separatedBy: "\n") {
                    if line.contains("kMDItemAcquisitionMake") {
                        make = extractMdlsValue(line)
                    }
                    if line.contains("kMDItemAcquisitionModel") {
                        model = extractMdlsValue(line)
                    }
                }

                if !model.isEmpty {
                    cameraCounts["\(make)|\(model)", default: 0] += 1
                }
            } catch {
                continue
            }
        }

        let topCamera = cameraCounts.max(by: { $0.value < $1.value })
        let cameraStat: StatsReport.CameraStat?
        if let topCamera {
            let parts = topCamera.key.split(separator: "|", maxSplits: 1)
            cameraStat = StatsReport.CameraStat(
                make: String(parts.first ?? ""),
                model: String(parts.last ?? ""),
                count: topCamera.value
            )
        } else {
            cameraStat = nil
        }

        return StatsReport(
            topLenses: [],
            mostUsedCamera: cameraStat,
            shutterSpeeds: [],
            totalFilesAnalyzed: files.count,
            rawOutput: "(mdls fallback - limited data)",
            avgISO: nil,
            avgAperture: nil,
            avgFocalLength: nil,
            lensCounts: [:],
            cameraCounts: cameraCounts,
            shutterCounts: [:],
            isoSum: 0,
            isoCount: 0,
            apertureSum: 0,
            apertureCount: 0,
            focalSum: 0,
            focalCount: 0,
            monthCounts: [:],
            weekCounts: [:],
            yearCounts: [:]
        )
    }

    private nonisolated static func extractMdlsValue(_ line: String) -> String {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return "" }
        return parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
    }
}
