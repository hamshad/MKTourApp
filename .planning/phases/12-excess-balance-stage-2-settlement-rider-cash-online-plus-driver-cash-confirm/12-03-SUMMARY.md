---
phase: 12-excess-balance-stage-2-settlement-rider-cash-online-plus-driver-cash-confirm
plan: 03
subsystem: payments
tags: [excess-balance, stage2-settlement, driver-cash-confirm, socket, error-mapper]

# Dependency graph
requires:
  - phase: 12-01-settlement-transport
    provides: confirmDriverCash ApiService method + excess-cash socket passthroughs
  - phase: 12-02-rider-settlement-sheet
    provides: selectBalanceMethod mapper entries (preserved via append-only edit)
provides:
  - Driver Collect-Cash modal on payment:excessCashRequested with confirm-driver-cash wiring
  - Silent auto-close on payment:excessCashCancelled + payment:succeeded
  - confirm-driver-cash 400/401/403/409 mapper copy in RideErrorMapper
affects: [13-suspension-safeguard]

# Tech tracking
tech-stack:
  added: []
  patterns: [flag-guarded dialog with stored dialog context for socket-driven pop, failure-stays-open StatefulBuilder modal]

key-files:
  created: []
  modified: [lib/features/driver/driver_home_screen.dart, lib/core/models/error_display_helper.dart]

key-decisions:
  - "Raw excess-cash event strings stay in SocketService passthroughs only; driver screen uses on/offExcessCashRequested passthroughs per key_links, not scattered raw strings"
  - "confirm-driver-cash mapper copy uses tolerant substring matches since live backend copy unverified, mirroring 12-02 select-method approach"
  - "payment:succeeded closes an open cash modal silently before the existing reset-to-online handler runs"

patterns-established:
  - "Socket-driven modal close-out: _excessCashDialogOpen flag + stored dialog context, pop-only-if-open, silent no-toast"

requirements-completed: [STAGE2-04, STAGE2-05, STAGE2-06]

# Metrics
duration: 2min
completed: 2026-09-17
---

# Phase 12 Plan 03: Driver Cash-Confirm Modal Summary

**Driver Collect-Cash modal on excessCashRequested with confirm-driver-cash wiring and inline failure, silently auto-closed by excessCashCancelled or payment:succeeded, plus confirm-driver-cash mapper copy**

## Performance

- **Duration:** 2 min
- **Started:** 2026-09-17T13:47:21Z
- **Completed:** 2026-09-17T13:49:16Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Collect-Cash `AlertDialog` (`barrierDismissible:false`, `StatefulBuilder` matching `_showCancellationReasonDialog`) on `payment:excessCashRequested`: "Collect Cash: £X — Passenger requested to pay £X excess balance in cash." + Confirm Cash Received button with inline spinner
- Requested handler normalizes payload, dedupe-guards `payment_excess_cash_requested`, rideId-matches against `_currentRideId` (`rideId/bookingId/_id/id`), amount via `excessAmount ?? amount`; opens once per event, never stacks
- Confirm tap calls `confirmDriverCash(rideId)` (driver token by device login): success pops via dialog context + `CustomSnackbar` "Cash payment confirmed! Ride fully completed."; failure renders inline `sheetError` via `RideErrorMapper`, modal stays open
- Cancelled handler dedupe-guards `payment_excess_cash_cancelled`, pops only if `_excessCashDialogOpen`, silent with no toast; `payment:succeeded` for the same ride also drops an open modal before the existing reset-to-online flow
- `RideErrorMapper` gains 3 confirm-driver-cash cases (no-cash-request 400, not-authorized 401/403, already-confirmed 409 info) appended after the 12-02 select-method entries — existing entries untouched
- Off-symmetry in both `dispose` and the reconnect re-setup block via `offExcessCashRequested/offExcessCashCancelled` passthroughs

## Task Commits

Each task was committed atomically:

1. **Task 1: Cash-request modal + confirm-driver-cash wiring** - `06f4f8c` (feat)
2. **Task 2: Auto-close on cancelled/succeeded + mapper copy** - `55ff1e3` (feat)

**Plan metadata:** pending final docs commit

## Files Created/Modified

- `lib/features/driver/driver_home_screen.dart` - `_excessCashDialogOpen` flag + stored dialog context, requested/cancelled listeners, `_showExcessCashDialog` + `_closeExcessCashDialogIfOpen`, succeeded auto-close, off-symmetry (modified, +202/-0 lines across both commits)
- `lib/core/models/error_display_helper.dart` - confirm-driver-cash no-request/unauthorized/already-confirmed mapper cases appended (modified)

## Decisions Made

- Raw event strings (`payment:excessCashRequested` / `payment:excessCashCancelled`) live only in `SocketService` passthroughs; the driver screen references `onExcessCashRequested/onExcessCashCancelled` per the plan's key_links — so the plan's Task-2 `rg` for raw strings in the driver screen intentionally matches nothing, while `rg excessCash` hits socket service + driver screen (+ the 12-02 settlement sheet)
- confirm-driver-cash mapper copy uses tolerant substring matches (`no cash request` / `cash not requested`, `only driver can confirm` / `not assigned`, `already confirmed`) since live backend copy is unverified — same approach as 12-02 select-method entries
- `payment:succeeded` closes the cash modal silently first, then the pre-existing "Payment completed! Ride finalized." toast + reset-to-online runs unchanged — no double toast, no behavior change to the non-settlement path

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- `flutter analyze` on the driver screen reports only pre-existing info/warning categories (`withOpacity` deprecations, `use_build_context_synchronously` infos already pervasive in the file — baseline 11, now 12 with the same lint on the new Confirm-tap snackbar, matching the existing cancel-dialog pattern — plus one pre-existing `unused_element` warning). Verified via `git stash` baseline comparison; out of scope, not fixed. `error_display_helper.dart` analyzes with zero issues.
- `rg 'payment_selected|select-payment'` in the driver screen returns zero matches — no old-event subscriptions introduced.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 12 complete (12-01 transport, 12-02 rider sheet, 12-03 driver modal) — ready for Phase 13 (account suspension safeguard on startup outstanding balance)
- Live-device verification still open: cash request → Collect-Cash modal → driver confirm → rider `payment:succeeded` pop, and rider switch-to-online → driver modal silent auto-close

---
*Phase: 12-excess-balance-stage-2-settlement-rider-cash-online-plus-driver-cash-confirm*
*Completed: 2026-09-17*

## Self-Check: PASSED
