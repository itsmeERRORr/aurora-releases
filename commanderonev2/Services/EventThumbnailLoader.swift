import Foundation
import AppKit
import Combine
import QuickLookThumbnailing

/// Best-effort thumbnail loader for event folders.
/// Looks for the first RAW file inside the folder (via FileManager), generates
/// a QL thumbnail, and caches it in-memory keyed by folder path. Falls back to
/// `nil` when nothing is accessible — callers should show a gradient.
@MainActor
final class EventThumbnailLoader: ObservableObject {
    static let shared = EventThumbnailLoader()

    private var cache: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    /// Paths that returned nothing — don't keep retrying every render.
    private var negative: Set<String> = []

    @Published private(set) var version: Int = 0

    private let extensions: Set<String> = [
        "3fr", "arw", "cr2", "cr3", "dng", "iiq", "nef", "nrw", "orf", "raf", "raw", "rw2"
    ]

    func image(forFolderPath path: String) -> NSImage? {
        guard !path.isEmpty else { return nil }
        return cache[path]
    }

    func requestLoad(folderPath path: String, size: CGSize = CGSize(width: 220, height: 160)) {
        guard !path.isEmpty,
              cache[path] == nil,
              !inFlight.contains(path),
              !negative.contains(path) else { return }
        inFlight.insert(path)

        Task.detached(priority: .utility) { [extensions] in
            let url = URL(fileURLWithPath: path)
            let fm = FileManager.default
            let candidates: [URL]? = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            let firstRaw = candidates?
                .filter { extensions.contains($0.pathExtension.lowercased()) }
                .sorted { ($0.lastPathComponent) < ($1.lastPathComponent) }
                .first

            guard let target = firstRaw else {
                await MainActor.run {
                    self.inFlight.remove(path)
                    self.negative.insert(path)
                }
                return
            }

            let request = QLThumbnailGenerator.Request(
                fileAt: target,
                size: size,
                scale: 2.0,
                representationTypes: .thumbnail
            )

            do {
                let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                await MainActor.run {
                    self.inFlight.remove(path)
                    self.cache[path] = rep.nsImage
                    self.version &+= 1
                }
            } catch {
                await MainActor.run {
                    self.inFlight.remove(path)
                    self.negative.insert(path)
                }
            }
        }
    }
}
