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
    @State private var showLicenseExpiredAlert = false
    @State private var importEngine = ImportEngine()
    @State private var selectedSourceID: String?
    private let gridPanelWidth: CGFloat = 450
    @State private var loadFilesTask: Task<Void, Never>?
    @State private var thumbnailTasks: [URL: Task<Void, Never>] = [:]
    @State private var panelImageStates: [URL: ThumbnailState] = [:]
    @State private var panelImageTasks: [URL: Task<Void, Never>] = [:]
    @State private var panelRawLoaded: Set<URL> = []
    @State private var previewTask: Task<Void, Never>?
    @State private var modifierEventMonitor: Any?
    @State private var currentModifierFlags: NSEvent.ModifierFlags = []
    @State private var mouseDownModifierFlags: NSEvent.ModifierFlags = []
    @State private var totalBytes: Int64 = 0

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
        case .all:    return files
        case .rated:  return files.filter { rating(for: $0) != nil }
        case .unrated: return files.filter { rating(for: $0) == nil }
        }
    }

    private var selectedFilesInView: [URL] {
        displayedFiles.filter { selectedFiles.contains($0) }
    }

    private var showImportOverlay: Bool {
        switch appState.importState {
        case .importing, .paused, .scanning, .verifying, .ejecting, .ejectingDone, .error:
            return true
        default:
            return false
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar

                Rectangle().fill(Color.auroraStroke).frame(height: 1)

                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        largePreviewPanel
                            .aspectRatio(3/2, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                        sourceHeaderInfo
                            .padding(.horizontal, 4)
                            .padding(.top, 10)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1)
                    thumbnailGridPanel
                        .frame(width: 450, height: 524)
                        .clipped()
                }
                .frame(height: 524)

                Rectangle().fill(Color.auroraStroke).frame(height: 1)

                bottomBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AuroraBackground())

            if let selectedFile, let previewImage {
                previewOverlay(file: selectedFile, image: previewImage)
            } else if isLoadingPreview {
                previewLoadingOverlay
            }

            if showImportOverlay {
                Color.black.opacity(0.38).ignoresSafeArea()
                ProgressOverlayView(
                    appState: appState,
                    onPause: pauseImport,
                    onResume: resumeImport,
                    onCancel: cancelImport
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(minWidth: 1100, idealWidth: 1280, maxWidth: .infinity,
               minHeight: 618, idealHeight: 720, maxHeight: .infinity)
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
        .onChange(of: selectedFile) { _, file in
            if let file {
                loadThumbnailIfNeeded(for: file)
                loadPanelImageIfNeeded(for: file)
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
        .alert("License Expired", isPresented: $showLicenseExpiredAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your Aurora license has expired. Renew your license to continue importing.")
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Aurora — Advanced Import")
                .font(.sora(14, weight: .bold))
                .foregroundStyle(Color.auroraTxt)

            Spacer(minLength: 12)

            if !files.isEmpty {
                HStack(spacing: 6) {
                    filterPill(.all)
                    filterPill(.rated)
                    filterPill(.unrated)
                }
            }

            Spacer().frame(width: 4)

            Button("Close", action: closeAdvanced)
                .buttonStyle(AuroraGhostButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var sourceHeaderInfo: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.auroraCyan.opacity(0.16))
                Image(systemName: "sdcard.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.auroraCyan)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                if sourceVolumes.count > 1 {
                    sourceMenu
                } else {
                    Text(headerTitle)
                        .font(.sora(14, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                        .lineLimit(1)
                }
                Text(headerSubtitle)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
                    .lineLimit(1)
            }
        }
    }

    private var sourceMenu: some View {
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
            HStack(spacing: 5) {
                Text(headerTitle)
                    .font(.sora(14, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var headerTitle: String {
        if isLoadingFiles { return "Scanning source files…" }
        guard !sourceVolumes.isEmpty else { return "No card detected" }
        if files.isEmpty { return sourceSelectionTitle }
        return "\(sourceSelectionTitle) — \(AuroraFormat.count(files.count)) \(files.count == 1 ? "RAW" : "RAWs")"
    }

    private var headerSubtitle: String {
        guard !files.isEmpty else { return "Insert a card with RAW files to begin" }
        var parts: [String] = []
        if totalBytes > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
        }
        let thumbsLoading = displayedFiles.prefix(24).contains { (thumbnailStates[$0] ?? .loading) == .loading }
        if thumbsLoading {
            parts.append("reading previews")
        } else {
            let picks = files.filter { rating(for: $0) != nil }.count
            parts.append(picks > 0 ? "\(AuroraFormat.count(picks)) picks" : "no picks yet")
        }
        return parts.joined(separator: " · ")
    }

    private func filterPill(_ filter: RatingFilter) -> some View {
        let isActive = ratingFilter == filter
        return Button {
            ratingFilter = filter
        } label: {
            HStack(spacing: 5) {
                if filter == .rated {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                } else if filter == .unrated {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(filterPillTitle(filter))
                    .font(.manrope(11, weight: .bold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isActive ? Color.auroraCyan.opacity(0.18) : Color.auroraPanel)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Color.auroraCyan.opacity(0.55) : Color.auroraStroke, lineWidth: 1)
            )
            .foregroundStyle(isActive ? Color.auroraCyan : Color.auroraMuted)
        }
        .buttonStyle(.plain)
    }

    private func filterPillTitle(_ filter: RatingFilter) -> String {
        switch filter {
        case .all:     return "All \(AuroraFormat.count(files.count))"
        case .rated:   return "Picks \(AuroraFormat.count(files.filter { rating(for: $0) != nil }.count))"
        case .unrated: return "Unrated \(AuroraFormat.count(files.filter { rating(for: $0) == nil }.count))"
        }
    }

    // MARK: - Large Preview Panel

    private var largePreviewPanel: some View {
        previewImageArea
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var previewImageArea: some View {
        let file = selectedFile ?? displayedFiles.first
        return ZStack {
            Color.clear

            if let file {
                let panelState = panelImageStates[file] ?? .loading

                // Photo
                switch panelState {
                case .loaded(let img):
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loading:
                    ProgressView()
                        .controlSize(.large)
                        .tint(Color.auroraCyan)
                case .failed:
                    Image(systemName: "photo")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(Color.auroraFaint)
                }

                // Gradient overlays for legibility
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.55), Color.clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 80)
                    Spacer()
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.62)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 100)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

                // UI overlay (PICK, counter, stars, filename)
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        if rating(for: file) != nil {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color.auroraHealthy)
                                    .frame(width: 7, height: 7)
                                Text("PICK")
                                    .font(.manrope(10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .tracking(0.8)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.auroraHealthy.opacity(0.22)))
                            .overlay(Capsule().strokeBorder(Color.auroraHealthy.opacity(0.45), lineWidth: 1))
                        }
                        Spacer()
                        Text(fileCounter)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                    }
                    .padding(16)

                    Spacer()

                    HStack(alignment: .bottom) {
                        HStack(spacing: 7) {
                            ForEach(1...5, id: \.self) { value in
                                Button {
                                    setRating(value, for: file)
                                    isGalleryFocused = true
                                } label: {
                                    Image(systemName: value <= (rating(for: file) ?? 0) ? "star.fill" : "star")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Color.yellow)
                                }
                                .buttonStyle(.plain)
                            }
                            if rating(for: file) != nil {
                                Button {
                                    clearRating(for: file)
                                    isGalleryFocused = true
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.white.opacity(0.42))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(file.lastPathComponent)
                                .font(.manrope(11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 220, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if !isLoadingFiles {
                VStack(spacing: 12) {
                    IconChip(systemName: "photo.on.rectangle.angled", color: .auroraViolet, size: 54, iconScale: 0.48)
                    Text("Select a photo")
                        .font(.manrope(16, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                    Text("Click any thumbnail to preview")
                        .font(.manrope(12, weight: .semibold))
                        .foregroundStyle(Color.auroraMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileCounter: String {
        guard let file = selectedFile,
              let index = displayedFiles.firstIndex(of: file) else {
            return displayedFiles.isEmpty ? "0 / 0" : "– / \(displayedFiles.count)"
        }
        return String(format: "%04d / %04d", index + 1, displayedFiles.count)
    }

    // MARK: - Thumbnail Grid Panel

    @ViewBuilder
    private var thumbnailGridPanel: some View {
        if isLoadingFiles {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Loading RAW files…")
                    .font(.manrope(12, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.auroraBg)
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
            .background(Color.auroraBg)
        } else {
            let gap: CGFloat = 10
            let pad: CGFloat = 12
            // Each cell = tileSize + gap (gap split as padding around each tile)
            let cellSize: CGFloat = max(80, floor((gridPanelWidth - pad * 2) / 3))
            let tileSize: CGFloat = max(60, cellSize - gap)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(cellSize), spacing: 0), count: 3),
                        spacing: 0
                    ) {
                        ForEach(Array(displayedFiles.enumerated()), id: \.element) { index, file in
                            AdvancedThumb(
                                file: file,
                                size: tileSize,
                                thumbnailState: thumbnailStates[file] ?? .loading,
                                isSelected: selectedFiles.contains(file),
                                isFocused: selectedFile == file,
                                rating: rating(for: file),
                                onSelect: { handleSelection(file, index: index) },
                                onPreview: { openPreview(file) },
                                onRate: { setRating($0, for: file) }
                            )
                            .id(file)
                            .padding(gap / 2)
                            .onAppear { loadThumbnailIfNeeded(for: file) }
                            .contextMenu {
                                Button("Import This Photo") {
                                    selectedFiles = [file]
                                    selectedFile = file
                                    beginImportConfirmation()
                                }
                                Divider()
                                Button("Clear Rating") { clearRating(for: file) }
                            }
                        }
                    }
                    .padding(.top, 5)
                    .padding([.bottom, .leading, .trailing], pad)
                }
                .scrollIndicators(.hidden)
                .onChange(of: selectedFile) { _, file in
                    if let file {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(file, anchor: .center)
                        }
                    }
                }
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
            .onKeyPress(.leftArrow)  { moveSelection(by: -1); return .handled }
            .onKeyPress(.rightArrow) { moveSelection(by:  1); return .handled }
            .onKeyPress(.upArrow)    { moveSelection(by: -3); return .handled }
            .onKeyPress(.downArrow)  { moveSelection(by:  3); return .handled }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 14) {
                shortcutChip("1–5", "Rate")
                shortcutChip("←→", "Navigate")
                shortcutChip("Space", "Loupe 100%")
                shortcutChip("⌘A", "Select all")
            }
            .padding(.leading, 20)

            Spacer()

            Text(destinationLabel)
                .font(.manrope(10.5, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 260, alignment: .trailing)

            Spacer().frame(width: 16)

            Button { beginImportConfirmation() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .bold))
                    Text(importButtonLabel)
                }
            }
            .buttonStyle(AuroraGradientButtonStyle(compact: true))
            .disabled(selectedFilesInView.isEmpty || appState.destinationURL == nil)
            .opacity(selectedFilesInView.isEmpty || appState.destinationURL == nil ? 0.45 : 1)
            .padding(.trailing, 20)
        }
        .frame(height: 52)
        .background(Color.auroraPanel2)
    }

    private var importButtonLabel: String {
        let count = selectedFilesInView.count
        return count > 0 ? "Import \(count) selected" : "Import Selected"
    }

    private func shortcutChip(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.auroraTxt)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.auroraPanel))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.auroraStroke, lineWidth: 0.5))
            Text(label)
                .font(.manrope(10, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
        }
    }

    // MARK: - Preview Overlay (full-res loupe)

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
            Color.black.opacity(0.94).ignoresSafeArea()

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
        .onKeyPress(.leftArrow)  { navigatePreview(offset: -1); return .handled }
        .onKeyPress(.rightArrow) { navigatePreview(offset:  1); return .handled }
        .onKeyPress("1") { setRating(1, for: file); return .handled }
        .onKeyPress("2") { setRating(2, for: file); return .handled }
        .onKeyPress("3") { setRating(3, for: file); return .handled }
        .onKeyPress("4") { setRating(4, for: file); return .handled }
        .onKeyPress("5") { setRating(5, for: file); return .handled }
        .onKeyPress("0") { clearRating(for: file); return .handled }
    }

    // MARK: - File Loading

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
                computeTotalBytes(for: files)
                if selectedFile == nil, let first = displayedFiles.first,
                   let idx = displayedFiles.firstIndex(of: first) {
                    selectedFile = first
                    lastSelectedIndex = idx
                    selectionAnchorIndex = idx
                }
            }
        }
    }

    private func clearLoadedGalleryState() {
        previewTask?.cancel()
        previewTask = nil
        for task in thumbnailTasks.values { task.cancel() }
        thumbnailTasks.removeAll()
        thumbnailStates = [:]
        totalBytes = 0
        for task in panelImageTasks.values { task.cancel() }
        panelImageTasks.removeAll()
        panelImageStates = [:]
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
        modifierEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .leftMouseDown, .keyDown]) { [self] event in
            let relevantFlags = relevantModifierFlags(event.modifierFlags)
            currentModifierFlags = relevantFlags
            if event.type == .leftMouseDown { mouseDownModifierFlags = relevantFlags }
            if event.type == .keyDown && event.keyCode == 49 && previewImage == nil && !isLoadingPreview {
                if let file = selectedFile {
                    DispatchQueue.main.async { openPreview(file) }
                    return nil
                }
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
        for task in thumbnailTasks.values { task.cancel() }
        thumbnailTasks.removeAll()
        for task in panelImageTasks.values { task.cancel() }
        panelImageTasks.removeAll()
    }

    // Preloads QL preview for a single file (phase 1 only, no RAW decode).
    private func preloadPanelQuickPreview(for file: URL) {
        guard panelImageStates[file] == nil, panelImageTasks[file] == nil else { return }
        panelImageStates[file] = .loading
        panelImageTasks[file] = Task {
            let quick = await quickLookImage(for: file, maxPixel: 600, scale: 1)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                panelImageTasks[file] = nil
                panelImageStates[file] = quick.map { .loaded($0) } ?? .failed
            }
        }
    }

    // Called for all files on load — fills panelImageStates with QL previews quickly.
    private func preloadAllPanelQuickPreviews() {
        for file in displayedFiles {
            preloadPanelQuickPreview(for: file)
        }
    }

    // Called for the selected file — upgrades to full RAW quality if not already done.
    private func loadPanelImageIfNeeded(for file: URL) {
        guard !panelRawLoaded.contains(file) else { return }
        guard panelImageTasks[file] == nil else { return }
        panelImageTasks[file] = Task {
            // Phase 1: only if not already loaded by quick preload
            if panelImageStates[file] == nil {
                panelImageStates[file] = .loading
                let quick = await quickLookImage(for: file, maxPixel: 600, scale: 1)
                if let quick, !Task.isCancelled {
                    await MainActor.run { panelImageStates[file] = .loaded(quick) }
                }
            }
            guard !Task.isCancelled else { return }
            // Phase 2: RAW decode for full quality
            let hq = await Task.detached(priority: .userInitiated) { [self] in
                rawDecodeImage(for: file, maxPixel: 2048, fullDecode: true)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                panelImageTasks[file] = nil
                if let hq {
                    panelImageStates[file] = .loaded(hq)
                    panelRawLoaded.insert(file)
                }
            }
        }
    }

    private func rawDecodeImage(for file: URL, maxPixel: CGFloat, fullDecode: Bool) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel)
        ]
        if fullDecode {
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
            options[kCGImageSourceShouldAllowFloat] = true
        } else {
            options[kCGImageSourceCreateThumbnailFromImageIfAbsent] = true
        }
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func loadThumbnailIfNeeded(for file: URL) {
        guard thumbnailStates[file] == nil, thumbnailTasks[file] == nil else { return }
        if let cached = ThumbnailCache.shared.get(for: file) {
            thumbnailStates[file] = .loaded(cached)
            return
        }
        thumbnailStates[file] = .loading
        thumbnailTasks[file] = Task.detached(priority: .userInitiated) { [self] in
            let image = await thumbnailImage(for: file)
            guard !Task.isCancelled else { return }
            let square = image.map { squareCrop($0) }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                thumbnailTasks[file] = nil
                guard let square else { thumbnailStates[file] = .failed; return }
                ThumbnailCache.shared.set(square, for: file)
                thumbnailStates[file] = .loaded(square)
            }
        }
    }

    private nonisolated func squareCrop(_ image: NSImage) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let w = cg.width
        let h = cg.height
        guard w > 0, h > 0, w != h else { return image }
        let side = min(w, h)
        let cropRect = CGRect(x: (w - side) / 2, y: (h - side) / 2, width: side, height: side)
        guard let cropped = cg.cropping(to: cropRect) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: side, height: side))
    }

    private func prefetchInitialThumbnails(limit: Int = 18) {
        for file in displayedFiles.prefix(limit) {
            loadThumbnailIfNeeded(for: file)
        }
        preloadAllPanelQuickPreviews()
        if let first = displayedFiles.first {
            loadPanelImageIfNeeded(for: first)
        }
    }

    private func computeTotalBytes(for urls: [URL]) {
        Task.detached(priority: .utility) {
            var sum: Int64 = 0
            for url in urls {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                sum += Int64(size)
            }
            await MainActor.run { totalBytes = sum }
        }
    }

    private func openPreview(_ file: URL) {
        previewTask?.cancel()
        selectedFile = file
        previewImage = nil
        isLoadingPreview = true
        isGalleryFocused = false
        previewTask = Task {
            // Phase 1: fast embedded preview
            let quick = await Task.detached(priority: .userInitiated) { [self] in
                rawDecodeImage(for: file, maxPixel: 1400, fullDecode: false)
            }.value
            if let quick, !Task.isCancelled {
                await MainActor.run {
                    guard selectedFile == file else { return }
                    previewImage = quick
                    isLoadingPreview = false
                }
            }
            guard !Task.isCancelled else { return }
            // Phase 2: full quality
            let image = await fullPreviewImage(for: file)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                previewTask = nil
                guard selectedFile == file, let image else { isLoadingPreview = false; return }
                previewImage = image
                isLoadingPreview = false
                isPreviewFocused = true
            }
        }
    }

    private func thumbnailImage(for file: URL) async -> NSImage? {
        if Task.isCancelled { return nil }
        if let image = await quickLookImage(for: file, maxPixel: 320, scale: 1) { return image }
        for tag in ["PreviewImage", "ThumbnailImage", "JpgFromRaw"] {
            if Task.isCancelled { return nil }
            guard let data = await extractJPEG(from: file, tag: tag) else { continue }
            if Task.isCancelled { return nil }
            if let image = makeImage(from: data, maxPixel: 320) { return image }
        }
        return nil
    }

    private func fullPreviewImage(for file: URL) async -> NSImage? {
        if Task.isCancelled { return nil }
        if let img = await Task.detached(priority: .userInitiated) { [self] in
            rawDecodeImage(for: file, maxPixel: 3000, fullDecode: true)
        }.value { return img }
        if Task.isCancelled { return nil }
        return await quickLookImage(for: file, maxPixel: 2400)
    }

    private func closePreview() {
        previewTask?.cancel()
        previewTask = nil
        previewImage = nil
        isLoadingPreview = false
        isPreviewFocused = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isGalleryFocused = true
        }
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
            if selectedFiles.contains(file) { selectedFiles.remove(file) }
            else { selectedFiles.insert(file) }
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

    // MARK: - Ratings

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
        for file in selectedFilesInView { setRating(rating, for: file) }
    }

    private func clearSelectionRatings() {
        for file in selectedFilesInView { clearRating(for: file) }
    }

    // MARK: - Import

    private var destinationLabel: String {
        if let destination = appState.destinationURL {
            return "Destination: \(destination.path)"
        }
        return "Choose a destination before importing"
    }

    private func beginImportConfirmation() {
        guard appState.canUseTrialAction() else { appState.requestActivationForTrialLimit(); return }
        guard !selectedFilesInView.isEmpty else { showNoSelectionAlert = true; return }
        guard appState.destinationURL != nil else { showNoDestinationAlert = true; return }
        showImportConfirmation = true
    }

    private func importSelectedFiles() {
        guard let destination = appState.destinationURL else { return }
        let filesToImport = selectedFilesInView
        guard !filesToImport.isEmpty else { return }
        let importSources = sources(containing: filesToImport)
        guard !importSources.isEmpty else { return }
        guard appState.consumeTrialAction("advanced import") else { return }
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
                        appState.importProgress.failedFiles = progress.failedFiles
                        appState.importProgress.copiedAfterMoveFailureFiles = progress.copiedAfterMoveFailureFiles
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
                    logImportOutcome(result)
                    if result.skippedFiles > 0 {
                        appState.log("Advanced import skipped \(result.skippedFiles) duplicate file\(result.skippedFiles == 1 ? "" : "s") already present in destination")
                    }
                    if result.importedFiles.isEmpty {
                        appState.sourceFileCountForDestinationCheck = result.skippedFiles + result.failedFiles
                        appState.allDestinationFilesAlreadyImported = result.failedFiles == 0 && result.skippedFiles > 0
                        appState.sourceFilesImportStatusMessage = Self.importOutcomeMessage(skippedFiles: result.skippedFiles, failedFiles: result.failedFiles, copiedAfterMoveFailureFiles: result.copiedAfterMoveFailureFiles, allSkipped: result.failedFiles == 0)
                        appState.importState = .idle
                    } else if result.skippedFiles > 0 || result.failedFiles > 0 || result.copiedAfterMoveFailureFiles > 0 {
                        appState.sourceFileCountForDestinationCheck = result.skippedFiles + result.failedFiles
                        appState.allDestinationFilesAlreadyImported = false
                        appState.sourceFilesImportStatusMessage = Self.importOutcomeMessage(skippedFiles: result.skippedFiles, failedFiles: result.failedFiles, copiedAfterMoveFailureFiles: result.copiedAfterMoveFailureFiles, allSkipped: false)
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
                        appState.refreshJPGDayCacheForImportedDestination(result.destinationPath)
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

    @MainActor
    private func logImportOutcome(_ result: ImportResult) {
        if result.copiedAfterMoveFailureFiles > 0 {
            let movedFiles = max(result.fileCount - result.copiedAfterMoveFailureFiles, 0)
            appState.log("Advanced import moved \(movedFiles) file\(movedFiles == 1 ? "" : "s"); copied \(result.copiedAfterMoveFailureFiles) because source delete failed", level: .warning)
            let diagnosticsToLog = result.moveFallbackDiagnostics.prefix(20)
            for diagnostic in diagnosticsToLog {
                appState.log("Advanced import move fallback diagnostic: \(diagnostic)", level: .warning)
            }
            if result.moveFallbackDiagnostics.count > diagnosticsToLog.count {
                appState.log("Advanced import move fallback diagnostic: \(result.moveFallbackDiagnostics.count - diagnosticsToLog.count) additional file\(result.moveFallbackDiagnostics.count - diagnosticsToLog.count == 1 ? "" : "s") omitted", level: .warning)
            }
        } else if appState.importMode == .move {
            appState.log("Advanced import moved \(result.fileCount) file\(result.fileCount == 1 ? "" : "s")")
        }
        if result.failedFiles > 0 {
            appState.log("Advanced import failed \(result.failedFiles) locked or unreadable file\(result.failedFiles == 1 ? "" : "s")", level: .warning)
        }
    }

    private static func importOutcomeMessage(skippedFiles: Int, failedFiles: Int, copiedAfterMoveFailureFiles: Int, allSkipped: Bool) -> String? {
        var messages: [String] = []
        if skippedFiles > 0 {
            let prefix = allSkipped ? "All" : "Skipped"
            messages.append("\(prefix) \(skippedFiles) duplicate file\(skippedFiles == 1 ? "" : "s")\(allSkipped ? " already imported" : "")")
        }
        if copiedAfterMoveFailureFiles > 0 {
            messages.append("Copied \(copiedAfterMoveFailureFiles) because source delete failed")
        }
        if failedFiles > 0 {
            messages.append("Failed \(failedFiles) locked or unreadable file\(failedFiles == 1 ? "" : "s")")
        }
        return messages.isEmpty ? nil : messages.joined(separator: ". ")
    }

    private func resumeImport() {
        Task {
            await importEngine.resume()
            await MainActor.run { appState.importState = .importing }
        }
    }

    private func cancelImport() {
        Task { await importEngine.cancel() }
    }

    // MARK: - Volume Helpers

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

    // MARK: - Image Helpers

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
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
        resized.unlockFocus()
        return resized
    }

    private func makeImage(from data: Data, maxPixel: CGFloat) -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }
        return makeImage(from: image, maxPixel: maxPixel)
    }
}

