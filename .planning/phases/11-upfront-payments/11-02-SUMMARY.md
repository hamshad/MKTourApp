---
phase: 11-upfront-payments
plan: "02"
subsystem: payments
tags: [flutter, stripe-checkout, webview, upfront-payment, booking]

# Dependency graph
requires:
  - phase: 11-01
    provides: [mandatory paymentMethod in bookRideWithPayment, instant 201 paymentUrl parsing, 400/403 actionable PaymentResults]
provides:
  - Mandatory Online-vs-Cash toggle on both booking screens
  - Immediate paymentUrl WebView routing for payment_link instant bookings
  - Direct-to-matching navigation for cash instant bookings
  - Actionable missing-method/missing-URL UI that never dead-ends
affects: [11-03, ride-assigned-display, receipt]

# Tech tracking
tech-stack:
  added: []
  patterns: [upfront link-vs-cash branch at booking time, WebView-success-gated matching navigation]

key-files:
  created: []
  modified:
    - lib/features/booking/ride_confirmation_screen.dart
    - lib/features/booking/confirm_booking_screen.dart
    - lib/features/ride/ride_assigned_screen.dart

key-decisions:
  - "RideAssignedScreen gains optional paymentMethod/paymentUrl fields so 11-03 can display them without further constructor churn"
  - "Instant WebView cancel returns to booking screen with orange snackbar instead of navigating, so no unpaid ride enters driver-matching"
  - "Legacy confirm keeps dialog-based success flow; only routing branches, no RideAssigned push added there"

patterns-established:
  - "Link-vs-cash branch: payment_link + non-empty paymentUrl opens PaymentWebViewScreen immediately; cash navigates directly with no WebView"
  - "Missing-URL and 400 missing-method stay on booking screen with orange snackbar copy"

requirements-completed: [UPFRONT-01, UPFRONT-02, UPFRONT-03]

# Metrics
duration: 12min
completed: 2026-09-17
---

# Phase 11 Plan 02: Mandatory Upfront Method Toggle + Instant Routing Summary

**Mandatory Online (Card via Link) vs Cash toggle on both booking screens with immediate paymentUrl WebView for link and direct driver-matching for cash**

## Performance

- **Duration:** 12 min
- **Started:** 2026-09-17T12:00:00Z
- **Completed:** 2026-09-17T12:12:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- RideConfirmationScreen shows mandatory payment selector above Confirm; `_confirmRide` uses payNow + picked method; `_processBooking` requires paymentMethod
- Instant link booking pushes PaymentWebViewScreen immediately and enters matching only on WebView success; missing URL stays with orange snackbar
- Cash instant booking navigates directly to RideAssignedScreen with no WebView
- Legacy ConfirmBookingScreen mirrors the same contract with file-local toggle while keeping its dialog-based success flow
- Schedule sheet verified cash|payment_link only with cash default; date/time and lead-time logic untouched

## Task Commits

Each task was committed atomically:

1. **Task 1: Mandatory method toggle + immediate routing on RideConfirmationScreen** - `a1def91` (feat)
2. **Task 2: Same upfront contract on legacy ConfirmBookingScreen + schedule sheet check** - `238037e` (feat)

**Plan metadata:** `7b99063` (docs: complete plan)

## Files Created/Modified

- `lib/features/booking/ride_confirmation_screen.dart` - Payment selector UI, required paymentMethod, instant link/cash branching, missing-method snackbar
- `lib/features/booking/confirm_booking_screen.dart` - File-local method toggle, explicit paymentMethod, WebView-first link flow, missing-method snackbar
- `lib/features/ride/ride_assigned_screen.dart` - Optional paymentMethod/paymentUrl constructor fields for 11-03 display

## Decisions Made

- RideAssignedScreen had no paymentMethod/paymentUrl/extraRideData constructor params, so two optional additive fields were added (no behavior change) to satisfy the plan's pass-through requirement for 11-03.
- Instant WebView cancel (success != true) stays on the booking screen with an orange "Payment cancelled" snackbar; unpaid rides never enter driver-matching.
- `_paymentTiming` kept and synced from the toggle in ConfirmBookingScreen so existing state stays live; the required paymentMethod is the source of truth for the payload.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added missing paymentMethod/paymentUrl pass-through params on RideAssignedScreen**
- **Found during:** Task 1 (instant link branching)
- **Issue:** Plan required passing paymentMethod + paymentUrl in constructor args/extraRideData, but RideAssignedScreen exposed neither
- **Fix:** Added two optional nullable fields (`paymentMethod`, `paymentUrl`) with constructor params; wired both link-success and cash navigations to pass them
- **Files modified:** lib/features/ride/ride_assigned_screen.dart, lib/features/booking/ride_confirmation_screen.dart
- **Verification:** flutter analyze clean (no errors); both push sites compile
- **Committed in:** a1def91 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Minimal additive change required to meet the plan's own pass-through requirement. No scope creep.

## Issues Encountered

None - scheduled paths (`_showScheduleSheet`, `_handleScheduledPayment`, `_switchScheduledPayment`) left logically identical; only paymentMethod pass-through retained.

## Verification

- `flutter analyze` on all three files: no errors, no warnings (23 pre-existing infos only: withOpacity deprecations, intl depend_on_referenced_packages)
- `rg "pay_later|payLater" lib/features/booking/` shows only enum defaults, toggle mapping, and legacy timing labels — no booking call without paymentMethod
- Schedule sheet confirmed: only `cash` + `payment_link` options, default `cash`, `onSchedule` always emits one of the two slugs, no `stripe` third option

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Upfront booking contract complete on both booking screens; ready for 11-03 (RideAssigned receipt/display of method + link state)
- Manual QA still needed: instant link opens WebView before driver search; instant cash skips WebView; 403 still opens balance screen

---
*Phase: 11-upfront-payments*
*Completed: 2026-09-17*

## Self-Check: PASSED
