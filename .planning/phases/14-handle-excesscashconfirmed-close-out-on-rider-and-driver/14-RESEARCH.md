# Phase 14: handle-excessCashConfirmed-close-out-on-rider-and-driver - Research

**Researched:** 2026-09-18
**Domain:** Flutter socket-event close-out (rider settlement sheet + driver Collect-Cash modal)
**Confidence:** HIGH

## Summary

`payment:excessCashConfirmed` (`{rideId, excessAmount, message}`) is verified UNHANDLED — zero hits in `lib/` (confirmed by grep this session). It is the final leg of the Phase 12 driver-cash round-trip: rider sits in `ExcessSettlementSheet` waitingCash state, driver sits in Collect-Cash modal. Both need a close-out handler.

The implementation is small and fully precedent-bound. Every pattern needed already exists in the touched files: SocketService colon-camelCase passthroughs (`socket_service.dart:690-708`), rider `_settled`-guarded authoritative `_refresh(fromEvent:true)` (`excess_settlement_sheet.dart:56-125`), driver `_excessCashDialogOpen` flag + stored dialog context + `_closeExcessCashDialogIfOpen` (`driver_home_screen.dart:2571-2667`), shared `_handleExcessCashRequest` with no `_currentRideId` gate (`driver_home_screen.dart:234-253`), canonical FCM↔socket dedupe (`fcm_service.dart:110-119`, `ride_event_dedupe.dart`), and reconnect re-registration via `_setupSocketListeners` on `connectionStatus` (`driver_home_screen.dart:331-358, 1256-1283`).

**Primary recommendation:** Socket-only v1 (no FCM type exists for confirmed) — add `on/offExcessCashConfirmed` passthroughs, wire rider waiting-state exit + driver modal-close behind `RideEventDedupe` + settled/dialog-open guards, tolerant to a co-fired `payment:succeeded` (either event closes, guards make the second a no-op).

<phase_requirements>
## Phase Requirements

Proposed IDs (no pre-defined IDs — planner uses these):

| ID | Description | Research Support |
|----|-------------|-----------------|
| CONFIRM-01 | Socket passthrough + dedupe for `payment:excessCashConfirmed` | SocketService passthrough pattern, canonical dedupe key, off-symmetry |
| CONFIRM-02 | Rider exits waitingCash state with settled confirmation on confirmed | `ExcessSettlementSheet` `_settled` + `_refresh(fromEvent:true)` pattern |
| CONFIRM-03 | Driver closes Collect-Cash modal + toast on confirmed | `_closeExcessCashDialogIfOpen` + `_showExcessCashDialog` confirm-success toast pattern |
| CONFIRM-04 | No double close-out when `payment:succeeded` also fires | Settled-flag reuse from 404 fix; driver succeeded-gate analysis |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| socket_io_client (via SocketService) | pinned in pubspec | `payment:*` event transport | All Phase 12 excess events already flow through it; raw strings live only in passthroughs |
| RideEventDedupe | in-repo (`lib/core/services/ride_event_dedupe.dart`) | 5s type+rideId exactly-once guard | Shared FCM/socket contract; Phase 12 + no-modal fix depend on it |
| CustomSnackbar | in-repo (`lib/core/widgets/custom_snackbar.dart`) | success/info toasts | Both rider sheet and driver modal already use it |
| flutter_test | pinned in pubspec | dedupe/contract regression tests | `test/excess_cash_modal_transport_test.dart` is the template to extend |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| AudioService | in-repo | notification ring | Only if confirmed needs a ring — recommendation: NO ring (settlement already rang on request; confirmed is a resolution, toast suffices) |
| FcmService NotificationType | in-repo | FCM type constants + canonical mapper | NOT needed for v1 — no `excess_cash_confirmed` type exists; only extend if backend later adds one |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| socket-only v1 | FCM `excess_cash_confirmed` type + canonical mapper + mixin cases | Adds tray backup for backgrounded apps, but backend brief shows socket only; Phase 12 shipped socket passthroughs first and added FCM later via debug fix — follow that sequence |
| authoritative re-fetch on rider confirmed | direct pop using event `message` | Faster + thank-you copy, but skips the cleared-balance proof that guards against mid-trip-capture confusion; tolerant hybrid recommended below |
| new settled-state machine | reuse `_settled` bool + `_excessCashDialogOpen` flag | New machine is over-engineering; existing flags already solve double-pop/double-toast |

