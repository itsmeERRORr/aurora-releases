# Finalized Events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Finalize Event" action that snapshots all per-event statistics into a self-contained, persistent record, decoupled from the live folder — so totals survive file deletion, folder moves, and offline volumes.

**Architecture:** A new first-class `FinalizedEvent` model with stable UUID identity, persisted in a single JSON via `FinalizedEventsStore`. `AppState` keeps a parallel array `eventFolderFinalizedEventID: [UUID?]` linking each sidebar bookmark to its snapshot. Read paths (sidebar event row, Top Events, Hero Card) prefer the snapshot when the bookmark is linked, else fall back to current live logic. Imports targeting a finalized event's folder are blocked with a Reopen prompt.

**Tech Stack:** Swift 5.9+, SwiftUI, Foundation. macOS app target only (no test target — verification via `xcodebuild` clean build + manual checklist per task).

**Spec:** [docs/superpowers/specs/2026-05-29-finalized-events-design.md](../specs/2026-05-29-finalized-events-design.md)

---

## File Structure

**New files:**
- `commanderonev2/Models/FinalizedEvent.swift` — the model + Codable.
- `commanderonev2/Services/FinalizedEventsStore.swift` — JSON-backed store + CRUD API.

**Modified files:**
- `commanderonev2/Models/AppState.swift` — load store; add `finalizedEvents`, `eventFolderFinalizedEventID`; sync helper; `finalize(at:)` / `reopen(at:)` / `bookmarkIndex(forFinalizedID:)` / `finalizedEvent(forPath:)`; extend `uniqueImportDestinations` to include bookmark index.
- `commanderonev2/Views/Statistics/TopEventsPanel.swift` — extend `EventAggregator.build()` to read from `finalizedEvents`.
- `commanderonev2/Views/Statistics/HeroEventCard.swift` — show "Finalizado" chip when latest event is finalized.
- `commanderonev2/Views/Shell/AuroraSidebarView.swift` — context menu (Finalize/Reopen) on event rows + chip.
- `commanderonev2/ContentView.swift` — block import when destination matches a finalized event; prompt to reopen.

---

## Conventions

**Build command (used everywhere):**
```bash
cd /Users/itsmeerror/Desktop/commanderv2/commanderonev2 && xcodebuild -project commanderonev2.xcodeproj -scheme commanderonev2 -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20
```

**Expected on success:** final lines include `** BUILD SUCCEEDED **`.

**Commit style:** matches existing log — short imperative title, no body needed for small commits, optional body for context. No `Co-Authored-By` trailer in these commits (project commits don't use them).

---

## Task 1: Add `FinalizedEvent` model

**Files:**
- Create: `commanderonev2/Models/FinalizedEvent.swift`

- [ ] **Step 1: Create the model file**

Write `commanderonev2/Models/FinalizedEvent.swift`:

```swift
import Foundation

/// Frozen snapshot of an event's statistics, persisted independently of the
/// sidebar bookmark so the totals survive file deletion, folder moves, and
/// offline volumes.
struct FinalizedEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var snapshot: StatsReport
    var totalBytes: Int64
    var photoCount: Int
    var firstImportDate: Date?
    var lastImportDate: Date?
    let finalizedAt: Date
    var lastKnownPath: String
    var originalBookmark: Data?

    init(
        id: UUID = UUID(),
        name: String,
        snapshot: StatsReport,
        totalBytes: Int64,
        photoCount: Int,
        firstImportDate: Date? = nil,
        lastImportDate: Date? = nil,
        finalizedAt: Date = Date(),
        lastKnownPath: String,
        originalBookmark: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.snapshot = snapshot
        self.totalBytes = totalBytes
        self.photoCount = photoCount
        self.firstImportDate = firstImportDate
        self.lastImportDate = lastImportDate
        self.finalizedAt = finalizedAt
        self.lastKnownPath = lastKnownPath
        self.originalBookmark = originalBookmark
    }
}
```

- [ ] **Step 2: Add the file to the Xcode target**

Open `commanderonev2.xcodeproj` in Xcode and confirm `FinalizedEvent.swift` appears under the `commanderonev2` group and is a member of the `commanderonev2` target. If running headless, add it to `project.pbxproj` via `xcodeproj` gem or by opening the project in Xcode once.

> If you cannot open Xcode, run the build (Step 3); if it fails with "FinalizedEvent not found" later in Task 2, the file is missing from the target — add it then.

- [ ] **Step 3: Build**

Run the build command (see Conventions). Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add commanderonev2/Models/FinalizedEvent.swift commanderonev2.xcodeproj/project.pbxproj
git commit -m "Add FinalizedEvent model"
```

---

## Task 2: Add `FinalizedEventsStore` service

**Files:**
- Create: `commanderonev2/Services/FinalizedEventsStore.swift`

- [ ] **Step 1: Create the store**

Write `commanderonev2/Services/FinalizedEventsStore.swift`:

```swift
import Foundation

/// JSON-backed store for `FinalizedEvent` snapshots.
/// Persists the entire collection as one file in Application Support.
enum FinalizedEventsStore {

    private static var storageURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("commanderonev2", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("finalized_events.json")
    }

    static func loadAll() -> [FinalizedEvent] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: storageURL)
            return try JSONDecoder().decode([FinalizedEvent].self, from: data)
        } catch {
            print("FinalizedEventsStore.loadAll: failed – \(error)")
            return []
        }
    }

    static func saveAll(_ events: [FinalizedEvent]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(events)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("FinalizedEventsStore.saveAll: failed – \(error)")
        }
    }
}
```

- [ ] **Step 2: Add the file to the Xcode target**

Same as Task 1 Step 2 — confirm membership in the `commanderonev2` target.

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add commanderonev2/Services/FinalizedEventsStore.swift commanderonev2.xcodeproj/project.pbxproj
git commit -m "Add FinalizedEventsStore JSON persistence"
```

