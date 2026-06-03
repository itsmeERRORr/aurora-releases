import SwiftUI

struct PhotosPerEventChart: View {
    @Bindable var appState: AppState
    var onViewAll: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Most RAW Photos per Event", actionLabel: "View all →", action: onViewAll)

            let top = topEvents()
            if top.count < 3 {
                empty
            } else {
                ChartCanvas(events: top)
                    .frame(minHeight: 232)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .auroraStaticCard()
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text("Need at least 3 events")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            Text("Import more events to see the curve.")
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// Picks 3 events to plot: highest at the centre, then the 2nd and 3rd
    /// distributed left/right by lastDate (oldest left, newest right).
    private func topEvents() -> [EventAggregate] {
        let all = EventAggregator.build(appState: appState)
            .sorted { $0.totalFiles > $1.totalFiles }
            .prefix(3)
        guard all.count == 3 else { return Array(all) }
        let peak = all[0]
        let others = [all[1], all[2]].sorted { $0.lastDate < $1.lastDate }
        return [others[0], peak, others[1]]
    }
}

private struct ChartCanvas: View {
    let events: [EventAggregate]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let topInset: CGFloat = 50    // room for value text + badge
            let bottomInset: CGFloat = 36 // room for event names
            let drawingHeight = h - topInset - bottomInset

            let xs: [CGFloat] = events.indices.map { i in
                let frac: CGFloat = events.count == 1 ? 0.5 : CGFloat(i) / CGFloat(events.count - 1)
                return frac * (w - 80) + 40
            }
            let maxV = max(CGFloat(events.map(\.totalFiles).max() ?? 1), 1)
            let ys: [CGFloat] = events.map { e in
                let frac = CGFloat(e.totalFiles) / maxV
                return topInset + drawingHeight * (1 - frac * 0.95)
            }
            let points = zip(xs, ys).map { CGPoint(x: $0, y: $1) }

            ZStack(alignment: .topLeading) {
                // Area + line
                Canvas { ctx, _ in
                    guard points.count >= 2 else { return }
                    let line = smoothPath(points: points)
                    var area = line
                    area.addLine(to: CGPoint(x: points.last!.x, y: h - bottomInset))
                    area.addLine(to: CGPoint(x: points.first!.x, y: h - bottomInset))
                    area.closeSubpath()

                    let areaShading = GraphicsContext.Shading.linearGradient(
                        Gradient(colors: [Color.auroraAccent.opacity(0.32), .clear]),
                        startPoint: CGPoint(x: 0, y: topInset),
                        endPoint: CGPoint(x: 0, y: h - bottomInset)
                    )
                    ctx.fill(area, with: areaShading)

                    let lineShading = GraphicsContext.Shading.linearGradient(
                        Gradient(colors: [.auroraCyan, .auroraViolet, .auroraMagenta]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: w, y: 0)
                    )
                    ctx.stroke(line, with: lineShading, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }

                // Badges + labels
                ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                    nodeLabel(event: event,
                              rank: rankFor(idx: idx),
                              x: xs[idx], y: ys[idx], h: h, bottomInset: bottomInset)
                }
            }
        }
    }

    /// Centre is peak (rank 1), left = silver (2), right = bronze (3).
    private func rankFor(idx: Int) -> Int {
        switch (events.count, idx) {
        case (3, 1): return 1 // peak
        case (3, 0): return 2 // left
        case (3, 2): return 3 // right
        default: return idx + 1
        }
    }

    private func nodeLabel(event: EventAggregate, rank: Int, x: CGFloat, y: CGFloat, h: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(AuroraFormat.count(event.totalFiles))
                .font(.sora(15, weight: .bold))
                .foregroundStyle(Color.auroraTxt)
            RankBadge(rank: rank, size: 32)
        }
        .position(x: x, y: y - 16)
        .overlay(
            Text(event.name)
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraMuted)
                .lineLimit(1)
                .frame(maxWidth: 200)
                .position(x: x, y: h - bottomInset + 14)
        )
    }

    private func smoothPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        let alpha: CGFloat = 0.5
        for i in 0..<(points.count - 1) {
            let p0 = i == 0 ? points[0] : points[i - 1]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) * alpha / 3.0,
                             y: p1.y + (p2.y - p0.y) * alpha / 3.0)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) * alpha / 3.0,
                             y: p2.y - (p3.y - p1.y) * alpha / 3.0)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

// MARK: - Deliverables per Event

struct DeliverablesPerEventChart: View {
    @Bindable var appState: AppState
    var onViewAll: () -> Void = {}

    struct DeliverableEntry: Identifiable {
        let id: String      // event folder path
        let name: String
        let jpgCount: Int
        let lastDate: Date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Most Deliverable Photos per Event", actionLabel: "View all →", action: onViewAll)