**Installation:** None — no new packages.

## Architecture Patterns

### Recommended Project Structure
No new files. Touch exactly:
```
lib/core/services/socket_service.dart        # on/offExcessCashConfirmed passthrough
lib/features/ride/excess_settlement_sheet.dart # confirmed listener + waiting exit
lib/features/driver/driver_home_screen.dart  # confirmed listener + modal close + toast
test/excess_cash_confirmed_closeout_test.dart # dedupe/settled regression (extend transport-test pattern)
```

### Pattern 1: Socket passthrough with off-symmetry
**What:** Raw event string lives ONLY in SocketService; screens call `on/offExcessCashConfirmed`.
**When to use:** Always for this event — STATE.md [12-03] decision mandates it.
**Example:**
```dart
// Source: lib/core/services/socket_service.dart:690-708 (existing requested/cancelled)
/// Driver confirmed cash receipt (Phase 14 INTEGRATION-GUIDE.md §2).
/// Payload: {rideId, excessAmount, message}.
void onExcessCashConfirmed(void Function(dynamic) handler) {
  on('payment:excessCashConfirmed', handler);
}

void offExcessCashConfirmed() {
  off('payment:excessCashConfirmed');
}
```
Wire off-symmetry in BOTH `dispose` and the reconnect re-setup block (`driver_home_screen.dart:1279-1280` pattern; rider sheet `dispose` at `excess_settlement_sheet.dart:50-54`).

### Pattern 2: Rider tolerant close-out (confirmed OR succeeded, settled flag guards)
**What:** `_onExcessCashConfirmed` mirrors `_onPaymentSucceeded` (`excess_settlement_sheet.dart:56-72`): rideId-match → `RideEventDedupe.shouldHandleEvent(source:'socket', type:'payment_excess_cash_confirmed', data:map)` → `if (!mounted || _settled) return` → authoritative `_refresh(fromEvent:true)`.
**When to use:** Rider sheet — always.
**Why tolerant:** Open question (does backend ALSO emit `payment:succeeded` for this flow?) is unanswerable from client code. Both handlers sharing `_settled` + `_refresh` makes order irrelevant: whichever fires first pops, the second hits `if (_settled) return` at handler entry AND at `_refresh` entry (`excess_settlement_sheet.dart:80`). Recommend passing the event's thank-you `message` through to the success snackbar so confirmed shows backend copy ("Thank you!") while succeeded keeps existing copy — implement as optional param on `_refresh` or a pre-set field, not a second pop path.
**Example:**
```dart
// Source: lib/features/ride/excess_settlement_sheet.dart:56-72 (mirror this)
void _onExcessCashConfirmed(dynamic data) {
  final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  final id = (map['rideId'] ?? map['bookingId'] ?? map['_id'])?.toString();
  if (id != null && id != widget.rideId) return;
  if (!RideEventDedupe.shouldHandleEvent(
    source: 'socket',
    type: 'payment_excess_cash_confirmed',
    data: map,
  )) {
    return;
  }
  if (!mounted || _settled) return;
  _refresh(fromEvent: true); // settled-flag reuse: succeeded race is a no-op
}
```