---

## Task 3: Wire `finalizedEvents` into `AppState`

**Files:**
- Modify: `commanderonev2/Models/AppState.swift`

- [ ] **Step 1: Add the state properties**

Locate the `// MARK: - Stats` block in `AppState.swift` (around line 77). After the `totalStatsReport` property block (ends ~line 98), add:

```swift
    // MARK: - Finalized Events

    /// Snapshots for events the user has marked as finalized.
    /// Persisted via `FinalizedEventsStore`. Source of truth for finalized events
    /// across the app (Top Events, Hero Card, sidebar row totals).
    var finalizedEvents: [FinalizedEvent] = [] {
        didSet { FinalizedEventsStore.saveAll(finalizedEvents) }
    }

    /// Per-bookmark link to a finalized snapshot. Same count as `eventFolderBookmarks`.
    /// `nil` = active event (live counts), non-nil = finalized (snapshot is source of truth).
    var eventFolderFinalizedEventID: [UUID?] = [] {
        didSet { saveFinalizedEventIDs() }
    }
```

- [ ] **Step 2: Add sync + persistence helpers**

After the existing `private func syncCachedCounts()` (around line 440), add:

```swift
    private func syncFinalizedEventIDs() {
        let n = eventFolderBookmarks.count
        if eventFolderFinalizedEventID.count > n {
            eventFolderFinalizedEventID = Array(eventFolderFinalizedEventID.prefix(n))
        } else if eventFolderFinalizedEventID.count < n {
            eventFolderFinalizedEventID += Array(repeating: nil, count: n - eventFolderFinalizedEventID.count)
        }
    }

    private func saveFinalizedEventIDs() {
        let strings: [String] = eventFolderFinalizedEventID.map { $0?.uuidString ?? "" }
        guard let data = try? PropertyListEncoder().encode(strings) else { return }
        UserDefaults.standard.set(data, forKey: "eventFolderFinalizedEventIDData")
    }
```

- [ ] **Step 3: Invoke `syncFinalizedEventIDs` from the bookmarks `didSet`**

Locate the `eventFolderBookmarks` declaration (around line 331):

```swift
    var eventFolderBookmarks: [Data] = [] {
        didSet { syncDisplayNamesCount(); syncPeakCounts(); syncCachedCounts(); saveEventFolderBookmarks() }
    }
```

Replace with:

```swift
    var eventFolderBookmarks: [Data] = [] {
        didSet { syncDisplayNamesCount(); syncPeakCounts(); syncCachedCounts(); syncFinalizedEventIDs(); saveEventFolderBookmarks() }
    }
```

- [ ] **Step 4: Load state in `init`**

At the end of `init` (just before `syncDisplayNamesCount(); syncPeakCounts(); syncCachedCounts()` around line 417), add:

