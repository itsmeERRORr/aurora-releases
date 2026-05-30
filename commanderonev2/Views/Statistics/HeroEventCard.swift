import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HeroEventCard: View {
    @Bindable var appState: AppState
    var onViewEvent: (Int) -> Void

    var body: some View {
        let info = resolveLatestEvent()

        ZStack {
            cardBannerBackground(info: info)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    leftPanel(info: info)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    rightPanel(info: info)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                }
                .frame(height: 198)
                bottomStrip(info: info)
                    .frame(height: 52)
            }
        }
        .frame(height: 250)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .fill(Color.auroraPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous))
    }

    // MARK: - Left

    private func leftPanel(info: LatestEventInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LATEST EVENT")
                .font(.manrope(9.5, weight: .bold))
                .tracking(1.9)
                .foregroundStyle(Color.auroraCyan)

            HStack(spacing: 8) {
                Text(info.name)
                    .font(.sora(24, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(2)

                if info.isFinalized {
                    Text("Finalizado")
                        .font(.manrope(8.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.auroraFaint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.auroraPanel2))
                }
            }

            if let meta = info.meta {
                Text(meta)
                    .font(.manrope(11.5, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
            }

            Spacer(minLength: 4)

            if info.hasData {
                Button {
                    if let bookmarkIndex = info.bookmarkIndex {
                        onViewEvent(bookmarkIndex)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("View Event")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .buttonStyle(HeroEventActionButtonStyle())
                .disabled(info.bookmarkIndex == nil)
                .padding(.bottom, 10)
            } else {
                Button {
                    // No-op; placeholder for "Connect a card" prompt.
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "externaldrive.badge.plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Connect a card to start")
                    }
                }
                .buttonStyle(AuroraGhostButtonStyle())
                .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, AuroraSpacing.heroPaddingH)
        .padding(.vertical, 14)
    }

    // MARK: - Right

    private func rightPanel(info: LatestEventInfo) -> some View {
        ZStack {
            if info.hasData {
                EmptyView()
            }

            VStack {
                HStack {
                    Spacer()
                    bannerMenu(info: info)
                        .padding(12)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func cardBannerBackground(info: LatestEventInfo) -> some View {
        if let path = info.bannerImagePath, let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .saturation(0.95)
                .contrast(1.08)
                .opacity(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else if info.hasData {
            EventThumbnail(
                eventName: info.name,
                folderPath: info.folderPath,
                cornerRadius: 0
            )
            .saturation(0.95)
            .contrast(1.08)
            .opacity(0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HeroAuroraBackdrop()
        }
    }

    @ViewBuilder
    private func bannerMenu(info: LatestEventInfo) -> some View {
        if let bookmarkIndex = info.bookmarkIndex {
            Menu {
                Button("Choose Banner Photo…") {
                    chooseBannerPhoto(for: bookmarkIndex)
                }
                if info.bannerImagePath != nil {
                    Button("Remove Banner Photo") {
                        appState.clearEventFolderBanner(at: bookmarkIndex)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 34, height: 26)
                    .background(
                        Capsule()
                            .fill(Color.auroraBg.opacity(0.72))
                            .background(.ultraThinMaterial, in: Capsule())
                    )
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
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

    // MARK: - Bottom strip

    private func bottomStrip(info: LatestEventInfo) -> some View {
        HStack(spacing: 0) {
            stripItem(icon: "photo.fill", value: info.strip.rawFiles, label: "RAW Files")
            stripDivider
            stripItem(icon: "externaldrive.fill", value: info.strip.data, label: "Data Imported")
            stripDivider
            stripItem(icon: "camera.aperture", value: info.strip.avgISO, label: "Avg ISO")
            stripDivider
            stripItem(icon: "camera.fill", value: info.strip.topLens, label: "Top Lenses")
            stripDivider
            stripItem(icon: "calendar", value: info.strip.date, label: "Last Imported")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
            Color.auroraBg.opacity(0.34)
                .background(.ultraThinMaterial)
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.auroraStroke),
            alignment: .top
        )
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(Color.auroraStroke)
            .frame(width: 1, height: 30)
    }

    private func stripItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 12) {
            IconChip(systemName: icon, color: .auroraViolet, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.sora(13, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(label)
                    .font(.manrope(10, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    // MARK: - Data resolution

    private struct LatestEventInfo {
        let name: String
        let folderPath: String?
        let bookmarkIndex: Int?
        let bannerImagePath: String?
        let meta: String?
        let description: String?
        let badge: String
        let strip: HeroStrip
        let hasData: Bool
        let isFinalized: Bool
    }

    private struct HeroStrip {
        let rawFiles: String
        let data: String
        let avgISO: String
        let topLens: String
        let date: String
    }

    private func resolveLatestEvent() -> LatestEventInfo {
        if let openEvent = latestOpenEventInfo() {
            return openEvent
        }

        guard let report = appState.lastImportReport else {
            return LatestEventInfo(
                name: "No imports yet",
                folderPath: nil,
                bookmarkIndex: nil,
                bannerImagePath: nil,
                meta: nil,
                description: "Connect a card reader and import to see your most recent event here.",
                badge: "Idle",
                strip: HeroStrip(rawFiles: "—", data: "—", avgISO: "—", topLens: "—", date: "—"),
                hasData: false,
                isFinalized: false
            )
        }

        let folderURL = URL(fileURLWithPath: report.destinationPath)
        let name = folderURL.lastPathComponent
        let date = report.timestamp

        // Aggregate matching history for richer description
        let agg = appState.importStats(forEventPath: report.destinationPath)
        let firstDate = agg?.firstDate ?? date
        let lastDate = agg?.lastDate ?? date

        let metaParts: [String] = [
            AuroraFormat.dateRange(firstDate, lastDate)
        ]
        let meta = metaParts.joined(separator: " · ")

        let sessions = agg?.sessionCount ?? 1
        let descTotal = agg?.photoCount ?? report.fileCount
        let description = "\(AuroraFormat.count(descTotal)) photos across \(sessions) import\(sessions == 1 ? "" : "s")."

        let bytes = AuroraFormat.bytesParts(report.totalBytes)
        let eventReport = cachedReport(forPath: report.destinationPath) ?? appState.statsReport
        let bookmarkIndex = matchingBookmarkIndex(for: report.destinationPath)

        let isFinalized = appState.finalizedEvent(matchingPath: report.destinationPath) != nil

        return LatestEventInfo(
            name: name,
            folderPath: report.destinationPath,
            bookmarkIndex: bookmarkIndex,
            bannerImagePath: nil,
            meta: meta,
            description: description,
            badge: name.split(separator: " ").prefix(2).joined(separator: " "),
            strip: HeroStrip(
                rawFiles: AuroraFormat.count(report.fileCount),
                data: "\(bytes.value) \(bytes.unit)",
                avgISO: eventReport?.avgISO.map(AuroraFormat.iso) ?? "—",
                topLens: eventReport?.allLenses.first.map { LensDisplayFormatter.displayName(make: $0.make, model: $0.model) } ?? "—",
                date: AuroraFormat.dateCompact(lastDate)
            ),
            hasData: true,
            isFinalized: isFinalized
        )
    }

    private func latestOpenEventInfo() -> LatestEventInfo? {
        guard let event = appState.uniqueImportDestinations.first(where: {
            appState.finalizedEvent(forBookmarkIndex: $0.bookmarkIndex) == nil
        }) else { return nil }

        let summary = appState.importStatsForEventFolder(at: event.bookmarkIndex)
        let report = cachedReport(for: event)
        let peak = event.bookmarkIndex < appState.eventFolderPeakRawCounts.count
            ? appState.eventFolderPeakRawCounts[event.bookmarkIndex]
            : 0
        let cachedCount = event.bookmarkIndex < appState.eventFolderCachedCounts.count
            ? max(appState.eventFolderCachedCounts[event.bookmarkIndex], 0)
            : 0
        let totalPhotos = max(summary?.photoCount ?? 0, max(report?.totalFilesAnalyzed ?? 0, max(peak, cachedCount)))
        let totalBytes = summary?.totalBytes ?? report?.totalBytes ?? 0
        let firstDate = summary?.firstDate ?? report?.firstImportDate
        let lastDate = summary?.lastDate ?? firstDate
        let sessions = summary?.sessionCount ?? (totalPhotos > 0 ? 1 : 0)

        let meta = firstDate.map { AuroraFormat.dateRange($0, lastDate ?? $0) }
        let description = totalPhotos > 0
            ? "\(AuroraFormat.count(totalPhotos)) photos across \(sessions) import\(sessions == 1 ? "" : "s")."
            : "Open event folder ready for the next import."
        let bytes = AuroraFormat.bytesParts(totalBytes)

        return LatestEventInfo(
            name: event.name,
            folderPath: event.path,
            bookmarkIndex: event.bookmarkIndex,
            bannerImagePath: bannerImagePath(for: event.bookmarkIndex),
            meta: meta,
            description: description,
            badge: event.name.split(separator: " ").prefix(2).joined(separator: " "),
            strip: HeroStrip(
                rawFiles: totalPhotos > 0 ? AuroraFormat.count(totalPhotos) : "—",
                data: totalBytes > 0 ? "\(bytes.value) \(bytes.unit)" : "—",
                avgISO: report?.avgISO.map(AuroraFormat.iso) ?? "—",
                topLens: report?.allLenses.first.map { LensDisplayFormatter.displayName(make: $0.make, model: $0.model) } ?? "—",
                date: lastDate.map(AuroraFormat.dateCompact) ?? "—"
            ),
            hasData: true,
            isFinalized: false
        )
    }

    private func cachedReport(for event: (path: String, name: String, bookmarkIndex: Int)) -> StatsReport? {
        if let cached = EventStatsCache.load(forPath: event.path)?.report {
            return cached
        }
        guard event.bookmarkIndex < appState.eventFolderPreviousCachedPaths.count else { return nil }
        let previousPath = appState.eventFolderPreviousCachedPaths[event.bookmarkIndex]
        guard !previousPath.isEmpty else { return nil }
        return EventStatsCache.load(forPath: previousPath)?.report
    }

    private func cachedReport(forPath path: String) -> StatsReport? {
        EventStatsCache.load(forPath: path)?.report
    }

    private func matchingBookmarkIndex(for path: String) -> Int? {
        let norm = path.hasSuffix("/") ? String(path.dropLast()) : path
        return appState.uniqueImportDestinations.first { destination in
            let destinationPath = destination.path.hasSuffix("/") ? String(destination.path.dropLast()) : destination.path
            guard !destinationPath.isEmpty else { return false }
            return norm == destinationPath || norm.hasPrefix(destinationPath + "/") || destinationPath.hasPrefix(norm + "/")
        }?.bookmarkIndex
    }

    private func bannerImagePath(for bookmarkIndex: Int) -> String? {
        guard bookmarkIndex >= 0,
              bookmarkIndex < appState.eventFolderBannerImagePaths.count else { return nil }
        let path = appState.eventFolderBannerImagePaths[bookmarkIndex]
        return path.isEmpty ? nil : path
    }
}

private struct HeroEventActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.manrope(12, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 17)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.auroraCyan, Color.blue.opacity(0.95)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.auroraCyan.opacity(0.34), radius: 12, x: 0, y: 6)
            .shadow(color: Color.black.opacity(0.28), radius: 8, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
