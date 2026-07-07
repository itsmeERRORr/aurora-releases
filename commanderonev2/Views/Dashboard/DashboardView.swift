import SwiftUI
import AppKit

/// One "Recent Events"/"Recent Added Folders" card's worth of data once assembled.
private typealias RecentEventItem = (event: EventAggregate, bannerPath: String?, bookmarkIndex: Int, isFinalized: Bool)

struct DashboardView: View {
    @Bindable var appState: AppState
    let volumeWatcher: VolumeWatcher?
    let statsRunner: StatsRunner?

    @State private var isCreatingEvent = false
    // Populated asynchronously by `refreshRecentEventAggregates()` — these used to
    // be computed properties that re-ran `EventStatsCache.load(forPath:)` (a
    // synchronous disk read + JSON decode of a StatsReport, which for an event with
    // many RAWs is a sizeable payload) for *every* event/folder in the whole
    // library on *every* body re-evaluation — which happens on basically any
    // appState change while Dashboard is visible. On a fresh launch (cold
    // EventStatsCache in-memory cache), that was a synchronous main-thread burst
    // across the entire library, i.e. the multi-second freeze right after opening
    // the app. Now the grid renders straight from these arrays and the expensive
    // work happens off the main thread.
    @State private var recentEventItems: [RecentEventItem] = []
    @State private var recentAddedFolderItems: [RecentEventItem] = []

    let onImportNow: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    var onViewAllEvents: () -> Void = {}
    var onSelectEvent: (EventAggregate) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topbar

                heroRow

                FileBrowserRow(appState: appState)

                recentEvents

