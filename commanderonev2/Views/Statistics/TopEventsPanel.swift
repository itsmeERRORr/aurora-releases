import SwiftUI
import AppKit

struct EventAggregate: Identifiable, Hashable {
    let id: String       // folder path
    let name: String
    let totalFiles: Int
    let totalBytes: Int64
    let totalWorkingSeconds: TimeInterval
    let totalShootingSeconds: TimeInterval
    let longestCoverageDaySeconds: TimeInterval
    let longestCoverageDayKey: String?
    let averageSpeed: Double // bytes/s
    let lastDate: Date
    let bookmarkIndex: Int
    let tags: Set<EventTag>
}

enum TopEventsMetric: String, CaseIterable, Identifiable {
    case raw = "RAW"
    case totalWorkingHours = "Total Working Hours"
    case shootingTime = "Shooting Time"
    case longestCoverageDay = "Longest Active Day"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .raw: return .auroraCyan
        case .totalWorkingHours: return .auroraBlue
        case .shootingTime: return .auroraMagenta
        case .longestCoverageDay: return .auroraViolet
        }
    }
}

enum EventAggregator {
    /// Everything the expensive `assemble` step needs, gathered on the main actor
    /// (cheap — in-memory array/dictionary reads and `importHistory` filtering, no
    /// disk I/O). The one genuinely expensive step, `EventStatsCache.load`, is
    /// deliberately excluded here; it happens off-thread in `assemble`.
    private struct PendingAggregateInput {
        let path: String
        let name: String
        let bookmarkIndex: Int
        let totalFiles: Int
        let totalBytesFromMetadata: Int64
        let finalizedSnapshot: StatsReport?
        let currentCachePath: String
        let previousCachePath: String
        let displayDate: Date
        let averageSpeed: Double
        let tags: Set<EventTag>
    }

    // Thread-safe (NSLock-guarded, same pattern as EventStatsCache's own memory
    // cache) so `build(...)` can be read from the main actor while `prewarm(...)`
    // populates it from a background thread.
    private static let cacheLock = NSLock()
    private static var cache: [String: [EventAggregate]] = [:]

    /// Builds event aggregates strictly from sidebar destinations so names always
    /// match what the sidebar shows. Stats come from bookmarked summaries and caches.
    @MainActor
    static func build(appState: AppState) -> [EventAggregate] {
        build(appState: appState, tagFilter: appState.dashboardTagFilter, yearFilter: appState.dashboardYearFilter)
    }

    /// Same as `build(appState:)`, but the tag/year predicate is passed explicitly instead of
    /// being read from `appState.dashboardTagFilter`/`dashboardYearFilter` — used by Compare,
    /// which filters by two specific tags without touching the page-wide dashboard filter.
    ///
    /// Reads from the shared cache when warm (see `prewarm(appState:tagFilter:yearFilter:)`,
    /// which every consuming view should call from a `.task` before relying on this from
    /// its `body`). Falls back to a synchronous compute on a cache miss — correct, but for
    /// a large library that redoes the same expensive per-event `EventStatsCache.load` walk
    /// this file used to always do on every single call.
    @MainActor
    static func build(appState: AppState, tagFilter: EventTag?, yearFilter: Int?) -> [EventAggregate] {
        let key = cacheKey(appState: appState, tagFilter: tagFilter, yearFilter: yearFilter)
        if let cached = cacheLock.withLock({ cache[key] }) {
            return cached
        }
        let result = gatherInputs(appState: appState, tagFilter: tagFilter, yearFilter: yearFilter)
            .compactMap { assemble(from: $0, yearFilter: yearFilter) }
        cacheLock.withLock { cache[key] = result }
        return result
    }

