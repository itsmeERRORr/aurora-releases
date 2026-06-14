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
    @State private var isEditingEventName = false
    @State private var eventNameDraft = ""
    @State private var isRepositioningBanner = false
    @State private var bannerOffsetDraft = EventBannerOffset()
    @State private var bannerDragStartOffset: EventBannerOffset?
    @State private var shareErrorMessage: String?
    @FocusState private var eventNameFieldFocused: Bool

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
            if !hasLoaded { loadFromCache() }
        }
        .onChange(of: destinationPath) { _, _ in
            hasLoaded = false
            report = nil
            errorMessage = nil
            shareErrorMessage = nil
            scanDate = nil
            isCachedData = false
            isEditingEventName = false
            eventNameDraft = ""
            isRepositioningBanner = false
            bannerOffsetDraft = EventBannerOffset()
            bannerDragStartOffset = nil
            loadFromCache()
        }
        .alert("Could not export share image", isPresented: shareErrorBinding) {
            Button("OK", role: .cancel) { shareErrorMessage = nil }
        } message: {
            Text(shareErrorMessage ?? "Unknown error")
        }
    }

    // MARK: - Header

    private var diskIsReachable: Bool {
        guard !destinationPath.isEmpty else { return false }
        return (try? URL(fileURLWithPath: destinationPath).checkResourceIsReachable()) == true
    }

    private var eventBannerCard: some View {
        bannerCardBackground
            .frame(maxWidth: .infinity)
            .frame(height: 400)
            .clipped()
            // Header (gradient + title + controls) overlaid at the top
            .overlay(alignment: .top) {
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
                        .frame(maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(false)
                    )
            }
            // Photos-imported caption overlaid at the bottom
            .overlay(alignment: .bottomLeading) {
                if let summary = importSummary {
                    Text("\(AuroraFormat.count(summary.photoCount)) photos imported")
                        .font(.manrope(12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: Color.black.opacity(0.6), radius: 6, x: 0, y: 2)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
    }

    @ViewBuilder
    private var bannerCardBackground: some View {
        if let path = eventBannerImagePath, let img = NSImage(contentsOfFile: path) {
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
            EventThumbnail(
                eventName: currentEventName,
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
                .shadow(color: Color.black.opacity(0.55), radius: 6, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                editableEventTitle
                if let date = scanDate {
                    Text("Last scan: \(date.formatted(date: .abbreviated, time: .omitted))")
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
        let topLenses = activeReport?.allLenses.prefix(3).map { lens in
            EventSocialRankItem(
                name: LensDisplayFormatter.displayName(make: lens.make, model: lens.model),
                subtitle: LensDisplayFormatter.brandName(make: lens.make, model: lens.model),
                count: AuroraFormat.count(lens.count)
            )
        } ?? []
        let topCameras = activeReport?.allCameras.prefix(3).map { camera in
            EventSocialRankItem(
                name: friendlyCameraName(for: camera.model),
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
            topLenses: topLenses,
            topCameras: topCameras
        )
    }

    @ViewBuilder
    private var editableEventTitle: some View {
        if isEditingEventName, bookmarkIndex != nil {
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
        } else {
            Text(currentEventName)
                .font(.sora(21, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .shadow(color: Color.black.opacity(0.6), radius: 8, x: 0, y: 2)
                .contentShape(Rectangle())
                .onTapGesture(perform: beginEventNameEdit)
                .help(bookmarkIndex == nil ? "" : "Click to rename event")
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
        }
    }

    @ViewBuilder
    private func photoStatsCard(for report: StatsReport) -> some View {
        let isLimitedData = report.rawOutput.contains("mdls fallback") && report.totalFilesAnalyzed > 0
        let isShowingCachedStatsWithoutCurrentRAWs = diskIsReachable && knownRawFileCount == 0 && report.totalFilesAnalyzed > 0
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Photo Stats")

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
        .auroraStaticCard()
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
    private func loadFromCache() {
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

    private func cachedStatsForCurrentEvent() -> (report: StatsReport, scanDate: Date, rawFileCountAtScan: Int?)? {
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
                EventStatsCache.save(r, forPath: destinationPath, scanDate: now, rawFileCountAtScan: r.totalFilesAnalyzed)
                if let bookmarkIndex {
                    appState.updateEventFolderCache(at: bookmarkIndex, count: r.totalFilesAnalyzed, path: destinationPath)
                    appState.setEventFolderPeakIfHigher(at: bookmarkIndex, count: r.totalFilesAnalyzed)
                }
                appState.log("Event stats scanned & cached: \(eventName) — \(r.totalFilesAnalyzed) photos")
            } else {
                let fileCount = VolumeWatcher.listRawFiles(at: url, extensions: appState.supportedExtensions).count
                if fileCount == 0 {
                    if let bookmarkIndex {
                        appState.updateEventFolderCache(at: bookmarkIndex, count: 0, path: destinationPath)
                    }
                    if let cached = cachedStatsForCurrentEvent() {
                        report = cached.report
                        scanDate = cached.scanDate
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
