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
| 07 | Driver Prebook Flow | In Progress | 1/2 | PREBOOK-03..07 |

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
| PREBOOK-06 | 06, 07 | 06-02, 07-02 | - |
| PREBOOK-07 | 07 | 07-01, 07-02 | ✓ |