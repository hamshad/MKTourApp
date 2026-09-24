# MK Tours - Project Roadmap

## Phase Overview

| Phase | Name | Status | Plans | Requirements |
|-------|------|--------|-------|--------------|
| 01 | Crash Reporting | Planned | 1 | CRASH-01..04 |
| 02 | Ride Flow Foundation | Complete | 2 | RIDE-01..04, RIDE-06, RIDE-09..12 |
| 03 | Rider Ride Flow | Complete | 2 | RIDE-01, RIDE-02, RIDE-05, RIDE-07..09 |
| 04 | Driver Flow + Polish | Complete | 2 | RIDE-03, RIDE-04, RIDE-06, RIDE-07..12 |
| 05 | Prebook Flow Foundation | Complete    | 2026-09-10 | PREBOOK-01..04 |
| 06 | 1/2 | Complete    | 2026-09-10 | PREBOOK-01..06 |
| 07 | 2/2 | Complete   | 2026-09-10 | PREBOOK-03..07 |
| 08 | 2/3 | Complete    | 2026-09-11 | SCHED-01..06 |
| 09 | 2/2 | Complete    | 2026-09-12 | PROMO-01..04 |
| 10 | 2/2 | Complete    | 2026-09-12 | STACK-01..04 |
| 11 | 3/3 | Complete   | 2026-09-17 | UPFRONT-01..05 |
| 16 | Revert Ride Payments | In Progress | 2/3 | RVT-01..06 |
| 17 | Backend payment_link only for scheduled | Planned | 0 | — |
| 18 | Enforce payment_method constraints for scheduled | Planned | 0 | PAYCONST-01..06 |
| 19 | 3/3 | Complete   | 2026-09-22 | RES-01..06 |
| 20 | 3/3 | In Progress|  | B2B-01..08 |

---

## Phase 01: Crash Reporting

**Goal:** Custom crash reporting system capturing Flutter/Dart errors with full device/OEM/GPS/network context, sent to backend API with offline queuing.

**Requirements:**
- **CRASH-01**: Capture all uncaught Flutter framework errors
- **CRASH-02**: Capture all uncaught Dart/Platform errors
- **CRASH-03**: Collect comprehensive device, location, network, app, and user context
- **CRASH-04**: Persistent offline queue with exponential backoff retry

**Plans:**
- [ ] `01-crash-reporting-01-PLAN.md` — Core implementation (models, service, wiring)

**Success Criteria:**
- Zero crash data loss (queue survives app restart)
- Backend receives valid JSON per CRASH_REPORT_SCHEMA.json
- < 5% battery/network overhead
- GDPR-compliant (no PII without consent)

---

## Phase 02: Ride Flow Foundation

**Goal:** App speaks new backend ride flow fluently — no-OTP start, stop arrive/resume, wait-fee math surfaced, unified error mapping. No dead OTP code paths remain.

**Requirements:**
- **RIDE-01**: Fare estimate supports optional `stops` JSON param
- **RIDE-02**: Create ride supports `stops[]` with per-stop pending state
- **RIDE-03**: Start ride sends empty body (OTP removed everywhere)
- **RIDE-04**: Arrive-at-pickup surfaces 100m proximity error with distance
- **RIDE-06**: Stop arrive/resume endpoints wired with wait-fee parsing
- **RIDE-09**: Cancel user/driver with reason; driver-cancel reassign flag parsed
- **RIDE-10**: End-early uses `{latitude, longitude, reason}` body per new docs
- **RIDE-11**: Central ride-error mapper (every backend message → friendly copy + action)
- **RIDE-12**: Socket + persistence know new statuses (`at_stop`, reassigned)

**Plans:**
2/2 plans complete
- [x] `02-01-PLAN.md` — API layer: endpoints, no-OTP start, stops, cancel, end-early fix
- [x] `02-02-PLAN.md` — Domain + error infra: at_stop status, stop/wait models, error mapper, socket/persist

**Success Criteria:**
- `flutter analyze` clean on touched files
- Every new endpoint callable from ApiService with typed parsing
- Zero `otp` references in ride-start path
- Each backend error message maps to user-friendly copy

---

## Phase 03: Rider Ride Flow

**Goal:** Rider glides booking → searching → assigned → payment → trip → receipt → rating with zero confusion; every wait/fee state visible, every failure actionable.