// MARK: - Helpers

private func relevantModifierFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
    flags.intersection([.shift, .command, .option, .control])
}

private func exiftoolPath() -> String? {
    var paths: [String] = []
    if let bundled = Bundle.main.path(forResource: "exiftool", ofType: nil) {
        paths.append(bundled)
    }
    paths += ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool"]
    return paths.first { FileManager.default.fileExists(atPath: $0) }
}

// MARK: - Thumbnail Cell

private struct AdvancedThumb: View {
    let file: URL
    let size: CGFloat
    let thumbnailState: AdvancedView.ThumbnailState
    let isSelected: Bool
    let isFocused: Bool
    let rating: Int?
    let onSelect: () -> Void
    let onPreview: () -> Void
    let onRate: (Int) -> Void

    private var thumbSize: CGFloat { size }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.auroraPanel2

            switch thumbnailState {
            case .loading:
                ProgressView().scaleEffect(0.65)
            case .failed:
                Image(systemName: "photo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
            case .loaded(let img):
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: thumbSize, height: thumbSize)
                    .clipped()
            }

            if rating != nil {
                Circle()
                    .fill(Color.auroraHealthy)
                    .frame(width: 7, height: 7)
                    .padding(6)
            }

            if let rating {
                VStack {
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { v in
                            Image(systemName: v <= rating ? "star.fill" : "star")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(Color.yellow)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(Color.black.opacity(0.55))
                }
            }
        }
        .frame(width: thumbSize, height: thumbSize)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isFocused ? Color.auroraCyan
                              : (isSelected ? Color.auroraCyan.opacity(0.5) : Color.clear),
                    lineWidth: isFocused ? 2.5 : 1.5
                )
        )
        .shadow(color: isFocused ? Color.auroraCyan.opacity(0.3) : .clear, radius: 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onPreview)
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
    }
}
