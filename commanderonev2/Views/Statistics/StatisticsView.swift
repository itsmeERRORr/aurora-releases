import SwiftUI
import AppKit

struct StatisticsView: View {
    @Bindable var appState: AppState
    let statsRunner: StatsRunner?
    var onStartImport: () -> Void = {}
    var onSelectEvent: (Int) -> Void = { _ in }

    @State private var mode: StatsMode = .total
    @State private var viewAllSheet: StatsViewAllSheet?
    @State private var topEventsMetric: TopEventsMetric = .raw
    @State private var isComparing = false
    @State private var compareTagA: EventTag?
    @State private var compareTagB: EventTag?
    // `hasNoFilteredData`/`selectedReport`/`shootingTimeRow` below must never call
    // `appState.dashboardStatsReport`/`dashboardShootingTimeSourceNamesByDay`
    // directly — see the matching comment in TopEventsPanel.swift.
    @State private var cachedTotalReport: StatsReport?
    @State private var cachedShootingTimeSourceNames: [String: String] = [:]

    var body: some View {
        Group {
            if shouldRequestLibraryFirst {
                dashboardAccessEmptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        StatisticsTopbar(mode: $mode, appState: appState, isComparing: $isComparing)

                        if isComparing && mode == .total {
                            CompareSectionView(appState: appState, tagA: $compareTagA, tagB: $compareTagB)
                                .onDisappear {
                                    compareTagA = nil
                                    compareTagB = nil
                                }
                        } else if hasNoFilteredData {
                            noFilteredDataState
                        } else {
                            if hasDashboardEvents {
                                GeneralStatsGrid(appState: appState, mode: mode)

                                HeroEventCard(appState: appState, onViewEvent: onSelectEvent)
                            }

                            PhotoStatsGrid(appState: appState, mode: mode)

                            camerasAndLensesRow

                            if mode == .total {
                                eventsRow

                                chartsRow

                                photosPerMonthRow

                                if hasImportedEvents {
                                    rawImportsTimelineRow
                                }
                            }

                            shootingTimeRow

                            if mode == .total && hasActiveDaysData {
                                activeImportDaysRow
                            }
                        }
                    }
                    .padding(.horizontal, AuroraSpacing.mainPaddingH)
                    .padding(.vertical, AuroraSpacing.mainPaddingV)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
        }
        .sheet(item: $viewAllSheet) { sheet in
            StatsViewAllSheetView(kind: sheet, appState: appState, onSelectEvent: onSelectEvent)
        }
        // Populates `cachedTotalReport`/`cachedShootingTimeSourceNames` off the main
        // thread — GeneralStatsGrid/PhotoStatsGrid have their own copies of this same
        // fix. `body` (via `hasNoFilteredData`/`selectedReport`/`shootingTimeRow`)
        // never calls the `appState` properties directly, so the first render (and
        // every render right after a stats change) is always cheap.
        // Debounced — see the matching comment in TopEventsPanel.swift.
        .task(id: appState.eventStatsCacheRevision) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await refreshTotalReportAndShootingTimeNames()
        }
        .task(id: "\(appState.dashboardTagFilter?.rawValue ?? "-")|\(appState.dashboardYearFilter.map(String.init) ?? "-")") {
            await refreshTotalReportAndShootingTimeNames()
        }
    }

    private func refreshTotalReportAndShootingTimeNames() async {
        await appState.prewarmStatsReport(forTag: appState.dashboardTagFilter, year: appState.dashboardYearFilter)
        cachedTotalReport = appState.statsReport(forTag: appState.dashboardTagFilter, year: appState.dashboardYearFilter)
        await appState.prewarmDashboardShootingTimeSourceNamesByDay()
        cachedShootingTimeSourceNames = appState.dashboardShootingTimeSourceNamesByDay
    }

    private var shouldRequestLibraryFirst: Bool {
        appState.uniqueImportDestinations.isEmpty
    }

    private var hasImportedEvents: Bool {
        appState.uniqueImportDestinations.contains { destination in
            !appState.isLibraryFolder(at: destination.bookmarkIndex)
                && appState.importStatsForEventFolder(at: destination.bookmarkIndex) != nil
        }
    }

    private var hasDashboardEvents: Bool {
        appState.uniqueImportDestinations.contains { destination in
            !appState.isLibraryFolder(at: destination.bookmarkIndex)
        }
    }

    private var hasActiveDashboardFilter: Bool {
        appState.dashboardTagFilter != nil || appState.dashboardYearFilter != nil
    }

    private var hasNoFilteredData: Bool {
        mode == .total && hasActiveDashboardFilter && cachedTotalReport == nil
    }

    private var noFilteredDataState: some View {
        VStack(spacing: 8) {
            Text("No stats for this filter")
                .font(.sora(18, weight: .bold))
                .foregroundStyle(Color.auroraTxt)
            Text(noFilteredDataSubtitle)
                .font(.manrope(12.5, weight: .medium))
                .foregroundStyle(Color.auroraMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .auroraStaticCard(radius: AuroraRadius.large, paddingH: 0, paddingV: 0)
    }

    private var noFilteredDataSubtitle: String {
        var parts: [String] = []
        if let tag = appState.dashboardTagFilter { parts.append(tag.rawValue) }
        if let year = appState.dashboardYearFilter { parts.append(String(year)) }
        return "No events match \(parts.joined(separator: " · ")). Try another tag or year."
    }

    private var hasActiveDaysData: Bool {
        if selectedReport?.captureTimestampsByDay.isEmpty == false { return true }
        return !appState.filteredImportHistory.isEmpty
    }

    private var dashboardAccessEmptyState: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                IconChip(systemName: "chart.bar.fill", color: .auroraCyan, size: 36, iconScale: 0.52)
                Text("Dashboard")
                    .font(.auroraTopbarH2)
                    .foregroundStyle(Color.auroraTxt)
                Spacer()
            }

            Spacer()

            VStack(alignment: .center, spacing: 18) {
                IconChip(systemName: "folder.badge.plus", color: .auroraMagenta, size: 46, iconScale: 0.5)

                VStack(alignment: .center, spacing: 8) {
                    Text("Add a folder or make an import first")
                        .font(.sora(26, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                        .lineLimit(1)
                    Text("Your Dashboard will appear once Aurora has an event or folder to analyze.")
                        .font(.manrope(13.5, weight: .medium))
                        .foregroundStyle(Color.auroraMuted)
                        .lineLimit(1)
                }

                Button(action: onStartImport) {
                    Label("Add Folder or Make Import", systemImage: "folder.badge.plus")
                }
                .buttonStyle(AuroraGradientButtonStyle(compact: true))
            }
            .padding(28)
            .frame(width: 620, alignment: .center)
            .auroraStaticCard(radius: AuroraRadius.large, paddingH: 0, paddingV: 0)

            Spacer()
        }
        .padding(.horizontal, AuroraSpacing.mainPaddingH)
        .padding(.vertical, AuroraSpacing.mainPaddingV)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // 1 : 1 — Top Events + Latest Events
    private var eventsRow: some View {
        HStack(alignment: .top, spacing: AuroraSpacing.gridGap) {
            TopEventsPanel(appState: appState, onSelect: onSelectEvent, onViewAll: { viewAllSheet = .topEvents(topEventsMetric) }, selectedMetric: $topEventsMetric)
                .frame(maxWidth: .infinity)
            LatestEventsPanel(appState: appState, onSelect: onSelectEvent, onViewAll: { viewAllSheet = .latestEvents })
                .frame(maxWidth: .infinity)
        }
    }

    // 1 : 1 — Top Cameras + Top Lenses
    private var camerasAndLensesRow: some View {
        HStack(alignment: .top, spacing: AuroraSpacing.gridGap) {
            TopCamerasPanel(appState: appState, report: selectedReport, onViewAll: { viewAllSheet = .topCameras(mode) })
                .frame(maxWidth: .infinity)
            TopLensesPanel(appState: appState, report: selectedReport, onViewAll: { viewAllSheet = .topLenses(mode) })
                .frame(maxWidth: .infinity)
        }
    }

    // 1 : 1 — Most RAW Photos + Most Deliverable Photos
    private var chartsRow: some View {
        HStack(alignment: .top, spacing: AuroraSpacing.gridGap) {
            PhotosPerEventChart(appState: appState, onViewAll: { viewAllSheet = .photosPerEvent })
                .frame(maxWidth: .infinity)
            DeliverablesPerEventChart(appState: appState, onViewAll: { viewAllSheet = .deliverablesPerEvent })
                .frame(maxWidth: .infinity)
        }
    }

    // Full width — RAW imports by day/week/month
    private var rawImportsTimelineRow: some View {
        RAWImportsTimelineChart(appState: appState)
    }

    private var shootingTimeRow: some View {
        ShootingTimePanel(
            report: selectedReport,
            title: mode == .lastImport ? "Import Shooting Time" : "Shooting Time",
            subtitle: mode == .lastImport
                ? "Working hours and active shooting time from this import"
                : "Working hours and active shooting time from RAW capture timestamps",
            sourceNamesByDay: mode == .total ? cachedShootingTimeSourceNames : [:]
        )
    }

    private var activeImportDaysRow: some View {
        ActiveImportDaysPanel(report: selectedReport, importHistory: appState.filteredImportHistory, appState: appState)
    }

    private var selectedReport: StatsReport? {
        mode == .lastImport ? appState.statsReport : cachedTotalReport
    }

    // Full width — Photos per Month
    private var photosPerMonthRow: some View {
        PhotosPerMonthChart(appState: appState, onViewAll: { viewAllSheet = .photosPerMonth })
    }
}

enum StatsViewAllSheet: Identifiable {
    case topEvents(TopEventsMetric)
    case latestEvents
    case topCameras(StatsMode)
    case topLenses(StatsMode)
    case photosPerEvent
    case deliverablesPerEvent
    case photosPerMonth

    var id: String {
        switch self {
        case .topEvents(let metric): return "topEvents-\(metric.rawValue)"
        case .latestEvents: return "latestEvents"
        case .topCameras(let mode): return "topCameras-\(mode.id)"
        case .topLenses(let mode): return "topLenses-\(mode.id)"
        case .photosPerEvent: return "photosPerEvent"
        case .deliverablesPerEvent: return "deliverablesPerEvent"
        case .photosPerMonth: return "photosPerMonth"
        }
    }

    var title: String {
        switch self {
        case .topEvents(let metric): return "Top Events per \(metric.rawValue)"
        case .latestEvents: return "Latest Events"
        case .topCameras: return "Top Cameras"
        case .topLenses: return "Top Lenses"
        case .photosPerEvent: return "Most Photos per Event"
        case .deliverablesPerEvent: return "Most Deliverable Photos per Event"
        case .photosPerMonth: return "Most Photos per Month"
        }
    }
}

struct StatsViewAllSheetView: View {
    let kind: StatsViewAllSheet
    @Bindable var appState: AppState
    var onSelectEvent: (Int) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var dateEditor: ManualEventDateEditorState?
    // See the matching comment in TopEventsPanel.swift — `content` below must
    // never call `EventAggregator.build` directly.
    @State private var cachedEvents: [EventAggregate] = []

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(kind.title.uppercased())
                        .font(.auroraSectionLabel)
                        .tracking(1.6)
                        .foregroundStyle(Color.auroraFaint)
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(AuroraGhostButtonStyle())
                }

                ScrollView {
                    VStack(spacing: 4) {
                        content
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(20)
            .frame(minWidth: 560, minHeight: 520)
            .background(Color.auroraBg)
            .background(OutsideSheetClickDismissor { dismiss() })

            if dateEditor != nil {
                Color.black.opacity(0.36)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { dateEditor = nil }
                manualDateEditor
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: dateEditor?.id)
        // Populates `cachedEvents` off the main thread for the `.topEvents`/
        // `.photosPerEvent` sheet kinds — `content` never calls
        // `EventAggregator.build` itself (see the matching comment in
        // TopEventsPanel.swift).
        .task(id: appState.eventStatsCacheRevision) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await refreshEvents()
        }
        .task(id: "\(appState.dashboardTagFilter?.rawValue ?? "-")|\(appState.dashboardYearFilter.map(String.init) ?? "-")") {
            await refreshEvents()
        }
    }

    private func refreshEvents() async {
        await EventAggregator.prewarm(appState: appState, tagFilter: appState.dashboardTagFilter, yearFilter: appState.dashboardYearFilter)
        cachedEvents = EventAggregator.build(appState: appState, tagFilter: appState.dashboardTagFilter, yearFilter: appState.dashboardYearFilter)
    }

    private var manualDateEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual Event Date")
                .font(.manrope(13, weight: .bold))
                .foregroundStyle(Color.auroraTxt)
            HStack {
                Spacer(minLength: 0)
                AuroraManualDatePicker(selection: dateEditorDateBinding)
                    .frame(width: 190)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button("Clear") {
                    if let dateEditor {
                        appState.setManualDateForEvent(at: dateEditor.bookmarkIndex, date: nil)
                    }
                    self.dateEditor = nil
                }
                .buttonStyle(AuroraGhostButtonStyle())
                Spacer()
                Button("Save") {
                    if let dateEditor {
                        appState.setManualDateForEvent(at: dateEditor.bookmarkIndex, date: dateEditor.date)
                    }
                    self.dateEditor = nil
                }
                .buttonStyle(AuroraGradientButtonStyle(compact: true))
            }
        }
        .padding(16)
        .frame(width: 252)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .fill(Color.auroraBg2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke2, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 14)
    }

    private var dateEditorDateBinding: Binding<Date> {
        Binding(
            get: { dateEditor?.date ?? Date() },
            set: { newDate in
                guard var dateEditor else { return }
                dateEditor.date = newDate
                self.dateEditor = dateEditor
            }
        )
    }

    private func openDateEditor(bookmarkIndex: Int, date: Date) {
        dateEditor = ManualEventDateEditorState(bookmarkIndex: bookmarkIndex, date: date)
    }

    private func latestEventSort(
        _ lhs: (path: String, name: String, bookmarkIndex: Int),
        _ rhs: (path: String, name: String, bookmarkIndex: Int)
    ) -> Bool {
        let lhsDate = latestDate(for: lhs)
        let rhsDate = latestDate(for: rhs)
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return lhs.bookmarkIndex > rhs.bookmarkIndex
    }

    private func latestDate(for event: (path: String, name: String, bookmarkIndex: Int)) -> Date {
        appState.effectiveDateForEvent(at: event.bookmarkIndex) ?? .distantPast
    }

    private func bookmarkIndex(for path: String) -> Int? {
        let eventPath = normalize(path)
        return appState.uniqueImportDestinations.first { destination in
            let destinationPath = normalize(destination.path)
            return destinationPath == eventPath
                || destinationPath.hasPrefix(eventPath + "/")
                || eventPath.hasPrefix(destinationPath + "/")
        }?.bookmarkIndex
    }

    private func selectEvent(_ bookmarkIndex: Int) {
        dismiss()
        onSelectEvent(bookmarkIndex)
    }

    private func normalize(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .topEvents(let metric):
            let events = cachedEvents
                .sorted { EventAggregator.sort($0, $1, by: metric) }
                .map { aggregate in
                    LatestEventDisplay(
                        aggregate: aggregate,
                        bookmarkIndex: bookmarkIndex(for: aggregate.id),
                        bannerImagePath: appState.bannerImagePath(forEventPath: aggregate.id)
                    )
            }
            ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                TopEventRow(rank: idx + 1, event: event, metric: metric) {
                    if let bookmarkIndex = event.bookmarkIndex {
                        selectEvent(bookmarkIndex)
                    }
                }
            }
        case .latestEvents:
            let events = appState.uniqueImportDestinations.sorted(by: latestEventSort)
            ForEach(Array(events.enumerated()), id: \.element.bookmarkIndex) { idx, event in
                LatestSidebarOrderRow(rank: idx + 1, event: event, appState: appState) { bookmarkIndex, date in
                    openDateEditor(bookmarkIndex: bookmarkIndex, date: date)
                } onSelect: {
                    selectEvent(event.bookmarkIndex)
                }
            }
        case .topCameras(let mode):
            let cameras = report(for: mode)?.allCameras ?? []
            ForEach(Array(cameras.enumerated()), id: \.offset) { idx, camera in
                TopCameraRow(rank: idx + 1, camera: camera)
            }
        case .topLenses(let mode):
            let lenses = report(for: mode)?.allLenses ?? []
            ForEach(Array(lenses), id: \.id) { lens in
                TopLensRow(lens: lens)
            }
        case .photosPerEvent:
            let events = cachedEvents
                .sorted { $0.totalFiles > $1.totalFiles }
            ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                PhotosPerEventListRow(rank: idx + 1, event: event, appState: appState)
            }
        case .photosPerMonth:
            // Chronological oldest-first (reversed from `photosByMonth`'s newest-first
            // order), unlike the card's top-5-by-volume — this is where a recent,
            // still-low-volume month like the current one (which the top-5-by-count
            // list can drop) always shows up, in reading order from the start.
            let months = appState.photosByMonth.reversed()
            ForEach(Array(months.enumerated()), id: \.element.month) { idx, entry in
                MonthPhotosListRow(rank: idx + 1, month: entry.month, count: entry.count)
            }
        case .deliverablesPerEvent:
            let entries = DeliverablesPerEventChart.deliverableEntries(appState: appState)
                .sorted { $0.jpgCount > $1.jpgCount }
            ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                DeliverableEventListRow(rank: idx + 1, entry: entry, appState: appState)
            }
        }
    }

    private func report(for mode: StatsMode) -> StatsReport? {
        mode == .lastImport ? appState.statsReport : appState.dashboardTotalStatsReport
    }
}

