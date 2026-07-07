import SwiftUI
import AppKit

/// JPG gallery for an event — filterable by camera and lens. Reads from
/// `GalleryPhotoRecord`s already built by `EventGalleryStore` (thumbnails and EXIF
/// persisted separately from the source folder, so this keeps working even after
/// the event is finalized and the folder moves — see `GalleryFullscreenView` for
/// what happens if the original file truly can't be found anymore).
struct EventGalleryCard: View {
    let photos: [GalleryPhotoRecord]
    let isBuilding: Bool
    /// Total JPGs the in-progress build found (known right after the initial
    /// filesystem enumeration, before any batch has been processed) — lets the
    /// "Loading more JPGs…" indicator show real progress like "1200/3000" instead of
    /// just a spinner.
    let buildTotal: Int?
    /// The JPG count already known from the (much cheaper) day-count scan, shown
    /// while the gallery itself is still building — otherwise the subtitle reads
    /// "0 JPGs found" even though the JPGs per day card right above already shows
    /// the real total.
    let knownJPGCount: Int
    let appState: AppState

    @State private var selectedCameras: Set<String> = []
    @State private var selectedLenses: Set<String> = []
    @State private var isFilterPresented = false

    /// The grid's viewport caps out at roughly this many rows (~30 thumbnails across
    /// 6 columns) regardless of how many photos the gallery has — beyond that, all of
    /// them still load and render, but the card itself never grows past this height;
    /// scrolling happens *inside* the card, not by growing the page. Below that count
    /// (e.g. a 30-photo gallery), the viewport shrinks to fit instead of reserving
    /// dead space for rows that don't exist.
    private static let columns = 6
    private static let maxVisibleRows = 5 // ceil(30 / columns)
    private static let thumbnailHeight: CGFloat = 90
    private static let gridSpacing: CGFloat = 8

    private var gridHeight: CGFloat {
        let totalRows = Int((Double(filteredPhotos.count) / Double(Self.columns)).rounded(.up))
        let rows = min(max(totalRows, 1), Self.maxVisibleRows)
        return CGFloat(rows) * Self.thumbnailHeight + CGFloat(rows - 1) * Self.gridSpacing
    }

    private var cameras: [String] {
        Array(Set(photos.compactMap(\.camera))).sorted()
    }
    private var lenses: [String] {
        Array(Set(photos.compactMap(\.lens))).sorted { lhs, rhs in
            let l = Self.leadingFocalLength(lhs)
            let r = Self.leadingFocalLength(rhs)
            if l != r { return l < r }
            return lhs < rhs
        }
    }