**Requirements:**
- **RIDE-01**: Rider sees per-category fare with promo/congestion/stops reflected
- **RIDE-02**: Rider can add intermediate stops at booking; stops shown in trip
- **RIDE-05**: Payment sheet (cash/stripe/payment_link) after driver arrival, errors handled
- **RIDE-07**: Receipt shows base fare + wait fee + actualFare breakdown
- **RIDE-08**: Cash-pending state + rate sheet (1-5 validation) work flawlessly
- **RIDE-09**: User-cancel sheet with reason; driver-cancel shows reassign banner not refund panic

**Plans:**
2/2 plans complete
- [x] `03-01-PLAN.md` — Booking → searching → assigned (stops input, OTP strip-out, reassign banner)
- [x] `03-02-PLAN.md` — Payment → trip → receipt → rating (fare breakdown, cash state, rate validation)

**Success Criteria:**
- Full rider journey completable against live backend without OTP screen
- Stops visible in booking, trip progress, and receipt
- Payment failure returns user to method selection, never dead-ends
- Cancel/reassign states never show stale driver or crash

---

## Phase 04: Driver Flow + Polish

**Goal:** Driver executes arrive → start → stops → complete → cash without guesswork; whole flow (both apps) looks cohesive and survives restarts, with human-verified pass.

**Requirements:**
- **RIDE-03**: Driver start button needs no OTP, works from driver_arrived state
- **RIDE-04**: Arrive shows proximity error with live distance + retry
- **RIDE-06**: Stop arrive/resume buttons + wait-timer chip (5 free min, £0.35/min)
- **RIDE-07**: Driver sees actualFare + wait totals at completion
- **RIDE-08**: Confirm-cash flow with success/error states
- **RIDE-09**: Driver-cancel reason sheet; pre-pickup cancel shows reassign outcome
- **RIDE-10**: End-early sheet with reason + adjusted fare display
- **RIDE-11**: Loading/empty/error states consistent across all ride screens
- **RIDE-12**: Mid-flow restart restores exact state; socket drives at_stop/payment updates live

**Plans:**
2/2 plans complete
- [x] `04-01-PLAN.md` — Driver execution (arrive, no-OTP start, stops, complete, cash, cancel, end-early)
- [x] `04-02-PLAN.md` — Cross-flow polish + live verification (socket, restore, visual QA, human pass)

**Success Criteria:**
- Full driver journey completable with stops + wait fees visible
- Restart mid-trip restores state on both sides
- `flutter analyze` clean; no placeholder/hardcoded fare or wait copy
- Human verifies end-to-end ride on test devices

---

## Phase 05: Prebook Flow Foundation

**Goal:** Scheduled ride API layer — driver pool, scheduled list, cancel endpoints for both roles.

**Requirements:**
- **PREBOOK-01**: User can schedule rides with pickup time
- **PREBOOK-02**: Driver pool shows open scheduled rides
- **PREBOOK-03**: Cancel scheduled ride (user and driver) with reason
- **PREBOOK-04**: Accept scheduled ride with schedule-conflict error paths

**Plans:**
2/2 plans complete
- [x] `05-01-PLAN.md` — Scheduled ride endpoints (pool, driver list, user/driver cancel)
- [ ] `05-02-PLAN.md` — (next plan)

**Success Criteria:**
- `flutter analyze` clean on api_service and constants
- All scheduled endpoints callable with typed return maps
- Cancel returns backend errors without throwing

---

## Requirement Traceability

| Requirement | Phase | Plan | Verified |
|-------------|-------|------|----------|
| CRASH-01 | 01 | 01 | - |
| CRASH-02 | 01 | 01 | - |
| CRASH-03 | 01 | 01 | - |
| CRASH-04 | 01 | 01 | - |
| RIDE-01 | 02, 03 | 02-01, 03-01 | - |
| RIDE-02 | 02, 03 | 02-01, 03-01 | - |
| RIDE-03 | 02, 04 | 02-01, 04-01 | - |
| RIDE-04 | 02, 04 | 02-01, 04-01 | - |
| RIDE-05 | 03 | 03-02 | - |
| RIDE-06 | 02, 04 | 02-01, 02-02, 04-01 | - |
| RIDE-07 | 03, 04 | 03-02, 04-01 | - |
| RIDE-08 | 03, 04 | 03-02, 04-01 | - |
| RIDE-09 | 02, 03, 04 | 02-02, 03-01, 04-01 | - |
| RIDE-10 | 02, 04 | 02-01, 04-01 | - |
| RIDE-11 | 02, 04 | 02-02, 04-02 | - |
| RIDE-12 | 02, 04 | 02-02, 04-02 | - |
| PREBOOK-01 | 05, 06 | 05-02, 06-01 | - |
| PREBOOK-02 | 05 | 05-01, 05-02 | ✓ |
| PREBOOK-03 | 05, 06, 07 | 05-01, 05-03, 06-02, 07-01 | ✓ |
| PREBOOK-04 | 05, 06, 07 | 05-04, 06-01, 07-01 | ✓ |
| PREBOOK-05 | 06 | 06-01 | ✓ |
| PREBOOK-06 | 06, 07 | 06-02, 07-02 | ✓ |
| PREBOOK-07 | 07 | 07-01, 07-02 | ✓ |
| PROMO-01 | 09 | 09-01 | - |
| PROMO-02 | 09 | 09-02 | - |
| PROMO-03 | 09 | 09-02 | - |
| PROMO-04 | 09 | 09-01 | - |
---

