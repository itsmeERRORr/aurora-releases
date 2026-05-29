import SwiftUI

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

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            SidebarView(selectedItem: $selectedNavItem, appState: appState)

            // Main content area
            VStack(spacing: 0) {
                // Main content
                ZStack {
                    switch selectedNavItem {
                    case .dashboard:
                        DashboardView(
                            appState: appState,
                            volumeWatcher: volumeWatcher,
                            statsRunner: statsRunner,
                            onImportNow: startImport,
                            onPause: pauseImport,
                            onResume: resumeImport,
                            onCancel: cancelImport
                        )

                    case .statistics:
                        StatisticsView(appState: appState, statsRunner: statsRunner)

                    case .logs:
                        LogsView(appState: appState)

                    case .event(let index):
                        EventStatsView(
                            appState: appState,
                            destinationPath: index < appState.uniqueImportDestinations.count
                                ? appState.uniqueImportDestinations[index].path
                                : "",
                            eventName: index < appState.uniqueImportDestinations.count
                                ? appState.uniqueImportDestinations[index].name
                                : "",
                            statsRunner: statsRunner
                        )
                    }

                    // Progress overlay
                    if showProgressOverlay {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()

                        ProgressOverlayView(
                            appState: appState,
                            onPause: pauseImport,
                            onResume: resumeImport,
                            onCancel: cancelImport
                        )
                    }

                    if showAutoImportOverlay {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()

                        autoImportOverlay
                    }
                }

                // Status bar at bottom
                StatusBarView(appState: appState)
            }
        }
        .onAppear {
            setupServices()
        }
        .onReceive(NotificationCenter.default.publisher(for: .startAutoImport)) { _ in
            startAutoImportCountdown()
        }
        .onChange(of: appState.autoImport) { _, isEnabled in
            if !isEnabled {
                cancelAutoImportCountdown()
            }
        }
        .background(
            LinearGradient(
                colors: [Color(hex: "061A2E"), Color(hex: "080815"), Color(hex: "030712")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .ignoresSafeArea()
        #if os(macOS)
        .background(TransparentTitleBar())
        #endif
    }

    // MARK: - Setup

    private func setupServices() {
        let watcher = VolumeWatcher(appState: appState)
        volumeWatcher = watcher
        statsRunner = StatsRunner(appState: appState)
        watcher.startWatching()
        appState.log("App started — João's Photos v1.0")
    }

    private var autoImportOverlay: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentGreen)
                Text("Auto-Importing in \(autoImportCountdown)")
                    .font(.title2.bold())
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            Divider()

            HStack {
                Button("Import Now") {
                    cancelAutoImportCountdown()
                    startImport()
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Stop Auto-Import") {
                    cancelAutoImportCountdown()
                    appState.autoImport = false
                }
                .buttonStyle(PrimaryButtonStyle(isDestructive: true))
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.glassStrong)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.glassBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
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
                await MainActor.run {
                    autoImportCountdown -= 1
                }
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

    // MARK: - Import Actions

    private func startImport() {
        guard let source = appState.activeVolume else {
            appState.log("Cannot import: no active volume", level: .warning)
            return
        }
        guard let dest = appState.destinationURL else {
            appState.log("Cannot import: no destination selected", level: .warning)
            return
        }
        guard let watcher = volumeWatcher else { return }

        appState.importState = .scanning
        showProgressOverlay = true
        appState.log("Starting import from \(source.name) to \(dest.path)")

        Task {
            // Request access to source volume ONCE at the beginning
            let sourceAccessing = source.path.startAccessingSecurityScopedResource()
            defer { if sourceAccessing { source.path.stopAccessingSecurityScopedResource() } }

            // Scan files
            let files = watcher.listRawFiles(at: source.path)

            guard !files.isEmpty else {
                appState.importState = .idle
                showProgressOverlay = false
                appState.log("No RAW files found on \(source.name)", level: .warning)
                return
            }

            appState.log("Found \(files.count) RAW files to import")
            appState.importState = .importing
            appState.importProgress = ImportProgress(
                totalFiles: files.count,
                startTime: Date()
            )

            // Access destination with bookmark
            let destAccessing = BookmarkManager.startAccessing(dest)
            defer { if destAccessing { BookmarkManager.stopAccessing(dest) } }

            do {
                let engineMode: ImportEngine.Mode = appState.importMode == .copy ? .copy : .move
                let result = try await importEngine.importFiles(
                    from: files,
                    to: dest,
                    mode: engineMode
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

                // Import complete
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

                // Auto-eject immediately (before stats), so the user can remove the card sooner
                if appState.autoEject {
                    appState.importState = .ejecting
                    appState.log("Ejecting card...")

                    // Force filesystem sync to flush all buffers
                    await Task.detached {
                        sync()
                    }.value

                    // Extra delay to ensure all file handles are closed
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

                // Run stats (after eject; stats use destination files, not the card)
                appState.importState = .generatingStats
                appState.log("Generating stats...")
                await statsRunner?.runStats(
                    importedFiles: result.importedFiles,
                    destinationPath: result.destinationPath,
                    duration: result.duration
                )

                // Accumulate total stats
                if let lastStats = appState.statsReport {
                    appState.totalStatsReport = StatsReport.combine(appState.totalStatsReport, lastStats)
                    appState.log("Total stats updated: \(appState.totalStatsReport?.totalFilesAnalyzed ?? 0) files total")
                }

                // Add to import history
                if let lastStats = appState.statsReport {
                    let historyEntry = ImportHistoryEntry(
                        sourceName: source.name,
                        destinationPath: result.destinationPath,
                        fileCount: result.importedFiles.count,
                        totalBytes: lastStats.totalBytes
                    )
                    ImportHistoryStorage.add(historyEntry)
                    appState.importHistory = ImportHistoryStorage.load()
                }

                // Dismiss progress overlay after stats are done
                try? await Task.sleep(for: .seconds(1))
                showProgressOverlay = false

                selectedNavItem = .statistics

                // Reset state
                try? await Task.sleep(for: .seconds(1))
                if appState.importState == .done || appState.importState == .ejecting || appState.importState == .ejectingDone || appState.importState == .generatingStats {
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