    /// Precomputes and caches the result off the main thread. Call this from a
    /// `.task(id:)` (keyed on `appState.eventStatsCacheRevision` plus the active
    /// tag/year filter) in every view that calls `build(...)` from its `body`, so
    /// the expensive per-event disk reads happen in the background instead of
    /// blocking the main thread the first time that view renders.
    @MainActor
    static func prewarm(appState: AppState, tagFilter: EventTag?, yearFilter: Int?) async {
        let key = cacheKey(appState: appState, tagFilter: tagFilter, yearFilter: yearFilter)
        guard cacheLock.withLock({ cache[key] }) == nil else { return }
        // `gatherInputs` reads `appState.dashboardTotalStatsReport` once, synchronously,
        // on the main actor (it has to — AppState is @MainActor). That's cheap if
        // already cached, but on a cache miss it triggers a library-wide, disk-I/O-heavy
        // aggregation across every event — a multi-second hang on a large production
        // library, hiding behind this file's own already-fixed cache/prewarm pattern.
        // Same fix as `DashboardView.refreshRecentEventAggregates()`: prewarm it first.
        await appState.prewarmDashboardTotalStatsReport()
        let inputs = gatherInputs(appState: appState, tagFilter: tagFilter, yearFilter: yearFilter)
        let result = await Task.detached(priority: .userInitiated) {
            inputs.compactMap { Self.assemble(from: $0, yearFilter: yearFilter) }
        }.value
        cacheLock.withLock { cache[key] = result }
    }

    @MainActor
    private static func cacheKey(appState: AppState, tagFilter: EventTag?, yearFilter: Int?) -> String {
        let paths = appState.eventFolderCachedPaths.joined(separator: "\u{1f}")
        let previousPaths = appState.eventFolderPreviousCachedPaths.joined(separator: "\u{1f}")
        let names = appState.uniqueImportDestinations.map(\.name).joined(separator: "\u{1f}")
        return "\(appState.eventStatsCacheRevision)|\(paths)|\(previousPaths)|\(names)|\(tagFilter?.rawValue ?? "-")|\(yearFilter.map(String.init) ?? "-")"
    }

    @MainActor
    private static func gatherInputs(appState: AppState, tagFilter: EventTag?, yearFilter: Int?) -> [PendingAggregateInput] {
        let avgSpeed = appState.dashboardTotalStatsReport?.averageSpeed ?? 0

        return appState.uniqueImportDestinations.compactMap { destination -> PendingAggregateInput? in
            guard !destination.path.isEmpty else { return nil }

            let eventTags = appState.tags(at: destination.bookmarkIndex)
            if let tagFilter, !eventTags.contains(tagFilter) { return nil }

            let effectiveName: String
            if isInvalidEventName(destination.name) {
                let root = inferredEventRoot(from: normalize(destination.path))
                effectiveName = URL(fileURLWithPath: root).lastPathComponent
            } else {
                effectiveName = destination.name
            }
            let displayName = appState.displayNameForEvent(at: destination.bookmarkIndex) ?? effectiveName
            guard !isInvalidEventName(displayName) else { return nil }

            let previousPath = destination.bookmarkIndex < appState.eventFolderPreviousCachedPaths.count
                ? appState.eventFolderPreviousCachedPaths[destination.bookmarkIndex]
                : ""
            let summary = appState.importStats(
                forEventPath: destination.path,
                alternatePaths: [previousPath],
                eventName: displayName
            )
            let finalized = appState.finalizedEvent(forBookmarkIndex: destination.bookmarkIndex)
            let peak = destination.bookmarkIndex < appState.eventFolderPeakRawCounts.count
                ? appState.eventFolderPeakRawCounts[destination.bookmarkIndex] : 0
            let cached = destination.bookmarkIndex < appState.eventFolderCachedCounts.count
                ? max(appState.eventFolderCachedCounts[destination.bookmarkIndex], 0) : 0
            let files = max(summary?.photoCount ?? 0, max(finalized?.photoCount ?? 0, max(peak, cached)))
            guard files > 0 else { return nil }
            let displayDate = appState.effectiveDateForEvent(at: destination.bookmarkIndex) ?? .distantPast
            let currentPath = destination.bookmarkIndex < appState.eventFolderCachedPaths.count
                ? appState.eventFolderCachedPaths[destination.bookmarkIndex] : ""

            return PendingAggregateInput(
                path: destination.path,
                name: displayName,
                bookmarkIndex: destination.bookmarkIndex,
                totalFiles: files,
                totalBytesFromMetadata: max(summary?.totalBytes ?? 0, finalized?.totalBytes ?? 0),
                finalizedSnapshot: finalized?.snapshot,
                currentCachePath: currentPath,
                previousCachePath: previousPath,
                displayDate: displayDate,
                averageSpeed: avgSpeed,
                tags: eventTags
            )
        }
    }

