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
    static func build(appState: AppState) -> [EventAggregate] {
        var byPath: [String: (name: String, files: Int, bytes: Int64, speedSum: Double, speedCount: Int, last: Date)] = [:]

        // Honor sidebar order: known event folders first.
        let destinations = appState.uniqueImportDestinations
        for (path, name, _) in destinations where !path.isEmpty {
            byPath[normalize(path), default: (name, 0, 0, 0, 0, .distantPast)].name = name
        }

        // Iterate history.
        for entry in appState.importHistory {
            // Match the entry's destination to the configured event folder it belongs to.
            let entryNorm = normalize(entry.destinationPath)
            // Prefer the deepest known event folder that is a prefix.
            let parentNorm = bestParent(of: entryNorm, in: destinations.map { normalize($0.path) }) ?? entryNorm
            let displayName = destinations.first { normalize($0.path) == parentNorm }?.name
                ?? URL(fileURLWithPath: parentNorm).lastPathComponent

            var slot = byPath[parentNorm] ?? (displayName, 0, 0, 0, 0, .distantPast)
            slot.name = slot.name.isEmpty ? displayName : slot.name
            slot.files += entry.fileCount
            slot.bytes += entry.totalBytes
            slot.last = max(slot.last, entry.date)
            byPath[parentNorm] = slot
        }

        // Pull speed averages from totalStatsReport when we have any.
        let avgSpeed = appState.totalStatsReport?.averageSpeed ?? 0

        return byPath.compactMap { path, info in
            guard info.files > 0 else { return nil }
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