```swift
        // Load finalized snapshots
        finalizedEvents = FinalizedEventsStore.loadAll()

        // Load per-bookmark finalized IDs
        if let data = UserDefaults.standard.data(forKey: "eventFolderFinalizedEventIDData"),
           let decoded = try? PropertyListDecoder().decode([String].self, from: data) {
            eventFolderFinalizedEventID = decoded.map { $0.isEmpty ? nil : UUID(uuidString: $0) }
        }
```

Then add `syncFinalizedEventIDs()` to the trailing sync calls:

```swift
        syncDisplayNamesCount()
        syncPeakCounts()
        syncCachedCounts()
        syncFinalizedEventIDs()
```

- [ ] **Step 5: Update `removeEventFolder(at:)` to clear the finalized ID slot**

Locate `removeEventFolder(at:)` (around line 527). Just before the line that removes from `eventFolderPeakRawCounts`, add:

```swift
        if index < eventFolderFinalizedEventID.count { eventFolderFinalizedEventID.remove(at: index) }
```

So the block becomes:

```swift
    func removeEventFolder(at index: Int) {
        guard index >= 0, index < eventFolderBookmarks.count else { return }
        if index < eventFolderCachedCounts.count { eventFolderCachedCounts.remove(at: index) }
        if index < eventFolderCachedPaths.count  { eventFolderCachedPaths.remove(at: index)  }
        if index < eventFolderDisplayNames.count { eventFolderDisplayNames.remove(at: index) }
        if index < eventFolderPeakRawCounts.count { eventFolderPeakRawCounts.remove(at: index) }
        if index < eventFolderFinalizedEventID.count { eventFolderFinalizedEventID.remove(at: index) }
        eventFolderScanningIndices.remove(index)
        eventFolderScanningIndices = Set(eventFolderScanningIndices.map { $0 > index ? $0 - 1 : $0 })
        eventFolderBookmarks.remove(at: index)
    }
```

> Note: this clears the link to the snapshot, but the snapshot itself stays in `finalizedEvents`. That matches the spec: removing from sidebar does not delete the historical record.

- [ ] **Step 6: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add commanderonev2/Models/AppState.swift
git commit -m "AppState: load finalized events store and per-bookmark IDs"
```

---

## Task 4: Add `finalize` / `reopen` / lookup methods on `AppState`

**Files:**
- Modify: `commanderonev2/Models/AppState.swift`

- [ ] **Step 1: Add helper to look up a finalized event by bookmark index**

At the end of `AppState` (right before the closing brace of the class, after `setEventFolderDisplayName`), add:

```swift
    // MARK: - Finalize / Reopen

    /// Returns the finalized snapshot for the given bookmark index, if any.
    func finalizedEvent(forBookmarkIndex index: Int) -> FinalizedEvent? {
        guard index >= 0, index < eventFolderFinalizedEventID.count else { return nil }
        guard let id = eventFolderFinalizedEventID[index] else { return nil }
        return finalizedEvents.first { $0.id == id }
    }

    /// Returns the finalized snapshot whose `lastKnownPath` matches (or contains) `path`.
    /// Used to guard imports against finalized event folders.
    func finalizedEvent(matchingPath path: String) -> FinalizedEvent? {
        let norm = path.hasSuffix("/") ? String(path.dropLast()) : path
        return finalizedEvents.first { event in
            let p = event.lastKnownPath.hasSuffix("/")
                ? String(event.lastKnownPath.dropLast())
                : event.lastKnownPath
            guard !p.isEmpty else { return false }
            return norm == p || norm.hasPrefix(p + "/")
        }
    }
