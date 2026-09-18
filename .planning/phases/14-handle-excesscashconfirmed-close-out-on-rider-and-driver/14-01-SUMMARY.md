---
phase: 14-handle-excesscashconfirmed-close-out-on-rider-and-driver
plan: "01"
subsystem: socket-transport
tags: [socket-io, excess-cash, dedupe, regression-tests]

# Dependency graph
requires:
  - phase: 12-excess-balance-stage-2-settlement-rider-cash-online-plus-driver-cash-confirm
    provides: excess-cash requested/cancelled passthroughs + dedupe contract
provides:
  - on/offExcessCashConfirmed typed passthroughs in SocketService
  - confirmed close-out dedupe regression tests (exactly-once, key isolation)
affects: [14-02 rider close-out, 14-03 driver close-out]

# Tech tracking
tech-stack:
  added: []
  patterns: [socket passthrough with off-symmetry, dedupe regression via RideEventDedupe.resetForTests]

key-files:
  created: [test/excess_cash_confirmed_closeout_test.dart]
  modified: [lib/core/services/socket_service.dart]

key-decisions:
  - "Confirmed-vs-succeeded ordering owned by screen settled/dialog guards, not dedupe — distinct keys must both pass dedupe, so tests pin true/true and document the guard contract"

patterns-established:
  - "Confirmed dedupe key payment_excess_cash_confirmed mirrors requested/cancelled naming, no collision"

requirements-completed: [CONFIRM-01, CONFIRM-04]

# Metrics
duration: 1min
completed: 2026-09-18
---

# Phase 14 Plan 01: Socket Transport Summary

**Typed on/offExcessCashConfirmed passthroughs in SocketService plus 5 dedupe regression tests pinning exactly-once and key isolation**

## Performance

- **Duration:** 1 min
- **Started:** 2026-09-18T12:39:32Z
- **Completed:** 2026-09-18T12:40:09Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- on/offExcessCashConfirmed passthrough pair added after offExcessCashCancelled, exact colon-camelCase string, raw string only in SocketService
- New regression test file green (5 tests); existing transport tests still green (11/11 combined)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add on/offExcessCashConfirmed passthroughs** - `90a3cb7` (feat)
2. **Task 2: Create confirmed close-out regression tests** - `fdbb0bd` (test)

## Files Created/Modified
- `lib/core/services/socket_service.dart` - on/offExcessCashConfirmed passthrough pair
- `test/excess_cash_confirmed_closeout_test.dart` - confirmed exactly-once + key-isolation tests

## Decisions Made
- Confirmed-vs-succeeded same-ride ordering is owned by screen-level settled/dialog-open guards, not by dedupe. Distinct dedupe keys necessarily both pass `shouldHandleEvent`; the tests pin true/true and document that `_settled` (rider) / dialog-open (driver) make the second close-out a no-op. This keeps CONFIRM-04's no-collision and no-double-close-out halves consistent.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected test expectation for confirmed-vs-succeeded same ride**
- **Found during:** Task 2 (confirmed close-out regression tests)
- **Issue:** Plan specified "confirmed vs succeeded-settlement same ride → second false", but the plan's own no-collision must-have requires distinct dedupe keys (`payment_excess_cash_confirmed` vs `payment_succeeded_settlement`), and distinct keys always both pass `shouldHandleEvent`. A second-false assertion would fail.
- **Fix:** Tests assert both pass dedupe (true/true, both orders) and document that screen settled/dialog guards own exactly-once close-out, per 14-RESEARCH.md Pitfall 2 tolerant-handling recommendation.
- **Files modified:** test/excess_cash_confirmed_closeout_test.dart
- **Verification:** flutter test passes 11/11
- **Committed in:** fdbb0bd (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 plan-expectation bug)
**Impact on plan:** Test now matches actual dedupe mechanics; no scope change, no screen behavior added.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Screens can subscribe via on/offExcessCashConfirmed; ready for 14-02 (rider waiting-exit) and 14-03 (driver modal-close)
- Open question carried forward: whether backend also emits payment:succeeded for this flow — tolerant handling already recommended by research, device QA should log both events during one cash-confirm

## Self-Check: PASSED
