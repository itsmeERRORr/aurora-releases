import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var appState: AppState

    @State private var volumeWatcher: VolumeWatcher?
    @State private var importEngine = ImportEngine()
    @State private var statsRunner: StatsRunner?
    @State private var showProgressOverlay = false
    @State private var selectedNavItem: NavigationItem = .statistics
    @State private var showAutoImportOverlay = false
    @State private var autoImportCountdown = 5
    @State private var autoImportTask: Task<Void, Never>?
    @State private var eventCountsRefreshTask: Task<Void, Never>?

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
                            Color.black.opacity(0.35).ignoresSafeArea()
                            ProgressOverlayView(
                                appState: appState,
                                onPause: pauseImport,
                                onResume: resumeImport,
                                onCancel: cancelImport
                            )
                        }
                        if showAutoImportOverlay {
                            Color.black.opacity(0.35).ignoresSafeArea()
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
        .onDisappear { stopEventCountsRefreshTimer() }
        .onReceive(NotificationCenter.default.publisher(for: .cardDetected)) { _ in
            selectedNavItem = .dashboard
        }
        .onReceive(NotificationCenter.default.publisher(for: .startAutoImport)) { _ in
            startAutoImportCountdown()
        }
        .onChange(of: appState.autoImport) { _, isEnabled in
            if !isEnabled { cancelAutoImportCountdown() }
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
        appState.log("App started — João's Photos v1.0")
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
        .auroraStaticCard(radius: AuroraRadius.large)
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
        guard let source = appState.activeVolume else {
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
        guard let watcher = volumeWatcher else { return }

        appState.importState = .scanning
        showProgressOverlay = true
        appState.log("Starting import from \(source.name) to \(dest.path)")

        Task {
            let sourceAccessing = source.path.startAccessingSecurityScopedResource()
            defer { if sourceAccessing { source.path.stopAccessingSecurityScopedResource() } }

            let files = watcher.listRawFiles(at: source.path)
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
                let result = try await importEngine.importFiles(
                    from: files, to: dest, mode: engineMode
                ) { progress in
                    Task { @MainActor in
                        appState.importProgress.completedFiles = progress.completedFiles
                        appState.importProgress.totalFiles = progress.totalFiles
                        appState.importProgress.transferredBytes = progress.transferredBytes
                        appState.importProgress.totalBytes = progress.totalBytes
                        appState.importProgress.currentFileName = progress.currentFileName
                        appState.importProgress.bytesPerSecond = progress.bytesPerSecond
                    }
                }

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
                appState.importState = .error(error.localizedDescription)
                appState.log("Import failed: \(error.localizedDescription)", level: .error)
                try? await Task.sleep(for: .seconds(3))
                showProgressOverlay = false
                appState.importState = .idle
            }
        }
    }

    private func pauseImport() {
        Task {
            await importEngine.pause()
            appState.importState = .paused
            appState.log("Import paused")
        }
    }

    private func resumeImport() {
        Task {
            await importEngine.resume()
            appState.importState = .importing
            appState.log("Import resumed")
        }
    }

    private func cancelImport() {
        Task {
            await importEngine.cancel()
            appState.log("Import cancel requested")
        }
    }
}