    /// The actual expensive step (`EventStatsCache.load`, a disk read + JSON
    /// decode) — kept `nonisolated`/`static` so it only touches its plain-value
    /// argument and can safely run on a background thread via `Task.detached`.
    /// A locked (finalized) event's snapshot is taken at finalize time and can
    /// predate a deep scan that finished afterwards (e.g. the user hit Refresh
    /// post-finalize), so the live cache is always consulted too, same as before.
    nonisolated private static func assemble(from pending: PendingAggregateInput, yearFilter: Int?) -> EventAggregate? {
        let liveReport: StatsReport? = (!pending.currentCachePath.isEmpty ? EventStatsCache.load(forPath: pending.currentCachePath)?.report : nil)
            ?? (!pending.previousCachePath.isEmpty ? EventStatsCache.load(forPath: pending.previousCachePath)?.report : nil)
        let statsReport = pending.finalizedSnapshot ?? liveReport
        let shootingMetrics = statsReport?.shootingTimeMetrics
        let bytes = max(pending.totalBytesFromMetadata, max(statsReport?.totalBytes ?? 0, liveReport?.totalBytes ?? 0))

        if let yearFilter {
            guard (statsReport?.yearCounts[String(yearFilter)] ?? 0) > 0 else { return nil }
        }

        return EventAggregate(
            id: pending.path,
            name: pending.name,
            totalFiles: pending.totalFiles,
            totalBytes: bytes,
            totalWorkingSeconds: shootingMetrics?.totalCoverageSeconds ?? 0,
            totalShootingSeconds: shootingMetrics?.totalShootingSeconds ?? 0,
            longestCoverageDaySeconds: shootingMetrics?.longestCoverageDay?.coverageSeconds ?? 0,
            longestCoverageDayKey: shootingMetrics?.longestCoverageDay?.dayKey,
            averageSpeed: pending.averageSpeed,
            lastDate: pending.displayDate,
            bookmarkIndex: pending.bookmarkIndex,
            tags: pending.tags
        )
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
        guard numericParts.count >= 3 else { return false }

        let hasYear = numericParts.contains { $0.count == 4 }
        let hasShortDateParts = numericParts.contains { part in
            guard let value = Int(part) else { return false }
            return value >= 1 && value <= 31
        }
        return hasYear && hasShortDateParts
    }

    static func sortByPhotoCount(_ lhs: EventAggregate, _ rhs: EventAggregate) -> Bool {
        if lhs.totalFiles != rhs.totalFiles { return lhs.totalFiles > rhs.totalFiles }
        if lhs.totalBytes != rhs.totalBytes { return lhs.totalBytes > rhs.totalBytes }
        return lhs.lastDate > rhs.lastDate
    }