                recentAddedFolders
            }
            .padding(.horizontal, AuroraSpacing.mainPaddingH)
            .padding(.vertical, AuroraSpacing.mainPaddingV)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $isCreatingEvent) {
            CreateEventSheet { name, folderURL in
                createEvent(name: name, folderURL: folderURL)
            }
        }
        // Runs once on first appear (both ids are non-nil from the start), and again
        // whenever event stats change anywhere in the app (revision bump) or a
        // folder is added/removed (bookmark count change) — not on every unrelated
        // appState mutation like the old computed-property version did.
        // Debounced: a deep scan's progress callback bumps the revision once per
        // batch (could be 10-50+ times for a large event), and the actual work
        // below runs in a non-cancellable `Task.detached` — without this delay,
        // a long scan would pile up that many overlapping background aggregations
        // instead of settling on one once progress actually stops.
        .task(id: appState.eventStatsCacheRevision) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await refreshRecentEventAggregates()
        }
        .task(id: appState.eventFolderBookmarks.count) { await refreshRecentEventAggregates() }
    }

    @ViewBuilder
    private var recentAddedFolders: some View {
        let items = recentAddedFolderItems.prefix(4)

        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                AuroraPanelHeader(title: "Recent Added Folders", actionLabel: nil, action: nil)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: AuroraSpacing.gridGap), count: 4),
                    spacing: AuroraSpacing.gridGap
                ) {
                    ForEach(Array(items), id: \.event.id) { item in
                        RecentEventThumb(event: item.event, bannerImagePath: item.bannerPath) {
                            onSelectEvent(item.event)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Topbar

    private var topbar: some View {
        HStack(spacing: 14) {
            IconChip(systemName: "square.grid.2x2.fill", color: .auroraCyan, size: 36, iconScale: 0.5)
            Text("Dashboard")
                .font(.auroraTopbarH2)
                .tracking(-0.4)
                .foregroundStyle(Color.auroraTxt)
            Spacer()
            Button(action: beginCreateEvent) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("New Event")
                }
            }
            .buttonStyle(AuroraGradientButtonStyle(compact: true))
        }
        .padding(.bottom, 20)
    }

    // MARK: - Hero row

    private var heroRow: some View {
        HStack(alignment: .top, spacing: AuroraSpacing.gridGap) {
            TotalLibraryCard(appState: appState)
                .frame(maxWidth: .infinity)
            WaitingCard(
                appState: appState,
                onImportNow: onImportNow,
                onPause: onPause,
                onResume: onResume,
                onCancel: onCancel
            )
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Recent events

    @ViewBuilder
    private var recentEvents: some View {
        let visibleItems = recentEventItems.prefix(4)

        if !visibleItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                AuroraPanelHeader(title: "Recent Events", actionLabel: recentEventItems.count > 5 ? "View all →" : nil, action: onViewAllEvents)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: AuroraSpacing.gridGap), count: 4),
                    spacing: AuroraSpacing.gridGap
                ) {
                    ForEach(Array(visibleItems), id: \.event.id) { item in
                        RecentEventThumb(event: item.event, bannerImagePath: item.bannerPath) {
                            onSelectEvent(item.event)
                        }
                    }
                }
            }
        }
    }

    private func recentEventSort(
        _ lhs: (event: EventAggregate, bannerPath: String?, bookmarkIndex: Int, isFinalized: Bool),
        _ rhs: (event: EventAggregate, bannerPath: String?, bookmarkIndex: Int, isFinalized: Bool)
    ) -> Bool {
        if lhs.event.lastDate != rhs.event.lastDate { return lhs.event.lastDate > rhs.event.lastDate }
        if lhs.isFinalized != rhs.isFinalized { return !lhs.isFinalized }
        return lhs.bookmarkIndex > rhs.bookmarkIndex
    }

    private func bannerImagePath(for bookmarkIndex: Int) -> String? {
        guard bookmarkIndex >= 0,
              bookmarkIndex < appState.eventFolderBannerImagePaths.count else { return nil }
        let path = appState.eventFolderBannerImagePaths[bookmarkIndex]
        return path.isEmpty ? nil : path
    }

    /// Everything `assembleAggregate(from:)` needs, gathered from `appState` while
    /// still on the main actor (all of this is cheap array/dictionary lookups — no
    /// disk I/O). The one genuinely expensive step, `EventStatsCache.load`, is
    /// deliberately *not* done here; it happens off-thread in `assembleAggregate`.
    private struct PendingEventAggregate {
        let path: String
        let name: String
        let bookmarkIndex: Int
        let totalFiles: Int
        let totalBytesFromMetadata: Int64
        let finalizedSnapshot: StatsReport?
        let isFinalized: Bool
        let currentCachePath: String
        let previousCachePath: String
        let displayDate: Date
        let averageSpeed: Double
        let tags: Set<EventTag>
        let bannerPath: String?
    }

    /// `reportsAsFinalized` mirrors the original behavior: "Recent Events" reports
    /// its real finalized state, while "Recent Added Folders" always reports
    /// `false` (library folders can't be finalized in the first place).
    private func gatherPendingAggregate(
        for destination: (path: String, name: String, bookmarkIndex: Int),
        reportsAsFinalized: Bool
    ) -> PendingEventAggregate? {
        guard !destination.path.isEmpty else { return nil }

        let summary = appState.importStatsForEventFolder(at: destination.bookmarkIndex)
        let finalized = appState.finalizedEvent(forBookmarkIndex: destination.bookmarkIndex)
        let peak = destination.bookmarkIndex < appState.eventFolderPeakRawCounts.count
            ? appState.eventFolderPeakRawCounts[destination.bookmarkIndex]
            : 0
        let cached = destination.bookmarkIndex < appState.eventFolderCachedCounts.count
            ? max(appState.eventFolderCachedCounts[destination.bookmarkIndex], 0)
            : 0
        let totalFiles = max(summary?.photoCount ?? 0, max(finalized?.photoCount ?? 0, max(peak, cached)))
        let currentPath = destination.bookmarkIndex < appState.eventFolderCachedPaths.count
            ? appState.eventFolderCachedPaths[destination.bookmarkIndex] : ""
        let previousPath = destination.bookmarkIndex < appState.eventFolderPreviousCachedPaths.count
            ? appState.eventFolderPreviousCachedPaths[destination.bookmarkIndex] : ""
        let displayDate = appState.effectiveDateForEvent(at: destination.bookmarkIndex) ?? .distantPast

        return PendingEventAggregate(
            path: destination.path,
            name: destination.name,
            bookmarkIndex: destination.bookmarkIndex,
            totalFiles: totalFiles,
            totalBytesFromMetadata: max(summary?.totalBytes ?? 0, finalized?.totalBytes ?? 0),
            finalizedSnapshot: finalized?.snapshot,
            isFinalized: reportsAsFinalized ? (finalized != nil) : false,
            currentCachePath: currentPath,
            previousCachePath: previousPath,
            displayDate: displayDate,
            averageSpeed: appState.dashboardTotalStatsReport?.averageSpeed ?? 0,
            tags: appState.tags(at: destination.bookmarkIndex),
            bannerPath: bannerImagePath(for: destination.bookmarkIndex)
        )
    }

    /// The actual expensive step (`EventStatsCache.load`, a disk read + JSON
    /// decode) — kept `nonisolated`/`static` so it only touches its plain-value
    /// argument and can safely run on a background thread via `Task.detached`.
    nonisolated private static func assembleAggregate(from pending: PendingEventAggregate) -> RecentEventItem {
        let liveReport: StatsReport? = (!pending.currentCachePath.isEmpty ? EventStatsCache.load(forPath: pending.currentCachePath)?.report : nil)
            ?? (!pending.previousCachePath.isEmpty ? EventStatsCache.load(forPath: pending.previousCachePath)?.report : nil)
        let report = pending.finalizedSnapshot ?? liveReport
        let totalBytes = max(pending.totalBytesFromMetadata, max(report?.totalBytes ?? 0, liveReport?.totalBytes ?? 0))
        let metrics = report?.shootingTimeMetrics

        let event = EventAggregate(
            id: pending.path,
            name: pending.name,
            totalFiles: pending.totalFiles,
            totalBytes: totalBytes,
            totalWorkingSeconds: metrics?.totalCoverageSeconds ?? 0,
            totalShootingSeconds: metrics?.totalShootingSeconds ?? 0,
            longestCoverageDaySeconds: metrics?.longestCoverageDay?.coverageSeconds ?? 0,
            longestCoverageDayKey: metrics?.longestCoverageDay?.dayKey,
            averageSpeed: pending.averageSpeed,
            lastDate: pending.displayDate,
            bookmarkIndex: pending.bookmarkIndex,
            tags: pending.tags
        )
        return (event: event, bannerPath: pending.bannerPath, bookmarkIndex: pending.bookmarkIndex, isFinalized: pending.isFinalized)
    }

    /// Gathers the cheap per-event inputs on the main actor (fast), then does the
    /// actual cache reads off the main thread, then writes the results back. This
    /// is what replaced the old synchronous `recentEventDisplay`/`cachedReport`
    /// computed-property pipeline that caused the launch-time freeze.
    private func refreshRecentEventAggregates() async {
        // `gatherPendingAggregate` reads `appState.dashboardTotalStatsReport` once
        // per event, synchronously, on the main actor (it has to — AppState is
        // @MainActor). That's cheap *if already cached*, but on a cache miss it
        // triggers a library-wide, disk-I/O-heavy aggregation (see
        // `aggregateDashboardTotalStatsReport`) — which for a large production
        // library was a second, bigger hang hiding behind the first one this
        // function's own refactor fixed. Prewarming it here, off the main thread,
        // *before* the per-event loop below means that loop only ever sees the
        // already-cached, cheap value.
        await appState.prewarmDashboardTotalStatsReport()

        let destinations = appState.uniqueImportDestinations
        let eventPending = destinations
            .filter { !appState.isLibraryFolder(at: $0.bookmarkIndex) }
            .compactMap { gatherPendingAggregate(for: $0, reportsAsFinalized: true) }
        let folderPending = destinations
            .filter { appState.isLibraryFolder(at: $0.bookmarkIndex) }
            .compactMap { gatherPendingAggregate(for: $0, reportsAsFinalized: false) }

        let (events, folders) = await Task.detached(priority: .userInitiated) { () -> ([RecentEventItem], [RecentEventItem]) in
            (eventPending.map(Self.assembleAggregate), folderPending.map(Self.assembleAggregate))
        }.value

        recentEventItems = events.sorted(by: recentEventSort)
        recentAddedFolderItems = folders.sorted(by: recentEventSort)
    }

    // MARK: - Actions

    private func beginCreateEvent() {
        isCreatingEvent = true
    }

    private func createEvent(name: String, folderURL: URL) -> String? {
        guard let bookmark = BookmarkManager.saveBookmark(for: folderURL) else {
            return "Aurora could not save access to this folder. Choose a different folder and try again."
        }
        let bookmarkIndex = appState.addEventFolder(bookmark: bookmark, displayName: name)
        appState.scanEventFolderIfRawFilesExist(at: bookmarkIndex, mergeIntoGlobalTotals: true)

        return nil
    }
}

