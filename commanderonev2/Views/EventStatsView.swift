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

    // Import history summary — available instantly, no scan needed
    // Falls back to cached report data if folder has been moved and history can't be matched
    private var importSummary: (photoCount: Int, totalBytes: Int64, sessionCount: Int, firstDate: Date?, lastDate: Date?)? {
        if let bookmarkIndex, let summary = appState.importStatsForEventFolder(at: bookmarkIndex) {
            return summary
        }
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
                eventBannerCard

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

    private var diskIsReachable: Bool {
        guard !destinationPath.isEmpty else { return false }
        return (try? URL(fileURLWithPath: destinationPath).checkResourceIsReachable()) == true
    }

    private var eventBannerCard: some View {
        VStack(spacing: 0) {
            bannerHeader
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.auroraPanel2)

            ZStack(alignment: .bottomLeading) {
                bannerCardBackground

                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if let summary = importSummary {
                    Text("\(AuroraFormat.count(summary.photoCount)) photos imported")
                        .font(.manrope(12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(18)
                }
            }
            .frame(height: 340)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var bannerCardBackground: some View {
        if let path = eventBannerImagePath, let img = NSImage(contentsOfFile: path) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            EventThumbnail(
                eventName: eventName,
                folderPath: destinationPath,
                cornerRadius: 0
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var bannerHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.auroraViolet)
                .font(.system(size: 18, weight: .bold))

            VStack(alignment: .leading, spacing: 2) {
                Text(eventName)
                    .font(.sora(21, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let date = scanDate {
                    Text("Last scan: \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.manrope(11, weight: .semibold))
                        .foregroundStyle(Color.auroraFaint)
                }
            }

            Spacer(minLength: 12)

            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(Color.auroraTxt)
            } else if diskIsReachable {
                Button {
                    loadEventStats()
                } label: {
                    Label(isCachedData ? "Refresh" : "Scan Photos", systemImage: "arrow.clockwise")
                        .font(.manrope(12, weight: .bold))
                }
                .buttonStyle(AuroraGhostButtonStyle())
            }

            bannerMenu
        }
    }

    @ViewBuilder
    private var bannerMenu: some View {
        if let bookmarkIndex {
            Menu {
                Button("Choose Banner Photo…") {
                    chooseBannerPhoto(for: bookmarkIndex)
                }
                if eventBannerImagePath != nil {
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

    private var eventBannerImagePath: String? {
        guard let bookmarkIndex,
              bookmarkIndex >= 0,
              bookmarkIndex < appState.eventFolderBannerImagePaths.count else { return nil }
        let path = appState.eventFolderBannerImagePaths[bookmarkIndex]
        return path.isEmpty ? nil : path
    }

    // MARK: - Import History Card (instant — from ImportHistory, no scan)

    @ViewBuilder
    private func importHistoryCard(summary: (photoCount: Int, totalBytes: Int64, sessionCount: Int, firstDate: Date?, lastDate: Date?)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Import History")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: AuroraSpacing.gridGap), count: summary.firstDate == nil ? 2 : 3),
                spacing: AuroraSpacing.gridGap
            ) {
                PhotoStatCard(
                    icon: "arrow.down.circle.fill",
                    accent: .auroraHealthy,
                    pages: [(label: "Photos Imported", value: AuroraFormat.count(summary.photoCount))]
                )

                let parts = AuroraFormat.bytesParts(summary.totalBytes)
                PhotoStatCard(
                    icon: "externaldrive.fill",
                    accent: .auroraBlue,
                    pages: [(label: "Data Transferred", value: "\(parts.value) \(parts.unit)")]
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
        .auroraStaticCard()
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundStyle(Color.auroraFaint)
            Text("No RAW files found")
                .font(.manrope(15, weight: .bold))
                .foregroundStyle(Color.auroraMuted)
            Text("No ARW, CR2, CR3 or DNG files found in this folder")
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

            if !report.monthCounts.isEmpty {
                monthlyChart(for: report)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func photoStatsCard(for report: StatsReport) -> some View {
        let isLimitedData = report.avgISO == nil && report.avgAperture == nil && report.avgFocalLength == nil && report.totalFilesAnalyzed > 0
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Photo Stats")

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

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: AuroraSpacing.gridGap), count: 5),
                spacing: AuroraSpacing.gridGap
            ) {
                PhotoStatCard(
                    icon: "photo.stack.fill",
                    accent: .auroraCyan,
                    pages: [(label: "RAW Files", value: AuroraFormat.count(report.totalFilesAnalyzed))]
                )

                PhotoStatCard(icon: "camera.aperture", accent: .auroraBlue, pages: isoPages(for: report))
                PhotoStatCard(icon: "circle.dotted", accent: .auroraViolet, pages: aperturePages(for: report))
                PhotoStatCard(icon: "viewfinder", accent: .auroraMagenta, pages: focalPages(for: report))
                PhotoStatCard(icon: "timer", accent: .auroraPurple, pages: shutterPages(for: report))
            }
        }
        .auroraStaticCard()
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
        return pages
    }

    private func aperturePages(for report: StatsReport) -> [(label: String, value: String)] {
        var pages: [(label: String, value: String)] = [("Avg Aperture", formatOptional(report.avgAperture, AuroraFormat.aperture))]
        if let v = report.maxAperture, v > 0 { pages.append(("Highest Aperture", AuroraFormat.aperture(v))) }
        if let v = report.minAperture, v > 0 { pages.append(("Lowest Aperture", AuroraFormat.aperture(v))) }
        return pages
    }

    private func focalPages(for report: StatsReport) -> [(label: String, value: String)] {
        var pages: [(label: String, value: String)] = [("Avg Focal", formatOptional(report.avgFocalLength, AuroraFormat.focal))]
        if let v = report.maxFocalLength, v > 0 { pages.append(("Highest Focal", AuroraFormat.focal(v))) }
        if let v = report.minFocalLength, v > 0 { pages.append(("Lowest Focal", AuroraFormat.focal(v))) }
        return pages
    }

    private func shutterPages(for report: StatsReport) -> [(label: String, value: String)] {
        var pages: [(label: String, value: String)] = [("Avg Shutter", formatOptional(report.avgShutterSpeed, AuroraFormat.shutter))]
        if let v = report.minShutterSpeed, v > 0 { pages.append(("Fastest Shutter", AuroraFormat.shutter(v))) }
        if let v = report.maxShutterSpeed, v > 0 { pages.append(("Longest Shutter", AuroraFormat.shutter(v))) }
        return pages
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
        .auroraStaticCard()
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
        .auroraStaticCard()
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
        if let cached = cachedStatsForCurrentEvent() {
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

    private func cachedStatsForCurrentEvent() -> (report: StatsReport, scanDate: Date)? {
        if let cached = EventStatsCache.load(forPath: destinationPath) {
            return cached
        }
        guard let bookmarkIndex,
              bookmarkIndex < appState.eventFolderPreviousCachedPaths.count else { return nil }
        let previousPath = appState.eventFolderPreviousCachedPaths[bookmarkIndex]
        guard !previousPath.isEmpty else { return nil }
        return EventStatsCache.load(forPath: previousPath)
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
