---
phase: 19-ride-flow-resilience
plan: 03
subsystem: ride-flow
tags: [connection-ux, kill-restore, rider-persist, active-ride-storage, human-verify]

# Dependency graph
requires:
  - phase: 19-ride-flow-resilience
    provides: 19-01 socket hardening (emitReliable queue, reconnect) + 19-02 RideSession restore/resync entry with versioned snapshots
provides:
  - ConnectionBanner widget (reconnecting/offline/retry) wired on rider + driver ride screens
  - Rider snapshot persisted on searching entry and every transition (kill-proof searching/assigned/progress)
  - snapshotStatusForRider canonicalization helper with unit tests
  - Human kill-restart device matrix (driver approved; rider bug found + fixed, re-verify pending)
affects: [ride-progress, ride-assigned, driver-home, future restore work]

# Tech tracking
tech-stack:
  added: []
  patterns: [snapshot-follows-transition, scheduled-never-persists, backend-canonical-snapshot-status]

key-files:
  created: [lib/core/widgets/connection_banner.dart, test/connection_banner_test.dart]
  modified: [lib/core/services/ride_session.dart, lib/features/ride/ride_assigned_screen.dart, lib/features/ride/ride_progress_screen.dart, lib/features/driver/driver_home_screen.dart, lib/features/home/home_screen.dart, test/ride_session_test.dart]

key-decisions:
  - "RideAssignedScreen persists its own snapshot (save on init, updateStatus per transition) instead of routing saves through home — booking pushes it directly, home is off-tree"
  - "Snapshot stores backend-canonical status via snapshotStatusForRider (searching/reassigning→requested, arrived→driver_arrived, at_stop→in_progress) so cold start reconciles 1:1 with getRideDetails"
  - "Scheduled rides never persist on the rider path (08-01 rule preserved); day-of scheduled entry stays home-owned via Upcoming Go to Pickup"
  - "Terminal rider states (cancel/expired/completed) clear or mark final so cold start lands home, never on a dead ride"

patterns-established:
  - "Snapshot-follows-transition: every _rideStatus assignment on rider screens is paired with a persist/update/clear call"
  - "Guarded persist: _isScheduled checked at call time (flag can flip mid-screen), skipping scheduled writes"

requirements-completed: [RES-04, RES-06]

# Metrics
duration: 45min
completed: 2026-09-22
---

# Phase 19 Plan 03: Connection UX + Kill-Proofing Summary

**Uber-style ConnectionBanner on all ride screens plus a fixed rider save path: searching entry and every transition now persist, with human device pass approving driver and a re-verify checklist for rider.**

## Performance

- **Duration:** 45 min
- **Started:** 2026-09-22T08:55:00Z
- **Completed:** 2026-09-22T09:42:33Z
- **Tasks:** 3 + 1 human-reported bug fix
- **Files modified:** 8

## Accomplishments

- ConnectionBanner widget (live-hidden / reconnecting-amber / offline-grey + retry via `initSocket(forceReconnect: true)` + `resyncActiveRide`), mounted overlay top-center on `ride_assigned_screen`, `ride_progress_screen`, driver home/execution; stale driver marker dimmed + "Last updated Xs ago" past 30s; offline action buttons queue via `emitReliable` with queued-intent copy, no double-fire while same rideId+action pending
- Widget tests for all banner states (live renders nothing, reconnecting pill + timestamp, offline retry fires once, double-tap debounced) + full regression sweep green
- Rider kill-restore bug found by human device pass, diagnosed and fixed (see Deviations): kill during searching now restores the overlay; kill on assigned/progress restores via updated snapshot + server-wins reconcile
- Full `flutter test` suite green (142 tests, incl. 3 new snapshot-canonicalization tests)

## Task Commits

Each task was committed atomically:

1. **Task 1: ConnectionBanner widget + screen wiring** - `98b4aeb` (feat)
2. **Task 2: Widget tests + regression sweep** - `70e2a6a` (test)
3. **Task 3 fix: Rider snapshot persist on searching entry + transitions** - `8532ad2` (fix)
4. **Task 3 test: snapshot-status canonicalization pins** - `c708cba` (test)

## Files Created/Modified

