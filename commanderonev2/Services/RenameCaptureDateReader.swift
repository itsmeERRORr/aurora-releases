import Foundation

enum RenameCaptureDateReader {
    static func captureDates(for files: [URL]) async -> [String: Date] {
        guard !files.isEmpty,
              let exiftoolPath = findExiftool() else { return [:] }

        return await Task.detached {
            runExiftool(exiftoolPath: exiftoolPath, files: files)
        }.value
    }

    private static func findExiftool() -> String? {
        var paths: [String] = []
        if let bundled = Bundle.main.path(forResource: "exiftool", ofType: nil) {
            paths.append(bundled)
        }
        paths += ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool"]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func runExiftool(exiftoolPath: String, files: [URL]) -> [String: Date] {
        let argfilePath = NSTemporaryDirectory() + "aurora_rename_dates_\(UUID().uuidString).txt"
        let flags = [
            "-json",
            "-q",
            "-fast",
            "-m",
            "-SourceFile",
            "-DateTimeOriginal",
            "-CreateDate",
            "-DateCreated"
        ]
        let contents = (flags + files.map(\.path)).joined(separator: "\n")
        guard (try? contents.write(toFile: argfilePath, atomically: true, encoding: .utf8)) != nil else {
            return [:]
        }
        defer { try? FileManager.default.removeItem(atPath: argfilePath) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exiftoolPath)
        process.arguments = ["-@", argfilePath]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return [:]
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard !data.isEmpty,
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }

        var datesByPath: [String: Date] = [:]
        for row in rows {
            guard let path = row["SourceFile"] as? String else { continue }
            let rawDate = row["DateTimeOriginal"] as? String
                ?? row["CreateDate"] as? String
                ?? row["DateCreated"] as? String
            guard let rawDate,
                  let date = parseExifDate(rawDate) else { continue }
            datesByPath[path] = date
        }
        return datesByPath
    }

    private static func parseExifDate(_ rawValue: String) -> Date? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        let formats = [
            "yyyy:MM:dd HH:mm:ss.SSSXXXXX",
            "yyyy:MM:dd HH:mm:ssXXXXX",
            "yyyy:MM:dd HH:mm:ss.SSS",
            "yyyy:MM:dd HH:mm:ss",
            "yyyy-MM-dd HH:mm:ssXXXXX",
            "yyyy-MM-dd HH:mm:ss"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }

        return nil
    }
}
