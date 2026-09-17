---
phase: 12-excess-balance-stage-2-settlement-rider-cash-online-plus-driver-cash-confirm
verified: 2026-09-17T00:00:00Z
status: passed
score: 12/12 must-haves verified
---

# Phase 12: Excess Balance Stage-2 Settlement Verification Report

**Phase Goal:** In-car excess-balance settlement — rider picks Cash (driver confirms) or Online (WebView) on the live trip-completion screen via POST /payments/balance/:rideId/select-method; driver gets excessCashRequested modal + confirm-driver-cash; startup balance stays online-only.
**Verified:** 2026-09-17T00:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | select-method and confirm-driver-cash endpoints are callable from ApiService with never-throws envelope | ✓ VERIFIED | `api_service.dart:1101,1112` both delegate to `_postRequest`; `api_constants.dart:113,117` build correct URLs |
| 2 | select-method response parses paymentUrl and amount tolerantly across envelope shapes | ✓ VERIFIED | `outstanding_balance.dart:75-140` handles flat+nested+list+flat-top-level, 3 amount keys; 9/9 contract tests green |
| 3 | driver socket events have symmetric on/off passthroughs for requested and cancelled | ✓ VERIFIED | `socket_service.dart:692-708` exact `payment:excessCashRequested` / `payment:excessCashCancelled` with off-symmetry |
| 4 | Rider on live trip-completion screen sees Cash and Pay Online options when excess is owed | ✓ VERIFIED | `excess_settlement_sheet.dart:241,260` Pay Cash to Driver + Pay Online; hosted via `ride_complete_screen.dart:174-192` modal sheet on pendingBalance + balanceDue |
| 5 | Tapping Cash calls select-method with cash and shows driver-confirm waiting state with a way back to Online | ✓ VERIFIED | `_selectCash` posts `'cash'` (`:130`), waiting state `:230-231` + Switch to Online `:300-308` + back chevron `:207-216` |
| 6 | Tapping Pay Online calls select-method with payment_link and opens paymentUrl in PaymentWebViewScreen | ✓ VERIFIED | `_selectOnline` posts `'payment_link'` (`:150`), parses via `fromSelectMethodEnvelope` (`:161`), pushes `PaymentWebViewScreen` (`:171-176`) |
| 7 | payment:succeeded closes settlement back to receipt/rating only after authoritative re-fetch confirms cleared | ✓ VERIFIED | `_onPaymentSucceeded` rideId-match + dedupe `payment_succeeded_settlement` + `_refresh(fromEvent:true)`; pop only on succeeded/404 (`:56-125`) |
| 8 | Startup OutstandingBalanceScreen stays online-only with no cash button | ✓ VERIFIED | grep `Pay Cash|_selectCash|selectBalanceMethod` in outstanding_balance_screen.dart = zero; only `Pay via Payment Link` (`:239`) + `Check again` |
| 9 | Driver receives Collect Cash modal with £X amount when rider requests cash | ✓ VERIFIED | `_showExcessCashDialog` AlertDialog `Collect Cash: £X` (`:2454-2475`), rideId-match + dedupe `payment_excess_cash_requested` (`:1353-1376`) |
| 10 | Confirm Cash Received calls confirm-driver-cash with driver token, closes modal, toasts success | ✓ VERIFIED | Confirm tap `confirmDriverCash(rideId)` (`:2495`), success pop + `Cash payment confirmed! Ride fully completed.` toast (`:2497-2506`) |
| 11 | Failed confirm keeps modal open with inline error | ✓ VERIFIED | Failure path `setDialogState sheetError` via `RideErrorMapper`, no pop (`:2507-2517`) |
| 12 | Rider switching to online auto-closes driver modal silently | ✓ VERIFIED | `onExcessCashCancelled` dedupe-guarded → `_closeExcessCashDialogIfOpen` silent no-toast (`:1380-1402,2542-2550`); `payment:succeeded` same-ride also drops modal (`:1270`) |

