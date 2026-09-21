---
phase: 16-revert-ride-payments
plan: "01"
subsystem: payments
tags: [revert, booking-routing, payment_link, webview-deferral, contract-tests]

# Dependency graph
requires:
  - phase: 15-outstanding-balance-silent-booking-fare-transparency
    provides: [fare transparency banners, silent-booking backstop on both booking screens]
provides:
  - Instant link bookings route to searching with no WebView at booking
  - Scheduled upfront WebView routing preserved byte-identical
  - Contract tests pinning revert §3/§5 201 parse shapes
affects: [16-02 accept-time Pay Now prompt, 16-03 regression sweep]

# Tech tracking
tech-stack:
  added: []
  patterns: [deferred-payment routing (inert payment fields threaded for accept-time use)]

key-files:
  created: [test/revert_booking_contract_test.dart]
  modified: [lib/features/booking/ride_confirmation_screen.dart, lib/features/booking/confirm_booking_screen.dart]

key-decisions:
  - "Deleted (not stubbed) the instant-link WebView branches so no dead payment-at-booking path remains"
  - "Missing-paymentUrl snackbar removed with the branch — absent URL is the expected normal-ride shape per spec §3, not an error"
  - "paymentUrl/clientSecret threaded as inert fields to RideAssignedScreen/success dialog for 16-02 accept-time consumption"

patterns-established:
  - "Deferred payment routing: instant rides carry payment fields inert; only scheduled branch opens WebView at booking"

requirements-completed: [RVT-01, RVT-06]

# Metrics
duration: 3min
completed: 2026-09-21
---

# Phase 16 Plan 01: Booking Deferral Summary

**Instant payment_link bookings deferred to post-accept: both booking screens route link + cash to searching with no WebView, scheduled upfront WebView intact, 8 contract tests pin the parse shapes**

## Performance

- **Duration:** 3 min
- **Started:** 2026-09-21T08:57:03Z
- **Completed:** 2026-09-21T09:00:04Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- New `test/revert_booking_contract_test.dart`: 8 tests pinning normal-ride 201 (no paymentUrl) vs scheduled 201 (awaiting_deposit + paymentUrl/sessionId) shapes and PaymentResult passthrough
- `ride_confirmation_screen.dart`: instant-link WebView branch deleted; link + cash fall through to `RideAssignedScreen` with `driver: null`, inert payment fields passed through
- `confirm_booking_screen.dart`: instant link goes straight to success dialog like cash; scheduled `_handleScheduleRide` WebView + switch helpers untouched

## Task Commits

Each task was committed atomically:

1. **Task 1: Contract tests for booking-create parse shape** - `8ad56bb` (test)
2. **Task 2: Defer instant payment_link on RideConfirmationScreen** - `b342097` (feat)
3. **Task 3: Defer instant payment_link on legacy ConfirmBookingScreen** - `4db2c89` (feat)

**Plan metadata:** (docs commit follows state/roadmap updates)

## Files Created/Modified
- `test/revert_booking_contract_test.dart` - Revert §3/§5 201-shape contract + routing-rule + passthrough tests
- `lib/features/booking/ride_confirmation_screen.dart` - Instant WebView branch removed (-64/+8), inert paymentUrl passthrough added
- `lib/features/booking/confirm_booking_screen.dart` - Instant WebView branch removed (-52/+6), direct success dialog

## Decisions Made
- Deleted the instant-link WebView branches outright rather than stubbing, so `rg PaymentWebViewScreen` on the instant path finds only the scheduled helpers
- Removed the "Payment link missing" snackbar with the branch: per spec §3 the normal-ride 201 carries no paymentUrl, so absence is expected, not an error
- Threaded `paymentUrl`/`clientSecret` as inert fields into the searching navigation for 16-02 (accept-time prompt) instead of dropping them

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- None. `flutter analyze` on both screens shows only pre-existing info/warning lints (deprecated `withOpacity`, unused `socket_service` import); zero errors. All 18 tests (revert + upfront) green; fare-balance + outstanding suites green (25 total with those files).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Ready for 16-02 (accept-time Pay Now prompt, authorized close-out, rehydrate, switcher restore) — inert `paymentUrl`/`paymentMethod` fields are in place on both instant paths
- Manual verification still open for 16-03 human pass: book instant link ride → searching, no WebView; book scheduled link ride → WebView opens

---
*Phase: 16-revert-ride-payments*
*Completed: 2026-09-21*

## Self-Check: PASSED
- All key files found on disk; all 3 task commits verified in git log.
