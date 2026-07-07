import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AuroraSidebarView: View {
    @Binding var selectedItem: NavigationItem
    @Bindable var appState: AppState
    @State private var draggedSidebarItem: EventSidebarItemReference?
    @State private var draggedEventBookmarkIndices = Set<Int>()
    @State private var selectedEventBookmarkIndices = Set<Int>()
    @State private var hoveringCreateFolder = false
    @State private var hoveringFolderDrop = false
    @State private var editingTagsBookmarkIndex: Int?

    #if canImport(Sparkle)
    @EnvironmentObject private var updater: SparkleUpdater
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 18)
                .padding(.top, 34)
                .padding(.bottom, 18)

            sectionLabel("Main Menu")
                .padding(.horizontal, 18)
                .padding(.bottom, 6)

            VStack(spacing: 2) {
                navRow(.dashboard)
                navRow(.statistics)
                navRow(.activity)
                navRow(.storage)
                navRow(.settings)
            }
            .padding(.horizontal, 10)

            eventsHeader
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 6)

            eventsList
                .frame(maxHeight: .infinity)
                .layoutPriority(0)
                .padding(.bottom, 10)
                .contentShape(Rectangle())
                .onDrop(of: [.fileURL], isTargeted: $hoveringFolderDrop) { providers in
                    addDroppedFolders(from: providers)
                }
                .overlay {
                    if hoveringFolderDrop {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.auroraCyan.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.auroraCyan.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                            )
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                            .allowsHitTesting(false)
                    }
                }

            Divider()
                .background(Color.auroraStroke)
                .padding(.horizontal, 10)

            HStack(spacing: 0) {
                navRow(.logs)
                Spacer()
                Button {
                    let subject = "[BUG] Aurora — \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")"
                    let encoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "mailto:hello@getaurora.pro?subject=\(encoded)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "ladybug")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.auroraFaint)
                }
                .buttonStyle(.plain)
                .auroraTooltip("Report a bug")
                .padding(.trailing, 10)
                #if canImport(Sparkle)
                if updater.updateAvailable {
                    Button {
                        selectedItem = .settings
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.auroraTxt)
                            Circle()
                                .fill(Color.auroraLive)
                                .frame(width: 7, height: 7)
                                .offset(x: 2, y: -2)
                        }
                    }
                    .buttonStyle(.plain)
                    .auroraTooltip("New update available — go to Settings")
                    .padding(.trailing, 14)
                }
                #endif
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .frame(width: AuroraSpacing.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            Color.auroraBg2
                .overlay(
                    Color.white.opacity(0.02) // soft glass
                )
        )
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(Color.auroraStroke),
            alignment: .trailing
        )
    }

    // MARK: - Brand

    private var brand: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text("Aurora")
                    .font(.auroraBrand)
                    .foregroundStyle(Color.auroraTxt)
                Text("RAW speed. Smart stats.")
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
            }
        }
    }

    // MARK: - Section label

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.auroraSectionLabel)
            .tracking(1.7)
            .foregroundStyle(Color.auroraFaint)
    }

    private var eventsHeader: some View {
        HStack(spacing: 8) {
            sectionLabel("Events & Folders")
            Spacer()
            Menu {
                Button("Sort Root by Name") {
                    appState.sortRootEventSidebarByName()
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.auroraFaint.opacity(0.72))
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            Button(action: createRootFolder) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.auroraCyan.opacity(hoveringCreateFolder ? 1 : 0.42))
                    .shadow(color: Color.auroraCyan.opacity(hoveringCreateFolder ? 0.75 : 0), radius: 8, x: 0, y: 0)
                    .scaleEffect(hoveringCreateFolder ? 1.08 : 1)
            }
            .buttonStyle(.plain)
            .auroraTooltip("Create folder")
            .onHover { hoveringCreateFolder = $0 }
            .animation(.easeOut(duration: 0.15), value: hoveringCreateFolder)
        }
    }

    // MARK: - Nav row (main menu / logs)

    private func navRow(_ item: NavigationItem) -> some View {
        AuroraNavRow(
            label: item.label,
            systemIcon: item.icon,
            isActive: selectedItem == item
        ) {
            selectedEventBookmarkIndices.removeAll()
            selectedItem = item
        }
    }

    // MARK: - Events list

    @ViewBuilder
    private var eventsList: some View {
        if appState.eventSidebarNodes.isEmpty {
            VStack {
                Spacer().frame(height: 60)
                Text("No events or folders yet")
                    .font(.manrope(12.5, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
                    .italic()
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(appState.eventSidebarNodes) { node in
                        sidebarNodeRow(node, depth: 0)
                    }
                    rootDropArea
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var rootDropArea: some View {
        Color.clear
            .frame(height: 26)
            .contentShape(Rectangle())
            .onDrop(of: [.plainText], isTargeted: nil) { _ in
                guard let draggedSidebarItem else { return false }
                let selectedBookmarkIndex = currentSelectedBookmarkIndex()
                moveDraggedSelection(draggedSidebarItem, intoFolder: nil)
                self.draggedSidebarItem = nil
                draggedEventBookmarkIndices.removeAll()
                restoreSelection(bookmarkIndex: selectedBookmarkIndex)
                return true
            }
    }

    private func sidebarNodeRow(_ node: EventSidebarNode, depth: Int) -> AnyView {
        switch node.kind {
        case .folder:
            return AnyView(VStack(spacing: 2) {
                folderRow(node, depth: depth)
                if node.isExpanded {
                    ForEach(node.children) { child in
                        sidebarNodeRow(child, depth: depth + 1)
                    }
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                        )
                    )
                }
            })
        case .event:
            if let bookmarkIndex = node.eventIndex,
               let event = eventDetails(bookmarkIndex: bookmarkIndex) {
                return AnyView(eventRow(bookmarkIndex: bookmarkIndex, event: event, depth: depth))
            }
            return AnyView(EmptyView())
        }
    }

    private func folderRow(_ node: EventSidebarNode, depth: Int) -> some View {
        Button {
            selectedEventBookmarkIndices.removeAll()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                appState.toggleEventSidebarFolder(id: node.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 10)
                    .foregroundStyle(Color.auroraFaint)
                    .rotationEffect(.degrees(node.isExpanded ? 90 : 0))
                Image(systemName: node.isExpanded ? "folder.fill" : "folder")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
                    .foregroundStyle(Color.auroraViolet)
                Text(node.name)
                    .font(.auroraNavItem)
                    .lineLimit(1)
                    .foregroundStyle(Color.auroraMuted)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * 12)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.badge, style: .continuous)
                    .fill(Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: node.isExpanded)
        .contextMenu {
            Button("Create Folder Inside…") { createFolder(inside: node.id) }
            Button("Rename Folder…") { renameFolder(id: node.id, currentName: node.name) }
            Button("Sort Contents by Name") { appState.sortEventSidebarFolderByName(id: node.id) }
            Divider()
            Button("Remove Folder…", role: .destructive) { confirmRemoveFolder(id: node.id, name: node.name) }
        }
        .opacity(draggedSidebarItem == .folder(node.id) ? 0.45 : 1)
        .onDrag {
            draggedSidebarItem = .folder(node.id)
            return NSItemProvider(object: "folder:\(node.id.uuidString)" as NSString)
        }
        .onDrop(of: [.plainText], isTargeted: nil) { _ in
            guard let draggedSidebarItem else { return false }
            let selectedBookmarkIndex = currentSelectedBookmarkIndex()
            moveDraggedSelection(draggedSidebarItem, intoFolder: node.id)
            self.draggedSidebarItem = nil
            draggedEventBookmarkIndices.removeAll()
            restoreSelection(bookmarkIndex: selectedBookmarkIndex)
            return true
        }
    }

    @ViewBuilder
    private func eventRow(bookmarkIndex: Int, event: (path: String, name: String, bookmarkIndex: Int), depth: Int) -> some View {
        let isFinalized = appState.finalizedEvent(forBookmarkIndex: event.bookmarkIndex) != nil
        let isLibrary = appState.isLibraryFolder(at: event.bookmarkIndex)
        let isLibraryScanning = appState.currentlyScanningIndex == event.bookmarkIndex
        let isQueued = appState.scanQueue.contains(event.bookmarkIndex)
        let isManualScanning = appState.backgroundScanningBookmarkIndices.contains(event.bookmarkIndex)
        let isScanning = isLibraryScanning || isManualScanning
        let isMultiSelected = selectedEventBookmarkIndices.contains(bookmarkIndex)

        let icon: String = {
            if isLibrary {
                return isScanning ? "arrow.triangle.2.circlepath" : "folder.fill"
            }
            return isFinalized ? "lock" : "folder"
        }()

        VStack(spacing: 0) {
            AuroraNavRow(
                label: event.name,
                systemIcon: icon,
                isActive: selectedItem == .event(bookmarkIndex: bookmarkIndex) || isMultiSelected,
                compact: true,
                tooltip: event.name,
                showEditHint: true
            ) {
                handleEventSelection(bookmarkIndex: bookmarkIndex)
            }
            .padding(.leading, CGFloat(depth) * 12)

            if isScanning || isQueued {
                HStack(spacing: 5) {
                    if isScanning {
                        ProgressView()
                            .scaleEffect(0.45)
                            .frame(width: 12, height: 12)
                        Text("Scanning…")
                    } else {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text("Queued")
                    }
                }
                .font(.manrope(10, weight: .medium))
                .foregroundStyle(Color.auroraMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, CGFloat(depth) * 12 + 36)
                .padding(.bottom, 2)
            }
        }
        .contextMenu {
            let bulkSelection = bulkSelectionIncluding(bookmarkIndex)

            if bulkSelection.count > 1 {
                Button("Remove \(bulkSelection.count) Events from Aurora…", role: .destructive) {
                    confirmRemoveSelected(bookmarkIndices: bulkSelection)
                }
                Divider()
            } else {
                Button("Relink Folder…") {
                    relinkEvent(bookmarkIndex: event.bookmarkIndex, name: event.name)
                }

                Button("Edit Tags…") {
                    editingTagsBookmarkIndex = event.bookmarkIndex
                }

                if !isLibrary {
                    if isFinalized {
                        Button("Reopen Event…") {
                            confirmReopen(bookmarkIndex: event.bookmarkIndex, name: event.name)
                        }
                    } else {
                        Button("Finalize Event…") {
                            confirmFinalize(bookmarkIndex: event.bookmarkIndex, name: event.name)
                        }
                    }
                }

                Divider()

                Button(isLibrary ? "Remove Folder from Aurora…" : "Remove Event from Aurora…", role: .destructive) {
                    confirmRemove(bookmarkIndex: event.bookmarkIndex, name: event.name)
                }
            }
        }
        .popover(isPresented: Binding(
            get: { editingTagsBookmarkIndex == bookmarkIndex },
            set: { isPresented in if !isPresented { editingTagsBookmarkIndex = nil } }
        ), arrowEdge: .trailing) {
            EventTagPickerView(selectedTags: Binding(
                get: { appState.tags(at: bookmarkIndex) },
                set: { appState.setTags($0, at: bookmarkIndex) }
            ))
        }
        .opacity(draggedEventBookmarkIndices.contains(bookmarkIndex) ? 0.45 : 1)
        .onDrag {
            let dragSelection = dragSelectionIncluding(bookmarkIndex)
            draggedEventBookmarkIndices = Set(dragSelection)
            draggedSidebarItem = .event(bookmarkIndex)
            return NSItemProvider(object: "event:\(bookmarkIndex)" as NSString)
        }
        .onDrop(of: [.plainText], isTargeted: nil) { _ in
            guard let draggedSidebarItem else { return false }
            let selectedBookmarkIndex = currentSelectedBookmarkIndex()
            moveDraggedSelection(draggedSidebarItem, before: .event(bookmarkIndex))
            self.draggedSidebarItem = nil
            draggedEventBookmarkIndices.removeAll()
            restoreSelection(bookmarkIndex: selectedBookmarkIndex)
            return true
        }
    }

    private func handleEventSelection(bookmarkIndex: Int) {
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) {
            if selectedEventBookmarkIndices.isEmpty, case .event(let currentIndex) = selectedItem {
                selectedEventBookmarkIndices.insert(currentIndex)
            }
            if selectedEventBookmarkIndices.contains(bookmarkIndex) {
                selectedEventBookmarkIndices.remove(bookmarkIndex)
            } else {
                selectedEventBookmarkIndices.insert(bookmarkIndex)
            }
            if selectedEventBookmarkIndices.isEmpty {
                selectedItem = .event(bookmarkIndex: bookmarkIndex)
            } else if !selectedEventBookmarkIndices.contains(bookmarkIndex), let first = selectedEventBookmarkIndices.sorted().first {
                selectedItem = .event(bookmarkIndex: first)
            } else {
                selectedItem = .event(bookmarkIndex: bookmarkIndex)
            }
        } else {
            selectedEventBookmarkIndices.removeAll()
            selectedItem = .event(bookmarkIndex: bookmarkIndex)
        }
    }

    private func bulkSelectionIncluding(_ bookmarkIndex: Int) -> [Int] {
        if selectedEventBookmarkIndices.contains(bookmarkIndex), selectedEventBookmarkIndices.count > 1 {
            return selectedEventBookmarkIndices.sorted()
        }
        return [bookmarkIndex]
    }

    private func dragSelectionIncluding(_ bookmarkIndex: Int) -> [Int] {
        if selectedEventBookmarkIndices.contains(bookmarkIndex), selectedEventBookmarkIndices.count > 1 {
            return selectedEventBookmarkIndices.sorted()
        }
        return [bookmarkIndex]
    }

    private func moveDraggedSelection(_ item: EventSidebarItemReference, intoFolder targetFolderID: UUID?) {
        let events = draggedEventBookmarkIndices.sorted()
        if !events.isEmpty {
            for bookmarkIndex in events {
                appState.moveEventSidebarItem(.event(bookmarkIndex), intoFolder: targetFolderID)
            }
        } else {
            appState.moveEventSidebarItem(item, intoFolder: targetFolderID)
        }
    }

    private func moveDraggedSelection(_ item: EventSidebarItemReference, before target: EventSidebarItemReference) {
        let events = draggedEventBookmarkIndices.sorted()
        if !events.isEmpty {
            for bookmarkIndex in events where .event(bookmarkIndex) != target {
                appState.moveEventSidebarItem(.event(bookmarkIndex), before: target)
            }
        } else {
            appState.moveEventSidebarItem(item, before: target)
        }
    }

    private func relinkEvent(bookmarkIndex: Int, name: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the new location for \(name)"
        panel.prompt = "Relink Folder"

        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = BookmarkManager.saveBookmark(for: url) else { return }

        if !appState.relinkEventFolder(at: bookmarkIndex, to: url, bookmark: bookmark) {
            let warn = NSAlert()
            warn.messageText = "Could not relink event"
            warn.informativeText = "The selected event is no longer available. Try adding it again."
            warn.addButton(withTitle: "OK")
            warn.runModal()
        }
    }

    private func confirmFinalize(bookmarkIndex: Int, name: String) {
        let alert = NSAlert()
        alert.messageText = "Finalize \(name)?"
        alert.informativeText = "Current totals will be saved permanently. New imports won't update them. You can reopen later."
        alert.addButton(withTitle: "Finalize")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if appState.finalizeEvent(at: bookmarkIndex) == nil {
            let warn = NSAlert()
            warn.messageText = "No fresh data for this folder"
            warn.informativeText = "Run a scan from the event detail view before finalizing."
            warn.addButton(withTitle: "OK")
            warn.runModal()
        }
    }

    private func confirmReopen(bookmarkIndex: Int, name: String) {
        let alert = NSAlert()
        alert.messageText = "Reopen \(name)?"
        alert.informativeText = "The snapshot will be deleted and the event will return to live counts. New imports will start counting again."
        alert.addButton(withTitle: "Reopen")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        appState.reopenEvent(at: bookmarkIndex)
    }

    private func confirmRemove(bookmarkIndex: Int, name: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove \(name) from Aurora?"
        alert.informativeText = "This removes the event, its cached stats, and its import history from Aurora. Files on disk will not be deleted."
        alert.addButton(withTitle: "Remove from Aurora")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if appState.removeEventFolderAndStats(at: bookmarkIndex) {
            selectedItem = .dashboard
        } else {
            let warn = NSAlert()
            warn.messageText = "Could not remove event"
            warn.informativeText = "The selected event is no longer available."
            warn.addButton(withTitle: "OK")
            warn.runModal()
        }
    }

    private func confirmRemoveSelected(bookmarkIndices: [Int]) {
        let validIndices = bookmarkIndices
            .filter { $0 >= 0 && $0 < appState.eventFolderBookmarks.count }
            .sorted()
        guard !validIndices.isEmpty else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove \(validIndices.count) events from Aurora?"
        alert.informativeText = "This removes the selected events, their cached stats, and their import history from Aurora. Files on disk will not be deleted."
        alert.addButton(withTitle: "Remove from Aurora")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var failed = 0
        for index in validIndices.sorted(by: >) {
            if !appState.removeEventFolderAndStats(at: index) {
                failed += 1
            }
        }

        selectedEventBookmarkIndices.removeAll()
        selectedItem = .dashboard

        if failed > 0 {
            let warn = NSAlert()
            warn.messageText = "Could not remove all events"
            warn.informativeText = "\(failed) selected event\(failed == 1 ? "" : "s") could not be removed."
            warn.addButton(withTitle: "OK")
            warn.runModal()
        }
    }

    private func createRootFolder() {
        createFolder(inside: nil)
    }

    private func createFolder(inside parentID: UUID?) {
        guard let name = promptForFolderName(title: "Create Folder", message: "Name this sidebar folder.", defaultValue: "") else { return }
        appState.createEventSidebarFolder(named: name, inside: parentID)
    }

    private func renameFolder(id: UUID, currentName: String) {
        guard let name = promptForFolderName(title: "Rename Folder", message: "Choose a new folder name.", defaultValue: currentName) else { return }
        appState.renameEventSidebarFolder(id: id, name: name)
    }

    private func confirmRemoveFolder(id: UUID, name: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove \(name)?"
        alert.informativeText = "This removes only the sidebar folder. Events and subfolders inside it move up one level. Files on disk are not touched."
        alert.addButton(withTitle: "Remove Folder")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        appState.removeEventSidebarFolder(id: id)
    }

    private func promptForFolderName(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultValue
        field.placeholderString = "Folder name"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func eventDetails(bookmarkIndex: Int) -> (path: String, name: String, bookmarkIndex: Int)? {
        appState.uniqueImportDestinations.first { $0.bookmarkIndex == bookmarkIndex }
    }

    private func currentSelectedBookmarkIndex() -> Int? {
        guard case .event(let bookmarkIndex) = selectedItem else { return nil }
        return bookmarkIndex
    }

    private func restoreSelection(bookmarkIndex: Int?) {
        guard let bookmarkIndex else { return }
        selectedItem = .event(bookmarkIndex: bookmarkIndex)
    }

    private func addDroppedFolders(from providers: [NSItemProvider]) -> Bool {
        let fileURLProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileURLProviders.isEmpty else { return false }
        guard appState.canUseTrialAction() else {
            appState.requestActivationForTrialLimit()
            return true
        }

        for provider in fileURLProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = droppedURL(from: item), isDirectory(url) else { return }
                DispatchQueue.main.async {
                    appState.addLibraryFolder(url: url)
                }
            }
        }
        return true
    }

    private func droppedURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let string = item as? String {
            return URL(string: string) ?? URL(fileURLWithPath: string)
        }
        return nil
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }


    // MARK: - Storage widget

    private var storageWidget: some View {
        let stats = computeStorage(appState: appState)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("STORAGE")
                    .font(.manrope(9.5, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.auroraFaint)
                Spacer()
                Text("\(Int((stats.fraction * 100).rounded()))%")
                    .font(.manrope(10.5, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(stats.usedValue)
                    .font(.sora(22, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Text(stats.usedUnit)
                    .font(.sora(13, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
            }

            StorageBar(fraction: stats.fraction)

            Text(stats.subtitle)
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
    }

    private struct StorageSummary {
        let fraction: Double
        let usedValue: String
        let usedUnit: String
        let subtitle: String
    }

    private func computeStorage(appState: AppState) -> StorageSummary {
        let used = appState.totalStatsReport?.totalBytes ?? 0
        let usedParts = AuroraFormat.bytesParts(used)
        var totalBytes: Int64 = 0
        if let dest = appState.destinationURL,
           let values = try? dest.resourceValues(forKeys: [.volumeTotalCapacityKey]),
           let capacity = values.volumeTotalCapacity {
            totalBytes = Int64(capacity)
        }
        let fraction: Double = totalBytes > 0 ? Double(used) / Double(totalBytes) : 0
        let totalParts = totalBytes > 0
            ? AuroraFormat.bytesParts(totalBytes)
            : (value: "—", unit: "")
        let subtitle: String
        if totalBytes > 0 {
            subtitle = "of \(totalParts.value) \(totalParts.unit) used"
        } else if used > 0 {
            subtitle = "destination not set"
        } else {
            subtitle = "No imports yet"
        }
        return StorageSummary(
            fraction: fraction,
            usedValue: usedParts.value,
            usedUnit: usedParts.unit,
            subtitle: subtitle
        )
    }
}

private struct EventSidebarDropDelegate: DropDelegate {
    let targetBookmarkIndex: Int
    @Binding var draggedBookmarkIndex: Int?
    @Binding var dropTargetBookmarkIndex: Int?
    @Binding var selectedItem: NavigationItem
    let appState: AppState

    func validateDrop(info: DropInfo) -> Bool {
        draggedBookmarkIndex != nil
    }

    func dropEntered(info: DropInfo) {
        guard let draggedBookmarkIndex,
              draggedBookmarkIndex != targetBookmarkIndex else { return }

        let selectedBookmarkIndex = currentSelectedBookmarkIndex()
        dropTargetBookmarkIndex = targetBookmarkIndex

        withAnimation(.easeInOut(duration: 0.16)) {
            appState.moveEventFolder(bookmarkIndex: draggedBookmarkIndex, before: targetBookmarkIndex)
            restoreSelection(bookmarkIndex: selectedBookmarkIndex)
        }
    }

    func dropExited(info: DropInfo) {
        if dropTargetBookmarkIndex == targetBookmarkIndex {
            dropTargetBookmarkIndex = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dropTargetBookmarkIndex = nil
        draggedBookmarkIndex = nil
        return true
    }

    private func currentSelectedBookmarkIndex() -> Int? {
        guard case .event(let bookmarkIndex) = selectedItem else { return nil }
        return bookmarkIndex
    }

    private func restoreSelection(bookmarkIndex: Int?) {
        guard let bookmarkIndex else { return }
        selectedItem = .event(bookmarkIndex: bookmarkIndex)
    }
}

// MARK: - Nav row component

struct AuroraNavRow: View {
    let label: String
    let systemIcon: String
    let isActive: Bool
    var compact: Bool = false
    var tooltip: String? = nil
    var showEditHint: Bool = false
    let action: () -> Void

    @State private var hovering = false
    @State private var rowWidth: CGFloat = 0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemIcon)
                    .font(.system(size: compact ? 12 : 13.5, weight: .semibold))
                    .frame(width: 16)
                Text(label)
                    .font(.auroraNavItem)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, compact ? 7 : 9)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.badge, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.badge, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: isActive ? Color.auroraAccent.opacity(0.8) : .clear, radius: 12, x: 0, y: 6)
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { rowWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in rowWidth = width }
            }
        )
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .auroraTooltip(visibleTooltip, edge: .trailing)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.2), value: isActive)
    }

    private var visibleTooltip: String {
        guard let tooltip, !tooltip.isEmpty, rowWidth > 0 else { return "" }
        let availableTextWidth = rowWidth - 24 - 16 - 11 - 4
        return textWidth(label) > availableTextWidth ? tooltip : ""
    }

    private func textWidth(_ text: String) -> CGFloat {
        let font = NSFont(name: AuroraFontFamily.manrope, size: 13.5) ?? NSFont.systemFont(ofSize: 13.5, weight: .semibold)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    private var textColor: Color {
        if isActive { return .white }
        if hovering { return .auroraTxt }
        return .auroraMuted
    }

    private var background: AnyShapeStyle {
        if isActive { return AnyShapeStyle(LinearGradient.auroraGradMuted) }
        if hovering { return AnyShapeStyle(Color.auroraPanel) }
        return AnyShapeStyle(Color.clear)
    }

    private var borderColor: Color {
        if isActive { return Color.auroraAccent.opacity(0.35) }
        return Color.auroraAccent.opacity(0)
    }
}