### Pattern 3: Driver modal close + single toast, NOT gated on _currentRideId
**What:** Confirmed handler uses the event's own rideId (via `_socketRideId`), never `_currentRideId` — the no-modal fix (`driver-excess-cash-no-modal.md`) proved `_currentRideId` is null after online-pay completion, before the rider selects cash. Close via `_closeExcessCashDialogIfOpen()` then toast once.
**When to use:** Driver home screen — always.
**Dedupe + toast-once:** `RideEventDedupe.shouldHandleEvent(type:'payment_excess_cash_confirmed')` kills socket duplicates; the `_excessCashDialogOpen` flag + a small `_excessCashConfirmToastShown`-style settled guard (or reuse dialog-open transition) kills confirmed-vs-succeeded double toast. Note the existing `payment:succeeded` driver handler (`driver_home_screen.dart:1312-1341`) is gated on `rideId == _currentRideId`, which is null in the excess flow — so it will NOT double-fire here today, but the guard must still exist because backend behavior may change.
**Example:**
```dart
// Source: lib/features/driver/driver_home_screen.dart:1406-1416 + 2659-2667 (combine)
_socketService.onExcessCashConfirmed((data) {
  if (!mounted) return;
  final map = data is Map ? Map<String, dynamic>.from(data as Map) : <String, dynamic>{};
  if (!RideEventDedupe.shouldHandleEvent(
    source: 'socket',
    type: 'payment_excess_cash_confirmed',
    data: map,
  )) {
    return;
  }
  // No _currentRideId gate — event rideId is authoritative (no-modal fix).
  _closeExcessCashDialogIfOpen();
  CustomSnackbar.show(context, message: 'Cash excess payment confirmed!', type: SnackbarType.success);
});
```

### Anti-Patterns to Avoid
- **Raw `payment:excessCashConfirmed` string in screens:** violates [12-03] decision; string lives in SocketService only.
- **Gating driver confirmed on `_currentRideId`:** repeats root cause #1 of the no-modal bug; event rideId is authoritative.
- **Popping rider sheet on the event alone without `_settled`/re-fetch:** repeats the 404-fix lesson; mid-trip base-fare captures fire `payment:succeeded` too, and a bare pop can't distinguish them.
- **Re-checking the dedupe key in a second layer (service + screen):** the no-modal fix proved double-consumption makes the second path dead; socket-only v1 has exactly one consumer per screen, so one `shouldHandleEvent` call per handler.
- **Adding an FCM `excess_cash_confirmed` type speculatively:** no backend evidence; ship socket-only, extend canonically if the backend adds it.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| FCM+socket double delivery | custom timestamp/flag logic | `RideEventDedupe.shouldHandleEvent` + `canonicalExcessCashDedupeType` if FCM ever added | 5s window + rideId keying + tested exactly-once contract |
| success/error copy for mapper failures | new snackbar system | `CustomSnackbar` + `RideErrorMapper`/`ErrorDisplayHelper` | Both screens already use them; no new failure path exists (confirmed is success-only) |
| socket reconnect re-registration | manual re-subscribe timers | existing `_setupSocketListeners` + `connectionStatus` re-setup (`driver_home_screen.dart:331-358`) | New listener must be registered inside `_setupSocketListeners` so reconnect re-arms it |
| test infra | new harness | extend `test/excess_cash_modal_transport_test.dart` pattern | Canonical-key + exactly-once + settled-guard tests already proven (49 green) |

**Key insight:** Phase 14 is a wiring phase, not a design phase. All guards (dedupe, settled, dialog-open, off-symmetry) exist — the planner should frame tasks as "mirror the adjacent handler," not "design close-out."

## Common Pitfalls

### Pitfall 1: Reconnect drops the confirmed listener
**What goes wrong:** Handler works until a socket drop, then never fires again.
**Why it happens:** Listener registered outside `_setupSocketListeners`, which is the only block re-run on `connectionStatus` reconnect (`driver_home_screen.dart:336-341`).
**How to avoid:** Register `onExcessCashConfirmed` inside `_setupSocketListeners` next to requested/cancelled; add `offExcessCashConfirmed` to both the dispose block AND the re-setup preamble (`lines 1279-1280` pattern).
**Warning signs:** Works on fresh launch, silent after background/resume.

### Pitfall 2: Double close-out if backend emits succeeded too
**What goes wrong:** Double `Navigator.pop` (popping the receipt underneath) or double toast.
**Why it happens:** Two success events for one state change, no shared guard.
**How to avoid:** Rider: `_settled` checked at handler entry, `_refresh` entry, and post-fetch (`excess_settlement_sheet.dart:67,80,84`). Driver: toast gated on a confirm-settled guard, not just modal-open (modal may already be closed by the other event).
**Warning signs:** `payment:succeeded` + `excessCashConfirmed` both in the same socket log window.

