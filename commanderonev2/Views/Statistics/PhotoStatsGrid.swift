import SwiftUI

struct PhotoStatsGrid: View {
    @Bindable var appState: AppState
    let mode: StatsMode

    // See the matching comment in GeneralStatsGrid.swift/TopEventsPanel.swift —
    // `report` below must never call `appState.dashboardStatsReport` directly.
    @State private var cachedTotalReport: StatsReport?

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: AuroraSpacing.gridGap), count: mode == .lastImport ? 6 : 7),
            spacing: AuroraSpacing.gridGap
        ) {
            PhotoStatCard(icon: "photo.stack.fill", accent: .auroraCyan,
                          pages: photosAddedPages)
            if mode == .total {
                PhotoStatCard(icon: "checkmark.rectangle.stack.fill", accent: .auroraHealthy,
                              pages: photosDeliveredPages)
            }
            PhotoStatCard(icon: "camera.aperture", accent: .auroraBlue,
                          pages: isoPages)
            PhotoStatCard(icon: "circle.dotted", accent: .auroraViolet,
                          pages: aperturePages)
            PhotoStatCard(icon: "viewfinder", accent: .auroraMagenta,
                          pages: focalPages)
            PhotoStatCard(icon: "timer", accent: .auroraPurple,
                          pages: shutterPages)
            PhotoStatCard(icon: "rectangle.portrait.fill", accent: .auroraLive,
                          pages: orientationPages)
        }
        .task(id: appState.eventStatsCacheRevision) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await refreshTotalReport()
        }
        .task(id: "\(appState.dashboardTagFilter?.rawValue ?? "-")|\(appState.dashboardYearFilter.map(String.init) ?? "-")") {
            await refreshTotalReport()
        }
    }

    private func refreshTotalReport() async {
        guard mode == .total else { return }
        await appState.prewarmStatsReport(forTag: appState.dashboardTagFilter, year: appState.dashboardYearFilter)
        cachedTotalReport = appState.statsReport(forTag: appState.dashboardTagFilter, year: appState.dashboardYearFilter)
    }

    private var report: StatsReport? {
        mode == .lastImport ? appState.statsReport : cachedTotalReport
    }

    // MARK: - Pages

    private var photosAdded: String {
        guard let r = report, r.totalFilesAnalyzed > 0 else { return "—" }
        return AuroraFormat.count(r.totalFilesAnalyzed)
    }

    private var photosAddedPages: [(label: String, value: String)] {
        guard let r = report, r.totalFilesAnalyzed > 0 else { return [("Photos Added", "—")] }

        switch mode {
        case .lastImport:
            return [
                ("Photos Added", AuroraFormat.count(r.totalFilesAnalyzed)),
                ("Avg / Import", AuroraFormat.count(r.totalFilesAnalyzed)),
                ("Avg / Day", AuroraFormat.count(r.totalFilesAnalyzed))
            ]
        case .total:
            let history = appState.filteredImportHistory
            guard !history.isEmpty else { return [("Photos Added", AuroraFormat.count(r.totalFilesAnalyzed))] }
            let avgImport = r.totalFilesAnalyzed / max(history.count, 1)
            let days = Set(history.map { Calendar.current.startOfDay(for: $0.date) })
            let avgDay = r.totalFilesAnalyzed / max(days.count, 1)
            return [
                ("Photos Added", AuroraFormat.count(r.totalFilesAnalyzed)),
                ("Avg / Import", AuroraFormat.count(avgImport)),
                ("Avg / Day", AuroraFormat.count(avgDay))
            ]
        }
    }

    private var photosDeliveredPages: [(label: String, value: String)] {
        switch mode {
        case .lastImport:
            return [("Photos Delivered", "—"), ("Keep Rate", "—")]
        case .total:
            let delivered = appState.eventFolderCachedJPGCounts.reduce(0) { $0 + max($1, 0) }
            let rawCount = report?.totalFilesAnalyzed ?? 0
            return [
                ("Photos Delivered", delivered > 0 ? AuroraFormat.count(delivered) : "—"),
                ("Keep Rate", keepRate(delivered: delivered, rawCount: rawCount)),
                ("Avg / Event", deliveredAveragePerEvent(delivered: delivered))
            ]
        }
    }

    private func deliveredAveragePerEvent(delivered: Int) -> String {
        guard delivered > 0 else { return "—" }
        let eventCount = appState.eventFolderCachedJPGCounts.filter { $0 > 0 }.count
        guard eventCount > 0 else { return "—" }
        return AuroraFormat.count(delivered / eventCount)
    }

    private var isoPages: [(label: String, value: String)] {
        guard let r = report else { return [("Avg ISO", "—")] }
        var pages: [(String, String)] = [("Avg ISO", value(r.avgISO, AuroraFormat.iso))]
        if let v = r.maxISO, v > 0 { pages.append(("Highest ISO", AuroraFormat.iso(v))) }
        if let v = r.minISO, v > 0 { pages.append(("Lowest ISO", AuroraFormat.iso(v))) }
        pages.append(("Most Used ISO", value(r.mostUsedISO, AuroraFormat.iso)))
        return pages
    }

    private var aperturePages: [(label: String, value: String)] {
        guard let r = report else { return [("Avg Aperture", "—")] }
        var pages: [(String, String)] = [("Avg Aperture", value(r.avgAperture, AuroraFormat.aperture))]
        if let v = r.maxAperture, v > 0 { pages.append(("Highest Aperture", AuroraFormat.aperture(v))) }
        if let v = r.minAperture, v > 0 { pages.append(("Lowest Aperture", AuroraFormat.aperture(v))) }
        pages.append(("Most Used Aperture", value(r.mostUsedAperture, AuroraFormat.aperture)))
        return pages
    }

    private var focalPages: [(label: String, value: String)] {
        guard let r = report else { return [("Avg Focal", "—")] }
        var pages: [(String, String)] = [("Avg Focal", value(r.avgFocalLength, AuroraFormat.focal))]
        if let v = r.maxFocalLength, v > 0 { pages.append(("Highest Focal", AuroraFormat.focal(v))) }
        if let v = r.minFocalLength, v > 0 { pages.append(("Lowest Focal", AuroraFormat.focal(v))) }
        pages.append(("Most Used Focal", value(r.mostUsedFocalLength, AuroraFormat.focal)))
        return pages
    }

    private var shutterPages: [(label: String, value: String)] {
        guard let r = report else { return [("Avg Shutter", "—")] }
        var pages: [(String, String)] = [("Avg Shutter", value(r.avgShutterSpeed, AuroraFormat.shutter))]
        // For shutter, "fastest" = shorter exposure = smaller seconds → max denominator,
        // "longest" = bigger seconds. Match the human-friendly framing.
        if let v = r.minShutterSpeed, v > 0 { pages.append(("Fastest Shutter", AuroraFormat.shutter(v))) }
        if let v = r.maxShutterSpeed, v > 0 { pages.append(("Longest Shutter", AuroraFormat.shutter(v))) }
        pages.append(("Most Used Shutter", value(r.mostUsedShutterSpeed, AuroraFormat.shutter)))
        return pages
    }

    private var orientationPages: [(label: String, value: String)] {
        guard let r = report, r.portraitCount + r.landscapeCount > 0 else {
            return [("Portraits", "—"), ("Landscapes", "—")]
        }
        return [
            ("Portraits", AuroraFormat.count(r.portraitCount)),
            ("Landscapes", AuroraFormat.count(r.landscapeCount))
        ]
    }

    private func value(_ v: Double?, _ format: (Double) -> String) -> String {
        guard let v = v, v > 0 else { return "—" }
        return format(v)
    }

    private func keepRate(delivered: Int, rawCount: Int) -> String {
        guard delivered > 0, rawCount > 0 else { return "—" }
        return String(format: "%.1f%%", Double(delivered) / Double(rawCount) * 100)
    }
}

