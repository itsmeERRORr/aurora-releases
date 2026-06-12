import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum EventSocialShareFormat: String, CaseIterable {
    case story
    case post

    var title: String {
        switch self {
        case .story: return "Instagram Story"
        case .post: return "Instagram Post"
        }
    }

    var size: CGSize {
        switch self {
        case .story: return CGSize(width: 1080, height: 1920)
        case .post: return CGSize(width: 1080, height: 1080)
        }
    }
}

struct EventSocialShareSnapshot {
    let eventName: String
    let destinationPath: String
    let bannerImagePath: String?
    let bannerOffset: EventBannerOffset
    let dateRange: String
    let rawFiles: String
    let deliveredPhotos: String
    let dataImported: String
    let avgISO: String
    let avgShutter: String
    let avgAperture: String
    let avgFocal: String
    let topLenses: [EventSocialRankItem]
    let topCameras: [EventSocialRankItem]
}

struct EventSocialRankItem: Hashable {
    let name: String
    let subtitle: String?
    let count: String
}

@MainActor
enum EventSocialShareExporter {
    static func export(snapshot: EventSocialShareSnapshot, format: EventSocialShareFormat) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(safeFilename(snapshot.eventName))-\(format.rawValue).png"
        panel.message = "Save a social-ready PNG for \(snapshot.eventName)"
        panel.prompt = "Export"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let view = EventSocialShareCard(snapshot: snapshot, format: format)
            .frame(width: format.size.width, height: format.size.height)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(format.size)
        renderer.scale = 1

        guard let cgImage = renderer.cgImage else {
            throw ExportError.renderFailed
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.pngFailed
        }
        try data.write(to: url, options: .atomic)
    }

    private static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let parts = value.components(separatedBy: invalid)
        let joined = parts.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "event-stats" : joined
    }

    enum ExportError: LocalizedError {
        case renderFailed
        case pngFailed

        var errorDescription: String? {
            switch self {
            case .renderFailed: return "The share image could not be rendered."
            case .pngFailed: return "The rendered image could not be converted to PNG."
            }
        }
    }
}

private struct EventSocialShareCard: View {
    let snapshot: EventSocialShareSnapshot
    let format: EventSocialShareFormat

    private var size: CGSize { format.size }
    private var isStory: Bool { format == .story }

    var body: some View {
        ZStack {
            background

            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer()
                    .frame(height: isStory ? 148 : 28)
                statsBlock
                Spacer(minLength: 0)
            }
            .padding(.horizontal, isStory ? 72 : 58)
            .padding(.top, isStory ? 96 : 80)
            .padding(.bottom, isStory ? 92 : 54)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var background: some View {
        ZStack {
            EventGradients.gradient(for: snapshot.eventName)

            if let path = snapshot.bannerImagePath, let image = NSImage(contentsOfFile: path) {
                GeometryReader { proxy in
                    let imageSize = scaledImageSize(imageSize: image.size, containerSize: proxy.size)
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: imageSize.width, height: imageSize.height)
                        .offset(x: snapshot.bannerOffset.x, y: snapshot.bannerOffset.y)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .saturation(0.96)
                        .contrast(1.08)
                }
            } else {
                EventThumbnail(eventName: snapshot.eventName, folderPath: snapshot.destinationPath, cornerRadius: 0)
            }

            LinearGradient(
                colors: [
                    Color.auroraBg.opacity(0.18),
                    Color.auroraBg.opacity(0.58),
                    Color.auroraBg.opacity(0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Color.auroraCyan.opacity(0.34), .clear],
                center: UnitPoint(x: 0.12, y: 0.08),
                startRadius: 10,
                endRadius: 620
            )

            RadialGradient(
                colors: [Color.auroraMagenta.opacity(0.24), .clear],
                center: UnitPoint(x: 0.94, y: 0.72),
                startRadius: 20,
                endRadius: 700
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: isStory ? 22 : 14) {
            HStack(spacing: 12) {
                Text("JOAO PHOTOS")
                    .font(.manrope(isStory ? 18 : 15, weight: .heavy))
                    .tracking(4)
                    .foregroundStyle(Color.auroraCyan)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text(snapshot.eventName)
                    .font(.sora(isStory ? 78 : 52, weight: .heavy))
                    .tracking(isStory ? -2.2 : -1.8)
                    .foregroundStyle(.white)
                    .lineLimit(isStory ? 3 : 2)
                    .minimumScaleFactor(0.58)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.55), radius: 18, x: 0, y: 8)

                Text(snapshot.dateRange)
                    .font(.manrope(isStory ? 29 : 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 4)
            }
        }
    }

    private var statsBlock: some View {
        VStack(alignment: .leading, spacing: isStory ? 22 : 12) {
            rawFilesHero

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: isStory ? 16 : 8) {
                shareStat("Delivered", snapshot.deliveredPhotos, "checkmark.rectangle.stack.fill", .auroraHealthy)
                shareStat("Data", snapshot.dataImported, "externaldrive.fill", .auroraBlue)
                shareStat("Avg ISO", snapshot.avgISO, "camera.aperture", .auroraViolet)
                shareStat("Avg Shutter", snapshot.avgShutter, "timer", .auroraPurple)
                shareStat("Avg Aperture", snapshot.avgAperture, "circle.dotted", .auroraMagenta)
                shareStat("Avg Focal", snapshot.avgFocal, "viewfinder", .auroraCyan)
            }

            HStack(alignment: .top, spacing: isStory ? 16 : 8) {
                shareRanking(title: "Top 3 Lenses", items: snapshot.topLenses, icon: "camera.aperture", color: .auroraMagenta)
                shareRanking(title: "Top 3 Cameras", items: snapshot.topCameras, icon: "camera.fill", color: .auroraCyan)
            }
            .padding(.top, isStory ? 6 : 0)
        }
    }

