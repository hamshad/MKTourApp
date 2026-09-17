# Phase 12: Excess Balance Stage 2 Settlement — Research

**Researched:** 2026-09-17
**Domain:** Flutter in-car excess-balance settlement (rider cash/online selection + driver cash confirm), socket-driven close-out
**Confidence:** HIGH (backend contract + existing code both read; only response-envelope details unverified)

## Summary

Phase 12 adds a live, in-car settlement surface for excess balance (wait fees / extra distance): on the trip-completion screen the rider picks **Cash** (driver confirms receipt) or **Online** (Stripe `paymentUrl` in the existing `PaymentWebViewScreen`) via a new endpoint `POST /payments/balance/:rideId/select-method`. `payment:succeeded` closes the settlement screen. On the driver side, a new `payment:excessCashRequested` socket event raises a "Collect Cash £X → Confirm Cash Received" modal wired to `POST /payments/balance/:rideId/confirm-driver-cash`, and `payment:excessCashCancelled` auto-closes that modal when the rider switches back to online. Startup balance (`GET /payments/balance`) stays online-only — cash option hidden.

**Primary recommendation:** Build one new rider widget (`ExcessSettlementSheet` content inside/on top of `RideCompleteScreen`, reusing the `OutstandingBalance` model + `PaymentWebViewScreen` + `payment:succeeded` re-fetch-and-pop pattern from `OutstandingBalanceScreen`), add two `ApiConstants` + two `ApiService._postRequest` methods, add `SocketService` passthroughs + `RideEventDedupe` keys for the two new driver events, and implement the driver cash modal in `driver_home_screen.dart` with `StatefulBuilder` + explicit modal-open tracking. Extend `test/outstanding_balance_test.dart`-style parsing tests for the select-method envelope. Do NOT resurrect the deleted `rides/:id/select-payment` arrival flow.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `http` | pinned in pubspec | REST calls (`_postRequest`, `getPaymentBalance`) | Every payment call in the app uses it via `ApiService` |
| `socket_io_client` | pinned in pubspec | `payment:*` live events | `SocketService.on/off` is the only socket path |
| `webview_flutter` | pinned in pubspec | Online settlement (`PaymentWebViewScreen`) | Already handles success/cancel URL detection + `{success:true/false}` pop contract |
| `provider` | pinned in pubspec | Auth user / driverId lookup | Driver screen already resolves driverId this way |
| `shared_preferences` | pinned in pubspec | `auth_token`, `pending_balance_ride_id` | Token + balance persistence live here |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `flutter_test` | SDK | Parsing contract tests | select-method envelope tests, same as `test/upfront_payment_contract_test.dart` |
| `CustomSnackbar` (`core/widgets`) | n/a | Toasts for confirm/cancel/error | All payment feedback uses it |
| `RideErrorMapper` (`core/models/error_display_helper.dart`) | n/a | Backend-error → friendly copy | Any new 400/403/409 copy from the two new endpoints goes here, never per-screen strings |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| New settlement content on `RideCompleteScreen` | Extend `OutstandingBalanceScreen` with a mode flag | Reuse is tempting but that screen is online-only by contract (Phase 13 suspension gate depends on it); a mode flag risks leaking the cash button into the startup path. Prefer a new widget that shares the model + WebView + refresh logic |
| `showDialog` driver modal | Slide-up panel / persistent banner | Dialog matches the existing fare-summary/cancel-reason modal pattern in `driver_home_screen.dart` and is interruptive by design (cash in hand). Banner is too easy to miss |
| New socket helpers | Raw `socket.on('payment:excessCashRequested')` inline | Raw strings scatter and break `off()` symmetry on reconnect; passthroughs (`onExcessCashRequested`/`offExcessCashRequested`) match the existing `onPaymentBalanceDue` pattern |

