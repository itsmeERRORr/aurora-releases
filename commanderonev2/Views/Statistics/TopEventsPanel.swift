import SwiftUI
import AppKit

struct EventAggregate: Identifiable, Hashable {
    let id: String       // folder path
    let name: String
    let totalFiles: Int
    let totalBytes: Int64
    let averageSpeed: Double // bytes/s
    let lastDate: Date
}

enum EventAggregator {
    /// Builds event aggregates strictly from sidebar destinations so names always
    /// match what the sidebar shows. Stats come from bookmarked summaries and caches.
    @MainActor
    static func build(appState: AppState) -> [EventAggregate] {
        let avgSpeed = appState.totalStatsReport?.averageSpeed ?? 0

        return appState.uniqueImportDestinations.compactMap { destination in
            guard !destination.path.isEmpty else { return nil }

            let effectiveName: String
            if isInvalidEventName(destination.name) {
                let root = inferredEventRoot(from: normalize(destination.path))
                effectiveName = URL(fileURLWithPath: root).lastPathComponent
            } else {
                effectiveName = destination.name
            }
            guard !isInvalidEventName(effectiveName) else { return nil }

            let summary = appState.importStatsForEventFolder(at: destination.bookmarkIndex)
            let finalized = appState.finalizedEvent(forBookmarkIndex: destination.bookmarkIndex)
            let peak = destination.bookmarkIndex < appState.eventFolderPeakRawCounts.count
                ? appState.eventFolderPeakRawCounts[destination.bookmarkIndex] : 0
            let cached = destination.bookmarkIndex < appState.eventFolderCachedCounts.count
                ? max(appState.eventFolderCachedCounts[destination.bookmarkIndex], 0) : 0
            let files = max(summary?.photoCount ?? 0, max(finalized?.photoCount ?? 0, max(peak, cached)))
            let bytes = max(summary?.totalBytes ?? 0, finalized?.totalBytes ?? 0)
            let lastDate = summary?.lastDate
                ?? finalized?.lastImportDate
                ?? finalized?.finalizedAt
                ?? .distantPast

            guard files > 0 else { return nil }

            return EventAggregate(
                id: destination.path,
                name: effectiveName,
                totalFiles: files,
                totalBytes: bytes,
                averageSpeed: avgSpeed,
                lastDate: lastDate
            )
        }
    }

    private static func normalize(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private static func bestParent(of path: String, in candidates: [String]) -> String? {
        candidates
            .filter { !$0.isEmpty && (path == $0 || path.hasPrefix($0 + "/")) }
            .max(by: { $0.count < $1.count })
    }

    /// Walks the path up past media subfolders (RAW/JPG/exports) and date-stamped
    /// folders (`2026-05-20`, `May 20`, etc.) so the returned root is the actual
    /// event folder name, not a media subfolder.
    private static func inferredEventRoot(from path: String) -> String {
        var url = URL(fileURLWithPath: path)
        while shouldStripFromEventRoot(url.lastPathComponent) {
            let parent = url.deletingLastPathComponent()
            guard parent.path != url.path else { break }
            url = parent
        }
        return normalize(url.path)
    }

    /// Picks the best display name: a user-provided custom name if present and
    /// non-generic, otherwise the last component of the inferred root path.
    private static func displayName(preferred: String?, root: String) -> String {
        if let preferred, !preferred.isEmpty, !shouldStripFromEventRoot(preferred) {
            return preferred
        }
        return URL(fileURLWithPath: root).lastPathComponent
    }

    /// True for media subfolders ("RAWs", "JPGs", "exports") and date-stamped
    /// folders ("2026-05-20", "May 20 2026"). These should not surface as event names.
    private static func shouldStripFromEventRoot(_ component: String) -> Bool {
        let folder = component.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !folder.isEmpty else { return false }

        let mediaFolders = [
            "raw", "raws", "raw files", "raw-files",
            "jpg", "jpeg", "jpegs", "photos", "images",
            "exports", "export", "selects", "selected", "edits",
            "finais", "final", "finals"
        ]
        if mediaFolders.contains(folder) { return true }

        return isDateLikeFolder(folder)
    }

    private static func isDateLikeFolder(_ folder: String) -> Bool {
        let monthNames = [
            "jan", "january", "feb", "february", "mar", "march", "apr", "april",
            "may", "jun", "june", "jul", "july", "aug", "august", "sep", "sept", "september",
            "oct", "october", "nov", "november", "dec", "december"
        ]
        if monthNames.contains(where: { folder.contains($0) }) && folder.contains(where: { $0.isNumber }) {
            return true
        }

        let numericParts = folder
            .split { !$0.isNumber }
            .map(String.init)
        guard numericParts.count >= 2 else { return false }

        let hasYear = numericParts.contains { $0.count == 4 }
        let hasShortDateParts = numericParts.contains { part in
            guard let value = Int(part) else { return false }
            return value >= 1 && value <= 31
        }
        return hasYear && hasShortDateParts
    }

    /// True for container folders that should never surface as event names
    /// (Desktop, Volumes, Users, etc.) and for media subfolder names.
    private static func isInvalidEventName(_ name: String) -> Bool {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return true }

        let containerFolders = [
            "desktop", "documents", "downloads", "pictures", "movies",
            "users", "volumes", "icloud drive", "commanderonev2"
        ]
        return containerFolders.contains(value) || shouldStripFromEventRoot(value)
    }
}