    private var rawFilesHero: some View {
        HStack(spacing: isStory ? 22 : 18) {
            IconChip(systemName: "photo.stack.fill", color: .auroraCyan, size: isStory ? 58 : 40, iconScale: 0.46)

            VStack(alignment: .leading, spacing: 2) {
                Text("RAW FILES")
                    .font(.manrope(isStory ? 17 : 12, weight: .heavy))
                    .tracking(2.6)
                    .foregroundStyle(Color.auroraCyan)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(snapshot.rawFiles)
                        .font(.sora(isStory ? 110 : 66, weight: .heavy))
                        .tracking(-4)
                        .foregroundStyle(.white)
                    Text("imported")
                        .font(.manrope(isStory ? 24 : 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, isStory ? 30 : 18)
        .padding(.vertical, isStory ? 24 : 14)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.auroraBg.opacity(0.64))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.auroraCyan.opacity(0.22), lineWidth: 1)
        )
    }

    private func shareStat(_ label: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: isStory ? 24 : 20, weight: .bold))
                    .foregroundStyle(color)
                Text(label.uppercased())
                    .font(.manrope(isStory ? 16 : 14, weight: .heavy))
                    .tracking(1.7)
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
            }

            Text(value)
                .font(.sora(isStory ? 37 : 24, weight: .heavy))
                .tracking(-0.8)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.58)
        }
        .frame(maxWidth: .infinity, minHeight: isStory ? 136 : 84, alignment: .leading)
        .padding(isStory ? 22 : 13)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.auroraBg.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func shareRanking(title: String, items: [EventSocialRankItem], icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: isStory ? 16 : 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: isStory ? 22 : 15, weight: .bold))
                    .foregroundStyle(color)
                Text(title.uppercased())
                    .font(.manrope(isStory ? 17 : 12, weight: .heavy))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: isStory ? 8 : 3) {
                if items.isEmpty {
                    socialRankingRow(rank: 1, item: EventSocialRankItem(name: "—", subtitle: nil, count: "—"), icon: icon, color: color)
                } else {
                    ForEach(Array(items.prefix(3).enumerated()), id: \.element) { index, item in
                        socialRankingRow(rank: index + 1, item: item, icon: icon, color: accentForRank(index + 1))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: isStory ? 238 : 128, alignment: .topLeading)
        .padding(isStory ? 20 : 12)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.auroraBg.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func socialRankingRow(rank: Int, item: EventSocialRankItem, icon: String, color: Color) -> some View {
        HStack(spacing: isStory ? 13 : 8) {
            RankBadge(rank: rank, size: isStory ? 31 : 21)

            IconChip(systemName: icon, color: color, size: isStory ? 42 : 28, iconScale: 0.5)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.manrope(isStory ? 24 : 15, weight: .heavy))
                    .tracking(-0.35)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.manrope(isStory ? 15 : 10, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(Color.auroraFaint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            SpeedPill(text: item.count, tint: color)
                .scaleEffect(isStory ? 1.32 : 0.92)
        }
        .padding(.horizontal, isStory ? 8 : 4)
        .padding(.vertical, isStory ? 7 : 3)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
    }

    private func accentForRank(_ rank: Int) -> Color {
        switch rank {
        case 1: return .auroraCyan
        case 2: return .auroraViolet
        case 3: return .auroraMagenta
        default: return .auroraBlue
        }
    }

    private func scaledImageSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return containerSize }
        let scale = max(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}
