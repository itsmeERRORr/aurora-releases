import Foundation
import AppKit
import ImageIO
import CryptoKit

/// One JPG discovered in an event folder, with the EXIF fields the Gallery filters
/// on and a small on-disk thumbnail generated once at build time.
struct GalleryPhotoRecord: Codable, Identifiable, Equatable {
    var id: String { sourcePath }
    let sourcePath: String
    let thumbnailFileName: String
    let camera: String?
    let lens: String?
    let captureDate: Date?
}

/// Builds and persists a JPG gallery for an event: EXIF (camera/lens) plus a small
/// generated thumbnail per photo, stored in Application Support so both survive the
/// source folder being moved or becoming unreachable after finalize — same
/// reasoning as event banner images.
enum EventGalleryStore {
    private static let thumbnailMaxPixelSize: CGFloat = 320

    // Bump this subdirectory name whenever the record format or the naming logic
    // changes — it namespaces old manifests out so a stale, differently-formatted
    // cache is never read as if it were current. v2: friendly camera/lens names
    // (matches Top Cameras/Top Lenses) instead of raw EXIF Make/Model strings.
    private static var manifestDir: URL { AppPaths.subdirectory("event_gallery_v2") }
    private static var thumbnailsDir: URL { AppPaths.subdirectory("event_gallery_v2/thumbnails") }

    private static func manifestFilename(for path: String) -> String {
        let sanitized = path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return String(sanitized.suffix(80)) + ".json"
    }

    static func load(forPath path: String) -> [GalleryPhotoRecord]? {
        let url = manifestDir.appendingPathComponent(manifestFilename(for: path))
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([GalleryPhotoRecord].self, from: data)
    }

    private static func save(_ photos: [GalleryPhotoRecord], forPath path: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(photos) else { return }
        try? FileManager.default.createDirectory(at: manifestDir, withIntermediateDirectories: true)
        try? data.write(to: manifestDir.appendingPathComponent(manifestFilename(for: path)), options: .atomic)
    }

    static func thumbnailURL(for fileName: String) -> URL {
        thumbnailsDir.appendingPathComponent(fileName)
    }

    /// Deletes the manifest and thumbnails for one event — call when the event is
    /// removed from Aurora, mirroring how banners/stats caches get cleaned up.
    static func clear(forPath path: String) {
        guard let existing = load(forPath: path) else { return }
        for record in existing {
            try? FileManager.default.removeItem(at: thumbnailURL(for: record.thumbnailFileName))
        }
        try? FileManager.default.removeItem(at: manifestDir.appendingPathComponent(manifestFilename(for: path)))
    }

    /// Cheap JPG count for `path` — just enumerates and counts, no exiftool/thumbnail
    /// work. Used to detect "the user dropped more JPGs into an already-scanned
    /// event" without waiting for (or requiring) a RAW rescan, since JPGs are added
    /// independently of RAW imports.
    nonisolated static func countJPGs(atPath path: String) -> Int {
        let root = URL(fileURLWithPath: path)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var count = 0
        for case let file as URL in enumerator {
            let ext = file.pathExtension.lowercased()
            guard ext == "jpg" || ext == "jpeg" else { continue }
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else { continue }
            count += 1
        }
        return count
    }

    /// Enumerates JPGs under `path`, then reads camera/lens/date and generates
    /// thumbnails **in batches** rather than all at once — with a large gallery
    /// (hundreds+ photos), building everything up front meant the UI stayed empty
    /// until the very last photo finished, well after the RAW scan itself had
    /// completed. Each batch's exiftool call and thumbnail generation (still
    /// parallelized per-batch across cores) reports through `progress` as it lands,
    /// so the caller can show real photos incrementally instead of one big wait.
    /// Does file I/O and shells out to exiftool — always call off the main thread.
    /// Returns nil if there are no JPGs or exiftool isn't available.
    nonisolated static func buildGallery(
        forEventPath path: String,
        progress: ((_ partial: [GalleryPhotoRecord], _ total: Int) -> Void)? = nil
    ) -> [GalleryPhotoRecord]? {
        let root = URL(fileURLWithPath: path)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var jpgFiles: [URL] = []
        for case let file as URL in enumerator {
            let ext = file.pathExtension.lowercased()
            guard ext == "jpg" || ext == "jpeg" else { continue }
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else { continue }
            jpgFiles.append(file)
        }
        guard !jpgFiles.isEmpty else {
            save([], forPath: path)
            return []
        }

        try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)

