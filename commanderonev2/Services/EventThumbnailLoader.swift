import Foundation
import AppKit
import QuickLookThumbnailing

/// Caps how many `QLThumbnailGenerator` requests run at once. Generating a
/// thumbnail from a RAW file is genuinely slow (often several hundred ms), and
/// a page like Dashboard/Statistics can want ~10 of them at once (Top Events +
/// Latest Events, each with their own thumbnail) right when it first appears.
/// Firing all of them concurrently saturates QuickLook's service and the CPU
/// cores doing the decode, and the flurry of near-simultaneous completions
/// (each one hopping back to the main actor to update its view's `@State`) was
/// enough to make the main thread feel unresponsive — including to scroll
/// input — for the first couple of seconds after the page mounted. Queuing
/// them a few at a time spreads that cost out instead of front-loading it all
/// at once.
private actor ThumbnailGenerationGate {
    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { availablePermits = limit }

    func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            availablePermits += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// Best-effort thumbnail loader for event folders.
/// Looks for the first RAW file inside the folder (via FileManager), generates
/// a QL thumbnail, and caches it in-memory keyed by folder path. Falls back to
/// `nil` when nothing is accessible — callers should show a gradient.
///
/// Deliberately *not* `ObservableObject` — it used to publish a single global
/// `version` counter that every `EventThumbnail` on screen observed via
/// `.id("\(loader.version)-...")`. That meant any one thumbnail finishing its
/// (relatively slow, QuickLook-based) load anywhere in the app forced *every*
/// `EventThumbnail` currently mounted — Dashboard, Statistics, event pages, all
/// of them — to be destroyed and recreated from scratch, not just re-rendered.
/// With several thumbnails loading concurrently (e.g. right after opening the
/// Dashboard), that's an O(n²) churn of full view recreations, which is exactly
/// the kind of thing that makes the main thread (and any gesture running on it,
/// like scrolling) feel like it's hanging. Each `EventThumbnail` now awaits its
/// own load and only updates its own `@State`.
@MainActor
final class EventThumbnailLoader {
    static let shared = EventThumbnailLoader()

    private var cache: [String: NSImage] = [:]
    /// Coalesces concurrent requests for the same path so multiple on-screen
    /// thumbnails for the same folder await one QuickLook generation instead of
    /// each kicking off their own.
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    /// Paths that returned nothing — don't keep retrying every render.
    private var negative: Set<String> = []
    private let generationGate = ThumbnailGenerationGate(limit: 2)

    private let extensions: Set<String> = [
        "3fr", "arw", "cr2", "cr3", "dng", "iiq", "nef", "nrw", "orf", "raf", "raw", "rw2"
    ]

    func image(forFolderPath path: String) -> NSImage? {
        guard !path.isEmpty else { return nil }
        return cache[path]
    }

    /// Awaits the thumbnail for `path`, generating it if needed. Call from a
    /// `.task(id: folderPath)` and store the result in that view's own `@State`.
    func load(forFolderPath path: String, size: CGSize = CGSize(width: 220, height: 160)) async -> NSImage? {
        guard !path.isEmpty else { return nil }
        if let cached = cache[path] { return cached }
        if negative.contains(path) { return nil }
        if let existing = inFlight[path] { return await existing.value }

        let extensions = self.extensions
        let gate = generationGate
        let task = Task.detached(priority: .utility) { () -> NSImage? in
            let url = URL(fileURLWithPath: path)
            let fm = FileManager.default
            let candidates: [URL]? = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            guard let firstRaw = candidates?
                .filter({ extensions.contains($0.pathExtension.lowercased()) })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                .first else { return nil }

            let request = QLThumbnailGenerator.Request(
                fileAt: firstRaw,
                size: size,
                scale: 2.0,
                representationTypes: .thumbnail
            )
            await gate.acquire()
            let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
            await gate.release()
            return image
        }
        inFlight[path] = task

        let result = await task.value
        inFlight[path] = nil
        if let result {
            cache[path] = result
        } else {
            negative.insert(path)
        }
        return result
    }
}