- `lib/core/widgets/connection_banner.dart` - Uber-style reconnecting/offline pill + stale chip + retry (Task 1)
- `test/connection_banner_test.dart` - Banner state widget tests (Task 2)
- `lib/core/services/ride_session.dart` - Added pure `snapshotStatusForRider` status canonicalizer (fix)
- `lib/features/ride/ride_assigned_screen.dart` - `_persist/_update/_clearRiderSnapshot` helpers; save on init; update on accepted/driver_arrived/in_progress/reassign/resume-sync/completed; clear on cancel/expired (fix)
- `lib/features/home/home_screen.dart` - `_persistSearchingSnapshot` on all 3 searching entries (restart/destination/airport); `updateStatus(requested)` on both reassign handlers (guarded by `_activeRide != null`); `clear()` on cancel success + expiration (fix)
- `test/ride_session_test.dart` - 3 new `snapshotStatusForRider` tests (searching family → requested + searching route; transitions keep routes; unknown passthrough) (fix test)
- `lib/features/ride/ride_progress_screen.dart`, `lib/features/driver/driver_home_screen.dart` - Banner wiring (Task 1)

## Decisions Made

- RideAssignedScreen owns its snapshot rather than routing saves through home: the modern booking flow pushes it directly via `pushReplacement`, so home is off-tree and its accepted/arrived/started handlers never fire. Any fix inside home alone would have left the bug in place.
- Backend-canonical snapshot statuses (`requested`, not UI `searching`) so the persisted value compares 1:1 with `getRideDetails` status and hits the same `routeForStatus` branches the restore path already tests.
- Scheduled rides excluded from rider persistence at call time (both widget flag and live `_isScheduled`), preserving the 08-01 no-corruption rule; day-of scheduled flow unchanged (home-owned via Upcoming list).
- Terminal states clear (cancel/expired) or stamp final (completed/early_completed, which `finalStatuses` clears on next cold start) so no dead ride ever restores.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Rider searching entry never persisted — kill+reopen dropped to home**
- **Found during:** Task 3 (human device pass reported rider kill+reopen does NOT restore; driver approved)
- **Issue:** The modern booking flow pushes `RideAssignedScreen` directly; that screen contained zero `ActiveRideStorage` references, and home's three searching entries (`_restartRideBooking`, destination-search, airport return) set `_isSearching/_activeRide` without saving. The only rider saves were `accepted`/`driver_arrived`/`in_progress` in home handlers that never run while the assigned screen is live. Kill during searching → no snapshot → restore finds nothing → home.
- **Fix:** `_persistRiderSnapshot` (save) at end of `_setupInitialState`; `_updateRiderSnapshot` on accepted, driver_arrived, in_progress, both reassign paths, resume-sync forward-apply, completed/early_completed; `_clearRiderSnapshot` on user cancel, `ride:cancelled`, hard driver-cancel, expired. Home's 3 searching entries save `requested`; home reassign handlers `updateStatus('requested')`; home cancel/expire `clear()`. New pure `snapshotStatusForRider` helper + 3 unit tests.
- **Files modified:** lib/core/services/ride_session.dart, lib/features/ride/ride_assigned_screen.dart, lib/features/home/home_screen.dart, test/ride_session_test.dart
- **Verification:** `flutter analyze` zero new issues (delta vs stash = line shifts only); `test/ride_session_test.dart` 18/18 green; full `flutter test` 142/142 green
- **Committed in:** `8532ad2` (fix) + `c708cba` (test)

---

**Total deviations:** 1 auto-fixed (1 bug — the exact failure the human device pass caught)
**Impact on plan:** Fix is the plan's success criterion ("zero dead-ends"); no scope creep — scheduled behavior, driver flow, and banner UX untouched.

## Issues Encountered

- Human device pass: driver kill-mid-trip restore approved; rider kill+reopen failed to restore (no snapshot on the save path). Diagnosed to the missing searching-entry save (restore core verified working by the driver pass), fixed, unit + suite green. Rider re-verification on device still pending — checklist below.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Rider re-verify checklist for the human (kill-proofing sign-off):
  1. Rider: book instant ride → kill app on searching → reopen → expect searching overlay restored, not home.
  2. Rider: kill on assigned (driver on the way) → reopen → expect assigned screen with driver, not home.
  3. Rider: kill mid-trip (in progress) → reopen → expect trip progress restored.
- Phase 19 complete after rider re-verify passes; ready for phase transition.

---
*Phase: 19-ride-flow-resilience*
*Completed: 2026-09-22*

## Self-Check: PASSED
- lib/core/widgets/connection_banner.dart, test/connection_banner_test.dart on disk; snapshotStatusForRider present in ride_session.dart
- Commits 98b4aeb, 70e2a6a, 8532ad2, c708cba in history
- flutter analyze: zero errors, zero new warnings; flutter test: 142/142 green
