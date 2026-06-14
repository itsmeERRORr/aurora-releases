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
                "-FocalLength", "-FNumber",
                // ISO + Sony's alternate ISO fields. On Sony bodies the EXIF
                // `ISO` tag can be capped at a reference value (often 400)
                // while the real ISO used is written to ISOSpeed or
                // RecommendedExposureIndex (SensitivityType=3). Read all
                // three plus Sony MakerNote variants so the parser can pick
                // the largest as the effective ISO.
                "-ISO", "-ISOSpeed", "-RecommendedExposureIndex", "-ISOSetting", "-SonyISO",
                "-ImageWidth", "-ImageHeight", "-ExifImageWidth", "-ExifImageHeight", "-Orientation",
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
            "-FocalLength", "-FNumber",
            // See the bulk-scan path for why we read all three ISO-ish tags
            // (Sony writes the real ISO to RecommendedExposureIndex when the
            // standard ISO field is capped at a reference value).
            "-ISO", "-ISOSpeed", "-RecommendedExposureIndex", "-ISOSetting", "-SonyISO",
            "-ImageWidth", "-ImageHeight", "-ExifImageWidth", "-ExifImageHeight", "-Orientation",
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
        var isoCounts: [String: Int] = [:]
        var apertureCounts: [String: Int] = [:]
        var focalCounts: [String: Int] = [:]
        var orientationCounts: [String: Int] = [:]
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
            let lower = trimmed.lowercased()
            return (!trimmed.isEmpty && trimmed.allSatisfy { $0 == "-" }) || lower.contains("no lens")
        }

        for entry in entries {
            let make = entry["Make"] as? String ?? ""
            let lensModel = entry["LensModel"] as? String
            let lensID = entry["LensID"] as? String
            let hasNoLens = [lensModel, lensID].compactMap { $0 }.contains(where: isNoLens)

            // Store lens with make|model format. No-lens shots still carry useful
            // camera, ISO, shutter and date data, so only exclude them from lens stats.
            if let lens = lensModel, !hasNoLens, !lens.isEmpty, lens != "Unknown" {
                let key = "\(make)|\(lens)"
                lensCounts[key, default: 0] += 1
            } else if let lensID, !hasNoLens, !lensID.isEmpty, lensID != "Unknown" {
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

            if let orientation = Self.imageOrientation(from: entry) {
                orientationCounts[orientation, default: 0] += 1
            }

            // ISO — take the largest of ISO / ISOSpeed / RecommendedExposureIndex
            // plus Sony MakerNote variants.
            // Sony bodies cap the standard `ISO` tag at a reference value
            // (often 400) for shots taken with SensitivityType=3 and write
            // the real ISO into RecommendedExposureIndex; ISOSpeed is the
            // EXIF 2.3 canonical field. We pick the max so a single capped
            // tag doesn't pull the highest-ISO stat down to the reference.
            if let iso = Self.effectiveISO(from: entry) {
                isoSum += iso
                isoCount += 1
                isoCounts[String(Int(iso.rounded())), default: 0] += 1
                maxISO = max(maxISO ?? iso, iso)
                minISO = min(minISO ?? iso, iso)
            }

            // Aperture (FNumber) — skip 0 (no-lens shots report FNumber=0)
            if let fnum = entry["FNumber"] as? Double, fnum > 0 {
                apertureSum += fnum
                apertureCount += 1
                apertureCounts[Self.histogramKey(fnum, decimals: 1), default: 0] += 1
                maxAperture = max(maxAperture ?? fnum, fnum)
                minAperture = min(minAperture ?? fnum, fnum)
            } else if let fnumStr = entry["FNumber"] as? String, let fnum = Double(fnumStr), fnum > 0 {
                apertureSum += fnum
                apertureCount += 1
                apertureCounts[Self.histogramKey(fnum, decimals: 1), default: 0] += 1
                maxAperture = max(maxAperture ?? fnum, fnum)
                minAperture = min(minAperture ?? fnum, fnum)
            }

            // Focal Length — skip 0 (no-lens shots report FocalLength=0)
            if let focal = entry["FocalLength"] as? Double, focal > 0 {
                focalSum += focal
                focalCount += 1
                focalCounts[String(Int(focal.rounded())), default: 0] += 1
                maxFocalLength = max(maxFocalLength ?? focal, focal)
                minFocalLength = min(minFocalLength ?? focal, focal)
            } else if let focalStr = entry["FocalLength"] as? String {
                // Parse "24.0 mm" -> 24.0
                let cleaned = focalStr.replacingOccurrences(of: " mm", with: "").trimmingCharacters(in: .whitespaces)
                if let focal = Double(cleaned), focal > 0 {
                    focalSum += focal
                    focalCount += 1
                    focalCounts[String(Int(focal.rounded())), default: 0] += 1
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
            isoCounts: isoCounts,
            apertureCounts: apertureCounts,
            focalCounts: focalCounts,
            orientationCounts: orientationCounts,
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

    private nonisolated static func histogramKey(_ value: Double, decimals: Int) -> String {
        String(format: "%.*f", decimals, value)
    }

    private nonisolated static func imageOrientation(from entry: [String: Any]) -> String? {
        let width = parseDimensionField(entry["ImageWidth"]) ?? parseDimensionField(entry["ExifImageWidth"])
        let height = parseDimensionField(entry["ImageHeight"]) ?? parseDimensionField(entry["ExifImageHeight"])
        guard var width, var height, width > 0, height > 0 else { return nil }

        if orientationRotatesDimensions(entry["Orientation"]) {
            swap(&width, &height)
        }

        if height > width { return "portrait" }
        if width > height { return "landscape" }
        return "square"
    }

    private nonisolated static func orientationRotatesDimensions(_ value: Any?) -> Bool {
        if let intValue = value as? Int { return [5, 6, 7, 8].contains(intValue) }
        if let doubleValue = value as? Double { return [5, 6, 7, 8].contains(Int(doubleValue)) }
        guard let string = value as? String else { return false }
        let lower = string.lowercased()
        if lower.contains("90") || lower.contains("270") || lower.contains("rotate cw") || lower.contains("rotate ccw") {
            return true
        }
        if let numeric = Int(lower.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return [5, 6, 7, 8].contains(numeric)
        }
        return false
    }

    private nonisolated static func parseDimensionField(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d.rounded()) }
        guard let s = value as? String else { return nil }
        let digits = s.prefix { $0.isNumber }
        return Int(digits)
    }

    /// Reads an integer-ish exiftool JSON field that may be Int, Double, or String.
    private nonisolated static func parseISOField(_ value: Any?) -> Double? {
        if let i = value as? Int { return Double(i) }
        if let d = value as? Double { return d }
        if let array = value as? [Any] { return array.compactMap(parseISOField).max() }
        guard let s = value as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = Double(trimmed.replacingOccurrences(of: ",", with: "")) { return d }

        var token = ""
        for char in trimmed {
            if char.isNumber || char == "." || char == "," {
                token.append(char)
            } else if !token.isEmpty {
                break
            }
        }
        return Double(token.replacingOccurrences(of: ",", with: ""))
    }

    /// Returns the effective ISO for a photo, picking the max across the three
    /// ISO-related EXIF tags Sony bodies may write to. Returns nil if none are
    /// present or all are <= 0.
    private nonisolated static func effectiveISO(from entry: [String: Any]) -> Double? {
        let candidates = [
            parseISOField(entry["ISO"]),
            parseISOField(entry["ISOSpeed"]),
            parseISOField(entry["RecommendedExposureIndex"]),
            parseISOField(entry["ISOSetting"]),
            parseISOField(entry["SonyISO"])
        ].compactMap { $0 }.filter { $0 > 0 }
        return candidates.max()
    }

    private nonisolated static func runMdlsStats(files: [String]) -> StatsReport {
        var cameraCounts: [String: Int] = [:]
        var shutterCounts: [Double: Int] = [:]
        var isoCounts: [String: Int] = [:]
        var apertureCounts: [String: Int] = [:]
        var focalCounts: [String: Int] = [:]
        var orientationCounts: [String: Int] = [:]
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
        var analyzedCount = 0

        for file in files.prefix(200) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
            process.arguments = [
                "-name", "kMDItemAcquisitionMake",
                "-name", "kMDItemAcquisitionModel",
                "-name", "kMDItemISOSpeed",
                "-name", "kMDItemExposureTimeSeconds",
                "-name", "kMDItemFNumber",
                "-name", "kMDItemFocalLength",
                "-name", "kMDItemPixelWidth",
                "-name", "kMDItemPixelHeight",
                "-name", "kMDItemOrientation",
                file
            ]
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
                var entry: [String: Any] = [:]
                for line in output.components(separatedBy: "\n") {
                    if line.contains("kMDItemAcquisitionMake") {
                        make = extractMdlsValue(line)
                    }
                    if line.contains("kMDItemAcquisitionModel") {
                        model = extractMdlsValue(line)
                    }
                    if let key = mdlsKey(from: line) {
                        entry[key] = extractMdlsValue(line)
                    }
                }

                analyzedCount += 1

                if !model.isEmpty {
                    cameraCounts["\(make)|\(model)", default: 0] += 1
                }

                if let iso = parseMdlsDouble(entry["kMDItemISOSpeed"]), iso > 0 {
                    isoSum += iso
                    isoCount += 1
                    isoCounts[String(Int(iso.rounded())), default: 0] += 1
                    maxISO = max(maxISO ?? iso, iso)
                    minISO = min(minISO ?? iso, iso)
                }

                if let shutter = parseMdlsDouble(entry["kMDItemExposureTimeSeconds"]), shutter > 0 {
                    let rounded = (shutter * 10000).rounded() / 10000
                    shutterCounts[rounded, default: 0] += 1
                    maxShutterSpeed = max(maxShutterSpeed ?? shutter, shutter)
                    minShutterSpeed = min(minShutterSpeed ?? shutter, shutter)
                }

                if let aperture = parseMdlsDouble(entry["kMDItemFNumber"]), aperture > 0 {
                    apertureSum += aperture
                    apertureCount += 1
                    apertureCounts[Self.histogramKey(aperture, decimals: 1), default: 0] += 1
                    maxAperture = max(maxAperture ?? aperture, aperture)
                    minAperture = min(minAperture ?? aperture, aperture)
                }

                if let focal = parseMdlsDouble(entry["kMDItemFocalLength"]), focal > 0 {
                    focalSum += focal
                    focalCount += 1
                    focalCounts[String(Int(focal.rounded())), default: 0] += 1
                    maxFocalLength = max(maxFocalLength ?? focal, focal)
                    minFocalLength = min(minFocalLength ?? focal, focal)
                }

                if let orientation = mdlsImageOrientation(from: entry) {
                    orientationCounts[orientation, default: 0] += 1
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

        let sortedShutters = shutterCounts.sorted { $0.value > $1.value }
        let topShutters = sortedShutters.prefix(5).map { pair in
            StatsReport.ShutterStat(rawValue: pair.key, count: pair.value)
        }

        let avgISO = isoCount > 0 ? isoSum / Double(isoCount) : nil
        let avgAperture = apertureCount > 0 ? apertureSum / Double(apertureCount) : nil
        let avgFocalLength = focalCount > 0 ? focalSum / Double(focalCount) : nil

        return StatsReport(
            topLenses: [],
            mostUsedCamera: cameraStat,
            shutterSpeeds: topShutters,
            totalFilesAnalyzed: analyzedCount,
            rawOutput: "(mdls fallback - limited data)",
            avgISO: avgISO,
            maxISO: maxISO,
            minISO: minISO,
            avgAperture: avgAperture,
            maxAperture: maxAperture,
            minAperture: minAperture,
            avgFocalLength: avgFocalLength,
            maxFocalLength: maxFocalLength,
            minFocalLength: minFocalLength,
            lensCounts: [:],
            cameraCounts: cameraCounts,
            shutterCounts: shutterCounts,
            isoCounts: isoCounts,
            apertureCounts: apertureCounts,
            focalCounts: focalCounts,
            orientationCounts: orientationCounts,
            maxShutterSpeed: maxShutterSpeed,
            minShutterSpeed: minShutterSpeed,
            isoSum: isoSum,
            isoCount: isoCount,
            apertureSum: apertureSum,
            apertureCount: apertureCount,
            focalSum: focalSum,
            focalCount: focalCount,
            monthCounts: [:],
            weekCounts: [:],
            yearCounts: [:]
        )
    }

    private nonisolated static func mdlsKey(from line: String) -> String? {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func parseMdlsDouble(_ value: Any?) -> Double? {
        guard let value = value as? String else { return nil }
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
        guard cleaned != "(null)", cleaned != "null" else { return nil }
        if let direct = Double(cleaned) { return direct }
        return parseFraction(cleaned)
    }

    private nonisolated static func mdlsImageOrientation(from entry: [String: Any]) -> String? {
        guard let width = parseMdlsDouble(entry["kMDItemPixelWidth"]),
              let height = parseMdlsDouble(entry["kMDItemPixelHeight"]),
              width > 0,
              height > 0 else { return nil }
        let rotated = orientationRotatesDimensions(entry["kMDItemOrientation"])
        let effectiveWidth = rotated ? height : width
        let effectiveHeight = rotated ? width : height
        if effectiveHeight > effectiveWidth { return "portrait" }
        if effectiveWidth > effectiveHeight { return "landscape" }
        return "square"
    }

    private nonisolated static func extractMdlsValue(_ line: String) -> String {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return "" }
        return parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
    }
}
