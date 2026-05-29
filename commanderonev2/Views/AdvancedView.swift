import SwiftUI
import AppKit

struct AdvancedView: View {
    @Bindable var appState: AppState
    let onClose: () -> Void

    @State private var thumbnailStates: [URL: ThumbnailState] = [:]
    @State private var selectedFileURL: URL?
    @State private var selectedFiles: Set<URL> = []
    @State private var lastSelectedIndex: Int?
    @State private var showFullPreview = false
    @State private var fullPreviewImage: NSImage?
    @State private var isLoadingFullPreview = false
    @State private var ratingFilter: RatingFilter = .all
    @State private var showImportConfirmation = false
    @State private var pendingImportURL: URL?
    @State private var showImportSingleConfirmation = false
    @State private var showNoSelectionAlert = false
    @State private var statsRunner: StatsRunner?
    @State private var importEngine = ImportEngine()
    @State private var gridWidth: CGFloat = 0
    @FocusState private var isGalleryFocused: Bool
    @FocusState private var isFullPreviewFocused: Bool
    private let cache = ThumbnailCache.shared
    
    enum ThumbnailState: Equatable {
        case loading
        case loaded(NSImage)
        case failed
        
        var isLoaded: Bool {
            if case .loaded = self { return true }
            return false
        }
        
