import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AuroraSidebarView: View {
    @Binding var selectedItem: NavigationItem
    @Bindable var appState: AppState
    @State private var draggedSidebarItem: EventSidebarItemReference?
    @State private var hoveringCreateFolder = false

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

            Divider()
                .background(Color.auroraStroke)
                .padding(.horizontal, 10)

            HStack(spacing: 0) {
                navRow(.logs)
                Spacer()
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
            sectionLabel("Events")
            Spacer()
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
            selectedItem = item
        }
    }

    // MARK: - Events list

    @ViewBuilder
    private var eventsList: some View {
        if appState.eventSidebarNodes.isEmpty {
            VStack {
                Spacer().frame(height: 60)
                Text("No events yet")
                    .font(.manrope(12.5, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
                    .italic()
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
        } else {
            ScrollView {
                VStack(spacing: 2) {
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
                appState.moveEventSidebarItem(draggedSidebarItem, intoFolder: nil)
                self.draggedSidebarItem = nil
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
                return AnyView(eventRow(bookmarkIndex: bookmarkIndex, event: event, depth: depth)
                    .opacity(draggedSidebarItem == .event(bookmarkIndex) ? 0.45 : 1)
                    .onDrag {
                        draggedSidebarItem = .event(bookmarkIndex)
                        return NSItemProvider(object: "event:\(bookmarkIndex)" as NSString)
                    }
                    .onDrop(of: [.plainText], isTargeted: nil) { _ in
                        guard let draggedSidebarItem else { return false }
                        let selectedBookmarkIndex = currentSelectedBookmarkIndex()
                        appState.moveEventSidebarItem(draggedSidebarItem, before: .event(bookmarkIndex))
                        self.draggedSidebarItem = nil
                        restoreSelection(bookmarkIndex: selectedBookmarkIndex)
                        return true
                    })
            }
            return AnyView(EmptyView())
        }
    }

    private func folderRow(_ node: EventSidebarNode, depth: Int) -> some View {
        Button {
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
        .auroraTooltip(node.name, edge: .trailing)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: node.isExpanded)
        .contextMenu {
            Button("Create Folder Inside…") { createFolder(inside: node.id) }
            Button("Rename Folder…") { renameFolder(id: node.id, currentName: node.name) }
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
            appState.moveEventSidebarItem(draggedSidebarItem, intoFolder: node.id)
            self.draggedSidebarItem = nil
            restoreSelection(bookmarkIndex: selectedBookmarkIndex)
            return true
        }
    }

    @ViewBuilder
    private func eventRow(bookmarkIndex: Int, event: (path: String, name: String, bookmarkIndex: Int), depth: Int) -> some View {
        let isFinalized = appState.finalizedEvent(forBookmarkIndex: event.bookmarkIndex) != nil
        let isLibrary = appState.isLibraryFolder(at: event.bookmarkIndex)
        let isScanning = appState.currentlyScanningIndex == event.bookmarkIndex
        let isQueued = appState.scanQueue.contains(event.bookmarkIndex)

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
                isActive: selectedItem == .event(bookmarkIndex: bookmarkIndex),
                compact: true,
                tooltip: event.name
            ) {
                selectedItem = .event(bookmarkIndex: bookmarkIndex)
            }
            .padding(.leading, CGFloat(depth) * 12)

            if isLibrary && (isScanning || isQueued) {
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
            Button("Relink Folder…") {
                relinkEvent(bookmarkIndex: event.bookmarkIndex, name: event.name)
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
    let action: () -> Void

    @State private var hovering = false

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
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .auroraTooltip(tooltip ?? "", edge: .trailing)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.2), value: isActive)
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