// MARK: - Card

struct PhotoStatCard: View {
    let icon: String
    let accent: Color
    let pages: [(label: String, value: String)]

    @State private var index = 0
    @State private var updatePulse = false

    var body: some View {
        let safeIndex = pages.indices.contains(index) ? index : 0
        let page = pages.isEmpty
            ? (label: "—", value: "—")
            : pages[safeIndex]

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IconChip(systemName: icon, color: accent)
                Spacer()
                if pages.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(pages.indices, id: \.self) { i in
                            Circle()
                                .fill(i == safeIndex ? accent : Color.auroraStroke2)
                                .frame(width: 5, height: 5)
                        }
                    }
                }
            }
            Text(page.label)
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraMuted)
            Text(page.value)
                .font(.auroraStatValue)
                .tracking(-0.5)
                .foregroundStyle(Color.auroraTxt)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
        }
        .scaleEffect(updatePulse ? 1.012 : 1.0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .auroraCard()
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.medium, style: .continuous)
                .strokeBorder(updatePulse ? accent.opacity(0.72) : accent.opacity(0.22), lineWidth: updatePulse ? 1.4 : 1)
        )
        .shadow(color: updatePulse ? accent.opacity(0.28) : .clear, radius: updatePulse ? 16 : 0, x: 0, y: 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: updatePulse)
        .animation(.easeInOut(duration: 0.22), value: page.value)
        .onChange(of: page.value) { _, _ in
            pulseUpdate()
        }
        .onTapGesture {
            guard pages.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                index = (safeIndex + 1) % pages.count
            }
        }
    }

    private func pulseUpdate() {
        updatePulse = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            updatePulse = false
        }
    }
}
