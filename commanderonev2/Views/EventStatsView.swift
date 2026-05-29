import SwiftUI

struct EventStatsView: View {
    @Bindable var appState: AppState
    let destinationPath: String
    let eventName: String
    let statsRunner: StatsRunner?

    @State private var report: StatsReport?
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var showAllLenses = false
    @State private var showAllCameras = false
    @State private var scanDate: Date? = nil      // when the last successful scan happened
    @State private var isCachedData = false       // true = currently showing cached (not fresh) data

    // Import history summary — available instantly, no scan needed
    // Falls back to cached report data if folder has been moved and history can't be matched
    private var importSummary: (photoCount: Int, totalBytes: Int64, sessionCount: Int, firstDate: Date?, lastDate: Date?)? {
        if let summary = appState.importStats(forEventPath: destinationPath) {
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

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard

                // Import history card — always visible, no scan needed
                if let summary = importSummary {
                    importHistoryCard(summary: summary)
                }

                // EXIF stats — loaded on first appear.
                // Only show the full-page spinner when there is no cached data yet.
                // If a background re-scan is running while we already have data, the
                // small header spinner is enough — we keep showing the (cached) content.
                if isLoading && report == nil {
                    loadingState
                } else if let err = errorMessage {
                    errorState(message: err)
                } else if let report = report, report.totalFilesAnalyzed > 0 {
                    statsContent(for: report)
                } else if hasLoaded {
                    emptyState
                }
            }
            .padding(.top, 48)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onAppear {
            if !hasLoaded { loadFromCacheThenScan() }
        }
        .onChange(of: destinationPath) { _, _ in
            hasLoaded = false
            report = nil
            errorMessage = nil
            scanDate = nil
            isCachedData = false
            loadFromCacheThenScan()
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(alignment: .center) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.primaryPurple)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(eventName)
                    .font(.title2.bold())
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let date = scanDate {
                    Text("Last scan: \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary.opacity(0.7))
                }
            }
            Spacer()
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(Color.primaryPurple)
            } else if diskIsReachable {
                // Disk online — show Refresh (if cached) or Scan (if never scanned)
                Button {
                    loadEventStats()
                } label: {
                    Label(isCachedData ? "Refresh" : "Scan Photos", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.primaryPurple)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var diskIsReachable: Bool {
        guard !destinationPath.isEmpty else { return false }
        return (try? URL(fileURLWithPath: destinationPath).checkResourceIsReachable()) == true
    }

    // MARK: - Import History Card (instant — from ImportHistory, no scan)

    @ViewBuilder
    private func importHistoryCard(summary: (photoCount: Int, totalBytes: Int64, sessionCount: Int, firstDate: Date?, lastDate: Date?)) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import History")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.textPrimary)

            HStack(spacing: 16) {
                StatCard(
                    title: "Photos Imported",
                    value: summary.photoCount.formatted(),
                    icon: "arrow.down.circle.fill",
                    color: Color.accentGreen
                )
                StatCard(
                    title: "Data Transferred",
                    value: formatBytes(summary.totalBytes),
                    icon: "externaldrive.fill",
                    color: Color.blue
                )
                if let first = summary.firstDate {
                    let dateFormatter = DateFormatter()
                    let _ = { dateFormatter.dateStyle = .medium; dateFormatter.timeStyle = .none }()
                    let last = summary.lastDate ?? first
                    StackableStatCard(
                        cards: {
                            var items: [StackableStatCard.CardData] = [
                                .init(title: "Last Import", value: dateFormatter.string(from: last))
                            ]
                            if first != last {
                                items.append(.init(title: "First Import", value: dateFormatter.string(from: first)))
                            }
                            return items
                        }(),
                        icon: "calendar",
                        color: Color.orange
                    )
                }
            }
        }
        .padding(16)
        .glassPanel()
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.primaryPurple)
            Text("Analyzing photos in event folder…")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
            Text("This may take a moment for large folders")
                .font(.caption)
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .glassPanel()
    }

    private func errorState(message: String) -> some View {
        let isDiskOffline = message.lowercased().contains("disconnected") || message.lowercased().contains("not found")
        return VStack(spacing: 12) {
            Image(systemName: isDiskOffline ? "externaldrive.badge.xmark" : "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(isDiskOffline ? Color.textSecondary : Color.orange)
            Text(isDiskOffline ? "Disk not connected" : "Unable to scan folder")
                .font(.title3)
                .foregroundColor(.textPrimary)
            Text(isDiskOffline
                 ? "Photo stats (ISO, aperture, cameras, lenses) require the disk to be connected. Connect the disk and click \"Scan Photos\"."
                 : message)
                .font(.caption)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(16)
        .glassPanel()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("No RAW files found")
                .font(.title3)
                .foregroundColor(.textSecondary)
            Text("No ARW, CR2, CR3 or DNG files found in this folder")
                .font(.caption)
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(16)
        .glassPanel()
    }

    // MARK: - EXIF Stats Content

    @ViewBuilder
    private func statsContent(for report: StatsReport) -> some View {
        VStack(spacing: 16) {
            photoStatsCard(for: report)

            HStack(alignment: .top, spacing: 16) {
                if !report.allCameras.isEmpty {
                    topCamerasSection(cameras: report.allCameras, total: report.totalFilesAnalyzed)
                        .frame(maxWidth: .infinity)
                }
                if !report.allLenses.isEmpty {
                    topLensesSection(report: report)
                        .frame(maxWidth: .infinity)
                }
            }

            if !report.monthCounts.isEmpty {
                monthlyChart(for: report)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func photoStatsCard(for report: StatsReport) -> some View {
        let isLimitedData = report.avgISO == nil && report.avgAperture == nil && report.avgFocalLength == nil && report.totalFilesAnalyzed > 0
        VStack(alignment: .leading, spacing: 16) {
            Text("Photo Stats")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.textPrimary)

            if isLimitedData {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Limited stats — exiftool not installed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textPrimary)
                        Text("Install exiftool for ISO, aperture, focal length and lens data: brew install exiftool")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            HStack(spacing: 16) {
                StatCard(
                    title: "RAW Files",
                    value: "\(report.totalFilesAnalyzed)",
                    icon: "photo.stack",
                    color: Color.primaryPurple
                )
                if let iso = report.avgISO {
                    StackableStatCard(
                        cards: {
                            var items: [StackableStatCard.CardData] = [.init(title: "Avg ISO", value: String(format: "%.0f", iso))]
                            if let max = report.maxISO { items.append(.init(title: "Highest ISO", value: String(format: "%.0f", max))) }
                            if let min = report.minISO { items.append(.init(title: "Lowest ISO", value: String(format: "%.0f", min))) }
                            return items
                        }(),
                        icon: "camera.aperture",
                        color: Color.blue
                    )
                }
                if let aperture = report.avgAperture, aperture > 0 {
                    StackableStatCard(
                        cards: {
                            var items: [StackableStatCard.CardData] = [.init(title: "Avg Aperture", value: String(format: "f/%.1f", aperture))]
                            if let max = report.maxAperture, max > 0 { items.append(.init(title: "Highest Aperture", value: String(format: "f/%.1f", max))) }
                            if let min = report.minAperture, min > 0 { items.append(.init(title: "Lowest Aperture", value: String(format: "f/%.1f", min))) }
                            else { items.append(.init(title: "Lowest Aperture", value: "N/A")) }
                            return items
                        }(),
                        icon: "circle.hexagongrid",
                        color: Color.cyan
                    )
                }
                if let focal = report.avgFocalLength, focal > 0 {
                    StackableStatCard(
                        cards: {
                            var items: [StackableStatCard.CardData] = [.init(title: "Avg Focal", value: String(format: "%.0fmm", focal))]
                            if let max = report.maxFocalLength, max > 0 { items.append(.init(title: "Highest Focal", value: String(format: "%.0fmm", max))) }
                            if let min = report.minFocalLength, min > 0 { items.append(.init(title: "Lowest Focal", value: String(format: "%.0fmm", min))) }
                            else { items.append(.init(title: "Lowest Focal", value: "N/A")) }
                            return items
                        }(),
                        icon: "camera.macro",
                        color: Color.pink
                    )
                }
            }
        }
        .padding(16)
        .glassPanel()
    }

    // MARK: - Top Lenses

    @ViewBuilder
    private func topLensesSection(report: StatsReport) -> some View {
        let podium = Array(report.allLenses.prefix(3))
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Lenses")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                if report.allLenses.count > 3 {
                    Button(showAllLenses ? "Less" : "More") {
                        withAnimation(.easeInOut(duration: 0.2)) { showAllLenses.toggle() }
                    }
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: -20) {
                if podium.count >= 2 { lensCard(lens: podium[1]) }
                if podium.count >= 1 { lensCard(lens: podium[0]) }
                if podium.count >= 3 { lensCard(lens: podium[2]) }
            }
            if showAllLenses {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(report.allLenses) { lens in
                        HStack {
                            Text(lens.fullName)
                                .font(.system(size: 13))
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Text("\(lens.count) photos")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassPanel()
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
    private func topCamerasSection(cameras: [StatsReport.CameraStat], total: Int) -> some View {
        let podium = Array(cameras.prefix(3))
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Cameras")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                if cameras.count > 3 {
                    Button(showAllCameras ? "Less" : "More") {
                        withAnimation(.easeInOut(duration: 0.2)) { showAllCameras.toggle() }
                    }
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: -20) {
                if podium.count >= 2 { cameraCard(camera: podium[1], rank: 2) }
                if podium.count >= 1 { cameraCard(camera: podium[0], rank: 1) }
                if podium.count >= 3 { cameraCard(camera: podium[2], rank: 3) }
            }
            if showAllCameras {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(cameras, id: \.fullName) { cam in
                        HStack {
                            Text(friendlyCameraName(for: cam.model))
                                .font(.system(size: 13))
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Text("\(cam.count) photos")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassPanel()
    }

    private func cameraCard(camera: StatsReport.CameraStat, rank: Int) -> some View {
        VStack(spacing: 8) {
            Text(rank == 1 ? "🥇" : rank == 2 ? "🥈" : "🥉")
                .font(.system(size: 48))
            Text(friendlyCameraName(for: camera.model))
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

    // MARK: - Monthly Chart

    private func monthlyChart(for report: StatsReport) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        let sorted = report.monthCounts
            .compactMap { key, count -> (String, Date, Int)? in
                guard let d = formatter.date(from: key) else { return nil }
                return (key, d, count)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(12)
            .map { (month: $0.0, count: $0.2) }
        return MonthlyChartView(data: Array(sorted))
    }

    // MARK: - Helpers

    private func friendlyCameraName(for model: String) -> String {
        let mappings: [String: String] = [
            "ILCE-7M4": "Sony A7 IV",
            "ILCE-1M2": "Sony A1 II",
            "ILCE-9M3": "Sony A9 III"
        ]
        return mappings[model] ?? model
    }

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
    private func loadFromCacheThenScan() {
        if let cached = EventStatsCache.load(forPath: destinationPath) {
            report = cached.report
            scanDate = cached.scanDate
            isCachedData = true
            hasLoaded = true
            errorMessage = nil
        } else {
            // No cache yet — mark as loaded so we show the correct empty/offline state
            hasLoaded = true
            let url = URL(fileURLWithPath: destinationPath)
            let reachable = !destinationPath.isEmpty && (try? url.checkResourceIsReachable()) == true
            if !reachable {
                errorMessage = "Folder not found — disk may be disconnected"
                appState.log("Event folder unreachable: \(destinationPath)", level: .warning)
            }
            // If reachable but no cache: show emptyState with "Scan Photos" button in header
        }
    }

    /// Fresh exiftool scan — saves result to cache on success.
    @MainActor
    private func loadEventStats() {
        guard !destinationPath.isEmpty else { return }
        let url = URL(fileURLWithPath: destinationPath)
        guard (try? url.checkResourceIsReachable()) == true else { return }

        isLoading = true
        errorMessage = nil

        Task {
            guard let runner = statsRunner else {
                isLoading = false
                return
            }

            let result = await runner.runStatsForEventFolder(at: url)
            isLoading = false
            hasLoaded = true

            if let r = result, r.totalFilesAnalyzed > 0 {
                report = r
                isCachedData = false
                let now = Date()
                scanDate = now
                EventStatsCache.save(r, forPath: destinationPath, scanDate: now)
                appState.log("Event stats scanned & cached: \(eventName) — \(r.totalFilesAnalyzed) photos")
            } else {
                // Scan returned nothing — keep showing cached data if available
                if report == nil {
                    let fileCount = VolumeWatcher.listRawFiles(at: url, extensions: appState.supportedExtensions).count
                    if fileCount > 0 {
                        errorMessage = "Could not analyze files — make sure exiftool is installed (brew install exiftool)"
                    }
                }
            }
        }
    }
}