        static func == (lhs: ThumbnailState, rhs: ThumbnailState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.failed, .failed):
                return true
            case (.loaded, .loaded):
                return true
            default:
                return false
            }
        }
    }

    enum RatingFilter: String, CaseIterable {
        case all = "All"
        case rated = "Rated"
        case unrated = "Unrated"
    }


    private var sourceFiles: [URL] {
        appState.sortedSourceFiles
    }

    private var displayedFiles: [URL] {
        switch ratingFilter {
        case .all:
            return sourceFiles
        case .rated:
            return sourceFiles.filter { (appState.photoRatings[$0] ?? 0) > 0 }
        case .unrated:
            return sourceFiles.filter { (appState.photoRatings[$0] ?? 0) == 0 }
        }
    }

    private var ratedFiles: [URL] {
        sourceFiles.filter { (appState.photoRatings[$0] ?? 0) > 0 }
    }

    private var ratedCount: Int {
        ratedFiles.count
    }

    private var selectedCount: Int {
        selectedFilesInView.count
    }

    private func filterLabel(for filter: RatingFilter) -> String {
        switch filter {
        case .rated:
            return ratedCount > 0 ? "Rated (\(ratedCount))" : filter.rawValue
        case .all, .unrated:
            return filter.rawValue
        }
    }

    private var hasRatings: Bool {
        appState.photoRatings.values.contains { $0 > 0 }
    }

    private func rating(for url: URL) -> Int? {
        let value = appState.photoRatings[url] ?? 0
        return value > 0 ? value : nil
    }

    private func setRating(_ rating: Int, for url: URL) {
        appState.photoRatings[url] = rating
    }

    private func clearRating(for url: URL) {
        appState.photoRatings[url] = 0
    }

    private var selectedFilesInView: [URL] {
        displayedFiles.filter { selectedFiles.contains($0) }
    }

    private func handleSelection(for fileURL: URL) {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        let isShift = modifiers.contains(.shift)
        let isCommand = modifiers.contains(.command)

        if isShift, let lastIndex = lastSelectedIndex, let currentIndex = displayedFiles.firstIndex(of: fileURL) {
            let range = lastIndex <= currentIndex ? lastIndex...currentIndex : currentIndex...lastIndex
            let rangeFiles = Set(range.map { displayedFiles[$0] })
            if isCommand {
                selectedFiles.formUnion(rangeFiles)
            } else {
                selectedFiles = rangeFiles
            }
        } else if isCommand {
            if selectedFiles.contains(fileURL) {
                selectedFiles.remove(fileURL)
            } else {
                selectedFiles.insert(fileURL)
            }
        } else {
            selectedFiles = [fileURL]
        }

        if selectedFiles.contains(fileURL) {
            selectedFileURL = fileURL
        } else {
            selectedFileURL = selectedFiles.first
        }

        lastSelectedIndex = displayedFiles.firstIndex(of: selectedFileURL ?? fileURL)
        isGalleryFocused = true
    }

    private func applyRatingToSelection(_ rating: Int) {
        let targets = selectedFilesInView
        guard !targets.isEmpty else { return }
        for url in targets {
            setRating(rating, for: url)
        }
    }

    private func clearRatingForSelection() {
        let targets = selectedFilesInView
        guard !targets.isEmpty else { return }
        for url in targets {
            clearRating(for: url)
        }
    }

    private var showImportOverlay: Bool {
        switch appState.importState {
        case .importing, .paused, .scanning, .verifying, .ejecting, .ejectingDone, .generatingStats:
            return true
        default:
            return false
        }
    }

    private func columnCount() -> Int {
        let minWidth: CGFloat = 200
        let spacing: CGFloat = 16
        let width = max(gridWidth, 1)
        let columns = Int((width + spacing) / (minWidth + spacing))
        return max(columns, 1)
    }

    private func selectIndex(_ index: Int) {
        guard !displayedFiles.isEmpty else { return }
        let clamped = max(0, min(index, displayedFiles.count - 1))
        let url = displayedFiles[clamped]
        selectedFiles = [url]
        selectedFileURL = url
        lastSelectedIndex = clamped
    }

    private func moveSelection(by offset: Int) {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        let isShift = modifiers.contains(.shift)

        guard let current = selectedFileURL,
              let currentIndex = displayedFiles.firstIndex(of: current) else {
            selectIndex(0)
            return
        }

        let targetIndex = max(0, min(currentIndex + offset, displayedFiles.count - 1))

        if isShift, let anchor = lastSelectedIndex {
            let range = anchor <= targetIndex ? anchor...targetIndex : targetIndex...anchor
            selectedFiles = Set(range.map { displayedFiles[$0] })
            selectedFileURL = displayedFiles[targetIndex]
        } else {
            selectIndex(targetIndex)
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Advanced Mode")
                            .font(.title.bold())
                            .foregroundColor(.textPrimary)

                        if let volume = appState.activeVolume {
                            Text("\(displayedFiles.count) files in \(volume.name)")
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                        }

                        if selectedCount > 0 {
                            Text("Selected: \(selectedCount)")
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                        }

                        if hasRatings {
                            Picker("Filter", selection: $ratingFilter) {
                                ForEach(RatingFilter.allCases, id: \.self) { filter in
                                    Text(filterLabel(for: filter)).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 260)
                        }
                        
                        // Hint when photo selected
                        if selectedFileURL != nil && !showFullPreview {
                            HStack(spacing: 4) {
                                Image(systemName: "space")
                                    .font(.system(size: 10))
                                Text("Press Space for full preview")
                                    .font(.caption2)
                            }
                            .foregroundColor(.textTertiary.opacity(0.8))
                        }
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        Button {
                            showImportConfirmation = true
                        } label: {
                            Label("Import Now", systemImage: "square.and.arrow.down.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(appState.activeVolume == nil || appState.destinationURL == nil)

                        Button {
                            onClose()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Close")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.glassBase)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.glassBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)

                Divider()

                // Photo Gallery
                if displayedFiles.isEmpty {
                    emptyState
                } else {
                    photoGallery
                }
            }
            
            // Full Preview Overlay
            if showFullPreview {
                fullPreviewOverlay
            }

            if showImportOverlay {
                Color.black.opacity(0.3)
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
        .onAppear {
            if statsRunner == nil {
                statsRunner = StatsRunner(appState: appState)
            }
            isGalleryFocused = true
        }
        .alert("Import photos?", isPresented: $showImportConfirmation) {
            Button("Import") {
                let filesToImport = selectedFilesInView
                if filesToImport.isEmpty {
                    showNoSelectionAlert = true
                } else {
                    importPhotos(filesToImport)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let destination = appState.destinationURL {
                Text("Destination: \(destination.path)\nSelected: \(selectedFilesInView.count)")
            } else {
                Text("No destination folder selected.")
            }
        }
        .alert("No photos selected", isPresented: $showNoSelectionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Select photos to import.")
        }
        .alert("Import this photo?", isPresented: $showImportSingleConfirmation) {
            Button("Import") {
                if let url = pendingImportURL {
                    importPhotos([url])
                }
                pendingImportURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingImportURL = nil
            }
        } message: {
            if let destination = appState.destinationURL {
                Text("Destination: \(destination.path)")
            } else {
                Text("No destination folder selected.")
            }
        }
        .onChange(of: ratingFilter) { _, _ in
            if let selected = selectedFileURL, !displayedFiles.contains(selected) {
                selectedFileURL = displayedFiles.first
            }
            selectedFiles = selectedFiles.intersection(displayedFiles)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(.textTertiary)

            Text("No Source Files")
                .font(.title2.bold())
                .foregroundColor(.textPrimary)

            Text("No RAW files found on the selected volume")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var fullPreviewOverlay: some View {
        ZStack {
            // Dark background
            Color.black.opacity(0.95)
                .ignoresSafeArea()
            
            VStack {
                // Close button
                HStack {
                    Spacer()
                    Button {
                        showFullPreview = false
                        fullPreviewImage = nil
                        isFullPreviewFocused = false
                        isGalleryFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .padding()
                }
                
                // Preview image
                if isLoadingFullPreview {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text("Loading full preview...")
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top)
                } else if let previewImage = fullPreviewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                    
                    // Rating controls
                    if let selectedURL = selectedFileURL {
                        HStack(spacing: 10) {
                            ForEach(1...5, id: \.self) { value in
                                Button {
                                    setRating(value, for: selectedURL)
                                } label: {
                                    Image(systemName: value <= (rating(for: selectedURL) ?? 0) ? "star.fill" : "star")
                                        .font(.system(size: 18))
                                        .foregroundColor(.yellow)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                } else {
                    Text("Failed to load preview")
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Filename and navigation hints
                VStack(spacing: 8) {
                    if let selectedURL = selectedFileURL {
                        Text(selectedURL.lastPathComponent)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 10))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                            Text("Navigate")
                                .font(.caption2)
                        }
                        
                        HStack(spacing: 4) {
                            Text("ESC")
                                .font(.caption2.monospaced())
                            Text("Close")
                                .font(.caption2)
                        }
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
                .padding()
            }
        }
        .focusable()
        .focused($isFullPreviewFocused)
        .focusEffectDisabled()
        .onAppear {
            isFullPreviewFocused = true
        }
        .onKeyPress("1") {
            if let selectedURL = selectedFileURL {
                setRating(1, for: selectedURL)
            }
            return .handled
        }
        .onKeyPress("2") {
            if let selectedURL = selectedFileURL {
                setRating(2, for: selectedURL)
            }
            return .handled
        }
        .onKeyPress("3") {
            if let selectedURL = selectedFileURL {
                setRating(3, for: selectedURL)
            }
            return .handled
        }
        .onKeyPress("4") {
            if let selectedURL = selectedFileURL {
                setRating(4, for: selectedURL)
            }
            return .handled
        }
        .onKeyPress("5") {
            if let selectedURL = selectedFileURL {
                setRating(5, for: selectedURL)
            }
            return .handled
        }
        .onKeyPress("0") {
            if let selectedURL = selectedFileURL {
                clearRating(for: selectedURL)
            }
            return .handled
        }
        .onKeyPress(.escape) {
            showFullPreview = false
            fullPreviewImage = nil
            isFullPreviewFocused = false
            isGalleryFocused = true
            return .handled
        }
        .onKeyPress(.leftArrow) {
            navigateToPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateToNext()
            return .handled
        }
    }

    private var photoGallery: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 16)
                ],
                spacing: 16
            ) {
                ForEach(displayedFiles, id: \.self) { fileURL in
                    PhotoThumbnailCard(
                        fileURL: fileURL,
                        thumbnailState: thumbnailStates[fileURL] ?? .loading,
                        isSelected: selectedFiles.contains(fileURL),
                        rating: rating(for: fileURL),
                        onRate: { value in
                            setRating(value, for: fileURL)
                        },
                        onSingleTap: {
                            handleSelection(for: fileURL)
                        },
                        onDoubleTap: {
                            selectedFileURL = fileURL
                            showFullPreview = true
                            loadFullPreview(for: fileURL)
                            isGalleryFocused = false
                            isFullPreviewFocused = true
                        }
                    )
                    .contextMenu {
                        Button("Import This Photo") {
                            selectedFiles = [fileURL]
                            selectedFileURL = fileURL
                            pendingImportURL = fileURL
                            showImportSingleConfirmation = true
                        }
                    }
                    .onAppear {
                        loadThumbnailIfNeeded(for: fileURL)
                    }
                }
            }
            .padding(20)
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { gridWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in
                        gridWidth = newValue
                    }
            }
        )
        .focusable()
        .focused($isGalleryFocused)
        .focusEffectDisabled()
        .onCommand(#selector(NSResponder.selectAll(_:))) {
            selectedFiles = Set(displayedFiles)
            selectedFileURL = displayedFiles.first
            lastSelectedIndex = displayedFiles.isEmpty ? nil : 0
        }
        .onKeyPress("1") {
            applyRatingToSelection(1)
            return .handled
        }
        .onKeyPress("2") {
            applyRatingToSelection(2)
            return .handled
        }
        .onKeyPress("3") {
            applyRatingToSelection(3)
            return .handled
        }
        .onKeyPress("4") {
            applyRatingToSelection(4)
            return .handled
        }
        .onKeyPress("5") {
            applyRatingToSelection(5)
            return .handled
        }
        .onKeyPress("0") {
            clearRatingForSelection()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -columnCount())
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: columnCount())
            return .handled
        }
        .onKeyPress(.space) {
            if let selected = selectedFileURL {
                showFullPreview = true
                loadFullPreview(for: selected)
                isGalleryFocused = false
                isFullPreviewFocused = true
            }
            return .handled
        }
    }

    private func loadThumbnailIfNeeded(for url: URL) {
        // Check if already loaded or loading
        guard thumbnailStates[url] == nil else { return }
        
        // Check cache first
        if let cachedImage = cache.get(for: url) {
            thumbnailStates[url] = .loaded(cachedImage)
            return
        }
        
        // Mark as loading
        thumbnailStates[url] = .loading
        
        // Generate thumbnail on background thread (lazy loading - only when visible)
        Task {
            if let thumbnail = await generateThumbnail(for: url) {
                // Store in cache
                cache.set(thumbnail, for: url)
                
                // Update UI on main thread
                await MainActor.run {
                    thumbnailStates[url] = .loaded(thumbnail)
                }
            } else {
                await MainActor.run {
                    thumbnailStates[url] = .failed
                }
            }
        }
    }
    
    private func loadFullPreview(for url: URL) {
        isLoadingFullPreview = true
        fullPreviewImage = nil
        
        Task {
            // Extract full JPEG preview (JpgFromRaw - larger, better quality)
            if let jpegData = await extractJPEG(from: url, tag: "JpgFromRaw"),
               let image = createFullPreviewImage(from: jpegData) {
                await MainActor.run {
                    fullPreviewImage = image
                    isLoadingFullPreview = false
                }
            } else {
                await MainActor.run {
                    isLoadingFullPreview = false
                }
            }
        }
    }

    private func importPhotos(_ filesToImport: [URL]) {
        guard let destination = appState.destinationURL,
              let volume = appState.activeVolume,
              !filesToImport.isEmpty else {
            return
        }

        Task {
            let sourceAccessing = volume.path.startAccessingSecurityScopedResource()
            defer { if sourceAccessing { volume.path.stopAccessingSecurityScopedResource() } }

            let destAccessing = BookmarkManager.startAccessing(destination)
            defer { if destAccessing { BookmarkManager.stopAccessing(destination) } }

            let filesNotImported = filesToImport.filter { fileURL in
                let destURL = destination.appendingPathComponent(fileURL.lastPathComponent)
                return !FileManager.default.fileExists(atPath: destURL.path)
            }

            if filesNotImported.isEmpty {
                await MainActor.run {
                    appState.importState = .idle
                    appState.log("Nothing to import — all files already exist in destination")
                }
                return
            }

            await MainActor.run {
                appState.importState = .importing
                appState.importProgress = ImportProgress(
                    totalFiles: filesNotImported.count,
                    startTime: Date()
                )
                appState.log("Importing \(filesNotImported.count) files to \(destination.path)")
            }

            do {
                let engineMode: ImportEngine.Mode = appState.importMode == .copy ? .copy : .move
                let result = try await importEngine.importFiles(
                    from: filesNotImported,
                    to: destination,
                    mode: engineMode,
                    createSubfolder: false
                ) { progress in
                    Task { @MainActor in
                        appState.importProgress.completedFiles = progress.completedFiles
                        appState.importProgress.totalFiles = progress.totalFiles
                        appState.importProgress.transferredBytes = progress.transferredBytes
                        appState.importProgress.totalBytes = progress.totalBytes
                        appState.importProgress.currentFileName = progress.currentFileName
                        appState.importProgress.bytesPerSecond = progress.bytesPerSecond
                    }
                }

                await MainActor.run {
                    appState.importState = .done
                    let report = ImportReport(
                        sourceVolumeName: volume.name,
                        sourcePath: volume.path.path,
                        destinationPath: result.destinationPath,
                        fileCount: result.fileCount,
                        totalBytes: result.totalBytes,
                        duration: result.duration,
                        averageSpeed: result.averageSpeed,
                        importedFiles: result.importedFiles
                    )
                    appState.lastImportReport = report
                    appState.log("Import complete: \(report.summary)")
                }

                let runner = statsRunner ?? StatsRunner(appState: appState)
                await runner.runStats(
                    importedFiles: result.importedFiles,
                    destinationPath: result.destinationPath,
                    duration: result.duration
                )

                if let lastStats = appState.statsReport {
                    appState.totalStatsReport = StatsReport.combine(appState.totalStatsReport, lastStats)
                    appState.log("Total stats updated: \(appState.totalStatsReport?.totalFilesAnalyzed ?? 0) files total")

                    let historyEntry = ImportHistoryEntry(
                        sourceName: volume.name,
                        destinationPath: result.destinationPath,
                        fileCount: result.importedFiles.count,
                        totalBytes: lastStats.totalBytes
                    )
                    ImportHistoryStorage.add(historyEntry)
                    appState.importHistory = ImportHistoryStorage.load()
                }

                try? await Task.sleep(for: .milliseconds(600))
                await MainActor.run {
                    appState.importState = .idle
                }
            } catch {
                await MainActor.run {
                    appState.importState = .error(error.localizedDescription)
                    appState.log("Import failed: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    private func pauseImport() {
        Task {
            await importEngine.pause()
            await MainActor.run {
                appState.importState = .paused
                appState.log("Import paused")
            }
        }
    }

    private func resumeImport() {
        Task {
            await importEngine.resume()
            await MainActor.run {
                appState.importState = .importing
                appState.log("Import resumed")
            }
        }
    }

    private func cancelImport() {
        Task {
            await importEngine.cancel()
            await MainActor.run {
                appState.log("Import cancel requested")
            }
        }
    }

    
    private func navigateToPrevious() {
        guard let currentURL = selectedFileURL,
              let currentIndex = displayedFiles.firstIndex(of: currentURL),
              currentIndex > 0 else { return }
        
        let previousURL = displayedFiles[currentIndex - 1]
        selectedFileURL = previousURL
        loadFullPreview(for: previousURL)
    }
    
    private func navigateToNext() {
        guard let currentURL = selectedFileURL,
              let currentIndex = displayedFiles.firstIndex(of: currentURL),
              currentIndex < displayedFiles.count - 1 else { return }
        
        let nextURL = displayedFiles[currentIndex + 1]
        selectedFileURL = nextURL
        loadFullPreview(for: nextURL)
    }
    
    private func selectPrevious() {
        if let currentURL = selectedFileURL,
           let currentIndex = displayedFiles.firstIndex(of: currentURL),
           currentIndex > 0 {
            selectedFileURL = displayedFiles[currentIndex - 1]
        } else if !displayedFiles.isEmpty {
            selectedFileURL = displayedFiles[0]
        }
    }
    
    private func selectNext() {
        if let currentURL = selectedFileURL,
           let currentIndex = displayedFiles.firstIndex(of: currentURL),
           currentIndex < displayedFiles.count - 1 {
            selectedFileURL = displayedFiles[currentIndex + 1]
        } else if !displayedFiles.isEmpty {
            selectedFileURL = displayedFiles[0]
        }
    }

    private func generateThumbnail(for url: URL) async -> NSImage? {
        // CRITICAL: Use exiftool to extract JPEG preview, NEVER decode RAW!
        // For grid view, use PreviewImage (smaller, faster ~150KB vs 4MB JpgFromRaw)

        if let jpegData = await extractJPEG(from: url, tag: "PreviewImage") {
            return createThumbnail(from: jpegData, filename: url.lastPathComponent)
        }

        print("⚠️ No JPEG preview found for \(url.lastPathComponent)")
        return nil
    }

    private func extractJPEG(from url: URL, tag: String) async -> Data? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/exiftool")
                process.arguments = ["-b", "-\(tag)", url.path]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 && !data.isEmpty {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    print("❌ exiftool error for \(url.lastPathComponent): \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func createThumbnail(from jpegData: Data, filename: String) -> NSImage? {
        // Use NSImage to handle orientation automatically
        guard let nsImage = NSImage(data: jpegData) else {
            print("❌ Failed to decode JPEG for \(filename)")
            return nil
        }
        
        // Get the correct size based on orientation
        let imageSize = nsImage.size
        let maxSize: CGFloat = 300
        
        // Calculate scale to fit within maxSize
        let scale = min(maxSize / imageSize.width, maxSize / imageSize.height)
        let newWidth = imageSize.width * scale
        let newHeight = imageSize.height * scale
        
        // Create thumbnail
        let thumbnailSize = NSSize(width: newWidth, height: newHeight)
        let thumbnailImage = NSImage(size: thumbnailSize)
        
        thumbnailImage.lockFocus()
        nsImage.draw(in: NSRect(origin: .zero, size: thumbnailSize),
                     from: NSRect(origin: .zero, size: imageSize),
                     operation: .copy,
                     fraction: 1.0)
        thumbnailImage.unlockFocus()
        
        return thumbnailImage
    }
    
    private func createFullPreviewImage(from jpegData: Data) -> NSImage? {
        // Use NSImage to handle orientation automatically
        guard let nsImage = NSImage(data: jpegData) else {
            return nil
        }
        
        // Get the correct size
        let imageSize = nsImage.size
        
        // Limit to 2048px max
        let maxSize: CGFloat = 2048
        var finalWidth = imageSize.width
        var finalHeight = imageSize.height
        
        if imageSize.width > maxSize || imageSize.height > maxSize {
            let scale = min(maxSize / imageSize.width, maxSize / imageSize.height)
            finalWidth = imageSize.width * scale
            finalHeight = imageSize.height * scale
        }
        
        // If no resize needed, return original
        if finalWidth == imageSize.width && finalHeight == imageSize.height {
            return nsImage
        }
        
        // Create resized image
        let previewSize = NSSize(width: finalWidth, height: finalHeight)
        let previewImage = NSImage(size: previewSize)
        
        previewImage.lockFocus()
        nsImage.draw(in: NSRect(origin: .zero, size: previewSize),
                     from: NSRect(origin: .zero, size: imageSize),
                     operation: .copy,
                     fraction: 1.0)
        previewImage.unlockFocus()
        
        return previewImage
    }
}

struct PhotoThumbnailCard: View {
    let fileURL: URL
    let thumbnailState: AdvancedView.ThumbnailState
    let isSelected: Bool
    let rating: Int?
    let onRate: (Int) -> Void
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                switch thumbnailState {
                case .loaded(let image):
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 200)
                        .clipped()
                        .transition(.opacity)
                    
                case .loading:
                    Rectangle()
                        .fill(Color.glassBase)
                        .frame(height: 200)
                        .overlay(
                            ProgressView()
                                .controlSize(.large)
                                .tint(.primaryPurple)
                        )
                    
                case .failed:
                    Rectangle()
                        .fill(Color.glassBase)
                        .frame(height: 200)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 24))
                                    .foregroundColor(.textTertiary)
                                Text("Failed to load")
                                    .font(.system(size: 11))
                                    .foregroundColor(.textSecondary)
                            }
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .animation(.easeInOut(duration: 0.3), value: thumbnailState.isLoaded)
            .overlay(alignment: .topTrailing) {
                if let rating = rating {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                        Text("\(rating)")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.yellow)
                    .padding(6)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                    .padding(6)
                }
            }

            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(fileURL.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                if let fileSize = fileSize(for: fileURL) {
                    Text(fileSize)
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            // Rating controls (grid)
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        onRate(value)
                    } label: {
                        Image(systemName: value <= (rating ?? 0) ? "star.fill" : "star")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.glassBase)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
                .shadow(color: (isHovered || isSelected) ? Color.primaryPurple.opacity(0.3) : .clear, radius: 12, x: 0, y: 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.primaryPurple : Color.glassBorder, lineWidth: isSelected ? 3 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onDoubleTap()
        }
        .onTapGesture(count: 1) {
            onSingleTap()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    private func fileSize(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