    static func sort(_ lhs: EventAggregate, _ rhs: EventAggregate, by metric: TopEventsMetric) -> Bool {
        switch metric {
        case .raw:
            return sortByPhotoCount(lhs, rhs)
        case .totalWorkingHours:
            if lhs.totalWorkingSeconds != rhs.totalWorkingSeconds {
                return lhs.totalWorkingSeconds > rhs.totalWorkingSeconds
            }
        case .shootingTime:
            if lhs.totalShootingSeconds != rhs.totalShootingSeconds {
                return lhs.totalShootingSeconds > rhs.totalShootingSeconds
            }
        case .longestCoverageDay:
            if lhs.longestCoverageDaySeconds != rhs.longestCoverageDaySeconds {
                return lhs.longestCoverageDaySeconds > rhs.longestCoverageDaySeconds
            }
        }
        return sortByPhotoCount(lhs, rhs)
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
    var onSelect: (Int) -> Void = { _ in }
    var onViewAll: () -> Void = {}
    @Binding var selectedMetric: TopEventsMetric

    // Populated only by `refreshEvents()` below — `body` never calls
    // `EventAggregator.build` directly. SwiftUI evaluates `body` synchronously
    // and immediately on mount, before any `.task` gets a chance to run, so a
    // cache-check-then-synchronous-fallback inside `body` (what this used to do)
    // still hit the expensive fallback on basically every first render — the
    // async prewarm could never win that race. Reading from `@State` here means
    // the first render is always cheap (empty list), and results pop in once the
    // background work finishes.
    @State private var cachedEvents: [EventAggregate] = []
    // Distinguishes "still loading" from "genuinely empty" — without this,
    // the first render (before `refreshEvents()` finishes) reads the same
    // empty `cachedEvents` as a library with zero events, flashing "No events
    // imported yet" for the ~1-3s the background load takes.
    @State private var hasLoadedOnce = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let allEvents = cachedEvents
                .sorted { EventAggregator.sort($0, $1, by: selectedMetric) }
            header(showViewAll: allEvents.count > 5)

            let sorted = allEvents
                .prefix(5)
                .map { aggregate in
                        LatestEventDisplay(
                            aggregate: aggregate,
                            bookmarkIndex: bookmarkIndex(for: aggregate.id),
                            bannerImagePath: appState.bannerImagePath(forEventPath: aggregate.id)
                        )
                }

            if !hasLoadedOnce {
                AuroraSkeletonEventList()
            } else if sorted.isEmpty {
                emptyState
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, event in
                        TopEventRow(rank: idx + 1, event: event, metric: selectedMetric) {
                            if let bookmarkIndex = event.bookmarkIndex {
                                onSelect(bookmarkIndex)
                            }
                        }
                    }
                }
                .animation(.spring(response: 0.34, dampingFraction: 0.82), value: selectedMetric)
            }
        }
        .auroraCollapsibleStaticCard(storageKey: "dashboard.topEvents")
        // Populates `cachedEvents` off the main thread — `body` above never calls
        // `EventAggregator.build` itself, so the first render (and every render
        // right after a stats change) is always cheap; the real list pops in once
        // this finishes instead of blocking that first render.
        // Debounced: a deep scan bumps this revision once per batch (10-50+ times
        // for a large event), and the work runs in a non-cancellable
        // `Task.detached` — without the delay, a long scan would pile up that many
        // overlapping background aggregations instead of settling on one.
        .task(id: appState.eventStatsCacheRevision) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await refreshEvents()
        }
        .task(id: "\(appState.dashboardTagFilter?.rawValue ?? "-")|\(appState.dashboardYearFilter.map(String.init) ?? "-")") {
            await refreshEvents()
        }
    }

    private func refreshEvents() async {
        await EventAggregator.prewarm(appState: appState, tagFilter: appState.dashboardTagFilter, yearFilter: appState.dashboardYearFilter)
        cachedEvents = EventAggregator.build(appState: appState, tagFilter: appState.dashboardTagFilter, yearFilter: appState.dashboardYearFilter)
        hasLoadedOnce = true
    }

    private func header(showViewAll: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            AuroraCollapsibleHeaderTitle(title: "Top Events Per")

            Menu {
                ForEach(TopEventsMetric.allCases) { metric in
                    Button(metric.rawValue) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            selectedMetric = metric
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedMetric.rawValue)
                        .font(.manrope(10.5, weight: .heavy))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(selectedMetric.tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(selectedMetric.tint.opacity(0.12)))
                .overlay(Capsule(style: .continuous).strokeBorder(selectedMetric.tint.opacity(0.25), lineWidth: 1))
                .contentTransition(.opacity)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if showViewAll {
                Button(action: onViewAll) {
                    Text("View all →")
                        .font(.manrope(11.5, weight: .semibold))
                        .foregroundStyle(Color.auroraCyan)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 12)
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

    private func bookmarkIndex(for path: String) -> Int? {
        let eventPath = normalize(path)
        return appState.uniqueImportDestinations.first { destination in
            let destinationPath = normalize(destination.path)
            return destinationPath == eventPath
                || destinationPath.hasPrefix(eventPath + "/")
                || eventPath.hasPrefix(destinationPath + "/")
        }?.bookmarkIndex
    }

    private func normalize(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

struct LatestEventsPanel: View {
    @Bindable var appState: AppState
    var onSelect: (Int) -> Void = { _ in }
    var onViewAll: () -> Void = {}

    // Same reasoning as TopEventsPanel/EventAggregator above: this used to call
    // `latestEventDisplay` (which hits `EventStatsCache.load`, a disk read, once
    // per event) directly from `body`. Because this panel sits below the fold,
    // SwiftUI didn't evaluate that body at all until it first scrolled into
    // view — so the expensive work landed squarely on the first scroll after
    // launch, freezing the whole app for as long as the per-event disk reads
    // took. Populated only by `refreshEvents()`; `body` never calls
    // `latestEventDisplay`/`EventStatsCache.load` itself.
    @State private var cachedEvents: [LatestEventDisplay] = []
    // Distinguishes "still loading" from "genuinely empty" — see the matching
    // comment in TopEventsPanel.swift.
    @State private var hasLoadedOnce = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Latest Events", actionLabel: cachedEvents.count > 5 ? "View all →" : nil, action: onViewAll)

            let sorted = cachedEvents.prefix(5)

            if !hasLoadedOnce {
                AuroraSkeletonEventList()
            } else if sorted.isEmpty {
                emptyState
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, event in
                        LatestEventRow(rank: idx + 1, event: event, appState: appState) {
                            if let bookmarkIndex = event.bookmarkIndex {
                                onSelect(bookmarkIndex)
                            }
                        }
                    }
                }
            }
        }
        .auroraCollapsibleStaticCard(storageKey: "dashboard.latestEvents")
        .task(id: appState.eventStatsCacheRevision) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await refreshEvents()
        }
        .task(id: "\(appState.dashboardTagFilter?.rawValue ?? "-")|\(appState.dashboardYearFilter.map(String.init) ?? "-")") {
            await refreshEvents()
        }
    }

    private func refreshEvents() async {
        // Same fix as `DashboardView.refreshRecentEventAggregates()`/`EventAggregator.prewarm`:
        // `gatherInputs()` reads `appState.dashboardTotalStatsReport` once, synchronously,
        // on the main actor. On a cache miss that triggers a library-wide, disk-I/O-heavy
        // aggregation across every event — prewarm it off the main thread first.
        await appState.prewarmDashboardTotalStatsReport()
        let inputs = gatherInputs()
        cachedEvents = await Task.detached(priority: .userInitiated) {
            inputs.compactMap(Self.assemble).sorted(by: Self.latestEventSort)
        }.value
        hasLoadedOnce = true
    }

    @MainActor
    private func gatherInputs() -> [PendingLatestEventInput] {
        appState.uniqueImportDestinations.compactMap { destination -> PendingLatestEventInput? in
            let eventTags = appState.tags(at: destination.bookmarkIndex)
            if let tagFilter = appState.dashboardTagFilter, !eventTags.contains(tagFilter) { return nil }

            let previousPath = destination.bookmarkIndex < appState.eventFolderPreviousCachedPaths.count
                ? appState.eventFolderPreviousCachedPaths[destination.bookmarkIndex]
                : ""
            let displayName = appState.displayNameForEvent(at: destination.bookmarkIndex) ?? destination.name
            let summary = appState.importStats(
                forEventPath: destination.path,
                alternatePaths: [previousPath],
                eventName: displayName
            )
            let finalized = appState.finalizedEvent(forBookmarkIndex: destination.bookmarkIndex)
            let peak = destination.bookmarkIndex < appState.eventFolderPeakRawCounts.count
                ? appState.eventFolderPeakRawCounts[destination.bookmarkIndex]
                : 0
            let cached = destination.bookmarkIndex < appState.eventFolderCachedCounts.count
                ? max(appState.eventFolderCachedCounts[destination.bookmarkIndex], 0)
                : 0
            let totalFiles = max(summary?.photoCount ?? 0, max(finalized?.photoCount ?? 0, max(peak, cached)))
            let displayDate = appState.effectiveDateForEvent(at: destination.bookmarkIndex) ?? .distantPast
            let currentPath = destination.bookmarkIndex < appState.eventFolderCachedPaths.count
                ? appState.eventFolderCachedPaths[destination.bookmarkIndex] : ""
            let bannerPath: String? = if destination.bookmarkIndex < appState.eventFolderBannerImagePaths.count {
                appState.eventFolderBannerImagePaths[destination.bookmarkIndex].isEmpty
                    ? nil
                    : appState.eventFolderBannerImagePaths[destination.bookmarkIndex]
            } else {
                nil
            }

            return PendingLatestEventInput(
                path: destination.path,
                name: displayName,
                bookmarkIndex: destination.bookmarkIndex,
                totalFiles: totalFiles,
                totalBytesFromMetadata: max(summary?.totalBytes ?? 0, finalized?.totalBytes ?? 0),
                finalizedSnapshot: finalized?.snapshot,
                currentCachePath: currentPath,
                previousCachePath: previousPath,
                displayDate: displayDate,
                averageSpeed: appState.dashboardTotalStatsReport?.averageSpeed ?? 0,
                tags: eventTags,
                yearFilter: appState.dashboardYearFilter,
                bannerImagePath: bannerPath
            )
        }
    }

    // The actual expensive step (`EventStatsCache.load`, a disk read + JSON
    // decode) — `nonisolated`/`static` so it only touches its plain-value
    // argument and can safely run on a background thread via `Task.detached`.
    nonisolated private static func assemble(from pending: PendingLatestEventInput) -> LatestEventDisplay? {
        let liveReport: StatsReport? = (!pending.currentCachePath.isEmpty ? EventStatsCache.load(forPath: pending.currentCachePath)?.report : nil)
            ?? (!pending.previousCachePath.isEmpty ? EventStatsCache.load(forPath: pending.previousCachePath)?.report : nil)
        let statsReport = pending.finalizedSnapshot ?? liveReport

        if let yearFilter = pending.yearFilter {
            guard (statsReport?.yearCounts[String(yearFilter)] ?? 0) > 0 else { return nil }
        }

        let aggregate = EventAggregate(
            id: pending.path,
            name: pending.name,
            totalFiles: pending.totalFiles,
            totalBytes: max(pending.totalBytesFromMetadata, max(statsReport?.totalBytes ?? 0, liveReport?.totalBytes ?? 0)),
            totalWorkingSeconds: (statsReport?.shootingTimeMetrics)?.totalCoverageSeconds ?? 0,
            totalShootingSeconds: (statsReport?.shootingTimeMetrics)?.totalShootingSeconds ?? 0,
            longestCoverageDaySeconds: (statsReport?.shootingTimeMetrics)?.longestCoverageDay?.coverageSeconds ?? 0,
            longestCoverageDayKey: (statsReport?.shootingTimeMetrics)?.longestCoverageDay?.dayKey,
            averageSpeed: pending.averageSpeed,
            lastDate: pending.displayDate,
            bookmarkIndex: pending.bookmarkIndex,
            tags: pending.tags
        )
        return LatestEventDisplay(aggregate: aggregate, bookmarkIndex: pending.bookmarkIndex, bannerImagePath: pending.bannerImagePath)
    }

    nonisolated private static func latestEventSort(_ lhs: LatestEventDisplay, _ rhs: LatestEventDisplay) -> Bool {
        if lhs.aggregate.lastDate != rhs.aggregate.lastDate {
            return lhs.aggregate.lastDate > rhs.aggregate.lastDate
        }
        return (lhs.bookmarkIndex ?? -1) > (rhs.bookmarkIndex ?? -1)
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
}

