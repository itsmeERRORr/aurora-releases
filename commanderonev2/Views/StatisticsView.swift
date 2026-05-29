import SwiftUI

struct StatisticsView: View {
    @Bindable var appState: AppState
    let statsRunner: StatsRunner?
    @State private var showAllLenses = false
    @State private var showAllCameras = false
    @State private var selectedStatsTab: StatsTab = .total
    @State private var showAllEventFolders = false
    // eventFolderResults and isRefreshingEventFolders live in AppState so they survive navigation.

    enum StatsTab {
        case lastImport
        case total
    }

    private var currentReport: StatsReport? {
        selectedStatsTab == .lastImport ? appState.statsReport : appState.totalStatsReport
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard

                if let report = currentReport {
                    statsContent(for: report)
                } else {
                    emptyState
                }
            }
            .padding(.top, 28)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .onAppear {
            // Only populate from cache on first appear; results persist in AppState across navigation.
            if appState.eventFolderResults.isEmpty {
                populateFromCache()
            }
        }
        .onChange(of: appState.importState) { old, new in
            if new == .idle && (old == .done || old == .ejectingDone || old == .generatingStats) {
                refreshEventFolderResults(onlyIfOverlapsDestination: true)
            }
        }
    }

    private var headerCard: some View {
        HStack {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(
                    LinearGradient(colors: [Color.importBlue, Color.importCyan], startPoint: .top, endPoint: .bottom)
                )
                .font(.system(size: 24, weight: .bold))
            Text("Import Statistics")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)

            // Reset button (only for Total tab)
            if selectedStatsTab == .total && appState.totalStatsReport != nil {
                Button {
                    showResetAlert()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(IconButtonStyle())
            }

            Spacer()

            // Tab selector inline with header
            Picker("", selection: $selectedStatsTab) {
                Text("Last Import").tag(StatsTab.lastImport)
                Text("Total").tag(StatsTab.total)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .tint(Color.importBlue)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }


    @ViewBuilder
    private func statsContent(for report: StatsReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryCards(for: report)

            latestEventHero(for: report)

            sectionLabel("PHOTO STATISTICS")
            photoStatsCards(for: report)

            HStack(alignment: .top, spacing: 16) {
                topEventsPanel
                    .frame(maxWidth: .infinity)
                latestImportsPanel
                    .frame(maxWidth: .infinity)
                featuredEventsPanel
                    .frame(maxWidth: .infinity)
            }

            HStack(alignment: .top, spacing: 16) {
                if !appState.photosByMonth.isEmpty {
                    monthlyPhotosChart(data: appState.photosByMonth)
                        .frame(maxWidth: .infinity)
                }
                eventFoldersCard
                    .frame(maxWidth: .infinity)
            }

            HStack(alignment: .top, spacing: 16) {
                if !report.allCameras.isEmpty {
                    topCamerasSection(cameras: report.allCameras, total: report.totalFilesAnalyzed)
                        .frame(maxWidth: .infinity)
                }

                if !report.allLenses.isEmpty {
                    topLensesSection(report: report)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Sorted by RAW count descending; (originalIndex, name, count, offline, path). Count = max(current, peak) so deleting files doesn't reduce it.
    private var sortedEventFolders: [(originalIndex: Int, name: String, count: Int, offline: Bool, path: String)] {
        appState.eventFolderBookmarks.enumerated().compactMap { index, _ in
            let r = appState.eventFolderResults[index]
            let custom = index < appState.eventFolderDisplayNames.count ? appState.eventFolderDisplayNames[index] : ""
            let resultName = r?.name ?? ""
            let name = custom.isEmpty ? (resultName.isEmpty ? "…" : resultName) : custom
            let peak = index < appState.eventFolderPeakRawCounts.count ? appState.eventFolderPeakRawCounts[index] : 0
            let rawCount = r?.count ?? -1
            // If still loading (r == nil), show -1. If offline with cache, show cache (>= 0). Otherwise max with peak.
            let count: Int
            if r == nil {
                count = -1 // still loading
            } else if rawCount < 0 {
                count = -1 // offline with no cache
            } else {
                count = max(rawCount, peak)
            }
            let path = index < appState.eventFolderCachedPaths.count ? appState.eventFolderCachedPaths[index] : ""
            return (originalIndex: index, name: name, count: count, offline: r?.offline ?? false, path: path)
        }.sorted { a, b in
            // Folders with valid counts before offline/loading ones
            if a.count < 0 && b.count >= 0 { return false }
            if a.count >= 0 && b.count < 0 { return true }
            return a.count > b.count
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(4)
            .foregroundColor(.textSecondary)
            .padding(.top, 2)
    }

    @ViewBuilder
    private func latestEventHero(for report: StatsReport) -> some View {
        let event = sortedEventFolders.first
        let title = event?.name ?? appState.uniqueImportDestinations.first?.name ?? "Latest Event"
        let rawCount = event?.count ?? report.totalFilesAnalyzed
        let importDate = appState.importHistory.first?.date ?? report.firstImportDate

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("LATEST EVENT")
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    Text(importDate.map { heroDateFormatter.string(from: $0) } ?? "Recent import")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textSecondary)

                    Text("Cached import statistics, RAW counts and metadata ready for offline viewing.")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)

                    Button {
                    } label: {
                        Label("View Event", systemImage: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    .background(
                        LinearGradient(colors: [Color.importBlue, Color.importPurple], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)

                ZStack(alignment: .bottomTrailing) {
                    eventGradient(index: 0)
                        .overlay(
                            LinearGradient(colors: [.black.opacity(0.08), .black.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Text("●  Cached")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(14)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(minHeight: 205)

            Divider().overlay(Color.importBorder)

            HStack(spacing: 0) {
                heroMetric(icon: "photo.on.rectangle", value: "\(max(rawCount, 0).formatted())", label: "RAW Files")
                heroMetric(icon: "externaldrive", value: formatBytes(report.totalBytes), label: "Data Imported")
                heroMetric(icon: "speedometer", value: formatSpeed(report.averageSpeed), label: "Avg Speed")
                heroMetric(icon: "calendar", value: importDate.map { compactDateFormatter.string(from: $0) } ?? "N/A", label: "Last Imported")
            }
        }
        .dashboardPanel(cornerRadius: 18)
    }

    private func heroMetric(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.importBlue)
                .frame(width: 34, height: 34)
                .background(Color.importBlue.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlay(Rectangle().fill(Color.importBorder).frame(width: 1), alignment: .trailing)
    }

    private var topEventsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader("TOP EVENTS")
            ForEach(Array(sortedEventFolders.prefix(4).enumerated()), id: \.element.originalIndex) { index, item in
                eventListRow(rank: index + 1, name: item.name, detail: "\(max(item.count, 0).formatted()) RAW files", accent: eventGradient(index: index))
            }
        }
        .dashboardPanel()
    }

    private var latestImportsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader("LATEST EVENT IMPORTS")
            ForEach(Array(appState.importHistory.prefix(4).enumerated()), id: \.element.id) { index, entry in
                eventListRow(
                    rank: nil,
                    name: URL(fileURLWithPath: entry.destinationPath).lastPathComponent,
                    detail: "\(entry.fileCount.formatted()) files  ·  \(formatBytes(entry.totalBytes))",
                    accent: eventGradient(index: index + 2)
                )
            }
            if appState.importHistory.isEmpty {
                Text("No recent imports yet")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .padding(.vertical, 18)
            }
        }
        .dashboardPanel()
    }

    private var featuredEventsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader("FEATURED EVENTS")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(sortedEventFolders.prefix(4).enumerated()), id: \.element.originalIndex) { index, item in
                    VStack(alignment: .leading, spacing: 7) {
                        eventGradient(index: index + 4)
                            .frame(height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Text(item.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                        Text("\(max(item.count, 0).formatted()) RAW files")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.importBorder, lineWidth: 1))
                }
            }
        }
        .dashboardPanel()
    }

    private func panelHeader(_ title: String) -> some View {
        HStack {
            sectionLabel(title)
            Spacer()
            Text("View all")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.importBlue)
        }
    }

    private func eventListRow(rank: Int?, name: String, detail: String, accent: LinearGradient) -> some View {
        HStack(spacing: 12) {
            if let rank {
                Text("\(rank)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(rank == 1 ? .black : .white)
                    .frame(width: 22, height: 22)
                    .background(rank == 1 ? Color.yellow : Color.white.opacity(0.16), in: Circle())
            }

            accent
                .frame(width: 62, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.importBorder, lineWidth: 1))
    }

    private func eventGradient(index: Int) -> LinearGradient {
        let palettes: [[Color]] = [
            [Color(hex: "0B5DFF"), Color(hex: "FF315F")],
            [Color(hex: "2246D2"), Color(hex: "00C2B8")],
            [Color(hex: "FF8A1C"), Color(hex: "7C3AED")],
            [Color(hex: "0EA5E9"), Color(hex: "2563EB")],
            [Color(hex: "EF4444"), Color(hex: "1D4ED8")]
        ]
        let colors = palettes[index % palettes.count]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var heroDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    private var compactDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    @State private var editingEventFolderIndex: Int? = nil
    @State private var editingDraftName: String = ""
    @State private var hoveredEventIndex: Int? = nil

    @ViewBuilder
    private var eventFoldersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MOST PHOTOS PER EVENT")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(4)
                    .foregroundColor(.textPrimary)
                Spacer()
                if !appState.eventFolderBookmarks.isEmpty && sortedEventFolders.count > 3 {
                    Button(showAllEventFolders ? "Less" : "More") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllEventFolders.toggle()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .buttonStyle(.plain)
                }
                if !appState.eventFolderBookmarks.isEmpty {
                    Button {
                        refreshEventFolderResults()
                    } label: {
                        if appState.isRefreshingEventFolders {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.textSecondary)
                    .disabled(appState.isRefreshingEventFolders)
                }
                Button {
                    addEventFolder()
                } label: {
                    Label("Add folder", systemImage: "folder.badge.plus")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.primaryPurple)
            }

            if appState.eventFolderBookmarks.isEmpty {
                Text("Add a folder (e.g. event) to count RAW files inside it and all subfolders.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                let total = sortedEventFolders.map(\.count).filter { $0 > 0 }.reduce(0, +)
                if total > 0 {
                    Text("Total: \(total) RAW files")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }

                HStack(spacing: -20) {
                    if sortedEventFolders.count >= 2 {
                        eventFolderCard(originalIndex: sortedEventFolders[1].originalIndex, name: sortedEventFolders[1].name, count: sortedEventFolders[1].count, rank: 2, offline: sortedEventFolders[1].offline, path: sortedEventFolders[1].path, hoveredEventIndex: $hoveredEventIndex, editingEventFolderIndex: $editingEventFolderIndex, editingDraftName: $editingDraftName)
                    }
                    if sortedEventFolders.count >= 1 {
                        eventFolderCard(originalIndex: sortedEventFolders[0].originalIndex, name: sortedEventFolders[0].name, count: sortedEventFolders[0].count, rank: 1, offline: sortedEventFolders[0].offline, path: sortedEventFolders[0].path, hoveredEventIndex: $hoveredEventIndex, editingEventFolderIndex: $editingEventFolderIndex, editingDraftName: $editingDraftName)
                    }
                    if sortedEventFolders.count >= 3 {
                        eventFolderCard(originalIndex: sortedEventFolders[2].originalIndex, name: sortedEventFolders[2].name, count: sortedEventFolders[2].count, rank: 3, offline: sortedEventFolders[2].offline, path: sortedEventFolders[2].path, hoveredEventIndex: $hoveredEventIndex, editingEventFolderIndex: $editingEventFolderIndex, editingDraftName: $editingDraftName)
                    }
                }

                if showAllEventFolders {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sortedEventFolders, id: \.originalIndex) { item in
                            eventFolderListRow(item: item)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .dashboardPanel()
        .onChange(of: appState.eventFolderBookmarks.count) { _, _ in refreshEventFolderResults() }
    }

    @ViewBuilder
    private func eventFolderCard(originalIndex: Int, name: String, count: Int, rank: Int, offline: Bool, path: String, hoveredEventIndex: Binding<Int?>, editingEventFolderIndex: Binding<Int?>, editingDraftName: Binding<String>) -> some View {
        let medal = rank == 1 ? "🥇" : (rank == 2 ? "🥈" : "🥉")
        let removeOnLeft = (rank == 2) // 2nd place: button on left so it isn't covered by 1st card
        let isEditing = editingEventFolderIndex.wrappedValue == originalIndex
        VStack(spacing: 8) {
            HStack {
                if removeOnLeft {
                    Button {
                        appState.removeEventFolder(at: originalIndex)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if offline {
                    Image(systemName: "wifi.slash")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                }
                if !removeOnLeft {
                    Button {
                        appState.removeEventFolder(at: originalIndex)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(medal)
                .font(.system(size: 48))
            eventFolderNameView(originalIndex: originalIndex, name: name, isEditing: isEditing, hoveredEventIndex: hoveredEventIndex, editingEventFolderIndex: editingEventFolderIndex, editingDraftName: editingDraftName, font: .system(size: 16, weight: .semibold))
            if appState.eventFolderScanningIndices.contains(originalIndex) {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.55)
                        .tint(Color.primaryPurple)
                    Text("Scanning…")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                }
            } else if count >= 0 {
                Text("\(count) RAW files")
                    .font(.caption)
                    .foregroundColor(offline ? .textSecondary.opacity(0.6) : .textSecondary)
                if offline {
                    Text("Last seen")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary.opacity(0.5))
                }
            } else {
                Text(offline ? "Disk offline" : "Counting…")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.glassBase)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.glassBorder, lineWidth: 1)
        )
        .zIndex(rank == 1 ? 10 : Double(4 - rank))
        .scaleEffect(rank == 1 ? 1.05 : 1.0)
        .modifier(HoverScaleEffect())
    }

    @ViewBuilder
    private func eventFolderNameView(originalIndex: Int, name: String, isEditing: Bool, hoveredEventIndex: Binding<Int?>, editingEventFolderIndex: Binding<Int?>, editingDraftName: Binding<String>, font: Font) -> some View {
        Group {
            if isEditing {
                TextField("Event name", text: editingDraftName)
                    .textFieldStyle(.roundedBorder)
                    .font(font)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .onSubmit {
                        appState.setEventFolderDisplayName(at: originalIndex, name: editingDraftName.wrappedValue)
                        editingEventFolderIndex.wrappedValue = nil
                    }
            } else {
                HStack(spacing: 6) {
                    Text(name)
                        .font(font)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .opacity(hoveredEventIndex.wrappedValue == originalIndex ? 1 : 0)
                }
                .frame(maxWidth: .infinity)
                .onHover { hovering in
                    hoveredEventIndex.wrappedValue = hovering ? originalIndex : nil
                }
                .onTapGesture {
                    editingEventFolderIndex.wrappedValue = originalIndex
                    editingDraftName.wrappedValue = name
                }
            }
        }
    }

    @ViewBuilder
    private func eventFolderListRow(item: (originalIndex: Int, name: String, count: Int, offline: Bool, path: String)) -> some View {
        let isEditing = editingEventFolderIndex == item.originalIndex
        HStack(spacing: 12) {
            if isEditing {
                TextField("Event name", text: $editingDraftName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit {
                        appState.setEventFolderDisplayName(at: item.originalIndex, name: editingDraftName)
                        editingEventFolderIndex = nil
                    }
                Text(item.count >= 0 ? "\(item.count) RAW files" : "Counting…")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Spacer()
                Button {
                    appState.setEventFolderDisplayName(at: item.originalIndex, name: editingDraftName)
                    editingEventFolderIndex = nil
                } label: {
                    Text("OK")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.primaryPurple)
            } else {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                        .opacity(hoveredEventIndex == item.originalIndex ? 1 : 0)
                }
                .onHover { hovering in
                    hoveredEventIndex = hovering ? item.originalIndex : nil
                }
                .onTapGesture {
                    editingEventFolderIndex = item.originalIndex
                    editingDraftName = item.name
                }
                Spacer()
                if item.offline {
                    Image(systemName: "wifi.slash")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                }
                if appState.eventFolderScanningIndices.contains(item.originalIndex) {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.55)
                            .tint(Color.primaryPurple)
                        Text("Scanning…")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                } else {
                    Group {
                        if item.count >= 0 {
                            Text("\(item.count)" + (item.offline ? " (cached)" : " RAW files"))
                        } else {
                            Text(item.offline ? "Disk offline" : "Counting…")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                }
                Button {
                    appState.removeEventFolder(at: item.originalIndex)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func addEventFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose an event folder (RAW count will include all subfolders)"
        if panel.runModal() == .OK, let url = panel.url,
           let bookmarkData = BookmarkManager.saveBookmark(for: url) {
            appState.addEventFolder(bookmark: bookmarkData)
            let newIndex = appState.eventFolderBookmarks.count - 1
            // Auto-scan the newly added folder in the background.
            // Only set the scanning indicator if we actually have a runner to scan with.
            if let runner = statsRunner {
                appState.eventFolderScanningIndices.insert(newIndex)
                Task {
                    let report = await runner.runStatsForEventFolder(at: url)
                    await MainActor.run {
                        if let report = report {
                            EventStatsCache.save(report, forPath: url.path)
                            appState.updateEventFolderCache(at: newIndex, count: report.totalFilesAnalyzed, path: url.path)
                        }
                        appState.eventFolderScanningIndices.remove(newIndex)
                    }
                }
            }
        }
    }

    /// Instant: populate from persisted cache with zero I/O. Called on first appear.
    private func populateFromCache() {
        guard !appState.eventFolderBookmarks.isEmpty else { return }
        let cachedCounts = appState.eventFolderCachedCounts
        let cachedPaths = appState.eventFolderCachedPaths
        let displayNames = appState.eventFolderDisplayNames
        var results: [Int: AppState.EventFolderResult] = [:]
        for index in appState.eventFolderBookmarks.indices {
            let cachedCount = index < cachedCounts.count ? cachedCounts[index] : -1
            let cachedPath = index < cachedPaths.count ? cachedPaths[index] : ""
            let customName = index < displayNames.count ? displayNames[index] : ""
            let folderName = cachedPath.isEmpty ? "…" : URL(fileURLWithPath: cachedPath).lastPathComponent
            let name = customName.isEmpty ? folderName : customName
            results[index] = AppState.EventFolderResult(name: name, count: cachedCount, offline: cachedCount < 0)
        }
        appState.eventFolderResults = results
    }

    /// Full rescan — only called manually (refresh button) or after an import.
    private func refreshEventFolderResults(onlyIfOverlapsDestination: Bool = false) {
        guard !appState.isRefreshingEventFolders else { return }
        appState.isRefreshingEventFolders = true
        let bookmarks = appState.eventFolderBookmarks
        let extensions = appState.supportedExtensions
        let cachedCounts = appState.eventFolderCachedCounts
        let cachedPaths = appState.eventFolderCachedPaths
        let destinationPath = appState.destinationURL?.path ?? ""
        Task {
            var results = appState.eventFolderResults // Start from current state to avoid flicker
            for (index, data) in bookmarks.enumerated() {
                // Smart refresh: skip folders that don't overlap with the destination
                if onlyIfOverlapsDestination && !destinationPath.isEmpty {
                    let cachedPath = index < cachedPaths.count ? cachedPaths[index] : ""
                    let folderPath = cachedPath.isEmpty ? "" : cachedPath
                    // Check if destination is inside this folder or vice versa
                    let overlaps = !folderPath.isEmpty && (
                        destinationPath.hasPrefix(folderPath) || folderPath.hasPrefix(destinationPath)
                    )
                    if !overlaps {
                        // Keep existing result unchanged, no need to rescan
                        continue
                    }
                }

                if let url = BookmarkManager.resolveBookmark(data) {
                    let name = url.lastPathComponent
                    let accessing = BookmarkManager.startAccessing(url)
                    let count = VolumeWatcher.countRawFiles(at: url, extensions: extensions, modifiedOnOrAfter: nil)
                    if accessing { BookmarkManager.stopAccessing(url) }
                    results[index] = AppState.EventFolderResult(name: name, count: count, offline: false)
                    await MainActor.run {
                        appState.setEventFolderPeakIfHigher(at: index, count: count)
                        appState.updateEventFolderCache(at: index, count: count, path: url.path)
                    }
                } else {
                    // Bookmark resolution failed — try cached path as fallback (NAS/network volumes
                    // may fail to resolve the bookmark after sleep/wake or remount)
                    let cachedPath = index < cachedPaths.count ? cachedPaths[index] : ""
                    let cachedURL = cachedPath.isEmpty ? nil : URL(fileURLWithPath: cachedPath)
                    if let fallbackURL = cachedURL,
                       (try? fallbackURL.checkResourceIsReachable()) ?? false {
                        let name = fallbackURL.lastPathComponent
                        let count = VolumeWatcher.countRawFiles(at: fallbackURL, extensions: extensions, modifiedOnOrAfter: nil)
                        results[index] = AppState.EventFolderResult(name: name, count: count, offline: false)
                        await MainActor.run {
                            appState.setEventFolderPeakIfHigher(at: index, count: count)
                            appState.updateEventFolderCache(at: index, count: count, path: fallbackURL.path)
                        }
                    } else {
                        // Truly offline — use cached count
                        let cachedCount = index < cachedCounts.count ? cachedCounts[index] : -1
                        let name = cachedPath.isEmpty ? "Unavailable" : URL(fileURLWithPath: cachedPath).lastPathComponent
                        results[index] = AppState.EventFolderResult(name: name, count: cachedCount, offline: true)
                    }
                }
            }
            await MainActor.run {
                appState.eventFolderResults = results
                appState.isRefreshingEventFolders = false
            }
        }
    }

    /// Derives the number of days since the first known import, calculated from import history.
    /// importHistory is stored newest-first, so .last is the oldest entry.
    /// Falls back to firstImportDate from StatsReport if history is unavailable.
    private func daySpan(for report: StatsReport) -> Int? {
        guard selectedStatsTab == .total, report.importCount > 1 else { return nil }
        let firstDate = appState.importHistory.last?.date ?? report.firstImportDate
        guard let date = firstDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        return max(days, 1)
    }

    /// Per-import averages calculated directly from import history (more accurate than report totals).
    private var historyAvgPhotosPerImport: Int? {
        guard selectedStatsTab == .total,
              !appState.importHistory.isEmpty else { return nil }
        let total = appState.importHistory.reduce(0) { $0 + $1.fileCount }
        return total / appState.importHistory.count
    }

    private var historyAvgBytesPerImport: Int64? {
        guard selectedStatsTab == .total,
              !appState.importHistory.isEmpty else { return nil }
        let total = appState.importHistory.reduce(Int64(0)) { $0 + $1.totalBytes }
        return total / Int64(appState.importHistory.count)
    }

    @ViewBuilder
    private func summaryCards(for report: StatsReport) -> some View {
        let days = daySpan(for: report)
        let isTotal = selectedStatsTab == .total

        HStack(spacing: 16) {
            StackableStatCard(
                cards: {
                    var items = [StackableStatCard.CardData(title: "Data Transferred", value: formatBytes(report.totalBytes))]
                    if let avg = historyAvgBytesPerImport {
                        items.append(.init(title: "Avg / Import", value: formatBytes(avg)))
                    }
                    if let d = days {
                        items.append(.init(title: "Avg / Day", value: formatBytes(report.totalBytes / Int64(d))))
                    }
                    return items
                }(),
                icon: "arrow.down.to.line.compact",
                color: Color.accentGreen
            )

            StatCard(
                title: "Avg Speed",
                value: formatSpeed(report.averageSpeed),
                icon: "bolt.fill",
                color: Color.importAmber
            )

            StackableStatCard(
                cards: {
                    var items = [StackableStatCard.CardData(title: "Time Wasted Importing", value: formatDuration(report.totalDuration))]
                    if isTotal && report.importCount > 1 {
                        items.append(.init(title: "Avg / Import", value: formatDuration(report.totalDuration / report.importCount)))
                    }
                    return items
                }(),
                icon: "clock",
                color: Color.importOrange
            )

            StackableStatCard(
                cards: {
                    var items = [StackableStatCard.CardData(title: "Total Imports", value: "\(report.importCount)")]
                    if let d = days {
                        let avgPerDay = Double(report.importCount) / Double(d)
                        items.append(.init(title: "Avg / Day", value: String(format: "%.1f", avgPerDay)))
                    }
                    return items
                }(),
                icon: "square.and.arrow.down",
                color: Color.importBlue
            )
        }
    }

    @ViewBuilder
    private func photoStatsCards(for report: StatsReport) -> some View {
        let days = daySpan(for: report)

        HStack(spacing: 16) {
            StackableStatCard(
                cards: {
                    var items = [StackableStatCard.CardData(title: "Photos Added", value: "\(report.totalFilesAnalyzed)")]
                    if let avg = historyAvgPhotosPerImport {
                        items.append(.init(title: "Avg / Import", value: "\(avg)"))
                    }
                    if let d = days {
                        let avgPerDay = Double(report.totalFilesAnalyzed) / Double(d)
                        items.append(.init(title: "Avg / Day", value: String(format: "%.0f", avgPerDay)))
                    }
                    return items
                }(),
                icon: "photo.on.rectangle.angled",
                color: Color.importBlue
            )

            if let iso = report.avgISO {
                let cards: [StackableStatCard.CardData] = {
                    var items: [StackableStatCard.CardData] = [
                        StackableStatCard.CardData(title: "Avg ISO", value: String(format: "%.0f", iso))
                    ]

                    if let maxISO = report.maxISO {
                        items.append(.init(title: "Highest ISO", value: String(format: "%.0f", maxISO)))
                    }

                    if let minISO = report.minISO {
                        items.append(.init(title: "Lowest ISO", value: String(format: "%.0f", minISO)))
                    }

                    return items
                }()

                StackableStatCard(cards: cards, icon: "camera.aperture", color: Color.importCyan)
            }

            if let aperture = report.avgAperture, aperture > 0 {
                let cards: [StackableStatCard.CardData] = {
                    var items: [StackableStatCard.CardData] = [
                        StackableStatCard.CardData(title: "Avg Aperture", value: String(format: "f/%.1f", aperture))
                    ]

                    if let maxAperture = report.maxAperture, maxAperture > 0 {
                        items.append(.init(title: "Highest Aperture", value: String(format: "f/%.1f", maxAperture)))
                    }

                    if let minAperture = report.minAperture, minAperture > 0 {
                        items.append(.init(title: "Lowest Aperture", value: String(format: "f/%.1f", minAperture)))
                    } else {
                        items.append(.init(title: "Lowest Aperture", value: "N/A"))
                    }

                    return items
                }()

                StackableStatCard(cards: cards, icon: "camera.aperture", color: Color.importBlue)
            }

            if let focal = report.avgFocalLength, focal > 0 {
                let cards: [StackableStatCard.CardData] = {
                    var items: [StackableStatCard.CardData] = [
                        StackableStatCard.CardData(title: "Avg Focal", value: String(format: "%.0fmm", focal))
                    ]

                    if let maxFocal = report.maxFocalLength, maxFocal > 0 {
                        items.append(.init(title: "Highest Focal", value: String(format: "%.0fmm", maxFocal)))
                    }

                    if let minFocal = report.minFocalLength, minFocal > 0 {
                        items.append(.init(title: "Lowest Focal", value: String(format: "%.0fmm", minFocal)))
                    } else {
                        items.append(.init(title: "Lowest Focal", value: "N/A"))
                    }

                    return items
                }()

                StackableStatCard(cards: cards, icon: "scope", color: Color.importPink)
            }

            if let shutter = report.avgShutterSpeed {
                let cards: [StackableStatCard.CardData] = {
                    var items: [StackableStatCard.CardData] = [
                        StackableStatCard.CardData(title: "Avg Shutter", value: formatShutterSpeed(shutter))
                    ]

                    if let minShutter = report.minShutterSpeed {
                        items.append(.init(title: "Highest Shutter", value: formatShutterSpeed(minShutter)))
                    }

                    if let maxShutter = report.maxShutterSpeed {
                        items.append(.init(title: "Lowest Shutter", value: formatShutterSpeed(maxShutter)))
                    }

                    return items
                }()

                StackableStatCard(cards: cards, icon: "clock", color: Color.importPurple)
            }
                }
    }

    @ViewBuilder
    private func topLensesSection(report: StatsReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Lenses")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)

                Spacer()

                if report.allLenses.count > 3 {
                    Button(showAllLenses ? "Less" : "More") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllLenses.toggle()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .buttonStyle(.plain)
                }
            }

            let podium = Array(report.allLenses.prefix(3))
            HStack(spacing: -20) {
                // Reorganizar: 2º lugar (esquerda), 1º lugar (meio), 3º lugar (direita)
                if podium.count >= 2 {
                    lensCard(lens: podium[1], total: report.totalFilesAnalyzed)
                }
                if podium.count >= 1 {
                    lensCard(lens: podium[0], total: report.totalFilesAnalyzed)
                }
                if podium.count >= 3 {
                    lensCard(lens: podium[2], total: report.totalFilesAnalyzed)
                }
            }

            if showAllLenses {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(report.allLenses) { lens in
                        statListRow(
                            title: lens.fullName,
                            value: "\(lens.count) photos"
                        )
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassPanel()
    }

    @ViewBuilder
    private func lensCard(lens: StatsReport.LensStat, total: Int) -> some View {
        VStack(spacing: 8) {
            // Medal icon (sem fundo)
            Text(lens.medal)
                .font(.system(size: 48))

            // Lens name
            Text(lens.fullName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)

            // Photo count
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
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.glassBorder, lineWidth: 1)
        )
        .zIndex(lens.rank == 1 ? 10 : Double(4 - lens.rank))
        .scaleEffect(lens.rank == 1 ? 1.05 : 1.0)
        .modifier(HoverScaleEffect())
    }

    @ViewBuilder
    private func topCamerasSection(cameras: [StatsReport.CameraStat], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Cameras")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)

                Spacer()

                if cameras.count > 3 {
                    Button(showAllCameras ? "Less" : "More") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllCameras.toggle()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: -20) {
                // Reorganizar: 2º lugar (esquerda), 1º lugar (meio), 3º lugar (direita)
                if cameras.count >= 2 {
                    cameraCard(camera: cameras[1], total: total, rank: 2)
                }
                if cameras.count >= 1 {
                    cameraCard(camera: cameras[0], total: total, rank: 1)
                }
                if cameras.count >= 3 {
                    cameraCard(camera: cameras[2], total: total, rank: 3)
                }
            }

            if showAllCameras {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(cameras, id: \.fullName) { cam in
                        statListRow(
                            title: friendlyCameraName(for: cam.model),
                            value: "\(cam.count) photos"
                        )
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassPanel()
    }

    private func statListRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func cameraCard(camera: StatsReport.CameraStat, total: Int, rank: Int) -> some View {
        VStack(spacing: 8) {
            // Medal icon (sem fundo)
            Text(rank == 1 ? "🥇" : rank == 2 ? "🥈" : "🥉")
                .font(.system(size: 48))

            // Camera name (com mapeamento)
            Text(friendlyCameraName(for: camera.model))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // Photo count
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
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.glassBorder, lineWidth: 1)
        )
        .zIndex(rank == 1 ? 10 : Double(4 - rank))
        .scaleEffect(rank == 1 ? 1.05 : 1.0)
        .modifier(HoverScaleEffect())
    }

    // Mapeamento de nomes de câmeras
    private func friendlyCameraName(for model: String) -> String {
        let mappings: [String: String] = [
            "ILCE-7M4": "Sony A7 IV",
            "ILCE-1M2": "Sony A1 II",
            "ILCE-9M3": "Sony A9 III"
        ]

        return mappings[model] ?? model
    }

    @ViewBuilder
    private func shutterSpeedSection(report: StatsReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shutter Speed Distribution")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.textPrimary)

            let shutters = Array(report.shutterSpeeds.prefix(10))
            ForEach(shutters) { shutter in
                shutterRow(shutter: shutter, total: report.totalFilesAnalyzed)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassPanel()
    }

    @ViewBuilder
    private func shutterRow(shutter: StatsReport.ShutterStat, total: Int) -> some View {
        HStack {
            Text(shutter.fractionString)
                .font(.mono(12))
                .foregroundColor(.textPrimary)
                .frame(width: 100, alignment: .leading)
            ProgressView(value: Double(shutter.count), total: Double(total))
                .tint(Color.primaryPurple)
            Text("\(shutter.count)")
                .font(.caption)
                .foregroundColor(.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func monthlyPhotosChart(data: [(month: String, count: Int)]) -> some View {
        MonthlyChartView(data: data)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 64))
                .foregroundStyle(Color.textTertiary)
            Text("No statistics yet")
                .font(.title2)
                .foregroundColor(.textSecondary)
            Text("Statistics will appear after the first import")
                .font(.caption)
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .glassPanel()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let tb = Double(bytes) / (1024.0 * 1024.0 * 1024.0 * 1024.0)
        if tb >= 1 {
            return String(format: "%.2f TB", tb)
        }
        let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(bytes) / (1024.0 * 1024.0)
        return String(format: "%.0f MB", mb)
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes < 60 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond <= 0 {
            return "N/A"
        }
        let mbps = bytesPerSecond / (1024 * 1024)
        if mbps >= 1 {
            return String(format: "%.1f MB/s", mbps)
        }
        let kbps = bytesPerSecond / 1024
        return String(format: "%.0f KB/s", kbps)
    }

    private func formatShutterSpeed(_ seconds: Double) -> String {
        if seconds >= 1 {
            return String(format: "%.1fs", seconds)
        }
        let denominator = Int(round(1.0 / seconds))
        return "1/\(denominator)s"
    }

    private func showResetAlert() {
        let alert = NSAlert()
        alert.messageText = "Reset Total Stats?"
        alert.informativeText = "This will permanently delete all accumulated statistics. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            appState.totalStatsReport = nil
            StatsStorage.clear()
            appState.log("Total stats have been reset")
        }
    }
}

struct MonthlyChartView: View {
    let data: [(month: String, count: Int)]
    @State private var animatedWidths: [CGFloat] = []
    /// Mostrar o número à direita da barra só depois da animação da barra terminar.
    @State private var showCounts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MOST PHOTOS PER MONTH")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(4)
                .foregroundColor(.textSecondary)

            let chartData = Array(data.prefix(12))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(chartData.indices, id: \.self) { index in
                    let item = chartData[index]

                    HStack(alignment: .center, spacing: 12) {
                        Text(item.month)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textPrimary)
                            .frame(width: 80, alignment: .leading)

                        ZStack(alignment: .trailing) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.05))
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.importBlue, Color.importBlue.opacity(0.68)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: index < animatedWidths.count ? animatedWidths[index] : 0, height: 32, alignment: .leading)

                            Text("\(item.count)")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                                .opacity(showCounts ? 1 : 0)
                                .padding(.trailing, 10)
                        }
                        .frame(height: 32)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .dashboardPanel()
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        let maxCount = data.map { $0.count }.max() ?? 1
        let chartData = Array(data.prefix(12))

        animatedWidths = Array(repeating: 0, count: chartData.count)

        for index in chartData.indices {
            let item = chartData[index]
            let targetWidth = max(CGFloat(item.count) / CGFloat(maxCount) * 400, 20)

            withAnimation(.easeOut(duration: 0.6).delay(Double(index) * 0.05)) {
                animatedWidths[index] = targetWidth
            }
        }

        let barAnimationDuration = 0.6 + Double(max(0, chartData.count - 1)) * 0.05
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(barAnimationDuration + 0.15))
            withAnimation(.easeOut(duration: 0.25)) {
                showCounts = true
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottom) {
            SparklineView(color: color, values: sparklineValues(seed: title.count + value.count))
                .frame(height: 34)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .opacity(0.85)

            VStack(alignment: .leading, spacing: 10) {
                statHeader(title: title, icon: icon, color: color)
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 22)
            }
            .padding(16)
        }
        .modernStatCard(color: color, isHovered: isHovered)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) { isHovered = hovering }
        }
    }
}

struct SparklineView: View {
    let color: Color
    let values: [CGFloat]

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard values.count > 1 else { return }
                let step = proxy.size.width / CGFloat(values.count - 1)
                for index in values.indices {
                    let point = CGPoint(x: CGFloat(index) * step, y: proxy.size.height - (values[index] * proxy.size.height))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

private func sparklineValues(seed: Int) -> [CGFloat] {
    let base: [CGFloat] = [0.22, 0.18, 0.20, 0.16, 0.28, 0.22, 0.25, 0.19, 0.34, 0.30, 0.42, 0.36, 0.44, 0.40, 0.52, 0.48]
    let shift = seed % max(base.count, 1)
    return Array(base[shift...] + base[..<shift])
}

private func statHeader(title: String, icon: String, color: Color) -> some View {
    HStack(spacing: 10) {
        Image(systemName: icon)
            .foregroundStyle(color)
            .font(.system(size: 13, weight: .bold))
            .frame(width: 28, height: 28)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.textSecondary)
            .lineLimit(1)
        Spacer()
    }
}

private extension View {
    func modernStatCard(color: Color, isHovered: Bool) -> some View {
        self
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.importCardTop.opacity(0.88), Color.importCard.opacity(0.96)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: isHovered ? color.opacity(0.28) : Color.black.opacity(0.18), radius: isHovered ? 24 : 14, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.importBorder, lineWidth: 1)
            )
    }
}

// MARK: - Stackable Stat Card (iOS-style card stacking with auto-rotation)

struct StackableStatCard: View {
    struct CardData: Identifiable {
        let id = UUID()
        let title: String
        let value: String
    }

    let cards: [CardData]
    let icon: String
    let color: Color

    @State private var currentIndex = 0
    @State private var timer: Timer?
    @State private var isHovered = false

    private var activeCard: CardData {
        cards[min(currentIndex, max(cards.count - 1, 0))]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SparklineView(color: color, values: sparklineValues(seed: icon.count + cards.count))
                .frame(height: 34)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .opacity(0.85)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 10) {
                    statHeader(title: activeCard.title, icon: icon, color: color)
                        .id("title-\(currentIndex)")
                        .transition(.asymmetric(insertion: .push(from: .bottom).combined(with: .opacity), removal: .push(from: .top).combined(with: .opacity)))

                    Text(activeCard.value)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .id("value-\(currentIndex)")
                        .transition(.asymmetric(insertion: .push(from: .bottom).combined(with: .opacity), removal: .push(from: .top).combined(with: .opacity)))
                    Spacer(minLength: 22)
                }

                if cards.count > 1 {
                    VStack(spacing: 6) {
                        ForEach(0..<cards.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentIndex ? color : Color.textTertiary)
                                .frame(width: 6, height: 6)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { currentIndex = index }
                                    resetTimer()
                                }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(16)
        }
        .modernStatCard(color: color, isHovered: isHovered)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) { isHovered = hovering }
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
    }

    private func startTimer() {
        guard cards.count > 1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentIndex = (currentIndex + 1) % cards.count
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func resetTimer() {
        stopTimer()
        startTimer()
    }
}

// Efeito de hover para os cards de câmera
struct HoverScaleEffect: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