**Installation:** none — no new dependencies.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| STAGE2-01 | Rider settlement UI on live trip-completion screen: Cash + Online options, cash shows "Waiting for driver to confirm…" state | `RideCompleteScreen` receipt + `_paymentMethodLabel` section; new `ExcessSettlementSheet` widget; `OutstandingBalance` model carries amount/message |
| STAGE2-02 | `select-method` API: `POST /payments/balance/:rideId/select-method` with `{paymentMethod: cash\|payment_link}`; `payment_link` returns `paymentUrl` opened in `PaymentWebViewScreen` | `ApiConstants.paymentBalance(rideId)` + `_postRequest` pattern; `PaymentWebViewScreen(paymentUrl, rideId)` `{success}` pop contract; `OutstandingBalance.fromBalanceEnvelope` tolerance (flat + nested `data.payment.paymentUrl`, `excessAmount/outstandingBalance/amount` keys) |
| STAGE2-03 | Rider close-out on `payment:succeeded`: close settlement screen → rating/home | `OutstandingBalanceScreen._onPaymentSucceeded` re-fetch-and-pop pattern (event + authoritative GET, not event-alone); `RideEventDedupe` 5s window; `_didNavigateToReceipt` once-guard precedent |
| STAGE2-04 | Driver `payment:excessCashRequested` modal: "Collect Cash £X" + Confirm Cash Received | `SocketService` passthrough pattern; `driver_home_screen.dart` `StatefulBuilder` dialog pattern; existing `payment:succeeded`/`payment:cancelled` listener setup/teardown block |
| STAGE2-05 | `confirm-driver-cash` API: `POST /payments/balance/:rideId/confirm-driver-cash` with driver token; close modal + success toast | `ApiService.confirmCashCollection` (`confirmCash`) `_postRequest` precedent; `ErrorDisplayHelper.showRideError` on failure; modal stays open on failure |
| STAGE2-06 | `payment:excessCashCancelled` auto-closes driver cash modal when rider switches to online | Modal-open tracking flag (`_excessCashDialogOpen`); `off()` symmetry in `dispose` + reconnect re-setup block; no toast spam on auto-close |
</phase_requirements>

## Architecture Patterns

### Recommended Project Structure
```
lib/
├── core/
│   ├── api_service.dart                  # + selectBalanceMethod, confirmDriverCash (via _postRequest)
│   ├── constants/api_constants.dart      # + selectBalanceMethod(rideId), confirmDriverCash(rideId)
│   ├── models/outstanding_balance.dart   # + fromSelectMethodEnvelope (tolerant parser)
│   └── services/socket_service.dart      # + on/offExcessCashRequested, on/offExcessCashCancelled
├── features/
│   ├── ride/
│   │   ├── ride_complete_screen.dart     # hosts ExcessSettlementSheet when excess owed
│   │   ├── excess_settlement_sheet.dart  # NEW: Cash/Online buttons + waiting state (STAGE2-01/02/03)
│   │   ├── outstanding_balance_screen.dart # UNTOUCHED online-only (startup path)
│   │   └── payment_webview_screen.dart   # reused as-is for paymentUrl
│   └── driver/
│       └── driver_home_screen.dart       # excess cash modal + confirm wiring (STAGE2-04/05/06)
test/
└── excess_settlement_contract_test.dart  # NEW: select-method envelope parsing tests
```

### Pattern 1: New `select-method` endpoints via `_postRequest` + `ApiConstants`
**What:** Two one-line URL builders plus two thin `ApiService` methods that delegate to `_postRequest` (never throws; returns decoded map on 200/201, decoded error body otherwise, `{success:false}` on exception).
**When to use:** STAGE2-02, STAGE2-05.
**Example:**
```dart
// Source: lib/core/constants/api_constants.dart:106-109, lib/core/api_service.dart:1085-1096,1168-1221
static String selectBalanceMethod(String rideId) =>
    '$baseUrl/payments/balance/$rideId/select-method';
static String confirmDriverCash(String rideId) =>
    '$baseUrl/payments/balance/$rideId/confirm-driver-cash';

Future<Map<String, dynamic>> selectBalanceMethod(String rideId, String paymentMethod) async {
  return await _postRequest(ApiConstants.selectBalanceMethod(rideId), {
    'paymentMethod': paymentMethod, // 'cash' | 'payment_link' per INTEGRATION-GUIDE.md
  });
}
Future<Map<String, dynamic>> confirmDriverCash(String rideId) async {
  return await _postRequest(ApiConstants.confirmDriverCash(rideId), {});
}
```
**Note:** This is a NEW endpoint family (`/payments/balance/:rideId/...`). Do not reuse or un-deprecate `rides/:id/select-payment` (deleted in 11-03, `5f01d0c`).

