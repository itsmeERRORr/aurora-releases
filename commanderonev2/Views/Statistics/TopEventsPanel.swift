import SwiftUI

struct EventAggregate: Identifiable, Hashable {
    let id: String       // folder path
    let name: String
    let totalFiles: Int
    let totalBytes: Int64
    let averageSpeed: Double // bytes/s
    let lastDate: Date
}

enum EventAggregator {
    /// Build aggregates for every unique destination in the import history.
    ///
    /// Display names are resolved by walking the path up past media subfolders
    /// (RAWs, JPGs, exports) and date-stamped subfolders, so an event imported
    /// into `/My Event/2026-05-20/RAWs/` is shown as "My Event", not "RAWs".
    static func build(appState: AppState) -> [EventAggregate] {
        var byPath: [String: (name: String, files: Int, bytes: Int64, speedSum: Double, speedCount: Int, last: Date)] = [:]

        // Finalized events first — source of truth for any matching path.
        // Track these paths so live logic does not overwrite them.
        var finalizedPaths = Set<String>()
        for event in appState.finalizedEvents {
            let root = inferredEventRoot(from: normalize(event.lastKnownPath))
            guard !root.isEmpty, !isInvalidEventName(event.name) else { continue }
            byPath[root] = (
                name: event.name,
                files: event.photoCount,
                bytes: event.totalBytes,
                speedSum: 0,
                speedCount: 0,
                last: event.lastImportDate ?? event.finalizedAt
            )
            finalizedPaths.insert(root)
        }

        // Configured event folders, resolved to their event root (strips RAW/date subfolders).
        let destinations = appState.eventFolderBookmarks.indices.compactMap { index -> (path: String, name: String, files: Int) in
            let rawPath = index < appState.eventFolderCachedPaths.count ? appState.eventFolderCachedPaths[index] : ""
            let root = inferredEventRoot(from: normalize(rawPath))
            let customName = index < appState.eventFolderDisplayNames.count ? appState.eventFolderDisplayNames[index] : ""
            let count = index < appState.eventFolderCachedCounts.count ? appState.eventFolderCachedCounts[index] : -1
            let peak = index < appState.eventFolderPeakRawCounts.count ? appState.eventFolderPeakRawCounts[index] : 0
            return (path: root, name: displayName(preferred: customName, root: root), files: max(count, peak))
        }
        for destination in destinations where !destination.path.isEmpty && !finalizedPaths.contains(destination.path) {
            byPath[destination.path, default: (destination.name, 0, 0, 0, 0, .distantPast)].name = destination.name
        }

        // Iterate history (skip entries whose parent is finalized — snapshot is canonical).
        for entry in appState.importHistory {
            let entryNorm = normalize(entry.destinationPath)
            let entryRoot = inferredEventRoot(from: entryNorm)
            let parentNorm = bestParent(of: entryRoot, in: destinations.map { $0.path }) ?? entryRoot
            if finalizedPaths.contains(parentNorm) { continue }

            let resolvedName = destinations.first { normalize($0.path) == parentNorm }?.name
                ?? displayName(preferred: nil, root: parentNorm)

            guard !isInvalidEventName(resolvedName) else { continue }

            var slot = byPath[parentNorm] ?? (resolvedName, 0, 0, 0, 0, .distantPast)
            slot.name = slot.name.isEmpty ? resolvedName : slot.name
            slot.files += entry.fileCount
            slot.bytes += entry.totalBytes
            slot.last = max(slot.last, entry.date)
            byPath[parentNorm] = slot
        }

        // If a configured event has cached counts but no import-history match, still show it.
        for event in destinations where !event.path.isEmpty && event.files > 0
            && !isInvalidEventName(event.name) && !finalizedPaths.contains(event.path)
        {
            var slot = byPath[event.path] ?? (event.name, 0, 0, 0, 0, .distantPast)
            slot.name = event.name
            slot.files = max(slot.files, event.files)
            byPath[event.path] = slot
        }

        // Pull speed averages from totalStatsReport when we have any.
        let avgSpeed = appState.totalStatsReport?.averageSpeed ?? 0

        return byPath.compactMap { path, info in
            guard info.files > 0 else { return nil }
            guard !isInvalidEventName(info.name) else { return nil }
            return EventAggregate(
                id: path,
                name: info.name,
                totalFiles: info.files,
                totalBytes: info.bytes,
                averageSpeed: avgSpeed,
                lastDate: info.last
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Top Events", actionLabel: "View all →")

            let sorted = EventAggregator.build(appState: appState)
                .sorted { $0.totalBytes > $1.totalBytes }
                .prefix(4)

            if sorted.isEmpty {
                emptyState
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, event in
                        TopEventRow(rank: idx + 1, event: event) {
                            onSelect(event)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
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

struct TopEventRow: View {
    let rank: Int
    let event: EventAggregate
    var onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RankBadge(rank: rank)
                EventThumbnail(eventName: event.name, folderPath: event.id)
                    .frame(width: 44, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.name)
                        .font(.auroraEventName)
                        .foregroundStyle(Color.auroraTxt)
                        .lineLimit(1)
                    let parts = AuroraFormat.bytesParts(event.totalBytes)
                    Text("\(parts.value) \(parts.unit)")
                        .font(.manrope(11, weight: .semibold))
                        .foregroundStyle(Color.auroraFaint)
                }
                Spacer(minLength: 4)
                SpeedPill(text: AuroraFormat.count(event.totalFiles), tint: .auroraCyan)
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