### Pitfall 3: Rider sheet pops the wrong ride's sheet
**What goes wrong:** Confirmed for ride A closes the sheet for ride B.
**Why it happens:** Missing rideId-match before acting.
**How to avoid:** Copy the `id != widget.rideId → return` guard (`excess_settlement_sheet.dart:59`); driver side uses event rideId for confirm, never assumes current.
**Warning signs:** Multi-ride QA sessions, stale sheets.

### Pitfall 4: Driver toast contradicts the existing succeeded toast
**What goes wrong:** "Cash excess payment confirmed!" + "Payment completed! Ride finalized." both fire, confusing the driver.
**Why it happens:** Both handlers toast unconditionally.
**How to avoid:** Confirmed toast is the excess-flow signal; succeeded handler's `_currentRideId` gate already excludes the excess flow today, but add the settled guard so any future backend change keeps exactly-one toast.
**Warning signs:** Two toasts in one confirm action during device QA.

### Pitfall 5: `flutter analyze` noise mistaken for new issues
**What goes wrong:** Plan verification stalls on pre-existing infos.
**Why it happens:** Both touched files carry pre-existing infos (`use_build_context_synchronously` in sheet + driver, `withOpacity` in receipt-adjacent code) — documented in 12-02/12-03 summaries via `git stash` baseline.
**How to avoid:** Verify with baseline comparison (`git stash` + analyze), not zero-info absolutism.
**Warning signs:** Infos on untouched lines.

## Code Examples

Verified patterns from repo sources (not external docs — domain is in-repo conventions):

### Socket passthrough + screen registration + off-symmetry
```dart
// Source: lib/core/services/socket_service.dart:690-708,
//         lib/features/driver/driver_home_screen.dart:1406-1416, 1279-1280
_socketService.onExcessCashConfirmed((data) { /* normalize → dedupe → act */ });
// dispose + reconnect preamble:
_socketService.offExcessCashConfirmed();
```

### Rider authoritative refresh with settled guard (reuse as-is)
```dart
// Source: lib/features/ride/excess_settlement_sheet.dart:79-125
Future<void> _refresh({bool fromEvent = false}) async {
  if (_settled) return;
  // getPaymentBalance → status=='succeeded' → snackbar + _settled=true + pop
  // 404 + fromEvent → snackbar + _settled=true + pop
  // still-owed → setState fresh amount, stay open
}
```

### Driver silent modal close (reuse as-is)
```dart
// Source: lib/features/driver/driver_home_screen.dart:2659-2667
void _closeExcessCashDialogIfOpen() {
  if (!_excessCashDialogOpen) return;
  _excessCashDialogOpen = false;
  final dialogCtx = _excessCashDialogContext;
  _excessCashDialogContext = null;
  if (dialogCtx != null && mounted) {
    Navigator.pop(dialogCtx);
  }
}
```

