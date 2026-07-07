# Library Folders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to add existing RAW-containing folders as "Library Folders" — tracked in the sidebar alongside events, immediately scanned for stats one at a time, with visual indicators showing scan progress.

**Architecture:** Add a parallel `eventFolderIsLibrary: [Bool]` array to AppState (same pattern as `eventFolderDisplayNames`). A `scanQueue: [Int]` + `currentlyScanningIndex: Int?` in AppState drives sequential scanning using the existing `StatsRunner.runStatsForEventFolder`. Sidebar `eventRow()` reads the isLibrary flag to switch icon/color and show queue state. EventStatsView hides the Finalize button for library folders.

**Tech Stack:** Swift 6, SwiftUI, AppKit (NSOpenPanel), existing StatsRunner + BookmarkManager + EventStatsCache infrastructure.

---

## File Map

| File | Changes |
|------|---------|
| `commanderonev2/Models/AppState.swift` | Add `eventFolderIsLibrary`, `scanQueue`, `currentlyScanningIndex`, `libraryScanRunner`; add `isLibraryFolder(at:)`, `addLibraryFolder(url:)`, `drainScanQueue()`; update `removeEventFolder()` and `syncDisplayNamesCount()` |
| `commanderonev2/Views/Dashboard/DashboardView.swift` | Add "Add Folder" button to `TotalLibraryCard` |
| `commanderonev2/Views/Shell/AuroraSidebarView.swift` | Update `eventRow()` for library icon/color, scan indicators, context menu |
| `commanderonev2/Views/EventStatsView.swift` | Hide `lockEventButton` for library folders |

---

## Task 1: Data model — eventFolderIsLibrary array

**Files:**
- Modify: `commanderonev2/Models/AppState.swift`

- [ ] **Step 1: Add the property and persistence**

In `AppState.swift`, after the `eventFolderDisplayNames` declaration (around line 482), add:

```swift
/// Whether each event folder slot is a library folder (vs. active event). Same count as eventFolderBookmarks.
var eventFolderIsLibrary: [Bool] = [] {
    didSet { saveEventFolderIsLibrary() }
}
```

- [ ] **Step 2: Add syncIsLibraryCount() helper**

After `syncDisplayNamesCount()` (around line 718), add:

```swift
private func syncIsLibraryCount() {
    let n = eventFolderBookmarks.count
    if eventFolderIsLibrary.count > n {
        eventFolderIsLibrary = Array(eventFolderIsLibrary.prefix(n))
    } else if eventFolderIsLibrary.count < n {
        eventFolderIsLibrary += Array(repeating: false, count: n - eventFolderIsLibrary.count)
    }
}
```

- [ ] **Step 3: Call syncIsLibraryCount() from eventFolderBookmarks.didSet**

Inside the `eventFolderBookmarks` `didSet` block (around line 469), add a call to `syncIsLibraryCount()` alongside the existing sync calls:

```swift
var eventFolderBookmarks: [Data] = [] {
    didSet {
        syncDisplayNamesCount()
        syncPeakCounts()
        syncCachedCounts()
        syncManualDatesCount()
        syncFinalizedEventIDs()
        syncIsLibraryCount()   // ← add this line
        saveEventFolderBookmarks()
    }
}
```

- [ ] **Step 4: Add save/load for UserDefaults**

After `saveEventFolderDisplayNames()` (around line 1132), add:

```swift
private func saveEventFolderIsLibrary() {
    guard let data = try? PropertyListEncoder().encode(eventFolderIsLibrary) else { return }
    UserDefaults.standard.set(data, forKey: "eventFolderIsLibraryData")
}
```

In `init()` (around line 570, before the bookmarks load), add:

```swift
if let data = UserDefaults.standard.data(forKey: "eventFolderIsLibraryData"),
   let decoded = try? PropertyListDecoder().decode([Bool].self, from: data) {
    eventFolderIsLibrary = decoded
}
```

- [ ] **Step 5: Update removeEventFolder() to clean up the array**

Inside `removeEventFolder(at:)` (around line 1461, where other parallel arrays are removed), add:

```swift
if index < eventFolderIsLibrary.count { eventFolderIsLibrary.remove(at: index) }
```

- [ ] **Step 6: Add isLibraryFolder(at:) public helper**

After `addEventFolder()` (around line 1444), add:

```swift
func isLibraryFolder(at index: Int) -> Bool {
    guard index >= 0, index < eventFolderIsLibrary.count else { return false }
    return eventFolderIsLibrary[index]
}
```

- [ ] **Step 7: Build and confirm no errors**

```bash
xcodebuild -scheme commanderonev2 -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add commanderonev2/Models/AppState.swift
git commit -m "feat: add eventFolderIsLibrary parallel array to AppState"
```

---

## Task 2: Scan queue + addLibraryFolder

**Files:**
- Modify: `commanderonev2/Models/AppState.swift`

- [ ] **Step 1: Add scan queue state properties**

After `var eventFolderScanningIndices: Set<Int> = []` (around line 454), add:

```swift
/// Queue of bookmarkIndex values waiting for a library folder scan.
var scanQueue: [Int] = []
/// The bookmarkIndex currently being scanned by the library scan queue. nil = idle.
var currentlyScanningIndex: Int? = nil
/// Dedicated StatsRunner for the library scan queue (lazy — created on first use).
private var libraryScanRunner: StatsRunner?
```

- [ ] **Step 2: Add addLibraryFolder(url:)**

After `addEventFolder(bookmark:displayName:)` (around line 1444), add:

```swift
func addLibraryFolder(url: URL) {
    guard let bookmark = BookmarkManager.saveBookmark(for: url) else { return }
    let index = addEventFolder(bookmark: bookmark, displayName: url.lastPathComponent)
    if index < eventFolderIsLibrary.count {
        eventFolderIsLibrary[index] = true
    }
    if !scanQueue.contains(index) {
        scanQueue.append(index)
    }
    drainScanQueue()
}
```

- [ ] **Step 3: Add drainScanQueue()**

After `addLibraryFolder(url:)`, add:

```swift
func drainScanQueue() {
    guard currentlyScanningIndex == nil, !scanQueue.isEmpty else { return }
    let index = scanQueue.removeFirst()
    currentlyScanningIndex = index

    if libraryScanRunner == nil {
        libraryScanRunner = StatsRunner(appState: self)
    }
    guard let runner = libraryScanRunner else {
        currentlyScanningIndex = nil
        drainScanQueue()
        return
    }

    let path = index < eventFolderCachedPaths.count ? eventFolderCachedPaths[index] : ""
    guard !path.isEmpty else {
        currentlyScanningIndex = nil
        drainScanQueue()
        return
    }
    let url = URL(fileURLWithPath: path)

    Task {
        let result = await runner.runStatsForEventFolder(at: url)
        if let r = result, r.totalFilesAnalyzed > 0 {
            let now = Date()
            EventStatsCache.save(r, forPath: path, scanDate: now, rawFileCountAtScan: r.totalFilesAnalyzed)
            updateEventFolderCache(at: index, count: r.totalFilesAnalyzed, path: path)
            setEventFolderPeakIfHigher(at: index, count: r.totalFilesAnalyzed)
            log("Library folder scan complete: \(url.lastPathComponent) — \(r.totalFilesAnalyzed) photos")
        }
        currentlyScanningIndex = nil
        drainScanQueue()
    }
}
```

- [ ] **Step 4: Build and confirm no errors**

```bash
xcodebuild -scheme commanderonev2 -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add commanderonev2/Models/AppState.swift
git commit -m "feat: add scan queue and addLibraryFolder to AppState"
```

---

## Task 3: "Add Folder" button in TotalLibraryCard

**Files:**
- Modify: `commanderonev2/Views/Dashboard/DashboardView.swift`

- [ ] **Step 1: Add the button above the meta row**

In `TotalLibraryCard.body`, replace the `Divider` + `HStack` block (around line 378):