## Phase 08: Scheduled Screen-Flow Integration

**Goal:** Scheduled rides navigate correctly on both apps — booking lands on Upcoming not tracking, driver-accept toasts without navigating, day-of arrival pulls user into live tracking, driver-cancel reassures with banner, driver Confirmed tab opens execution via Go to Pickup.

**Requirements:**
- **SCHED-01**: Scheduled booking success routes to Home/Upcoming, never live tracking
- **SCHED-02**: Scheduled driver-accept shows toast, no navigation, Upcoming list refreshes
- **SCHED-03**: Day-of arrival navigates to tracking from anywhere; started/completed reach rating/receipt
- **SCHED-04**: Scheduled driver-cancel shows persistent banner, no navigation, lists refresh
- **SCHED-05**: Driver Confirmed tab has time-gated Go to Pickup entering unified execution
- **SCHED-06**: Driver accept shows feedback, removes pool entry, lists under Confirmed

**Plans:** 3/3 plans complete
Plans:
- [x] `08-01-PLAN.md` — Rider booking + accept guards (nav split, accept toast, list refresh)
- [x] `08-02-PLAN.md` — Rider day-of + cancel (global arrival nav, live continuity, cancel banner)
- [x] `08-03-PLAN.md` — Driver entry + landing (Go to Pickup, accept verification)

**Success Criteria:**
- Full scheduled lifecycle navigates per guide on both apps with zero disruptive navigation
- Instant-ride flows behavior-identical (no regressions)
- `flutter analyze` clean on touched files
- No payment, fare, or repayment logic touched

---

## Phase 09: Promo Pending State

**Goal:** Promo flow reflects the 4-state backend (none/eligible/pending/claimed) — pending shows as locked free ride on status screen and home banner, with no client-side fare/booking blocks.

**Requirements:**
- **PROMO-01**: App parses all 4 promo states including isPending from GET /api/v1/users/promo-status
- **PROMO-02**: PromoStatusScreen renders pending as locked state (badge, hero, progress copy)
- **PROMO-03**: Home promo banner renders pending as locked banner, tappable to status screen
- **PROMO-04**: 401/500 promo errors handled gracefully; fare/booking add no client-side pending block (backend authoritative)

**Plans:** 2/2 plans complete
Plans:
- [x] `09-01-PLAN.md` — Typed PromoStatus model + ApiService docs + unit tests (TDD)
- [x] `09-02-PLAN.md` — Pending UI: status screen + home banner

**Success Criteria:**
- All 4 backend scenarios render correct copy on both surfaces
- `flutter analyze` clean on touched files
- `flutter test test/promo_status_test.dart` passes
- Zero fare/booking blocking logic added

---

## Phase 10: Driver Request Stack

**Goal:** Driver never misses a request because a card is open — concurrent offers stack Uber-style, dead ones (rider-cancelled, taken by another driver) vanish with feedback.

**Requirements:**
- **STACK-01**: Concurrent ride requests queue while a request card is open (no drops)
- **STACK-02**: Rider cancel removes only that ride from the stack, rest stay visible
- **STACK-03**: `ride:unavailable` socket event removes the taken ride with a toast
- **STACK-04**: Stacked UX — count badge, card cycling, per-card accept/decline

**Plans:** 2/2 plans complete
Plans:
- [ ] `10-01-PLAN.md` — Queue state + per-ride removal + ride:unavailable listener
- [ ] `10-02-PLAN.md` — Stacked panel UI + queue wiring

