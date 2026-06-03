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
            }
            .padding(.horizontal, AuroraSpacing.mainPaddingH)
            .padding(.vertical, AuroraSpacing.mainPaddingV)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $viewAllSheet) { sheet in
            StatsViewAllSheetView(kind: sheet, appState: appState)
        }
    }

    // 1 : 1 — Top Events + Latest Events
    private var eventsRow: some View {
        HStack(alignment: .top, spacing: AuroraSpacing.gridGap) {
            TopEventsPanel(appState: appState, onViewAll: { viewAllSheet = .topEvents })
                .frame(maxWidth: .infinity)
            LatestEventsPanel(appState: appState, onViewAll: { viewAllSheet = .latestEvents })
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
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
                        bannerImagePath: appState.bannerImagePath(forEventPath: aggregate.id)
                    )
                }
            ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                TopEventRow(rank: idx + 1, event: event) {}
            }
        case .latestEvents:
            ForEach(Array(appState.uniqueImportDestinations.enumerated()), id: \.element.bookmarkIndex) { idx, event in
                LatestSidebarOrderRow(rank: idx + 1, event: event, appState: appState)
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

private struct LatestSidebarOrderRow: View {
    let rank: Int
    let event: (path: String, name: String, bookmarkIndex: Int)
    @Bindable var appState: AppState

    var body: some View {
        let summary = appState.importStatsForEventFolder(at: event.bookmarkIndex)
        let bannerPath: String? = {
            guard event.bookmarkIndex < appState.eventFolderBannerImagePaths.count else { return nil }
            let path = appState.eventFolderBannerImagePaths[event.bookmarkIndex]
            return path.isEmpty ? nil : path
        }()
        HStack(spacing: 12) {
            RankBadge(rank: rank)
            EventThumbnail(eventName: event.name, folderPath: event.path, bannerImagePath: bannerPath)
                .frame(width: 44, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(.auroraEventName)
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)
                Text(summary?.lastDate.map(AuroraFormat.dateCompact) ?? "—")
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
            }
            Spacer(minLength: 4)
            SpeedPill(text: AuroraFormat.count(summary?.photoCount ?? 0), tint: .auroraViolet)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
