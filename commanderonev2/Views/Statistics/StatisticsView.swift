import SwiftUI
import AppKit

struct StatisticsView: View {
    @Bindable var appState: AppState
    let statsRunner: StatsRunner?
    var onSelectEvent: (Int) -> Void = { _ in }

    @State private var mode: StatsMode = .total
    @State private var viewAllSheet: StatsViewAllSheet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatisticsTopbar(mode: $mode)

                GeneralStatsGrid(appState: appState, mode: mode)

                HeroEventCard(appState: appState, onViewEvent: onSelectEvent)

                PhotoStatsGrid(appState: appState, mode: mode)

                camerasAndLensesRow

                eventsRow

                chartsRow

                photosPerMonthRow

                rawImportsTimelineRow
            }
            .padding(.horizontal, AuroraSpacing.mainPaddingH)
            .padding(.vertical, AuroraSpacing.mainPaddingV)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $viewAllSheet) { sheet in
            StatsViewAllSheetView(kind: sheet, appState: appState, onSelectEvent: onSelectEvent)
        }
    }

    // 1 : 1 — Top Events + Latest Events
    private var eventsRow: some View {
        HStack(alignment: .top, spacing: AuroraSpacing.gridGap) {
            TopEventsPanel(appState: appState, onSelect: onSelectEvent, onViewAll: { viewAllSheet = .topEvents })
                .frame(maxWidth: .infinity)
            LatestEventsPanel(appState: appState, onSelect: onSelectEvent, onViewAll: { viewAllSheet = .latestEvents })
                .frame(maxWidth: .infinity)
        }
    }

    // 1 : 1 — Top Cameras + Top Lenses
    private var camerasAndLensesRow: some View {
        HStack(alignment: .top, spacing: AuroraSpacing.gridGap) {
            TopCamerasPanel(appState: appState, onViewAll: { viewAllSheet = .topCameras })
                .frame(maxWidth: .infinity)
            TopLensesPanel(appState: appState, onViewAll: { viewAllSheet = .topLenses })
                .frame(maxWidth: .infinity)
        }
    }

    // 1 : 1 — Most RAW Photos + Most Deliverable Photos
    private var chartsRow: some View {
        GeometryReader { geo in
            let gap = AuroraSpacing.gridGap
            let unit = (geo.size.width - gap) / 2
            HStack(alignment: .top, spacing: gap) {
                PhotosPerEventChart(appState: appState, onViewAll: { viewAllSheet = .photosPerEvent })
                    .frame(width: unit)
                DeliverablesPerEventChart(appState: appState, onViewAll: { viewAllSheet = .deliverablesPerEvent })
                    .frame(width: unit)
            }
        }
        .frame(minHeight: 360)
    }

    // Full width — RAW imports by day/week/month
    private var rawImportsTimelineRow: some View {
        RAWImportsTimelineChart(appState: appState)
    }

    // Full width — Photos per Month
    private var photosPerMonthRow: some View {
        PhotosPerMonthChart(appState: appState)
    }
}

enum StatsViewAllSheet: String, Identifiable {
    case topEvents
    case latestEvents
    case topCameras
    case topLenses
    case photosPerEvent
    case deliverablesPerEvent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topEvents: return "Top Events"
        case .latestEvents: return "Latest Events"
        case .topCameras: return "Top Cameras"
        case .topLenses: return "Top Lenses"
        case .photosPerEvent: return "Most Photos per Event"
        case .deliverablesPerEvent: return "Most Deliverable Photos per Event"
        }
    }
}

struct StatsViewAllSheetView: View {
    let kind: StatsViewAllSheet
    @Bindable var appState: AppState
    var onSelectEvent: (Int) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var dateEditor: ManualEventDateEditorState?

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
        case .topEvents:
            let events = EventAggregator.build(appState: appState)
                .sorted(by: EventAggregator.sortByPhotoCount)
                .map { aggregate in
                    LatestEventDisplay(
                        aggregate: aggregate,
                        bookmarkIndex: bookmarkIndex(for: aggregate.id),
                        bannerImagePath: appState.bannerImagePath(forEventPath: aggregate.id)
                    )
                }
            ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                TopEventRow(rank: idx + 1, event: event) {
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
        case .topCameras:
            let cameras = appState.totalStatsReport?.allCameras ?? []
            ForEach(Array(cameras.enumerated()), id: \.offset) { idx, camera in
                TopCameraRow(rank: idx + 1, camera: camera)
            }
        case .topLenses:
            let lenses = appState.totalStatsReport?.allLenses ?? []
            ForEach(Array(lenses), id: \.id) { lens in
                TopLensRow(lens: lens)
            }
        case .photosPerEvent:
            let events = EventAggregator.build(appState: appState)
                .sorted { $0.totalFiles > $1.totalFiles }
            ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                PhotosPerEventListRow(rank: idx + 1, event: event, appState: appState)
            }
        case .deliverablesPerEvent:
            let entries = DeliverablesPerEventChart.deliverableEntries(appState: appState)
                .sorted { $0.jpgCount > $1.jpgCount }
            ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                DeliverableEventListRow(rank: idx + 1, entry: entry, appState: appState)
            }
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
            EventThumbnail(eventName: event.name, folderPath: event.path, bannerImagePath: bannerPath)
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
                    .help("Click to set a manual event date")
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
                folderPath: event.id,
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

private struct DeliverableEventListRow: View {
    let rank: Int
    let entry: DeliverablesPerEventChart.DeliverableEntry
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            RankBadge(rank: rank)
            EventThumbnail(
                eventName: entry.name,
                folderPath: entry.id,
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