**Success Criteria:**
- 2+ concurrent requests all visible and operable, none dropped
- Cancel/taken rides vanish with explanatory feedback; survivors stay
- Single-request flow pixel-identical to today
- `flutter analyze` clean on touched files

### Phase 12: Excess balance Stage 2 settlement rider cash online plus driver cash confirm

**Goal:** In-car excess-balance settlement — rider picks Cash (driver confirms) or Online (WebView) on the live trip-completion screen via POST /payments/balance/:rideId/select-method; driver gets excessCashRequested modal + confirm-driver-cash; startup balance stays online-only. Full backend contract in phase dir INTEGRATION-GUIDE.md.
**Depends on:** Phase 11
**Plans:** 3/3 plans complete

Plans:
- [x] `12-01-PLAN.md` — API foundation: select-method + confirm-driver-cash, tolerant parser, socket passthroughs, contract tests
- [x] `12-02-PLAN.md` — Rider settlement sheet on receipt: Cash/Online + waiting state + WebView + succeeded close-out
- [x] `12-03-PLAN.md` — Driver cash modal: Collect-Cash request + confirm wiring + cancelled auto-close

### Phase 13: Account suspension safeguard on startup outstanding balance

**Goal:** Startup suspension gate — on GET /payments/balance with accountSuspended:true + allowCash:false, lock Book/Schedule buttons and show pay-online-only modal; unlock on payment:succeeded. Live in-car settlement stays in Phase 12. Full backend contract in phase dir INTEGRATION-GUIDE.md.
**Depends on:** Phase 12
**Plans:** 2/2 plans complete

Plans:
- [ ] `13-01-PLAN.md` — Suspension-flag parsing foundation (model + contract tests) + 403 backstop verification
- [ ] `13-02-PLAN.md` — Home startup gate (entry lock + pay-online modal + succeeded/clear unlock)

### Phase 14: Handle excessCashConfirmed close-out on rider and driver

**Goal:** Close out the driver-cash round-trip — on `payment:excessCashConfirmed`, rider exits the waiting state with settled confirmation and driver closes the Collect-Cash modal with toast. Exact backend payloads in phase dir INTEGRATION-GUIDE.md; event verified unhandled (zero hits in lib/).
**Depends on:** Phase 13
**Plans:** 3/3 plans complete

Plans:
- [x] `14-01-PLAN.md` — Socket transport: on/offExcessCashConfirmed passthroughs + dedupe regression tests
- [x] `14-02-PLAN.md` — Rider close-out: waitingCash exit via authoritative refresh + thank-you copy
- [x] `14-03-PLAN.md` — Driver close-out: Collect-Cash modal close + single toast + reconnect wiring

### Phase 17: Backend enforces payment_link only for scheduled rides — remove cash from prebook flow and handle new error responses

**Goal:** [To be planned]
**Depends on:** Phase 16
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 17 to break down)

---

## Phase 18: Enforce backend payment_method constraints for scheduled rides

**Goal:** Scheduled rides accept payment_link only — cash rejected at create/schedule with 400; select-payment endpoint rejects cash for scheduled rides with 400. Frontend handles new error responses with friendly copy.

**Requirements:**
- **PAYCONST-01**: POST /rides/schedule returns 400 when payment_method=cash for scheduled rides
- **PAYCONST-02**: POST /rides/create returns 400 when payment_method=cash for scheduled rides (if endpoint allows schedule)
- **PAYCONST-03**: POST /rides/:id/select-payment returns 400 when payment_method=cash for scheduled rides
- **PAYCONST-04**: Error mapper surfaces friendly "Scheduled rides require online payment" copy for all three 400 cases
- **PAYCONST-05**: Booking/schedule UI disables cash option for scheduled rides preemptively
- **PAYCONST-06**: Select-payment sheet (if ever shown for scheduled) filters cash option

**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 18 to break down)

**Success Criteria:**
- Scheduled ride create/schedule with cash returns 400, not 500
- Select-payment with cash on scheduled ride returns 400
- Friendly error shown to user, no crashes
- Cash option hidden/disabled in UI for scheduled rides
- `flutter analyze` clean; contract tests green

## Phase 11: Upfront Ride Payments

**Goal:** Payment method fixed at booking — rider picks Online (payment_link) or Cash upfront, pays via immediate WebView or rides cash, never re-prompted on driver arrival.