```

- [ ] **Step 2: Add `finalizeEvent(at:)`**

Append after the previous block:

```swift
    /// Builds a snapshot for the event at the given bookmark index using:
    /// - the cached `StatsReport` from `EventStatsCache` for the folder path
    /// - `importHistory` entries that match the folder path (for bytes and dates)
    /// - `eventFolderPeakRawCounts` and `eventFolderCachedCounts` for the count floor
    ///
    /// If no `StatsReport` cache is available, returns `nil` (caller should trigger a scan first).
    @discardableResult
    func finalizeEvent(at index: Int) -> FinalizedEvent? {
        guard index >= 0, index < eventFolderBookmarks.count else { return nil }
        // Already finalized? Return existing.
        if let existing = finalizedEvent(forBookmarkIndex: index) { return existing }

        let path = index < eventFolderCachedPaths.count ? eventFolderCachedPaths[index] : ""
        guard !path.isEmpty else { return nil }

        guard let cached = EventStatsCache.load(forPath: path) else { return nil }
        let snapshot = cached.report

        // Derive aggregates
        let importStats = importStats(forEventPath: path)
        let peak = index < eventFolderPeakRawCounts.count ? eventFolderPeakRawCounts[index] : 0
        let cachedCount = index < eventFolderCachedCounts.count ? eventFolderCachedCounts[index] : -1
        let photoCount = max(snapshot.totalFilesAnalyzed, max(peak, max(cachedCount, 0)))

        let customName = index < eventFolderDisplayNames.count ? eventFolderDisplayNames[index] : ""
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        let name = customName.isEmpty ? folderName : customName

        let bookmark = eventFolderBookmarks[index]

        let event = FinalizedEvent(
            name: name,
            snapshot: snapshot,
            totalBytes: importStats?.totalBytes ?? snapshot.totalBytes,
            photoCount: photoCount,
            firstImportDate: importStats?.firstDate ?? snapshot.firstImportDate,
            lastImportDate: importStats?.lastDate,
            lastKnownPath: path,
            originalBookmark: bookmark
        )

        finalizedEvents.append(event)
        eventFolderFinalizedEventID[index] = event.id
        log("Finalized event '\(name)' with \(photoCount) photos")
        return event
    }

    /// Removes the snapshot link for the given bookmark index and deletes the snapshot from the store.
    func reopenEvent(at index: Int) {
        guard index >= 0, index < eventFolderFinalizedEventID.count else { return }
        guard let id = eventFolderFinalizedEventID[index] else { return }
        finalizedEvents.removeAll { $0.id == id }
        eventFolderFinalizedEventID[index] = nil
        log("Reopened event at index \(index)")
    }

    /// Permanently deletes a snapshot from the store (used when a finalized event no longer has a bookmark in the sidebar).
    func deleteFinalizedEvent(id: UUID) {
        finalizedEvents.removeAll { $0.id == id }
    }
```

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add commanderonev2/Models/AppState.swift
git commit -m "AppState: add finalize/reopen/lookup methods"
```

---

## Task 5: Extend `uniqueImportDestinations` to expose the bookmark index

**Files:**
- Modify: `commanderonev2/Models/AppState.swift`
- Modify: `commanderonev2/ContentView.swift`
- Modify: `commanderonev2/Views/Shell/AuroraSidebarView.swift`
- Modify: `commanderonev2/Views/Storage/StorageView.swift`

> Sidebar UI needs to call `finalizeEvent(at: bookmarkIndex)` but currently only has the sorted display index. Easiest fix: add `bookmarkIndex` to the existing tuple. Backward-compatible because all existing callers use `.path` / `.name`.

- [ ] **Step 1: Update the tuple shape in `AppState.swift`**

Replace the existing `uniqueImportDestinations` (around line 107) so the tuple includes `bookmarkIndex`:

```swift
    var uniqueImportDestinations: [(path: String, name: String, bookmarkIndex: Int)] {
        var result: [(path: String, name: String, lastDate: Date, index: Int)] = []

        for index in eventFolderBookmarks.indices {
            let folderPath = index < eventFolderCachedPaths.count ? eventFolderCachedPaths[index] : ""

            let customName = index < eventFolderDisplayNames.count ? eventFolderDisplayNames[index] : ""
            let folderName: String
            if !folderPath.isEmpty {
                folderName = URL(fileURLWithPath: folderPath).lastPathComponent
            } else {
                folderName = customName.isEmpty ? "Event \(index + 1)" : customName
            }
            let name = customName.isEmpty ? folderName : customName

            let lastDate: Date
            if !folderPath.isEmpty {
                let norm = folderPath.hasSuffix("/") ? String(folderPath.dropLast()) : folderPath
                let latest = importHistory
                    .filter { e in
                        let d = e.destinationPath.hasSuffix("/")
                            ? String(e.destinationPath.dropLast())
                            : e.destinationPath
                        return d == norm || d.hasPrefix(norm + "/")
                    }
                    .map(\.date).max()
                lastDate = latest ?? Date.distantPast
            } else {
                lastDate = Date.distantPast
            }

            result.append((path: folderPath, name: name, lastDate: lastDate, index: index))
        }

        return result
            .sorted { lhs, rhs in
                lhs.lastDate != rhs.lastDate ? lhs.lastDate > rhs.lastDate : lhs.index < rhs.index
            }
            .map { (path: $0.path, name: $0.name, bookmarkIndex: $0.index) }
    }
```