        // Local disk: fewer, bigger batches (less exiftool spawn overhead per photo —
        // the per-file I/O itself is already fast). NAS: stays at the smaller size,
        // since its higher per-file latency means bigger batches would both take
        // longer to land *and* be a worse fit for showing frequent progress on a
        // connection that's already the bottleneck.
        let batchSize = VolumeWatcher.isLocalVolume(at: root) ? 100 : 60
        var records: [GalleryPhotoRecord] = []
        for batch in chunked(jpgFiles, into: batchSize) {
            let metadataByPath = readMetadata(for: batch)

            // Thumbnail generation is CPU-bound (decode + resize + re-encode per
            // file) and each file is independent, so fan it out across cores instead
            // of doing it one file at a time.
            var thumbnailNames = [String?](repeating: nil, count: batch.count)
            thumbnailNames.withUnsafeMutableBufferPointer { buffer in
                DispatchQueue.concurrentPerform(iterations: batch.count) { i in
                    buffer[i] = writeThumbnail(for: batch[i])
                }
            }

            for (index, file) in batch.enumerated() {
                guard let thumbnailFileName = thumbnailNames[index] else { continue }
                let meta = metadataByPath[file.path]
                records.append(GalleryPhotoRecord(
                    sourcePath: file.path,
                    thumbnailFileName: thumbnailFileName,
                    camera: meta?.camera,
                    lens: meta?.lens,
                    captureDate: meta?.captureDate
                ))
            }
            progress?(records, jpgFiles.count)
        }

        save(records, forPath: path)
        return records
    }

    private static func chunked(_ files: [URL], into size: Int) -> [[URL]] {
        guard size > 0 else { return [files] }
        return stride(from: 0, to: files.count, by: size).map { start in
            Array(files[start..<Swift.min(start + size, files.count)])
        }
    }

    // MARK: - EXIF read

    private struct PhotoMetadata {
        let camera: String?
        let lens: String?
        let captureDate: Date?
    }

    private nonisolated static func readMetadata(for files: [URL]) -> [String: PhotoMetadata] {
        guard let exiftoolPath = ExiftoolInstallerService.installedExiftoolPath() else { return [:] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exiftoolPath)
        process.arguments = [
            "-json", "-q", "-m", "-fast2",
            "-Make", "-Model", "-LensModel", "-LensID",
            "-DateTimeOriginal", "-CreateDate"
        ] + files.map(\.path)

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

        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

        var result: [String: PhotoMetadata] = [:]
        for entry in entries {
            guard let sourceFile = entry["SourceFile"] as? String else { continue }
            let make = entry["Make"] as? String ?? ""
            let model = entry["Model"] as? String ?? ""
            // Same friendly-name mapping Top Cameras/Top Lenses use, so the Gallery
            // filter shows "Sony A1 II" instead of the raw "SONY ILCE-1M2".
            let camera = model.isEmpty ? nil : StatsReport.CameraStat(make: make, model: model, count: 0).fullName

            let lensModel = (entry["LensModel"] as? String) ?? (entry["LensID"] as? String) ?? ""
            let lens = lensModel.isEmpty ? nil : StatsReport.LensStat(make: make, model: lensModel, count: 0, rank: 0).fullName

            let dateRaw = (entry["DateTimeOriginal"] as? String) ?? (entry["CreateDate"] as? String)
            let captureDate = dateRaw.flatMap { dateFormatter.date(from: String($0.prefix(19))) }

            result[sourceFile] = PhotoMetadata(camera: camera, lens: lens, captureDate: captureDate)
        }
        return result
    }

    // MARK: - Thumbnail generation

    /// Downsamples via ImageIO (no QuickLook dependency, works headless) and writes
    /// a small JPEG named after a hash of the source path, so re-running the build
    /// for the same file overwrites rather than accumulating orphaned thumbnails.
    private nonisolated static func writeThumbnail(for file: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let fileName = sha256Hex(file.path) + ".jpg"
        let destination = thumbnailsDir.appendingPathComponent(fileName)
        guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return fileName
    }

    private nonisolated static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
