---
phase: 14-handle-excesscashconfirmed-close-out-on-rider-and-driver
plan: "02"
subsystem: rider-settlement
tags: [socket-io, excess-cash, rider, settlement-sheet, dedupe]

# Dependency graph
requires:
  - phase: 14-handle-excesscashconfirmed-close-out-on-rider-and-driver plan 01
    provides: on/offExcessCashConfirmed typed passthroughs + confirmed dedupe regression tests
provides:
  - confirmed listener wired in ExcessSettlementSheet with waiting-state exit via authoritative refresh
  - event thank-you message passthrough into settled snackbar
affects: [14-03 driver close-out]

# Tech tracking
tech-stack:
  added: []
  patterns: [mirror-handler with shared settled guard, optional success-message passthrough into shared refresh]

key-files:
  created: []
  modified: [lib/features/ride/excess_settlement_sheet.dart]

key-decisions:
  - "Success copy passed as optional _refresh param, not a second pop path — single authoritative exit preserved"
  - "Baseline stash step skipped: parallel uncommitted driver work in tree made stash unsafe; current analyze zero-issues suffices"

patterns-established:
  - "Confirmed handler mirrors succeeded handler order: rideId-match, dedupe, settled guard, refresh"

requirements-completed: [CONFIRM-02, CONFIRM-04]

# Metrics
duration: 5min
completed: 2026-09-18
---

# Phase 14 Plan 02: Rider Close-Out Summary

**Rider waitingCash exits with event thank-you settled confirmation via authoritative refresh on driver cash-confirm, co-fired succeeded no-ops on shared settled guard**

## Performance

- **Duration:** 5 min
- **Started:** 2026-09-18T12:41:07Z
- **Completed:** 2026-09-18T12:46:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- `_onExcessCashConfirmed` wired via `on/offExcessCashConfirmed` passthroughs with off-symmetry in dispose
- Handler order pinned: rideId-match (rideId/bookingId/_id fallbacks) → dedupe `payment_excess_cash_confirmed` → `mounted || _settled` guard → `_refresh(fromEvent: true)`
- Event non-empty `message` shown verbatim as success snackbar, fallback to existing "Excess paid successfully!" copy
- 11/11 tests green across confirmed close-out + transport suites; analyze zero issues; zero select-payment refs; raw confirmed string absent from sheet

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire confirmed listener with tolerant settled close-out** - `34336a9` (feat)
2. **Task 2: Verify rider close-out with tests and analyze** - no new commit (verification-only, working tree clean for plan files)

**Plan metadata:** `5bcdb08` (docs: complete plan)

## Files Created/Modified
- `lib/features/ride/excess_settlement_sheet.dart` - confirmed listener + handler + optional successMessage passthrough in `_refresh`

## Decisions Made
- Success copy passed as optional `_refresh(successMessage:)` param, not a second pop path — keeps the single authoritative-balance exit (404-fix lesson intact). Displayed verbatim, never substring-matched.
- No AudioService ring on confirmed (toast suffices per plan); `_selectCash`, WebView, and OutstandingBalanceScreen untouched.
- Baseline `git stash` + analyze step replaced with current-tree analyze: uncommitted driver-home changes (parallel 14-03 work) made stashing unsafe; current file analyzes "No issues found" so zero new issues holds trivially.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed raw event string from doc comment**
- **Found during:** Task 1 (post-edit rg verification)
- **Issue:** Doc comment contained literal `payment:excessCashConfirmed`, violating the plan's "raw string forbidden here, rg-absent" rule
- **Fix:** Reworded comment to "confirmed event"
- **Files modified:** lib/features/ride/excess_settlement_sheet.dart
- **Verification:** `rg payment:excessCashConfirmed lib/features/ride/` returns clean
- **Committed in:** 34336a9 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Comment-only change; no behavior or scope change.

## Issues Encountered
- Uncommitted modifications to `lib/core/constants/api_constants.dart` (local socket IP) and `lib/features/driver/driver_home_screen.dart` (confirmed-toast guard, appears to be parallel 14-03 work) present in tree on arrival. Left untouched and excluded from plan commits.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Rider close-out complete; ready for 14-03 (driver Collect-Cash modal close-out)
- Open live-backend question (carried from 14-01): whether backend ALSO emits `payment:succeeded` for driver-cash-confirm. Code handles either order via shared `_settled` guard; device QA should log both events during one cash-confirm to confirm.

## Self-Check: PASSED
- SUMMARY.md exists on disk; sheet file exists; commit 34336a9 in git log.
