import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct EventStatsView: View {
    @Bindable var appState: AppState
    let destinationPath: String
    let eventName: String
    let bookmarkIndex: Int?
    let statsRunner: StatsRunner?

    @State private var report: StatsReport?
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var showAllLenses = false
    @State private var showAllCameras = false
    @State private var scanDate: Date? = nil      // when the last successful scan happened
    @State private var isCachedData = false       // true = currently showing cached (not fresh) data
    @State private var scanQuality: EventStatsScanQuality? = nil
    @State private var isEditingEventName = false
    @State private var eventNameDraft = ""
    @State private var isRepositioningBanner = false
    @State private var bannerOffsetDraft = EventBannerOffset()
    @State private var bannerDragStartOffset: EventBannerOffset?
    @State private var shareErrorMessage: String?
    @State private var scanProgress: Double = 0
    // Latched, not recomputed fresh each render — once a scan is flagged as slow it
    // stays flagged for the rest of that scan, even if the live ETA estimate later
    // dips back under the threshold (e.g. pace briefly speeds up near the end).
    // Reset only when a new scan starts (see `.task(id: isBackgroundScanning)`).
    @State private var showSlowScanInfo = false
    @State private var showLockInfo = false
    @State private var showLockedInfo = false
    @State private var showLockConfirmPrompt = false
    @State private var showUnlockConfirmPrompt = false
    @State private var showPostLockSharePrompt = false
    @State private var jpgCountsByDay: [String: Int] = [:]
    @State private var isLoadingJPGCounts = false
    @State private var isBannerCompact = false
    @State private var isHoveringBanner = false
    @State private var bannerImage: NSImage?
    @State private var loadedBannerImagePath: String?
    @State private var isEditingTags = false
    @State private var galleryPhotos: [GalleryPhotoRecord] = []
    @State private var isBuildingGallery = false
    @State private var galleryBuildTotal: Int?
    // `destinationPath` is a plain `let` (a constructor parameter), not `@State` —
    // reading it from inside an async closure that captured `self` earlier reads a
    // *frozen* value from whenever that closure was created, not the live current
    // path. `@State`'s storage is a shared box, so this mirror of it (kept in sync
    // via onAppear/onChange below) is what async gallery work should actually check
    // against to detect "the user has since switched events" — comparing against
    // `destinationPath` directly always trivially matched, letting an old event's
    // still-in-progress gallery build write its photos into whatever event the user
    // had since navigated to.
    @State private var currentEventPath: String = ""
    @FocusState private var eventNameFieldFocused: Bool

    // Import history summary — available instantly, no scan needed
    // Falls back to cached report data if folder has been moved and history can't be matched
    private var importSummary: (photoCount: Int, totalBytes: Int64, sessionCount: Int, firstDate: Date?, lastDate: Date?)? {
        guard !isAddedLibraryFolder else { return nil }
        if let bookmarkIndex, let summary = appState.importStatsForEventFolder(at: bookmarkIndex) {
            return summary
        }
        if let summary = appState.importStats(forEventPath: destinationPath, eventName: eventName) {
            return summary
        }
        // Fallback: use cached report data when folder path has changed
        if let cached = report, cached.totalFilesAnalyzed > 0 {
            return (
                photoCount: cached.totalFilesAnalyzed,
                totalBytes: cached.totalBytes,
                sessionCount: 1,
                firstDate: cached.firstImportDate,
                lastDate: cached.firstImportDate
            )
        }
        return nil
    }

    private var isAddedLibraryFolder: Bool {
        guard let bookmarkIndex else { return false }
        return appState.isLibraryFolder(at: bookmarkIndex)
    }

    private var eventImportHistoryEntries: [ImportHistoryEntry] {
        let paths = eventImportCandidatePaths
        guard !paths.isEmpty else { return [] }
        return appState.importHistory.filter { entry in
            let destination = normalizeEventPath(entry.destinationPath)
            return paths.contains { path in
                destination == path || destination.hasPrefix(path + "/")
            }
        }
    }

    private var eventImportCandidatePaths: [String] {
        var paths = [destinationPath]
        if let bookmarkIndex {
            if bookmarkIndex < appState.eventFolderCachedPaths.count {
                paths.append(appState.eventFolderCachedPaths[bookmarkIndex])
            }
            if bookmarkIndex < appState.eventFolderPreviousCachedPaths.count {
                paths.append(appState.eventFolderPreviousCachedPaths[bookmarkIndex])
            }
        }
        return Array(Set(paths.map(normalizeEventPath).filter { !$0.isEmpty }))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                eventBannerCard

                if bookmarkIndex != nil {
                    eventTagsRow
                }

                // Import history card — visible for imported events only.
                if !isAddedLibraryFolder, let summary = importSummary {
                    importHistoryCard(summary: summary)
                }

                // EXIF stats — loaded on first appear.
                // Only show the full-page spinner when there is no cached data yet.
                // If a background re-scan is running while we already have data, the
                // small header spinner is enough — we keep showing the (cached) content.
                if isBackgroundScanning && report == nil {
                    backgroundScanningState
                } else if isLoading && report == nil {
                    loadingState
                } else if let err = errorMessage {
                    errorState(message: err)
                } else if let report = report, report.totalFilesAnalyzed > 0 {
                    statsContent(for: report)
                } else if hasLoaded {
                    if isQueuedForBackgroundScan {
                        queuedScanState
                    } else if isBackgroundScanning {
                        backgroundScanningState
                    } else {
                        emptyState
                    }
                }

                // JPGs are detected/built independently of the RAW scan (see
                // checkForNewJPGsAndRebuildIfNeeded), so this stays outside the
                // report-gated branches above — otherwise it'd stay hidden behind the
                // "scanning RAWs" skeleton for however long that scan takes. Kept at
                // the bottom, after the RAW stats, to match where it always was.
                if !galleryPhotos.isEmpty || isBuildingGallery {
                    EventGalleryCard(photos: galleryPhotos, isBuilding: isBuildingGallery, buildTotal: galleryBuildTotal, knownJPGCount: deliveredPhotoCount, appState: appState)
                }
            }
            .padding(.top, 48)
            .padding(.horizontal, AuroraSpacing.mainPaddingH)
            .padding(.bottom, 20)
        }
        .onAppear {
            currentEventPath = destinationPath
            loadBannerDisplayMode()
            loadBannerImageIfNeeded()
            if !hasLoaded { loadFromCache() }
            loadJPGCountsByDay()
            loadGalleryFromCache()
        }
        .task(id: destinationPath) {
            // JPGs (e.g. edited exports dropped in after a shoot) are added
            // independently of RAW imports, so the gallery — and the "Photos
            // Delivered" / "Keep Rate" cards, which read the same JPG count — can't
            // just piggyback on RAW rescans. Poll lightly while parked on this event
            // to pick new JPGs up without the user having to hit Refresh. One combined
            // full-tree walk per tick (see refreshJPGCountsAndGalleryPeriodically),
            // not two, and a longer interval — this doesn't need sub-15s precision.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { break }
                refreshJPGCountsAndGalleryPeriodically()
            }
        }
        .onChange(of: isBackgroundScanning) { _, stillScanning in
            if !stillScanning {
                scanProgress = 1.0
                loadFromCache()
            }
        }
        .onChange(of: currentBackgroundScanQuality) { _, quality in
            if quality == .full, report == nil {
                loadFromCache()
            }
        }
        .task(id: isBackgroundScanning) {
            guard isBackgroundScanning else { return }
            // Use the real scan start time so progress resumes correctly if the
            // user navigates away and comes back while the scan is still running.
            let fileCount = backgroundScanFileCount
            let estimatedSecs = fileCount > 0 ? max(3.0, Double(fileCount) * 0.030) : 30.0
            let startTime = (bookmarkIndex.flatMap { appState.backgroundScanStartTimes[$0] }) ?? Date()
            var lastLoadedProcessedCount = -1
            showSlowScanInfo = false
            while !Task.isCancelled {
                let processed = backgroundScanProcessedFileCount
                let total = backgroundScanFileCount
                if processed > 0, total > 0 {
                    scanProgress = min(1.0, Double(processed) / Double(total))
                    if processed != lastLoadedProcessedCount {
                        lastLoadedProcessedCount = processed
                        loadFromCache()
                    }
                } else {
                    let ratio = Date().timeIntervalSince(startTime) / estimatedSecs
                    scanProgress = 1.0 - 1.0 / (1.0 + ratio * 2.0)
                }
                if !showSlowScanInfo, shouldShowSlowScanInfo(fileCount: total) {
                    showSlowScanInfo = true
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        .onChange(of: destinationPath) { _, newPath in
            currentEventPath = newPath
            hasLoaded = false
            report = nil
            errorMessage = nil
            shareErrorMessage = nil
            scanDate = nil
            scanQuality = nil
            isCachedData = false
            isEditingEventName = false
            eventNameDraft = ""
            isRepositioningBanner = false
            bannerOffsetDraft = EventBannerOffset()
            bannerDragStartOffset = nil
            bannerImage = nil
            loadedBannerImagePath = nil
            loadBannerDisplayMode()
            jpgCountsByDay = [:]
            loadFromCache()
            loadJPGCountsByDay()
            loadBannerImageIfNeeded()
            galleryPhotos = []
            galleryBuildTotal = nil
            loadGalleryFromCache()
        }
        .onChange(of: eventBannerImagePath) { _, _ in loadBannerImageIfNeeded() }
        .alert("Could not export share image", isPresented: shareErrorBinding) {
            Button("OK", role: .cancel) { shareErrorMessage = nil }
        } message: {
            Text(shareErrorMessage ?? "Unknown error")
        }
    }

    // MARK: - Tags

    private var eventTagsBinding: Binding<Set<EventTag>> {
        Binding(
            get: { bookmarkIndex.map(appState.tags(at:)) ?? [] },
            set: { newValue in
                guard let bookmarkIndex else { return }
                appState.setTags(newValue, at: bookmarkIndex)
            }
        )
    }

    private var eventTagsRow: some View {
        HStack(alignment: .top, spacing: 10) {
            EventTagChipsRow(tags: eventTagsBinding.wrappedValue)
            Spacer(minLength: 8)
            Button {
                isEditingTags = true
            } label: {
                Label("Edit tags", systemImage: "tag")
                    .font(.manrope(11.5, weight: .bold))
            }
            .buttonStyle(AuroraGhostButtonStyle())
            .popover(isPresented: $isEditingTags, arrowEdge: .bottom) {
                EventTagPickerView(selectedTags: eventTagsBinding)
            }
        }
    }

    // MARK: - Header

    private var isBackgroundScanning: Bool {
        guard let bookmarkIndex else { return false }
        if appState.backgroundScanningBookmarkIndices.contains(bookmarkIndex) { return true }
        // Library folder scan via drainScanQueue
        if appState.currentlyScanningIndex == bookmarkIndex { return true }
        return false
    }

    private var currentBackgroundScanQuality: EventStatsScanQuality? {
        guard let bookmarkIndex else { return nil }
        return appState.backgroundScanQualities[bookmarkIndex]
    }

    private var isQueuedForBackgroundScan: Bool {
        guard let bookmarkIndex else { return false }
        return appState.scanQueue.contains(bookmarkIndex) && !isBackgroundScanning
    }

    private var queuedScanPosition: Int? {
        guard let bookmarkIndex,
              let index = appState.scanQueue.firstIndex(of: bookmarkIndex) else { return nil }
        return index + 1
    }

    private var backgroundScanFileCount: Int {
        guard let bookmarkIndex else { return 0 }
        return appState.backgroundScanFileCount[bookmarkIndex] ?? 0
    }

    private var backgroundScanProcessedFileCount: Int {
        guard let bookmarkIndex else { return 0 }
        return appState.backgroundScanProcessedFileCount[bookmarkIndex] ?? 0
    }

    private var diskIsReachable: Bool {
        guard !destinationPath.isEmpty else { return false }
        return (try? URL(fileURLWithPath: destinationPath).checkResourceIsReachable()) == true
    }

    private func loadJPGCountsByDay() {
        if let cachedCounts = cachedJPGCountsByDayForCurrentEvent(), !cachedCounts.isEmpty {
            jpgCountsByDay = cachedCounts
        }

        guard diskIsReachable else {
            isLoadingJPGCounts = false
            return
        }

        // A locked event is a frozen snapshot — show whatever counts were cached
        // before locking, but don't re-walk the folder to refresh them. Unlocking
        // (reopenLockedEvent) explicitly kicks this off again.
        guard !isEventLocked else {
            isLoadingJPGCounts = false
            return
        }

        let path = destinationPath
        isLoadingJPGCounts = true
        Task.detached(priority: .utility) {
            let counts = Self.countJPGFilesByDay(at: path)
            await MainActor.run {
                guard currentEventPath == path else { return }
                jpgCountsByDay = counts
                if let bookmarkIndex, bookmarkIndex < appState.eventFolderCachedJPGCounts.count {
                    let count = counts.reduce(0) { $0 + $1.value }
                    if count > 0 { appState.eventFolderCachedJPGCounts[bookmarkIndex] = count }
                    if !counts.isEmpty {
                        appState.updateEventFolderJPGDayCache(at: bookmarkIndex, countsByDay: counts)
                    }
                }
                if !counts.isEmpty {
                    EventStatsCache.saveJPGCountsByDay(counts, forPath: path)
                }
                isLoadingJPGCounts = false
            }
        }
    }

    /// Periodic tick while parked on an event (see `.task(id: destinationPath)`
    /// below): does **one** full folder walk that both refreshes the JPGs-per-day
    /// chart and checks whether the gallery needs rebuilding, reusing the same
    /// enumeration for both instead of `loadJPGCountsByDay()` and
    /// `checkForNewJPGsAndRebuildIfNeeded()` each doing their own independent
    /// recursive `FileManager` walk of the same tree every tick. On a large
    /// "production" event folder — especially over a NAS, where each file's
    /// resourceValues fetch has real per-file latency — running two full walks
    /// every 12s was a continuous, self-inflicted I/O/CPU cost and the actual cause
    /// of the reported sluggishness while inside an event.
    private func refreshJPGCountsAndGalleryPeriodically() {
        // Locked events are frozen — see checkForNewJPGsAndRebuildIfNeeded. This is
        // also what stops the periodic tick below from doing any real work (and
        // thus any real I/O) for the — typically large majority of — events that
        // are locked/archived, which was the whole point of gating on lock state.
        guard !isEventLocked else { return }
        guard diskIsReachable, !isBuildingGallery else { return }
        let path = destinationPath
        Task.detached(priority: .utility) {
            let counts = Self.countJPGFilesByDay(at: path)
            let total = counts.reduce(0) { $0 + $1.value }
            await MainActor.run {
                guard currentEventPath == path else { return }
                jpgCountsByDay = counts
                if let bookmarkIndex, bookmarkIndex < appState.eventFolderCachedJPGCounts.count {
                    if total > 0 { appState.eventFolderCachedJPGCounts[bookmarkIndex] = total }
                    if !counts.isEmpty {
                        appState.updateEventFolderJPGDayCache(at: bookmarkIndex, countsByDay: counts)
                    }
                }
                if !counts.isEmpty {
                    EventStatsCache.saveJPGCountsByDay(counts, forPath: path)
                }
                if total != galleryPhotos.count, !isBuildingGallery {
                    rebuildGalleryInBackground()
                }
            }
        }
    }

    // MARK: - Gallery

    /// Loads whatever was already built (survives even if the source folder later
    /// moves — thumbnails/metadata live in Application Support, not the event folder).
    /// Reads + JSON-decodes the manifest off the main thread — for a large gallery
    /// (hundreds+ photos) doing that synchronously on `.onAppear`/`.onChange` was
    /// blocking the UI for a noticeable moment every time this event was opened.
    private func loadGalleryFromCache() {
        let path = destinationPath
        Task.detached(priority: .userInitiated) {
            let cached = EventGalleryStore.load(forPath: path)
            await MainActor.run {
                guard currentEventPath == path else { return }
                if let cached { galleryPhotos = cached }
                // Chained here (instead of called separately right after
                // loadGalleryFromCache(), like before this became async) and passed
                // the just-loaded count directly — otherwise this would race the
                // cache load and almost always see a stale/empty `galleryPhotos`,
                // triggering a spurious full rebuild on every single event open.
                checkForNewJPGsAndRebuildIfNeeded(knownCount: cached?.count ?? 0)
            }
        }
    }

    /// Rebuilds the gallery for the current event. Called after a RAW scan finishes
    /// successfully — JPGs are far cheaper for exiftool to read than RAWs, so this
    /// piggybacks on the scan the user already triggered instead of running on its own.
    /// Also called directly by `checkForNewJPGsAndRebuildIfNeeded()` when the JPG
    /// count itself changes, independent of any RAW scan.
    private func rebuildGalleryInBackground() {
        guard diskIsReachable else { return }
        let path = destinationPath
        isBuildingGallery = true
        galleryBuildTotal = nil
        Task.detached(priority: .utility) {
            let built = EventGalleryStore.buildGallery(forEventPath: path) { partial, total in
                Task { @MainActor in
                    guard currentEventPath == path else { return }
                    galleryPhotos = partial
                    galleryBuildTotal = total
                }
            }
            await MainActor.run {
                // Always clear the "building" flag regardless of whether the user
                // has since navigated away — it's a single shared flag, not one kept
                // per event, so leaving it stuck at `true` for an abandoned build
                // would block the *new* current event's own gallery check from ever
                // running (see the guard in checkForNewJPGsAndRebuildIfNeeded).
                isBuildingGallery = false
                guard currentEventPath == path, let built else { return }
                galleryPhotos = built
                galleryBuildTotal = nil
            }
        }
    }

    /// Cheap (count-only, no exiftool/thumbnails) check for whether JPGs were added
    /// or removed in the event folder since the gallery was last built. JPGs get
    /// dropped in on their own — e.g. exports from an editor, after the RAW import is
    /// long done — so this is the only thing that notices without a manual Refresh.
    private func checkForNewJPGsAndRebuildIfNeeded(knownCount: Int? = nil) {
        // A locked event is a frozen snapshot — the gallery it had at lock time
        // stands until the user explicitly unlocks (reopenLockedEvent), which
        // re-triggers this. No point walking the folder to notice changes we're
        // going to ignore anyway.
        guard !isEventLocked else { return }
        guard diskIsReachable, !isBuildingGallery else { return }
        let path = destinationPath
        let knownCount = knownCount ?? galleryPhotos.count
        Task.detached(priority: .utility) {
            let currentCount = EventGalleryStore.countJPGs(atPath: path)
            guard currentCount != knownCount else { return }
            await MainActor.run {
                guard currentEventPath == path, !isBuildingGallery else { return }
                rebuildGalleryInBackground()
            }
        }
    }

    private func cachedJPGCountsByDayForCurrentEvent() -> [String: Int]? {
        if let bookmarkIndex,
           bookmarkIndex < appState.eventFolderCachedJPGCountsByDay.count {
            let cached = appState.eventFolderCachedJPGCountsByDay[bookmarkIndex]
            if !cached.isEmpty { return cached }
        }
        if let counts = EventStatsCache.loadJPGCountsByDay(forPath: destinationPath) {
            return counts
        }
        guard let bookmarkIndex,
              bookmarkIndex < appState.eventFolderPreviousCachedPaths.count else { return nil }
        let previousPath = appState.eventFolderPreviousCachedPaths[bookmarkIndex]
        guard !previousPath.isEmpty else { return nil }
        return EventStatsCache.loadJPGCountsByDay(forPath: previousPath)
    }

    nonisolated private static func countJPGFilesByDay(at path: String) -> [String: Int] {
        let root = URL(fileURLWithPath: path)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [:] }

        var counts: [String: Int] = [:]
        for case let file as URL in enumerator {
            let ext = file.pathExtension.lowercased()
            guard ext == "jpg" || ext == "jpeg" else { continue }
            if let values = try? file.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == false {
                continue
            }
            guard let day = dayKeyForJPGFile(file) else { continue }
            counts[day, default: 0] += 1
        }
        return counts
    }

    nonisolated private static func dayKeyForJPGFile(_ url: URL) -> String? {
        // Avoid opening every JPG with ImageIO during normal chart loading. On
        // NAS/external disks hundreds of tiny image opens are slower than a plain
        // directory walk, and delivered JPGs are usually already grouped by day.
        if let pathDay = dayKeyFromPath(url.path) { return pathDay }

        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        guard let date = values?.creationDate ?? values?.contentModificationDate else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    nonisolated private static func dayKeyFromPath(_ path: String) -> String? {
        let tokens = path
            .split { char in
                char == "/" || char == "_" || char == " "
            }
            .map(String.init)

        for token in tokens.reversed() {
            let normalized = token.replacingOccurrences(of: ".", with: "-")
            let parts = normalized.split(separator: "-").map(String.init)
            guard parts.count == 3 else { continue }

            if parts[0].count == 4,
               let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
               isValidDay(year: year, month: month, day: day) {
                return String(format: "%04d-%02d-%02d", year, month, day)
            }

            if parts[2].count == 4,
               let day = Int(parts[0]), let month = Int(parts[1]), let year = Int(parts[2]),
               isValidDay(year: year, month: month, day: day) {
                return String(format: "%04d-%02d-%02d", year, month, day)
            }
        }
        return nil
    }

    nonisolated private static func isValidDay(year: Int, month: Int, day: Int) -> Bool {
        guard (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day) else { return false }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        return components.date != nil
    }

    private var eventBannerCard: some View {
        ZStack {
            bannerCardBackground

            VStack(spacing: 0) {
                bannerHeader
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.78), Color.black.opacity(0.45), Color.black.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 130)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .allowsHitTesting(false),
                        alignment: .top
                    )
                Spacer()
            }

            if !effectiveBannerIsCompact && (importSummary != nil || bookmarkIndex != nil) {
                VStack(spacing: 0) {
                    Spacer()
                    HStack(alignment: .center, spacing: 0) {
                        if let summary = importSummary {
                            Text("\(AuroraFormat.count(summary.photoCount)) photos imported")
                                .font(.manrope(12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.92))
                                .shadow(color: Color.black.opacity(0.6), radius: 6, x: 0, y: 2)
                        }
                        Spacer()
                        if let bookmarkIndex, !appState.isLibraryFolder(at: bookmarkIndex) {
                            lockEventButton
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: effectiveBannerIsCompact ? 86 : 400)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: effectiveBannerIsCompact)
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke, lineWidth: 1)
        )
        .overlay {
            if isRepositioningBanner {
                bannerRepositionOverlay
            }
        }
        .overlay(alignment: .topLeading) {
            if bookmarkIndex != nil && isHoveringBanner && !isRepositioningBanner {
                Button {
                    setBannerCompact(!effectiveBannerIsCompact)
                } label: {
                    Image(systemName: effectiveBannerIsCompact ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Color.auroraCyan)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(Color.auroraPanel2.opacity(0.94))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.auroraStroke2, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(6)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .help(effectiveBannerIsCompact ? "Expand banner" : "Collapse banner")
            }
        }
        .animation(.easeOut(duration: 0.14), value: isHoveringBanner)
        .onHover { isHoveringBanner = $0 }
    }

    @ViewBuilder
    private var bannerCardBackground: some View {
        if let img = bannerImage {
            GeometryReader { geo in
                let imageSize = scaledBannerImageSize(imageSize: img.size, containerSize: geo.size)
                let offset = clampedBannerOffset(activeBannerOffset, imageSize: img.size, containerSize: geo.size)

                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: imageSize.width, height: imageSize.height)
                    .offset(x: offset.x, y: offset.y)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        } else {
            // No explicit banner — show the Aurora gradient. The user sets a banner
            // manually via the Banner menu; we don't auto-pick RAW files here.
            EventThumbnail(
                eventName: currentEventName,
                cornerRadius: 0
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadBannerImageIfNeeded() {
        guard let path = eventBannerImagePath else {
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

    private var bannerHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.auroraViolet)
                .font(.system(size: 18, weight: .bold))
                .shadow(color: Color.black.opacity(0.55), radius: 6, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                editableEventTitle
                if let date = scanDate {
                    Text("\(scanQuality?.label ?? "Last") scan: \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.manrope(11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .shadow(color: Color.black.opacity(0.6), radius: 6, x: 0, y: 1)
                }
            }

            Spacer(minLength: 12)

            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(Color.white)
            } else if diskIsReachable {
                Button {
                    loadEventStats()
                } label: {
                    Label(isCachedData ? "Refresh" : "Scan Photos", systemImage: "arrow.clockwise")
                        .font(.manrope(12, weight: .bold))
                }
                .buttonStyle(AuroraGhostButtonStyle())
            }

            if effectiveBannerIsCompact,
               let bookmarkIndex,
               !appState.isLibraryFolder(at: bookmarkIndex) {
                lockEventButton
            }

            shareMenu

            bannerMenu
        }
    }

    private var shareErrorBinding: Binding<Bool> {
        Binding(
            get: { shareErrorMessage != nil },
            set: { if !$0 { shareErrorMessage = nil } }
        )
    }

    private var shareMenu: some View {
        Menu {
            Button("Instagram Story") {
                exportSocialShare(format: .story)
            }
            Button("Instagram Post") {
                exportSocialShare(format: .post)
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
                .font(.manrope(12, weight: .bold))
        }
        .buttonStyle(AuroraGhostButtonStyle())
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func exportSocialShare(format: EventSocialShareFormat) {
        do {
            try EventSocialShareExporter.export(snapshot: socialShareSnapshot, format: format)
        } catch {
            shareErrorMessage = error.localizedDescription
        }
    }

    private var socialShareSnapshot: EventSocialShareSnapshot {
        let summary = importSummary
        let activeReport = report
        let totalBytes = summary?.totalBytes ?? activeReport?.totalBytes ?? 0
        let bytes = AuroraFormat.bytesParts(totalBytes)
        let rawCount = knownRawFileCount ?? activeReport?.totalFilesAnalyzed ?? summary?.photoCount ?? 0
        let shootingMetrics = activeReport?.shootingTimeMetrics
        let topLenses = activeReport?.allLenses.prefix(3).map { lens in
            EventSocialRankItem(
                name: LensDisplayFormatter.displayName(make: lens.make, model: lens.model),
                subtitle: LensDisplayFormatter.brandName(make: lens.make, model: lens.model),
                count: AuroraFormat.count(lens.count)
            )
        } ?? []
        let topCameras = activeReport?.allCameras.prefix(3).map { camera in
            EventSocialRankItem(
                name: camera.fullName,
                subtitle: nil,
                count: AuroraFormat.count(camera.count)
            )
        } ?? []
        let dateRange: String = {
            if let first = summary?.firstDate {
                return AuroraFormat.dateRange(first, summary?.lastDate ?? first)
            }
            if let date = activeReport?.firstImportDate {
                return AuroraFormat.dateMedium(date)
            }
            return "Event stats"
        }()

        return EventSocialShareSnapshot(
            eventName: currentEventName,
            destinationPath: destinationPath,
            bannerImagePath: eventBannerImagePath,
            bannerOffset: activeBannerOffset,
            dateRange: dateRange,
            rawFiles: rawCount > 0 ? AuroraFormat.count(rawCount) : "—",
            deliveredPhotos: deliveredPhotoCount > 0 ? AuroraFormat.count(deliveredPhotoCount) : "—",
            dataImported: totalBytes > 0 ? "\(bytes.value) \(bytes.unit)" : "—",
            avgISO: activeReport?.avgISO.map(AuroraFormat.iso) ?? "—",
            avgShutter: activeReport?.avgShutterSpeed.map(AuroraFormat.shutter) ?? "—",
            avgAperture: activeReport?.avgAperture.map(AuroraFormat.aperture) ?? "—",
            avgFocal: activeReport?.avgFocalLength.map(AuroraFormat.focal) ?? "—",
            mostRawPhotosInDay: shootingMetrics?.busiestPhotoDay.map { AuroraFormat.count($0.photoCount) } ?? "—",
            totalWorkingHours: shootingMetrics.map { formatSocialDuration($0.totalCoverageSeconds) } ?? "—",
            longestActiveDay: shootingMetrics?.longestCoverageDay.map { formatSocialDuration($0.coverageSeconds) } ?? "—",
            topLenses: topLenses,
            topCameras: topCameras
        )
    }

    @ViewBuilder
    private var editableEventTitle: some View {
        if isEditingEventName, bookmarkIndex != nil {
            HStack(spacing: 8) {
                TextField("Event name", text: $eventNameDraft)
                    .font(.sora(21, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(.white)
                    .textFieldStyle(.plain)
                    .focused($eventNameFieldFocused)
                    .onSubmit(commitEventNameEdit)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                    )
                    .frame(maxWidth: 420, alignment: .leading)

                Button(action: commitEventNameEdit) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.black.opacity(0.32), in: Circle())
                }
                .buttonStyle(.plain)
                .auroraTooltip("Save name")
            }
        } else {
            HStack(spacing: 8) {
                Text(currentEventName)
                    .font(.sora(21, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .shadow(color: Color.black.opacity(0.6), radius: 8, x: 0, y: 2)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: beginEventNameEdit)

                if bookmarkIndex != nil {
                    Button(action: beginEventNameEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(width: 26, height: 26)
                            .background(Color.black.opacity(0.22), in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .auroraTooltip("Rename event")
                }
            }
        }
    }

    private var currentEventName: String {
        guard let bookmarkIndex,
              bookmarkIndex >= 0,
              bookmarkIndex < appState.eventFolderDisplayNames.count else { return eventName }
        let displayName = appState.eventFolderDisplayNames[bookmarkIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return displayName.isEmpty ? eventName : displayName
    }

    private func beginEventNameEdit() {
        guard bookmarkIndex != nil else { return }
        eventNameDraft = currentEventName
        isEditingEventName = true
        Task { @MainActor in eventNameFieldFocused = true }
    }

    private func commitEventNameEdit() {
        guard let bookmarkIndex else { return }
        let trimmed = eventNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isEditingEventName = false
            eventNameFieldFocused = false
            return
        }

        appState.setEventFolderDisplayName(at: bookmarkIndex, name: trimmed)
        isEditingEventName = false
        eventNameFieldFocused = false
    }

    @ViewBuilder
    private var bannerMenu: some View {
        if let bookmarkIndex {
            Menu {
                Button("Choose Banner Photo…") {
                    chooseBannerPhoto(for: bookmarkIndex)
                }
                Button(effectiveBannerIsCompact ? "Expand Banner" : "Collapse Banner") {
                    setBannerCompact(!effectiveBannerIsCompact)
                }
                if eventBannerImagePath != nil {
                    Button("Reposition Banner") {
                        beginBannerReposition()
                    }
                    Button("Reset Position") {
                        appState.resetEventFolderBannerOffset(at: bookmarkIndex)
                    }
                    Button("Remove Banner Photo") {
                        appState.clearEventFolderBanner(at: bookmarkIndex)
                    }
                }
            } label: {
                Label("Banner", systemImage: "photo.fill")
                    .font(.manrope(12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.auroraViolet.opacity(0.92))
                    )
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var effectiveBannerIsCompact: Bool {
        bookmarkIndex != nil && isBannerCompact
    }

    private var bannerDisplayModeKey: String? {
        guard let bookmarkIndex else { return nil }
        return "eventBannerCompact-\(bookmarkIndex)"
    }

    private func loadBannerDisplayMode() {
        guard let key = bannerDisplayModeKey else {
            isBannerCompact = false
            return
        }
        isBannerCompact = UserDefaults.standard.bool(forKey: key)
    }

    private func setBannerCompact(_ compact: Bool) {
        guard let key = bannerDisplayModeKey else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            isBannerCompact = compact
        }
        UserDefaults.standard.set(compact, forKey: key)
        if compact {
            isRepositioningBanner = false
        }
    }

    private var bannerRepositionOverlay: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.18))
                .contentShape(Rectangle())
                .gesture(bannerRepositionGesture)

            VStack {
                HStack {
                    Label("Drag the banner to reposition", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.manrope(12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.52))
                                .background(.ultraThinMaterial, in: Capsule())
                        )
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    Button("Done") {
                        commitBannerReposition()
                    }
                    .buttonStyle(AuroraGradientButtonStyle(compact: true))
                }
            }
            .padding(18)
            .allowsHitTesting(true)

            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .background(.ultraThinMaterial, in: Circle())
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 6)
                .offset(x: activeBannerOffset.x, y: activeBannerOffset.y)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous))
    }

    private var bannerRepositionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if bannerDragStartOffset == nil {
                    bannerDragStartOffset = bannerOffsetDraft
                }
                let start = bannerDragStartOffset ?? bannerOffsetDraft
                bannerOffsetDraft = EventBannerOffset(
                    x: min(500, max(-500, start.x + value.translation.width)),
                    y: min(500, max(-500, start.y + value.translation.height))
                )
            }
            .onEnded { _ in
                bannerDragStartOffset = nil
            }
    }

    private func beginBannerReposition() {
        guard eventBannerImagePath != nil else { return }
        if effectiveBannerIsCompact {
            setBannerCompact(false)
        }
        bannerOffsetDraft = eventBannerOffset
        bannerDragStartOffset = nil
        isRepositioningBanner = true
    }

    private func commitBannerReposition() {
        guard let bookmarkIndex else { return }
        appState.setEventFolderBannerOffset(at: bookmarkIndex, offset: bannerOffsetDraft)
        isRepositioningBanner = false
        bannerDragStartOffset = nil
    }

    private func scaledBannerImageSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return containerSize }

        let scale = max(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func clampedBannerOffset(_ offset: EventBannerOffset, imageSize: CGSize, containerSize: CGSize) -> EventBannerOffset {
        let scaledSize = scaledBannerImageSize(imageSize: imageSize, containerSize: containerSize)
        let maxX = max(0, (scaledSize.width - containerSize.width) / 2)
        let maxY = max(0, (scaledSize.height - containerSize.height) / 2)

        return EventBannerOffset(
            x: min(Double(maxX), max(-Double(maxX), offset.x)),
            y: min(Double(maxY), max(-Double(maxY), offset.y))
        )
    }

    private func chooseBannerPhoto(for bookmarkIndex: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a photo to use as this event banner"
        panel.prompt = "Use as Banner"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !appState.setEventFolderBanner(at: bookmarkIndex, sourceURL: url) {
            let alert = NSAlert()
            alert.messageText = "Could not use this banner"
            alert.informativeText = "The selected image could not be copied into the app cache."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private var isEventLocked: Bool {
        guard let bookmarkIndex else { return false }
        return appState.finalizedEvent(forBookmarkIndex: bookmarkIndex) != nil
    }

    @ViewBuilder
    private var lockEventButton: some View {
        if isEventLocked {
            // Locked state — amber pill communicating stats are preserved
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Stats Locked")
                        .font(.manrope(11, weight: .bold))
                }
                .foregroundStyle(Color.auroraGold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.auroraGold.opacity(0.18))
                        .overlay(Capsule().strokeBorder(Color.auroraGold.opacity(0.45), lineWidth: 1))
                )
                .onTapGesture { showUnlockConfirmPrompt = true }
                .popover(isPresented: $showUnlockConfirmPrompt, arrowEdge: .bottom) {
                    lockActionPopover(
                        icon: "lock.open.fill",
                        title: "Reopen \(currentEventName)?",
                        message: "The saved snapshot will be removed and the event will return to live counts.",
                        primaryTitle: "Reopen Event",
                        primaryColor: .auroraGold,
                        primaryAction: reopenLockedEvent,
                        cancelAction: { showUnlockConfirmPrompt = false }
                    )
                }
                .popover(isPresented: $showPostLockSharePrompt, arrowEdge: .bottom) {
                    postLockSharePopover
                }

                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.auroraGold.opacity(0.72))
                    .onHover { showLockedInfo = $0 }
                    .popover(isPresented: $showLockedInfo, arrowEdge: .bottom) {
                        lockedInfoPopover
                    }
            }
        } else {
            // Unlocked state — CTA + info icon
            HStack(spacing: 6) {
                Button(action: { showLockConfirmPrompt = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock")
                            .font(.system(size: 10, weight: .bold))
                        Text("Lock Event")
                            .font(.manrope(11, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showLockConfirmPrompt, arrowEdge: .bottom) {
                    lockActionPopover(
                        icon: "lock.fill",
                        title: "Lock \(currentEventName)?",
                        message: "All current stats will be saved permanently. You can reopen this event later if needed.",
                        primaryTitle: "Lock Event",
                        primaryColor: .auroraBlue,
                        primaryAction: lockCurrentEvent,
                        cancelAction: { showLockConfirmPrompt = false }
                    )
                }

                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .onHover { showLockInfo = $0 }
                    .popover(isPresented: $showLockInfo, arrowEdge: .bottom) {
                        lockInfoPopover
                    }
            }
        }
    }

    private var lockInfoPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.auroraViolet)
                Text("Lock Event")
                    .font(.sora(14, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
            }
            .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 10) {
                lockInfoRow(
                    icon: "checkmark.circle.fill", color: .auroraHealthy,
                    text: "Saves a permanent snapshot of all stats for this event."
                )
                lockInfoRow(
                    icon: "folder.badge.questionmark", color: .auroraGold,
                    text: "Lock before moving or deleting the folder — guarantees every file contributes to your lifetime stats."
                )
                lockInfoRow(
                    icon: "hand.thumbsup.fill", color: .auroraCyan,
                    text: "After locking, you're free to move, rename, or delete the folder without losing any data."
                )
            }
        }
        .padding(16)
        .frame(width: 272)
        .background(Color.auroraPanel)
        .environment(\.colorScheme, .dark)
    }

    private var lockedInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.auroraGold)
                Text("Stats Locked")
                    .font(.sora(14, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
            }

            Text("Stats, and the gallery's JPG detection, are locked and won't update automatically. Tap the badge to reopen this event and pick up any changes.")
                .font(.manrope(12, weight: .medium))
                .foregroundStyle(Color.auroraMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 250, alignment: .leading)
        .background(Color.auroraPanel)
        .environment(\.colorScheme, .dark)
    }

    private func lockActionPopover(
        icon: String,
        title: String,
        message: String,
        primaryTitle: String,
        primaryColor: Color,
        primaryAction: @escaping () -> Void,
        cancelAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.auroraPanel2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(primaryColor)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.manrope(13, weight: .heavy))
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.manrope(13, weight: .medium))
                    .foregroundStyle(Color.auroraMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                subtlePopoverButton(title: primaryTitle, primary: true, fill: primaryColor, action: primaryAction)
                subtlePopoverButton(title: "Cancel", action: cancelAction)
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(width: 260)
        .background(Color.auroraPanel)
        .environment(\.colorScheme, .dark)
    }

    private var postLockSharePopover: some View {
        VStack(alignment: .leading, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.auroraPanel2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(LinearGradient.auroraGrad)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 6) {
                Text("Share event stats?")
                    .font(.manrope(13, weight: .heavy))
                    .foregroundStyle(Color.auroraTxt)
                Text("Export a social-ready image for Instagram now that this event is locked.")
                    .font(.manrope(13, weight: .medium))
                    .foregroundStyle(Color.auroraMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                subtlePopoverButton(title: "Instagram Story", primary: true, fill: .blue) {
                    showPostLockSharePrompt = false
                    exportSocialShare(format: .story)
                }
                subtlePopoverButton(title: "Instagram Post") {
                    showPostLockSharePrompt = false
                    exportSocialShare(format: .post)
                }
                subtlePopoverButton(title: "Not Now") {
                    showPostLockSharePrompt = false
                }
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(width: 260)
        .background(Color.auroraPanel)
        .environment(\.colorScheme, .dark)
    }

    private func subtlePopoverButton(title: String, primary: Bool = false, fill: Color = .blue, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.manrope(13, weight: .bold))
                .foregroundStyle(.white.opacity(primary ? 1.0 : 0.86))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(primary ? AnyShapeStyle(fill) : AnyShapeStyle(Color.white.opacity(0.10)))
                )
        }
        .buttonStyle(.plain)
    }

    private func lockInfoRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)
            Text(text)
                .font(.manrope(12, weight: .medium))
                .foregroundStyle(Color.auroraMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lockCurrentEvent() {
        guard let bookmarkIndex else { return }
        showLockConfirmPrompt = false

        if appState.finalizeEvent(at: bookmarkIndex) == nil {
            let warn = NSAlert()
            warn.messageText = "No scan data found"
            warn.informativeText = "Run a scan first using the Refresh button, then lock the event."
            warn.addButton(withTitle: "OK")
            warn.runModal()
        } else {
            showPostLockSharePrompt = true
        }
    }

    private func reopenLockedEvent() {
        guard let bookmarkIndex else { return }
        showUnlockConfirmPrompt = false
        appState.reopenEvent(at: bookmarkIndex)
        // Unlocking is exactly the signal that should resume the auto-refresh these
        // gate on `!isEventLocked` — kick it off immediately rather than leaving the
        // user waiting for the next periodic tick (up to 20s away).
        loadJPGCountsByDay()
        checkForNewJPGsAndRebuildIfNeeded()
    }

    private var eventBannerImagePath: String? {
        guard let bookmarkIndex,
              bookmarkIndex >= 0,
              bookmarkIndex < appState.eventFolderBannerImagePaths.count else { return nil }
        let path = appState.eventFolderBannerImagePaths[bookmarkIndex]
        return path.isEmpty ? nil : path
    }

    private var eventBannerOffset: EventBannerOffset {
        guard let bookmarkIndex else { return EventBannerOffset() }
        return appState.bannerOffsetForEvent(at: bookmarkIndex)
    }

    private var activeBannerOffset: EventBannerOffset {
        isRepositioningBanner ? bannerOffsetDraft : eventBannerOffset
    }

    // MARK: - Import History Card (instant — from ImportHistory, no scan)

    @ViewBuilder
    private func importHistoryCard(summary: (photoCount: Int, totalBytes: Int64, sessionCount: Int, firstDate: Date?, lastDate: Date?)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Import History")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: AuroraSpacing.gridGap), count: 5),
                spacing: AuroraSpacing.gridGap
            ) {
                PhotoStatCard(
                    icon: "arrow.down.circle.fill",
                    accent: .auroraHealthy,
                    pages: [(label: "Photos Imported", value: AuroraFormat.count(summary.photoCount))]
                )

                PhotoStatCard(
                    icon: "externaldrive.fill",
                    accent: .auroraBlue,
                    pages: dataTransferredPages(summary: summary)
                )

                PhotoStatCard(
                    icon: "arrow.up.circle.fill",
                    accent: .auroraViolet,
                    pages: importCountPages(summary: summary)
                )

                PhotoStatCard(
                    icon: "clock",
                    accent: .auroraPurple,
                    pages: importingTimePages(dayCount: importDayCount(summary: summary))
                )

                if let first = summary.firstDate {
                    let last = summary.lastDate ?? first
                    PhotoStatCard(
                        icon: "calendar",
                        accent: .auroraMagenta,
                        pages: datePages(first: first, last: last)
                    )
                }
            }
        }
        .auroraCollapsibleStaticCard(storageKey: "event.importHistory")
    }

    private func dataTransferredPages(summary: (photoCount: Int, totalBytes: Int64, sessionCount: Int, firstDate: Date?, lastDate: Date?)) -> [(label: String, value: String)] {
        let total = AuroraFormat.bytesParts(summary.totalBytes)
        let imports = max(summary.sessionCount, 1)
        let avgImport = AuroraFormat.bytesParts(summary.totalBytes / Int64(imports))
        let days = max(importDayCount(summary: summary), 1)
        let avgDay = AuroraFormat.bytesParts(summary.totalBytes / Int64(days))
        return [
            (label: "Data Transferred", value: "\(total.value) \(total.unit)"),
            (label: "Avg / Import", value: "\(avgImport.value) \(avgImport.unit)"),
            (label: "Avg / Day", value: "\(avgDay.value) \(avgDay.unit)")
        ]
    }

    private func importCountPages(summary: (photoCount: Int, totalBytes: Int64, sessionCount: Int, firstDate: Date?, lastDate: Date?)) -> [(label: String, value: String)] {
        let days = max(importDayCount(summary: summary), 1)
        return [
            (label: "Total Imports", value: AuroraFormat.count(summary.sessionCount)),
            (label: "Avg / Day", value: String(format: "%.1f", Double(summary.sessionCount) / Double(days)))
        ]
    }

    private func importingTimePages(dayCount: Int) -> [(label: String, value: String)] {
        guard let report, report.totalDuration > 0 else {
            return [(label: "Time Wasted Importing", value: "—")]
        }
        let total = AuroraFormat.durationParts(report.totalDuration)
        let avgDay = AuroraFormat.durationParts(report.totalDuration / max(dayCount, 1))
        return [
            (label: "Time Wasted Importing", value: "\(total.value) \(total.unit)"),
            (label: "Avg / Day", value: "\(avgDay.value) \(avgDay.unit)")
        ]
    }

    private func importDayCount(summary: (photoCount: Int, totalBytes: Int64, sessionCount: Int, firstDate: Date?, lastDate: Date?)) -> Int {
        let days = Set(eventImportHistoryEntries.map { Calendar.current.startOfDay(for: $0.date) })
        if !days.isEmpty { return days.count }
        return 1
    }

    private func normalizeEventPath(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.auroraViolet)
            Text("Analyzing photos in event folder…")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraMuted)
            Text("This may take a moment for large folders")
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .auroraStaticCard()
    }

    private func errorState(message: String) -> some View {
        let isDiskOffline = message.lowercased().contains("disconnected") || message.lowercased().contains("not found")
        return VStack(spacing: 12) {
            Image(systemName: isDiskOffline ? "externaldrive.badge.xmark" : "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(isDiskOffline ? Color.auroraMuted : Color.orange)
            Text(isDiskOffline ? "Disk not connected" : "Unable to scan folder")
                .font(.manrope(15, weight: .bold))
                .foregroundStyle(Color.auroraTxt)
            Text(isDiskOffline
                 ? "Photo stats (ISO, aperture, cameras, lenses) require the disk to be connected. Connect the disk and click \"Scan Photos\"."
                 : message)
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .auroraStaticCard()
    }

    private var backgroundScanningState: some View {
        let fileCount = backgroundScanFileCount
        let processedCount = backgroundScanProcessedFileCount
        let pct = Int((scanProgress * 100).rounded())
        let quality = currentBackgroundScanQuality ?? .full
        let title = quality == .quick ? "Quick scanning photos…" : "Deep scan running…"
        let timingText = scanTimingText(fileCount: fileCount)
        let showSlowInfo = showSlowScanInfo
        let subtitle = fileCount > 0
            ? (processedCount > 0 ? "Scanned \(processedCount) of \(fileCount) RAW files…" : "Scanning \(fileCount) RAW files…")
            : (quality == .quick ? "Building quick stats first…" : "Refining full EXIF stats in background…")

        return VStack(spacing: 14) {
            HStack {
                Text(title)
                    .font(.manrope(15, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Spacer()
                Text("\(pct)%")
                    .font(.manrope(15, weight: .bold))
                    .foregroundStyle(Color.auroraViolet)
                    .monospacedDigit()
                    .animation(.none, value: pct)
            }

            ProgressView(value: scanProgress)
                .tint(Color.auroraViolet)
                .animation(.linear(duration: 0.4), value: scanProgress)

            Text(subtitle)
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let timingText {
                slowScanTimingRow(timingText: timingText, showInfo: showSlowInfo)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 120)
        .auroraStaticCard()
    }

    private var queuedScanState: some View {
        let status = queuedScanPosition.map { "Queued #\($0)" } ?? "Queued"

        return HStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.auroraViolet)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text("Waiting for other folders to get scanned")
                    .font(.manrope(15, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Text("Aurora scans added folders one at a time to keep the app responsive.")
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
            }

            Spacer()

            Text(status)
                .font(.manrope(12, weight: .bold))
                .foregroundStyle(Color.auroraViolet)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.auroraViolet.opacity(0.14), in: Capsule())
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 120)
        .auroraStaticCard()
    }

    private var emptyState: some View {
        let hasKnownRawFiles = (knownRawFileCount ?? 0) > 0
        return VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundStyle(Color.auroraFaint)
            Text(hasKnownRawFiles ? "Photo stats need a scan" : "No RAW files found")
                .font(.manrope(15, weight: .bold))
                .foregroundStyle(Color.auroraMuted)
            Text(hasKnownRawFiles
                 ? "RAW files are counted, but ISO, cameras and lenses need a fresh scan."
                 : "No supported RAW files found in this folder")
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .auroraStaticCard()
    }

    // MARK: - EXIF Stats Content

    @ViewBuilder
    private func statsContent(for report: StatsReport) -> some View {
        VStack(spacing: 16) {
            if isBackgroundScanning, currentBackgroundScanQuality == .full {
                quickStatsBanner
            }

            photoStatsCard(for: report)

            HStack(alignment: .top, spacing: 16) {
                if !report.allCameras.isEmpty {
                    topCamerasSection(cameras: report.allCameras)
                        .frame(maxWidth: .infinity)
                }
                if !report.allLenses.isEmpty {
                    topLensesSection(report: report)
                        .frame(maxWidth: .infinity)
                }
            }

            ShootingTimePanel(
                report: report,
                title: "Event Shooting Time",
                subtitle: "Working hours and active shooting time for this event",
                sourceNamesByDay: shootingTimeSourceNames(for: report)
            )

            HStack(alignment: .top, spacing: 16) {
                EventDailyMediaChart(
                    title: "RAWs per Day",
                    subtitle: "RAW files captured each event day",
                    entries: rawCountsByDay(for: report),
                    tint: .auroraViolet,
                    emptyMessage: "No RAW day data yet"
                )
                    .frame(maxWidth: .infinity)

                EventDailyMediaChart(
                    title: "JPGs per Day",
                    subtitle: jpgChartSubtitle,
                    entries: jpgCountsByDayEntries,
                    tint: .auroraMagenta,
                    emptyMessage: jpgChartEmptyMessage,
                    isLoading: isLoadingJPGCounts
                )
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func rawCountsByDay(for report: StatsReport) -> [EventDailyMediaChart.Entry] {
        report.captureTimestampsByDay
            .map { day, timestamps in
                EventDailyMediaChart.Entry(dayKey: day, count: timestamps.count)
            }
            .filter { $0.count > 0 }
            .sorted { $0.dayKey < $1.dayKey }
    }

    private var jpgCountsByDayEntries: [EventDailyMediaChart.Entry] {
        let entries = jpgCountsByDay
            .map { day, count in EventDailyMediaChart.Entry(dayKey: day, count: count) }
            .filter { $0.count > 0 }
            .sorted { $0.dayKey < $1.dayKey }
        if !entries.isEmpty { return entries }

        guard deliveredPhotoCount > 0,
              let dayKey = jpgFallbackDayKey else { return [] }
        return [EventDailyMediaChart.Entry(dayKey: dayKey, count: deliveredPhotoCount)]
    }

    private var isShowingJPGTotalFallback: Bool {
        jpgCountsByDay.isEmpty && deliveredPhotoCount > 0 && jpgFallbackDayKey != nil
    }

    private var jpgChartSubtitle: String {
        if isLoadingJPGCounts { return "Counting JPG files…" }
        if isShowingJPGTotalFallback { return "Cached JPG total shown offline" }
        return "JPG deliverables found each day"
    }

    private var jpgFallbackDayKey: String? {
        if let latestRawDay = report?.captureTimestampsByDay.keys.max() {
            return latestRawDay
        }
        if let scanDate {
            return Self.dayKey(from: scanDate)
        }
        return nil
    }

    private var jpgChartEmptyMessage: String {
        if isLoadingJPGCounts { return "Counting JPG files…" }
        if !diskIsReachable, deliveredPhotoCount > 0 { return "Cached JPG total available, day breakdown pending" }
        if !diskIsReachable { return "JPG counts unavailable offline" }
        if deliveredPhotoCount > 0 { return "JPG day breakdown unavailable" }
        return "No JPG files found"
    }

    private static func dayKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func shootingTimeSourceNames(for report: StatsReport) -> [String: String] {
        Dictionary(uniqueKeysWithValues: report.captureTimestampsByDay.keys.map { ($0, eventName) })
    }

    private var quickStatsBanner: some View {
        let pct = Int((scanProgress * 100).rounded())
        let fileCount = backgroundScanFileCount
        let processedCount = backgroundScanProcessedFileCount
        let timingText = scanTimingText(fileCount: fileCount)
        let showSlowInfo = showSlowScanInfo

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.75)
                    .tint(Color.auroraCyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text(refreshBannerTitle)
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                    Text(fileCount > 0
                         ? (processedCount > 0 ? "Deep EXIF scan has analyzed \(processedCount) of \(fileCount) RAWs." : "Deep EXIF scan is analyzing \(fileCount) RAWs in the background.")
                         : "Deep EXIF scan is running in the background and will replace these stats automatically.")
                        .font(.manrope(11, weight: .medium))
                        .foregroundStyle(Color.auroraFaint)
                    if let timingText {
                        slowScanTimingRow(timingText: timingText, showInfo: showSlowInfo)
                    }
                }
                Spacer()
                Text("\(pct)%")
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Color.auroraCyan)
                    .monospacedDigit()
                    .animation(.none, value: pct)
                Text("Preliminary")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Color.auroraCyan)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.auroraCyan.opacity(0.13), in: Capsule())
            }

            ProgressView(value: scanProgress)
                .tint(Color.auroraCyan)
                .animation(.linear(duration: 0.4), value: scanProgress)
        }
        .padding(14)
        .auroraStaticCard()
    }

    private var refreshBannerTitle: String {
        if scanQuality == .partial { return "Stats updating" }
        if scanQuality == .quick { return "Quick stats ready" }
        return "Refreshing stats"
    }

    private func slowScanTimingRow(timingText: String, showInfo: Bool) -> some View {
        HStack(spacing: 6) {
            Text(timingText)
                .font(.manrope(10.5, weight: .semibold))
                .foregroundStyle(Color.auroraFaint.opacity(0.92))
                .monospacedDigit()
            if showInfo {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.auroraCyan.opacity(0.9))
                    .auroraTooltip("Why is this a bit slow?\n\nThis can happen with a considerable number of RAWs, photos stored on a NAS or slower external disk, network latency, large RAW files, or batches that need deeper EXIF metadata.", edge: .top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scanTimingText(fileCount: Int) -> String? {
        guard let bookmarkIndex,
              let startTime = appState.backgroundScanStartTimes[bookmarkIndex] else { return nil }
        let elapsed = Date().timeIntervalSince(startTime)
        let elapsedText = formatDuration(elapsed)
        guard fileCount > 0 else { return "Elapsed: \(elapsedText)" }

        let processed = appState.backgroundScanProcessedFileCount[bookmarkIndex] ?? 0
        if processed > 0 {
            let filesPerSecond = Double(processed) / max(1, elapsed)
            let remainingFiles = max(0, fileCount - processed)
            let remaining = filesPerSecond > 0 ? Double(remainingFiles) / filesPerSecond : 0
            return "Elapsed: \(elapsedText) · ETA: \(formatDuration(remaining))"
        }

        let estimatedTotal = max(30.0, Double(fileCount) * 0.30)
        let remaining = max(0, estimatedTotal - elapsed)
        return "Elapsed: \(elapsedText) · ETA estimate: \(formatDuration(remaining))"
    }

    private func shouldShowSlowScanInfo(fileCount: Int) -> Bool {
        // Gating on remaining time alone made the info icon disappear near the end
        // of a slow scan (ETA drops under 5min even though the scan already took
        // much longer than that) — once a scan has crossed the "slow" threshold,
        // keep the explanation available for the rest of it instead of flickering off.
        if let bookmarkIndex, let startTime = appState.backgroundScanStartTimes[bookmarkIndex] {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > 300 { return true }
        }
        guard let remaining = scanRemainingTime(fileCount: fileCount) else { return false }
        return remaining > 300
    }

    private func scanRemainingTime(fileCount: Int) -> TimeInterval? {
        guard let bookmarkIndex,
              let startTime = appState.backgroundScanStartTimes[bookmarkIndex],
              fileCount > 0 else { return nil }
        let elapsed = Date().timeIntervalSince(startTime)
        let processed = appState.backgroundScanProcessedFileCount[bookmarkIndex] ?? 0
        if processed > 0 {
            let filesPerSecond = Double(processed) / max(1, elapsed)
            guard filesPerSecond > 0 else { return nil }
            return Double(max(0, fileCount - processed)) / filesPerSecond
        }
        return max(0, max(30.0, Double(fileCount) * 0.30) - elapsed)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        return String(format: "%dm %02ds", minutes, secs)
    }

    private func formatSocialDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    @ViewBuilder
    private func photoStatsCard(for report: StatsReport) -> some View {
        let isLimitedData = report.rawOutput.contains("mdls fallback") && report.totalFilesAnalyzed > 0
        let isShowingCachedStatsWithoutCurrentRAWs = diskIsReachable && knownRawFileCount == 0 && report.totalFilesAnalyzed > 0
        VStack(alignment: .leading, spacing: 6) {
            if isShowingCachedStatsWithoutCurrentRAWs {
                HStack(spacing: 8) {
                    Image(systemName: "archivebox")
                        .foregroundStyle(Color.auroraCyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No RAW files currently in this folder")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textPrimary)
                        Text("Showing cached stats from the last scan/import. Import history is kept separately.")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    }
                }
                .padding(10)
                .background(Color.auroraCyan.opacity(0.1))
                .cornerRadius(8)
                .padding(.bottom, 6)
            }

            if isLimitedData {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Limited stats — Spotlight fallback")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textPrimary)
                        Text("ISO and shutter appear when macOS exposes them. Install exiftool for full lens, date and exposure data: brew install exiftool")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: AuroraSpacing.gridGap), count: 7),
                spacing: AuroraSpacing.gridGap
            ) {
                PhotoStatCard(
                    icon: "photo.stack.fill",
                    accent: .auroraCyan,
                    pages: [(label: "RAW Files", value: AuroraFormat.count(rawFileCount(for: report)))]
                )

                PhotoStatCard(
                    icon: "checkmark.rectangle.stack.fill",
                    accent: .auroraHealthy,
                    pages: deliveredPages(for: report)
                )

                PhotoStatCard(icon: "camera.aperture", accent: .auroraBlue, pages: isoPages(for: report))
                PhotoStatCard(icon: "circle.dotted", accent: .auroraViolet, pages: aperturePages(for: report))
                PhotoStatCard(icon: "viewfinder", accent: .auroraMagenta, pages: focalPages(for: report))
                PhotoStatCard(icon: "timer", accent: .auroraPurple, pages: shutterPages(for: report))
                PhotoStatCard(icon: "rectangle.portrait.fill", accent: .auroraLive, pages: orientationPages(for: report))
            }
        }
    }

    private func rawFileCount(for report: StatsReport) -> Int {
        knownRawFileCount ?? report.totalFilesAnalyzed
    }

    private var knownRawFileCount: Int? {
        guard let bookmarkIndex,
              bookmarkIndex >= 0,
              bookmarkIndex < appState.eventFolderCachedCounts.count else { return nil }
        let cachedRawCount = appState.eventFolderCachedCounts[bookmarkIndex]
        return cachedRawCount >= 0 ? cachedRawCount : nil
    }

    private var deliveredPhotoCount: Int {
        guard let bookmarkIndex,
              bookmarkIndex >= 0,
              bookmarkIndex < appState.eventFolderCachedJPGCounts.count else { return 0 }
        return max(appState.eventFolderCachedJPGCounts[bookmarkIndex], 0)
    }

    private func deliveredPages(for report: StatsReport) -> [(label: String, value: String)] {
        let delivered = deliveredPhotoCount
        let rawCount = rawFileCount(for: report)
        return [
            ("Photos Delivered", delivered > 0 ? AuroraFormat.count(delivered) : "—"),
            ("Keep Rate", keepRate(delivered: delivered, rawCount: rawCount))
        ]
    }

    private func keepRate(delivered: Int, rawCount: Int) -> String {
        guard delivered > 0, rawCount > 0 else { return "—" }
        return String(format: "%.1f%%", Double(delivered) / Double(rawCount) * 100)
    }

    private func datePages(first: Date, last: Date) -> [(label: String, value: String)] {
        var pages: [(label: String, value: String)] = [
            (label: "Last Import", value: AuroraFormat.dateMedium(last))
        ]
        if !Calendar.current.isDate(first, inSameDayAs: last) {
            pages.append((label: "First Import", value: AuroraFormat.dateMedium(first)))
        }
        return pages
    }

    private func isoPages(for report: StatsReport) -> [(label: String, value: String)] {
        var pages: [(label: String, value: String)] = [("Avg ISO", formatOptional(report.avgISO, AuroraFormat.iso))]
        if let v = report.maxISO, v > 0 { pages.append(("Highest ISO", AuroraFormat.iso(v))) }
        if let v = report.minISO, v > 0 { pages.append(("Lowest ISO", AuroraFormat.iso(v))) }
        pages.append(("Most Used ISO", formatOptional(report.mostUsedISO, AuroraFormat.iso)))
        return pages
    }

    private func aperturePages(for report: StatsReport) -> [(label: String, value: String)] {
        var pages: [(label: String, value: String)] = [("Avg Aperture", formatOptional(report.avgAperture, AuroraFormat.aperture))]
        if let v = report.maxAperture, v > 0 { pages.append(("Highest Aperture", AuroraFormat.aperture(v))) }
        if let v = report.minAperture, v > 0 { pages.append(("Lowest Aperture", AuroraFormat.aperture(v))) }
        pages.append(("Most Used Aperture", formatOptional(report.mostUsedAperture, AuroraFormat.aperture)))
        return pages
    }

    private func focalPages(for report: StatsReport) -> [(label: String, value: String)] {
        var pages: [(label: String, value: String)] = [("Avg Focal", formatOptional(report.avgFocalLength, AuroraFormat.focal))]
        if let v = report.maxFocalLength, v > 0 { pages.append(("Highest Focal", AuroraFormat.focal(v))) }
        if let v = report.minFocalLength, v > 0 { pages.append(("Lowest Focal", AuroraFormat.focal(v))) }
        pages.append(("Most Used Focal", formatOptional(report.mostUsedFocalLength, AuroraFormat.focal)))
        return pages
    }

    private func shutterPages(for report: StatsReport) -> [(label: String, value: String)] {
        var pages: [(label: String, value: String)] = [("Avg Shutter", formatOptional(report.avgShutterSpeed, AuroraFormat.shutter))]
        if let v = report.minShutterSpeed, v > 0 { pages.append(("Fastest Shutter", AuroraFormat.shutter(v))) }
        if let v = report.maxShutterSpeed, v > 0 { pages.append(("Longest Shutter", AuroraFormat.shutter(v))) }
        pages.append(("Most Used Shutter", formatOptional(report.mostUsedShutterSpeed, AuroraFormat.shutter)))
        return pages
    }

    private func orientationPages(for report: StatsReport) -> [(label: String, value: String)] {
        guard report.portraitCount + report.landscapeCount > 0 else {
            return [("Portraits", "—"), ("Landscapes", "—")]
        }
        return [
            ("Portraits", AuroraFormat.count(report.portraitCount)),
            ("Landscapes", AuroraFormat.count(report.landscapeCount))
        ]
    }

    private func formatOptional(_ value: Double?, _ formatter: (Double) -> String) -> String {
        guard let value, value > 0 else { return "—" }
        return formatter(value)
    }

    // MARK: - Top Lenses

    @ViewBuilder
    private func topLensesSection(report: StatsReport) -> some View {
        let lenses = showAllLenses ? report.allLenses : Array(report.allLenses.prefix(5))
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(
                title: "Top Lenses",
                actionLabel: report.allLenses.count > 5 ? (showAllLenses ? "Less" : "More") : nil
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { showAllLenses.toggle() }
            }

            VStack(spacing: 4) {
                ForEach(lenses) { lens in
                    TopLensRow(lens: lens)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .auroraCollapsibleStaticCard(storageKey: "event.topLenses")
    }

    private func lensCard(lens: StatsReport.LensStat) -> some View {
        VStack(spacing: 8) {
            Text(lens.medal)
                .font(.system(size: 48))
            Text(lens.fullName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("\(lens.count) photos")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.glassBase)
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        )
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.glassBorder, lineWidth: 1))
        .zIndex(lens.rank == 1 ? 10 : Double(4 - lens.rank))
        .scaleEffect(lens.rank == 1 ? 1.05 : 1.0)
        .modifier(HoverScaleEffect())
    }

    // MARK: - Top Cameras

    @ViewBuilder
    private func topCamerasSection(cameras: [StatsReport.CameraStat]) -> some View {
        let visibleCameras = showAllCameras ? cameras : Array(cameras.prefix(5))
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(
                title: "Top Cameras",
                actionLabel: cameras.count > 5 ? (showAllCameras ? "Less" : "More") : nil
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { showAllCameras.toggle() }
            }

            VStack(spacing: 4) {
                ForEach(Array(visibleCameras.enumerated()), id: \.offset) { idx, camera in
                    TopCameraRow(rank: idx + 1, camera: camera)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .auroraCollapsibleStaticCard(storageKey: "event.topCameras")
    }

    private func cameraCard(camera: StatsReport.CameraStat, rank: Int) -> some View {
        VStack(spacing: 8) {
            Text(rank == 1 ? "🥇" : rank == 2 ? "🥈" : "🥉")
                .font(.system(size: 48))
            Text(camera.fullName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("\(camera.count) photos")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.glassBase)
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        )
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.glassBorder, lineWidth: 1))
        .zIndex(rank == 1 ? 10 : Double(4 - rank))
        .scaleEffect(rank == 1 ? 1.05 : 1.0)
        .modifier(HoverScaleEffect())
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        let tb = Double(bytes) / (1024 * 1024 * 1024 * 1024)
        if tb >= 1 { return String(format: "%.2f TB", tb) }
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }

    // MARK: - Load

    /// Load from cache immediately. Never auto-scans — the scan is triggered when the
    /// folder is first added (Statistics/Dashboard). The user can manually refresh here.
    @MainActor
    /// `StatsReport` carries a timestamp per analyzed file (`captureTimestampsByDay`)
    /// plus several per-camera/lens/shutter/ISO/aperture/focal-length count
    /// dictionaries — for a large "production" event (thousands of RAWs) this is a
    /// meaningfully bigger JSON payload than the gallery's manifest. Reading and
    /// decoding it synchronously on the main thread (the same bug already found and
    /// fixed for `loadGalleryFromCache`) blocked the UI every time this ran — on
    /// every event open, and every 400ms tick of the scan-progress poll while a scan
    /// is running.
    private func loadFromCache() {
        let path = destinationPath
        let previousPath = bookmarkIndex.flatMap { idx -> String? in
            guard idx < appState.eventFolderPreviousCachedPaths.count else { return nil }
            let candidate = appState.eventFolderPreviousCachedPaths[idx]
            return candidate.isEmpty ? nil : candidate
        }
        Task.detached(priority: .userInitiated) {
            let cached = EventStatsCache.loadWithQuality(forPath: path) ?? previousPath.flatMap { EventStatsCache.loadWithQuality(forPath: $0) }
            await MainActor.run {
                guard currentEventPath == path else { return }
                if let cached {
                    report = cached.report
                    scanDate = cached.scanDate
                    scanQuality = cached.scanQuality
                    isCachedData = true
                    hasLoaded = true
                    errorMessage = nil
                } else {
                    // No cache yet — mark as loaded so we show the correct empty/offline state
                    hasLoaded = true
                    let url = URL(fileURLWithPath: path)
                    let reachable = !path.isEmpty && (try? url.checkResourceIsReachable()) == true
                    if !reachable {
                        errorMessage = "Folder not found — disk may be disconnected"
                        appState.log("Event folder unreachable: \(path)", level: .warning)
                    }
                    // If reachable but no cache: show emptyState with "Scan Photos" button in header
                }
            }
        }
    }

    /// Still used as a synchronous fallback inside `loadEventStats()` (an already
    /// `@MainActor` function) for the rare case a fresh scan comes back empty and we
    /// fall back to the last cached stats — not a hot/repeated path, so the
    /// synchronous read there is fine. `loadFromCache()` above does its own capture
    /// of the relevant paths instead of calling this, since it needs to run the
    /// actual disk read off the main thread.
    private func cachedStatsForCurrentEvent() -> (report: StatsReport, scanDate: Date, rawFileCountAtScan: Int?, scanQuality: EventStatsScanQuality)? {
        if let cached = EventStatsCache.loadWithQuality(forPath: destinationPath) {
            return cached
        }
        guard let bookmarkIndex,
              bookmarkIndex < appState.eventFolderPreviousCachedPaths.count else { return nil }
        let previousPath = appState.eventFolderPreviousCachedPaths[bookmarkIndex]
        guard !previousPath.isEmpty else { return nil }
        return EventStatsCache.loadWithQuality(forPath: previousPath)
    }

    /// Fresh exiftool scan — saves result to cache on success.
    @MainActor
    private func loadEventStats() {
        guard !destinationPath.isEmpty else { return }
        let url = URL(fileURLWithPath: destinationPath)
        guard (try? url.checkResourceIsReachable()) == true else { return }

        isLoading = true
        errorMessage = nil

        // Register in backgroundScanningBookmarkIndices so the progress bar and
        // sidebar indicator activate — same mechanism used by auto-scans.
        if let idx = bookmarkIndex {
            appState.backgroundScanningBookmarkIndices.insert(idx)
            appState.backgroundScanStartTimes[idx] = Date()
            appState.backgroundScanQualities[idx] = .full
        }

        Task {
            guard let runner = statsRunner else {
                isLoading = false
                if let idx = bookmarkIndex {
                    appState.backgroundScanningBookmarkIndices.remove(idx)
                    appState.backgroundScanProcessedFileCount.removeValue(forKey: idx)
                    appState.backgroundScanStartTimes.removeValue(forKey: idx)
                    appState.backgroundScanQualities.removeValue(forKey: idx)
                }
                return
            }

            // Count files upfront so the estimated progress bar is meaningful.
            if let idx = bookmarkIndex, appState.backgroundScanFileCount[idx] == nil {
                let count = VolumeWatcher.countRawFiles(at: url, extensions: appState.supportedExtensions)
                appState.backgroundScanFileCount[idx] = count
                appState.backgroundScanProcessedFileCount[idx] = 0
            }

            let result = await runner.runStatsForEventFolderInBatches(at: url, quality: .full) { processed, total, partialReport in
                if let idx = bookmarkIndex {
                    appState.backgroundScanProcessedFileCount[idx] = processed
                    appState.backgroundScanFileCount[idx] = total
                    if let partialReport, partialReport.totalFilesAnalyzed > 0 {
                        let now = Date()
                        EventStatsCache.save(partialReport, forPath: destinationPath, scanDate: now, rawFileCountAtScan: partialReport.totalFilesAnalyzed, scanQuality: .partial)
                        appState.noteEventStatsCacheChanged()
                        appState.updateEventFolderCache(at: idx, count: max(total, partialReport.totalFilesAnalyzed), path: destinationPath)
                        appState.setEventFolderPeakIfHigher(at: idx, count: max(total, partialReport.totalFilesAnalyzed))
                    }
                }
            }

            if let idx = bookmarkIndex {
                appState.backgroundScanningBookmarkIndices.remove(idx)
                appState.backgroundScanFileCount.removeValue(forKey: idx)
                appState.backgroundScanProcessedFileCount.removeValue(forKey: idx)
                appState.backgroundScanStartTimes.removeValue(forKey: idx)
                appState.backgroundScanQualities.removeValue(forKey: idx)
            }
            isLoading = false
            hasLoaded = true

            if let r = result, r.totalFilesAnalyzed > 0 {
                report = r
                scanQuality = .full
                isCachedData = false
                let now = Date()
                scanDate = now
                EventStatsCache.save(r, forPath: destinationPath, scanDate: now, rawFileCountAtScan: r.totalFilesAnalyzed, scanQuality: .full)
                appState.noteEventStatsCacheChanged()
                if let bookmarkIndex {
                    appState.updateEventFolderCache(at: bookmarkIndex, count: r.totalFilesAnalyzed, path: destinationPath)
                    appState.setEventFolderPeakIfHigher(at: bookmarkIndex, count: r.totalFilesAnalyzed)
                }
                appState.log("Event stats scanned & cached: \(eventName) — \(r.totalFilesAnalyzed) photos")
                rebuildGalleryInBackground()
            } else {
                if let bookmarkIndex, appState.isLibraryFolder(at: bookmarkIndex) {
                    if let cached = cachedStatsForCurrentEvent() {
                        report = cached.report
                        scanDate = cached.scanDate
                        scanQuality = cached.scanQuality
                        isCachedData = true
                    }
                    appState.log("Library folder scan returned no RAW stats; keeping cached stats for \(eventName)", level: .warning)
                    return
                }
                let fileCount = VolumeWatcher.listRawFiles(at: url, extensions: appState.supportedExtensions).count
                if fileCount == 0 {
                    if let bookmarkIndex {
                        appState.updateEventFolderCache(at: bookmarkIndex, count: 0, path: destinationPath)
                    }
                    if let cached = cachedStatsForCurrentEvent() {
                        report = cached.report
                        scanDate = cached.scanDate
                        scanQuality = cached.scanQuality
                        isCachedData = true
                    }
                    appState.log("Event scan found no current RAW files; keeping cached stats for \(eventName)", level: .warning)
                } else if report == nil {
                    errorMessage = "Could not analyze files — make sure exiftool is installed (brew install exiftool)"
                }
            }
        }
    }
}

