import SwiftUI

struct DashboardView: View {
    @Bindable var appState: AppState
    let volumeWatcher: VolumeWatcher?
    let statsRunner: StatsRunner?
    let onImportNow: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void

    @State private var sourceFiles: [URL] = []
    @State private var destFiles: [URL] = []
    @State private var showFolderPicker = false
    @State private var showAdvancedMode = false
    @State private var trendPeriod: TrendPeriod = .week
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    // New Event sheet state
    @State private var showNewEventSheet = false
    @State private var newEventName = ""
    @State private var newEventURL: URL? = nil

    var body: some View {
        Group {
            if showAdvancedMode {
                AdvancedView(
                    appState: appState,
                    onClose: {
                        showAdvancedMode = false
                    }
                )
            } else {
                dashboardContent
            }
        }
    }

    private var dashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dashboardHeader

                HStack(spacing: 16) {
                    totalLibraryCard
                        .frame(maxWidth: .infinity)
                    importStatusCard
                        .frame(maxWidth: .infinity)
                }

                recentEventsSection

                if !trendData.isEmpty {
                    importTrendSection
                }
            }
            .padding(.top, 28)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .onAppear {
            refreshSourceFiles()
            refreshDestFiles()
        }
        .onChange(of: appState.activeVolume) { _, _ in
            refreshSourceFiles()
        }
        .onChange(of: appState.destinationURL) { _, _ in
            refreshDestFiles()
        }
        .onChange(of: appState.importState) { _, newState in
            if newState == .done {
                refreshDestFiles()
            }
        }
        .sheet(isPresented: $showNewEventSheet) {
            newEventSheet
        }
    }

    private var dashboardHeader: some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.importPurple)
                    .frame(width: 34, height: 34)
                    .background(Color.importPurple.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
                Text("Dashboard")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
            }

            Spacer()

            Button {
                showNewEventSheet = true
            } label: {
                Label("Add folder", systemImage: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .background(
                LinearGradient(colors: [Color.importBlue, Color.importPink], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
    }

    private var totalLibraryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Total Library")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)

            Text(totalPhotos.formatted())
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            Text("photos across \(max(appState.uniqueImportDestinations.count, 1)) events · \(formatBytes(totalBytes)) stored")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)

            HStack(spacing: 32) {
                libraryMiniMetric(value: "\(totalImports)", label: "Imports")
                libraryMiniMetric(value: formatSpeed(avgSpeed), label: "Avg speed")
                libraryMiniMetric(value: "\(totalRawFiles.formatted())", label: "RAW files")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Color.importCardTop.opacity(0.92), Color.importCard.opacity(0.96), Color.importBlue.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.importBlue.opacity(0.45), lineWidth: 1))
    }

    private func libraryMiniMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
        }
    }

    private var importStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Circle()
                    .fill(appState.activeVolume == nil ? Color.importCyan : Color.accentGreen)
                    .frame(width: 9, height: 9)
                    .shadow(color: (appState.activeVolume == nil ? Color.importCyan : Color.accentGreen).opacity(0.6), radius: 8)
                Text(appState.activeVolume == nil ? "Waiting for card..." : "Card detected")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            Text(appState.activeVolume == nil ? "Insert an SD or CFexpress card to begin importing automatically." : "\(appState.activeVolume?.rawFileCount ?? 0) RAW files ready to import.")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)

            Button {
                if appState.activeVolume == nil {
                    volumeWatcher?.selectManualSource()
                } else {
                    onImportNow()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: appState.activeVolume == nil ? "tray.and.arrow.down" : "bolt.fill")
                    Text(appState.activeVolume == nil ? "Drag photos here or browse" : "Import now")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.importBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [Color.importCardTop.opacity(0.75), Color.importCard.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.importBorder, lineWidth: 1))
    }

    private var recentEventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT EVENTS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(4)
                .foregroundColor(.textSecondary)

            let events = Array(dashboardEvents.prefix(4))
            if events.isEmpty {
                Text("Add folders to build your event library.")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .dashboardPanel()
            } else {
                HStack(spacing: 14) {
                    ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                        dashboardEventCard(event: event, index: index)
                    }
                }
            }
        }
    }

    private func dashboardEventCard(event: (name: String, count: Int), index: Int) -> some View {
        ZStack(alignment: .bottomLeading) {
            dashboardGradient(index: index)
            LinearGradient(colors: [.clear, .black.opacity(0.68)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Text("\(max(event.count, 0).formatted()) RAW")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(dashboardBorderColor(index: index), lineWidth: 1))
    }

    private var dashboardEvents: [(name: String, count: Int)] {
        appState.uniqueImportDestinations.enumerated().map { index, destination in
            let count: Int
            if index < appState.eventFolderCachedCounts.count, appState.eventFolderCachedCounts[index] >= 0 {
                count = appState.eventFolderCachedCounts[index]
            } else if let summary = appState.importStats(forEventPath: destination.path) {
                count = summary.photoCount
            } else {
                count = 0
            }
            return (name: destination.name, count: count)
        }
    }

    private var totalPhotos: Int {
        appState.totalStatsReport?.totalFilesAnalyzed ?? appState.importHistory.reduce(0) { $0 + $1.fileCount }
    }

    private var totalBytes: Int64 {
        let reportBytes = appState.totalStatsReport?.totalBytes ?? 0
        return reportBytes > 0 ? reportBytes : appState.importHistory.reduce(Int64(0)) { $0 + $1.totalBytes }
    }

    private var totalImports: Int {
        appState.totalStatsReport?.importCount ?? appState.importHistory.count
    }

    private var totalRawFiles: Int {
        let cached = appState.eventFolderCachedCounts.filter { $0 > 0 }.reduce(0, +)
        return cached > 0 ? cached : totalPhotos
    }

    private var avgSpeed: Double {
        appState.totalStatsReport?.averageSpeed ?? 0
    }

    private func dashboardGradient(index: Int) -> LinearGradient {
        let palettes: [[Color]] = [
            [Color(hex: "F43F5E"), Color(hex: "581C87")],
            [Color(hex: "F59E0B"), Color(hex: "7C2D12")],
            [Color(hex: "10B981"), Color(hex: "064E3B")],
            [Color(hex: "3B82F6"), Color(hex: "1E1B4B")]
        ]
        return LinearGradient(colors: palettes[index % palettes.count], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func dashboardBorderColor(index: Int) -> Color {
        [Color.importPink, Color.importAmber, Color.accentGreen, Color.importBlue][index % 4].opacity(0.75)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let tb = Double(bytes) / (1024.0 * 1024.0 * 1024.0 * 1024.0)
        if tb >= 1 { return String(format: "%.2f TB", tb) }
        let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        let mb = Double(bytes) / (1024.0 * 1024.0)
        return String(format: "%.0f MB", mb)
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "N/A" }
        let mbps = bytesPerSecond / (1024 * 1024)
        if mbps >= 1 { return String(format: "%.1f MB/s", mbps) }
        return String(format: "%.0f KB/s", bytesPerSecond / 1024)
    }

    // MARK: - New Event Sheet

    private var newEventSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(Color.primaryPurple)
                    .font(.title2)
                Text("New Event")
                    .font(.title2.bold())
                    .foregroundColor(.textPrimary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Event Name")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.textSecondary)
                TextField("e.g. Wedding 2024", text: $newEventName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Event Folder")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.textSecondary)
                Button {
                    chooseNewEventFolder()
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text(newEventURL?.lastPathComponent ?? "Choose Folder…")
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.primaryPurple)
                if let url = newEventURL {
                    Text(url.path)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    showNewEventSheet = false
                    newEventName = ""
                    newEventURL = nil
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button("Create Event") {
                    createNewEvent()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(newEventURL == nil)
            }
        }
        .padding(24)
        .frame(width: 400, height: 320)
        .background(
            LinearGradient(
                colors: [Color.bgDarkGradientTopLeading, Color.bgDarkGradientBottomTrailing],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func chooseNewEventFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the main folder for this event"
        panel.prompt = "Select Folder"
        if panel.runModal() == .OK, let url = panel.url {
            newEventURL = url
            if newEventName.isEmpty {
                newEventName = url.lastPathComponent
            }
        }
    }

    private func createNewEvent() {
        guard let url = newEventURL,
              let bookmark = BookmarkManager.saveBookmark(for: url) else { return }

        appState.addEventFolder(bookmark: bookmark)
        let newIndex = appState.eventFolderBookmarks.count - 1

        let name = newEventName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            appState.setEventFolderDisplayName(at: newIndex, name: name)
        }

        // Dismiss sheet
        showNewEventSheet = false
        newEventName = ""
        newEventURL = nil

        // Auto-scan the event folder in the background.
        // Only set the scanning indicator if we actually have a runner to scan with.
        if let runner = statsRunner {
            appState.eventFolderScanningIndices.insert(newIndex)
            Task {
                let report = await runner.runStatsForEventFolder(at: url)
                await MainActor.run {
                    if let report = report {
                        EventStatsCache.save(report, forPath: url.path)
                        appState.updateEventFolderCache(at: newIndex, count: report.totalFilesAnalyzed, path: url.path)
                    }
                    appState.eventFolderScanningIndices.remove(newIndex)
                }
            }
        }
    }

    private func refreshSourceFiles() {
        guard let vol = appState.activeVolume, let watcher = volumeWatcher else {
            sourceFiles = []
            return
        }
        Task {
            let files = watcher.listRawFiles(at: vol.path)
            sourceFiles = files
            await MainActor.run {
                appState.updateSourceFiles(files)
            }
        }
    }

    private func refreshDestFiles() {
        guard let dest = appState.destinationURL else {
            destFiles = []
            return
        }

        Task {
            let accessing = BookmarkManager.startAccessing(dest)
            defer { if accessing { BookmarkManager.stopAccessing(dest) } }

            let fm = FileManager.default
            if let contents = try? fm.contentsOfDirectory(
                at: dest,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                destFiles = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
            } else {
                destFiles = []
            }
        }
    }

    private enum TrendPeriod: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
    }

    private var trendData: [(label: String, count: Int)] {
        switch trendPeriod {
        case .week:
            return appState.photosByWeek
        case .month:
            return appState.photosByMonthChart
        case .year:
            return appState.photosByYear(selectedYear)
        }
    }

    private var importTrendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Import Activity")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()

                // Year picker — shown inline when in Year mode
                if trendPeriod == .year {
                    Picker("", selection: $selectedYear) {
                        ForEach(appState.availableYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }

                Picker("", selection: $trendPeriod) {
                    ForEach(TrendPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            if trendData.isEmpty {
                Text("No import data yet")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                LineChartView(data: trendData)
                    .frame(height: 160)
            }
        }
        .padding(16)
        .glassPanel()
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the destination folder for imported photos"
        panel.prompt = "Select Destination"

        if panel.runModal() == .OK, let url = panel.url {
            if let bookmarkData = BookmarkManager.saveBookmark(for: url) {
                appState.destinationBookmarkData = bookmarkData
            }
            appState.destinationURL = url
            appState.log("Destination set: \(url.path)")
        }
    }
}
