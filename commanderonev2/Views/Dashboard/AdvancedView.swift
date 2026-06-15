import SwiftUI
import AppKit
import QuickLookThumbnailing

struct AdvancedView: View {
    @Bindable var appState: AppState
    let onClose: () -> Void

    @State private var files: [URL] = []
    @State private var selectedFiles: Set<URL> = []
    @State private var selectedFile: URL?
    @State private var lastSelectedIndex: Int?
    @State private var selectionAnchorIndex: Int?
    @State private var thumbnailStates: [URL: ThumbnailState] = [:]
    @State private var previewImage: NSImage?
    @State private var isLoadingFiles = false
    @State private var isLoadingPreview = false
    @State private var ratingFilter: RatingFilter = .all
    @State private var showImportConfirmation = false
    @State private var showNoSelectionAlert = false
    @State private var showNoDestinationAlert = false
    @State private var importEngine = ImportEngine()
    @State private var gridWidth: CGFloat = 0
    @State private var selectedSourceID: String?
    @State private var loadFilesTask: Task<Void, Never>?
    @State private var thumbnailTasks: [URL: Task<Void, Never>] = [:]
    @State private var previewTask: Task<Void, Never>?
    @State private var modifierEventMonitor: Any?
    @State private var currentModifierFlags: NSEvent.ModifierFlags = []
    @State private var mouseDownModifierFlags: NSEvent.ModifierFlags = []

    @FocusState private var isGalleryFocused: Bool
    @FocusState private var isPreviewFocused: Bool

    enum ThumbnailState: Equatable {
        case loading
        case loaded(NSImage)
        case failed