```swift
Divider().background(Color.auroraStroke).padding(.vertical, 6)

Button {
    addLibraryFolders()
} label: {
    Label("Add Folder", systemImage: "folder.badge.plus")
        .font(.manrope(12, weight: .semibold))
}
.buttonStyle(.plain)
.foregroundStyle(Color.auroraCyan)

HStack(spacing: 16) {
    metaItem(label: "Imports", value: "\(appState.importHistory.count)")
    Divider().frame(height: 22).background(Color.auroraStroke)
    metaItem(label: "Avg Speed", value: speedString)
    Divider().frame(height: 22).background(Color.auroraStroke)
    metaItem(label: "Events", value: "\(eventCount)")
}
Spacer(minLength: 4)
```

- [ ] **Step 2: Add addLibraryFolders() function to TotalLibraryCard**

After the closing brace of `metaItem(label:value:)` and before the closing brace of `TotalLibraryCard`, add:

```swift
private func addLibraryFolders() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    panel.message = "Select folders containing RAW files to add to your library"
    panel.prompt = "Add Folder"
    guard panel.runModal() == .OK else { return }
    for url in panel.urls {
        appState.addLibraryFolder(url: url)
    }
}
```

- [ ] **Step 3: Build and confirm no errors**

```bash
xcodebuild -scheme commanderonev2 -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add commanderonev2/Views/Dashboard/DashboardView.swift
git commit -m "feat: add Add Folder button to TotalLibraryCard"
```

---

## Task 4: Sidebar — library icon, scan indicators, context menu

**Files:**
- Modify: `commanderonev2/Views/Shell/AuroraSidebarView.swift`

- [ ] **Step 1: Update eventRow() icon and color for library folders**

In `eventRow(bookmarkIndex:event:depth:)` (around line 291), replace the full function:

```swift
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
```

- [ ] **Step 2: Build and confirm no errors**

```bash
xcodebuild -scheme commanderonev2 -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add commanderonev2/Views/Shell/AuroraSidebarView.swift
git commit -m "feat: library folder icon, scan indicators, and context menu in sidebar"
```

---

## Task 5: Hide Finalize button in EventStatsView

**Files:**
- Modify: `commanderonev2/Views/EventStatsView.swift`

- [ ] **Step 1: Guard lockEventButton behind isLibraryFolder check**

In `EventStatsView`, find where `lockEventButton` is shown (around line 178):

```swift
if bookmarkIndex != nil {
    lockEventButton
}
```

Replace with:

```swift
if let bookmarkIndex, !appState.isLibraryFolder(at: bookmarkIndex) {
    lockEventButton
}
```

- [ ] **Step 2: Build and confirm no errors**

```bash
xcodebuild -scheme commanderonev2 -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add commanderonev2/Views/EventStatsView.swift
git commit -m "feat: hide Finalize button for library folders in EventStatsView"
```

---

## Self-Review

**Spec coverage:**
- ✅ "Add Folder" button in TotalLibraryCard → Task 3
- ✅ Folder picker (NSOpenPanel, multi-select, directories only) → Task 3
- ✅ `eventFolderIsLibrary` parallel array, persisted → Task 1
- ✅ Sequential scan queue with `drainScanQueue()` → Task 2
- ✅ Sidebar visual distinction (different icon, scan state indicators) → Task 4
- ✅ Context menu without Finalize for library folders → Task 4
- ✅ EventStatsView hides lockEventButton → Task 5
- ✅ Remove from all arrays on `removeEventFolder()` → Task 1 Step 5

**Placeholder scan:** No TBDs or incomplete steps. All code is complete.

**Type consistency:**
- `isLibraryFolder(at:)` defined in Task 1, used in Tasks 4 and 5 ✅
- `addLibraryFolder(url:)` defined in Task 2, called in Task 3 ✅
- `drainScanQueue()` defined in Task 2, called from `addLibraryFolder` ✅
- `scanQueue`, `currentlyScanningIndex` defined in Task 2, read in Task 4 ✅
- `EventStatsCache.save(r, forPath:scanDate:rawFileCountAtScan:)` — matches existing call signature in EventStatsView.swift line 1212 ✅
- `updateEventFolderCache(at:count:path:)` and `setEventFolderPeakIfHigher(at:count:)` — both exist in AppState ✅