### Pattern 2: Rider settlement as new content on the receipt, sharing model + WebView
**What:** When the completed ride carries excess owed (via `pendingBalance` handoff or `payment:balanceDue` post-completion), show `ExcessSettlementSheet` (Cash / Pay Online buttons + waiting state) on top of / inside `RideCompleteScreen`. Cash → `selectBalanceMethod(rid, 'cash')` → waiting UI ("Waiting for driver to confirm cash receipt…", cancellable back to method choice). Online → `selectBalanceMethod(rid, 'payment_link')` → parse `paymentUrl` (flat or `data.payment.paymentUrl`) → push `PaymentWebViewScreen`; `{success:true}` → authoritative `_refresh(fromEvent:true)`; `{success:false}` → back to method choice with warning snackbar.
**When to use:** STAGE2-01, STAGE2-02, STAGE2-03.
**Example (reuse targets):**
```dart
// Source: lib/features/ride/outstanding_balance_screen.dart:48-58,122-180
// 1. payment:succeeded handler: re-fetch authoritatively, pop ONLY when cleared
//    (event alone is NOT proof — backend also emits it for mid-trip base-fare captures).
// 2. _openPaymentLink: paymentUrl ?? refetch, push PaymentWebViewScreen,
//    success → _refresh(fromEvent: true), cancel → warning, stay on screen.
// Source: lib/features/ride/ride_assigned_screen.dart:2300-2335,2337-2368
// 3. Mid-trip balanceDue → stash in _pendingBalanceDue, hand to receipt via
//    consumePendingBalance() → receipt auto-opens settlement on top of summary.
// 4. _didNavigateToReceipt once-guard: receipt pushed exactly once.
```

### Pattern 3: Socket passthroughs + dedupe keys for the two new driver events
**What:** Add `onExcessCashRequested/offExcessCashRequested` and `onExcessCashCancelled/offExcessCashCancelled` to `SocketService` (mirroring `onPaymentBalanceDue`, `socket_service.dart:663-669`), register in `driver_home_screen._setupSocketListeners` with the same `off`-before-`on` re-setup hygiene (lines 1200-1220), and guard the modal-open path with `RideEventDedupe.shouldHandleEvent(source:'socket', type:'payment_excess_cash_requested', data: map)`.
**When to use:** STAGE2-04, STAGE2-06.
**Example:**
```dart
// Source: lib/core/services/socket_service.dart:661-679, lib/core/services/ride_event_dedupe.dart:42-58
void onExcessCashRequested(void Function(dynamic) handler) {
  on('payment:excessCashRequested', handler);
}
void offExcessCashRequested() {
  off('payment:excessCashRequested');
}
// Driver handler:
final map = data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data as Map);
if (!RideEventDedupe.shouldHandleEvent(source: 'socket', type: 'payment_excess_cash_requested', data: map)) return;
// Exact event strings: 'payment:excessCashRequested', 'payment:excessCashCancelled'
// (colon form — NOT dot form; cf. 'payment:balanceDue' precedent).
```

### Pattern 4: Driver cash modal with open-tracking + failure-stays-open
**What:** `barrierDismissible:false` `AlertDialog` via `StatefulBuilder` (matches `_showCancellationReasonDialog`, `driver_home_screen.dart:2624-2728`): amount headline, `Confirm Cash Received` elevated button with inline spinner, failure renders inline `sheetError` via `RideErrorMapper` and keeps the modal open; success pops + success snackbar ("Cash payment confirmed! Ride fully completed."). Track `_excessCashDialogOpen` bool: set true on open, false on any pop; `payment:excessCashCancelled` pops only if flag true (silent, no error toast); also pop on `payment:succeeded` for that rideId. Match rideId against `_currentRideId` accepting `rideId/bookingId/_id/id` keys.
**When to use:** STAGE2-04, STAGE2-05, STAGE2-06.

