import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    @State private var volumeWatcher: VolumeWatcher?
    @State private var importEngine = ImportEngine()
    @State private var activeImportEngines: [String: ImportEngine] = [:]
    @State private var statsRunner: StatsRunner?
    @State private var showProgressOverlay = false
    @State private var selectedNavItem: NavigationItem = .statistics
    @State private var showAutoImportOverlay = false
    @State private var autoImportCountdown = 5
    @State private var autoImportTask: Task<Void, Never>?
    @State private var eventCountsRefreshTask: Task<Void, Never>?
    @State private var telegramDailySummaryTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            AuroraBackground()

            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    AuroraSidebarView(selectedItem: $selectedNavItem, appState: appState)

                    ZStack {
                        mainContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                        if showProgressOverlay {
                            Color.black.opacity(0.55).ignoresSafeArea()
                            ProgressOverlayView(
                                appState: appState,
                                onPause: pauseImport,
                                onResume: resumeImport,
                                onCancel: cancelImport
                            )
                        }
                        if showAutoImportOverlay {
                            Color.black.opacity(0.55).ignoresSafeArea()
                            autoImportOverlay
                        }
                    }
                }

                GridRow {
                    AuroraStatusBarView(appState: appState)
                        .gridCellColumns(2)
                }
            }
        }
        .frame(minWidth: 1280, minHeight: 800)
        .ignoresSafeArea()
        #if os(macOS)
        .background(TransparentTitleBar())
        #endif
        .onAppear { setupServices() }
        .onDisappear {
            stopEventCountsRefreshTimer()
            stopTelegramDailySummaryScheduler()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cardDetected)) { _ in
            selectedNavItem = .dashboard
        }
        .onReceive(NotificationCenter.default.publisher(for: .startAutoImport)) { _ in
            startAutoImportCountdown()
        }
        .onChange(of: appState.autoImport) { _, isEnabled in
            if !isEnabled { cancelAutoImportCountdown() }
        }
        .onChange(of: appState.destinationURL) { _, _ in
            volumeWatcher?.refreshMountedVolumes()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                startEventCountsRefreshTimer()
            } else {
                stopEventCountsRefreshTimer()
            }
        }
    }

    // MARK: - Routing

    @ViewBuilder
    private var mainContent: some View {
        switch selectedNavItem {
        case .dashboard:
            DashboardView(
                appState: appState,
                volumeWatcher: volumeWatcher,
                statsRunner: statsRunner,
                onImportNow: startImport,
                onPause: pauseImport,
                onResume: resumeImport,
                onCancel: cancelImport,
                onViewAllEvents: { selectedNavItem = .statistics },
                onSelectEvent: selectEventFromDashboard
            )
        case .statistics:
            StatisticsView(appState: appState, statsRunner: statsRunner) { bookmarkIndex in
                guard let eventIndex = appState.uniqueImportDestinations.firstIndex(where: { $0.bookmarkIndex == bookmarkIndex }) else { return }
                selectedNavItem = .event(index: eventIndex)
            }
        case .activity:
            ActivityView(appState: appState)
        case .storage:
            StorageView(appState: appState)
        case .settings:
            SettingsView(appState: appState)
        case .logs:
            LogsView(appState: appState)
        case .event(let index):
            EventStatsView(
                appState: appState,
                destinationPath: index < appState.uniqueImportDestinations.count
                    ? appState.uniqueImportDestinations[index].path : "",
                eventName: index < appState.uniqueImportDestinations.count
                    ? appState.uniqueImportDestinations[index].name : "",
                bookmarkIndex: index < appState.uniqueImportDestinations.count
                    ? appState.uniqueImportDestinations[index].bookmarkIndex : nil,
                statsRunner: statsRunner
            )
        }
    }

    // MARK: - Setup

    private func selectEventFromDashboard(_ event: EventAggregate) {
        let eventPath = normalizedPath(event.id)
        guard let index = appState.uniqueImportDestinations.firstIndex(where: { destination in
            let destinationPath = normalizedPath(destination.path)
            return destinationPath == eventPath
                || destinationPath.hasPrefix(eventPath + "/")
                || eventPath.hasPrefix(destinationPath + "/")
        }) else { return }

        selectedNavItem = .event(index: index)
    }

    private func normalizedPath(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func setupServices() {
        guard volumeWatcher == nil else { return }
        let watcher = VolumeWatcher(appState: appState)
        volumeWatcher = watcher
        statsRunner = StatsRunner(appState: appState)
        watcher.startWatching()
        startEventCountsRefreshTimer()
        startTelegramDailySummaryScheduler()
        appState.log("App started — Aurora v1.0")
    }

    private func startEventCountsRefreshTimer() {
        guard eventCountsRefreshTask == nil else { return }
        appState.refreshEventFolderMediaCounts()

        eventCountsRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                if Task.isCancelled { return }
                appState.refreshEventFolderMediaCounts()
            }
        }
    }

    private func stopEventCountsRefreshTimer() {
        eventCountsRefreshTask?.cancel()
        eventCountsRefreshTask = nil
    }

    private func startTelegramDailySummaryScheduler() {
        guard telegramDailySummaryTask == nil else { return }
        telegramDailySummaryTask = Task {
            await attemptTelegramDailySummarySend()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                if Task.isCancelled { return }
                await attemptTelegramDailySummarySend()
            }
        }
    }

    private func stopTelegramDailySummaryScheduler() {
        telegramDailySummaryTask?.cancel()
        telegramDailySummaryTask = nil
    }

    private func attemptTelegramDailySummarySend() async {
        do {
            try await TelegramDailySummaryService.sendDailySummaryIfDue()
            await MainActor.run {
                appState.log("Telegram daily summary sent")
            }
        } catch let error as TelegramDailySummaryService.SummaryError {
            switch error {
            case .tooEarly, .alreadySent, .noImportsToday, .disabledOrIncomplete:
                break
            case .invalidURL, .telegramRejected:
                await MainActor.run {
                    appState.log("Telegram daily summary failed: \(error.localizedDescription)", level: .warning)
                }
            }
        } catch {
            await MainActor.run {
                appState.log("Telegram daily summary failed: \(error.localizedDescription)", level: .warning)
            }
        }
    }

    // MARK: - Auto-import overlay

    private var autoImportOverlay: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                IconChip(systemName: "bolt.fill", color: .auroraCyan, size: 36, iconScale: 0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Importing in \(autoImportCountdown)")
                        .font(.sora(20, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                    Text("Card detected. Import starts automatically.")
                        .font(.manrope(12, weight: .medium))
                        .foregroundStyle(Color.auroraMuted)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    cancelAutoImportCountdown()
                    startImport()
                } label: {
                    Text("Import Now")
                }
                .buttonStyle(AuroraGradientButtonStyle(compact: true))

                Button {
                    cancelAutoImportCountdown()
                    appState.autoImport = false
                } label: {
                    Text("Stop Auto-Import")
                }
                .buttonStyle(AuroraGhostButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .fill(Color.auroraBg2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 16)
    }

    private func startAutoImportCountdown() {
        guard appState.autoImport, appState.destinationURL != nil else { return }
        guard autoImportTask == nil else { return }

        autoImportCountdown = 5
        showAutoImportOverlay = true

        autoImportTask = Task {
            while autoImportCountdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                if !appState.autoImport {
                    await MainActor.run { cancelAutoImportCountdown() }
                    return
                }
                await MainActor.run { autoImportCountdown -= 1 }
            }

            await MainActor.run {
                cancelAutoImportCountdown()
                startImport()
            }
        }
    }

    private func cancelAutoImportCountdown() {
        autoImportTask?.cancel()
        autoImportTask = nil
        showAutoImportOverlay = false
        autoImportCountdown = 5
    }

    // MARK: - Import actions

    private func startImport() {
        guard isImportStartAllowed else {
            appState.log("Cannot import: another import is already running", level: .warning)
            return
        }

        let importSources = eligibleImportVolumes()
        guard let source = importSources.first else {
            appState.log("Cannot import: no active volume", level: .warning)
            return
        }
        guard let dest = appState.destinationURL else {
            appState.log("Cannot import: no destination selected", level: .warning)
            return
        }
        if let finalized = appState.finalizedEvent(matchingPath: dest.path) {
            let alert = NSAlert()
            alert.messageText = "\"\(finalized.name)\" is finalized"
            alert.informativeText = "Reopen the event to continue importing into this folder."
            alert.addButton(withTitle: "Reopen and Import")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else {
                appState.log("Import cancelled: destination belongs to finalized event \(finalized.name)", level: .warning)
                return
            }
            if let idx = appState.eventFolderFinalizedEventID.firstIndex(where: { $0 == finalized.id }) {
                appState.reopenEvent(at: idx)
            }
        }

        if importSources.count > 1 {
            startMultiCardImport(sources: Array(importSources.prefix(2)), destination: dest)
            return
        }

        guard let watcher = volumeWatcher else { return }

        appState.importState = .scanning
        showProgressOverlay = true
        appState.importJobs = []
        appState.log("Starting import from \(source.name) to \(dest.path)")

        Task {
            let sourceAccessing = source.path.startAccessingSecurityScopedResource()
            defer { if sourceAccessing { source.path.stopAccessingSecurityScopedResource() } }

            let files = watcher.listRawFiles(at: source.path).sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            guard !files.isEmpty else {
                appState.importState = .idle
                showProgressOverlay = false
                appState.log("No RAW files found on \(source.name)", level: .warning)
                return
            }

            appState.log("Found \(files.count) RAW files to import")
            appState.importState = .importing
            appState.importProgress = ImportProgress(totalFiles: files.count, startTime: Date())

            let destAccessing = BookmarkManager.startAccessing(dest)
            defer { if destAccessing { BookmarkManager.stopAccessing(dest) } }

            do {
                let engineMode: ImportEngine.Mode = appState.importMode == .copy ? .copy : .move
                let importDate = Date()
                let captureDates = appState.renameOnImport && RenameTemplateRenderer.usesDateTokens(appState.renameTemplate)
                    ? await RenameCaptureDateReader.captureDates(for: files)
                    : [:]
                let renameOptions = appState.renameOnImport
                    ? ImportRenameOptions(
                        template: appState.renameTemplate,
                        eventName: appState.renameEventName(forDestinationPath: dest.path),
                        importDate: importDate,
                        totalCount: files.count,
                        captureDatesByPath: captureDates
                    )
                    : nil
                let result = try await importEngine.importFiles(
                    from: files, to: dest, mode: engineMode, renameOptions: renameOptions
                ) { progress in
                    Task { @MainActor in
                        appState.importProgress.completedFiles = progress.completedFiles
                        appState.importProgress.totalFiles = progress.totalFiles
                        appState.importProgress.transferredBytes = progress.transferredBytes
                        appState.importProgress.totalBytes = progress.totalBytes
                        appState.importProgress.currentFileName = progress.currentFileName
                        appState.importProgress.bytesPerSecond = progress.bytesPerSecond
                        appState.importProgress.skippedFiles = progress.skippedFiles
                        appState.importProgress.statusMessage = progress.statusMessage
                    }
                }
                volumeWatcher?.refreshMountedVolumes()

                appState.importState = .done
                let report = ImportReport(
                    sourceVolumeName: source.name,
                    sourcePath: source.path.path,
                    destinationPath: result.destinationPath,
                    fileCount: result.fileCount,
                    totalBytes: result.totalBytes,
                    duration: result.duration,
                    averageSpeed: result.averageSpeed,
                    importedFiles: result.importedFiles
                )
                appState.lastImportReport = report
                appState.log("Import complete: \(report.summary)")
                if result.skippedFiles > 0 {
                    appState.log("Skipped \(result.skippedFiles) duplicate file\(result.skippedFiles == 1 ? "" : "s") already present in destination")
                }

                if result.importedFiles.isEmpty {
                    if result.skippedFiles > 0 {
                        appState.sourceFileCountForDestinationCheck = result.skippedFiles
                        appState.allDestinationFilesAlreadyImported = true
                        appState.sourceFilesImportStatusMessage = "All \(result.skippedFiles) files are already imported"
                    }
                    try? await Task.sleep(for: .seconds(1))
                    showProgressOverlay = false
                    appState.importState = .idle
                    return
                } else if result.skippedFiles > 0 {
                    appState.sourceFileCountForDestinationCheck = result.skippedFiles
                    appState.allDestinationFilesAlreadyImported = false
                    appState.sourceFilesImportStatusMessage = "Skipped \(result.skippedFiles) duplicate file\(result.skippedFiles == 1 ? "" : "s")"
                }

                if appState.autoEject {
                    appState.importState = .ejecting
                    appState.log("Ejecting card...")
                    await Task.detached { sync() }.value
                    try? await Task.sleep(for: .seconds(3))
                    let ejected = await VolumeEjector.eject(volumeURL: source.path)
                    appState.importState = .ejectingDone
                    if ejected {
                        appState.log("Ejecting card... Done")
                    } else {
                        appState.log("⚠ Failed to eject \(source.name). You may need to eject manually.", level: .warning)
                    }
                    try? await Task.sleep(for: .milliseconds(800))
                }

                appState.importState = .generatingStats
                appState.log("Generating stats...")
                await statsRunner?.runStats(
                    importedFiles: result.importedFiles,
                    destinationPath: result.destinationPath,
                    duration: result.duration
                )

                if let lastStats = appState.statsReport {
                    appState.totalStatsReport = StatsReport.combine(appState.totalStatsReport, lastStats)
                    appState.log("Total stats updated: \(appState.totalStatsReport?.totalFilesAnalyzed ?? 0) files total")

                    let historyEntry = ImportHistoryEntry(
                        sourceName: source.name,
                        destinationPath: result.destinationPath,
                        fileCount: result.importedFiles.count,
                        totalBytes: lastStats.totalBytes
                    )
                    ImportHistoryStorage.add(historyEntry)
                    appState.importHistory = ImportHistoryStorage.load()
                    appState.mergeImportedStatsIntoEventCache(lastStats, destinationPath: result.destinationPath)
                    appState.recordTelegramDailyImport(
                        sourceName: source.name,
                        destinationPath: result.destinationPath,
                        fileCount: result.importedFiles.count,
                        totalBytes: lastStats.totalBytes,
                        duration: result.duration,
                        report: lastStats
                    )
                    Task { await attemptTelegramDailySummarySend() }
                }
                try? await Task.sleep(for: .seconds(1))
                showProgressOverlay = false
                selectedNavItem = .statistics

                try? await Task.sleep(for: .seconds(1))
                if appState.importState == .done || appState.importState == .ejecting
                    || appState.importState == .ejectingDone || appState.importState == .generatingStats {
                    appState.importState = .idle
                }

            } catch ImportError.cancelled {
                appState.importState = .idle
                showProgressOverlay = false
                appState.log("Import cancelled by user", level: .warning)
            } catch {
                appState.importProgress.failureMessage = error.localizedDescription
                appState.importProgress.statusMessage = "Import failed: \(error.localizedDescription)"
                appState.importState = .error(error.localizedDescription)
                appState.log("Import failed: \(error.localizedDescription)", level: .error)
                try? await Task.sleep(for: .seconds(3))
                showProgressOverlay = false
                appState.importState = .idle
            }
        }
    }

    private var isImportStartAllowed: Bool {
        switch appState.importState {
        case .idle, .done, .ejectingDone, .error:
            return true
        default:
            return false
        }
    }

    private func eligibleImportVolumes() -> [VolumeInfo] {
        let volumes = appState.mountedVolumes.filter { $0.rawFileCount > 0 && !isDestinationVolume($0.path) }
        guard !volumes.isEmpty else {
            if let active = appState.activeVolume, active.rawFileCount > 0, !isDestinationVolume(active.path) { return [active] }
            return []
        }
        if let active = appState.activeVolume,
           let activeIndex = volumes.firstIndex(where: { $0.path == active.path }) {
            var ordered = volumes
            ordered.remove(at: activeIndex)
            ordered.insert(active, at: 0)
            return ordered
        }
        return volumes
    }

    private func isDestinationVolume(_ sourceURL: URL) -> Bool {
        guard let destinationURL = appState.destinationURL else { return false }
        let sourcePath = normalizedPath(sourceURL.path)
        let destinationPath = normalizedPath(destinationURL.path)
        return destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/")
    }

    private func startMultiCardImport(sources: [VolumeInfo], destination dest: URL) {
        guard !sources.isEmpty else { return }
        guard sources.count > 1 else { return }

        let startDate = Date()
        let jobIDs = sources.map { $0.id }
        let engines = Dictionary(uniqueKeysWithValues: jobIDs.map { ($0, ImportEngine()) })
        activeImportEngines = engines
        appState.importJobs = sources.map { source in
            ImportJobProgress(
                id: source.id,
                sourceName: source.name,
                sourcePath: source.path.path,
                state: .scanning,
                progress: ImportProgress(totalFiles: source.rawFileCount, startTime: startDate)
            )
        }
        appState.importProgress = ImportProgress(
            totalFiles: sources.reduce(0) { $0 + max($1.rawFileCount, 0) },
            startTime: startDate
        )
        appState.importState = .scanning
        showProgressOverlay = true
        appState.log("Starting parallel import from \(sources.count) cards to \(dest.path)")

        let mode: ImportEngine.Mode = appState.importMode == .copy ? .copy : .move
        let renameOnImport = appState.renameOnImport
        let renameTemplate = appState.renameTemplate
        let importDate = Date()
        let eventName = appState.renameEventName(forDestinationPath: dest.path)
        let supportedExtensions = appState.supportedExtensions
        let reservationCoordinator = DestinationReservationCoordinator()

        Task {
            let outcomes = await withTaskGroup(of: MultiImportOutcome.self) { group in
                for source in sources {
                    guard let engine = engines[source.id] else { continue }
                    group.addTask {
                        await runMultiImportJob(
                            source: source,
                            dest: dest,
                            mode: mode,
                            renameOnImport: renameOnImport,
                            renameTemplate: renameTemplate,
                            eventName: eventName,
                            importDate: importDate,
                            supportedExtensions: supportedExtensions,
                            engine: engine,
                            reservationCoordinator: reservationCoordinator
                        )
                    }
                }

                var finished: [MultiImportOutcome] = []
                for await outcome in group {
                    finished.append(outcome)
                }
                return finished
            }

            activeImportEngines.removeAll()
            volumeWatcher?.refreshMountedVolumes()

            let successful = outcomes.filter { $0.errorMessage == nil }
            let failed = outcomes.filter { $0.errorMessage != nil }
            let importedOutcomes = successful.filter { !$0.result.importedFiles.isEmpty }
            let skippedFiles = successful.reduce(0) { $0 + $1.result.skippedFiles }

            if !failed.isEmpty {
                let message = failed.map { "\($0.source.name): \($0.errorMessage ?? "unknown error")" }.joined(separator: " · ")
                appState.importProgress.failureMessage = message
                appState.importProgress.statusMessage = "Some card imports failed: \(message)"
                appState.log("Parallel import failures: \(message)", level: .error)
            }

            if importedOutcomes.isEmpty {
                if skippedFiles > 0 {
                    appState.sourceFileCountForDestinationCheck = skippedFiles
                    appState.allDestinationFilesAlreadyImported = true
                    appState.sourceFilesImportStatusMessage = "All \(skippedFiles) files are already imported"
                }
                try? await Task.sleep(for: .seconds(1))
                showProgressOverlay = false
                appState.importState = failed.isEmpty ? .idle : .error(appState.importProgress.failureMessage ?? "Import failed")
                try? await Task.sleep(for: .seconds(2))
                appState.importState = .idle
                appState.importJobs = []
                return
            }

            if skippedFiles > 0 {
                appState.sourceFileCountForDestinationCheck = skippedFiles
                appState.allDestinationFilesAlreadyImported = false
                appState.sourceFilesImportStatusMessage = "Skipped \(skippedFiles) duplicate file\(skippedFiles == 1 ? "" : "s")"
            }

            appState.importState = .generatingStats
            appState.log("Generating stats for \(importedOutcomes.count) card import\(importedOutcomes.count == 1 ? "" : "s")...")

            var combinedSessionStats: StatsReport?
            var combinedImportedFiles: [String] = []
            var combinedBytes: Int64 = 0
            let startedAt = startDate

            for outcome in importedOutcomes {
                await statsRunner?.runStats(
                    importedFiles: outcome.result.importedFiles,
                    destinationPath: outcome.result.destinationPath,
                    duration: outcome.result.duration
                )

                guard let lastStats = appState.statsReport else { continue }
                combinedSessionStats = StatsReport.combine(combinedSessionStats, lastStats)
                combinedImportedFiles.append(contentsOf: outcome.result.importedFiles)
                combinedBytes += lastStats.totalBytes

                appState.totalStatsReport = StatsReport.combine(appState.totalStatsReport, lastStats)
                appState.log("Total stats updated: \(appState.totalStatsReport?.totalFilesAnalyzed ?? 0) files total")

                let historyEntry = ImportHistoryEntry(
                    sourceName: outcome.source.name,
                    destinationPath: outcome.result.destinationPath,
                    fileCount: outcome.result.importedFiles.count,
                    totalBytes: lastStats.totalBytes
                )
                ImportHistoryStorage.add(historyEntry)
                appState.importHistory = ImportHistoryStorage.load()
                appState.mergeImportedStatsIntoEventCache(lastStats, destinationPath: outcome.result.destinationPath)
                appState.recordTelegramDailyImport(
                    sourceName: outcome.source.name,
                    destinationPath: outcome.result.destinationPath,
                    fileCount: outcome.result.importedFiles.count,
                    totalBytes: lastStats.totalBytes,
                    duration: outcome.result.duration,
                    report: lastStats
                )
            }

            if let combinedSessionStats {
                appState.statsReport = combinedSessionStats
            }

            let duration = Date().timeIntervalSince(startedAt)
            let averageSpeed = duration > 0 ? Double(combinedBytes) / duration : 0
            appState.lastImportReport = ImportReport(
                sourceVolumeName: sources.map(\.name).joined(separator: " + "),
                sourcePath: sources.map { $0.path.path }.joined(separator: "\n"),
                destinationPath: dest.path,
                fileCount: combinedImportedFiles.count,
                totalBytes: combinedBytes,
                duration: duration,
                averageSpeed: averageSpeed,
                importedFiles: combinedImportedFiles
            )
            appState.log("Parallel import complete: \(combinedImportedFiles.count) files from \(sources.count) cards")
            Task { await attemptTelegramDailySummarySend() }

            try? await Task.sleep(for: .seconds(1))
            showProgressOverlay = false
            selectedNavItem = .statistics
            appState.importJobs = []

            try? await Task.sleep(for: .seconds(1))
            appState.importState = .idle
        }
    }

    private func runMultiImportJob(
        source: VolumeInfo,
        dest: URL,
        mode: ImportEngine.Mode,
        renameOnImport: Bool,
        renameTemplate: String,
        eventName: String,
        importDate: Date,
        supportedExtensions: Set<String>,
        engine: ImportEngine,
        reservationCoordinator: DestinationReservationCoordinator
    ) async -> MultiImportOutcome {
        do {
            let sourceAccessing = source.path.startAccessingSecurityScopedResource()
            defer { if sourceAccessing { source.path.stopAccessingSecurityScopedResource() } }

            let files = VolumeWatcher.listRawFiles(at: source.path, extensions: supportedExtensions)
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

            guard !files.isEmpty else {
                await MainActor.run {
                    updateMultiImportJob(sourceID: source.id, state: .done, progress: ImportProgress(totalFiles: 0, completedFiles: 0, currentFileName: "No RAW files", startTime: Date()))
                    appState.log("No RAW files found on \(source.name)", level: .warning)
                }
                return MultiImportOutcome(source: source, result: .empty, errorMessage: nil)
            }

            await MainActor.run {
                updateMultiImportJob(sourceID: source.id, state: .importing, progress: ImportProgress(totalFiles: files.count, startTime: Date()))
                appState.importState = .importing
                appState.log("\(source.name): found \(files.count) RAW files to import")
            }

            let destAccessing = BookmarkManager.startAccessing(dest)
            defer { if destAccessing { BookmarkManager.stopAccessing(dest) } }

            let captureDates = renameOnImport && RenameTemplateRenderer.usesDateTokens(renameTemplate)
                ? await RenameCaptureDateReader.captureDates(for: files)
                : [:]
            let renameOptions = renameOnImport
                ? ImportRenameOptions(
                    template: renameTemplate,
                    eventName: eventName,
                    importDate: importDate,
                    totalCount: files.count,
                    captureDatesByPath: captureDates
                )
                : nil

            let result = try await engine.importFiles(
                from: files,
                to: dest,
                mode: mode,
                renameOptions: renameOptions,
                reservationCoordinator: reservationCoordinator
            ) { progress in
                Task { @MainActor in
                    var jobProgress = ImportProgress(
                        totalFiles: progress.totalFiles,
                        completedFiles: progress.completedFiles,
                        totalBytes: progress.totalBytes,
                        transferredBytes: progress.transferredBytes,
                        currentFileName: progress.currentFileName,
                        startTime: Date(),
                        bytesPerSecond: progress.bytesPerSecond,
                        skippedFiles: progress.skippedFiles,
                        statusMessage: progress.statusMessage
                    )
                    if let existing = appState.importJobs.first(where: { $0.id == source.id })?.progress.startTime {
                        jobProgress.startTime = existing
                    }
                    updateMultiImportJob(sourceID: source.id, state: .importing, progress: jobProgress)
                }
            }

            await MainActor.run {
                updateMultiImportJob(sourceID: source.id, state: .done, progress: completedProgress(for: source.id, result: result))
                appState.log("\(source.name): import complete (\(result.importedFiles.count) files, \(result.skippedFiles) skipped)")
            }

            if !result.importedFiles.isEmpty, appState.autoEject {
                await MainActor.run {
                    updateMultiImportJobState(sourceID: source.id, state: .ejecting)
                    appState.log("\(source.name): ejecting card...")
                }
                await Task.detached { sync() }.value
                try? await Task.sleep(for: .seconds(3))
                let ejected = await VolumeEjector.eject(volumeURL: source.path)
                await MainActor.run {
                    updateMultiImportJobState(sourceID: source.id, state: .ejectingDone)
                    appState.log(ejected ? "\(source.name): ejecting card... Done" : "⚠ Failed to eject \(source.name). You may need to eject manually.", level: ejected ? .info : .warning)
                }
            }

            return MultiImportOutcome(source: source, result: result, errorMessage: nil)
        } catch ImportError.cancelled {
            await MainActor.run {
                updateMultiImportJobState(sourceID: source.id, state: .idle)
                appState.log("\(source.name): import cancelled", level: .warning)
            }
            return MultiImportOutcome(source: source, result: .empty, errorMessage: nil)
        } catch {
            await MainActor.run {
                var progress = appState.importJobs.first(where: { $0.id == source.id })?.progress ?? ImportProgress()
                progress.failureMessage = error.localizedDescription
                progress.statusMessage = "Import failed: \(error.localizedDescription)"
                updateMultiImportJob(sourceID: source.id, state: .error(error.localizedDescription), progress: progress)
                appState.log("\(source.name): import failed: \(error.localizedDescription)", level: .error)
            }
            return MultiImportOutcome(source: source, result: .empty, errorMessage: error.localizedDescription)
        }
    }

    @MainActor
    private func updateMultiImportJob(sourceID: String, state: ImportState, progress: ImportProgress) {
        guard let index = appState.importJobs.firstIndex(where: { $0.id == sourceID }) else { return }
        appState.importJobs[index].state = state
        appState.importJobs[index].progress = progress
        updateAggregateImportProgress()
    }

    @MainActor
    private func updateMultiImportJobState(sourceID: String, state: ImportState) {
        guard let index = appState.importJobs.firstIndex(where: { $0.id == sourceID }) else { return }
        appState.importJobs[index].state = state
        updateAggregateImportProgress()
    }

    @MainActor
    private func completedProgress(for sourceID: String, result: ImportResult) -> ImportProgress {
        var progress = appState.importJobs.first(where: { $0.id == sourceID })?.progress ?? ImportProgress()
        progress.completedFiles = result.fileCount
        progress.totalFiles = max(progress.totalFiles, result.fileCount)
        progress.transferredBytes = result.totalBytes
        progress.totalBytes = max(progress.totalBytes, result.totalBytes)
        progress.bytesPerSecond = result.averageSpeed
        progress.currentFileName = result.importedFiles.isEmpty ? "No new files" : "Done"
        progress.skippedFiles = result.skippedFiles
        if result.skippedFiles > 0 {
            progress.statusMessage = "Skipped \(result.skippedFiles) duplicate file\(result.skippedFiles == 1 ? "" : "s")"
        }
        return progress
    }

    @MainActor
    private func updateAggregateImportProgress() {
        guard !appState.importJobs.isEmpty else { return }
        let jobs = appState.importJobs
        let startTime = appState.importProgress.startTime ?? jobs.compactMap { $0.progress.startTime }.min()
        let totalFiles = jobs.reduce(0) { $0 + $1.progress.totalFiles }
        let completedFiles = jobs.reduce(0) { $0 + $1.progress.completedFiles }
        let totalBytes = jobs.reduce(Int64(0)) { $0 + $1.progress.totalBytes }
        let transferredBytes = jobs.reduce(Int64(0)) { $0 + $1.progress.transferredBytes }
        let speed = jobs.reduce(0.0) { $0 + $1.progress.bytesPerSecond }
        let skipped = jobs.reduce(0) { $0 + $1.progress.skippedFiles }
        let activeNames = jobs
            .filter { if case .importing = $0.state { return true }; return false }
            .map(\.sourceName)
        appState.importProgress = ImportProgress(
            totalFiles: totalFiles,
            completedFiles: completedFiles,
            totalBytes: totalBytes,
            transferredBytes: transferredBytes,
            currentFileName: activeNames.isEmpty ? "Parallel import" : activeNames.joined(separator: " + "),
            startTime: startTime,
            bytesPerSecond: speed,
            skippedFiles: skipped,
            statusMessage: skipped > 0 ? "Skipped \(skipped) duplicate file\(skipped == 1 ? "" : "s")" : nil,
            failureMessage: appState.importProgress.failureMessage
        )
    }

    private func pauseImport() {
        Task {
            if activeImportEngines.isEmpty {
                await importEngine.pause()
            } else {
                for engine in activeImportEngines.values {
                    await engine.pause()
                }
            }
            appState.importState = .paused
            appState.log("Import paused")
        }
    }

    private func resumeImport() {
        Task {
            if activeImportEngines.isEmpty {
                await importEngine.resume()
            } else {
                for engine in activeImportEngines.values {
                    await engine.resume()
                }
            }
            appState.importState = .importing
            appState.log("Import resumed")
        }
    }

    private func cancelImport() {
        Task {
            if activeImportEngines.isEmpty {
                await importEngine.cancel()
            } else {
                for engine in activeImportEngines.values {
                    await engine.cancel()
                }
            }
            activeImportEngines.removeAll()
            appState.importJobs = []
            appState.log("Import cancel requested")
        }
    }
}

private struct MultiImportOutcome: Sendable {
    let source: VolumeInfo
    let result: ImportResult
    let errorMessage: String?
}
