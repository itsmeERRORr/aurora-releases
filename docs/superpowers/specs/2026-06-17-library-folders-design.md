# Library Folders — Design Spec
**Date:** 2026-06-17

## Overview

Users can add existing folders that already contain RAW files as "Library Folders". These appear in the sidebar alongside events but are visually distinct. They are immediately scanned for stats using the existing StatsRunner pipeline. Scans run one at a time, with a queue indicator for folders awaiting scan.

---

## Data Model (AppState)

Two new parallel arrays, same indexing pattern as `eventFolderBookmarks`:

```swift
var eventFolderIsLibrary: [Bool] = []
```

- `true` = library folder (added via "Add Folder"), `false` = normal event
- Persisted in UserDefaults under key `"eventFolderIsLibraryData"` (JSON-encoded)
- Expanded/shrunk in sync with `eventFolderBookmarks` on add/remove (same pattern as `eventFolderDisplayNames`)

Scan queue state (in-memory only, not persisted):

```swift
var scanQueue: [Int] = []
var currentlyScanningIndex: Int? = nil
```

---

## Adding a Library Folder

**Entry point:** "Add Folder" button in `TotalLibraryCard`.

**Flow:**
1. Open `NSOpenPanel` with `canChooseFiles = false`, `canChooseDirectories = true`, `allowsMultipleSelection = true`
2. For each selected URL:
   - Create a security-scoped bookmark (`bookmarkData`)
   - Append to `eventFolderBookmarks`
   - Append `true` to `eventFolderIsLibrary`
   - Append index to `scanQueue`
3. Call `drainScanQueue()`

---

## Scan Queue

```
drainScanQueue():
  if currentlyScanningIndex != nil → return (already running)
  if scanQueue.isEmpty → return
  pop first index from scanQueue → currentlyScanningIndex
  run StatsRunner for that folder path (existing pipeline)
  on completion:
    currentlyScanningIndex = nil
    drainScanQueue()
```

Visual states per library folder in sidebar:
- **Scanning now** → small spinner + "Scanning…" label
- **Queued** → clock icon + "Queued" label  
- **Done** → normal library folder icon (no indicator)

---

## Sidebar

- Library folders appear in the existing EVENTS section (no new section)
- **Icon:** `folder.badge.gearshape` or `folder.fill` tinted `Color.auroraBlue` (vs events which use `auroraViolet`)
- Tooltip, truncation, rename, re-link, remove all work identically to events
- Right-click context menu: Rename, Re-link, Remove — **no Finalize**
- Scan state indicators (spinner / clock) rendered inline in the sidebar row

---

## EventStatsView

- Clicking a library folder in the sidebar opens the same `EventStatsView`
- The **Finalize Event** button is hidden when the folder is a library folder
- All other features (stats, lenses, cameras, ISO, rename, manual date, etc.) work identically

---

## TotalLibraryCard UI

Button placement — below the existing Divider, left-aligned, before the meta row:

```
Total Library
[count]
[subtitle]
─────────────────────────────
[+ Add Folder]
0 Imports  |  — Avg Speed  |  0 Events
```

Button style: ghost/outline (secondary), compact, using existing `AuroraGradientButtonStyle` or a plain bordered style consistent with the app.

---

## What Library Folders Cannot Do

- Cannot be Finalized
- Cannot be used as an import destination (they are read-only scan targets)
- No banner image (or same as events — low priority, can be added later)

---

## Out of Scope

- Re-scanning a library folder on demand (can be added later)
- Showing library folder stats in the Statistics page aggregates (uses existing total stats pipeline which already covers all event folders)
- Drag-and-drop reordering (already works for all event folder nodes)