### Anti-Patterns to Avoid
- **Resurrecting `rides/:id/select-payment`:** deleted in 11-03 on purpose. The new call is `POST /payments/balance/:rideId/select-method` with values `cash | payment_link`. Grep-verify zero live `select-payment` calls after the phase.
- **Popping on `payment:succeeded` without re-fetch:** the event also fires for mid-trip base-fare captures (see `outstanding_balance_screen.dart:54-56`). Always re-fetch `getPaymentBalance` and pop only when `succeeded`/404-after-event.
- **Raw socket strings scattered in UI:** use the new passthroughs so `off()` cleanup and reconnect re-registration stay symmetric.
- **Cash option on the startup screen:** `OutstandingBalanceScreen` stays online-only (Phase 13 suspension gate builds on this). The cash button lives only in the new live-settlement widget.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Payment URL success/cancel detection | Custom URL matcher | Existing `PaymentWebViewScreen` as-is | Already handles success/cancel URL shapes, cancel-confirm dialog, `{success}` pop contract |
| FCM+socket double delivery | Ad-hoc `bool _handled` flags | `RideEventDedupe.shouldHandleEvent` (5s type+rideId window) | Shared cross-transport guard; first transport wins; used by every payment/ride handler |
| Backend error copy | Per-screen strings | `RideErrorMapper` / `ErrorDisplayHelper.showRideError` | Central mapper is the Phase 11+ rule; keeps copy consistent and testable |
| Balance amount parsing | New amount model | Extend `OutstandingBalance` (`fromSelectMethodEnvelope`) | Already tolerates flat + nested `data.payment.paymentUrl`, three amount keys, list envelopes; covered by 9 existing tests |
| Auth headers / 401 handling | Manual http.post | `ApiService._postRequest` | Token injection, debug logging, 401 hook, never-throws envelope |

**Key insight:** Every moving part except the settlement sheet UI and the driver modal already exists as a proven pattern. The phase is wiring, not invention.

## Common Pitfalls

### Pitfall 1: `payment:succeeded` ambiguity closes the wrong thing
**What goes wrong:** Rider's settlement screen pops when the event was for a mid-trip base-fare capture, stranding the real excess unpaid.
**Why it happens:** Backend emits `payment:succeeded` for multiple payment kinds with similar payloads.
**How to avoid:** Copy `OutstandingBalanceScreen._onPaymentSucceeded` exactly: rideId-match → `_refresh(fromEvent:true)` → pop only on `status==succeeded` or 404-after-event; if balance still owed, `setState` fresh amount and stay open.
**Warning signs:** Pop called directly inside the socket callback with no GET.