**Requirements:**
- **UPFRONT-01**: Mandatory payment selection (payment_link|cash) on booking screen before request
- **UPFRONT-02**: paymentMethod sent in POST /rides/create and POST /rides/schedule; 400/403 handled
- **UPFRONT-03**: payment_link opens paymentUrl WebView immediately at booking; cash goes direct to matching
- **UPFRONT-04**: No POST /rides/:id/select-payment on driver arrival (display booking method only)
- **UPFRONT-05**: Startup GET /payments/balance surfaces outstanding balance with pay link

**Plans:** 3/3 plans complete
Plans:
- [ ] `11-01-PLAN.md` — API contract: mandatory paymentMethod, instant paymentUrl parsing, 400/403, balance tolerance + tests
- [ ] `11-02-PLAN.md` — Booking UI: mandatory Online-vs-Cash toggle + immediate link/cash routing (instant + scheduled)
- [ ] `11-03-PLAN.md` — Arrival cleanup: remove late select-payment, display-only method chip, mapper copy, startup banner verify

**Success Criteria:**
- Every booking POST carries cash|payment_link; link opens WebView at booking, cash skips it
- Zero select-payment calls on driver arrival; arrival shows Continue only
- 400/403 produce friendly actionable UI; startup debt banner opens pay link
- `flutter analyze` clean; contract tests green

## Phase 16: Revert Ride Payments (pay-after-accept)

**Goal:** Normal rides dispatch to drivers with zero payment at booking — rider pays via Pay Now WebView only after driver accepts (`ride:accepted` with `requiresPayment:true`); scheduled rides keep full upfront WebView. Method switching, reopen-rehydrate, and cancel/expired fallbacks all per `flutter_revert_flow.md`.

**Requirements:**
- **RVT-01**: Instant booking (link + cash) lands on searching with no WebView; scheduled booking still opens paymentUrl immediately
- **RVT-02**: Accept-time Pay Now prompt on `requiresPayment:true` link rides; cash/scheduled show no prompt
- **RVT-03**: `payment:authorized` closes the prompt with authorized copy, no navigation side-effects
- **RVT-04**: link<->cash switching via select-payment in requested/accepted/driver_arrived; driver sees `ride:paymentSelected`
- **RVT-05**: App reopen on accepted-unpaid link ride re-shows Pay Now via GET ride details
- **RVT-06**: Scheduled upfront, window-400, expired-refund, driver-cancel-repool, user-cancel-refund paths intact with friendly copy

**Plans:** 2/3 plans executed
Plans:
- [x] `16-01-PLAN.md` — Booking deferral: instant link to searching, scheduled WebView intact (wave 1)
- [x] `16-02-PLAN.md` — Accept-time payment: Pay Now prompt, authorized close-out, rehydrate, switcher restore (wave 1)
- [ ] `16-03-PLAN.md` — Scheduled + error audit, regression sweep, human end-to-end pass (wave 2)

**Success Criteria:**
- Instant link booking → searching, no WebView; accept → Pay Now → WebView → authorized ✓
- Cash/scheduled accepts never prompt; reopen restores prompt; switch updates driver UI
- `flutter analyze` clean; full test suite green; human approves 7-step device pass

### Phase 11.1: booking screen bottom-sheet UI compaction (INSERTED)

**Goal:** Ride booking screen bottom section (fare price + Online/Cash method buttons + Confirm ride + Prebook/Schedule buttons) currently fills too much of the screen after Phase 11 added the mandatory payment toggle — redesign into a compact bottom sheet so the map stays visible and the layout looks clean.
**Depends on:** Phase 11
**Plans:** 1/1 plans complete

Plans:
- [x] `11.1-01-PLAN.md` — Compact bottom-sheet card on both booking screens + contract verification

### Phase 15: Outstanding balance silent booking + fare transparency

**Goal:** Silent outstanding-balance booking — fare-estimate `outstandingBalance` surfaced as "Includes £X unpaid balance" transparency on booking screens, create/schedule succeed without 403, Stripe auto-covers the combined total with zero client-side fare math.
**Depends on:** Phase 14

**Requirements:**
- **BAL-01**: Parse `outstandingBalance` per fare-estimate category without altering totals ✅ (15-01)
- **BAL-02**: Contract tests pin brief section 1 JSON (total 15, balance 5, no double-count) ✅ (15-01)
- **BAL-03**: Booking screens show "Includes £X.XX unpaid balance" line/banner when balance > 0 ✅ (15-02)
- **BAL-04**: Create/schedule succeed with balance owing (403 backstop retained dormant); no socket/FCM/cancel-refund changes ✅ (15-02)

**Plans:** 2/2 plans complete

