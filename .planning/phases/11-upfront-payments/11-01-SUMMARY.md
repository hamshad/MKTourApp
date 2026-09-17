---
phase: 11-upfront-payments
plan: "01"
subsystem: payments
tags: [upfront-payment, payment-link, cash, stripe-webview, contract-tests, flutter]

# Dependency graph
requires:
  - phase: 10-driver-request-stack
    provides: [stable booking and driver flows that payment contract builds on]
provides:
  - Mandatory paymentMethod (cash | payment_link) on every booking POST
  - Instant-ride 201 parsing for paymentUrl/sessionId/paymentStatus
  - 400 missing-paymentMethod and 403 balance-block actionable results
  - Balance-envelope tolerance (flat + nested paymentUrl, both amount keys)
  - Contract tests documenting 201/400/403 shapes
affects: [11-02, 11-03, rider-booking-ui, scheduled-prebook, ride-assigned]

# Tech tracking
tech-stack:
  added: []
  patterns: [parsing-only contract tests for http+context code, normalized enum-like string params with ArgumentError guard]

key-files:
  created: [test/upfront_payment_contract_test.dart]
  modified: [lib/core/services/payment_service.dart, lib/core/models/outstanding_balance.dart, lib/core/api_service.dart, lib/core/constants/api_constants.dart, lib/features/booking/confirm_booking_screen.dart, lib/features/booking/ride_confirmation_screen.dart]

key-decisions:
  - "Legacy instant caller maps payNow/payLater to payment_link/cash so required param compiles without behavior change"
  - "Kept prior committed unified instant+scheduled 201 parser instead of divergent re-implementation"
  - "PaymentResult.failure extended with optional data/message so 400 failure carries missingPaymentMethod flag"

patterns-established:
  - "Booking callers always pass explicit paymentMethod cash|payment_link; never rely on backend default"
  - "Balance parsing tolerates flat and data.payment nested paymentUrl plus excessAmount/outstandingBalance/amount keys"

requirements-completed: [UPFRONT-02, UPFRONT-05]

# Metrics
duration: 30min
completed: 2026-09-17
---

# Phase 11 Plan 01: Upfront Payment Contract Summary

**Mandatory cash|payment_link on every booking POST with instant-ride paymentUrl parsing, 400/403 actionable results, and tolerant balance-envelope parsing covered by contract tests**

## Performance

- **Duration:** 30 min
- **Started:** 2026-09-17T10:14:59Z
- **Completed:** 2026-09-17T10:45:00Z
- **Tasks:** 3
- **Files modified:** 7 (4 existing plan files + 2 caller fixes + 1 new test)

## Accomplishments

- `bookRideWithPayment` requires `paymentMethod`, normalizes case/whitespace, throws `ArgumentError` before any network call on other values, and always sends it for instant and scheduled rides; `paymentTiming` key removed from body (enum param retained for caller compat)
- Instant 201 responses parse `paymentUrl`/`sessionId`/`paymentMethod`/`paymentStatus` from `data.payment` / `data.ride` / `data` — payment_link yields WebView URL, cash yields `pending_collection` with no URL
- 400 `paymentMethod is required` returns `PaymentResult.failure` with `data: {missingPaymentMethod: true}` so UI shows method-selector error; existing 403 balanceBlocked detection untouched
- `OutstandingBalance.fromBalanceEnvelope` accepts nested `data.payment.paymentUrl` and defaults empty status to `balance_due`; `fromForbiddenEnvelope` accepts `excessAmount` fallback and copies `paymentUrl`
- `selectPaymentMethod()` marked DEPRECATED (kept for scheduled-switch fallback; removal in 11-03); `getGlobalPaymentBalance` doc updated to new `{rideId, excessAmount, paymentUrl, status: balance_due}` shape
- New `test/upfront_payment_contract_test.dart` (10 tests) passes alongside existing `outstanding_balance_test.dart` (9 tests): 19/19 green

## Task Commits

Each task was committed atomically:

1. **Task 1: Mandatory paymentMethod in PaymentService booking** - `1404868` (feat)
2. **Task 2: Balance envelope tolerance + deprecate select-payment endpoint** - `47f08ee` (feat)
3. **Task 3: Contract tests for upfront payment shapes** - `add0f8c` (test)

