import SwiftUI
import AppKit

enum BannerImageCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(forPath path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    static func load(path: String) -> NSImage? {
        if let cached = image(forPath: path) {
            return cached
        }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    static func remove(path: String) {
        cache.removeObject(forKey: path as NSString)
    }
}

/// Shows the first photo in an event folder when accessible, otherwise the
/// Aurora signature gradient for the event.
struct EventThumbnail: View {
    let eventName: String
    /// Optional folder path — when present, a QL thumbnail is requested.
    var folderPath: String? = nil
    var cornerRadius: CGFloat = 8
    var overlay: AnyView? = nil
    /// Custom banner image path — takes priority over the folder thumbnail.
    var bannerImagePath: String? = nil

    @State private var bannerImage: NSImage?
    @State private var loadedBannerImagePath: String?
    @State private var folderImage: NSImage?

    var body: some View {
        ZStack {
            EventGradients.gradient(for: eventName)
                .overlay(
                    // Subtle radial highlight from the handoff
                    RadialGradient(
                        colors: [Color.white.opacity(0.16), .clear],
                        center: UnitPoint(x: 0.38, y: 0.22),
                        startRadius: 0, endRadius: 180
                    )
                )

            if let img = bannerImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .transition(.opacity)
            } else if let img = folderImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .transition(.opacity)
            }

            overlay
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear { loadBannerImageIfNeeded() }
        .onChange(of: bannerImagePath) { _, _ in
            loadBannerImageIfNeeded()
        }
        // Each instance awaits its own folder thumbnail and stores it in its own
        // `@State` — no shared/global invalidation, so one thumbnail finishing
        // never forces every other `EventThumbnail` on screen to be recreated.
        .task(id: folderPath) {
            guard bannerImagePath == nil, let path = folderPath else { return }
            if let cached = EventThumbnailLoader.shared.image(forFolderPath: path) {
                folderImage = cached
                return
            }
            folderImage = await EventThumbnailLoader.shared.load(forFolderPath: path)
        }
    }

    private func loadBannerImageIfNeeded() {
        guard let path = bannerImagePath else {
            bannerImage = nil
            loadedBannerImagePath = nil
            return
        }
        guard loadedBannerImagePath != path else { return }
        loadedBannerImagePath = path
        if let cached = BannerImageCache.image(forPath: path) {
            bannerImage = cached
            return
        }
        Task.detached(priority: .utility) {
            let image = BannerImageCache.load(path: path)
            await MainActor.run {
                guard loadedBannerImagePath == path else { return }
                bannerImage = image
            }
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        EventThumbnail(eventName: "R6 SLC Major 2026")
            .frame(width: 44, height: 34)
        EventThumbnail(eventName: "Six Invitational 2026")
            .frame(width: 44, height: 34)
        EventThumbnail(eventName: "Liga Portugal - Etapa 1", cornerRadius: 12)
            .frame(width: 180, height: 110)
    }
    .padding(40)
    .background(Color.auroraBg)
}