- [ ] **Step 2: Build (will pass — existing call sites still work via labelled access)**

Run the build command. Expected: `** BUILD SUCCEEDED **`. Existing callers (`ContentView.swift:91`, `StorageView.swift:142`, `AuroraSidebarView.swift:105`) reference `.path` and `.name` — both still present.

- [ ] **Step 3: Commit**

```bash
git add commanderonev2/Models/AppState.swift
git commit -m "AppState: expose bookmarkIndex on uniqueImportDestinations"
```

---

## Task 6: Read snapshot in `EventAggregator.build()`

**Files:**
- Modify: `commanderonev2/Views/Statistics/TopEventsPanel.swift`

- [ ] **Step 1: Inject finalized snapshots as canonical**

Locate the `EventAggregator.build(appState:)` function (around line 14). Replace the entire function with:

```swift
    static func build(appState: AppState) -> [EventAggregate] {
        var byPath: [String: (name: String, files: Int, bytes: Int64, speedSum: Double, speedCount: Int, last: Date)] = [:]

        // Finalized events first — they are the source of truth for any matching path.
        // We track which paths are already covered so live logic does not overwrite them.
        var finalizedPaths = Set<String>()
        for event in appState.finalizedEvents {
            let root = inferredEventRoot(from: normalize(event.lastKnownPath))
            guard !root.isEmpty, !isInvalidEventName(event.name) else { continue }
            byPath[root] = (
                name: event.name,
                files: event.photoCount,
                bytes: event.totalBytes,
                speedSum: 0,
                speedCount: 0,
                last: event.lastImportDate ?? event.finalizedAt
            )
            finalizedPaths.insert(root)
        }

        // Known event folders are the source of truth for display names/counts (active events only).
        let destinations = appState.eventFolderBookmarks.indices.compactMap { index -> (path: String, name: String, files: Int) in
            let rawPath = index < appState.eventFolderCachedPaths.count ? appState.eventFolderCachedPaths[index] : ""
            let root = inferredEventRoot(from: normalize(rawPath))
            let customName = index < appState.eventFolderDisplayNames.count ? appState.eventFolderDisplayNames[index] : ""
            let count = index < appState.eventFolderCachedCounts.count ? appState.eventFolderCachedCounts[index] : -1
            let peak = index < appState.eventFolderPeakRawCounts.count ? appState.eventFolderPeakRawCounts[index] : 0
            return (path: root, name: displayName(preferred: customName, root: root), files: max(count, peak))
        }
        for destination in destinations where !destination.path.isEmpty && !finalizedPaths.contains(destination.path) {
            byPath[destination.path, default: (destination.name, 0, 0, 0, 0, .distantPast)].name = destination.name
        }

        // Iterate history — skip entries whose root is finalized (snapshot is canonical).
        for entry in appState.importHistory {
            let entryNorm = normalize(entry.destinationPath)
            let entryRoot = inferredEventRoot(from: entryNorm)
            let parentNorm = bestParent(of: entryRoot, in: destinations.map { $0.path }) ?? entryRoot
            if finalizedPaths.contains(parentNorm) { continue }

            let displayName = destinations.first { normalize($0.path) == parentNorm }?.name
                ?? displayName(preferred: nil, root: parentNorm)
            guard !isInvalidEventName(displayName) else { continue }

            var slot = byPath[parentNorm] ?? (displayName, 0, 0, 0, 0, .distantPast)
            slot.name = slot.name.isEmpty ? displayName : slot.name
            slot.files += entry.fileCount
            slot.bytes += entry.totalBytes
            slot.last = max(slot.last, entry.date)
            byPath[parentNorm] = slot
        }

        // Cached counts top-up for active events only.
        for event in destinations where !event.path.isEmpty && event.files > 0 && !isInvalidEventName(event.name) && !finalizedPaths.contains(event.path) {
            var slot = byPath[event.path] ?? (event.name, 0, 0, 0, 0, .distantPast)
            slot.name = event.name
            slot.files = max(slot.files, event.files)
            byPath[event.path] = slot
        }

        let avgSpeed = appState.totalStatsReport?.averageSpeed ?? 0

        return byPath.compactMap { path, info in
            guard info.files > 0 else { return nil }
            guard !isInvalidEventName(info.name) else { return nil }
            return EventAggregate(
                id: path,
                name: info.name,
                totalFiles: info.files,
                totalBytes: info.bytes,
                averageSpeed: avgSpeed,
                lastDate: info.last
            )
        }
    }
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual check**

Launch the app. Top Events should look unchanged (no finalized events exist yet). Confirm no crash, list renders.

- [ ] **Step 4: Commit**

```bash
git add commanderonev2/Views/Statistics/TopEventsPanel.swift
git commit -m "EventAggregator: read from finalizedEvents as canonical"
```

---

## Task 7: Add "Finalize Event" / "Reopen Event" menu + chip in the sidebar

**Files:**
- Modify: `commanderonev2/Views/Shell/AuroraSidebarView.swift`

- [ ] **Step 1: Replace the `eventsList` body with a context-menu-enabled row**

In `AuroraSidebarView.swift`, replace the `eventsList` computed property (around line 103-131) with:

```swift
    @ViewBuilder
    private var eventsList: some View {
        let events = appState.uniqueImportDestinations
        if events.isEmpty {
            Text("No events yet")
                .font(.manrope(12.5, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
                .italic()
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(events.enumerated()), id: \.offset) { idx, event in
                        eventRow(idx: idx, event: event)
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func eventRow(idx: Int, event: (path: String, name: String, bookmarkIndex: Int)) -> some View {
        let isFinalized = appState.finalizedEvent(forBookmarkIndex: event.bookmarkIndex) != nil

        HStack(spacing: 6) {
            AuroraNavRow(
                label: event.name,
                systemIcon: isFinalized ? "lock" : "folder",
                isActive: selectedItem == .event(index: idx),
                compact: true
            ) {
                selectedItem = .event(index: idx)
            }

            if isFinalized {
                Text("Finalizado")
                    .font(.manrope(8.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.auroraFaint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.auroraPanel2)
                    )
                    .padding(.trailing, 4)
            }
        }
        .contextMenu {
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
```

> The chip is intentionally inline next to the nav row (not inside it) so we don't touch `AuroraNavRow`. The lock icon replaces `folder` when finalized.

- [ ] **Step 2: Add the `AppKit` import**

At the top of the file, ensure `import AppKit` exists alongside `import SwiftUI`. If not, add it.

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual check**

Launch the app. Right-click an event in the sidebar — "Finalize Event…" should appear. (Don't finalize yet unless you have a scanned event; will be tested end-to-end after Task 9.)

- [ ] **Step 5: Commit**

```bash
git add commanderonev2/Views/Shell/AuroraSidebarView.swift
git commit -m "Sidebar: add Finalize/Reopen menu and Finalizado chip"
```

---

## Task 8: Show "Finalizado" chip in `HeroEventCard`

**Files:**
- Modify: `commanderonev2/Views/Statistics/HeroEventCard.swift`

- [ ] **Step 1: Find where the event name is rendered**

Open `HeroEventCard.swift`. In `leftPanel(info:)` (around line 35), the event name is rendered as:

```swift
            Text(info.name)
                .font(.sora(18, weight: .heavy))
                .tracking(-0.8)
                .foregroundStyle(Color.auroraTxt)
                .lineLimit(1)
```

- [ ] **Step 2: Add the chip**

Replace that block with:

```swift
            HStack(spacing: 8) {
                Text(info.name)
                    .font(.sora(18, weight: .heavy))
                    .tracking(-0.8)
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)

                if info.isFinalized {
                    Text("Finalizado")
                        .font(.manrope(8.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.auroraFaint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.auroraPanel2))
                }
            }
```

- [ ] **Step 3: Add `isFinalized` to `LatestEventInfo`**

Find the `LatestEventInfo` struct definition and the `resolveLatestEvent()` function in the same file. Search for `struct LatestEventInfo` and `func resolveLatestEvent`.

Add `var isFinalized: Bool` to the struct, defaulting to `false`. In `resolveLatestEvent()`, after the latest event's path is determined, set `info.isFinalized = appState.finalizedEvent(matchingPath: path) != nil` (use `appState` reference already available).

> If you cannot locate the struct or function via the partial Read, do `grep -n "LatestEventInfo\|resolveLatestEvent" HeroEventCard.swift` first to find the exact lines, then edit. The change is one new boolean field and one assignment.

- [ ] **Step 4: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add commanderonev2/Views/Statistics/HeroEventCard.swift
git commit -m "HeroEventCard: show Finalizado chip when event is finalized"
```

---

## Task 9: Block imports into a finalized event's folder

**Files:**
- Modify: `commanderonev2/ContentView.swift`

- [ ] **Step 1: Add a guard at the top of `startImport()`**

Open `commanderonev2/ContentView.swift`. Locate `startImport()` (around line 185). Right after the `guard let dest = appState.destinationURL else { ... }` block, add:

```swift
        if let finalized = appState.finalizedEvent(matchingPath: dest.path) {
            let alert = NSAlert()
            alert.messageText = "\"\(finalized.name)\" is finalized"
            alert.informativeText = "Reopen the event to continue importing into this folder."
            alert.addButton(withTitle: "Reopen and Import")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else {
                appState.log("Import cancelled: destination belongs to finalized event \(finalized.name)", level: .warning)
                return
            }
            // Reopen via bookmark index lookup
            if let idx = appState.eventFolderFinalizedEventID.firstIndex(of: finalized.id) {
                appState.reopenEvent(at: idx)
            }
        }
```

- [ ] **Step 2: Ensure `import AppKit` is at the top of `ContentView.swift`**

If not present, add it next to `import SwiftUI`.

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add commanderonev2/ContentView.swift
git commit -m "ContentView: block imports into finalized event folders"
```

---

## Task 10: End-to-end manual verification

**No files modified. Verification only.**

- [ ] **Step 1: Launch the app and pick a real event folder**

Use the running app on a folder that already has imported RAWs and a scanned `StatsReport` cache (any event card showing real counts will do).

- [ ] **Step 2: Finalize**

Right-click the event in the sidebar → "Finalize Event…" → confirm. Expected:
- Event row shows lock icon + "Finalizado" chip.
- Top Events row for this event shows the same total counts as before.
- Hero Card (if this is the latest event) shows the chip.

- [ ] **Step 3: Simulate file deletion**

Manually delete some RAWs from the folder via Finder. Reopen the app (or force a rescan from the event detail view). Expected: totals in Top Events / Hero Card do **not** decrease. The snapshot is canonical.

- [ ] **Step 4: Simulate folder move**

Move the entire event folder to another location (e.g. another folder on Desktop or external drive). The bookmark will fail to resolve. Expected: Top Events still shows the event with its finalized totals.

- [ ] **Step 5: Attempt to re-import**

Plug in a memory card, select the same (moved) destination via the app's destination picker — or import into the original path if recreated. Expected: alert "is finalized" appears, offering to Reopen and Import.

- [ ] **Step 6: Reopen**

Right-click the event → "Reopen Event…" → confirm. Expected:
- Chip disappears, lock icon back to folder.
- Top Events row recalculates from live data (will drop to current cached/peak/history values).
- The `finalized_events.json` file in `Application Support/commanderonev2/` no longer contains this event.

- [ ] **Step 7: Test removal from sidebar with surviving snapshot**

Finalize an event again. Then remove the event folder from the sidebar (using the existing remove UI, wherever that is — likely Settings or a sidebar context action that already exists). Expected: snapshot remains in Top Events (id stays in `finalized_events.json`).

> If there is no existing UI to remove an event folder, document that in a follow-up — out of scope for this plan.

- [ ] **Step 8: No commit**

This task is verification only. If any step fails, file the bug (or fix inline if obvious) and re-verify before closing the plan.

---

## Out of scope (deferred)

- Permanently deleting a snapshot whose bookmark has been removed (no UI surface for this yet). The snapshot will persist silently; sidebar bugs the user mentioned will be tackled in a separate pass.
- Automatic relink of moved folders via `originalBookmark`. Captured but unused.
- Migration / "Finalize all old events" bulk action. Out of scope per spec.

## Self-review notes (recorded for the implementer)

- All 4 spec sections (model, UI, read flow, finalize steps) are covered by Tasks 1–9.
- Task 10 covers the manual test list from the spec.
- Type names used consistently across tasks: `FinalizedEvent`, `FinalizedEventsStore`, `finalizedEvents`, `eventFolderFinalizedEventID`, `finalizeEvent(at:)`, `reopenEvent(at:)`, `finalizedEvent(forBookmarkIndex:)`, `finalizedEvent(matchingPath:)`, `deleteFinalizedEvent(id:)`.
- No placeholders ("TBD", "implement later", "appropriate error handling") remain.
- One soft instruction in Task 8 Step 3 asks the implementer to grep for an exact line range — acceptable because the file location is known and the change is one-line.
