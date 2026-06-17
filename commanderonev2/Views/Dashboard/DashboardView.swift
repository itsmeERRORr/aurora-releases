import SwiftUI
import AppKit

struct DashboardView: View {
    @Bindable var appState: AppState
    let volumeWatcher: VolumeWatcher?
    let statsRunner: StatsRunner?

    @State private var isCreatingEvent = false

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

                FileBrowserRow(appState: appState)

                recentEvents
            }
            .padding(.horizontal, AuroraSpacing.mainPaddingH)
            .padding(.vertical, AuroraSpacing.mainPaddingV)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $isCreatingEvent) {
            CreateEventSheet { name, folderURL in
                createEvent(name: name, folderURL: folderURL)
            }
        }
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
            Button(action: beginCreateEvent) {
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

            let items = appState.uniqueImportDestinations
                .filter { !appState.isLibraryFolder(at: $0.bookmarkIndex) }
                .compactMap { destination -> (event: EventAggregate, bannerPath: String?, bookmarkIndex: Int, isFinalized: Bool)? in
                    guard let event = recentEventDisplay(for: destination) else { return nil }
                    return (
                        event: event,
                        bannerPath: bannerImagePath(for: destination.bookmarkIndex),
                        bookmarkIndex: destination.bookmarkIndex,
                        isFinalized: appState.finalizedEvent(forBookmarkIndex: destination.bookmarkIndex) != nil
                    )
                }
                .sorted(by: recentEventSort)
                .prefix(4)

            if items.isEmpty {
                emptyEvents
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: AuroraSpacing.gridGap), count: 4),
                    spacing: AuroraSpacing.gridGap
                ) {
                    ForEach(Array(items), id: \.event.id) { item in
                        RecentEventThumb(event: item.event, bannerImagePath: item.bannerPath) {
                            onSelectEvent(item.event)
                        }
                    }
                }
            }
        }
    }

    private func recentEventSort(
        _ lhs: (event: EventAggregate, bannerPath: String?, bookmarkIndex: Int, isFinalized: Bool),
        _ rhs: (event: EventAggregate, bannerPath: String?, bookmarkIndex: Int, isFinalized: Bool)
    ) -> Bool {
        if lhs.event.lastDate != rhs.event.lastDate { return lhs.event.lastDate > rhs.event.lastDate }
        if lhs.isFinalized != rhs.isFinalized { return !lhs.isFinalized }
        return lhs.bookmarkIndex > rhs.bookmarkIndex
    }

    private func bannerImagePath(for bookmarkIndex: Int) -> String? {
        guard bookmarkIndex >= 0,
              bookmarkIndex < appState.eventFolderBannerImagePaths.count else { return nil }
        let path = appState.eventFolderBannerImagePaths[bookmarkIndex]
        return path.isEmpty ? nil : path
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
        let displayDate = appState.effectiveDateForEvent(at: destination.bookmarkIndex) ?? .distantPast

        return EventAggregate(
            id: destination.path,
            name: destination.name,
            totalFiles: totalFiles,
            totalBytes: totalBytes,
            averageSpeed: appState.totalStatsReport?.averageSpeed ?? 0,
            lastDate: displayDate
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
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.auroraStroke, lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Actions

    private func beginCreateEvent() {
        isCreatingEvent = true
    }

    private func createEvent(name: String, folderURL: URL) -> String? {
        guard let bookmark = BookmarkManager.saveBookmark(for: folderURL) else {
            return "Aurora could not save access to this folder. Choose a different folder and try again."
        }
        let bookmarkIndex = appState.addEventFolder(bookmark: bookmark, displayName: name)

        // Auto-scan the folder in the background so stats are ready when the user opens the event.
        guard let runner = statsRunner else { return nil }
        let folderPath = folderURL.path
        appState.backgroundScanningBookmarkIndices.insert(bookmarkIndex)
        appState.backgroundScanStartTimes[bookmarkIndex] = Date()
        Task {
            // Count files first so the UI can show a meaningful estimate.
            let fileCount = VolumeWatcher.countRawFiles(at: folderURL, extensions: appState.supportedExtensions)
            appState.backgroundScanFileCount[bookmarkIndex] = fileCount

            let result = await runner.runStatsForEventFolder(at: folderURL)

            appState.backgroundScanningBookmarkIndices.remove(bookmarkIndex)
            appState.backgroundScanFileCount.removeValue(forKey: bookmarkIndex)
            appState.backgroundScanStartTimes.removeValue(forKey: bookmarkIndex)

            guard let r = result, r.totalFilesAnalyzed > 0 else { return }
            let now = Date()
            EventStatsCache.save(r, forPath: folderPath, scanDate: now, rawFileCountAtScan: r.totalFilesAnalyzed)
            appState.updateEventFolderCache(at: bookmarkIndex, count: r.totalFilesAnalyzed, path: folderPath)
            appState.setEventFolderPeakIfHigher(at: bookmarkIndex, count: r.totalFilesAnalyzed)
            appState.log("Auto-scan complete: \(name) — \(r.totalFilesAnalyzed) photos")
            // Merge into global stats off the MainActor so EventStatsView can
            // load from cache immediately without waiting for the combine + save.
            let existing = appState.totalStatsReport
            Task.detached(priority: .utility) {
                let combined = StatsReport.combine(existing, r)
                await MainActor.run { appState.totalStatsReport = combined }
            }
        }

        return nil
    }
}

private struct CreateEventSheet: View {
    let onCreate: (String, URL) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var eventName = ""
    @State private var folderURL: URL?
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        eventName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canChooseFolder: Bool {
        !trimmedName.isEmpty
    }

    private var canCreate: Bool {
        canChooseFolder && folderURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                IconChip(systemName: "folder.badge.plus", color: .auroraCyan, size: 38, iconScale: 0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Event")
                        .font(.sora(20, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                    Text("Name the event first, then choose its main folder.")
                        .font(.manrope(12, weight: .medium))
                        .foregroundStyle(Color.auroraMuted)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Event Name")
                    .font(.manrope(11, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.auroraFaint)
                TextField("R6 SLC Major 2026", text: $eventName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Main Folder")
                    .font(.manrope(11, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.auroraFaint)

                HStack(spacing: 10) {
                    IconChip(systemName: "folder.fill", color: .auroraViolet, size: 32, iconScale: 0.5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folderURL?.lastPathComponent ?? "No folder selected")
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(folderURL == nil ? Color.auroraMuted : Color.auroraTxt)
                            .lineLimit(1)
                        Text(folderURL?.path ?? "Choose where this event's photos will live")
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(folderURL == nil ? "Choose…" : "Change…", action: chooseFolder)
                        .buttonStyle(AuroraGhostButtonStyle())
                        .disabled(!canChooseFolder)
                        .opacity(canChooseFolder ? 1 : 0.45)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                        .fill(Color.auroraPanel2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                        .strokeBorder(folderURL == nil ? Color.auroraStroke : Color.auroraViolet.opacity(0.45), lineWidth: 1)
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraLive)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(AuroraGhostButtonStyle())
                Button("Create Event") { createEvent() }
                    .buttonStyle(AuroraGradientButtonStyle(compact: true))
                    .disabled(!canCreate)
                    .opacity(canCreate ? 1 : 0.45)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Color.auroraBg2)
        .onAppear { nameFocused = true }
    }

    private func chooseFolder() {
        guard canChooseFolder else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the main folder for \(trimmedName)"
        panel.prompt = "Select Folder"
        if panel.runModal() == .OK, let url = panel.url {
            folderURL = url
            errorMessage = nil
        }
    }

    private func createEvent() {
        guard let folderURL, canCreate else { return }
        if let error = onCreate(trimmedName, folderURL) {
            errorMessage = error
            return
        }
        dismiss()
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

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button {
                    addLibraryFolders()
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                        .font(.manrope(12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.auroraCyan)
            }
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

    private func addLibraryFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select folders containing RAW files to add to your library"
        panel.prompt = "Add Folder"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            appState.addLibraryFolder(url: url)
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
    @State private var importBorderSpin = false
    @State private var showRenameEditor = false
    @State private var renameEditorConfirmed = false

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

            currentEventPicker

            destinationPicker

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
            updateAnimations()
        }
        .onDisappear {
            pulse = false
            importBorderSpin = false
        }
        .onChange(of: shouldPulseWaitingCard) { _, _ in
            updateAnimations()
        }
        .onChange(of: shouldEmphasizeImportNow) { _, _ in
            updateAnimations()
        }
        .onChange(of: isImportNowBlocked) { _, _ in
            updateAnimations()
        }
        .onChange(of: appState.renameOnImport) { _, isEnabled in
            if isEnabled {
                renameEditorConfirmed = false
                showRenameEditor = true
            }
        }
        .sheet(isPresented: $showRenameEditor, onDismiss: handleRenameEditorDismiss) {
            RenameTemplateEditorSheet(appState: appState) {
                renameEditorConfirmed = true
            }
        }
    }

    private func updateAnimations() {
        if shouldPulseWaitingCard {
            pulse = false
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        } else {
            pulse = false
        }

        if shouldEmphasizeImportNow && !isImportNowBlocked {
            importBorderSpin = false
            withAnimation(.linear(duration: 1.85).repeatForever(autoreverses: false)) {
                importBorderSpin = true
            }
        } else {
            importBorderSpin = false
        }
    }

    private var cardIcon: String {
        if !importableVolumes.isEmpty { return "externaldrive.fill" }
        return "sdcard"
    }

    private var title: String {
        if importableVolumes.count > 1 {
            return "\(importableVolumes.count) cards ready"
        }
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
        if importableVolumes.count > 1 {
            let total = importableVolumes.reduce(0) { $0 + $1.rawFileCount }
            return "\(AuroraFormat.count(total)) RAW files across \(importableVolumes.count) cards"
        }
        if let vol = appState.activeVolume, vol.rawFileCount > 0 {
            return "\(AuroraFormat.count(vol.rawFileCount)) RAW files detected"
        }
        if appState.activeVolume != nil { return "Inserted card detected" }
        return "Plug in a reader to start an import"
    }

    @ViewBuilder
    private var currentEventPicker: some View {
        if !openEvents.isEmpty {
            HStack(spacing: 10) {
                IconChip(systemName: "flag.checkered", color: .auroraCyan, size: 30, iconScale: 0.48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Event")
                        .font(.manrope(10.5, weight: .bold))
                        .foregroundStyle(Color.auroraFaint)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Text(activeEvent?.name ?? "No event selected")
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(activeEvent == nil ? Color.auroraMuted : Color.auroraTxt)
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    ForEach(openEvents, id: \.bookmarkIndex) { event in
                        Button {
                            chooseDestination(for: event)
                        } label: {
                            if activeEvent?.bookmarkIndex == event.bookmarkIndex {
                                Label(event.name, systemImage: "checkmark")
                            } else {
                                Text(event.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(activeEvent == nil ? "Choose Event" : "Switch")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .buttonStyle(AuroraGhostButtonStyle())
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .fill(Color.auroraPanel2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .strokeBorder(activeEvent == nil ? Color.auroraStroke : Color.auroraCyan.opacity(0.45), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var destinationPicker: some View {
        if let dest = appState.destinationURL {
            HStack(spacing: 10) {
                IconChip(systemName: "folder.fill", color: .auroraViolet, size: 32, iconScale: 0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dest.lastPathComponent)
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                        .lineLimit(1)
                    Text(dest.path)
                        .font(.manrope(11, weight: .medium))
                        .foregroundStyle(Color.auroraFaint)
                        .lineLimit(1)
                }
                Spacer()
                Button("Change…", action: chooseDestination)
                    .buttonStyle(AuroraGhostButtonStyle())
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .fill(Color.auroraPanel2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .strokeBorder(Color.auroraStroke, lineWidth: 1)
            )
        } else {
            VStack(spacing: 2) {
                Button("Choose Destination", action: chooseDestination)
                    .buttonStyle(AuroraGradientButtonStyle(compact: true))
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)

                Text("Please choose a destination to import the files")
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to import photos"
        panel.prompt = "Select"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = BookmarkManager.saveBookmark(for: url) else { return }
        appState.destinationURL = url
        appState.destinationBookmarkData = data
        appState.activeEventFolderIndex = eventContainingDestination(url.path)?.bookmarkIndex
    }

    private var openEvents: [(path: String, name: String, bookmarkIndex: Int)] {
        appState.uniqueImportDestinations.filter { event in
            !event.path.isEmpty
                && appState.finalizedEvent(forBookmarkIndex: event.bookmarkIndex) == nil
                && !appState.isLibraryFolder(at: event.bookmarkIndex)
        }
    }

    private var activeEvent: (path: String, name: String, bookmarkIndex: Int)? {
        if let index = appState.activeEventFolderIndex,
           let event = openEvents.first(where: { $0.bookmarkIndex == index }) {
            return event
        }
        guard let destination = appState.destinationURL else { return nil }
        let destinationPath = normalizedPath(destination.path)
        return eventContainingDestination(destinationPath)
    }

    private func eventContainingDestination(_ path: String) -> (path: String, name: String, bookmarkIndex: Int)? {
        let destinationPath = normalizedPath(path)
        return openEvents
            .sorted { $0.path.count > $1.path.count }
            .first { event in
                let eventPath = normalizedPath(event.path)
                return destinationPath == eventPath || destinationPath.hasPrefix(eventPath + "/")
            }
    }

    private func chooseDestination(for event: (path: String, name: String, bookmarkIndex: Int)) {
        appState.activeEventFolderIndex = event.bookmarkIndex
        let url = URL(fileURLWithPath: event.path)
        appState.destinationURL = url
        appState.destinationBookmarkData = BookmarkManager.saveBookmark(for: url)
    }

    private func normalizedPath(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
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
                let importBlocked = isImportNowBlocked
                Button {
                    onImportNow()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold))
                        Text(importableVolumes.count > 1 ? "Import all" : "Import now")
                    }
                }
                .buttonStyle(AuroraGradientButtonStyle(compact: true))
                .disabled(importBlocked)
                .opacity(importBlocked ? 0.5 : 1)
                .overlay {
                    if shouldEmphasizeImportNow && !importBlocked {
                        ZStack {
                            RoundedRectangle(cornerRadius: AuroraRadius.badge, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                            RoundedRectangle(cornerRadius: AuroraRadius.badge, style: .continuous)
                                .strokeBorder(
                                    AngularGradient(
                                        gradient: Gradient(stops: [
                                            .init(color: .white.opacity(0.05), location: 0.00),
                                            .init(color: .white.opacity(0.05), location: 0.62),
                                            .init(color: .auroraCyan, location: 0.74),
                                            .init(color: .white, location: 0.82),
                                            .init(color: .auroraMagenta, location: 0.90),
                                            .init(color: .white.opacity(0.05), location: 1.00)
                                        ]),
                                        center: .center,
                                        startAngle: .degrees(importBorderSpin ? 360 : 0),
                                        endAngle: .degrees(importBorderSpin ? 720 : 360)
                                    ),
                                    lineWidth: 2.4
                                )
                        }
                        .padding(-3)
                        .allowsHitTesting(false)
                    }
                }
                .shadow(
                    color: shouldEmphasizeImportNow && !importBlocked ? Color.auroraCyan.opacity(0.35) : .clear,
                    radius: shouldEmphasizeImportNow && !importBlocked ? 14 : 0,
                    x: 0,
                    y: 0
                )

                HStack(spacing: 12) {
                    Spacer()
                    AuroraMiniToggle(label: "Rename", isOn: $appState.renameOnImport, tint: .auroraMagenta)
                    if appState.renameOnImport {
                        Button("Edit") { showRenameEditor = true }
                            .font(.manrope(11, weight: .bold))
                            .foregroundStyle(Color.auroraMagenta)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.auroraMagenta.opacity(0.14))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.auroraMagenta.opacity(0.35), lineWidth: 1)
                            )
                            .buttonStyle(.plain)
                    }
                    AuroraMiniToggle(label: "Auto-import", isOn: $appState.autoImport, tint: .auroraCyan)
                }
            }
        }
    }

    private func handleRenameEditorDismiss() {
        if appState.renameOnImport && !renameEditorConfirmed {
            appState.renameOnImport = false
        }
        renameEditorConfirmed = false
    }

    private var shouldEmphasizeImportNow: Bool {
        guard !importableVolumes.isEmpty else { return false }
        switch appState.importState {
        case .idle, .done, .ejectingDone:
            return true
        default:
            return false
        }
    }

    private var isImportNowBlocked: Bool {
        let allAlreadyImported = appState.allDestinationFilesAlreadyImported && appState.sourceFileCountForDestinationCheck > 0
        return importableVolumes.isEmpty || allAlreadyImported || appState.destinationURL == nil
    }

    private var shouldPulseWaitingCard: Bool {
        guard importableVolumes.isEmpty else { return false }
        switch appState.importState {
        case .idle, .done, .ejectingDone:
            return true
        default:
            return false
        }
    }

    private var importableVolumes: [VolumeInfo] {
        let volumes = appState.mountedVolumes.filter { $0.rawFileCount > 0 && !isDestinationVolume($0.path) }
        guard !volumes.isEmpty else {
            if let active = appState.activeVolume, active.rawFileCount > 0, !isDestinationVolume(active.path) { return [active] }
            return []
        }
        return Array(volumes.prefix(2))
    }

    private func isDestinationVolume(_ sourceURL: URL) -> Bool {
        guard let destinationURL = appState.destinationURL else { return false }
        let sourcePath = normalizedPath(sourceURL.path)
        let destinationPath = normalizedPath(destinationURL.path)
        return destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/")
    }
}

private struct AuroraMiniToggle: View {
    let label: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { isOn.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .font(.manrope(12, weight: .semibold))
                    .foregroundStyle(isOn ? Color.auroraTxt : Color.auroraMuted)
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? tint.opacity(0.95) : Color.auroraStroke2.opacity(0.9))
                        .frame(width: 36, height: 20)
                    Circle()
                        .fill(Color.white.opacity(isOn ? 0.96 : 0.72))
                        .frame(width: 16, height: 16)
                        .padding(.horizontal, 2)
                        .shadow(color: isOn ? tint.opacity(0.45) : .clear, radius: 6, x: 0, y: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .auroraTooltip(isOn ? "Enabled" : "Disabled")
    }
}

// MARK: - Recent event tile

struct RecentEventThumb: View {
    let event: EventAggregate
    var bannerImagePath: String? = nil
    var onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            EventThumbnail(
                eventName: event.name,
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
                ),
                bannerImagePath: bannerImagePath
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

// MARK: - File Browser Row

struct FileBrowserRow: View {
    @Bindable var appState: AppState

    @State private var sourceFiles: [URL] = []
    @State private var destFiles: [URL] = []
    @State private var isLoadingSource = false
    @State private var isLoadingDest = false
    @State private var showAdvanced = false
    @State private var loadSourceTask: Task<Void, Never>?
    @State private var loadDestTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: AuroraSpacing.gridGap) {
            filePanel(
                title: "Source Files",
                icon: "sdcard",
                color: .auroraCyan,
                files: sourceFiles,
                isLoading: isLoadingSource,
                emptyHint: sourceVolumes.isEmpty ? "No card detected" : "No RAW files found",
                statusText: sourceFilesStatusText,
                onAdvanced: sourceFiles.isEmpty ? nil : { showAdvanced = true }
            )
            filePanel(
                title: "Destination Files",
                icon: "folder.fill",
                color: .auroraViolet,
                files: destFiles,
                isLoading: isLoadingDest,
                emptyHint: appState.destinationURL == nil ? "No destination set" : "No files found",
                onRefresh: appState.destinationURL == nil ? nil : { loadDestFiles(from: appState.destinationURL) }
            )
        }
        .sheet(isPresented: $showAdvanced) {
            AdvancedView(appState: appState) {
                showAdvanced = false
            }
            .frame(minWidth: 1100, idealWidth: 1280, minHeight: 638, idealHeight: 638)
            .environment(\.colorScheme, .dark)
        }
        .onChange(of: appState.activeVolume) { _, volume in
            loadSourceFiles()
        }
        .onChange(of: appState.mountedVolumes) { _, _ in
            loadSourceFiles()
        }
        .onChange(of: appState.destinationURL) { _, url in
            loadDestFiles(from: url)
        }
        .onChange(of: appState.renameOnImport) { _, _ in
            clearImportBlockReason()
        }
        .onChange(of: appState.renameTemplate) { _, _ in
            clearImportBlockReason()
        }
        .onChange(of: appState.importMode) { _, _ in
            clearImportBlockReason()
        }
        .onAppear {
            loadSourceFiles()
            loadDestFiles(from: appState.destinationURL)
        }
        .onDisappear {
            loadSourceTask?.cancel()
            loadDestTask?.cancel()
        }
    }

    private func filePanel(
        title: String,
        icon: String,
        color: Color,
        files: [URL],
        isLoading: Bool,
        emptyHint: String,
        statusText: String? = nil,
        onAdvanced: (() -> Void)? = nil,
        onRefresh: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                IconChip(systemName: icon, color: color, size: 26, iconScale: 0.5)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(Color.auroraTxt)
                        if title == "Source Files", let statusText {
                            Text(statusText)
                                .font(.manrope(11, weight: .bold))
                                .foregroundStyle(Color.auroraCyan)
                                .lineLimit(1)
                        }
                    }
                    if title == "Source Files", let sourceNamesText {
                        Text(sourceNamesText)
                            .font(.manrope(10.5, weight: .semibold))
                            .foregroundStyle(Color.auroraFaint)
                            .lineLimit(1)
                    }
                }
                if let statusText, title != "Source Files" {
                    Text(statusText)
                        .font(.manrope(11, weight: .bold))
                        .foregroundStyle(Color.auroraCyan)
                        .lineLimit(1)
                }
                Spacer()
                if let onAdvanced {
                    Button("Advanced", action: onAdvanced)
                        .buttonStyle(AuroraGhostButtonStyle())
                }
                if let onRefresh {
                    Button(action: onRefresh) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                            Text("Refresh")
                        }
                    }
                    .buttonStyle(AuroraGhostButtonStyle())
                    .disabled(isLoading)
                }
                if !files.isEmpty {
                    Text("\(files.count)")
                        .font(.manrope(11, weight: .bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(color.opacity(0.12)))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)

            Rectangle()
                .fill(Color.auroraStroke)
                .frame(height: 1)

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading…")
                        .font(.manrope(11, weight: .medium))
                        .foregroundStyle(Color.auroraFaint)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 180)
            } else if files.isEmpty {
                Text(emptyHint)
                    .font(.manrope(12, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(files.enumerated()), id: \.offset) { idx, file in
                            HStack(spacing: 10) {
                                Text(file.pathExtension.uppercased())
                                    .font(.manrope(9, weight: .bold))
                                    .foregroundStyle(color)
                                    .frame(width: 34)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(color.opacity(0.12)))
                                    .multilineTextAlignment(.center)
                                Text(file.lastPathComponent)
                                    .font(.manrope(11.5, weight: .medium))
                                    .foregroundStyle(Color.auroraTxt)
                                    .lineLimit(1)
                                Spacer()
                                if let size = fileSize(for: file) {
                                    Text(size)
                                        .font(.manrope(10, weight: .medium))
                                        .foregroundStyle(Color.auroraFaint)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)

                            if idx < files.count - 1 {
                                Rectangle()
                                    .fill(Color.auroraStroke)
                                    .frame(height: 1)
                                    .padding(.leading, 14)
                            }
                        }
                    }
                }
                .frame(height: 180)
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 233)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .fill(Color.auroraPanel)
        )
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke, lineWidth: 1)
        )
    }

    private func fileSize(for url: URL) -> String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else { return nil }
        let parts = AuroraFormat.bytesParts(Int64(size))
        return "\(parts.value) \(parts.unit)"
    }

    private func loadSourceFiles() {
        let volumes = sourceVolumes
        guard !volumes.isEmpty else {
            loadSourceTask?.cancel()
            sourceFiles = []
            clearImportBlockReason()
            return
        }
        isLoadingSource = true
        let paths = volumes.map(\.path)
        let exts = appState.supportedExtensions
        loadSourceTask?.cancel()
        loadSourceTask = Task.detached(priority: .utility) {
            let files = paths.flatMap { path in
                VolumeWatcher.listRawFiles(at: path, extensions: exts)
            }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                sourceFiles = files
                isLoadingSource = false
                clearImportBlockReason()
            }
        }
    }

    private func loadDestFiles(from url: URL?) {
        guard let url = url else {
            loadDestTask?.cancel()
            destFiles = []
            clearImportBlockReason()
            return
        }
        isLoadingDest = true
        let exts = appState.supportedExtensions
        loadDestTask?.cancel()
        loadDestTask = Task.detached(priority: .utility) {
            let files = VolumeWatcher.listRawFiles(at: url, extensions: exts)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                destFiles = files
                isLoadingDest = false
                clearImportBlockReason()
            }
        }
    }

    private var sourceFilesStatusText: String? {
        if let message = appState.sourceFilesImportStatusMessage { return message }
        return sourceVolumes.count > 1 ? "\(sourceVolumes.count) cards" : nil
    }

    private var sourceNamesText: String? {
        let names = sourceVolumes.map(\.name)
        guard !names.isEmpty else { return nil }
        return names.joined(separator: " + ")
    }

    private var sourceVolumes: [VolumeInfo] {
        let volumes = appState.mountedVolumes.filter { $0.rawFileCount > 0 && !isDestinationVolume($0.path) }
        guard !volumes.isEmpty else {
            if let active = appState.activeVolume, active.rawFileCount > 0, !isDestinationVolume(active.path) { return [active] }
            return []
        }
        return Array(volumes.prefix(2))
    }

    private func isDestinationVolume(_ sourceURL: URL) -> Bool {
        guard let destinationURL = appState.destinationURL else { return false }
        let sourcePath = normalizedPath(sourceURL.path)
        let destinationPath = normalizedPath(destinationURL.path)
        return destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/")
    }

    private func normalizedPath(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func clearImportBlockReason() {
        appState.sourceFileCountForDestinationCheck = sourceFiles.count
        appState.allDestinationFilesAlreadyImported = false
        appState.sourceFilesImportStatusMessage = nil
    }
}