private struct EventDailyMediaChart: View {
    struct Entry: Identifiable, Equatable {
        let dayKey: String
        let count: Int

        var id: String { dayKey }
    }

    let title: String
    let subtitle: String
    let entries: [Entry]
    let tint: Color
    let emptyMessage: String
    var isLoading: Bool = false

    @State private var hoveredEntryID: String?
    @State private var isHoveringChart = false
    @State private var animateBars = false

    private var displayEntries: [Entry] {
        guard !entries.isEmpty else { return [] }
        let sorted = entries.sorted { $0.dayKey < $1.dayKey }
        guard let latestDate = sorted.compactMap({ Self.date(from: $0.dayKey) }).max() else { return sorted }

        let countsByDay = Dictionary(uniqueKeysWithValues: sorted.map { ($0.dayKey, $0.count) })
        let calendar = Calendar(identifier: .gregorian)
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - 6, to: latestDate) else { return nil }
            let key = Self.dayKey(from: date)
            return Entry(dayKey: key, count: countsByDay[key] ?? 0)
        }
    }

    private var maxCount: Int { max(displayEntries.map(\.count).max() ?? 1, 1) }
    private var maxEntryID: String? { displayEntries.max { $0.count < $1.count }?.id }
    private var totalText: String? {
        guard !entries.isEmpty else { return nil }
        return AuroraFormat.count(entries.reduce(0) { $0 + $1.count })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    AuroraCollapsibleHeaderTitle(title: title)
                    Text(subtitle)
                        .font(.manrope(11, weight: .semibold))
                        .foregroundStyle(Color.auroraFaint)
                        .lineLimit(1)
                }
                Spacer()
                if let total = totalText {
                    Text(total)
                        .font(.manrope(11, weight: .bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule(style: .continuous).fill(tint.opacity(0.12)))
                }
            }

            if entries.isEmpty {
                VStack(spacing: 10) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(emptyMessage)
                        .font(.manrope(12, weight: .semibold))
                        .foregroundStyle(Color.auroraFaint)
                }
                .frame(maxWidth: .infinity, minHeight: 170)
            } else {
                chart
                    .frame(height: 190)
            }
        }
        .auroraCollapsibleStaticCard(
            storageKey: "event.dailyMedia.\(title)",
            radius: AuroraRadius.large,
            paddingH: 16,
            paddingV: 16,
            collapsedVisibleHeight: 31
        )
        .onAppear { animateBars = true }
        .onChange(of: entries) { _, _ in restartAnimation() }
    }

    private var chart: some View {
        GeometryReader { geo in
            let chartEntries = displayEntries
            let chartHeight = geo.size.height - 42
            let contentWidth = max(geo.size.width, CGFloat(chartEntries.count) * ImportTimelinePeriod.day.minBarWidth)

            ZStack(alignment: .bottomLeading) {
                grid(width: contentWidth, height: chartHeight)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(chartEntries) { entry in
                        let activeID = hoveredEntryID ?? (isHoveringChart ? nil : maxEntryID)
                        EventDailyTimelineBar(
                            entry: entry,
                            fraction: animateBars ? CGFloat(entry.count) / CGFloat(maxCount) : 0,
                            isHighlighted: entry.id == activeID,
                            chartHeight: chartHeight
                        )
                        .frame(width: barWidth(totalWidth: contentWidth, entryCount: chartEntries.count))
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            guard hovering else { return }
                            withAnimation(.easeOut(duration: 0.12)) { hoveredEntryID = entry.id }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .frame(width: contentWidth, height: geo.size.height, alignment: .bottomLeading)
            }
            .frame(width: contentWidth, height: geo.size.height)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHoveringChart = hovering
                    if !hovering { hoveredEntryID = nil }
                }
            }
        }
    }

    private func barWidth(totalWidth: CGFloat, entryCount: Int) -> CGFloat {
        let totalSpacing = CGFloat(max(entryCount - 1, 0)) * 6 + 12
        return max(ImportTimelinePeriod.day.minBarWidth, (totalWidth - totalSpacing) / CGFloat(max(entryCount, 1)))
    }

    private func grid(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<4) { index in
                Rectangle()
                    .fill(index == 3 ? Color.auroraStroke.opacity(0.7) : Color.auroraStroke.opacity(0.28))
                    .frame(height: 1)
                if index < 3 { Spacer() }
            }
        }
        .frame(width: width, height: height)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
    }

    private func restartAnimation() {
        animateBars = false
        withAnimation(.timingCurve(0.18, 0.86, 0.22, 1, duration: 0.95)) {
            animateBars = true
        }
    }

    private static func date(from dayKey: String) -> Date? {
        dayKeyFormatter.date(from: dayKey)
    }

    private static func dayKey(from date: Date) -> String {
        dayKeyFormatter.string(from: date)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct EventDailyTimelineBar: View {
    let entry: EventDailyMediaChart.Entry
    let fraction: CGFloat
    let isHighlighted: Bool
    let chartHeight: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            if isHighlighted {
                Text(AuroraFormat.count(entry.count))
                    .font(.sora(10.5, weight: .heavy))
                    .foregroundStyle(Color.auroraCyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(height: 14)
            } else {
                Spacer().frame(height: 14)
            }

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.auroraPanel2.opacity(0.55))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(barGradient)
                    .frame(height: entry.count > 0 ? max(6, chartHeight * min(max(fraction, 0), 1)) : 0)
                    .shadow(color: barTint.opacity(isHighlighted ? 0.55 : 0.24), radius: isHighlighted ? 12 : 5, x: 0, y: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: chartHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )

            Text(label)
                .font(.manrope(10, weight: .bold))
                .foregroundStyle(isHighlighted ? Color.auroraTxt : Color.auroraFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(height: 18)
        }
    }

    private var label: String { isHighlighted ? shortLabel : "" }

    private var shortLabel: String {
        let parts = entry.dayKey.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return entry.dayKey }
        let monthSymbols = Calendar.current.shortMonthSymbols
        let monthName = (1...12).contains(month) ? monthSymbols[month - 1] : String(parts[1])
        return "\(monthName) \(day)"
    }

    private var barTint: Color { isHighlighted ? .auroraCyan : .auroraViolet }

    private var barGradient: LinearGradient {
        LinearGradient(
            colors: isHighlighted
                ? [Color.auroraCyan, Color.auroraBlue]
                : [Color.auroraViolet.opacity(0.92), Color.auroraMagenta.opacity(0.8)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