private struct PendingLatestEventInput {
    let path: String
    let name: String
    let bookmarkIndex: Int
    let totalFiles: Int
    let totalBytesFromMetadata: Int64
    let finalizedSnapshot: StatsReport?
    let currentCachePath: String
    let previousCachePath: String
    let displayDate: Date
    let averageSpeed: Double
    let tags: Set<EventTag>
    let yearFilter: Int?
    let bannerImagePath: String?
}

struct LatestEventDisplay: Identifiable {
    let aggregate: EventAggregate
    let bookmarkIndex: Int?
    let bannerImagePath: String?

    var id: String { aggregate.id }
}

struct TopEventRow: View {
    let rank: Int
    let event: LatestEventDisplay
    var metric: TopEventsMetric = .raw
    var onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RankBadge(rank: rank)
                EventThumbnail(
                    eventName: event.aggregate.name,
                    bannerImagePath: event.bannerImagePath
                )
                .frame(width: 44, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.aggregate.name)
                        .font(.auroraEventName)
                        .foregroundStyle(Color.auroraTxt)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.manrope(11, weight: .semibold))
                            .foregroundStyle(Color.auroraFaint)
                    }
                }
                Spacer(minLength: 4)
                SpeedPill(text: pillText, tint: metric.tint)
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

    private var subtitle: String? {
        switch metric {
        case .raw:
            let parts = AuroraFormat.bytesParts(event.aggregate.totalBytes)
            return "\(parts.value) \(parts.unit)"
        case .totalWorkingHours:
            return nil
        case .shootingTime:
            return nil
        case .longestCoverageDay:
            return event.aggregate.longestCoverageDayKey.map(formatDayKey)
        }
    }

    private var pillText: String {
        switch metric {
        case .raw:
            return AuroraFormat.count(event.aggregate.totalFiles)
        case .totalWorkingHours:
            return formatDuration(event.aggregate.totalWorkingSeconds)
        case .shootingTime:
            return formatDuration(event.aggregate.totalShootingSeconds)
        case .longestCoverageDay:
            return formatDuration(event.aggregate.longestCoverageDaySeconds)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 { return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }

    private func formatDayKey(_ dayKey: String) -> String {
        guard let date = Self.dayKeyFormatter.date(from: dayKey) else { return dayKey }
        return AuroraFormat.dateCompact(date)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

struct LatestEventRow: View {
    let rank: Int
    let event: LatestEventDisplay
    @Bindable var appState: AppState
    var onTap: () -> Void

    @State private var hovering = false
    @State private var isEditingDate = false
    @State private var draftDate = Date()

    var body: some View {
        HStack(spacing: 12) {
            RankBadge(rank: rank)
            EventThumbnail(
                eventName: event.aggregate.name,
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
                    .contentShape(Rectangle())
                    .help(dateHelpText)
                    .highPriorityGesture(TapGesture().onEnded {
                        guard event.bookmarkIndex != nil else { return }
                        draftDate = editableDate
                        isEditingDate = true
                    })
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
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
        .popover(isPresented: $isEditingDate, arrowEdge: .bottom) {
            manualDateEditor
        }
    }

    private var dateText: String {
        event.aggregate.lastDate == .distantPast ? "—" : AuroraFormat.dateCompact(event.aggregate.lastDate)
    }

    private var dateHelpText: String {
        event.bookmarkIndex == nil ? "" : "Click to set a manual event date"
    }

    private var editableDate: Date {
        if let bookmarkIndex = event.bookmarkIndex,
           let manual = appState.manualDateForEvent(at: bookmarkIndex) {
            return manual
        }
        return event.aggregate.lastDate == .distantPast ? Date() : event.aggregate.lastDate
    }

    private var manualDateEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual Event Date")
                .font(.manrope(13, weight: .bold))
                .foregroundStyle(Color.auroraTxt)
            HStack {
                Spacer(minLength: 0)
                AuroraManualDatePicker(selection: $draftDate)
                    .frame(width: 190)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button("Clear") {
                    if let bookmarkIndex = event.bookmarkIndex {
                        appState.setManualDateForEvent(at: bookmarkIndex, date: nil)
                    }
                    isEditingDate = false
                }
                .buttonStyle(AuroraGhostButtonStyle())
                Spacer()
                Button("Save") {
                    if let bookmarkIndex = event.bookmarkIndex {
                        appState.setManualDateForEvent(at: bookmarkIndex, date: draftDate)
                    }
                    isEditingDate = false
                }
                .buttonStyle(AuroraGradientButtonStyle(compact: true))
            }
        }
        .padding(16)
        .frame(width: 252)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .fill(Color.auroraBg2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke2, lineWidth: 1)
        )
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