private extension StatsMode {
    var id: String {
        switch self {
        case .lastImport: return "lastImport"
        case .total: return "total"
        }
    }
}

private struct ManualEventDateEditorState: Identifiable, Equatable {
    let id = UUID()
    let bookmarkIndex: Int
    var date: Date
}

private struct LatestSidebarOrderRow: View {
    let rank: Int
    let event: (path: String, name: String, bookmarkIndex: Int)
    @Bindable var appState: AppState
    var onEditDate: (Int, Date) -> Void
    var onSelect: () -> Void = {}

    var body: some View {
        let finalized = appState.finalizedEvent(forBookmarkIndex: event.bookmarkIndex)
        let peak = event.bookmarkIndex < appState.eventFolderPeakRawCounts.count
            ? appState.eventFolderPeakRawCounts[event.bookmarkIndex]
            : 0
        let cached = event.bookmarkIndex < appState.eventFolderCachedCounts.count
            ? max(appState.eventFolderCachedCounts[event.bookmarkIndex], 0)
            : 0
        let summary = appState.importStatsForEventFolder(at: event.bookmarkIndex)
        let totalFiles = max(summary?.photoCount ?? 0, max(finalized?.photoCount ?? 0, max(peak, cached)))
        let displayDate = appState.effectiveDateForEvent(at: event.bookmarkIndex)
        let bannerPath: String? = {
            guard event.bookmarkIndex < appState.eventFolderBannerImagePaths.count else { return nil }
            let path = appState.eventFolderBannerImagePaths[event.bookmarkIndex]
            return path.isEmpty ? nil : path
        }()
        HStack(spacing: 12) {
            RankBadge(rank: rank)
            EventThumbnail(eventName: event.name, bannerImagePath: bannerPath)
                .frame(width: 44, height: 34)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(.auroraEventName)
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onSelect)
                Text(displayDate.map(AuroraFormat.dateCompact) ?? "—")
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
                    .contentShape(Rectangle())
                    .auroraTooltip("Click to set a manual event date")
                    .onTapGesture {
                        onEditDate(event.bookmarkIndex, editableDate())
                    }
            }
            Spacer(minLength: 4)
            SpeedPill(text: AuroraFormat.count(totalFiles), tint: .auroraViolet)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func editableDate() -> Date {
        if let manual = appState.manualDateForEvent(at: event.bookmarkIndex) {
            return manual
        }
        if let effectiveDate = appState.effectiveDateForEvent(at: event.bookmarkIndex) {
            return effectiveDate
        }
        return Date()
    }

}