        static func == (lhs: ThumbnailState, rhs: ThumbnailState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.failed, .failed), (.loaded, .loaded): return true
            default: return false
            }
        }
    }

    private enum RatingFilter: String, CaseIterable {
        case all = "All"
        case rated = "Rated"
        case unrated = "Unrated"
    }

    private var displayedFiles: [URL] {
        switch ratingFilter {
        case .all:
            return files
        case .rated:
            return files.filter { rating(for: $0) != nil }
        case .unrated:
            return files.filter { rating(for: $0) == nil }
        }
    }

    private var selectedFilesInView: [URL] {
        displayedFiles.filter { selectedFiles.contains($0) }
    }

    private var showImportOverlay: Bool {
        switch appState.importState {
        case .importing, .paused, .scanning, .verifying, .ejecting, .ejectingDone, .generatingStats, .error:
            return true
        default:
            return false
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header

                Rectangle()
                    .fill(Color.auroraStroke)
                    .frame(height: 1)

                gallery
            }
            .background(AuroraBackground())

            if let selectedFile, let previewImage {
                previewOverlay(file: selectedFile, image: previewImage)
            } else if isLoadingPreview {
                previewLoadingOverlay
            }

            if showImportOverlay {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                ProgressOverlayView(
                    appState: appState,
                    onPause: pauseImport,
                    onResume: resumeImport,
                    onCancel: cancelImport
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(minWidth: 980, minHeight: 720)
        .onAppear {
            startModifierMonitor()
            loadFiles()
            isGalleryFocused = true
        }
        .onDisappear {
            cancelPreviewAndThumbnailWork()
            stopModifierMonitor()
        }
        .onChange(of: ratingFilter) { _, _ in
            selectedFiles = selectedFiles.intersection(displayedFiles)
            if let selectedFile, !displayedFiles.contains(selectedFile) {
                self.selectedFile = displayedFiles.first
            }
            if let anchor = selectionAnchorIndex, !displayedFiles.indices.contains(anchor) {
                selectionAnchorIndex = displayedFiles.firstIndex { selectedFiles.contains($0) }
            }
        }
        .alert("Import selected photos?", isPresented: $showImportConfirmation) {
            Button("Import") { importSelectedFiles() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Selected: \(selectedFilesInView.count)\nDestination: \(appState.destinationURL?.path ?? "No destination selected")")
        }
        .alert("No photos selected", isPresented: $showNoSelectionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Select one or more photos before importing from Advanced.")
        }
        .alert("No destination selected", isPresented: $showNoDestinationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Choose an import destination before importing selected photos.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            IconChip(systemName: "rectangle.grid.3x2.fill", color: .auroraCyan, size: 38, iconScale: 0.48)

            VStack(alignment: .leading, spacing: 6) {
                Text("Advanced Import")
                    .font(.auroraTopbarH2)
                    .tracking(-0.4)
                    .foregroundStyle(Color.auroraTxt)

                Text(headerSubtitle)
                    .font(.manrope(12.5, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)

                if !files.isEmpty {
                    HStack(spacing: 8) {
                        if sourceVolumes.count > 1 {
                            Menu {
                                Button {
                                    selectedSourceID = nil
                                    loadFiles()
                                } label: {
                                    Label("All Cards", systemImage: selectedSourceID == nil ? "checkmark" : "")
                                }
                                Divider()
                                ForEach(sourceVolumes) { volume in
                                    Button {
                                        selectedSourceID = volume.id
                                        loadFiles()
                                    } label: {
                                        Label(volume.name, systemImage: selectedSourceID == volume.id ? "checkmark" : "")
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(sourceSelectionTitle)
                                        .font(.manrope(11.5, weight: .semibold))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .frame(minWidth: 120)
                        }
                        filterButton(.all)
                        filterButton(.rated)
                        filterButton(.unrated)
                    }
                    .padding(.top, 6)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 10) {
                    Button("Import Selected") {
                        beginImportConfirmation()
                    }
                    .buttonStyle(AuroraGradientButtonStyle(compact: true))
                    .disabled(selectedFilesInView.isEmpty || appState.destinationURL == nil)
                    .opacity(selectedFilesInView.isEmpty || appState.destinationURL == nil ? 0.45 : 1)

                    Button("Close", action: closeAdvanced)
                        .buttonStyle(AuroraGhostButtonStyle())
                }

                Text(destinationLabel)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 360, alignment: .trailing)
            }
        }
        .padding(.horizontal, AuroraSpacing.mainPaddingH)
        .padding(.vertical, 18)
    }

    private var headerSubtitle: String {
        if isLoadingFiles { return "Scanning source files…" }
        guard !sourceVolumes.isEmpty else { return "No card detected" }
        let selected = selectedFilesInView.count
        if selected > 0 {
            return "\(AuroraFormat.count(selected)) selected from \(AuroraFormat.count(displayedFiles.count)) shown · \(sourceSelectionTitle)"
        }
        return "\(AuroraFormat.count(displayedFiles.count)) files shown · \(AuroraFormat.count(files.count)) RAW files · \(sourceSelectionTitle)"
    }

    private var destinationLabel: String {
        if let destination = appState.destinationURL {
            return "Destination: \(destination.path)"
        }
        return "Choose a destination before importing"
    }

    private func filterButton(_ filter: RatingFilter) -> some View {
        Button {
            ratingFilter = filter
        } label: {
            Text(filterTitle(filter))
        }
        .buttonStyle(AuroraGhostButtonStyle(active: ratingFilter == filter))
    }

    private func filterTitle(_ filter: RatingFilter) -> String {
        switch filter {
        case .all:
            return "All"
        case .rated:
            return "Rated (\(files.filter { rating(for: $0) != nil }.count))"
        case .unrated:
            return "Unrated"
        }
    }

    @ViewBuilder
    private var gallery: some View {
        if isLoadingFiles {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Loading RAW files…")
                    .font(.manrope(12, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayedFiles.isEmpty {
            VStack(spacing: 12) {
                IconChip(systemName: "photo.on.rectangle.angled", color: .auroraViolet, size: 54, iconScale: 0.48)
                Text(files.isEmpty ? "No RAW files found" : "No files match this filter")
                    .font(.sora(18, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Text(files.isEmpty ? "Choose a card with RAW files, or select All Cards." : "Change the filter or rate more photos.")
                    .font(.manrope(12, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { proxy in
                let layout = gridLayout(for: proxy.size.width)
                ScrollView {
                    LazyVGrid(columns: layout.columns, spacing: layout.spacing) {
                        ForEach(Array(displayedFiles.enumerated()), id: \.element) { index, file in
                            AdvancedPhotoTile(
                                file: file,
                                thumbnailState: thumbnailStates[file] ?? .loading,
                                isSelected: selectedFiles.contains(file),
                                rating: rating(for: file),
                                onSelect: { handleSelection(file, index: index) },
                                onPreview: { openPreview(file) },
                                onRate: { setRating($0, for: file) }
                            )
                            .frame(width: layout.tileWidth)
                            .clipped()
                            .onAppear { loadThumbnailIfNeeded(for: file) }
                            .contextMenu {
                                Button("Import This Photo") {
                                    selectedFiles = [file]
                                    selectedFile = file
                                    beginImportConfirmation()
                                }
                                Divider()
                                Button("Clear Rating") {
                                    clearRating(for: file)
                                }
                            }
                        }
                    }
                    .padding(layout.padding)
                }
                .scrollIndicators(.hidden)
                .onAppear { gridWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, width in gridWidth = width }
            }
            .focusable()
            .focused($isGalleryFocused)
            .focusEffectDisabled()
            .onCommand(#selector(NSResponder.selectAll(_:))) {
                selectedFiles = Set(displayedFiles)
                selectedFile = displayedFiles.first
                lastSelectedIndex = displayedFiles.isEmpty ? nil : 0
                selectionAnchorIndex = lastSelectedIndex
            }
            .onKeyPress("1") { rateSelection(1); return .handled }
            .onKeyPress("2") { rateSelection(2); return .handled }
            .onKeyPress("3") { rateSelection(3); return .handled }
            .onKeyPress("4") { rateSelection(4); return .handled }
            .onKeyPress("5") { rateSelection(5); return .handled }
            .onKeyPress("0") { clearSelectionRatings(); return .handled }
            .onKeyPress(.space) {
                if let selectedFile { openPreview(selectedFile) }
                return .handled
            }
            .onKeyPress(.leftArrow) { moveSelection(by: -1); return .handled }
            .onKeyPress(.rightArrow) { moveSelection(by: 1); return .handled }
            .onKeyPress(.upArrow) { moveSelection(by: -columnCount); return .handled }
            .onKeyPress(.downArrow) { moveSelection(by: columnCount); return .handled }
        }
    }

    private func gridLayout(for width: CGFloat) -> (columns: [GridItem], tileWidth: CGFloat, spacing: CGFloat, padding: CGFloat) {
        let spacing: CGFloat = 24
        let padding: CGFloat = 24
        let minTileWidth: CGFloat = 210
        let contentWidth = max(width - padding * 2, minTileWidth)
        let count = max(Int((contentWidth + spacing) / (minTileWidth + spacing)), 1)
        let tileWidth = floor((contentWidth - spacing * CGFloat(count - 1)) / CGFloat(count))
        let columns = Array(repeating: GridItem(.fixed(tileWidth), spacing: spacing), count: count)
        return (columns, tileWidth, spacing, padding)
    }

    private var columnCount: Int {
        gridLayout(for: gridWidth).columns.count
    }

    private var previewLoadingOverlay: some View {
        Color.black.opacity(0.82)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Color.auroraCyan)
                    Text("Loading preview…")
                        .font(.manrope(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
    }

    private func previewOverlay(file: URL, image: NSImage) -> some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.lastPathComponent)
                            .font(.sora(16, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Arrow keys navigate · 1-5 rate · ESC closes")
                            .font(.manrope(11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    Spacer()
                    Button("Close") { closePreview() }
                        .buttonStyle(AuroraGhostButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)

                HStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            setRating(value, for: file)
                        } label: {
                            Image(systemName: value <= (rating(for: file) ?? 0) ? "star.fill" : "star")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.yellow)
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Clear") { clearRating(for: file) }
                        .buttonStyle(AuroraGhostButtonStyle())
                        .padding(.leading, 8)
                }
                .padding(.bottom, 20)
            }
        }
        .focusable()
        .focused($isPreviewFocused)
        .focusEffectDisabled()
        .onAppear { isPreviewFocused = true }
        .onKeyPress(.escape) { closePreview(); return .handled }
        .onKeyPress(.leftArrow) { navigatePreview(offset: -1); return .handled }
        .onKeyPress(.rightArrow) { navigatePreview(offset: 1); return .handled }
        .onKeyPress("1") { setRating(1, for: file); return .handled }
        .onKeyPress("2") { setRating(2, for: file); return .handled }
        .onKeyPress("3") { setRating(3, for: file); return .handled }
        .onKeyPress("4") { setRating(4, for: file); return .handled }
        .onKeyPress("5") { setRating(5, for: file); return .handled }
        .onKeyPress("0") { clearRating(for: file); return .handled }
    }

    private func loadFiles() {
        let volumes = selectedSourceVolumes
        guard !volumes.isEmpty else {
            files = []
            return
        }
        loadFilesTask?.cancel()
        clearLoadedGalleryState()
        isLoadingFiles = true
        let paths = volumes.map(\.path)
        let extensions = appState.supportedExtensions
        loadFilesTask = Task {
            let sourceFiles = await Task.detached(priority: .userInitiated) {
                paths.flatMap { path in
                    VolumeWatcher.listRawFiles(at: path, extensions: extensions)
                }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                loadFilesTask = nil
                appState.updateSourceFiles(sourceFiles)
                files = appState.sortedSourceFiles.isEmpty ? sourceFiles : appState.sortedSourceFiles
                selectedFiles = selectedFiles.intersection(files)
                if let anchor = selectionAnchorIndex, !files.indices.contains(anchor) {
                    selectionAnchorIndex = files.firstIndex { selectedFiles.contains($0) }
                }
                isLoadingFiles = false
                prefetchInitialThumbnails()
            }
        }
    }

    private func clearLoadedGalleryState() {
        previewTask?.cancel()
        previewTask = nil
        for task in thumbnailTasks.values { task.cancel() }
        thumbnailTasks.removeAll()
        thumbnailStates = [:]
        previewImage = nil
        isLoadingPreview = false
        selectedFile = nil
        selectedFiles = []
        lastSelectedIndex = nil
        selectionAnchorIndex = nil
    }

    private func closeAdvanced() {
        cancelPreviewAndThumbnailWork()
        stopModifierMonitor()
        onClose()
    }

    private func startModifierMonitor() {
        guard modifierEventMonitor == nil else { return }
        modifierEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .leftMouseDown]) { event in
            let relevantFlags = relevantModifierFlags(event.modifierFlags)
            currentModifierFlags = relevantFlags
            if event.type == .leftMouseDown {
                mouseDownModifierFlags = relevantFlags
            }
            return event
        }
    }

    private func stopModifierMonitor() {
        if let monitor = modifierEventMonitor {
            NSEvent.removeMonitor(monitor)
            modifierEventMonitor = nil
        }
        currentModifierFlags = []
        mouseDownModifierFlags = []
    }

    private func cancelPreviewAndThumbnailWork() {
        loadFilesTask?.cancel()
        loadFilesTask = nil
        previewTask?.cancel()
        previewTask = nil
        for task in thumbnailTasks.values {
            task.cancel()
        }
        thumbnailTasks.removeAll()
    }

    private func loadThumbnailIfNeeded(for file: URL) {
        guard thumbnailStates[file] == nil, thumbnailTasks[file] == nil else { return }
        if let cached = ThumbnailCache.shared.get(for: file) {
            thumbnailStates[file] = .loaded(cached)
            return
        }
        thumbnailStates[file] = .loading
        thumbnailTasks[file] = Task {
            let image = await thumbnailImage(for: file)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                thumbnailTasks[file] = nil
                guard let image else {
                    thumbnailStates[file] = .failed
                    return
                }
                ThumbnailCache.shared.set(image, for: file)
                thumbnailStates[file] = .loaded(image)
            }
        }
    }

    private func prefetchInitialThumbnails(limit: Int = 18) {
        for file in displayedFiles.prefix(limit) {
            loadThumbnailIfNeeded(for: file)
        }
    }

    private func openPreview(_ file: URL) {
        previewTask?.cancel()
        selectedFile = file
        previewImage = nil
        isLoadingPreview = true
        isGalleryFocused = false
        previewTask = Task {
            let image = await fullPreviewImage(for: file)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                previewTask = nil
                guard selectedFile == file, let image else {
                    isLoadingPreview = false
                    return
                }
                previewImage = image
                isLoadingPreview = false
                isPreviewFocused = true
            }
        }
    }

    private func thumbnailImage(for file: URL) async -> NSImage? {
        if Task.isCancelled { return nil }
        if let image = await quickLookImage(for: file, maxPixel: 320, scale: 1) {
            return image
        }

        for tag in ["PreviewImage", "ThumbnailImage", "JpgFromRaw"] {
            if Task.isCancelled { return nil }
            guard let data = await extractJPEG(from: file, tag: tag) else { continue }
            if Task.isCancelled { return nil }
            if let image = makeImage(from: data, maxPixel: 320) {
                return image
            }
        }
        return nil
    }

    private func fullPreviewImage(for file: URL) async -> NSImage? {
        for tag in ["JpgFromRaw", "PreviewImage", "ThumbnailImage"] {
            if Task.isCancelled { return nil }
            guard let data = await extractJPEG(from: file, tag: tag) else { continue }
            if Task.isCancelled { return nil }
            if let image = makeImage(from: data, maxPixel: 2400) {
                return image
            }
        }
        if Task.isCancelled { return nil }
        return await quickLookImage(for: file, maxPixel: 1800)
    }

    private func closePreview() {
        previewTask?.cancel()
        previewTask = nil
        previewImage = nil
        isLoadingPreview = false
        isPreviewFocused = false
        isGalleryFocused = true
    }

    private func navigatePreview(offset: Int) {
        guard let selectedFile, let index = displayedFiles.firstIndex(of: selectedFile) else { return }
        let nextIndex = max(0, min(displayedFiles.count - 1, index + offset))
        guard nextIndex != index else { return }
        openPreview(displayedFiles[nextIndex])
    }

    private func handleSelection(_ file: URL, index: Int) {
        let modifiers = selectionModifierFlags()
        let isShift = modifiers.contains(.shift)
        let isCommand = modifiers.contains(.command)

        if isShift {
            let anchor = selectionAnchorIndex ?? lastSelectedIndex ?? index
            let bounds = min(anchor, index)...max(anchor, index)
            let rangeFiles = Set(bounds.map { displayedFiles[$0] })
            selectedFiles = isCommand ? selectedFiles.union(rangeFiles) : rangeFiles
        } else if isCommand {
            if selectedFiles.contains(file) {
                selectedFiles.remove(file)
            } else {
                selectedFiles.insert(file)
            }
            selectionAnchorIndex = index
        } else {
            selectedFiles = [file]
            selectionAnchorIndex = index
        }

        selectedFile = selectedFiles.contains(file) ? file : selectedFiles.first
        lastSelectedIndex = index
        mouseDownModifierFlags = []
        isGalleryFocused = true
    }

    private func selectionModifierFlags() -> NSEvent.ModifierFlags {
        let mouseFlags = relevantModifierFlags(mouseDownModifierFlags)
        if !mouseFlags.isEmpty { return mouseFlags }

        let currentFlags = relevantModifierFlags(currentModifierFlags)
        if !currentFlags.isEmpty { return currentFlags }

        return relevantModifierFlags(NSApp.currentEvent?.modifierFlags ?? [])
    }

    private func moveSelection(by offset: Int) {
        guard !displayedFiles.isEmpty else { return }
        let currentIndex = selectedFile.flatMap { displayedFiles.firstIndex(of: $0) } ?? 0
        let nextIndex = max(0, min(displayedFiles.count - 1, currentIndex + offset))
        handleSelection(displayedFiles[nextIndex], index: nextIndex)
    }

    private func rating(for file: URL) -> Int? {
        let value = appState.photoRatings[file] ?? 0
        return value > 0 ? value : nil
    }

    private func setRating(_ rating: Int, for file: URL) {
        appState.photoRatings[file] = rating
    }

    private func clearRating(for file: URL) {
        appState.photoRatings[file] = 0
    }

    private func rateSelection(_ rating: Int) {
        for file in selectedFilesInView {
            setRating(rating, for: file)
        }
    }

    private func clearSelectionRatings() {
        for file in selectedFilesInView {
            clearRating(for: file)
        }
    }

    private func beginImportConfirmation() {
        guard !selectedFilesInView.isEmpty else {
            showNoSelectionAlert = true
            return
        }
        guard appState.destinationURL != nil else {
            showNoDestinationAlert = true
            return
        }
        showImportConfirmation = true
    }

    private func importSelectedFiles() {
        guard let destination = appState.destinationURL else { return }
        let filesToImport = selectedFilesInView
        guard !filesToImport.isEmpty else { return }
        let importSources = sources(containing: filesToImport)
        guard !importSources.isEmpty else { return }
        let sourceName = importSources.map(\.name).joined(separator: " + ")
        let sourcePath = importSources.map { $0.path.path }.joined(separator: "\n")

        Task {
            let sourceAccesses = importSources.map { ($0.path, $0.path.startAccessingSecurityScopedResource()) }
            defer {
                for (url, isAccessing) in sourceAccesses where isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let destinationAccessing = BookmarkManager.startAccessing(destination)
            defer { if destinationAccessing { BookmarkManager.stopAccessing(destination) } }

            await MainActor.run {
                appState.importState = .importing
                appState.importProgress = ImportProgress(totalFiles: filesToImport.count, startTime: Date())
                appState.log("Advanced import: \(filesToImport.count) selected files from \(sourceName) to \(destination.path)")
            }

            do {
                let mode: ImportEngine.Mode = appState.importMode == .copy ? .copy : .move
                let orderedFiles = filesToImport.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                let importDate = Date()
                let captureDates = appState.renameOnImport && RenameTemplateRenderer.usesDateTokens(appState.renameTemplate)
                    ? await RenameCaptureDateReader.captureDates(for: orderedFiles)
                    : [:]
                let renameOptions = appState.renameOnImport
                    ? ImportRenameOptions(
                        template: appState.renameTemplate,
                        eventName: appState.renameEventName(forDestinationPath: destination.path),
                        importDate: importDate,
                        totalCount: orderedFiles.count,
                        captureDatesByPath: captureDates
                    )
                    : nil
                let result = try await importEngine.importFiles(from: orderedFiles, to: destination, mode: mode, renameOptions: renameOptions) { progress in
                    Task { @MainActor in
                        appState.importProgress.completedFiles = progress.completedFiles
                        appState.importProgress.totalFiles = progress.totalFiles
                        appState.importProgress.transferredBytes = progress.transferredBytes
                        appState.importProgress.totalBytes = progress.totalBytes
                        appState.importProgress.currentFileName = progress.currentFileName
                        appState.importProgress.bytesPerSecond = progress.bytesPerSecond
                        appState.importProgress.skippedFiles = progress.skippedFiles
                        appState.importProgress.statusMessage = progress.statusMessage
                    }
                }

                await MainActor.run {
                    appState.importState = .generatingStats
                    appState.lastImportReport = ImportReport(
                        sourceVolumeName: sourceName,
                        sourcePath: sourcePath,
                        destinationPath: result.destinationPath,
                        fileCount: result.fileCount,
                        totalBytes: result.totalBytes,
                        duration: result.duration,
                        averageSpeed: result.averageSpeed,
                        importedFiles: result.importedFiles
                    )
                    appState.log("Advanced import complete: \(result.fileCount) files")
                    if result.skippedFiles > 0 {
                        appState.log("Advanced import skipped \(result.skippedFiles) duplicate file\(result.skippedFiles == 1 ? "" : "s") already present in destination")
                    }
                    if result.importedFiles.isEmpty {
                        if result.skippedFiles > 0 {
                            appState.sourceFileCountForDestinationCheck = result.skippedFiles
                            appState.allDestinationFilesAlreadyImported = true
                            appState.sourceFilesImportStatusMessage = "All \(result.skippedFiles) files are already imported"
                        }
                        appState.importState = .idle
                    } else if result.skippedFiles > 0 {
                        appState.sourceFileCountForDestinationCheck = result.skippedFiles
                        appState.allDestinationFilesAlreadyImported = false
                        appState.sourceFilesImportStatusMessage = "Skipped \(result.skippedFiles) duplicate file\(result.skippedFiles == 1 ? "" : "s")"
                    }
                }

                guard !result.importedFiles.isEmpty else { return }

                let runner = StatsRunner(appState: appState)
                await runner.runStats(importedFiles: result.importedFiles, destinationPath: result.destinationPath, duration: result.duration)

                await MainActor.run {
                    if let lastStats = appState.statsReport {
                        appState.totalStatsReport = StatsReport.combine(appState.totalStatsReport, lastStats)
                        ImportHistoryStorage.add(ImportHistoryEntry(
                            sourceName: sourceName,
                            destinationPath: result.destinationPath,
                            fileCount: result.importedFiles.count,
                            totalBytes: lastStats.totalBytes
                        ))
                        appState.importHistory = ImportHistoryStorage.load()
                        appState.mergeImportedStatsIntoEventCache(lastStats, destinationPath: result.destinationPath)
                        appState.recordTelegramDailyImport(
                            sourceName: sourceName,
                            destinationPath: result.destinationPath,
                            fileCount: result.importedFiles.count,
                            totalBytes: lastStats.totalBytes,
                            duration: result.duration,
                            report: lastStats
                        )
                    }
                    selectedFiles.subtract(filesToImport)
                    files.removeAll { filesToImport.contains($0) }
                    appState.updateSourceFiles(files)
                    appState.importState = .idle
                }
            } catch ImportError.cancelled {
                await MainActor.run {
                    appState.importState = .idle
                    appState.log("Advanced import cancelled", level: .warning)
                }
            } catch {
                await MainActor.run {
                    appState.importProgress.failureMessage = error.localizedDescription
                    appState.importProgress.statusMessage = "Import failed: \(error.localizedDescription)"
                    appState.importState = .error(error.localizedDescription)
                    appState.log("Advanced import failed: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    private func pauseImport() {
        Task {
            await importEngine.pause()
            await MainActor.run { appState.importState = .paused }
        }
    }

    private func resumeImport() {
        Task {
            await importEngine.resume()
            await MainActor.run { appState.importState = .importing }
        }
    }

    private func cancelImport() {
        Task {
            await importEngine.cancel()
        }
    }

    private var sourceVolumes: [VolumeInfo] {
        let volumes = appState.mountedVolumes.filter { $0.rawFileCount > 0 && !isDestinationVolume($0.path) }
        guard !volumes.isEmpty else {
            if let active = appState.activeVolume, active.rawFileCount > 0, !isDestinationVolume(active.path) { return [active] }
            return []
        }
        return Array(volumes.prefix(2))
    }

    private var selectedSourceVolumes: [VolumeInfo] {
        guard let selectedSourceID else { return sourceVolumes }
        let selected = sourceVolumes.filter { $0.id == selectedSourceID }
        return selected.isEmpty ? sourceVolumes : selected
    }

    private var sourceSelectionTitle: String {
        guard selectedSourceID != nil else {
            return sourceVolumes.count > 1 ? "All Cards" : (sourceVolumes.first?.name ?? "No card")
        }
        return selectedSourceVolumes.first?.name ?? "All Cards"
    }

    private func sources(containing files: [URL]) -> [VolumeInfo] {
        sourceVolumes.filter { volume in
            files.contains { file in isFile(file, under: volume.path) }
        }
    }

    private func isDestinationVolume(_ sourceURL: URL) -> Bool {
        guard let destinationURL = appState.destinationURL else { return false }
        let sourcePath = normalizedPath(sourceURL.path)
        let destinationPath = normalizedPath(destinationURL.path)
        return destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/")
    }

    private func isFile(_ file: URL, under folder: URL) -> Bool {
        let filePath = normalizedPath(file.path)
        let folderPath = normalizedPath(folder.path)
        return filePath == folderPath || filePath.hasPrefix(folderPath + "/")
    }

    private func normalizedPath(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func extractJPEG(from file: URL, tag: String) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let exiftoolPath = exiftoolPath() else {
                    continuation.resume(returning: nil)
                    return
                }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: exiftoolPath)
                process.arguments = ["-b", "-\(tag)", file.path]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0 && !data.isEmpty ? data : nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func quickLookImage(for file: URL, maxPixel: CGFloat, scale: CGFloat = 2) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: file,
            size: CGSize(width: maxPixel, height: maxPixel),
            scale: scale,
            representationTypes: .thumbnail
        )

        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return makeImage(from: representation.nsImage, maxPixel: maxPixel)
        } catch {
            return nil
        }
    }

    private func makeImage(from image: NSImage, maxPixel: CGFloat) -> NSImage? {
        let width = max(image.size.width, 1)
        let height = max(image.size.height, 1)
        let scale = min(1, maxPixel / max(width, height))
        guard scale < 1 else { return image }

        let size = NSSize(width: width * scale, height: height * scale)
        let resized = NSImage(size: size)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
        resized.unlockFocus()
        return resized
    }

    private func makeImage(from data: Data, maxPixel: CGFloat) -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }
        return makeImage(from: image, maxPixel: maxPixel)
    }
}

private func relevantModifierFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
    flags.intersection([.shift, .command, .option, .control])
}

private func exiftoolPath() -> String? {
    ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool"]
        .first { FileManager.default.fileExists(atPath: $0) }
}

private struct AdvancedPhotoTile: View {
    let file: URL
    let thumbnailState: AdvancedView.ThumbnailState
    let isSelected: Bool
    let rating: Int?
    let onSelect: () -> Void
    let onPreview: () -> Void
    let onRate: (Int) -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.auroraPanel2)

                switch thumbnailState {
                case .loading:
                    ProgressView()
                        .scaleEffect(0.8)
                case .failed:
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 24, weight: .semibold))
                        Text("No preview")
                            .font(.manrope(11, weight: .semibold))
                    }
                    .foregroundStyle(Color.auroraFaint)
                case .loaded(let image):
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }

                if let rating {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                        Text("\(rating)")
                    }
                    .font(.manrope(10, weight: .bold))
                    .foregroundStyle(Color.yellow)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.58)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(8)
                }
            }
            .frame(height: 118)
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(file.lastPathComponent)
                    .font(.manrope(12, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)
                Text(fileSizeLabel)
                    .font(.manrope(10.5, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
            }

            HStack(spacing: 5) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        onRate(value)
                    } label: {
                        Image(systemName: value <= (rating ?? 0) ? "star.fill" : "star")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.yellow)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(hovering ? Color.auroraPanel2 : Color.auroraPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Color.auroraCyan : Color.auroraStroke, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? Color.auroraCyan.opacity(0.18) : .clear, radius: 16, x: 0, y: 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onPreview)
        .onTapGesture(count: 1, perform: onSelect)
        .onHover { hovering = $0 }
    }

    private var fileSizeLabel: String {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else { return file.pathExtension.uppercased() }
        let parts = AuroraFormat.bytesParts(Int64(size))
        return "\(file.pathExtension.uppercased()) · \(parts.value) \(parts.unit)"
    }
}
