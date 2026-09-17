---
phase: 12-excess-balance-stage-2-settlement-rider-cash-online-plus-driver-cash-confirm
plan: 02
subsystem: payments
tags: [excess-balance, stage2-settlement, settlement-sheet, cash, payment-link, webview]

# Dependency graph
requires:
  - phase: 12-01-settlement-transport
    provides: selectBalanceMethod + fromSelectMethodEnvelope + socket passthroughs
provides:
  - ExcessSettlementSheet (Cash/Online + waiting + WebView + succeeded close-out)
  - Receipt-hosted live settlement (pendingBalance handoff + post-completion balanceDue)
  - selectBalanceMethod 400/403/409 mapper copy
affects: [12-03-driver-cash-modal, 13-suspension-safeguard]

# Tech tracking
tech-stack:
  added: []
  patterns: [modal-bottom-sheet settlement over receipt, pop-only-when-cleared succeeded close-out, targeted mapper append]

key-files:
  created: [lib/features/ride/excess_settlement_sheet.dart]
  modified: [lib/features/ride/ride_complete_screen.dart, lib/core/models/error_display_helper.dart]

key-decisions:
  - "Settlement presented as modal bottom sheet (not push) so dismiss reveals receipt + rating intact"
  - "Post-completion payment:balanceDue listener added on receipt with dedupe + rideId guards"
  - "select-method error strings are tolerant substring matches since live backend copy unverified"

patterns-established:
  - "Settlement close-out: rideId-match + RideEventDedupe guard + authoritative GET, pop only when cleared"

requirements-completed: [STAGE2-01, STAGE2-02, STAGE2-03]

# Metrics
duration: 12min
completed: 2026-09-17
---

# Phase 12 Plan 02: Rider Live-Settlement Sheet Summary

**Rider in-car excess settlement: ExcessSettlementSheet with Cash/Online choice, driver-confirm waiting state with Switch-to-Online escape, payment_link WebView, and succeeded close-out that pops only after authoritative re-fetch — hosted on the receipt, startup screen untouched**

## Performance

- **Duration:** 12 min
- **Started:** 2026-09-17T13:43:17Z
- **Completed:** 2026-09-17T13:55:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- New `ExcessSettlementSheet({rideId, balance})` (324 lines): amount headline, Pay Cash to Driver + Pay Online buttons, cash waiting state ("Waiting for driver to confirm cash receipt…") with Switch-to-Online + back-chevron escapes, online WebView via `fromSelectMethodEnvelope` paymentUrl parsing, all errors via `ErrorDisplayHelper.showRideError`
- Receipt hosts sheet as modal bottom sheet on `pendingBalance` handoff AND post-completion `payment:balanceDue` (dedupe + rideId guards); dismiss reveals receipt + rating intact
- `payment:succeeded` handler copied from `OutstandingBalanceScreen` exactly: rideId-match → dedupe-guarded → authoritative `getPaymentBalance` → pop only on `status==succeeded` or 404-after-event, else setState fresh amount and stay open
- `RideErrorMapper` gains 3 select-method cases: invalid-method 400, already-settled info, 409 in-progress — targeted append, no unrelated entries touched
- Startup `OutstandingBalanceScreen` untouched: no cash button, online-only preserved

## Task Commits

Each task was committed atomically:

1. **Task 1: ExcessSettlementSheet widget with method selection + waiting + WebView** - `874bae9` (feat)
2. **Task 2: Host on receipt + succeeded close-out + mapper copy** - `729a7fa` (feat)

**Plan metadata:** pending final docs commit

## Files Created/Modified

- `lib/features/ride/excess_settlement_sheet.dart` - Cash/Online buttons + waiting state + WebView + succeeded close-out (created, 324 lines)
- `lib/features/ride/ride_complete_screen.dart` - Modal-bottom-sheet settlement hosting, post-completion balanceDue listener, disposed listener (modified)
- `lib/core/models/error_display_helper.dart` - selectBalanceMethod 400/403/409 mapper cases (modified)

## Decisions Made

- Settlement presented as `showModalBottomSheet` (not `Navigator.push`) so the receipt + rating stay mounted underneath — dismissing the sheet reveals them intact per research open-question-5 decision
- Added a `payment:balanceDue` listener on `RideCompleteScreen` (plan's "post-completion path"): excess arriving after the receipt is already shown opens the sheet on top, with `RideEventDedupe` + rideId guards so FCM duplicates never double-open
- select-method error strings are tolerant substring matches (`paymentmethod must be`, `balance already paid`/`no outstanding balance`, `already requested`/`settlement in progress`) since live backend copy is unverified; 12-03 appends confirm-driver-cash cases after this plan

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- `flutter analyze` on touched files reports 2 pre-existing `withOpacity` infos on untouched receipt lines (verified present on stashed original) — out of scope, not fixed
- `rg 'cash'` on `outstanding_balance_screen.dart` matches 5 pre-existing references (doc comments, `payment:cashCollected` live-update listener, one snackbar string) — none is a cash button; startup screen has only "Pay via Payment Link" + "Check again", online-only preserved
- `rg 'select-payment'` matches only the deprecated endpoint definition + a doc comment — zero live arrival-flow calls

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Ready for 12-03 (driver cash modal: Collect-Cash request + confirm wiring + cancelled auto-close)
- Live-envelope pinning still open: first device test should exercise cash → waiting → driver confirm → succeeded pop, and online → WebView → succeeded pop

---
*Phase: 12-excess-balance-stage-2-settlement-rider-cash-online-plus-driver-cash-confirm*
*Completed: 2026-09-17*

## Self-Check: PASSED
