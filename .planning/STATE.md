# MK Tours - Project State

## Current Position
- **Phase:** 10-driver-request-stack — Complete (2/2 plans, 2026-09-12)
- **Next:** Phase transition (phase 10 done)

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
- 07-02: Execution merge + verification — scheduled rides merge into live flow, full lifecycle verified (commits shared with 07-01)
- 08-01: Scheduled screen-flow guards — scheduled booking to /home, scheduled accept toast-only, upcoming silent refresh (`9a4c4e5`, `89e1549`, `2b00f93`)
- 08-03: Day-of entry + accept landing — Go to Pickup into unified execution, accept lands on Confirmed (`45f068c`, `56ec34e`)
- 08-02: Day-of transitions + cancel reassignment — global arrival routing, started/completed verified, cancel banner + refresh (`cbcaa37`, `d1e8bd8`)
- 09-01: PromoStatus foundation — 4-state typed model, ApiService docs, 8 unit tests (`de0080e`, `f4fff4e`)
- 09-02: Pending UI — status screen locked hero + RIDE BOOKED badge, home locked banner, no fare gates (`9f3d11b`, `4f46f90`)
- 10-01: Driver request queue + eviction — 5-deep stack, per-ride dedupe, cancel/expire/unavailable single-card removal (`3977389`, `5dd66df`)
- 10-02: Stacked request UX — 1-of-N pill with chevrons/dots, background rows, newest-at-0, per-card decline, stack-clearing accept (`1ee228c`, `e3ccf64`)

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
- [07-02] Scheduled rides follow identical arrive/start/complete flow as instant rides from pickup time onward
- [08-01] Scheduled booking success routes to /home with clean back-stack, not into ScheduledRidesScreen directly
- [08-01] isScheduled checked before state-clear and ActiveRideStorage save so scheduled accepts never corrupt cold-start restore
- [08-01] Silent refresh (no loader flash, no toast) on Upcoming list; Home owns the toast
- [08-03] Go to Pickup adopts via pop-with-result into home pickup state, not a new route (home owns lifecycle)
- [08-03] Pickup window 60 min including overdue; button never hidden, disabled with countdown hint
- [08-03] Accept auto-switches to Confirmed tab so driver lands on My Scheduled
- [08-02] Arrival pushes RideAssignedScreen with isScheduled:true (same destination _handleDriverArrival mutates in place)
- [08-02] Scheduled started/completed verified with no code change; instant payment logic untouched
- [08-02] Upcoming cancel refresh uses silent refresh per 08-01 pattern, not full loader
- [09-01] PromoStatus.fromMap parses data map only; 401/500 envelopes stay plain failure maps, no throw
- [09-01] getPromoStatus logic untouched (docs only); model consumed by UI in 09-02
- [09-02] Status screen parses via PromoStatus.fromMap as source of truth; _isLoading/_error flow untouched
- [09-02] Pending home banner branch before eligible check; _fetchPromoStatus unchanged, no fare/booking gates
- [10-01] Decline drops visible card and reveals next stacked request; only last decline returns to online
- [10-01] Queue cleared on accept and offline toggle so stale requests never resurface
- [10-02] Newest request inserts at 0 and takes the visible card; prior card becomes background row
- [10-02] Decline never stops audio while stack non-empty; stop only on drain
- [10-02] Card switch clears accept error since banner is bound to visible card

## Blockers
- None

## Session
- Last session: Completed 10-02-PLAN.md (2026-09-12, 2 feat commits, SUMMARY at phases/10-driver-request-stack/10-02-SUMMARY.md). Phase 10 complete.
- Previous: Completed 10-01-PLAN.md (2026-09-12, 2 feat commits, SUMMARY at phases/10-driver-request-stack/10-01-SUMMARY.md). Next: 10-02.
- Previous: Completed 09-02-PLAN.md (2026-09-12, 2 feat commits, SUMMARY at phases/09-promo-pending-state/09-02-SUMMARY.md). Phase 09 complete.
- Previous: Completed 09-01-PLAN.md (2026-09-12, test + feat commits, SUMMARY at phases/09-promo-pending-state/09-01-SUMMARY.md). Next: 09-02.
- Previous: Completed 08-03-PLAN.md (2026-09-11, 2 commits, SUMMARY at phases/08-scheduled-screen-flow/08-03-SUMMARY.md). Next: 08-02.
- Previous: Completed 08-01-PLAN.md (2026-09-11, 3 feat commits, SUMMARY at phases/08-scheduled-screen-flow/08-01-SUMMARY.md). Next: 08-02.
- Previous: Completed 07-02-PLAN.md (2026-09-10, verification approved, SUMMARY at phases/07-driver-prebook/07-02-SUMMARY.md). Phase 07 complete.
- Previous: Completed 07-01-PLAN.md (2026-09-10, 2 feat commits, SUMMARY at phases/07-driver-prebook/07-01-SUMMARY.md).
- Previous: Completed 06-02-PLAN.md (2026-09-10, 2 feat commits, SUMMARY at phases/06-rider-prebook/06-02-SUMMARY.md).