private struct PhotosPerEventListRow: View {
    let rank: Int
    let event: EventAggregate
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            RankBadge(rank: rank)
            EventThumbnail(
                eventName: event.name,
                bannerImagePath: appState.bannerImagePath(forEventPath: event.id)
            )
            .frame(width: 44, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(.auroraEventName)
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)
                Text(AuroraFormat.dateCompact(event.lastDate))
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
            }
            Spacer(minLength: 4)
            SpeedPill(text: AuroraFormat.count(event.totalFiles), tint: .auroraCyan)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct MonthPhotosListRow: View {
    let rank: Int
    let month: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            RankBadge(rank: rank)
            Text(month)
                .font(.auroraEventName)
                .foregroundStyle(Color.auroraTxt)
            Spacer(minLength: 4)
            SpeedPill(text: AuroraFormat.count(count), tint: .auroraCyan)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct DeliverableEventListRow: View {
    let rank: Int
    let entry: DeliverablesPerEventChart.DeliverableEntry
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            RankBadge(rank: rank)
            EventThumbnail(
                eventName: entry.name,
                bannerImagePath: appState.bannerImagePath(forEventPath: entry.id)
            )
            .frame(width: 44, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.auroraEventName)
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)
                Text(entry.lastDate == .distantPast ? "—" : AuroraFormat.dateCompact(entry.lastDate))
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
            }
            Spacer(minLength: 4)
            SpeedPill(text: AuroraFormat.count(entry.jpgCount), tint: .auroraMagenta)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct OutsideSheetClickDismissor: NSViewRepresentable {
    let onOutsideClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.onOutsideClick = onOutsideClick
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.onOutsideClick = onOutsideClick
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var view: NSView?
        var onOutsideClick: (() -> Void)?
        private var monitor: Any?

        func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self, let sheetWindow = self.view?.window else { return event }
                if event.window !== sheetWindow {
                    DispatchQueue.main.async { self.onOutsideClick?() }
                }
                return event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}
