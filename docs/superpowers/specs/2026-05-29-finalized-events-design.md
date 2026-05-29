# Finalized Events — Design

**Date:** 2026-05-29
**Status:** Design approved, pending implementation plan

## Problem

User workflow:

1. Before an event, creates a folder structure on Desktop or external 990 Pro drive:
   ```
   <Event Name>/
     <Event Day>/
       RAWs/
       Finais/
   ```
2. Throughout the event (days to weeks), imports RAW files into `RAWs/`.
3. After the event, deletes RAWs that were not edited (e.g. 20.000 → 2.000).
4. Moves the entire event folder to a home NAS, which is unreachable when away from home.

The user wants the app to preserve the **total** statistics for the event (e.g. the original 20.000 photos and all derived EXIF data) forever — independent of:

- Files being deleted from the folder.
- The folder being moved to a different location.
- The folder's host volume being offline.

Current behaviour partially addresses this via `eventFolderPeakRawCounts` (peak-only count) and `eventFolderCachedCounts/Paths`, but the data model is coupled to the sidebar bookmark index and breaks when the folder moves or the bookmark resolution fails. EXIF aggregates (lenses, cameras, ISO, etc.) are not captured per-event at all.

## Goal

Add an explicit "Finalize Event" action that snapshots all of an event's statistics into a self-contained, persistent record decoupled from the live folder.

## Approach

### Trigger model — hybrid

Statistics accumulate live throughout the event (no change to existing behaviour). When the user is ready, an explicit "Finalize Event" action freezes the current totals. After finalization:

- Totals shown in the app for that event become the frozen snapshot.
- New imports to that folder are blocked (with a "Reopen" escape hatch).
- The folder may be deleted, moved, or its volume ejected — the snapshot remains canonical.

### Data model

New first-class model with stable identity, independent of the sidebar bookmark.

```swift
struct FinalizedEvent: Identifiable, Codable {
    let id: UUID
    var name: String                 // editable
    var snapshot: StatsReport        // frozen — all EXIF/counts/aggregates
    var totalBytes: Int64            // sum of importHistory for the folder
    var photoCount: Int              // max(snapshot.totalFilesAnalyzed, peak, cached)
    var firstImportDate: Date?
    var lastImportDate: Date?
    let finalizedAt: Date
    var lastKnownPath: String        // informational
    var originalBookmark: Data?      // optional, for future relink attempts
}
```

New service `FinalizedEventsStore`:

- Persists a single JSON file at `Application Support/commanderonev2/finalized_events.json`.
- API: `all()`, `add(_:)`, `update(_:)`, `remove(id:)`, `find(byPath:)`.
- Lives alongside `StatsStorage` and `EventStatsCache`.

`AppState` additions:

- `var finalizedEvents: [FinalizedEvent] = []` — loaded from the store on `init`.
- `var eventFolderFinalizedEventID: [UUID?]` — parallel array to `eventFolderBookmarks`, synced by the same helpers (`syncCachedCounts` etc.). `nil` while active; set to the snapshot's UUID after finalization.

### UI

**"Finalize Event" action**

- Surfaced on each event card in the sidebar (in the existing `…` menu / context menu — pattern-aligned with current actions).
- Confirmation dialog: *"Finalize `<Name>`? Current totals (X photos, Y GB) will be saved permanently. New imports won't update the totals."*

**Finalized state visual**

- "Finalizado" chip next to the name in the sidebar (neutral colour, `auroraFaint`).
- Same chip in Statistics → Top Events and Hero Card rows.
- Subtle lock icon if the folder's host volume is currently inaccessible.

**Secondary actions**

- "Reopen Event" — removes `finalizedEventID` from the bookmark, removes the snapshot from the store, returns the entry to live-count mode. Confirmation required.
- "Delete Permanently" — only available on snapshots whose sidebar bookmark has been removed; deletes from `FinalizedEventsStore`.

**Importing into a finalized event**

- Blocked by default. If the import destination matches a finalized event's path (or is inside it), show warning: *"This event is finalized. Reopen to continue importing?"* with `Reopen and Import` / `Cancel`.