Caller compat fix (Rule 3, supports Task 1) - `a8994d5` (fix)

**Plan metadata:** _pending final docs commit_ (docs: complete plan)

## Files Created/Modified

- `lib/core/services/payment_service.dart` - Required paymentMethod, unified 201 parser, 400 branch, extended failure factory
- `lib/core/models/outstanding_balance.dart` - Nested paymentUrl + amount-key tolerance in both parsers
- `lib/core/api_service.dart` - `getGlobalPaymentBalance` doc describes new envelope shape (no logic change)
- `lib/core/constants/api_constants.dart` - `selectPaymentMethod()` DEPRECATED comment, method kept
- `lib/features/booking/confirm_booking_screen.dart` - Legacy instant call maps payNow/payLater to payment_link/cash
- `lib/features/booking/ride_confirmation_screen.dart` - Forwards selected method, defaults to cash
- `test/upfront_payment_contract_test.dart` - 10 parsing/contract tests (new)

## Decisions Made

- Legacy instant caller maps `payNow → payment_link`, `payLater → cash` so the new required param compiles with zero behavior change for existing UI paths.
- Kept the already-committed unified instant+scheduled 201 parser (HEAD) rather than a divergent re-implementation drafted mid-execution; restored HEAD for the 4 core files.
- `PaymentResult.failure` gained optional `message`/`data` so the 400 branch carries the `missingPaymentMethod` flag without touching the 403 `balanceBlocked` factory.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Booking callers omitted required paymentMethod**
- **Found during:** Task 1 (Mandatory paymentMethod in PaymentService booking)
- **Issue:** Making `paymentMethod` required broke two call sites: `confirm_booking_screen.dart` instant path passed no method, `ride_confirmation_screen.dart` passed nullable `String?`
- **Fix:** Legacy instant path maps `_paymentTiming` to `payment_link`/`cash`; ride_confirmation forwards `paymentMethod ?? _selectedPaymentMethod` (defaults to cash)
- **Files modified:** lib/features/booking/confirm_booking_screen.dart, lib/features/booking/ride_confirmation_screen.dart
- **Verification:** `flutter analyze` clean on both files (only pre-existing infos/warnings); full test suite green
- **Committed in:** a8994d5 (fix)

**2. [Rule 1 - Bug] Prior-run Task 1/2 commits already in HEAD diverged from fresh re-implementation**
- **Found during:** Task 1 verification (git log showed 1404868/47f08ee already committed)
- **Issue:** Fresh edits duplicated committed work and reintroduced Stripe-sheet-at-booking logic the committed version had removed
- **Fix:** Restored the 4 core files to HEAD (committed implementation is plan-compliant and cleaner), kept only caller fixes + new tests on top
- **Files modified:** lib/core/services/payment_service.dart, lib/core/api_service.dart, lib/core/constants/api_constants.dart, lib/core/models/outstanding_balance.dart (restored)
- **Verification:** Re-ran `flutter test` (19/19) and `flutter analyze` (no issues on core files) after restore
- **Committed in:** n/a (restore, no new commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug/correctness)
**Impact on plan:** Both necessary for compilability and a single coherent implementation. No scope creep; no Stripe Payment Sheet logic added.

## Issues Encountered

- `flutter analyze` on booking screens reports 2 pre-existing warnings (`unused_import` socket_service, `unused_field` _paymentTiming) — verified present on HEAD with changes stashed; left untouched as out of scope.
- `rg paymentTiming.*pay_now|pay_later` still matches a doc comment and a debugPrint string in payment_service — no `'paymentTiming'` body key is sent (verified via dedicated rg); remaining `paymentTiming` refs in vehicle model/home cache/assigned screen are pre-existing and out of scope.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- UI plans (11-02, 11-03) inherit the mandatory paymentMethod contract; every booking POST now carries cash|payment_link
- `selectPaymentMethod()` deprecation noted; actual call-site removal scheduled for plan 11-03 (ride_assigned only)
- No blockers

---
*Phase: 11-upfront-payments*
*Completed: 2026-09-17*

## Self-Check: PASSED
- Test file (151 lines), SUMMARY, and all 4 commits (1404868, 47f08ee, a8994d5, add0f8c) verified present