Plans:
- [x] `15-01-PLAN.md` — Fare parser: outstandingBalance through _normalizeCategory + contract tests
- [x] `15-02-PLAN.md` — Transparency UI on booking surfaces + silent-booking backstop verify

**Success Criteria:**
- Balance > 0 shows transparency copy pre-confirm; balance 0 renders pixel-identical
- Booking with debt succeeds via normal flow; Stripe covers combined total, no client math
- `flutter analyze` clean; fare-balance + outstanding + upfront tests green

## Phase 19: Ride Flow Resilience (socket-robust cold-start restore)

**Goal:** Kill-proof ride flow — app kill, device lock, OS restart, or socket drop never breaks an active ride; cold start restores exact screen from authoritative backend state with Uber/Bolt-style reconnecting UX.

**Requirements:**
- **RES-01**: Socket transport survives drops — unbounded reconnect with backoff, ack/timeout on critical emits, no silent listener loss on re-init
- **RES-02**: Cold start restores exact ride screen — kill + reopen lands on searching/assigned/progress/receipt via GET ride details, never home-dead-end
- **RES-03**: Background/lock/restart re-syncs — foreground resume + FCM data-message trigger authoritative refresh + room rejoin, missed events reconciled
- **RES-04**: Stale/offline states are explicit — reconnecting banner, last-known chip, retry action; never fake-live UI (Uber/Bolt/Lyft reference)
- **RES-05**: Outgoing actions never lost — queued across restart with sane expiry, deduped, flushed in order on reconnect
- **RES-06**: No regressions — instant + scheduled + payment flows behavior-identical when network healthy

**Plans:** 3/3 plans complete

Plans:
- [x] `19-01-PLAN.md` — Socket transport hardening (unbounded reconnect, ack emits, listener registry, durable queue + tests)
- [x] `19-02-PLAN.md` — Cold-start restore + re-sync (RideSession global entry, rider/driver wiring, FCM/resume, merge tests)
- [x] `19-03-PLAN.md` — Resilience UX + verification (ConnectionBanner, stale chips, regression sweep, human device pass)

**Success Criteria:**
- Kill app mid-trip (rider + driver) → reopen restores exact screen with live updates resumed
- Airplane-mode 60s → reconnect reconciles missed status without duplicate actions
- `flutter analyze` clean; contract/unit tests green; human kill-restart pass on both roles

## Phase 20: Driver Back-to-Back Dispatch

**Goal:** Drivers chain rides without idle gap — mid-trip B2B offer → docked queued pill → complete promotes next trip with auto-navigation; riders see a standard assigned experience with honest ETAs. Full backend contract in `driver-multirequest.md`.

**Requirements:**
- **B2B-01**: Driver accepts queued ride (POST accept → status accepted + isQueued true); second-queue blocked with friendly copy
- **B2B-02**: Queued trip docked as Next-trip pill (pickup + fare + driver-cancel) while Trip A keeps map and all action buttons
- **B2B-03**: Complete promotes queued ride (hasQueuedRidePromoted/nextRideId) + ride:nextTripActivated auto-switches navigation exactly once
- **B2B-04**: Socket ride:newRequest (isBackToBack) + ride:cancelled clear queued with feedback, Trip A untouched
- **B2B-05**: Rider B sees standard assigned UI (driver card, no negative phrasing) + cancel-while-queued with reason
- **B2B-06**: Rider live tracking (trackDriver emit, driver:locationChanged, etaUpdate) + driverEnRoute status trigger
- **B2B-07**: FCM data types ride_request B2B / queued_ride_cancelled / ride_accepted / ride_driver_en_route land correctly
- **B2B-08**: No regressions — instant + scheduled + payment + restore flows identical when network healthy

**Plans:** 3/3 plans executed

Plans:
- [x] `20-01-PLAN.md` — Contract + transport: QueuedRide parsers, 6 socket passthroughs, error copy, contract tests (wave 1)
- [x] `20-02-PLAN.md` — Driver B2B: queuedTrip state, docked pill, promotion auto-transition (wave 2, needs 20-01)
- [x] `20-03-PLAN.md` — Rider B2B: assigned tracking, FCM types, regression sweep (wave 2, needs 20-01)

**Success Criteria:**
- Mid-trip B2B accept → pill visible → complete A → auto-navigate to B pickup, exactly once
- Rider B sees driver card + live marker + honest ETA, never queue language
- `flutter analyze` clean; contract + full test suite green; human two-device B2B pass
