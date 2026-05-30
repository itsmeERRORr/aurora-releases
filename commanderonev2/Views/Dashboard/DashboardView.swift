import SwiftUI
import AppKit

struct DashboardView: View {
    @Bindable var appState: AppState
    let volumeWatcher: VolumeWatcher?
    let statsRunner: StatsRunner?

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

                recentEvents
            }
            .padding(.horizontal, AuroraSpacing.mainPaddingH)
            .padding(.vertical, AuroraSpacing.mainPaddingV)
        }
        .scrollIndicators(.hidden)
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
            Button(action: addFolder) {
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

    private var recentEvents: some View {
        VStack(alignment: .leading, spacing: 8) {
            AuroraPanelHeader(title: "Recent Events", actionLabel: "View all →", action: onViewAllEvents)

            let events = appState.uniqueImportDestinations
                .prefix(4)
                .compactMap(recentEventDisplay)

            if events.isEmpty {
                emptyEvents
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: AuroraSpacing.gridGap), count: 4),
                    spacing: AuroraSpacing.gridGap
                ) {
                    ForEach(events) { event in
                        RecentEventThumb(event: event) {
                            onSelectEvent(event)
                        }
                    }
                }
            }
        }
    }

    private func recentEventDisplay(for destination: (path: String, name: String, bookmarkIndex: Int)) -> EventAggregate? {
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
        let totalBytes = max(summary?.totalBytes ?? 0, finalized?.totalBytes ?? 0)
        let lastDate = summary?.lastDate
            ?? finalized?.lastImportDate
            ?? finalized?.finalizedAt
            ?? .distantPast

        return EventAggregate(
            id: destination.path,
            name: destination.name,
            totalFiles: totalFiles,
            totalBytes: totalBytes,
            averageSpeed: appState.totalStatsReport?.averageSpeed ?? 0,
            lastDate: lastDate
        )
    }

    private var emptyEvents: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: AuroraSpacing.gridGap), count: 4),
            spacing: AuroraSpacing.gridGap
        ) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.auroraPanel2)
                    .aspectRatio(4.0/3.0, contentMode: .fit)
                    .overlay(
                        Text("No event")
                            .font(.manrope(11, weight: .semibold))
                            .foregroundStyle(Color.auroraFaint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.auroraStroke, lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Actions

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to host a new event"
        panel.prompt = "Select Folder"
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = BookmarkManager.saveBookmark(for: url) else { return }
        appState.addEventFolder(bookmark: bookmark)
        let idx = appState.eventFolderBookmarks.count - 1
        appState.setEventFolderDisplayName(at: idx, name: url.lastPathComponent)
    }
}

// MARK: - Total Library card

struct TotalLibraryCard: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Total Library")
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Color.auroraMuted)

            Text(AuroraFormat.count(totalPhotos))
                .font(.auroraBigNumber)
                .tracking(-1.5)
                .foregroundStyle(Color.auroraTxt)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(subtitle)
                .font(.manrope(12.5, weight: .semibold))
                .foregroundStyle(Color.auroraMuted)
                .lineLimit(1)

            Divider().background(Color.auroraStroke).padding(.vertical, 6)

            HStack(spacing: 16) {
                metaItem(label: "Imports", value: "\(appState.importHistory.count)")
                Divider().frame(height: 22).background(Color.auroraStroke)
                metaItem(label: "Avg Speed", value: speedString)
                Divider().frame(height: 22).background(Color.auroraStroke)
                metaItem(label: "Events", value: "\(eventCount)")
            }
            Spacer(minLength: 4)
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
        appState.totalStatsReport?.totalFilesAnalyzed
            ?? appState.importHistory.reduce(0) { $0 + $1.fileCount }
    }

    private var eventCount: Int {
        EventAggregator.build(appState: appState).count
    }

    private var subtitle: String {
        let parts = AuroraFormat.bytesParts(appState.totalStatsReport?.totalBytes ?? 0)
        if totalPhotos == 0 { return "Your library will appear here." }
        return "photos across \(eventCount) event\(eventCount == 1 ? "" : "s") · \(parts.value) \(parts.unit) stored"
    }

    private var speedString: String {
        guard let r = appState.totalStatsReport, r.averageSpeed > 0 else { return "—" }
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
}

// MARK: - Waiting card

struct WaitingCard: View {
    @Bindable var appState: AppState
    let onImportNow: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void

    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.auroraCyan.opacity(0.55), lineWidth: 1.5)
                        .frame(width: pulse ? 56 : 42, height: pulse ? 56 : 42)
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

            dropZone

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
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }

    private var cardIcon: String {
        if appState.activeVolume != nil { return "externaldrive.fill" }
        return "sdcard"
    }

    private var title: String {
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
        if let vol = appState.activeVolume, vol.rawFileCount > 0 {
            return "\(AuroraFormat.count(vol.rawFileCount)) RAW files detected"
        }
        if appState.activeVolume != nil { return "Inserted card detected" }
        return "Plug in a reader to start an import"
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
            .strokeBorder(Color.auroraStroke2, style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .fill(Color.auroraPanel)
            )
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line.square")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.auroraFaint)
                    Text(dropLabel)
                        .font(.manrope(12, weight: .semibold))
                        .foregroundStyle(Color.auroraMuted)
                    Text(dropHint)
                        .font(.manrope(11, weight: .medium))
                        .foregroundStyle(Color.auroraFaint)
                }
            )
            .frame(height: 96)
    }

    private var dropLabel: String {
        if appState.destinationURL != nil { return "Destination set" }
        return "Drop a destination folder"
    }

    private var dropHint: String {
        if let dest = appState.destinationURL { return dest.lastPathComponent }
        return "Imports will be moved or copied here"
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
                Button {
                    onImportNow()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold))
                        Text("Import now")
                    }
                }
                .buttonStyle(AuroraGradientButtonStyle(compact: true))
                .disabled(appState.activeVolume == nil)
                .opacity(appState.activeVolume == nil ? 0.5 : 1)

                Toggle("Auto-import", isOn: $appState.autoImport)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Color.auroraCyan)
                    .font(.manrope(12, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
            }
        }
    }
}

// MARK: - Recent event tile

struct RecentEventThumb: View {
    let event: EventAggregate
    var onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            EventThumbnail(
                eventName: event.name,
                folderPath: event.id,
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
                )
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