### Dedupe regression test template
```dart
// Source: test/excess_cash_modal_transport_test.dart:36-70
// Extend with: confirmed-vs-succeeded same-ride second-skips;
// different-ride still-flows; settled-guard single-pop.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `_currentRideId`-gated excess handlers | event-rideId authoritative, no gate | 2026-09-18 no-modal fix | Phase 14 driver handler must NOT gate |
| manual `_refresh()` after WebView success | `_refresh(fromEvent:true)` + `_settled` | 2026-09-17 404 fix | Phase 14 rider handler reuses both |
| socket-only excess transport | socket + FCM with canonical dedupe key | 2026-09-18 no-modal fix | Phase 14 stays socket-only v1 (no confirmed FCM type exists); extend canonically if added |
| succeeded closes driver modal (gated) | same, silent before reset-to-online | Phase 12 12-03 | Confirmed handler coexists; guards prevent double |

**Deprecated/outdated:** None. Do not touch `selectPaymentMethod` (deprecated, [12-01] decision), `OutstandingBalanceScreen` cash UI (online-only, 12-02), or arrival select-payment (deleted, 11-03).

## Open Questions

1. **Does the backend ALSO emit `payment:succeeded` for the driver-cash-confirm flow?**
   - What we know: Rider sheet's succeeded handler exists precisely because succeeded fires for online settlement AND mid-trip base captures; driver succeeded handler resets to online. INTEGRATION-GUIDE.md tells Phase 14 to "determine whether both fire."
   - What's unclear: Live backend behavior — unverifiable from client code.
   - Recommendation: Tolerant handling (either event closes, `_settled`/dialog guards make the second a no-op). Device QA should log both events during one cash-confirm to pin the answer; no code branch should assume exactly-one.

2. **Is there an FCM `excess_cash_confirmed` type?**
   - What we know: `NotificationType` has `excessCashRequested`/`excessCashCancelled` only; brief shows socket only; grep shows zero confirmed references anywhere.
   - What's unclear: Whether backend will add one later.
   - Recommendation: Socket-only v1 like Phase 12 transport did. If added later: `NotificationType.excessCashConfirmed` + `canonicalExcessCashDedupeType` case + mixin cases + screen forwarding, mirroring the no-modal fix exactly.

3. **Should rider confirmed show the event `message` or the existing "Excess paid successfully!" copy?**
   - What we know: Event carries `"Driver confirmed cash receipt for excess balance. Thank you!"`; existing succeeded copy is `"Excess paid successfully! Your ride is fully settled."`
   - What's unclear: Backend copy stability (12-02 used tolerant substring matching for unverified copy).
   - Recommendation: Prefer event `message` when non-empty (faster UX signal + thank-you per guide), fallback to existing copy. Display verbatim, never substring-match success copy.

## No-Regress Constraints (from Phase 12 + debug fixes)

- Startup `OutstandingBalanceScreen` untouched (online-only, no cash UI).
- Deprecated `selectPaymentMethod` untouched; zero new `select-payment` references.
- Raw `payment:excessCash*` strings only in SocketService passthroughs.
- `payment:succeeded` rider pop-only-when-cleared semantics preserved; driver reset-to-online flow unchanged.
- Exactly-once dedupe keys: `payment_excess_cash_confirmed` (new) must not collide with `payment_excess_cash_requested` / `payment_excess_cash_cancelled` / `payment_succeeded_settlement`.
- `flutter analyze` verified via baseline comparison; contract/transport tests green.

## Sources

### Primary (HIGH confidence)
- `lib/features/ride/excess_settlement_sheet.dart` — rider waiting state, settled guard, authoritative refresh
- `lib/features/driver/driver_home_screen.dart` — shared excess handler, modal open/close, succeeded auto-close, reconnect re-registration
- `lib/core/services/socket_service.dart` — passthrough + off-symmetry pattern
- `lib/core/services/fcm_service.dart` — NotificationType inventory (no confirmed type), canonical dedupe, sound policy
- `lib/core/services/ride_event_dedupe.dart` — 5s type+rideId contract
- `.planning/phases/14-*/INTEGRATION-GUIDE.md` — backend contract + scope
- `.planning/debug/resolved/driver-excess-cash-no-modal.md` — exactly-once/no-gate patterns
- `.planning/debug/resolved/balance-paid-spurious-404-message.md` — settled-flag pattern
- `.planning/phases/12-*/12-0{1,2,3}-SUMMARY.md` — no-regress constraints

### Secondary (MEDIUM confidence)
- `lib/features/ride/ride_complete_screen.dart` — receipt hosting, balanceDue listener (adjacent pattern reference)
- `test/excess_cash_modal_transport_test.dart` — test template to extend

### Tertiary (LOW confidence)
- None. The `payment:succeeded` co-fire question is explicitly flagged as needing live-device verification, not answered here.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all in-repo, version-pinned, precedent-bound; no new packages
- Architecture: HIGH - every handler mirrors an adjacent, reviewed, device-fixed handler
- Pitfalls: HIGH - drawn from two resolved debug docs on these exact files

**Research date:** 2026-09-18
**Valid until:** 30 days (stable in-repo domain, no external deps)

**Project skills:** `.agents/skills/` does not exist in repo — no project skill patterns to account for. Followed existing Flutter patterns in touched files per brief.
**Project instructions:** No CLAUDE.md in repo root (verified) — followed brief + STATE.md decisions.
**CONTEXT.md:** None exists in phase dir — no locked user decisions to honor.
