---
phase: 13-account-suspension-safeguard-on-startup-outstanding-balance
plan: 01
subsystem: payments
tags: [outstanding-balance, account-suspension, contract-tests, flutter]

# Dependency graph
requires:
  - phase: 12-excess-balance-stage-2-settlement-rider-cash-online-plus-driver-cash-confirm
    provides: [OutstandingBalance model, 403 balanceBlocked backstop, payment:succeeded flow]
provides:
  - OutstandingBalance suspension flags (accountSuspended/allowCash) + isSuspended getter + tolerant _flag parser
  - Suspension contract tests pinning INTEGRATION-GUIDE.md §1 JSON
  - Verified 403 booking-block backstop file:line evidence (no behavior change)
affects: [13-02 home startup gate, booking screens, payment service]

# Tech tracking
tech-stack:
  added: []
  patterns: [tolerant flag parsing mirroring _num precedent, conjunction gate accountSuspended && !allowCash]

key-files:
  created: [test/suspension_contract_test.dart]
  modified: [lib/core/models/outstanding_balance.dart]

key-decisions:
  - "Conjunction gate isSuspended = accountSuspended && !allowCash (Pitfall 5)"
  - "Fallbacks preserve today: accountSuspended=false, allowCash=true when flags absent"
  - "fromSelectMethodEnvelope and fromForbiddenEnvelope left untouched (live in-car flow + 403 shape)"

patterns-established:
  - "Tolerant _flag parser: bool passthrough, num != 0, case-insensitive true/1/false/0 strings, else fallback"

requirements-completed: [SUSPEND-01, SUSPEND-05]

# Metrics
duration: 1min
completed: 2026-09-18
---

# Phase 13 Plan 01: Suspension-Flag Parsing Foundation Summary

**OutstandingBalance gains tolerant accountSuspended/allowCash parsing with isSuspended conjunction gate, pinned by 6 contract tests on the brief's exact §1 JSON; 403 booking backstop verified intact with zero edits.**

## Performance

- **Duration:** 1 min
- **Started:** 2026-09-18T06:58:19Z
- **Completed:** 2026-09-18T06:59:13Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Extended OutstandingBalance with suspension flags + isSuspended getter + tolerant _flag parser
- Created 6-case suspension contract test file (123 lines) covering exact brief JSON, backward compat, conjunction, string/int tolerance, socket event, succeeded
- Verified SUSPEND-05 403 backstop unchanged with file:line evidence, no booking-screen/payment_service/mapper edits
- Full test suite green (43 tests), touched files analyze clean

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend OutstandingBalance with suspension flags** - `ce0dd86` (feat)
2. **Task 2: Contract tests for flags + 403 backstop verification** - `2a9d7ba` (test)

**Plan metadata:** `a788bb8` (docs: complete plan)

## Files Created/Modified
- `lib/core/models/outstanding_balance.dart` - Added accountSuspended/allowCash fields + isSuspended getter + _flag helper, wired through fromBalanceEnvelope and fromBalanceDueEvent (succeeded branches default to not-suspended)
- `test/suspension_contract_test.dart` - 6 suspension-flag contract tests mirroring outstanding_balance_test.dart style

## Decisions Made
- Conjunction gate `isSuspended = accountSuspended && !allowCash`: suspended flag alone with cash allowed (in-car) is NOT suspended — matches brief §1 + Pitfall 5
- Safe defaults (absent flags → not suspended) so today's startup balance behavior is preserved until 13-02 consumes the getter
- Socket/FCM `fromBalanceDueEvent` parses the same flags for consistency; select-method and 403 parsers deliberately untouched

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Plan verification string `rg 'isSuspended'` shows only the getter (line 31); the two parse sites use `_flag(m['accountSuspended']...)` / `_flag(event['accountSuspended']...)` (lines 82-83, 189-190), confirmed via `rg 'accountSuspended|allowCash|_flag'`. Not a code issue — verification wording imprecision.
- `flutter analyze lib test` reports 389 pre-existing issues in unrelated files (e.g. ride_progress_screen). All 4 touched/verified files (`outstanding_balance.dart`, `suspension_contract_test.dart`, `outstanding_balance_test.dart`, `payment_service.dart`) analyze clean with zero issues.

## 403 Backstop Evidence (SUSPEND-05, no edits)

- `lib/core/services/payment_service.dart:295-314` — 403 with balance-like message/rideId returns `PaymentResult.balanceBlocked` (lines 299-303); balance-like failures on any status also return `balanceBlocked` (309-313)
- `lib/core/services/payment_service.dart:55-71` — `PaymentResult.balanceBlocked` factory sets `data['balanceBlocked']=true`; `isBalanceBlocked` getter reads it
- `lib/features/booking/ride_confirmation_screen.dart:665-670` — `if (result.isBalanceBlocked)` → `_openBalanceBlocked(...)`; helper defined at line 708
- `lib/features/booking/confirm_booking_screen.dart:139-144` — `if (result.isBalanceBlocked)` → `_openBalanceBlocked(...)` (second call site at 246-247); helper defined at line 376
- `lib/core/models/error_display_helper.dart:124-131` — `outstanding balance` → title 'Clear balance to continue', actionLabel 'Pay now'

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Ready for 13-02 (home startup gate): consume `isSuspended` on GET /payments/balance to lock Book/Schedule + show pay-online-only modal, unlock on payment:succeeded / data:null
- No blockers or concerns

---
*Phase: 13-account-suspension-safeguard-on-startup-outstanding-balance*
*Completed: 2026-09-18*

## Self-Check: PASSED