### Read flow — snapshot vs live

Rule: if the bookmark has a `finalizedEventID`, the snapshot is the source of truth. Otherwise, live calculation as today.

| Surface | Active | Finalized |
|---|---|---|
| Sidebar event card | live or cached count | `snapshot.totalFilesAnalyzed`, no scan |
| Statistics → Top Events / Hero | current `EventAggregator` logic | reads from `finalizedEvents` |
| Statistics → totals (`totalStatsReport`) | unchanged | unchanged |
| Statistics → monthly/yearly charts | unchanged (`totalStatsReport`) | unchanged |
| Remove bookmark from sidebar | clears all event data | snapshot remains in store, still appears in Top Events |

`EventAggregator.build()` is extended to iterate `appState.finalizedEvents` first as canonical for finalized events; the existing logic over `importHistory + cached/peak counts` continues for active ones.

`totalStatsReport` is **not** modified by the snapshot lifecycle — it remains the accumulated global EXIF total. Per-event snapshots are an additional per-event view.

### Finalize action — exact steps

1. Ensure a recent EXIF scan exists for the folder. If not, run one now with a progress indicator. Refuse to finalize without one (or with explicit user override — see edge cases).
2. Build the `FinalizedEvent`:
   - `snapshot` = the freshest `StatsReport` from `EventStatsCache` or the just-completed re-scan.
   - `photoCount` = `max(snapshot.totalFilesAnalyzed, peakRawCount, cachedCount)`. Defensive.
   - `totalBytes` = sum of `importHistory` entries that fall under the folder path.
   - `firstImportDate` / `lastImportDate` from the same import history.
   - `lastKnownPath` and `originalBookmark` captured.
3. Persist via `FinalizedEventsStore.add(_:)`.
4. Set `appState.eventFolderFinalizedEventID[index] = newID`.

### Edge cases

- **Folder offline at finalize time:** show warning *"No fresh data for this folder. Finalize with last known values (X photos)?"* — user decides.
- **Editing a snapshot:** only `name` is editable. Numbers are immutable. Reopen is the path to revise numbers (triggers re-scan).
- **Migration of existing events:** none. `finalizedEvents` starts empty. All existing sidebar events remain active until the user finalizes them manually. (User noted that existing sidebar events have separate bugs to address later.)
- **Reopen:** removes the snapshot from the store entirely (no soft-delete). The bookmark returns to live mode.

### Testing (manual)

- Finalize event with folder online → snapshot correct, "Finalizado" chip appears.
- Eject the volume after finalize → Top Events still shows correct numbers.
- Move folder to another location → idem.
- Remove bookmark from sidebar → snapshot remains in Top Events; "Delete Permanently" removes it from the store.
- Reopen finalized event → chip disappears, count returns to live, snapshot gone from store.
- Attempt to import into a finalized event → blocked, prompt to reopen.

## Non-goals

- Automatic detection of "event ended". The user controls when to finalize.
- Relinking a moved folder automatically. `originalBookmark` is captured but not actively used yet — reserved for a future "Relocate folder" UX.
- Backfilling snapshots for already-archived events (folders no longer in the sidebar, never tracked).
- Touching the existing sidebar bugs separately raised by the user.

## Files touched (anticipated)

New:
- `commanderonev2/Models/FinalizedEvent.swift`
- `commanderonev2/Services/FinalizedEventsStore.swift`

Modified:
- `commanderonev2/Models/AppState.swift` — add `finalizedEvents`, `eventFolderFinalizedEventID`, sync helpers, finalize/reopen methods.
- `commanderonev2/Views/Statistics/TopEventsPanel.swift` — `EventAggregator` extension.
- `commanderonev2/Views/Statistics/HeroEventCard.swift` — finalized chip.
- `commanderonev2/Views/Shell/AuroraSidebarView.swift` — finalize/reopen menu, finalized chip on event card.
- `commanderonev2/Services/ImportEngine.swift` — guard against importing into finalized events.