    /// The widest (smallest-number) focal length in a lens name, e.g. 16 for
    /// "Sony FE 16-35mm F2.8 GM II" or 50 for "Sony FE 50mm F1.2 GM" — used to sort
    /// the lens filter shortest-to-longest instead of alphabetically. Falls back to
    /// sorting last if no focal length can be parsed out of the name.
    private static func leadingFocalLength(_ lens: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\s*-\s*\d+\s*mm|(\d+)\s*mm"#, options: .caseInsensitive) else {
            return Int.max
        }
        let range = NSRange(lens.startIndex..., in: lens)
        guard let match = regex.firstMatch(in: lens, options: [], range: range) else { return Int.max }
        for groupIndex in 1...2 {
            if let matchRange = Range(match.range(at: groupIndex), in: lens), let value = Int(lens[matchRange]) {
                return value
            }
        }
        return Int.max
    }

    private var activeFilterCount: Int {
        (selectedCameras.isEmpty ? 0 : 1) + (selectedLenses.isEmpty ? 0 : 1)
    }

    private var filteredPhotos: [GalleryPhotoRecord] {
        let matches = photos.filter { photo in
            if !selectedCameras.isEmpty, !(photo.camera.map(selectedCameras.contains) ?? false) { return false }
            if !selectedLenses.isEmpty, !(photo.lens.map(selectedLenses.contains) ?? false) { return false }
            return true
        }
        // While the gallery is still streaming in, batches land in filesystem
        // enumeration order rather than date order — re-sorting by captureDate on
        // every batch reshuffled already-visible thumbnails to new grid positions
        // mid-scroll/mid-click, so a tap could land on a button that moved out from
        // under it a frame earlier and silently do nothing. Keep arrival order
        // stable (append-only, nothing already on screen moves) until the build is
        // done, then apply the real chronological sort once.
        guard !isBuilding else { return matches }
        return matches.sorted { ($0.captureDate ?? .distantPast) < ($1.captureDate ?? .distantPast) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        AuroraCollapsibleHeaderTitle(title: "Gallery")
                        Image(systemName: "info.circle")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.auroraFaint)
                            .auroraTooltip("Large galleries can take a moment to feel fully smooth while every photo loads in — this gets better once everything's finished loading. Collapsing this card also makes the rest of the app feel snappier in the meantime.", edge: .bottom)
                    }
                    GalleryCollapsedGate {
                        Text(subtitleText)
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                    }
                }
                Spacer()
                // Only shown once there's already a grid on screen being refreshed —
                // during the initial build (no photos yet) the big `buildingState`
                // below already communicates that, and this spinner sitting where the
                // "Filter by" pill usually goes reads as the filter button being
                // stuck loading.
                if isBuilding, !photos.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text(loadingMoreText)
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                    }
                }
                if !cameras.isEmpty || !lenses.isEmpty {
                    GalleryCollapsedGate {
                        filterByButton
                    }
                }
            }

            GalleryCollapsedGate {
                if photos.isEmpty, isBuilding {
                    buildingState
                } else if filteredPhotos.isEmpty {
                    emptyState
                } else {
                    // Capped-height viewport (~30 thumbnails' worth, shrinking to fit
                    // when there are fewer) that scrolls internally — the card's own
                    // size never grows past that with the gallery, whether it has 30
                    // photos or 1400; the user scrolls inside it.
                    ScrollView(.vertical) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.gridSpacing), count: Self.columns), spacing: Self.gridSpacing) {
                            ForEach(Array(filteredPhotos.enumerated()), id: \.element.id) { index, photo in
                                thumbnail(for: photo, index: index)
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: gridHeight)
                }
            }
        }
        .auroraCollapsibleStaticCard(storageKey: "event.gallery")
    }

    private var subtitleText: String {
        let total = photos.count
        let shown = filteredPhotos.count
        if total == 0, isBuilding, knownJPGCount > 0 {
            return "\(AuroraFormat.count(knownJPGCount)) JPGs found in this event"
        }
        if shown == total { return "\(AuroraFormat.count(total)) JPGs found in this event" }
        return "\(AuroraFormat.count(shown)) of \(AuroraFormat.count(total)) JPGs match the active filters"
    }

    private var loadingMoreText: String {
        guard let buildTotal, buildTotal > 0 else { return "Loading more JPGs…" }
        return "Loading more JPGs… (\(AuroraFormat.count(photos.count))/\(AuroraFormat.count(buildTotal)))"
    }

    // MARK: - Filter by

    private var filterByButton: some View {
        Button {
            isFilterPresented = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 10.5, weight: .bold))
                Text("Filter by")
                    .font(.manrope(12, weight: .semibold))
                if activeFilterCount > 0 {
                    Text("\(activeFilterCount)")
                        .font(.manrope(10, weight: .bold))
                        .foregroundStyle(Color.auroraBg)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(Capsule(style: .continuous).fill(Color.auroraCyan))
                }
            }
            .foregroundStyle(activeFilterCount > 0 ? Color.auroraTxt : Color.auroraMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(activeFilterCount > 0 ? Color.auroraPanel2 : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(activeFilterCount > 0 ? Color.auroraCyan.opacity(0.4) : Color.auroraStroke2, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isFilterPresented, arrowEdge: .bottom) {
            filterPopoverContent
        }
    }

    private var filterPopoverContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Filter by")
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Spacer()
                if activeFilterCount > 0 {
                    Button("Clear") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedCameras.removeAll()
                            selectedLenses.removeAll()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.manrope(11.5, weight: .semibold))
                    .foregroundStyle(Color.auroraCyan)
                }
            }

            if !cameras.isEmpty {
                filterGroup(label: "CAMERA", values: cameras, selection: $selectedCameras)
            }
            if !lenses.isEmpty {
                filterGroup(label: "LENS", values: lenses, selection: $selectedLenses)
            }
        }
        .padding(16)
        .frame(width: filterPopoverWidth)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .fill(Color.auroraBg2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke2, lineWidth: 1)
        )
    }

    /// Widens to fit the longest camera/lens pill (some lens names are long, e.g.
    /// "Sigma 15mm F1.4 DG DN DIAGONAL FISHEYE"), clamped to a sane range.
    private var filterPopoverWidth: CGFloat {
        let longest = (cameras + lenses).map(chipWidth).max() ?? 0
        // Extra buffer beyond the popover's own 16pt side padding: NSFont measurement
        // slightly underestimates the app's custom Manrope metrics, so without this
        // the widest pill ends up flush against the trailing edge instead of matching
        // the leading margin.
        return min(max(longest + 32 + 16, 280), 460)
    }

    private func chipWidth(_ text: String) -> CGFloat {
        let font = NSFont(name: AuroraFontFamily.manrope, size: 11.5) ?? NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        return (text as NSString).size(withAttributes: [.font: font]).width + 24
    }

    private func filterGroup(label: String, values: [String], selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.manrope(10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.auroraFaint)
            FlowLayout(spacing: 6) {
                ForEach(values, id: \.self) { value in
                    filterChip(value, isSelected: selection.wrappedValue.contains(value)) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if selection.wrappedValue.contains(value) {
                                selection.wrappedValue.remove(value)
                            } else {
                                selection.wrappedValue.insert(value)
                            }
                        }
                    }
                }
            }
        }
    }

    private func filterChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.manrope(11.5, weight: .semibold))
                .foregroundStyle(isSelected ? Color.auroraCyan : Color.auroraMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.auroraCyan.opacity(0.16) : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? Color.auroraCyan.opacity(0.5) : Color.auroraStroke2, lineWidth: isSelected ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid

    private func thumbnail(for photo: GalleryPhotoRecord, index: Int) -> some View {
        Button {
            appState.galleryFullscreenPhotos = filteredPhotos
            appState.galleryFullscreenIndex = index
        } label: {
            GalleryThumbnailImage(url: EventGalleryStore.thumbnailURL(for: photo.thumbnailFileName))
                .frame(height: 90)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                        .strokeBorder(Color.auroraStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        // No `.help()` tooltip here on purpose — with up to ~30 thumbnails mounted
        // at once (the grid's row cap), each one's tooltip tracking area was real,
        // continuous AppKit overhead (hit-tested on every mouse move across the
        // whole window), and was the main suspect for the app feeling less smooth
        // whenever the Gallery card was expanded.
        // Filtering changes `filteredPhotos`, which ForEach diffs by `photo.id`
        // (the source path) — pairing that with a transition + the `withAnimation`
        // wrapping each filter toggle makes photos that leave/enter the filtered set
        // animate out/in instead of just popping.
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    /// The collapse flag is injected by `.auroraCollapsibleStaticCard` as an
    /// environment value on its *content* parameter — a sibling view built inline in
    /// `EventGalleryCard.body` can't see it via `@Environment` on `EventGalleryCard`
    /// itself (that reads the environment `EventGalleryCard` was instantiated with,
    /// not the one the modifier attaches afterwards). A small descendant view like
    /// this one, rendered inside that content, reads the injected value correctly.
    private struct GalleryCollapsedGate<Content: View>: View {
        @Environment(\.auroraCardIsCollapsed) private var cardIsCollapsed
        @ViewBuilder let content: () -> Content

        var body: some View {
            if !cardIsCollapsed {
                content()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(photos.isEmpty ? "No JPGs found in this event" : "No JPGs match the active filters")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    /// Shown while the RAW scan is still running and no JPGs have come in yet —
    /// without this, an event mid-initial-scan would show the misleading "No JPGs
    /// found in this event" (from `emptyState`) even though the gallery is actively
    /// being built and just hasn't produced results yet.
    private var buildingState: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Fetching JPG previews…")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Fullscreen viewer

/// Full-size preview of the gallery photo at `index` within `photos`, with
/// previous/next navigation (arrow keys or on-screen chevrons). Tries to load the
/// original file first; if the event folder was moved/archived after finalize and
/// the original is no longer reachable, falls back to the cached thumbnail with a
/// note instead of showing a blank sheet.
///
/// Rendered as an in-window overlay from `ContentView` (see `AppState.galleryFullscreenIndex`)
/// rather than a `.sheet()` — a macOS sheet is a separate modal window that blocks
/// and dims the parent, so "click anywhere outside the photo to close" could only
/// ever work inside the sheet's own small bounds, not the rest of the app. Living
/// in the same window means the whole main content area is fair game to dismiss it.
struct GalleryFullscreenView: View {
    let photos: [GalleryPhotoRecord]
    @Binding var index: Int
    let onDismiss: () -> Void
    @State private var fullImage: NSImage?
    @State private var sourceIsReachable = true
    @FocusState private var isFocused: Bool

    private var photo: GalleryPhotoRecord { photos[index] }
    private var canGoPrevious: Bool { index > 0 }
    private var canGoNext: Bool { index < photos.count - 1 }

    var body: some View {
        ZStack {
            // Plain `.onTapGesture` proved unreliable here on macOS (the nav/close
            // buttons, which are real `Button`s, always worked — the background tap
            // never fired), so background-dismiss and photo-tap-swallow are both
            // implemented as invisible `Button`s instead of gestures.
            Button {
                onDismiss()
            } label: {
                Color.auroraBg.ignoresSafeArea()
            }
            .buttonStyle(.plain)

            VStack(spacing: 10) {
                Group {
                    if let fullImage {
                        // `.aspectRatio(.fit)` letterboxes the image inside this frame,
                        // so a full-frame swallow button would eat clicks in the empty
                        // letterbox bars too — compute the actual rendered photo rect
                        // and only swallow clicks inside that.
                        GeometryReader { proxy in
                            let displaySize = fittedSize(of: fullImage.size, in: proxy.size)
                            Button {
                                // no-op: swallows the click so it doesn't reach the
                                // background dismiss button underneath
                            } label: {
                                Image(nsImage: fullImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            }
                            .buttonStyle(.plain)
                            .frame(width: displaySize.width, height: displaySize.height)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        }
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !sourceIsReachable {
                    Text("Original file not found — showing the cached preview instead.")
                        .font(.manrope(11.5, weight: .medium))
                        .foregroundStyle(Color.auroraFaint)
                }

                Text("\(URL(fileURLWithPath: photo.sourcePath).lastPathComponent) · \(index + 1) of \(photos.count)")
                    .font(.manrope(11.5, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
            }
            .padding(24)

            navButton(direction: .previous)
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            navButton(direction: .next)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

            VStack {
                HStack(spacing: 8) {
                    Spacer()
                    if sourceIsReachable {
                        // Same reveal-in-Finder action as before — the icon just reads as
                        // "download" to the user, since the photo already lives in a folder
                        // rather than needing an actual download.
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: photo.sourcePath)])
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .buttonStyle(AuroraGhostButtonStyle())
                        .help("Reveal in Finder")

                        Button {
                            shareViaAirDrop()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .buttonStyle(AuroraGhostButtonStyle())
                        .help("Share via AirDrop")
                    }
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(AuroraGhostButtonStyle())
                }
                Spacer()
            }
            .padding(16)
        }
        .frame(minWidth: 750, idealWidth: 847, maxWidth: 920, minHeight: 581, idealHeight: 653, maxHeight: 702)
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke2, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            loadImage()
            // Sheets don't auto-focus a plain container — without this, key presses
            // go nowhere and the arrow-key navigation silently does nothing.
            DispatchQueue.main.async { isFocused = true }
        }
        .onChange(of: index) { _, _ in loadImage() }
        .onKeyPress(.leftArrow) { goToPrevious(); return .handled }
        .onKeyPress(.rightArrow) { goToNext(); return .handled }
        .onKeyPress(.escape) { onDismiss(); return .handled }
    }

    private enum NavDirection { case previous, next }

    private func navButton(direction: NavDirection) -> some View {
        let enabled = direction == .previous ? canGoPrevious : canGoNext
        return Button {
            direction == .previous ? goToPrevious() : goToNext()
        } label: {
            Image(systemName: direction == .previous ? "chevron.left" : "chevron.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(enabled ? Color.auroraTxt : Color.auroraFaint.opacity(0.3))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.auroraPanel2.opacity(0.85)))
                .overlay(Circle().strokeBorder(Color.auroraStroke2, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func goToPrevious() {
        guard canGoPrevious else { return }
        index -= 1
    }

    private func goToNext() {
        guard canGoNext else { return }
        index += 1
    }

    private func shareViaAirDrop() {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: [URL(fileURLWithPath: photo.sourcePath)])
    }

    private func fittedSize(of imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return containerSize
        }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        if imageAspect > containerAspect {
            return CGSize(width: containerSize.width, height: containerSize.width / imageAspect)
        } else {
            return CGSize(width: containerSize.height * imageAspect, height: containerSize.height)
        }
    }

    private func loadImage() {
        fullImage = nil
        let sourceURL = URL(fileURLWithPath: photo.sourcePath)
        if FileManager.default.fileExists(atPath: sourceURL.path), let image = NSImage(contentsOf: sourceURL) {
            fullImage = image
            sourceIsReachable = true
            return
        }
        sourceIsReachable = false
        fullImage = NSImage(contentsOf: EventGalleryStore.thumbnailURL(for: photo.thumbnailFileName))
    }
}

// MARK: - Async cached thumbnail

/// Loads a grid thumbnail off the main thread via `ThumbnailCache`, instead of the
/// synchronous `NSImage(contentsOf:)` disk read the grid cell used to run inline —
/// with hundreds of JPGs that re-decoded on every SwiftUI re-render and was the
/// source of the reported scroll/expand lag inside an event.
private struct GalleryThumbnailImage: View {
    let url: URL
    @State private var image: NSImage?

    // The NSCache lookup is a cheap, synchronous in-memory check, so grab it at
    // init time rather than only inside `.task` — during a fast scroll, LazyVGrid
    // recreates this view for every cell that comes back on-screen, and for an
    // already-cached thumbnail (the common case after the first pass through the
    // gallery) that meant an async Task round-trip per cell for no reason other
    // than to immediately return a value we already had synchronously.
    init(url: URL) {
        self.url = url
        _image = State(initialValue: ThumbnailCache.shared.get(for: url))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.auroraPanel2
            }
        }
        .task(id: url) {
            guard image == nil else { return }
            let loaded = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value
            guard !Task.isCancelled, let loaded else { return }
            ThumbnailCache.shared.set(loaded, for: url)
            image = loaded
        }
    }
}
