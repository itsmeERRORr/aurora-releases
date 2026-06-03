import SwiftUI
import AppKit

struct AdvancedView: View {
    @Bindable var appState: AppState
    let onClose: () -> Void

    @State private var files: [URL] = []
    @State private var selectedFiles: Set<URL> = []
    @State private var selectedFile: URL?
    @State private var lastSelectedIndex: Int?
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
        case .importing, .paused, .scanning, .verifying, .ejecting, .ejectingDone, .generatingStats:
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
            loadFiles()
            isGalleryFocused = true
        }
        .onChange(of: ratingFilter) { _, _ in
            selectedFiles = selectedFiles.intersection(displayedFiles)
            if let selectedFile, !displayedFiles.contains(selectedFile) {
                self.selectedFile = displayedFiles.first
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

                    Button("Close", action: onClose)
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
        guard let volume = appState.activeVolume else { return "No card detected" }
        let selected = selectedFilesInView.count
        if selected > 0 {
            return "\(AuroraFormat.count(selected)) selected from \(AuroraFormat.count(displayedFiles.count)) shown · \(volume.name)"
        }
        return "\(AuroraFormat.count(displayedFiles.count)) files shown · \(AuroraFormat.count(files.count)) RAW files on \(volume.name)"
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
                Text(files.isEmpty ? "Advanced appears only when the active card has source files." : "Change the filter or rate more photos.")
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
        guard let volume = appState.activeVolume, volume.rawFileCount > 0 else {
            files = []
            return
        }
        isLoadingFiles = true
        let path = volume.path
        let extensions = appState.supportedExtensions
        Task {
            let sourceFiles = VolumeWatcher.listRawFiles(at: path, extensions: extensions)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            await MainActor.run {
                appState.updateSourceFiles(sourceFiles)
                files = appState.sortedSourceFiles.isEmpty ? sourceFiles : appState.sortedSourceFiles
                selectedFiles = selectedFiles.intersection(files)
                isLoadingFiles = false
            }
        }
    }

    private func loadThumbnailIfNeeded(for file: URL) {
        guard thumbnailStates[file] == nil else { return }
        if let cached = ThumbnailCache.shared.get(for: file) {
            thumbnailStates[file] = .loaded(cached)
            return
        }
        thumbnailStates[file] = .loading
        Task {
            guard let data = await extractJPEG(from: file, tag: "PreviewImage"),
                  let image = makeImage(from: data, maxPixel: 420) else {
                thumbnailStates[file] = .failed
                return
            }
            ThumbnailCache.shared.set(image, for: file)
            thumbnailStates[file] = .loaded(image)
        }
    }

    private func openPreview(_ file: URL) {
        selectedFile = file
        previewImage = nil
        isLoadingPreview = true
        isGalleryFocused = false
        Task {
            let rawPreview = await extractJPEG(from: file, tag: "JpgFromRaw")
            let fallbackPreview = rawPreview == nil ? await extractJPEG(from: file, tag: "PreviewImage") : nil
            guard let data = rawPreview ?? fallbackPreview,
                  let image = makeImage(from: data, maxPixel: 2400) else {
                isLoadingPreview = false
                return
            }
            previewImage = image
            isLoadingPreview = false
            isPreviewFocused = true
        }
    }

    private func closePreview() {
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
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        let isShift = modifiers.contains(.shift)
        let isCommand = modifiers.contains(.command)

        if isShift, let anchor = lastSelectedIndex {
            let bounds = min(anchor, index)...max(anchor, index)
            let rangeFiles = Set(bounds.map { displayedFiles[$0] })
            selectedFiles = isCommand ? selectedFiles.union(rangeFiles) : rangeFiles
        } else if isCommand {
            if selectedFiles.contains(file) {
                selectedFiles.remove(file)
            } else {
                selectedFiles.insert(file)
            }
        } else {
            selectedFiles = [file]
        }

        selectedFile = selectedFiles.contains(file) ? file : selectedFiles.first
        lastSelectedIndex = index
        isGalleryFocused = true
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
        guard let source = appState.activeVolume,
              let destination = appState.destinationURL else { return }
        let filesToImport = selectedFilesInView
        guard !filesToImport.isEmpty else { return }

        Task {
            let sourceAccessing = source.path.startAccessingSecurityScopedResource()
            defer { if sourceAccessing { source.path.stopAccessingSecurityScopedResource() } }
            let destinationAccessing = BookmarkManager.startAccessing(destination)
            defer { if destinationAccessing { BookmarkManager.stopAccessing(destination) } }

            await MainActor.run {
                appState.importState = .importing
                appState.importProgress = ImportProgress(totalFiles: filesToImport.count, startTime: Date())
                appState.log("Advanced import: \(filesToImport.count) selected files to \(destination.path)")
            }

            do {
                let mode: ImportEngine.Mode = appState.importMode == .copy ? .copy : .move
                let result = try await importEngine.importFiles(from: filesToImport, to: destination, mode: mode) { progress in
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
                    appState.importState = .generatingStats
                    appState.lastImportReport = ImportReport(
                        sourceVolumeName: source.name,
                        sourcePath: source.path.path,
                        destinationPath: result.destinationPath,
                        fileCount: result.fileCount,
                        totalBytes: result.totalBytes,
                        duration: result.duration,
                        averageSpeed: result.averageSpeed,
                        importedFiles: result.importedFiles
                    )
                    appState.log("Advanced import complete: \(result.fileCount) files")
                }

                let runner = StatsRunner(appState: appState)
                await runner.runStats(importedFiles: result.importedFiles, destinationPath: result.destinationPath, duration: result.duration)

                await MainActor.run {
                    if let lastStats = appState.statsReport {
                        appState.totalStatsReport = StatsReport.combine(appState.totalStatsReport, lastStats)
                        ImportHistoryStorage.add(ImportHistoryEntry(
                            sourceName: source.name,
                            destinationPath: result.destinationPath,
                            fileCount: result.importedFiles.count,
                            totalBytes: lastStats.totalBytes
                        ))
                        appState.importHistory = ImportHistoryStorage.load()
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

    private func extractJPEG(from file: URL, tag: String) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/exiftool")
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

    private func makeImage(from data: Data, maxPixel: CGFloat) -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }
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