**Score:** 12/12 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/core/api_service.dart` | selectBalanceMethod + confirmDriverCash via _postRequest | ✓ VERIFIED | Both present, substantive, wired (called from sheet + driver modal) |
| `lib/core/constants/api_constants.dart` | select-method + confirm-driver-cash URL builders | ✓ VERIFIED | Correct `$baseUrl/payments/balance/$rideId/...` paths |
| `lib/core/models/outstanding_balance.dart` | fromSelectMethodEnvelope tolerant parser | ✓ VERIFIED | 66-line parser, exercised by 9 passing tests |
| `lib/core/services/socket_service.dart` | excess cash requested/cancelled passthroughs | ✓ VERIFIED | 4 methods, exact colon-camelCase strings, used by driver screen |
| `test/excess_settlement_contract_test.dart` | select-method envelope parsing tests | ✓ VERIFIED | 152 lines, 9/9 green (`flutter test` confirmed) |
| `lib/features/ride/excess_settlement_sheet.dart` | Cash/Online buttons + waiting state + succeeded close-out | ✓ VERIFIED | 324 lines, substantive, hosted on receipt |
| `lib/features/ride/ride_complete_screen.dart` | Hosts settlement sheet when excess owed | ✓ VERIFIED | Contains `ExcessSettlementSheet`, pendingBalance + balanceDue paths |
| `lib/core/models/error_display_helper.dart` | select-method + confirm-driver-cash error copy | ✓ VERIFIED | Contains `selectBalanceMethod` (`:134`) + `confirmDriverCash` (`:167`) mapper cases |
| `lib/features/driver/driver_home_screen.dart` | excess cash modal + confirm wiring + auto-close | ✓ VERIFIED | Contains `_excessCashDialogOpen`, confirm wiring, off-symmetry in dispose + setup |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `lib/core/api_service.dart` | `lib/core/constants/api_constants.dart` | selectBalanceMethod/confirmDriverCash URL builders in _postRequest call | WIRED | `ApiConstants.selectBalanceMethod` / `confirmDriverCash` referenced in both methods |
| `test/excess_settlement_contract_test.dart` | `lib/core/models/outstanding_balance.dart` | imports and exercises fromSelectMethodEnvelope | WIRED | Import + 9 cases all calling parser, all pass |
| `lib/features/ride/excess_settlement_sheet.dart` | `lib/core/api_service.dart` | selectBalanceMethod cash/payment_link calls | WIRED | Both `_selectCash` and `_selectOnline` call it |
| `lib/features/ride/excess_settlement_sheet.dart` | PaymentWebViewScreen | push paymentUrl, success re-fetch, cancel returns to choice | WIRED | `Navigator.push PaymentWebViewScreen(paymentUrl, rideId)`, success → `_refresh`, cancel → warning snackbar |
| `lib/features/ride/excess_settlement_sheet.dart` | payment:succeeded socket | rideId-match, authoritative GET, pop-only-when-cleared | WIRED | `on('payment:succeeded')` + dedupe + re-fetch, never pops on event alone |
| `lib/features/driver/driver_home_screen.dart` | `lib/core/services/socket_service.dart` | on/offExcessCashRequested + on/offExcessCashCancelled passthroughs | WIRED | `on...` in `_setupSocketListeners` (`:1353,1380`), `off...` in dispose (`:537-538`) + re-setup (`:1228-1229`) |
| `lib/features/driver/driver_home_screen.dart` | `lib/core/api_service.dart` | confirmDriverCash on Confirm tap | WIRED | Confirm button awaits `confirmDriverCash(rideId)` |
| `payment:excessCashCancelled socket` | `_excessCashDialogOpen modal` | pop only if flag true, silent no-toast | WIRED | `_closeExcessCashDialogIfOpen` flag-guarded, no snackbar on that path |

### Requirements Coverage

No REQUIREMENTS.md exists in repo — verified IDs against PLAN frontmatter + SUMMARYs + 12-RESEARCH.md requirement table instead.

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| STAGE2-01 | 12-02 | Rider settlement UI on live trip-completion screen: Cash + Online, cash waiting state | ✓ SATISFIED | ExcessSettlementSheet choice + waitingCash states hosted on RideCompleteScreen |
| STAGE2-02 | 12-01, 12-02 | select-method API cash\|payment_link; payment_link returns paymentUrl in WebView | ✓ SATISFIED | ApiService + ApiConstants + parser + WebView push, tests green |
| STAGE2-03 | 12-02 | Rider close-out on payment:succeeded → rating/home | ✓ SATISFIED | Re-fetch-and-pop handler, pop only when cleared |
| STAGE2-04 | 12-03 | Driver excessCashRequested modal Collect Cash £X + Confirm | ✓ SATISFIED | Dialog with amount, dedupe + rideId guards |
| STAGE2-05 | 12-01, 12-03 | confirm-driver-cash API with driver token; close modal + toast | ✓ SATISFIED | confirmDriverCash via _postRequest, success pop + toast, failure stays open |
| STAGE2-06 | 12-03 | excessCashCancelled auto-closes driver modal | ✓ SATISFIED | Silent flag-guarded close; also on payment:succeeded |

No orphaned requirements — all 6 IDs claimed across the 3 plans (01: 02,05; 02: 01,02,03; 03: 04,05,06).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (phase files only) | — | `return null` hits in touched files | ℹ️ Info | All are legitimate nullable-parser early returns (`outstanding_balance.dart:40,89,125`, `error_display_helper.dart:39,46`), not stubs |
| — | — | TODO/FIXME/placeholder/Not implemented | — | Zero matches in phase-touched lib files (only pre-existing `fcm_service.dart:359` TODO, out of scope) |
| — | — | `select-payment` resurrection | — | None — only deprecated definition + doc comment remain, zero live calls |

### Human Verification Required

1. **In-car cash round-trip**
   - **Test:** Complete a trip with excess; rider taps Cash; driver confirms on driver device; observe rider screen.
   - **Expected:** Driver modal opens with correct £X; rider shows waiting state; driver Confirm → rider auto-closes to receipt/rating via payment:succeeded.
   - **Why human:** Needs two live devices + backend socket events; cannot verify end-to-end programmatically.

2. **Rider switch-to-online cancels driver modal**
   - **Test:** Rider taps Cash, then Switch to Online and pays via WebView.
   - **Expected:** Driver modal auto-closes silently (no toast); online payment completes normally.
   - **Why human:** Cross-device socket timing; needs live backend.

3. **Online WebView payment flow**
   - **Test:** Rider taps Pay Online, completes Stripe checkout in WebView.
   - **Expected:** Success returns to sheet, authoritative re-fetch confirms cleared, sheet pops with success snackbar.
   - **Why human:** Real Stripe paymentUrl + WebView navigation; live backend required.

### Gaps Summary

None. All 12 must-have truths verified at all three levels (exists, substantive, wired); all 8 key links WIRED; startup screen confirmed online-only; 9/9 contract tests pass; no blocker anti-patterns.

---

_Verified: 2026-09-17T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
