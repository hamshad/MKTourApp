# MK Tours - Project State

## Current Position
- **Phase:** 07-driver-prebook — In Progress (0/2 plans)
- **Plan:** 07-01 — Complete (2026-09-10)
- **Next:** 07-02

## Completed Plans
- 02-01: Ride-flow API layer — no-OTP startRide, stopArrive/stopResume, stops-aware fare/create, reason cancel, fixed end-early (`c0c7d26`, `0e95c3b`)
- 02-02: Domain + error infra (parallel agent — see 02-02-SUMMARY.md)
- 03-01: Rider booking → searching → assigned — stops editor + fare cards, overlay states, OTP-free assigned (`bdf0aaa`, `396af2c`)
- 03-02: Rider payment sheet, trip progress with stops/wait, fare receipt + rating (`cb5de4a`, `75b9f77`, `848ab91`)
- 04-01: Driver trip execution — proximity banner arrive, no-OTP start, stops + totals, fare dialog, reasoned sheets (`89234e6`, `a652414`, `d72fcd4`)
- 04-02: Cross-flow polish — live sync + restore, visual sweep, cash/link-only sheet, FCM/socket dedupe, cash-race fix, rider at_stop, backend wait policy (`95fc87d`, `ad064eb`, `6b7b7fc`, `a35a7e6`, `cca97c0`, `d83cac9`, `197c86d`, `1c93f38`)
- 05-01: Scheduled ride endpoints — pool, driver list, user/driver cancel (`d23f16b`)
- 05-02: Models + error mapping + persistence — ScheduledRide, booking-window errors, storage keys (`077d3e1`, `1da279f`)
- 06-01: Schedule creation + payment routing — SchedulePayload, 2h-30d constraint, paymentUrl/clientSecret routing (`ef8920b`, `76c38fc`)
- 06-02: Scheduled list + detail + cancel — model-parsed list, live handoff, cancel with reason, optimistic UI (`e29a33a`, `ab0dd84`)
- 07-01: Driver pool + claim + scheduled rides — pool tiles, claim feedback, scheduled tab with countdown and cancel (`63b4e11`, `4ec7d88`)

## Decisions
- [02-01] OTP dialog UI left in place; only API call path made OTP-free (UI strip-out in 03-01)
- [02-01] Driver-cancel reassigned flag needs no code change (map passthrough)
- [02-01] Fare-estimate change landed in PlacesService, not ApiService (actual call site)
- [03-01] Stops editor wired into live flow (destination search + confirmation), not only legacy confirm screen
- [03-01] ride_assigned_screen OTP stripped (verification covers all lib/features)
- [03-01] Legacy assigned screen exposes optional onSelectPayment hook for 03-02 sheet
- [03-02] Rating success lands on /home (ActivityScreen is a tab there; no /activity route)
- [03-02] Receipt total uses actualFare only with backend wait data, else legacy fare (preserves promo/scheduled math)
- [03-02] Wait-fee rate from WaitFeePolicy, never hardcoded
- [04-01] Auth phone-update OTP kept (ride OTP only in scope); cancel chips offer vehicle_breakdown + vehicle_issue
- [04-01] Reassigned driver-cancel is info outcome, not error; stop wait timer ticks locally, backend fee authoritative
- [04-02] Payment sheet cash + payment_link only; other echoed methods are version-mismatch errors
- [04-02] FCM + socket share one 5s type+rideId dedupe window; first transport wins
- [04-02] Payment attempts carry generation counter; stale link-cancel callbacks never touch newer flows
- [04-02] Cash success syncs authoritative status immediately; backend wait policy wins, constants fallback-only
- [05-01] Cancel methods return decoded backend errors (no throw) — callers display conflict messages
- [05-02] AddressLocation defined in scheduled_ride.dart (no existing location model in codebase)
- [05-02] ScheduledPayment.fromMap tolerates both Map and Map<String, dynamic>
- [06-01] SchedulePayload struct replaces raw DateTime+notes callback for type safety
- [06-01] ISO8601 UTC pickupTime built from local DateTime in sheet, not at API call site
- [06-01] Payment routing reuses PaymentService.bookRideWithPayment with scheduledAt param
- [06-01] Schedule button placed alongside Confirm Booking as outlined secondary action
- [06-02] Cancel uses optimistic UI with "cancelling" intermediate status
- [06-02] Live handoff checks status + pickupTime before redirecting to RideProgressScreen
- [06-02] PaymentService.cancelScheduledRideUser accepts optional reason parameter
- [07-01] Pool tiles show countdown to pickup time inline
- [07-01] Accept errors displayed as inline banner in request panel, not just snackbar

## Blockers
- None

## Session
- Last session: Completed 07-01-PLAN.md (2026-09-10, 2 feat commits, SUMMARY at phases/07-driver-prebook/07-01-SUMMARY.md). Stopped after plan completion.
- Previous: Completed 06-02-PLAN.md (2026-09-10, 2 feat commits, SUMMARY at phases/06-rider-prebook/06-02-SUMMARY.md).
