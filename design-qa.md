# Tablet landscape journey UX — design QA

## Scope

- Branch: `codex/tablet-landscape-redesign`
- Target: 13-inch iPad landscape and similarly sized resizable windows.
- Source of truth: `/Users/wesleynyamu/Desktop/Screen Recording 2026-09-02 at 16.37.59.mov`.
- Phone and portrait tablet layouts retain their existing compact behavior.

## Evidence

- Combined recording/final comparison: `/private/tmp/tulink-tablet-journey-comparison.png`
- Final destination search: `/private/tmp/tulink-ipad-destination-panel-landscape.png`
- Final companion picker: `/private/tmp/tulink-ipad-companion-panel-landscape.png`
- Final journey preview: `/private/tmp/tulink-ipad-ready-card-landscape.png`
- Final recent journeys: `/private/tmp/tulink-ipad-journeys-panel-final-landscape.png`

The combined image places the recorded design and the implementation at the
same landscape density. The final states were rendered in the running iPad Pro
13-inch simulator with production map, route, and journey data.

## Findings and resolutions

1. **Where are you going** — the tall centered phone sheet required excessive
   reach and obscured the map. It is now a bounded 520-pixel lower-left panel,
   remains keyboard-aware, and retains an explicit close action.
2. **Who's coming** — the centered portrait sheet is now a bounded lower-left
   panel. Search, selection count, editing, and completion stay together within
   thumb reach while the route remains visible.
3. **Journey preview** — the route setup card now floats at the lower-left with
   a 16-pixel safe margin, full corner radius, and the existing participant and
   start controls intact.
4. **Live location/progress** — the journey progress surface is constrained to
   the same 520-pixel lower-left region instead of stretching across the map.
5. **End journey confirmation** — leader and follower confirmation dialogs use
   a lower-left, 480-pixel bounded placement on wide landscape screens. Phone
   dialogs are unchanged.
6. **Journey complete** — the completion summary is a 520-pixel lower-left card
   on wide screens, preserving the driven route behind it and keeping Done and
   View details reachable.
7. **Journey recap** — recap content is presented in a 760-pixel left panel with
   16-pixel margins, rounded containment, and independent scrolling. The panel
   is bounded to the available screen height.
8. **Recent journeys** — the previously missing landscape overlay is now a
   visible, content-sized lower-left panel. It preserves journey preview, long
   press details, and Go again actions without consuming the full map height.

Invitations use the same content-sized lower-left panel treatment so the map
navigation rail remains consistent across all journey overlays.

## Verification

- Full Flutter suite: passed, 443 tests with 14 declared skips.
- Focused tablet layout tests: passed for breakpoints, pending journey,
  completion summary, and journey recap.
- iOS simulator build: passed (`Runner.app`).
- Static analysis of all changed production and test files: no errors. Existing
  repository warnings and style notices remain outside this UI change.
- Visual inspection: no clipping, overflow, inaccessible actions, or map-blocking
  full-width surfaces were found in the verified landscape states.

final result: passed
