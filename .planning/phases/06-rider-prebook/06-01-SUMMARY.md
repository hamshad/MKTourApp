---
phase: 06-rider-prebook
plan: 01
subsystem: booking
tags: [scheduled-rides, prebook, payment-routing, schedule-sheet, stripe, payment-link]

requires:
  - phase: 05-prebook-foundation
    provides: ScheduledRide model, ScheduledPayment, AddressLocation, error mapper, storage keys
provides:
  - SchedulePayload with ISO8601 pickupTime, paymentMethod, note, stops
  - 2h-30d pickup window validation in schedule sheet
  - Scheduled ride payment routing (paymentUrl → WebView, clientSecret → Stripe)
  - Confirm booking screen with Schedule button and payment flow
affects: [06-02, 07-driver-prebook]

tech-stack:
  added: []
  patterns: [schedule-payload-struct, iso8601-utc-pickup, payment-url-routing]

key-files:
  created: []
  modified:
    - lib/features/booking/widgets/schedule_ride_sheet.dart
    - lib/features/booking/confirm_booking_screen.dart

key-decisions:
  - "SchedulePayload struct replaces raw DateTime+notes callback for type safety"
  - "ISO8601 UTC pickupTime built from local DateTime in sheet, not at API call site"
  - "Payment routing reuses PaymentService.bookRideWithPayment with scheduledAt param"
  - "Schedule button placed alongside Confirm Booking as outlined secondary action"

patterns-established:
  - "SchedulePayload: structured return from schedule sheets (pickupTime, paymentMethod, note, stops)"
  - "Payment routing: paymentUrl → WebView, clientSecret → Stripe sheet, cancel → back to selection"

requirements-completed: [PREBOOK-01, PREBOOK-04, PREBOOK-05]

duration: 3min
completed: 2026-09-10
---

# Phase 06 Plan 01: Schedule Creation + Payment Routing Summary

**ScheduleRideSheet with 2h-30d constraint returning ISO8601 SchedulePayload, plus payment routing for Stripe clientSecret and paymentLink URL in confirm booking screen**

## Performance

- **Duration:** 3 min
- **Started:** 2026-09-10T11:36:46Z
- **Completed:** 2026-09-10T11:40:15Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- SchedulePayload class with typed fields (pickupTime ISO8601, paymentMethod, note, stops)
- 2h minimum pickup constraint enforced in sheet UI (was 30min) with 30d maximum
- UTC ISO8601 pickupTime built from selected DateTime at sheet level
- Confirm booking screen wired with Schedule button that opens ScheduleRideSheet
- Payment routing: paymentUrl → PaymentWebViewScreen, clientSecret → Stripe sheet
- Cancel from payment WebView returns to selection without duplicate ride create

## Task Commits

Each task was committed atomically:

1. **Task 1: Schedule sheet + payload** - `ef8920b` (feat)
2. **Task 2: Payment routing** - `76c38fc` (feat)

## Files Created/Modified
- `lib/features/booking/widgets/schedule_ride_sheet.dart` — SchedulePayload class, 2h-30d constraint, ISO8601 UTC pickupTime builder
- `lib/features/booking/confirm_booking_screen.dart` — Schedule button, _handleScheduleRide, payment routing (paymentUrl/clientSecret), deposit payment WebView flow

## Decisions Made
- SchedulePayload struct used instead of raw DateTime+notes for type safety and extensibility (stops, paymentMethod)
- ISO8601 UTC pickupTime built in sheet's onSchedule callback, not deferred to API call site
- Payment routing leverages existing PaymentService.bookRideWithPayment with scheduledAt param — no new API method needed
- Schedule button is outlined (secondary) alongside filled Confirm Booking (primary) to preserve instant-book flow

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Schedule creation flow complete (sheet → payload → API → payment routing)
- Ready for 06-02: Scheduled ride list and status management UI
- Ready for 07-driver-prebook: Driver-side pool and accept flows

---
*Phase: 06-rider-prebook*
*Completed: 2026-09-10*

## Self-Check: PASSED
