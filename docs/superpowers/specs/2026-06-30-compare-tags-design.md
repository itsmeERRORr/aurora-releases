# Compare Tags — Design

## Goal

Let the user compare two event tags side by side (e.g. "Sports" vs "Esports") to answer "what do I do differently when shooting X vs Y" — without duplicating the entire Statistics page per tag.

## Entry point

A new **"Compare"** button sits next to the existing "Filter by" button in `StatisticsTopbar`, visible only when `mode == .total` (same visibility rule as Filter by). Tapping it opens a popover tag picker:

1. Step 1: list of all `EventTag` cases — pick Tag A.
2. Step 2: same list minus Tag A — pick Tag B.
3. Popover closes; the page switches into **Compare mode**.

While in Compare mode:
- The "Compare" button changes label to show the active pair (e.g. "Sports vs Esports") with a small "×" to exit Compare mode and return to normal Statistics.
- The "Filter by" **tag** pill section is irrelevant (Compare already picks two explicit tags) — hide it while comparing. The **Year** filter stays active and applies to both columns equally, so Compare always respects whatever year is selected in Filter by (default: current year, per existing behavior).
- The existing single-tag-filtered content (GeneralStatsGrid, HeroEventCard, PhotoStatsGrid, cameras/lenses, events rows, charts, shooting time, active days) is replaced by a single new component: `TagComparisonView`.

## TagComparisonView

A static card with a header (`Tag A name` | vs | `Tag B name`, each colored with its `EventTag.tint`) followed by a comparison table, one row per metric, two value columns:

1. Total RAWs
2. Data Transferred
3. Top Camera (name + count)
4. Top Lens (name + count)
5. Avg ISO / Avg Aperture / Avg Shutter (three sub-rows or one combined row — implementation detail, keep as three rows for readability)
6. Avg Working Hours per Event
7. Busiest Day (most photos in a single day, with date)
8. Events (count of events carrying that tag, within the active year filter)

For numeric metrics (1, 2, 6, 8, and the ISO/aperture/shutter trio where "higher/lower is just different" doesn't really have a winner — only 1, 2, 6, 8 get a winner highlight), the column with the higher value gets a subtle highlight (bold value + small accent-colored up-chevron). Top Camera/Lens/Busiest Day are informational only, no highlight.

If a tag has zero matching events (within the active year filter), its column shows "—" for every row instead of zero, plus a one-line note under the header: "No events tagged {Tag} in {year}."

## Data layer

Today, `AppState.dashboardStatsReport` and `EventAggregator.build` only know how to filter by the *currently selected* `appState.dashboardTagFilter` / `appState.dashboardYearFilter` — they read those properties directly. Compare needs the same filtering logic but parameterized by an explicit tag, independent of (and without disturbing) the global dashboard filter state.

Refactor:
- `EventAggregator.build(appState:)` gains two optional parameters, `tagOverride: EventTag?` and `yearOverride: Int?`, defaulting to `nil`. When set, they're used instead of reading `appState.dashboardTagFilter`/`appState.dashboardYearFilter`. Existing call sites (Top Events, Latest Events, View All sheets) are unaffected — they call it with no overrides and keep reading the live dashboard filters exactly as before.
- `AppState.dashboardStatsReport` is split: the actual combine-by-tag-and-year logic moves into a new `func statsReport(forTag tag: EventTag?, year: Int?) -> StatsReport?`, and `dashboardStatsReport` becomes a one-line wrapper: `statsReport(forTag: dashboardTagFilter, year: dashboardYearFilter)`.
- A new `CompareTagsAggregate` (or reuse `EventAggregate` list + the combined `StatsReport`) is computed twice per render — once for Tag A, once for Tag B — using `appState.statsReport(forTag: tagA, year: appState.dashboardYearFilter)` for the report-level metrics (RAWs, bytes, ISO/aperture/shutter, top camera/lens, busiest day) and `EventAggregator.build(appState:, tagOverride: tagA, yearOverride: appState.dashboardYearFilter)` for the per-event metrics (avg working hours per event, events count).

## State

- `StatisticsView` gains `@State private var compareTags: (EventTag, EventTag)?` (nil = not comparing).
- `StatisticsTopbar` gains a binding to this state (or the picker logic lives directly in `StatisticsTopbar`, calling back up via a closure — match whatever's least invasive once in the plan).
- Exiting Compare mode (the "×") simply sets `compareTags = nil`, returning to the normal filtered page.

## Out of scope (for this spec)

- Comparing more than 2 tags at once.
- Comparing a tag against "no tag" / against the global total.
- Persisting the last-compared pair across app relaunches.