### Pitfall 2: Driver modal orphaned by navigation / rebuild
**What goes wrong:** `payment:excessCashCancelled` arrives but the dialog context is dead → exception or modal stuck open; or two modals stack on duplicate events.
**Why it happens:** Dialogs live outside the widget tree; socket callbacks outlive screens.
**How to avoid:** `_excessCashDialogOpen` flag + `mounted` checks + dedupe key on open; store no `BuildContext` across awaits (use the dialog's own context for pop); `off()` all three payment listeners in `dispose` and re-register in the reconnect block.
**Warning signs:** `showDialog` called without a dedupe guard; `Navigator.pop(context)` using a stale outer context.

### Pitfall 3: Rider cash-waiting state is a dead end
**What goes wrong:** Rider taps Cash, driver never confirms (offline, wrong screen), rider stuck on spinner with no way back.
**Why it happens:** No timeout / back affordance specified in the contract.
**How to avoid:** Waiting state offers "Switch to Online" (re-calls select-method with `payment_link` — which per contract fires `excessCashCancelled` to close the driver modal) and a back chevron to method choice. Recommend: no auto-timeout in v1, user-driven switch only.
**Warning signs:** Waiting UI with no buttons.

### Pitfall 4: Startup balance leaks the cash option
**What goes wrong:** Shared widget shows "Pay Cash to Driver" on the startup screen where no driver is present.
**Why it happens:** Over-reuse of one widget for both live and startup surfaces.
**How to avoid:** New `ExcessSettlementSheet` used ONLY from `RideCompleteScreen`/live flow; `OutstandingBalanceScreen` untouched (online-only). Phase 13's suspension modal also depends on this separation.
**Warning signs:** Any edit to `outstanding_balance_screen.dart` adding a cash button.

### Pitfall 5: Wrong token role on `confirm-driver-cash`
**What goes wrong:** 401/403 on driver confirm because the request carries the rider token (single-codebase app, both roles share `ApiService` + `auth_token` key).
**Why it happens:** One app binary serves both roles; token in prefs belongs to whoever logged in on that device.
**How to avoid:** No code branching needed — driver device holds the driver token by construction — but verification must test with a driver-role token; surface mapper copy (not raw 401) on failure and keep the modal open.
**Warning signs:** Manual QA done only with a rider login.

### Pitfall 6: Event-name drift (`:` vs `_` vs camelCase)
**What goes wrong:** Listener never fires because the registered string doesn't match the backend emission.
**Why it happens:** Codebase mixes `payment:succeeded`, `payment_selected`, `payment:balanceDue`. The new events are camelCase after the colon.
**How to avoid:** Exact strings `payment:excessCashRequested` and `payment:excessCashCancelled`; verify against `SocketService.onAny` logs on a live trip; do NOT also subscribe snake_case variants unless logs prove the backend emits them.
**Warning signs:** Copy-pasting `payment_selected` (old upfront event) as a template.

## Code Examples

Verified patterns from repo sources:

### ApiService never-throws POST + balance GET
```dart
// Source: lib/core/api_service.dart:1085-1096, 1136-1166, 1168-1221
Future<Map<String, dynamic>> selectPaymentMethod(String rideId, String paymentMethod) async {
  return await _postRequest(ApiConstants.selectPaymentMethod(rideId), {'paymentMethod': paymentMethod});
}
// _postRequest: Bearer token from prefs, jsonEncode body, 200/201 → decoded JSON,
// error status → decoded error body, exception → {'success': false, 'message': 'Error: $e'}.
// getPaymentBalance: GET, 404 → {'success': false, 'message': ...} (callers branch without try/catch).
```

### Socket listener setup/teardown symmetry (driver)
```dart
// Source: lib/features/driver/driver_home_screen.dart:1197-1220, 511-554
// _setupSocketListeners: if (_socketListenersSetup) { off(...) x N } then on(...) x N.
// dispose: off('ride:newRequest'), off('payment:succeeded'), ... (add the 2 new events here).
// Reconnect: _connectionSubscription → _setupSocketListeners() + _emitDriverOnline().
// New listeners MUST be added in all three places (setup, dispose, re-setup is automatic via setup).
```

### Dedupe before acting (rider precedent)
```dart
// Source: lib/features/ride/ride_assigned_screen.dart:1039-1045, 1127-1133
if (!RideEventDedupe.shouldHandleEvent(source: 'socket', type: 'payment_balance_due', data: map)) return;
// New keys: 'payment_excess_cash_requested', 'payment_excess_cash_cancelled', 'payment_succeeded_settlement'.
```

### BalanceDue → stash-mid-trip / open-when-completed (rider precedent)
```dart
// Source: lib/features/ride/ride_assigned_screen.dart:2307-2335
// _rideStatus not completed → setState(_pendingBalanceDue) + orange snackbar, return.
// Completed → Navigator.push(OutstandingBalanceScreen). Receipt picks stash via consumePendingBalance().
```

### Home startup check stays online-only (do not touch)
```dart
// Source: lib/features/home/home_screen.dart:1110-1139, 1238-1277
// _checkPendingBalance: global GET → persist banner → tap opens OutstandingBalanceScreen (pay link only).
// No cash path exists here; Phase 12 MUST NOT add one.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Arrival-time `rides/:id/select-payment` sheet (cash/stripe/link) | Deleted; booking-time method display-only chip + Continue | Phase 11-03 (`5f01d0c`, 2026-09-17) | New `select-method` is a different endpoint on a different resource — no code reuse, no un-deletion |
| `paymentTiming: pay_now/pay_later` booking body | Mandatory `paymentMethod: cash\|payment_link` on every booking POST | Phase 11-01 (`1404868`) | Settlement `paymentMethod` values align with booking vocabulary |
| Balance envelope flat `paymentUrl` only | Tolerate nested `data.payment.paymentUrl` + 3 amount keys + list envelope | Phase 11-01 (`47f08ee`) | select-method response parser must be equally tolerant (shape unverified) |
| Upfront `paymentMethod is required` 400 / balance 403 via mapper | Same mapper for new endpoints | Phase 11-03 (`a45f0e7`) | Add select-method/confirm-driver-cash cases to `RideErrorMapper`, not inline copy |

**Deprecated/outdated:**
- `ApiService.selectPaymentMethod` / `ApiConstants.selectPaymentMethod` (`rides/:id/select-payment`): deprecated, arrival call sites deleted. Leave alone.

## Open Questions

1. **Exact `select-method` response envelope**
   - What we know: `payment_link` returns `paymentUrl` (per INTEGRATION-GUIDE.md); existing parsers tolerate flat + `data.payment.paymentUrl`.
   - What's unclear: top-level `success` flag? `status` value for cash selection (`pending_driver_confirm`? `balance_due` unchanged?)? amount echo?
   - Recommendation: parser tolerates all known shapes; planner adds a Wave-1 task to log the live response and pin the shape in a contract test.

2. **`confirm-driver-cash` response + side-effect events**
   - What we know: header `Authorization: Bearer <driver_token>`; rider closes on `payment:succeeded`.
   - What's unclear: does confirm return the settled ride, and does the driver ALSO get `payment:succeeded` (their existing handler resets to online — desired?) or only the rider?
   - Recommendation: driver modal pops on 200 regardless; keep existing `payment:succeeded` driver handler (resets to online) — verify on live trip it doesn't double-reset.

3. **`excessCashRequested` payload keys**
   - What we know: modal copy is "Collect Cash: £X"; analogous `payment:balanceDue` carries `{rideId, excessAmount, paymentUrl?, clientSecret?, isReminder}`.
   - What's unclear: amount key (`amount`? `excessAmount`?) and rideId key (`rideId`? `bookingId`?).
   - Recommendation: accept `excessAmount ?? amount`, rideId via `rideId/bookingId/_id/id` loop (same as `shouldHandleEvent`); log-and-pin on live trip.

4. **FCM fallback for driver cash events**
   - What we know: `NotificationType` has no cash-request/cancel types; driver FCM currently handles `rideRequest` + payment types via `FcmNotificationHandler` mixin.
   - What's unclear: does backend send FCM for `excessCashRequested` (driver in background)?
   - Recommendation: socket-only in v1 (in-car driver app is foreground); note as follow-up if backend confirms FCM types.

5. **Rider identity of the settled receipt**
   - What we know: guide says close settlement screen and navigate to rating/home on `payment:succeeded`.
   - What's unclear: whether settlement sits ON TOP of `RideCompleteScreen` (pop reveals receipt+ratting — preferred, matches balanceDue-on-top precedent) or REPLACES it.
   - Recommendation: push settlement on top of the receipt; `payment:succeeded` pops settlement back to the receipt (rating intact). Planner locks this.

## Sources

### Primary (HIGH confidence)
- `.planning/phases/12-.../INTEGRATION-GUIDE.md` — backend contract (endpoints, events, UI states)
- `lib/features/ride/outstanding_balance_screen.dart` — re-fetch-and-pop, WebView contract
- `lib/features/ride/ride_complete_screen.dart` — receipt host, `pendingBalance` auto-open, cash banner
- `lib/features/ride/ride_assigned_screen.dart` — `ride:completed` once-guard, balanceDue stash/open, FCM+socket dedupe
- `lib/features/driver/driver_home_screen.dart` — socket setup/teardown, completeRide + `confirmCashCollection`, dialog patterns
- `lib/core/services/socket_service.dart` — passthrough + `on/off` + reconnect semantics
- `lib/core/services/ride_event_dedupe.dart` — 5s type+rideId guard
- `lib/core/api_service.dart` + `lib/core/constants/api_constants.dart` — `_postRequest`, balance GETs
- `lib/core/models/outstanding_balance.dart` + `test/outstanding_balance_test.dart` — tolerant parsing precedent
- `lib/features/home/home_screen.dart` — startup online-only check (do-not-touch boundary)
- `.planning/phases/11-upfront-payments/11-01-SUMMARY.md`, `11-03-SUMMARY.md` — no-regress constraints
- `.planning/STATE.md`, `.planning/ROADMAP.md` — phase ordering (12 before 13), prior decisions

### Secondary (MEDIUM confidence)
- None — no external docs needed; all patterns are repo-internal.

### Tertiary (LOW confidence)
- Live response envelopes for the two new endpoints + `excessCashRequested` payload keys (contract prose only, unverified against live backend — flagged above).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; every library already in use for the same purposes.
- Architecture: HIGH — host screens, model, WebView, socket, dedupe, and test patterns all mapped to file:line.
- Pitfalls: HIGH — derived from in-repo comments and prior-phase fixes (succeeded-ambiguity, receipt double-push, arrival-flow deletion).

**Research date:** 2026-09-17
**Valid until:** 30 days (stable domain; only live-envelope details may refine after first device test)