private struct CreateEventSheet: View {
    let onCreate: (String, URL) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var eventName = ""
    @State private var folderURL: URL?
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        eventName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canChooseFolder: Bool {
        !trimmedName.isEmpty
    }

    private var canCreate: Bool {
        canChooseFolder && folderURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                IconChip(systemName: "folder.badge.plus", color: .auroraCyan, size: 38, iconScale: 0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Event")
                        .font(.sora(20, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                    Text("Name the event first, then choose its main folder.")
                        .font(.manrope(12, weight: .medium))
                        .foregroundStyle(Color.auroraMuted)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Event Name")
                    .font(.manrope(11, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.auroraFaint)
                TextField("R6 SLC Major 2026", text: $eventName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Main Folder")
                    .font(.manrope(11, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.auroraFaint)

                HStack(spacing: 10) {
                    IconChip(systemName: "folder.fill", color: .auroraViolet, size: 32, iconScale: 0.5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folderURL?.lastPathComponent ?? "No folder selected")
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(folderURL == nil ? Color.auroraMuted : Color.auroraTxt)
                            .lineLimit(1)
                        Text(folderURL?.path ?? "Choose where this event's photos will live")
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(folderURL == nil ? "Choose…" : "Change…", action: chooseFolder)
                        .buttonStyle(AuroraGhostButtonStyle())
                        .disabled(!canChooseFolder)
                        .opacity(canChooseFolder ? 1 : 0.45)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                        .fill(Color.auroraPanel2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                        .strokeBorder(folderURL == nil ? Color.auroraStroke : Color.auroraViolet.opacity(0.45), lineWidth: 1)
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraLive)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(AuroraGhostButtonStyle())
                Button("Create Event") { createEvent() }
                    .buttonStyle(AuroraGradientButtonStyle(compact: true))
                    .disabled(!canCreate)
                    .opacity(canCreate ? 1 : 0.45)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Color.auroraBg2)
        .onAppear { nameFocused = true }
    }

    private func chooseFolder() {
        guard canChooseFolder else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the main folder for \(trimmedName)"
        panel.prompt = "Select Folder"
        if panel.runModal() == .OK, let url = panel.url {
            folderURL = url
            errorMessage = nil
        }
    }

    private func createEvent() {
        guard let folderURL, canCreate else { return }
        if let error = onCreate(trimmedName, folderURL) {
            errorMessage = error
            return
        }
        dismiss()
    }
}

// MARK: - Total Library card

struct TotalLibraryCard: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: label + big number + subtitle
            Text("Total Library")
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Color.auroraMuted)

            Text(AuroraFormat.count(totalPhotos))
                .font(.auroraBigNumber)
                .tracking(-1.5)
                .foregroundStyle(Color.auroraTxt)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 2)

            Text(subtitle)
                .font(.manrope(12.5, weight: .semibold))
                .foregroundStyle(Color.auroraMuted)
                .lineLimit(1)
                .padding(.top, 6)

            Spacer(minLength: 16)

            // Center: Add Folder button
            HStack {
                Spacer()
                Button(action: addLibraryFolders) {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(AuroraGradientButtonStyle(compact: false))
                .disabled(!canAddLibraryFolder)
                .opacity(canAddLibraryFolder ? 1 : 0.45)
                .help(canAddLibraryFolder ? "Add folders containing RAW files to your library" : trialLimitHelp)
                Spacer()
            }

            Spacer(minLength: 16)

            // Bottom: divider + meta row
            Divider().background(Color.auroraStroke)
                .padding(.bottom, 12)

            HStack(spacing: 16) {
                metaItem(label: "Imports", value: "\(appState.importHistory.count)")
                Divider().frame(height: 22).background(Color.auroraStroke)
                metaItem(label: "Avg Speed", value: speedString)
                Divider().frame(height: 22).background(Color.auroraStroke)
                metaItem(label: eventCount == 1 ? "Event" : "Events", value: "\(eventCount)")
                Divider().frame(height: 22).background(Color.auroraStroke)
                metaItem(label: addedFolderCount == 1 ? "Added Folder" : "Added Folders", value: "\(addedFolderCount)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, AuroraSpacing.heroPaddingH)
        .padding(.vertical, AuroraSpacing.heroPaddingV)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .fill(Color.auroraPanel)
                .overlay(
                    RadialGradient(
                        colors: [Color.auroraAccent.opacity(0.18), .clear],
                        center: UnitPoint(x: 0.9, y: 0.1),
                        startRadius: 0, endRadius: 320
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke, lineWidth: 1)
        )
        .frame(minHeight: 260)
    }

    private var totalPhotos: Int {
        appState.dashboardTotalStatsReport?.totalFilesAnalyzed
            ?? appState.importHistory.reduce(0) { $0 + $1.fileCount }
    }

    private var eventCount: Int {
        appState.uniqueImportDestinations.filter { !appState.isLibraryFolder(at: $0.bookmarkIndex) }.count
    }

    private var addedFolderCount: Int {
        appState.uniqueImportDestinations.filter { appState.isLibraryFolder(at: $0.bookmarkIndex) }.count
    }

    private var canAddLibraryFolder: Bool {
        appState.canUseTrialAction()
    }

    private var trialLimitHelp: String {
        "Trial limit reached. Enter a license key to add more folders."
    }

    private var subtitle: String {
        let parts = AuroraFormat.bytesParts(appState.dashboardTotalStatsReport?.totalBytes ?? 0)
        if totalPhotos == 0 { return "Your library will appear here." }
        if eventCount > 0 {
            return "photos across \(eventCount) event\(eventCount == 1 ? "" : "s") · \(parts.value) \(parts.unit) stored"
        }
        return "photos across \(addedFolderCount) added folder\(addedFolderCount == 1 ? "" : "s") · \(parts.value) \(parts.unit) stored"
    }

    private var speedString: String {
        guard let r = appState.dashboardTotalStatsReport, r.averageSpeed > 0 else { return "—" }
        let s = AuroraFormat.speedParts(r.averageSpeed)
        return "\(s.value) \(s.unit)"
    }

    private func metaItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.sora(15, weight: .bold))
                .foregroundStyle(Color.auroraTxt)
            Text(label)
                .font(.manrope(10.5, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
        }
    }

    private func addLibraryFolders() {
        guard canAddLibraryFolder else {
            appState.requestActivationForTrialLimit()
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select folders containing RAW files to add to your library"
        panel.prompt = "Add Folder"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            appState.addLibraryFolder(url: url)
        }
    }
}

// MARK: - Waiting card

struct WaitingCard: View {
    @Bindable var appState: AppState
    let onImportNow: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void

    @State private var pulse = false
    @State private var importBorderSpin = false
    @State private var showRenameEditor = false
    @State private var renameEditorConfirmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.auroraCyan.opacity(0.55), lineWidth: 1.5)
                        .frame(width: 42, height: 42)
                        .scaleEffect(pulse ? 1.34 : 1)
                        .opacity(pulse ? 0 : 1)
                    Circle()
                        .fill(Color.auroraCyan.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: cardIcon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.auroraCyan)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.sora(18, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                    Text(subtitle)
                        .font(.manrope(12, weight: .semibold))
                        .foregroundStyle(Color.auroraMuted)
                }
                Spacer()
            }

            currentEventPicker

            destinationPicker

            Spacer(minLength: 4)

            actions
        }
        .padding(.horizontal, AuroraSpacing.heroPaddingH)
        .padding(.vertical, AuroraSpacing.heroPaddingV)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .fill(Color.auroraPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke, lineWidth: 1)
        )
        .frame(minHeight: 260)
        .onAppear {
            clearLibraryFolderDestinationIfNeeded()
            updateAnimations()
        }
        .onDisappear {
            pulse = false
            importBorderSpin = false
        }
        .onChange(of: shouldPulseWaitingCard) { _, _ in
            updateAnimations()
        }
        .onChange(of: shouldEmphasizeImportNow) { _, _ in
            updateAnimations()
        }
        .onChange(of: isImportNowBlocked) { _, _ in
            updateAnimations()
        }
        .onChange(of: appState.renameOnImport) { _, isEnabled in
            if isEnabled {
                renameEditorConfirmed = false
                showRenameEditor = true
            }
        }
        .sheet(isPresented: $showRenameEditor, onDismiss: handleRenameEditorDismiss) {
            RenameTemplateEditorSheet(appState: appState) {
                renameEditorConfirmed = true
            }
        }
    }

    private func updateAnimations() {
        if shouldPulseWaitingCard {
            pulse = false
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        } else {
            pulse = false
        }

        if shouldEmphasizeImportNow && !isImportNowBlocked {
            importBorderSpin = false
            withAnimation(.linear(duration: 1.85).repeatForever(autoreverses: false)) {
                importBorderSpin = true
            }
        } else {
            importBorderSpin = false
        }
    }

    private var cardIcon: String {
        if !importableVolumes.isEmpty { return "externaldrive.fill" }
        return "sdcard"
    }

    private var title: String {
        if importableVolumes.count > 1 {
            return "\(importableVolumes.count) cards ready"
        }
        if let vol = appState.activeVolume {
            return "Card ready: \(vol.name)"
        }
        switch appState.importState {
        case .importing: return "Importing…"
        case .scanning: return "Scanning…"
        case .paused: return "Import paused"
        default: return "Waiting for card…"
        }
    }

    private var subtitle: String {
        if importableVolumes.count > 1 {
            let total = importableVolumes.reduce(0) { $0 + $1.rawFileCount }
            return "\(AuroraFormat.count(total)) RAW files across \(importableVolumes.count) cards"
        }
        if let vol = appState.activeVolume, vol.rawFileCount > 0 {
            return "\(AuroraFormat.count(vol.rawFileCount)) RAW files detected"
        }
        if appState.activeVolume != nil { return "Inserted card detected" }
        return "Plug in a reader to start an import"
    }

    @ViewBuilder
    private var currentEventPicker: some View {
        if !openEvents.isEmpty {
            HStack(spacing: 10) {
                IconChip(systemName: "flag.checkered", color: .auroraCyan, size: 30, iconScale: 0.48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Event")
                        .font(.manrope(10.5, weight: .bold))
                        .foregroundStyle(Color.auroraFaint)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Text(activeEvent?.name ?? "No event selected")
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(activeEvent == nil ? Color.auroraMuted : Color.auroraTxt)
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    ForEach(openEvents, id: \.bookmarkIndex) { event in
                        Button {
                            chooseDestination(for: event)
                        } label: {
                            if activeEvent?.bookmarkIndex == event.bookmarkIndex {
                                Label(event.name, systemImage: "checkmark")
                            } else {
                                Text(event.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(activeEvent == nil ? "Choose Event" : "Switch")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .buttonStyle(AuroraGhostButtonStyle())
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .fill(Color.auroraPanel2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .strokeBorder(activeEvent == nil ? Color.auroraStroke : Color.auroraCyan.opacity(0.45), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var destinationPicker: some View {
        if let dest = validImportDestinationURL {
            HStack(spacing: 10) {
                IconChip(systemName: "folder.fill", color: .auroraViolet, size: 32, iconScale: 0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dest.lastPathComponent)
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                        .lineLimit(1)
                    Text(dest.path)
                        .font(.manrope(11, weight: .medium))
                        .foregroundStyle(Color.auroraFaint)
                        .lineLimit(1)
                }
                Spacer()
                Button("Change…", action: chooseDestination)
                    .buttonStyle(AuroraGhostButtonStyle())
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .fill(Color.auroraPanel2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .strokeBorder(Color.auroraStroke, lineWidth: 1)
            )
        } else {
            VStack(spacing: 2) {
                Button("Choose Destination", action: chooseDestination)
                    .buttonStyle(AuroraGradientButtonStyle(compact: true))
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)

                Text("Please choose a destination to import the files")
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to import photos"
        panel.prompt = "Select"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = BookmarkManager.saveBookmark(for: url) else { return }
        appState.destinationURL = url
        appState.destinationBookmarkData = data
        appState.activeEventFolderIndex = eventContainingDestination(url.path)?.bookmarkIndex
    }

    private var validImportDestinationURL: URL? {
        guard let destinationURL = appState.destinationURL else { return nil }
        return isLibraryFolderPath(destinationURL.path) ? nil : destinationURL
    }

    private func clearLibraryFolderDestinationIfNeeded() {
        guard let destinationURL = appState.destinationURL,
              isLibraryFolderPath(destinationURL.path) else { return }
        appState.destinationURL = nil
        appState.destinationBookmarkData = nil
        appState.activeEventFolderIndex = nil
    }

    private func isLibraryFolderPath(_ path: String) -> Bool {
        let destinationPath = normalizedPath(path)
        return appState.uniqueImportDestinations.contains { event in
            appState.isLibraryFolder(at: event.bookmarkIndex)
                && normalizedPath(event.path) == destinationPath
        }
    }

    private var openEvents: [(path: String, name: String, bookmarkIndex: Int)] {
        appState.uniqueImportDestinations.filter { event in
            !event.path.isEmpty
                && appState.finalizedEvent(forBookmarkIndex: event.bookmarkIndex) == nil
                && !appState.isLibraryFolder(at: event.bookmarkIndex)
        }
    }

    private var activeEvent: (path: String, name: String, bookmarkIndex: Int)? {
        if let index = appState.activeEventFolderIndex,
           let event = openEvents.first(where: { $0.bookmarkIndex == index }) {
            return event
        }
        guard let destination = validImportDestinationURL else { return nil }
        let destinationPath = normalizedPath(destination.path)
        return eventContainingDestination(destinationPath)
    }

    private func eventContainingDestination(_ path: String) -> (path: String, name: String, bookmarkIndex: Int)? {
        let destinationPath = normalizedPath(path)
        return openEvents
            .sorted { $0.path.count > $1.path.count }
            .first { event in
                let eventPath = normalizedPath(event.path)
                return destinationPath == eventPath || destinationPath.hasPrefix(eventPath + "/")
            }
    }

    private func chooseDestination(for event: (path: String, name: String, bookmarkIndex: Int)) {
        appState.activeEventFolderIndex = event.bookmarkIndex
        let url = URL(fileURLWithPath: event.path)
        appState.destinationURL = url
        appState.destinationBookmarkData = BookmarkManager.saveBookmark(for: url)
    }

    private func normalizedPath(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private var actions: some View {
        HStack(spacing: 10) {
            switch appState.importState {
            case .importing:
                Button("Pause", action: onPause).buttonStyle(AuroraGhostButtonStyle())
                Button("Cancel", action: onCancel).buttonStyle(AuroraGhostButtonStyle())
            case .paused:
                Button("Resume", action: onResume).buttonStyle(AuroraGradientButtonStyle(compact: true))
                Button("Cancel", action: onCancel).buttonStyle(AuroraGhostButtonStyle())
            default:
                let importBlocked = isImportNowBlocked
                Button {
                    onImportNow()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold))
                        Text(importableVolumes.count > 1 ? "Import all" : "Import now")
                    }
                }
                .buttonStyle(AuroraGradientButtonStyle(compact: true))
                .disabled(importBlocked)
                .opacity(importBlocked ? 0.5 : 1)
                .overlay {
                    if shouldEmphasizeImportNow && !importBlocked {
                        ZStack {
                            RoundedRectangle(cornerRadius: AuroraRadius.badge, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                            RoundedRectangle(cornerRadius: AuroraRadius.badge, style: .continuous)
                                .strokeBorder(
                                    AngularGradient(
                                        gradient: Gradient(stops: [
                                            .init(color: .white.opacity(0.05), location: 0.00),
                                            .init(color: .white.opacity(0.05), location: 0.62),
                                            .init(color: .auroraCyan, location: 0.74),
                                            .init(color: .white, location: 0.82),
                                            .init(color: .auroraMagenta, location: 0.90),
                                            .init(color: .white.opacity(0.05), location: 1.00)
                                        ]),
                                        center: .center,
                                        startAngle: .degrees(importBorderSpin ? 360 : 0),
                                        endAngle: .degrees(importBorderSpin ? 720 : 360)
                                    ),
                                    lineWidth: 2.4
                                )
                        }
                        .padding(-3)
                        .allowsHitTesting(false)
                    }
                }
                .shadow(
                    color: shouldEmphasizeImportNow && !importBlocked ? Color.auroraCyan.opacity(0.35) : .clear,
                    radius: shouldEmphasizeImportNow && !importBlocked ? 14 : 0,
                    x: 0,
                    y: 0
                )

                HStack(spacing: 12) {
                    Spacer()
                    AuroraMiniToggle(label: "Rename", isOn: $appState.renameOnImport, tint: .auroraMagenta)
                    if appState.renameOnImport {
                        Button("Edit") { showRenameEditor = true }
                            .font(.manrope(11, weight: .bold))
                            .foregroundStyle(Color.auroraMagenta)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.auroraMagenta.opacity(0.14))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.auroraMagenta.opacity(0.35), lineWidth: 1)
                            )
                            .buttonStyle(.plain)
                    }
                    AuroraMiniToggle(
                        label: "Auto-import",
                        isOn: $appState.autoImport,
                        tint: .auroraCyan,
                        isDisabled: appState.importState == .generatingStats
                    )
                }
            }
        }
    }

    private func handleRenameEditorDismiss() {
        if appState.renameOnImport && !renameEditorConfirmed {
            appState.renameOnImport = false
        }
        renameEditorConfirmed = false
    }

    private var shouldEmphasizeImportNow: Bool {
        guard !importableVolumes.isEmpty else { return false }
        switch appState.importState {
        case .idle, .done, .ejectingDone:
            return true
        default:
            return false
        }
    }

    private var isImportNowBlocked: Bool {
        let allAlreadyImported = appState.allDestinationFilesAlreadyImported && appState.sourceFileCountForDestinationCheck > 0
        return appState.importState == .generatingStats || importableVolumes.isEmpty || allAlreadyImported || validImportDestinationURL == nil
    }

    private var shouldPulseWaitingCard: Bool {
        guard importableVolumes.isEmpty else { return false }
        switch appState.importState {
        case .idle, .done, .ejectingDone:
            return true
        default:
            return false
        }
    }

    private var importableVolumes: [VolumeInfo] {
        let volumes = appState.mountedVolumes.filter { $0.rawFileCount > 0 && !isDestinationVolume($0.path) }
        guard !volumes.isEmpty else {
            if let active = appState.activeVolume, active.rawFileCount > 0, !isDestinationVolume(active.path) { return [active] }
            return []
        }
        return Array(volumes.prefix(2))
    }

    private func isDestinationVolume(_ sourceURL: URL) -> Bool {
        guard let destinationURL = validImportDestinationURL else { return false }
        let sourcePath = normalizedPath(sourceURL.path)
        let destinationPath = normalizedPath(destinationURL.path)
        return destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/")
    }
}

private struct AuroraMiniToggle: View {
    let label: String
    @Binding var isOn: Bool
    let tint: Color
    var isDisabled: Bool = false

    var body: some View {
        Button {
            guard !isDisabled else { return }
            withAnimation(.easeOut(duration: 0.16)) { isOn.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .font(.manrope(12, weight: .semibold))
                    .foregroundStyle(isDisabled ? Color.auroraFaint : (isOn ? Color.auroraTxt : Color.auroraMuted))
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isDisabled ? Color.auroraStroke.opacity(0.7) : (isOn ? tint.opacity(0.95) : Color.auroraStroke2.opacity(0.9)))
                        .frame(width: 36, height: 20)
                    Circle()
                        .fill(Color.white.opacity(isDisabled ? 0.36 : (isOn ? 0.96 : 0.72)))
                        .frame(width: 16, height: 16)
                        .padding(.horizontal, 2)
                        .shadow(color: !isDisabled && isOn ? tint.opacity(0.45) : .clear, radius: 6, x: 0, y: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .auroraTooltip(isDisabled ? "Unavailable while generating stats" : (isOn ? "Enabled" : "Disabled"))
    }
}

// MARK: - Recent event tile

struct RecentEventThumb: View {
    let event: EventAggregate
    var bannerImagePath: String? = nil
    var onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            EventThumbnail(
                eventName: event.name,
                cornerRadius: 14,
                overlay: AnyView(
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.85)],
                            startPoint: .top, endPoint: .bottom
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.name)
                                .font(.manrope(12.5, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("\(AuroraFormat.count(event.totalFiles)) RAW files")
                                .font(.manrope(11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.78))
                        }
                        .padding(12)
                    }
                ),
                bannerImagePath: bannerImagePath
            )
            .aspectRatio(4.0/3.0, contentMode: .fit)
            .offset(y: hovering ? -2 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hovering ? Color.auroraStroke2 : Color.auroraStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - File Browser Row

struct FileBrowserRow: View {
    @Bindable var appState: AppState

    @State private var sourceFiles: [URL] = []
    @State private var destFiles: [URL] = []
    @State private var sourceFileSizes: [URL: String] = [:]
    @State private var destFileSizes: [URL: String] = [:]
    @State private var isLoadingSource = false
    @State private var isLoadingDest = false
    @State private var showAdvanced = false
    @State private var loadSourceTask: Task<Void, Never>?
    @State private var loadDestTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: AuroraSpacing.gridGap) {
            filePanel(
                title: "Source Files",
                icon: "sdcard",
                color: .auroraCyan,
                files: sourceFiles,
                fileSizes: sourceFileSizes,
                isLoading: isLoadingSource,
                emptyHint: sourceVolumes.isEmpty ? "No card detected" : "No RAW files found",
                statusText: sourceFilesStatusText,
                storageSummary: sourceStorageSummary,
                onAdvanced: sourceFiles.isEmpty ? nil : { showAdvanced = true }
            )
            filePanel(
                title: "Destination Files",
                icon: "folder.fill",
                color: .auroraViolet,
                files: destFiles,
                fileSizes: destFileSizes,
                isLoading: isLoadingDest,
                emptyHint: appState.destinationURL == nil ? "No destination set" : "No files found",
                storageSummary: destinationStorageSummary,
                onRefresh: appState.destinationURL == nil ? nil : { loadDestFiles(from: appState.destinationURL) }
            )
        }
        .sheet(isPresented: $showAdvanced) {
            AdvancedView(appState: appState) {
                showAdvanced = false
            }
            .frame(minWidth: 1100, idealWidth: 1280, minHeight: 638, idealHeight: 638)
            .environment(\.colorScheme, .dark)
        }
        .onChange(of: appState.activeVolume) { _, volume in
            loadSourceFiles()
        }
        .onChange(of: appState.mountedVolumes) { _, _ in
            loadSourceFiles()
        }
        .onChange(of: appState.destinationURL) { _, url in
            loadDestFiles(from: url)
        }
        .onChange(of: appState.renameOnImport) { _, _ in
            clearImportBlockReason()
        }
        .onChange(of: appState.renameTemplate) { _, _ in
            clearImportBlockReason()
        }
        .onChange(of: appState.importMode) { _, _ in
            clearImportBlockReason()
        }
        .onAppear {
            loadSourceFiles()
            loadDestFiles(from: appState.destinationURL)
        }
        .onDisappear {
            loadSourceTask?.cancel()
            loadDestTask?.cancel()
        }
    }

    private func filePanel(
        title: String,
        icon: String,
        color: Color,
        files: [URL],
        fileSizes: [URL: String],
        isLoading: Bool,
        emptyHint: String,
        statusText: String? = nil,
        storageSummary: FilePanelStorageSummary? = nil,
        onAdvanced: (() -> Void)? = nil,
        onRefresh: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                IconChip(systemName: icon, color: color, size: 26, iconScale: 0.5)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(Color.auroraTxt)
                        if title == "Source Files", let statusText {
                            Text(statusText)
                                .font(.manrope(11, weight: .bold))
                                .foregroundStyle(Color.auroraCyan)
                                .lineLimit(1)
                        }
                    }
                    if title == "Source Files", storageSummary == nil, let sourceNamesText {
                        Text(sourceNamesText)
                            .font(.manrope(10.5, weight: .semibold))
                            .foregroundStyle(Color.auroraFaint)
                            .lineLimit(1)
                    }
                    if let storageSummary {
                        fileStorageRow(storageSummary)
                            .padding(.top, 1)
                    }
                }
                if let statusText, title != "Source Files" {
                    Text(statusText)
                        .font(.manrope(11, weight: .bold))
                        .foregroundStyle(Color.auroraCyan)
                        .lineLimit(1)
                }
                Spacer()
                if let onAdvanced {
                    Button("Advanced", action: onAdvanced)
                        .buttonStyle(AuroraGhostButtonStyle())
                }
                if let onRefresh {
                    Button(action: onRefresh) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                            Text("Refresh")
                        }
                    }
                    .buttonStyle(AuroraGhostButtonStyle())
                    .disabled(isLoading)
                }
                if !files.isEmpty {
                    Text("\(files.count)")
                        .font(.manrope(11, weight: .bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(color.opacity(0.12)))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 62)

            Rectangle()
                .fill(Color.auroraStroke)
                .frame(height: 1)

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading…")
                        .font(.manrope(11, weight: .medium))
                        .foregroundStyle(Color.auroraFaint)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 180)
            } else if files.isEmpty {
                Text(emptyHint)
                    .font(.manrope(12, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(files.enumerated()), id: \.offset) { idx, file in
                            HStack(spacing: 10) {
                                Text(file.pathExtension.uppercased())
                                    .font(.manrope(9, weight: .bold))
                                    .foregroundStyle(color)
                                    .frame(width: 34)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(color.opacity(0.12)))
                                    .multilineTextAlignment(.center)
                                Text(file.lastPathComponent)
                                    .font(.manrope(11.5, weight: .medium))
                                    .foregroundStyle(Color.auroraTxt)
                                    .lineLimit(1)
                                Spacer()
                                if let size = fileSizes[file] {
                                    Text(size)
                                        .font(.manrope(10, weight: .medium))
                                        .foregroundStyle(Color.auroraFaint)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)

                            if idx < files.count - 1 {
                                Rectangle()
                                    .fill(Color.auroraStroke)
                                    .frame(height: 1)
                                    .padding(.leading, 14)
                            }
                        }
                    }
                }
                .frame(height: 180)
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 243)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .fill(Color.auroraPanel)
        )
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke, lineWidth: 1)
        )
    }

    private struct FilePanelStorageSummary {
        let usedFraction: Double
        let line: String
        let tint: Color
        let isAvailable: Bool
    }

    private var sourceStorageSummary: FilePanelStorageSummary? {
        let urls = sourceVolumes.map(\.path)
        guard !urls.isEmpty else { return nil }
        return fileStorageSummary(for: urls)
    }

    private var destinationStorageSummary: FilePanelStorageSummary? {
        guard let url = appState.destinationURL else { return nil }
        return fileStorageSummary(for: url)
    }

    @ViewBuilder
    private func fileStorageRow(_ storage: FilePanelStorageSummary) -> some View {
        HStack(spacing: 8) {
            StorageBar(
                fraction: storage.usedFraction,
                height: 5,
                radius: 3,
                fill: AnyShapeStyle(storage.tint)
            )
            .frame(width: 86)

            Text(storage.line)
                .font(.manrope(10.5, weight: .semibold))
                .foregroundStyle(storage.isAvailable ? storage.tint.opacity(0.95) : Color.auroraFaint)
                .lineLimit(1)
        }
    }

    private func fileStorageSummary(for urls: [URL]) -> FilePanelStorageSummary {
        guard urls.count > 1 else {
            return fileStorageSummary(for: urls[0])
        }

        let summaries = urls.map { fileStorageValues(for: $0) }
        let validSummaries = summaries.compactMap { $0 }
        guard validSummaries.count == urls.count else {
            return FilePanelStorageSummary(
                usedFraction: 0,
                line: "Storage unavailable",
                tint: .auroraFaint,
                isAvailable: false
            )
        }

        let total = validSummaries.reduce(Int64(0)) { $0 + $1.total }
        let available = validSummaries.reduce(Int64(0)) { $0 + $1.available }
        guard total > 0 else {
            return FilePanelStorageSummary(
                usedFraction: 0,
                line: "Storage unavailable",
                tint: .auroraFaint,
                isAvailable: false
            )
        }

        let usedFraction = min(1, max(0, Double(total - available) / Double(total)))
        let availableParts = AuroraFormat.bytesParts(available)
        let percentUsed = Int((usedFraction * 100).rounded())
        let tint = fileStorageTint(available: available, usedFraction: usedFraction)
        let line: String
        let lowSpaceThreshold: Int64 = 100 * 1024 * 1024 * 1024

        if available < lowSpaceThreshold {
            line = "Low space: \(availableParts.value) \(availableParts.unit) free across \(urls.count) cards"
        } else {
            line = "\(availableParts.value) \(availableParts.unit) free · \(percentUsed)% used across \(urls.count) cards"
        }

        return FilePanelStorageSummary(
            usedFraction: usedFraction,
            line: line,
            tint: tint,
            isAvailable: true
        )
    }

    private func fileStorageSummary(for url: URL) -> FilePanelStorageSummary {
        guard let values = fileStorageValues(for: url) else {
            return FilePanelStorageSummary(
                usedFraction: 0,
                line: "Storage unavailable",
                tint: .auroraFaint,
                isAvailable: false
            )
        }

        let usedFraction = min(1, max(0, Double(values.total - values.available) / Double(values.total)))
        let availableParts = AuroraFormat.bytesParts(values.available)
        let percentUsed = Int((usedFraction * 100).rounded())
        let tint = fileStorageTint(available: values.available, usedFraction: usedFraction)
        let line: String
        let lowSpaceThreshold: Int64 = 100 * 1024 * 1024 * 1024

        if values.available < lowSpaceThreshold {
            line = "Low space: \(availableParts.value) \(availableParts.unit) free"
        } else {
            line = "\(availableParts.value) \(availableParts.unit) free · \(percentUsed)% used on \(values.volumeName)"
        }

        return FilePanelStorageSummary(
            usedFraction: usedFraction,
            line: line,
            tint: tint,
            isAvailable: true
        )
    }

    private func fileStorageValues(for url: URL) -> (available: Int64, total: Int64, volumeName: String)? {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey,
            .volumeNameKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let totalCapacity = values.volumeTotalCapacity,
              totalCapacity > 0 else {
            return nil
        }

        let total = Int64(totalCapacity)
        let availableCapacity = values.volumeAvailableCapacity.map(Int64.init)
        let forImportant = values.volumeAvailableCapacityForImportantUsage.flatMap { $0 > 0 ? $0 : nil }
        let available = max(0, forImportant ?? availableCapacity ?? 0)
        let volumeName = values.volumeName ?? url.lastPathComponent
        return (available, total, volumeName)
    }

    private func fileStorageTint(available: Int64, usedFraction: Double) -> Color {
        let lowSpaceThreshold: Int64 = 100 * 1024 * 1024 * 1024
        if available < lowSpaceThreshold || usedFraction >= 0.9 { return .auroraMagenta }
        if usedFraction >= 0.75 { return .auroraViolet }
        return .auroraCyan
    }

    private static func fileSizeText(for url: URL) -> String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else { return nil }
        let parts = AuroraFormat.bytesParts(Int64(size))
        return "\(parts.value) \(parts.unit)"
    }

    private func loadSourceFiles() {
        let volumes = sourceVolumes
        guard !volumes.isEmpty else {
            loadSourceTask?.cancel()
            sourceFiles = []
            sourceFileSizes = [:]
            clearImportBlockReason()
            return
        }
        isLoadingSource = true
        let paths = volumes.map(\.path)
        let exts = appState.supportedExtensions
        loadSourceTask?.cancel()
        loadSourceTask = Task.detached(priority: .utility) {
            let files = paths.flatMap { path in
                VolumeWatcher.listRawFiles(at: path, extensions: exts)
            }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            let sizes = Dictionary(uniqueKeysWithValues: files.compactMap { file in
                Self.fileSizeText(for: file).map { (file, $0) }
            })
            await MainActor.run {
                guard !Task.isCancelled else { return }
                sourceFiles = files
                sourceFileSizes = sizes
                isLoadingSource = false
                clearImportBlockReason()
            }
        }
    }

    private func loadDestFiles(from url: URL?) {
        guard let url = url else {
            loadDestTask?.cancel()
            destFiles = []
            destFileSizes = [:]
            clearImportBlockReason()
            return
        }
        isLoadingDest = true
        let exts = appState.supportedExtensions
        loadDestTask?.cancel()
        loadDestTask = Task.detached(priority: .utility) {
            let files = VolumeWatcher.listRawFiles(at: url, extensions: exts)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            let sizes = Dictionary(uniqueKeysWithValues: files.compactMap { file in
                Self.fileSizeText(for: file).map { (file, $0) }
            })
            await MainActor.run {
                guard !Task.isCancelled else { return }
                destFiles = files
                destFileSizes = sizes
                isLoadingDest = false
                clearImportBlockReason()
            }
        }
    }

    private var sourceFilesStatusText: String? {
        if let message = appState.sourceFilesImportStatusMessage { return message }
        return sourceVolumes.count > 1 ? "\(sourceVolumes.count) cards" : nil
    }

    private var sourceNamesText: String? {
        let names = sourceVolumes.map(\.name)
        guard !names.isEmpty else { return nil }
        return names.joined(separator: " + ")
    }

    private var sourceVolumes: [VolumeInfo] {
        let volumes = appState.mountedVolumes.filter { $0.rawFileCount > 0 && !isDestinationVolume($0.path) }
        guard !volumes.isEmpty else {
            if let active = appState.activeVolume, active.rawFileCount > 0, !isDestinationVolume(active.path) { return [active] }
            return []
        }
        return Array(volumes.prefix(2))
    }

    private func isDestinationVolume(_ sourceURL: URL) -> Bool {
        guard let destinationURL = appState.destinationURL else { return false }
        let sourcePath = normalizedPath(sourceURL.path)
        let destinationPath = normalizedPath(destinationURL.path)
        return destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/")
    }

    private func normalizedPath(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func clearImportBlockReason() {
        appState.sourceFileCountForDestinationCheck = sourceFiles.count
        appState.allDestinationFilesAlreadyImported = false
        appState.sourceFilesImportStatusMessage = nil
    }
}