// MARK: - Panel

struct TopEventsPanel: View {
    @Bindable var appState: AppState
    var onSelect: (EventAggregate) -> Void = { _ in }
    var onViewAll: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Top Events", actionLabel: "View all →", action: onViewAll)

            let sorted = EventAggregator.build(appState: appState)
                .sorted { $0.totalBytes > $1.totalBytes }
                .prefix(5)
                .map { aggregate in
                    LatestEventDisplay(
                        aggregate: aggregate,
                        bannerImagePath: appState.bannerImagePath(forEventPath: aggregate.id)
                    )
                }

            if sorted.isEmpty {
                emptyState
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, event in
                        TopEventRow(rank: idx + 1, event: event) {
                            onSelect(event.aggregate)
                        }
                    }
                }
            }
        }
        .auroraStaticCard()
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No events imported yet")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            Text("Top events appear here once imports complete.")
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct LatestEventsPanel: View {
    @Bindable var appState: AppState
    var onSelect: (EventAggregate) -> Void = { _ in }
    var onViewAll: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Latest Events", actionLabel: "View all →", action: onViewAll)

            let sorted = appState.uniqueImportDestinations
                .prefix(5)
                .compactMap(latestEventDisplay)

            if sorted.isEmpty {
                emptyState
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, event in
                        LatestEventRow(rank: idx + 1, event: event) {
                            onSelect(event.aggregate)
                        }
                    }
                }
            }
        }
        .auroraStaticCard()
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No recent events yet")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            Text("Latest events appear here once imports complete.")
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func latestEventDisplay(
        for destination: (path: String, name: String, bookmarkIndex: Int)
    ) -> LatestEventDisplay? {
        let summary = appState.importStatsForEventFolder(at: destination.bookmarkIndex)
        let peak = destination.bookmarkIndex < appState.eventFolderPeakRawCounts.count
            ? appState.eventFolderPeakRawCounts[destination.bookmarkIndex]
            : 0
        let cached = destination.bookmarkIndex < appState.eventFolderCachedCounts.count
            ? max(appState.eventFolderCachedCounts[destination.bookmarkIndex], 0)
            : 0
        let totalFiles = max(summary?.photoCount ?? 0, max(peak, cached))

        let aggregate = EventAggregate(
            id: destination.path,
            name: destination.name,
            totalFiles: totalFiles,
            totalBytes: summary?.totalBytes ?? 0,
            averageSpeed: appState.totalStatsReport?.averageSpeed ?? 0,
            lastDate: summary?.lastDate ?? .distantPast
        )
        let bannerPath: String? = if destination.bookmarkIndex < appState.eventFolderBannerImagePaths.count {
            appState.eventFolderBannerImagePaths[destination.bookmarkIndex].isEmpty
                ? nil
                : appState.eventFolderBannerImagePaths[destination.bookmarkIndex]
        } else {
            nil
        }
        return LatestEventDisplay(aggregate: aggregate, bannerImagePath: bannerPath)
    }
}

struct LatestEventDisplay: Identifiable {
    let aggregate: EventAggregate
    let bannerImagePath: String?

    var id: String { aggregate.id }
}

struct TopEventRow: View {
    let rank: Int
    let event: LatestEventDisplay
    var onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RankBadge(rank: rank)
                EventThumbnail(
                    eventName: event.aggregate.name,
                    folderPath: event.aggregate.id,
                    bannerImagePath: event.bannerImagePath
                )
                .frame(width: 44, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.aggregate.name)
                        .font(.auroraEventName)
                        .foregroundStyle(Color.auroraTxt)
                        .lineLimit(1)
                    let parts = AuroraFormat.bytesParts(event.aggregate.totalBytes)
                    Text("\(parts.value) \(parts.unit)")
                        .font(.manrope(11, weight: .semibold))
                        .foregroundStyle(Color.auroraFaint)
                }
                Spacer(minLength: 4)
                SpeedPill(text: AuroraFormat.count(event.aggregate.totalFiles), tint: .auroraCyan)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(hovering ? Color.auroraPanel2 : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct LatestEventRow: View {
    let rank: Int
    let event: LatestEventDisplay
    var onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RankBadge(rank: rank)
                EventThumbnail(
                    eventName: event.aggregate.name,
                    folderPath: event.aggregate.id,
                    bannerImagePath: event.bannerImagePath
                )
                .frame(width: 44, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.aggregate.name)
                        .font(.auroraEventName)
                        .foregroundStyle(Color.auroraTxt)
                        .lineLimit(1)
                    Text(dateText)
                        .font(.manrope(11, weight: .semibold))
                        .foregroundStyle(Color.auroraFaint)
                }
                Spacer(minLength: 4)
                SpeedPill(text: AuroraFormat.count(event.aggregate.totalFiles), tint: .auroraViolet)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(hovering ? Color.auroraPanel2 : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var dateText: String {
        event.aggregate.lastDate == .distantPast ? "—" : AuroraFormat.dateCompact(event.aggregate.lastDate)
    }
}

struct SpeedPill: View {
    let text: String
    var tint: Color = .auroraCyan

    var body: some View {
        Text(text)
            .font(.sora(11.5, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            )
    }
}
