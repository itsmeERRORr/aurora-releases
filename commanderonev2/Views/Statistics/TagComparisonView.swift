import SwiftUI

/// Whole Compare section: an empty-state card (matching the "no events yet" card
/// style) with two "Edit tags"-style pickers until both sides are chosen, then the
/// comparison table. Replaces all normal Statistics content while Compare mode is on.
struct CompareSectionView: View {
    @Bindable var appState: AppState
    @Binding var tagA: EventTag?
    @Binding var tagB: EventTag?

    @State private var isPickingA = false
    @State private var isPickingB = false

    var body: some View {
        Group {
            if tagA != nil, tagB != nil {
                TagComparisonView(appState: appState, tagA: $tagA, tagB: $tagB)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            } else {
                pickTagsEmptyState
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: tagA)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: tagB)
    }

    private var pickTagsEmptyState: some View {
        VStack(spacing: 24) {
            IconChip(systemName: "arrow.left.arrow.right", color: .auroraCyan, size: 46, iconScale: 0.5)

            VStack(spacing: 8) {
                Text("Pick two tags to compare")
                    .font(.sora(26, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Text("See what you do differently when shooting one vs the other.")
                    .font(.manrope(13.5, weight: .medium))
                    .foregroundStyle(Color.auroraMuted)
            }

            HStack(spacing: 12) {
                pickerButton(label: tagA?.rawValue ?? "Choose Tag A", tint: tagA?.tint ?? .auroraMuted, hasSelection: tagA != nil, isPresented: $isPickingA) {
                    EventTagSinglePickerView(selectedTag: $tagA, excluding: tagB) {
                        isPickingA = false
                        if tagB == nil {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isPickingB = true
                            }
                        }
                    }
                }
                Text("vs")
                    .font(.manrope(11.5, weight: .bold))
                    .foregroundStyle(Color.auroraFaint)
                pickerButton(label: tagB?.rawValue ?? "Choose Tag B", tint: tagB?.tint ?? .auroraMuted, hasSelection: tagB != nil, isPresented: $isPickingB) {
                    EventTagSinglePickerView(selectedTag: $tagB, excluding: tagA) {
                        isPickingB = false
                    }
                }
            }
        }
        .padding(28)
        .frame(width: 620, alignment: .center)
        .auroraStaticCard(radius: AuroraRadius.large, paddingH: 0, paddingV: 0)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func pickerButton<Content: View>(
        label: String, tint: Color, hasSelection: Bool, isPresented: Binding<Bool>,
        @ViewBuilder popover: @escaping () -> Content
    ) -> some View {
        EditTagButton(label: label, tint: tint, hasSelection: hasSelection, isPresented: isPresented)
            .popover(isPresented: isPresented, arrowEdge: .bottom) { popover() }
    }
}

/// Side-by-side comparison of two tags — "what do I do differently when shooting
/// Sports vs Esports" — instead of duplicating the whole Statistics page per tag.
struct TagComparisonView: View {
    @Bindable var appState: AppState
    @Binding var tagA: EventTag?
    @Binding var tagB: EventTag?

    @State private var isPickingA = false
    @State private var isPickingB = false
    @State private var hasAppeared = false
    @State private var isComputing = false

    // reportA/B and eventsA/B involve combining StatsReports across every matching
    // event (dictionary merges over potentially large per-day timestamp data) — a real
    // per-tag cost of up to a few seconds for big libraries, not just an animation
    // artifact. We cache the result per (tag, year) so switching back to an
    // already-computed tag is instant, and defer the first computation by a tick so
    // SwiftUI can paint a loading state instead of hanging with no feedback.
    private struct ReportCacheEntry {
        let report: StatsReport?
        let events: [EventAggregate]
    }
    @State private var cache: [String: ReportCacheEntry] = [:]
    @State private var reportACache: StatsReport?
    @State private var reportBCache: StatsReport?
    @State private var eventsACache: [EventAggregate] = []
    @State private var eventsBCache: [EventAggregate] = []

    private var yearFilter: Int? { appState.dashboardYearFilter }

    private var reportA: StatsReport? { reportACache }
    private var reportB: StatsReport? { reportBCache }
    private var eventsA: [EventAggregate] { eventsACache }
    private var eventsB: [EventAggregate] { eventsBCache }

    private func cacheKey(for tag: EventTag) -> String {
        "\(tag.rawValue)|\(yearFilter.map(String.init) ?? "all")"
    }

    private func computeEntry(for tag: EventTag) -> ReportCacheEntry {
        let key = cacheKey(for: tag)
        if let cached = cache[key] { return cached }
        let entry = ReportCacheEntry(
            report: appState.statsReport(forTag: tag, year: yearFilter),
            events: EventAggregator.build(appState: appState, tagFilter: tag, yearFilter: yearFilter)
        )
        cache[key] = entry
        return entry
    }

    private func refreshData() {
        guard let tagA, let tagB else { return }
        let keyA = cacheKey(for: tagA)
        let keyB = cacheKey(for: tagB)
        // Already cached — apply immediately, no need to show a loading state.
        if let entryA = cache[keyA], let entryB = cache[keyB] {
            reportACache = entryA.report
            eventsACache = entryA.events
            reportBCache = entryB.report
            eventsBCache = entryB.events
            hasAppeared = false
            withAnimation { hasAppeared = true }
            return
        }
        isComputing = true
        Task { @MainActor in
            // Warms the shared caches (see TopEventsPanel.swift/AppState.swift) off
            // the main thread first — `computeEntry` below still calls
            // `EventAggregator.build`/`statsReport` synchronously on a cache miss,
            // so without this a first-time Compare on a tag no other view has
            // already warmed would still block the main thread for the full
            // per-event disk-read walk.
            async let prewarmA: () = EventAggregator.prewarm(appState: appState, tagFilter: tagA, yearFilter: yearFilter)
            async let prewarmB: () = EventAggregator.prewarm(appState: appState, tagFilter: tagB, yearFilter: yearFilter)
            async let prewarmReportA: () = appState.prewarmStatsReport(forTag: tagA, year: yearFilter)
            async let prewarmReportB: () = appState.prewarmStatsReport(forTag: tagB, year: yearFilter)
            _ = await (prewarmA, prewarmB, prewarmReportA, prewarmReportB)
            let entryA = computeEntry(for: tagA)
            let entryB = computeEntry(for: tagB)
            reportACache = entryA.report
            eventsACache = entryA.events
            reportBCache = entryB.report
            eventsBCache = entryB.events
            isComputing = false
            hasAppeared = false
            withAnimation { hasAppeared = true }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if isComputing {
                loadingState
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row)
                            .opacity(hasAppeared ? 1 : 0)
                            .offset(y: hasAppeared ? 0 : 8)
                            .animation(.easeOut(duration: 0.32).delay(Double(index) * 0.03), value: hasAppeared)
                    }
                }

                if !tips.isEmpty {
                    tipsSection
                }
            }
        }
        .padding(.horizontal, AuroraSpacing.cardPaddingH)
        .padding(.vertical, AuroraSpacing.cardPaddingV)
        .onAppear {
            refreshData()
        }
        .onChange(of: tagA) { _, _ in refreshData() }
        .onChange(of: tagB) { _, _ in refreshData() }
        .onChange(of: appState.dashboardYearFilter) { _, _ in refreshData() }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Crunching the numbers…")
                .font(.manrope(12, weight: .medium))
                .foregroundStyle(Color.auroraMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TIPS")
                .font(.manrope(10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.auroraFaint)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(Array(tips.enumerated()), id: \.element.id) { index, tip in
                    tipCard(tip)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 10)
                        .animation(.easeOut(duration: 0.32).delay(Double(rows.count + index) * 0.03 + 0.1), value: hasAppeared)
                }
            }
        }
        .padding(.top, 6)
    }

    private func tipCard(_ tip: Tip) -> some View {
        HStack(spacing: 12) {
            IconChip(systemName: tip.icon, color: tip.tint, size: 34, iconScale: 0.48)
            VStack(alignment: .leading, spacing: 2) {
                Text(tip.title.uppercased())
                    .font(.manrope(9.5, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(Color.auroraFaint)
                Text(tip.headline)
                    .font(.sora(18, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(tip.detail)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .auroraCard(paddingH: 13, paddingV: 13)
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.medium, style: .continuous)
                .strokeBorder(tip.tint.opacity(0.2), lineWidth: 1)
        )
    }

    private struct Tip: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let title: String
        let headline: String
        let detail: String
        let magnitude: Double
    }

    private var tips: [Tip] {
        guard let tagA, let tagB else { return [] }
        var candidates: [Tip] = []

        if let isoA = reportA?.avgISO, let isoB = reportB?.avgISO, isoA > 0, isoB > 0 {
            let (higherTag, higherVal, lowerTag, lowerVal) = isoA >= isoB ? (tagA, isoA, tagB, isoB) : (tagB, isoB, tagA, isoA)
            let ratio = higherVal / max(lowerVal, 1)
            if ratio > 1.2 {
                candidates.append(Tip(
                    id: "iso", icon: "moon.stars.fill", tint: .auroraViolet, title: "Low Light",
                    headline: "\(AuroraFormat.iso(higherVal)) vs \(AuroraFormat.iso(lowerVal))",
                    detail: "\(higherTag.rawValue) sessions run noticeably darker than \(lowerTag.rawValue).",
                    magnitude: ratio
                ))
            }
        }

        if let apA = reportA?.avgAperture, let apB = reportB?.avgAperture, apA > 0, apB > 0 {
            let (widerTag, widerVal, narrowerTag, narrowerVal) = apA <= apB ? (tagA, apA, tagB, apB) : (tagB, apB, tagA, apA)
            let ratio = narrowerVal / max(widerVal, 0.1)
            if ratio > 1.15 {
                candidates.append(Tip(
                    id: "aperture", icon: "circle.dashed", tint: .auroraCyan, title: "Depth of Field",
                    headline: "\(AuroraFormat.aperture(widerVal)) vs \(AuroraFormat.aperture(narrowerVal))",
                    detail: "\(widerTag.rawValue) shoots wider open than \(narrowerTag.rawValue) — more light, shallower focus.",
                    magnitude: ratio
                ))
            }
        }

        if let shA = reportA?.avgShutterSpeed, let shB = reportB?.avgShutterSpeed, shA > 0, shB > 0 {
            let (fasterTag, fasterVal, slowerTag, slowerVal) = shA <= shB ? (tagA, shA, tagB, shB) : (tagB, shB, tagA, shA)
            let ratio = slowerVal / max(fasterVal, 0.0001)
            if ratio > 1.3 {
                candidates.append(Tip(
                    id: "shutter", icon: "bolt.fill", tint: .auroraMagenta, title: "Shutter Speed",
                    headline: "\(AuroraFormat.shutter(fasterVal)) vs \(AuroraFormat.shutter(slowerVal))",
                    detail: "\(fasterTag.rawValue) freezes far more motion than \(slowerTag.rawValue).",
                    magnitude: ratio
                ))
            }
        }

        let hoursA = avgWorkingHours(eventsA)
        let hoursB = avgWorkingHours(eventsB)
        if hoursA > 0, hoursB > 0 {
            let (longerTag, longerVal, shorterTag, shorterVal) = hoursA >= hoursB ? (tagA, hoursA, tagB, hoursB) : (tagB, hoursB, tagA, hoursA)
            let ratio = longerVal / max(shorterVal, 0.1)
            if ratio > 1.25 {
                candidates.append(Tip(
                    id: "workingHours", icon: "clock.fill", tint: .auroraBlue, title: "Event Length",
                    headline: "\(String(format: "%.1fh", longerVal)) vs \(String(format: "%.1fh", shorterVal))",
                    detail: "\(longerTag.rawValue) events run longer than \(shorterTag.rawValue) on average.",
                    magnitude: ratio
                ))
            }
        }

        let paceA = eventsA.isEmpty ? 0 : Double(reportA?.totalFilesAnalyzed ?? 0) / Double(eventsA.count)
        let paceB = eventsB.isEmpty ? 0 : Double(reportB?.totalFilesAnalyzed ?? 0) / Double(eventsB.count)
        if paceA > 0, paceB > 0 {
            let (heavierTag, heavierVal, lighterTag, lighterVal) = paceA >= paceB ? (tagA, paceA, tagB, paceB) : (tagB, paceB, tagA, paceA)
            let ratio = heavierVal / max(lighterVal, 1)
            if ratio > 1.3 {
                candidates.append(Tip(
                    id: "pace", icon: "flame.fill", tint: .auroraGold, title: "Shooting Pace",
                    headline: "\(String(format: "%.1fx", ratio)) more photos",
                    detail: "You shoot far more per event in \(heavierTag.rawValue) than \(lighterTag.rawValue).",
                    magnitude: ratio
                ))
            }
        }

        if let cameraA = reportA?.mostUsedCamera?.fullName, let cameraB = reportB?.mostUsedCamera?.fullName, cameraA != cameraB {
            candidates.append(Tip(
                id: "camera", icon: "camera.fill", tint: .auroraHealthy, title: "Camera Choice",
                headline: "\(cameraA) → \(cameraB)",
                detail: "\(tagA.rawValue) vs \(tagB.rawValue) go-to camera.",
                magnitude: 1.4
            ))
        }

        if let lensA = reportA?.topLenses.first?.fullName, let lensB = reportB?.topLenses.first?.fullName, lensA != lensB {
            candidates.append(Tip(
                id: "lens", icon: "camera.aperture", tint: .auroraAccent, title: "Lens Choice",
                headline: "\(lensA) → \(lensB)",
                detail: "\(tagA.rawValue) vs \(tagB.rawValue) go-to lens.",
                magnitude: 1.2
            ))
        }

        if !eventsA.isEmpty, !eventsB.isEmpty, eventsA.count != eventsB.count {
            let (moreTag, moreCount, lessTag, lessCount) = eventsA.count >= eventsB.count
                ? (tagA, eventsA.count, tagB, eventsB.count)
                : (tagB, eventsB.count, tagA, eventsA.count)
            let ratio = Double(moreCount) / Double(max(lessCount, 1))
            if ratio > 1.5 {
                candidates.append(Tip(
                    id: "events", icon: "calendar.badge.clock", tint: .auroraLive, title: "Frequency",
                    headline: "\(moreCount) vs \(lessCount) events",
                    detail: "\(moreTag.rawValue) is your busier tag this period.",
                    magnitude: ratio
                ))
            }
        }

        // Orientation mix (portrait vs landscape)
        if let a = reportA, let b = reportB, a.portraitCount + a.landscapeCount > 0, b.portraitCount + b.landscapeCount > 0 {
            let portraitShareA = Double(a.portraitCount) / Double(a.portraitCount + a.landscapeCount)
            let portraitShareB = Double(b.portraitCount) / Double(b.portraitCount + b.landscapeCount)
            let (higherTag, higherVal, lowerTag, lowerVal) = portraitShareA >= portraitShareB
                ? (tagA, portraitShareA, tagB, portraitShareB) : (tagB, portraitShareB, tagA, portraitShareA)
            if higherVal - lowerVal > 0.15 {
                candidates.append(Tip(
                    id: "orientation", icon: "rectangle.portrait.fill", tint: .auroraLive, title: "Orientation",
                    headline: "\(Int((higherVal * 100).rounded()))% vs \(Int((lowerVal * 100).rounded()))% portrait",
                    detail: "\(higherTag.rawValue) leans far more portrait than \(lowerTag.rawValue).",
                    magnitude: (higherVal - lowerVal) * 6
                ))
            }
        }

        // Average file size — proxy for resolution/RAW format differences
        let sizeA = (reportA?.totalFilesAnalyzed ?? 0) > 0 ? Double(reportA!.totalBytes) / Double(reportA!.totalFilesAnalyzed) : 0
        let sizeB = (reportB?.totalFilesAnalyzed ?? 0) > 0 ? Double(reportB!.totalBytes) / Double(reportB!.totalFilesAnalyzed) : 0
        if sizeA > 0, sizeB > 0 {
            let (biggerTag, biggerVal, smallerTag, smallerVal) = sizeA >= sizeB ? (tagA, sizeA, tagB, sizeB) : (tagB, sizeB, tagA, sizeA)
            let ratio = biggerVal / max(smallerVal, 1)
            if ratio > 1.2 {
                let biggerParts = AuroraFormat.bytesParts(Int64(biggerVal))
                let smallerParts = AuroraFormat.bytesParts(Int64(smallerVal))
                candidates.append(Tip(
                    id: "fileSize", icon: "doc.fill", tint: .auroraBlue, title: "RAW File Size",
                    headline: "\(biggerParts.value)\(biggerParts.unit) vs \(smallerParts.value)\(smallerParts.unit)",
                    detail: "\(biggerTag.rawValue) RAWs average noticeably larger than \(smallerTag.rawValue).",
                    magnitude: ratio
                ))
            }
        }

        // Average focal length — wide vs telephoto tendency
        if let focalA = reportA?.avgFocalLength, let focalB = reportB?.avgFocalLength, focalA > 0, focalB > 0 {
            let (longerTag, longerVal, widerTag, widerVal) = focalA >= focalB ? (tagA, focalA, tagB, focalB) : (tagB, focalB, tagA, focalA)
            let ratio = longerVal / max(widerVal, 1)
            if ratio > 1.3 {
                candidates.append(Tip(
                    id: "focal", icon: "camera.metering.spot", tint: .auroraViolet, title: "Focal Length",
                    headline: "\(AuroraFormat.focal(longerVal)) vs \(AuroraFormat.focal(widerVal))",
                    detail: "\(longerTag.rawValue) leans telephoto vs \(widerTag.rawValue)'s wider glass.",
                    magnitude: ratio
                ))
            }
        }

        // ISO range — how variable the lighting conditions are
        if let minA = reportA?.minISO, let maxA = reportA?.maxISO, let minB = reportB?.minISO, let maxB = reportB?.maxISO {
            let rangeA = maxA - minA
            let rangeB = maxB - minB
            if rangeA > 0 || rangeB > 0 {
                let (widerTag, widerVal, narrowerTag, narrowerVal) = rangeA >= rangeB ? (tagA, rangeA, tagB, rangeB) : (tagB, rangeB, tagA, rangeA)
                let ratio = widerVal / max(narrowerVal, 1)
                if ratio > 1.4 {
                    candidates.append(Tip(
                        id: "isoRange", icon: "arrow.up.arrow.down", tint: .auroraGold, title: "ISO Range",
                        headline: "\(AuroraFormat.iso(widerVal)) vs \(AuroraFormat.iso(narrowerVal))",
                        detail: "\(widerTag.rawValue) covers far more varied lighting than \(narrowerTag.rawValue).",
                        magnitude: ratio
                    ))
                }
            }
        }

        // Widest aperture actually used (lowest f-number)
        if let minApA = reportA?.minAperture, let minApB = reportB?.minAperture, minApA > 0, minApB > 0 {
            let (widerTag, widerVal, narrowerTag, narrowerVal) = minApA <= minApB ? (tagA, minApA, tagB, minApB) : (tagB, minApB, tagA, minApA)
            let ratio = narrowerVal / max(widerVal, 0.1)
            if ratio > 1.2 {
                candidates.append(Tip(
                    id: "widestAperture", icon: "aperture", tint: .auroraCyan, title: "Widest Aperture Used",
                    headline: "\(AuroraFormat.aperture(widerVal)) vs \(AuroraFormat.aperture(narrowerVal))",
                    detail: "\(widerTag.rawValue) goes noticeably wider open than \(narrowerTag.rawValue).",
                    magnitude: ratio
                ))
            }
        }

        // Gear variety — distinct cameras used
        if let camerasA = reportA?.cameraCounts.count, let camerasB = reportB?.cameraCounts.count, camerasA != camerasB, camerasA > 0, camerasB > 0 {
            let (moreTag, moreVal, lessTag, lessVal) = camerasA >= camerasB ? (tagA, camerasA, tagB, camerasB) : (tagB, camerasB, tagA, camerasA)
            let ratio = Double(moreVal) / Double(max(lessVal, 1))
            if ratio > 1.4 {
                candidates.append(Tip(
                    id: "cameraVariety", icon: "camera.badge.ellipsis", tint: .auroraHealthy, title: "Camera Variety",
                    headline: "\(moreVal) vs \(lessVal) cameras",
                    detail: "You reach for more gear variety in \(moreTag.rawValue) than \(lessTag.rawValue).",
                    magnitude: ratio
                ))
            }
        }

        // Gear variety — distinct lenses used
        if let lensesA = reportA?.lensCounts.count, let lensesB = reportB?.lensCounts.count, lensesA != lensesB, lensesA > 0, lensesB > 0 {
            let (moreTag, moreVal, lessTag, lessVal) = lensesA >= lensesB ? (tagA, lensesA, tagB, lensesB) : (tagB, lensesB, tagA, lensesA)
            let ratio = Double(moreVal) / Double(max(lessVal, 1))
            if ratio > 1.4 {
                candidates.append(Tip(
                    id: "lensVariety", icon: "camera.aperture", tint: .auroraAccent, title: "Lens Variety",
                    headline: "\(moreVal) vs \(lessVal) lenses",
                    detail: "You rotate through more lenses in \(moreTag.rawValue) than \(lessTag.rawValue).",
                    magnitude: ratio
                ))
            }
        }

        // Seasonal spread — how many distinct months each tag shows activity in
        if let monthsA = reportA?.monthCounts.count, let monthsB = reportB?.monthCounts.count, monthsA != monthsB, monthsA > 0, monthsB > 0 {
            let (broaderTag, broaderVal, narrowerTag, narrowerVal) = monthsA >= monthsB ? (tagA, monthsA, tagB, monthsB) : (tagB, monthsB, tagA, monthsA)
            let ratio = Double(broaderVal) / Double(max(narrowerVal, 1))
            if ratio > 1.5 {
                candidates.append(Tip(
                    id: "seasonSpread", icon: "calendar", tint: .auroraBlue, title: "Season Spread",
                    headline: "\(broaderVal) vs \(narrowerVal) active months",
                    detail: "\(broaderTag.rawValue) happens year-round, \(narrowerTag.rawValue) is more seasonal.",
                    magnitude: ratio
                ))
            }
        }

        // Weekday vs weekend split
        let weekendA = weekendFraction(reportA)
        let weekendB = weekendFraction(reportB)
        if let weekendA, let weekendB {
            let (higherTag, higherVal, lowerTag, lowerVal) = weekendA >= weekendB ? (tagA, weekendA, tagB, weekendB) : (tagB, weekendB, tagA, weekendA)
            if higherVal - lowerVal > 0.15 {
                candidates.append(Tip(
                    id: "weekend", icon: "sun.max.fill", tint: .auroraGold, title: "Weekday vs Weekend",
                    headline: "\(Int((higherVal * 100).rounded()))% vs \(Int((lowerVal * 100).rounded()))% weekend",
                    detail: "\(higherTag.rawValue) happens on weekends far more than \(lowerTag.rawValue).",
                    magnitude: (higherVal - lowerVal) * 6
                ))
            }
        }

        // Day vs night shooting split
        let nightA = nightFraction(reportA)
        let nightB = nightFraction(reportB)
        if let nightA, let nightB {
            let (higherTag, higherVal, lowerTag, lowerVal) = nightA >= nightB ? (tagA, nightA, tagB, nightB) : (tagB, nightB, tagA, nightA)
            if higherVal - lowerVal > 0.15 {
                candidates.append(Tip(
                    id: "nightShooting", icon: "moon.fill", tint: .auroraPurple, title: "Day vs Night",
                    headline: "\(Int((higherVal * 100).rounded()))% vs \(Int((lowerVal * 100).rounded()))% at night",
                    detail: "\(higherTag.rawValue) skews far more toward night shooting than \(lowerTag.rawValue).",
                    magnitude: (higherVal - lowerVal) * 6
                ))
            }
        }

        // Pace per working hour (distinct from pace per event)
        let hourPaceA = hoursA > 0 ? Double(reportA?.totalFilesAnalyzed ?? 0) / hoursA : 0
        let hourPaceB = hoursB > 0 ? Double(reportB?.totalFilesAnalyzed ?? 0) / hoursB : 0
        if hourPaceA > 0, hourPaceB > 0 {
            let (fasterTag, fasterVal, slowerTag, slowerVal) = hourPaceA >= hourPaceB ? (tagA, hourPaceA, tagB, hourPaceB) : (tagB, hourPaceB, tagA, hourPaceA)
            let ratio = fasterVal / max(slowerVal, 1)
            if ratio > 1.3 {
                candidates.append(Tip(
                    id: "hourlyPace", icon: "speedometer", tint: .auroraMagenta, title: "Shots per Hour",
                    headline: "\(AuroraFormat.count(Int(fasterVal))) vs \(AuroraFormat.count(Int(slowerVal)))/h",
                    detail: "\(fasterTag.rawValue) keeps a much faster shooting pace than \(slowerTag.rawValue).",
                    magnitude: ratio
                ))
            }
        }

        return candidates.sorted { $0.magnitude > $1.magnitude }.prefix(6).map { $0 }
    }

    /// Fraction of captured photos taken on a Saturday or Sunday.
    private func weekendFraction(_ report: StatsReport?) -> Double? {
        let timestamps = allTimestamps(report)
        guard !timestamps.isEmpty else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let weekendCount = timestamps.filter {
            let weekday = calendar.component(.weekday, from: Date(timeIntervalSince1970: $0))
            return weekday == 1 || weekday == 7
        }.count
        return Double(weekendCount) / Double(timestamps.count)
    }

    /// Fraction of captured photos taken before 6am or after 8pm.
    private func nightFraction(_ report: StatsReport?) -> Double? {
        let timestamps = allTimestamps(report)
        guard !timestamps.isEmpty else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let nightCount = timestamps.filter {
            let hour = calendar.component(.hour, from: Date(timeIntervalSince1970: $0))
            return hour < 6 || hour >= 20
        }.count
        return Double(nightCount) / Double(timestamps.count)
    }

    private func allTimestamps(_ report: StatsReport?) -> [Double] {
        guard let report else { return [] }
        return report.captureTimestampsByDay.values.flatMap { $0 }
    }

    private var header: some View {
        HStack(spacing: 0) {
            tagHeader(tagA, emptyNote: eventsA.isEmpty, excluding: tagB, isPresented: $isPickingA) { tagA = $0 }
                .frame(maxWidth: .infinity, alignment: .center)
            Text("vs")
                .font(.manrope(11.5, weight: .bold))
                .foregroundStyle(Color.auroraFaint)
                .padding(.horizontal, 12)
            tagHeader(tagB, emptyNote: eventsB.isEmpty, excluding: tagA, isPresented: $isPickingB) { tagB = $0 }
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func tagHeader(
        _ tag: EventTag?, emptyNote: Bool, excluding: EventTag?,
        isPresented: Binding<Bool>, onPick: @escaping (EventTag) -> Void
    ) -> some View {
        let tint = tag?.tint ?? Color.auroraMuted
        return VStack(spacing: 6) {
            Button {
                isPresented.wrappedValue = true
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                        .shadow(color: tint.opacity(tag != nil ? 0.9 : 0), radius: 5)
                    Text(tag?.rawValue ?? "Choose tag")
                        .font(.sora(15.5, weight: .bold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .opacity(0.55)
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(tint.opacity(tag != nil ? 0.14 : 0.06))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [tint.opacity(tag != nil ? 0.75 : 0.3), tint.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1.3
                        )
                )
                .shadow(color: tint.opacity(tag != nil ? 0.32 : 0), radius: 14, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .popover(isPresented: isPresented, arrowEdge: .bottom) {
                EventTagSinglePickerView(
                    selectedTag: Binding(get: { tag }, set: { if let newTag = $0 { onPick(newTag) } }),
                    excluding: excluding
                ) {
                    isPresented.wrappedValue = false
                }
            }

            if emptyNote, let tag {
                Text("No events tagged \(tag.rawValue)\(yearFilter.map { " in \($0)" } ?? "")")
                    .font(.manrope(10.5, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Rows

    private struct Row: Identifiable {
        let id: String
        let label: String
        let valueA: String
        let valueB: String
        let winner: Winner
        var prefixA: String? = nil
        var prefixB: String? = nil
        var suffixA: String? = nil
        var suffixB: String? = nil
    }

    private enum Winner { case none, a, b }

    private var rows: [Row] {
        [
            numericRow(
                id: "raws", label: "Total RAWs",
                a: Double(reportA?.totalFilesAnalyzed ?? 0), b: Double(reportB?.totalFilesAnalyzed ?? 0),
                format: { AuroraFormat.count(Int($0)) }
            ),
            numericRow(
                id: "bytes", label: "Data Transferred",
                a: Double(reportA?.totalBytes ?? 0), b: Double(reportB?.totalBytes ?? 0),
                format: { bytes in
                    let parts = AuroraFormat.bytesParts(Int64(bytes))
                    return "\(parts.value) \(parts.unit)"
                }
            ),
            nameWithCountRow(
                id: "camera", label: "Top Camera",
                a: reportA?.mostUsedCamera.map { ($0.fullName, $0.count) },
                b: reportB?.mostUsedCamera.map { ($0.fullName, $0.count) }
            ),
            nameWithCountRow(
                id: "lens", label: "Top Lens",
                a: reportA?.topLenses.first.map { ($0.fullName, $0.count) },
                b: reportB?.topLenses.first.map { ($0.fullName, $0.count) }
            ),
            numericRow(
                id: "iso", label: "Avg ISO",
                a: reportA?.avgISO ?? 0, b: reportB?.avgISO ?? 0,
                format: AuroraFormat.iso, lowerIsBetter: true
            ),
            numericRow(
                id: "aperture", label: "Avg Aperture",
                a: reportA?.avgAperture ?? 0, b: reportB?.avgAperture ?? 0,
                format: AuroraFormat.aperture, lowerIsBetter: true
            ),
            numericRow(
                id: "shutter", label: "Avg Shutter",
                a: reportA?.avgShutterSpeed ?? 0, b: reportB?.avgShutterSpeed ?? 0,
                format: AuroraFormat.shutter, lowerIsBetter: true
            ),
            numericRow(
                id: "workingHours", label: "Avg Work Hours",
                a: avgWorkingHours(eventsA), b: avgWorkingHours(eventsB),
                format: { String(format: "%.1fh", $0) }
            ),
            comparableRow(
                id: "busiestDay", label: "Busiest Day",
                a: Double(reportA?.shootingTimeMetrics?.busiestPhotoDay?.photoCount ?? 0),
                b: Double(reportB?.shootingTimeMetrics?.busiestPhotoDay?.photoCount ?? 0),
                textA: busiestDayCount(reportA), textB: busiestDayCount(reportB),
                prefixA: busiestDayPrefix(reportA), prefixB: busiestDayPrefix(reportB),
                suffixA: busiestDaySuffix(reportA, events: eventsA), suffixB: busiestDaySuffix(reportB, events: eventsB)
            ),
            numericRow(
                id: "events", label: "Events",
                a: Double(eventsA.count), b: Double(eventsB.count),
                format: { AuroraFormat.count(Int($0)) }
            )
        ]
    }

    private func numericRow(id: String, label: String, a: Double, b: Double, format: (Double) -> String, lowerIsBetter: Bool = false) -> Row {
        var winner: Winner = a == b ? .none : (a > b ? .a : .b)
        if lowerIsBetter, winner != .none {
            winner = winner == .a ? .b : .a
        }
        return Row(id: id, label: label, valueA: format(a), valueB: format(b), winner: a > 0 || b > 0 ? winner : .none)
    }

    private func infoRow(id: String, label: String, a: String, b: String) -> Row {
        Row(id: id, label: label, valueA: a, valueB: b, winner: .none)
    }

    /// Name + photo count row (Top Camera / Top Lens): the count renders as a
    /// lighter-weight suffix so the camera/lens name stays the visual focus.
    private func nameWithCountRow(id: String, label: String, a: (name: String, count: Int)?, b: (name: String, count: Int)?) -> Row {
        Row(
            id: id, label: label,
            valueA: a?.name ?? "—", valueB: b?.name ?? "—",
            winner: .none,
            suffixA: a.map { " with \(AuroraFormat.count($0.count)) photos" },
            suffixB: b.map { " with \(AuroraFormat.count($0.count)) photos" }
        )
    }

    /// Like `numericRow`, but the displayed text is supplied separately from the
    /// number used to decide the winner (e.g. Busiest Day: compares photo count,
    /// but shows the date + event name).
    private func comparableRow(
        id: String, label: String, a: Double, b: Double, textA: String, textB: String,
        prefixA: String? = nil, prefixB: String? = nil, suffixA: String? = nil, suffixB: String? = nil
    ) -> Row {
        let winner: Winner = a == b ? .none : (a > b ? .a : .b)
        return Row(
            id: id, label: label, valueA: textA, valueB: textB, winner: a > 0 || b > 0 ? winner : .none,
            prefixA: prefixA, prefixB: prefixB, suffixA: suffixA, suffixB: suffixB
        )
    }

    private func avgWorkingHours(_ events: [EventAggregate]) -> Double {
        guard !events.isEmpty else { return 0 }
        let totalSeconds = events.reduce(0) { $0 + $1.totalWorkingSeconds }
        return (totalSeconds / Double(events.count)) / 3600
    }

    /// Bold part of the Busiest Day row: the photo count (the "win" that matters most).
    private func busiestDayCount(_ report: StatsReport?) -> String {
        guard let day = report?.shootingTimeMetrics?.busiestPhotoDay else { return "—" }
        return AuroraFormat.count(day.photoCount)
    }

    private func busiestDayPrefix(_ report: StatsReport?) -> String? {
        guard let day = report?.shootingTimeMetrics?.busiestPhotoDay else { return nil }
        return "\(formattedDayKey(day.dayKey)) with "
    }

    private func busiestDaySuffix(_ report: StatsReport?, events: [EventAggregate]) -> String? {
        guard let day = report?.shootingTimeMetrics?.busiestPhotoDay else { return nil }
        let eventName = events.first {
            appState.eventStatsReport(forBookmarkIndex: $0.bookmarkIndex)?.shootingTimeMetrics?.busiestPhotoDay?.dayKey == day.dayKey
        }?.name ?? "—"
        return " photos @ \(eventName)"
    }

    private func formattedDayKey(_ dayKey: String) -> String {
        guard let date = Self.dayKeyFormatter.date(from: dayKey) else { return dayKey }
        return Self.displayDateFormatter.string(from: date)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter
    }()

    private enum ValueState { case winner, loser, neutral }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        let stateA: ValueState = row.winner == .a ? .winner : (row.winner == .b ? .loser : .neutral)
        let stateB: ValueState = row.winner == .b ? .winner : (row.winner == .a ? .loser : .neutral)
        HStack(spacing: 0) {
            valueView(row.valueA, prefix: row.prefixA, suffix: row.suffixA, state: stateA)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(row.label)
                .font(.manrope(12.5, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
                .frame(width: 160)
                .multilineTextAlignment(.center)
            valueView(row.valueB, prefix: row.prefixB, suffix: row.suffixB, state: stateB)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }

    private func valueView(_ value: String, prefix: String?, suffix: String?, state: ValueState) -> some View {
        let color: Color = {
            switch state {
            case .winner: return .auroraCyan
            case .loser: return .auroraMagenta
            case .neutral: return .auroraMuted
            }
        }()
        var text = Text(value)
            .font(.sora(13, weight: state == .neutral ? .semibold : .bold))
            .foregroundStyle(color)
        if let prefix {
            text = Text(prefix)
                .font(.manrope(12, weight: .medium))
                .foregroundStyle(color.opacity(0.75))
                + text
        }
        if let suffix {
            text = text + Text(suffix)
                .font(.manrope(12, weight: .medium))
                .foregroundStyle(color.opacity(0.75))
        }
        return text.lineLimit(1)
    }
}
