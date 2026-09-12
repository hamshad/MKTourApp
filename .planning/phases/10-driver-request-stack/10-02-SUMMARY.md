---
phase: 10-driver-request-stack
plan: 02
subsystem: driver
tags: [ride-request, stack-ui, flutter, queue]

# Dependency graph
requires:
  - phase: 10-01 queue foundation
    provides: _requestQueue/_requestIndex state with enqueue-while-requesting and per-ride eviction
provides:
  - Stack-visible DriverRequestPanel (1-of-N pill, chevrons, dots, background rows)
  - Queue-to-panel wiring with per-card select/accept/decline semantics
affects: [driver request display, future request timeout UI]

# Tech tracking
tech-stack:
  added: []
  patterns: [stack-mirrors-visible-card, newest-at-zero, payload-only-background-rows]

key-files:
  created: []
  modified: [lib/features/driver/driver_request_panel.dart, lib/features/driver/driver_home_screen.dart]

key-decisions:
  - "Newest request inserts at 0 and takes the visible card; previous card becomes a background row"
  - "Decline never stops audio while the stack is non-empty; stop happens only on drain"

patterns-established:
  - "Stack-mirrors-visible-card: panel receives unmodifiable queue + index; home owns selection so accept/decline need no panel logic"
  - "Payload-only background rows: name/fare/distance/address from queued payload, no PlacesService lookup off the visible card"

requirements-completed: [STACK-04]

# Metrics
duration: 1min
completed: 2026-09-12
---

# Phase 10 Plan 02: Stacked Request UX Summary

**Uber/Bolt-style stacked request cards: 1-of-N count pill with chevrons/dots, tappable background rows, per-card decline and stack-clearing accept on top of the 10-01 queue.**

## Performance

- **Duration:** 1 min
- **Started:** 2026-09-12T09:36:34Z
- **Completed:** 2026-09-12T09:37:45Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- DriverRequestPanel accepts `requests`/`requestIndex`/`onSelectRequest` with `[rideData]` fallback so single-request flow renders pixel-identical to today
- Count pill "N of M" plus chevron buttons (wrapped) and dot indicators whenever 2+ requests queued; background rows show name, £fare, distance and jump to that card on tap
- Home screen passes unmodifiable queue + index + selector; newest request inserts at 0 and takes the card
- Declining removes only the visible card with audio kept ringing while the stack remains; accepting the visible card clears the whole stack and proceeds to pickup as today

## Task Commits

Each task was committed atomically:

1. **Task 1: Stack-aware DriverRequestPanel** - `1ee228c` (feat)
2. **Task 2: Wire queue to panel with per-card accept/decline** - `e3ccf64` (feat)

**Plan metadata:** docs commit `docs(10-02)` (see git log; amended for SUMMARY sync)

## Files Created/Modified

- `lib/features/driver/driver_request_panel.dart` - Stack props, count pill, chevrons/dots, background rows, didUpdateWidget address refetch
- `lib/features/driver/driver_home_screen.dart` - Queue/index/callback wiring, newest-at-0 insert, `_selectQueuedRequest`, decline audio fix

## Decisions Made

- Newest request inserts at 0 and takes the visible card. Rationale: plan mandates bold-first newest-at-0 UX; previous visible card stays reachable as a background row instead of being buried at the end.
- Decline no longer calls `AudioService.stop()` upfront; `_removeQueuedRequest` stops only when the queue drains. Rationale: stacked declines must keep ringing while offers remain.
- `_selectQueuedRequest` clears `_acceptError` on card switch. Rationale: error banner is bound to the visible card; carrying it across would blame the wrong ride.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Decline stopped ringtone while stacked requests remained**
- **Found during:** Task 2 (queue-to-panel wiring)
- **Issue:** `_declineRide` called `AudioService.instance.stop()` before `_removeQueuedRequest`, silencing the ringtone even with cards left in the queue
- **Fix:** Removed the upfront stop; drain-stop inside `_removeQueuedRequest` is the single owner
- **Files modified:** lib/features/driver/driver_home_screen.dart
- **Verification:** `flutter analyze` clean (0 errors); code path review confirms stop only on empty
- **Committed in:** e3ccf64 (Task 2 commit)

**2. [Rule 2 - Missing Critical] `_selectQueuedRequest` clamps index and clears card-bound error**
- **Found during:** Task 2 (queue-to-panel wiring)
- **Issue:** Plan specified the callback but no bounds/error semantics; an out-of-range index would desync `_rideData`/`_currentRideId` and a stale accept error would stick to the wrong card
- **Fix:** Added `_selectQueuedRequest` with clamping, visible-card sync, and `_acceptError = null` on switch
- **Files modified:** lib/features/driver/driver_home_screen.dart
- **Verification:** `flutter analyze` clean (0 errors)
- **Committed in:** e3ccf64 (Task 2 commit)

**3. [Rule 1 - Bug] Panel fetched geocoded addresses only once, staling on card switch**
- **Found during:** Task 1 (stack-aware panel)
- **Issue:** `_fetchDetailedAddresses` ran only in `initState`; cycling cards would show the previous card's pickup/dropoff addresses
- **Fix:** Added `didUpdateWidget` comparing `rideData` and refetching for the newly visible card
- **Files modified:** lib/features/driver/driver_request_panel.dart
- **Verification:** `flutter analyze` clean (0 errors)
- **Committed in:** 1ee228c (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (2 bugs, 1 missing critical)
**Impact on plan:** All auto-fixes necessary for stack correctness. No scope creep; no new dependencies; execution path untouched.

## Issues Encountered

None - `flutter analyze` reports 0 errors on both files (pre-existing `withOpacity` deprecation infos only).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Stack UI complete on top of the 10-01 queue; phase 10 has no further plans (2/2) — ready for phase transition.
- Manual device pass still recommended per plan verification: stack 2-3 test requests, cycle, decline one card, accept visible, confirm pickup rideId.

---
*Phase: 10-driver-request-stack*
*Completed: 2026-09-12*

## Self-Check: PASSED