            let entries = Self.deliverableEntries(appState: appState)
            if appState.isRefreshingEventFolders && entries.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.75)
                    Text("Counting deliverables…")
                        .font(.manrope(12, weight: .medium))
                        .foregroundStyle(Color.auroraFaint)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
            } else {
                let top = topEntries(from: entries)
                if top.count < 3 {
                    emptyView
                } else {
                    DeliverableChartCanvas(entries: top)
                        .frame(minHeight: 232)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .auroraStaticCard()
        .task { appState.refreshEventFolderMediaCounts() }
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Text("Need at least 3 events with JPG files")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            Text("JPG deliverables in event folders will appear here.")
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    @MainActor
    static func deliverableEntries(appState: AppState) -> [DeliverableEntry] {
        appState.uniqueImportDestinations.compactMap { destination in
            guard destination.bookmarkIndex < appState.eventFolderCachedJPGCounts.count else { return nil }
            let count = max(appState.eventFolderCachedJPGCounts[destination.bookmarkIndex], 0)
            guard count > 0 else { return nil }
            let lastDate = appState.importStatsForEventFolder(at: destination.bookmarkIndex)?.lastDate
                ?? appState.finalizedEvent(forBookmarkIndex: destination.bookmarkIndex)?.lastImportDate
                ?? .distantPast
            return DeliverableEntry(
                id: destination.path,
                name: destination.name,
                jpgCount: count,
                lastDate: lastDate
            )
        }
    }

    private func topEntries(from entries: [DeliverableEntry]) -> [DeliverableEntry] {
        let sorted = entries.sorted { $0.jpgCount > $1.jpgCount }
        let top3 = Array(sorted.prefix(3))
        guard top3.count == 3 else { return top3 }
        let peak = top3[0]
        let others = [top3[1], top3[2]].sorted { $0.lastDate < $1.lastDate }
        return [others[0], peak, others[1]]
    }
}

private struct DeliverableChartCanvas: View {
    let entries: [DeliverablesPerEventChart.DeliverableEntry]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let topInset: CGFloat = 50
            let bottomInset: CGFloat = 56
            let horizontalInset: CGFloat = 40
            let labelWidth: CGFloat = min(190, max(130, (w - 40) / 3.1))
            let drawingHeight = h - topInset - bottomInset

            let xs: [CGFloat] = entries.indices.map { i in
                let frac: CGFloat = entries.count == 1 ? 0.5 : CGFloat(i) / CGFloat(entries.count - 1)
                return frac * (w - horizontalInset * 2) + horizontalInset
            }
            let maxV = max(CGFloat(entries.map(\.jpgCount).max() ?? 1), 1)
            let ys: [CGFloat] = entries.map { e in
                let frac = CGFloat(e.jpgCount) / maxV
                return topInset + drawingHeight * (1 - frac * 0.95)
            }
            let points = zip(xs, ys).map { CGPoint(x: $0, y: $1) }

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    guard points.count >= 2 else { return }
                    let line = smoothPath(points: points)
                    var area = line
                    area.addLine(to: CGPoint(x: points.last!.x, y: h - bottomInset))
                    area.addLine(to: CGPoint(x: points.first!.x, y: h - bottomInset))
                    area.closeSubpath()

                    ctx.fill(area, with: .linearGradient(
                        Gradient(colors: [Color.auroraViolet.opacity(0.28), .clear]),
                        startPoint: CGPoint(x: 0, y: topInset),
                        endPoint: CGPoint(x: 0, y: h - bottomInset)
                    ))
                    ctx.stroke(line, with: .linearGradient(
                        Gradient(colors: [.auroraViolet, .auroraMagenta, .auroraLive]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: w, y: 0)
                    ), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }

                ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                    nodeLabel(entry: entry, rank: rank(for: entry),
                              x: xs[idx], y: ys[idx], h: h, bottomInset: bottomInset, labelWidth: labelWidth, chartWidth: w)
                }
            }
        }
    }

    private func rank(for entry: DeliverablesPerEventChart.DeliverableEntry) -> Int {
        entries
            .sorted { $0.jpgCount > $1.jpgCount }
            .firstIndex { $0.id == entry.id }
            .map { $0 + 1 } ?? 1
    }

    private func nodeLabel(entry: DeliverablesPerEventChart.DeliverableEntry, rank: Int,
                           x: CGFloat, y: CGFloat, h: CGFloat, bottomInset: CGFloat, labelWidth: CGFloat, chartWidth: CGFloat) -> some View {
        let labelX = min(max(x, labelWidth / 2), max(labelWidth / 2, chartWidth - labelWidth / 2))
        return VStack(spacing: 4) {
            Text(AuroraFormat.count(entry.jpgCount))
                .font(.sora(15, weight: .bold))
                .foregroundStyle(Color.auroraTxt)
            RankBadge(rank: rank, size: 32)
        }
        .position(x: x, y: y - 16)
        .overlay(
            Text(entry.name)
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraMuted)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(width: labelWidth)
                .multilineTextAlignment(.center)
                .position(x: labelX, y: h - bottomInset + 24)
        )
    }

    private func smoothPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        let alpha: CGFloat = 0.5
        for i in 0..<(points.count - 1) {
            let p0 = i == 0 ? points[0] : points[i - 1]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) * alpha / 3.0,
                             y: p1.y + (p2.y - p0.y) * alpha / 3.0)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) * alpha / 3.0,
                             y: p2.y - (p3.y - p1.y) * alpha / 3.0)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}
