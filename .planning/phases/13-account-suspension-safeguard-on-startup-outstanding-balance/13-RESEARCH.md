# Phase 13: Account Suspension Safeguard on Startup Outstanding Balance - Research

**Researched:** 2026-09-17
**Domain:** Flutter rider-app startup gate — balance-flag parsing, UI locking, modal pay-online flow, socket unlock
**Confidence:** HIGH

## Summary

Phase 13 adds a startup suspension gate on top of the existing pending-balance system. Backend `GET /payments/balance` gains two new fields — `accountSuspended` and `allowCash` — and when `accountSuspended:true + allowCash:false`, the app must lock booking entry points and show a pay-online-only modal, unlocking on `payment:succeeded` or a clear re-fetch.

The good news: ~80% of the machinery already exists. `HomeScreen._checkPendingBalance` already calls `getGlobalPaymentBalance` on mount and resume, `OutstandingBalance.fromBalanceEnvelope` already parses the same envelope (minus the two new flags), `OutstandingBalanceScreen` already implements the exact online-only WebView + succeeded-close-out flow the modal needs, `payment:succeeded` listeners already clear the banner, and the 403 `balanceBlocked` backstop already works on both booking screens. This phase is: extend the model with 2 bools, add a suspended boolean + entry-point lock + modal on home, extend unlock to dismiss the modal, and pin it all with parser tests.

**Primary recommendation:** Implement suspension as a boolean derived from the parsed model (`isSuspended = accountSuspended && !allowCash`, tolerant to either flag alone), gate home entry points + show one non-dismissible modal reusing `OutstandingBalanceScreen` for payment, unlock via the existing `payment:succeeded` + re-fetch paths, and leave Phase 12 files untouched.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter (Material) | 3.41.7 stable | `AlertDialog` suspension modal, button disabling | Existing home patterns (`_handleRideExpiration` dialog, banner) |
| socket_io_client (via `SocketService`) | existing | `payment:succeeded` unlock trigger | Passthroughs `onPaymentSucceeded/offPaymentSucceeded` already used by home |
| shared_preferences | existing | `_pendingBalanceKey` rideId persistence | Banner survives restart; suspension rides along for free |
| flutter_test | sdk | Parser contract tests | `outstanding_balance_test.dart` + `excess_settlement_contract_test.dart` precedent |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| provider (`AuthProvider`) | existing | user/session context | No change needed; listed so planner doesn't re-wire auth |
| `PaymentWebViewScreen` | existing | Stripe checkout WebView | Reached via `OutstandingBalanceScreen`; do not invoke directly from modal |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Reuse `OutstandingBalanceScreen` for Pay-Online | New dedicated suspension screen | New screen duplicates WebView + succeeded-re-fetch logic already verified in 12-02; reuse wins |
| Reuse `ExcessSettlementSheet` for modal | `OutstandingBalanceScreen` | Settlement sheet offers Cash — forbidden at startup (`allowCash:false`); would regress 12-02's online-only startup guarantee |
| New `isSuspended` flag in `OutstandingBalance` | Separate suspension state object | Model extension (2 bools + getter) matches tolerant-parser precedent; smallest diff |

**Installation:** None — no new packages.

<phase_requirements>
## Phase Requirements (proposed — no pre-defined IDs; planner to adopt)

| ID | Description | Research Support |
|----|-------------|-----------------|
| SUSPEND-01 | Parse `accountSuspended` / `allowCash` flags from `GET /payments/balance` envelope into `OutstandingBalance` | Model extension §Pattern 1; tolerant-bool parsing; contract tests mirror `outstanding_balance_test.dart` |
| SUSPEND-02 | Lock Book + Schedule booking entry points while suspended | Home entry-point map §Pattern 2; `onPressed: null` disabled pattern from `vehicle_selection_widget.dart:904` |
| SUSPEND-03 | Suspension modal with Pay-Online WebView (online-only, no cash) | `AlertDialog barrierDismissible:false` precedent (`home_screen.dart:974`); payment via existing `OutstandingBalanceScreen` |
| SUSPEND-04 | Unlock on `payment:succeeded` / balance-clear re-fetch | Existing `_registerBalanceSocketListeners` + `_checkPendingBalance` clear paths; 12-02 pop-only-when-cleared pattern |
| SUSPEND-05 | Keep 403 create-block as backstop (verify, no behavior change) | `PaymentResult.balanceBlocked` + `_openBalanceBlocked` on both booking screens; mapper `Pay now` entry intact |
</phase_requirements>

## Architecture Patterns

### Recommended Project Structure
No new files expected except tests. Touch list:
```
lib/core/models/outstanding_balance.dart   # SUSPEND-01: 2 bool fields + getter
lib/features/home/home_screen.dart         # SUSPEND-02/03/04: flag, lock, modal, unlock
test/suspension_contract_test.dart         # NEW: flag-parsing contract tests (or extend outstanding_balance_test.dart)
```
Explicitly NOT touched: `excess_settlement_sheet.dart`, `ride_complete_screen.dart`, `driver_home_screen.dart`, `payment_service.dart` (backstop verified as-is), `socket_service.dart` (passthroughs exist).

### Pattern 1: Tolerant suspension-flag parsing on `OutstandingBalance`
**What:** Add `accountSuspended` + `allowCash` bools (default `false` / `true` = current behavior when absent) plus `isSuspended` getter. Parse tolerantly — backend bools may arrive as bool, int, or string.
**When to use:** In `fromBalanceEnvelope` (global startup envelope) and `fromBalanceDueEvent` (socket/FCM path, for consistency). `fromSelectMethodEnvelope` needs no change (live in-car flow, cash allowed there). `fromForbiddenEnvelope` needs no change (403 shape has neither flag).
**Example:**
```dart
// Source: INTEGRATION-GUIDE.md §1 envelope + outstanding_balance.dart _num precedent
static bool _flag(dynamic v, {required bool fallback}) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v?.toString().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return fallback;
}
// in fromBalanceEnvelope:
accountSuspended: _flag(m['accountSuspended'], fallback: false),
allowCash: _flag(m['allowCash'], fallback: true),
...
/// Startup gate: suspended account that may only pay online.
bool get isSuspended => accountSuspended && !allowCash;
```
`isSuspended` semantics: gate on the conjunction per guide step 3 ("Detect `accountSuspended: true` and `allowCash: false`"). Absent flags → `false && ...` → not suspended → today's behavior preserved (backward compatible with current backend).

### Pattern 2: Home entry-point lock
**What:** A `_isSuspended` bool in `_HomeScreenState`, set alongside `_pendingBalance` in `_checkPendingBalance`/`_persistPendingBalance` and cleared in `_clearPendingBalance`. While true: disable the booking entry `GestureDetector.onTap`s (search bar `home_screen.dart:1755`, airport tile `:1812`) and the `/scheduled-rides` tile (`:2010`) — either `onTap: null`-style guard or an early-return that re-shows the suspension modal. Keep the existing orange banner (it already says "Tap to pay and unlock booking").
**When to use:** Home only. Booking screens (`ride_confirmation_screen`, `confirm_booking_screen`) keep the 403 backstop rather than pre-gating — they already resolve blocks via the global endpoint in `_openBalanceBlocked`.
**Example (guard-tap, preserves layout):**
```dart
// Follows vehicle_selection_widget.dart:904 `condition ? null : (...)` disabled pattern
onTap: () {
  if (_isSuspended) { _showSuspensionModal(); return; }
  // ... existing navigation
},
```

### Pattern 3: Single-shot non-dismissible suspension modal
**What:** `AlertDialog` with `barrierDismissible: false` (precedent: `_handleRideExpiration`, `home_screen.dart:974`), title "Account Temporarily Suspended", amount + backend message + "Cash is not available after leaving the vehicle" copy, single CTA `Pay £X Online Now` → `Navigator.push(OutstandingBalanceScreen(balance: ...))`. On return: success map → `_clearPendingBalance()` (clears flag + banner + dismiss state); otherwise `_checkPendingBalance()` re-verify (exact `_openPendingBalance` pattern, `home_screen.dart:1279-1294`).
**When to use:** Show once per suspension episode via a `_suspensionModalOpen` flag, posted with `runAfterFrame` (home's established socket→nav pattern). Never stack: check flag + `ModalRoute.isCurrent`-style guard before `showDialog`.

### Pattern 4: Unlock = existing clear paths + modal dismiss
**What:** `payment:succeeded` handler in `_registerBalanceSocketListeners` already calls `_clearPendingBalance()`; extend that method (or its call sites) to also reset `_isSuspended = false` and pop the suspension dialog if open. Re-fetch clear (`data: null` in `_checkPendingBalance`) flows through the same method — no separate unlock code path.
**When to use:** Both socket-driven and resume-driven (`didChangeAppLifecycleState` → `_checkPendingBalance`) unlocks. Follow the 12-02/12-03 pop-only-if-open discipline: dismiss silently, no extra toast (the balance screen already toasts on success).

### Anti-Patterns to Avoid
- **Cash button on the startup flow:** `OutstandingBalanceScreen` must stay online-only ("Pay via Payment Link" + "Check again"). Adding cash regresses 12-02's verified constraint (`rg 'cash'` audit in 12-02-SUMMARY).
- **New socket event strings:** Unlock uses existing `payment:succeeded` passthrough only. No new backend events exist in the guide.
- **Gating inside booking screens:** Don't duplicate suspension checks in `ride_confirmation_screen`/`confirm_booking_screen` — the 403 backstop already covers suspended users who reach booking; double-gating risks breaking 11-02 toggle / 11.1-01 compaction behavior.
- **Modal on wrong route:** Don't `showDialog` from a socket callback while tracking screens are on top — home listeners are global; guard to home-visible only.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Stripe payment UI | Custom card form / Payment Sheet | Existing `OutstandingBalanceScreen` → `PaymentWebViewScreen` | Link-based checkout already wired + verified; sheet was deliberately removed app-wide |
| Socket event dedupe | Ad-hoc "already showed" booleans alone | `RideEventDedupe.shouldHandleEvent` (as in balance-due handler) | FCM + socket duplicate every balance event; dedupe is the established guard |
| Balance-cleared verification | Trust `payment:succeeded` payload alone | Authoritative `getGlobalPaymentBalance`/`getPaymentBalance` re-fetch before unlock | 12-02 proved succeeded events also fire for unrelated mid-trip captures; pop/unlock only when cleared |
| 403 error copy | New mapper entries | Existing `RideErrorInfo(title: 'Clear balance to continue', actionLabel: 'Pay now')` | Backstop copy already exists (`error_display_helper.dart:124-132`); unchanged |

**Key insight:** Suspension is a presentation layer (lock + modal + unlock) over the already-built balance pipeline. Every backend interaction it needs — global GET, per-ride GET, WebView, succeeded event, 403 block — exists and is tested. The only new parsing is two booleans.

## Common Pitfalls

### Pitfall 1: Suspension modal double-show / stacking
**What goes wrong:** `payment:balanceDue` socket + FCM reminder + resume re-check each trigger `showDialog` → stacked or orphaned dialogs.
**Why it happens:** Three independent entry paths (`_checkPendingBalance`, balance-due socket, FCM tap) all observe the same suspension.
**How to avoid:** `_suspensionModalOpen` flag + `RideEventDedupe` guard + show only when home route is current. Single show site (called from all three paths) enforcing the guard.
**Warning signs:** `showDialog` called directly inside a socket/FCM callback without a flag check.

### Pitfall 2: Unlocking on the wrong `payment:succeeded`
**What goes wrong:** A mid-trip base-fare capture emits `payment:succeeded`; naive handler unlocks booking while the excess balance is still owed.
**Why it happens:** Backend emits the event for multiple payment kinds (documented in `outstanding_balance_screen.dart:53-58`).
**How to avoid:** Copy the verified pattern: on succeeded → authoritative re-fetch → unlock only when `data == null` or `status == succeeded`; otherwise refresh amount and stay locked.
**Warning signs:** Handler calls `_clearPendingBalance()` unconditionally on any succeeded payload.

### Pitfall 3: Modal survives unlock / blocks home after payment
**What goes wrong:** User pays via WebView, balance clears, but the non-dismissible modal is still up with no way out except the (now stale) pay button.
**Why it happens:** `barrierDismissible: false` + unlock path doesn't hold the dialog context.
**How to avoid:** Track dialog context (12-03 `_excessCashDialogOpen` + stored-context precedent) and pop-if-open in the unlock path; also handle the modal's own push-return (`_openPendingBalance` success → clear).
**Warning signs:** `showDialog` return value / context not stored anywhere.

### Pitfall 4: Regressing Phase 12 live settlement or Phase 11 booking
**What goes wrong:** Shared-model edit breaks `ExcessSettlementSheet` parsing, or booking-screen edits disturb the 11-02 toggle / 11.1-01 compact CTA.
**Why it happens:** `OutstandingBalance` is shared across startup, receipt sheet, and 403 paths.
**How to avoid:** Additive-only model change (new optional fields with safe defaults); zero edits to `excess_settlement_sheet.dart`, `ride_complete_screen.dart`, `driver_home_screen.dart`, booking screens, `payment_service.dart`. Verify with `flutter analyze` + full `flutter test` + `rg 'cash'` audit on `outstanding_balance_screen.dart` (must show no cash button, per 12-02 verification).
**Warning signs:** Diff touches any Phase 12 file or the booking bottom-sheet CTA widgets.

### Pitfall 5: `allowCash:true` future shape mis-gated
**What goes wrong:** Backend later sends `accountSuspended:true + allowCash:true` (e.g. in-car variant); strict `accountSuspended`-only check would show the online-only modal and hide a legitimate cash option.
**Why it happens:** Gating on one flag instead of the conjunction.
**How to avoid:** Gate on `isSuspended = accountSuspended && !allowCash`. If suspended with cash allowed (not in current contract), fall back to today's banner behavior — note as open question, don't build for it.
**Warning signs:** `if (accountSuspended)` without consulting `allowCash`.

### Pitfall 6: Resume-loop modal nag
**What goes wrong:** Every app resume re-fires `_checkPendingBalance` → re-shows modal even while user is mid-payment in the WebView pushed over home.
**Why it happens:** `didChangeAppLifecycleState(resumed)` unconditionally re-checks.
**How to avoid:** Skip modal show when a balance/payment route is already on top (`_suspensionModalOpen` or route check); the in-flight `OutstandingBalanceScreen` owns its own succeeded handling.
**Warning signs:** Modal reappears over the open payment screen after background/foreground cycle.

## Code Examples

Verified patterns from the codebase (not external docs — this phase is entirely in-repo):

### Global balance check + banner set/clear (extend for suspension)
```dart
// Source: lib/features/home/home_screen.dart:1110-1139 (_checkPendingBalance)
final res = await _apiService.getGlobalPaymentBalance();
if (res['success'] == true) {
  if (res['data'] == null) { await _clearPendingBalance(); return; }  // clear → unlock
  final parsed = OutstandingBalance.fromBalanceEnvelope(res, '');
  if (parsed != null && parsed.isOwed && parsed.rideId.isNotEmpty && mounted) {
    await _persistPendingBalance(parsed);  // + set _isSuspended = parsed.isSuspended; maybe show modal
    return;
  }
  ...
}
```

### Balance-screen open with post-payment re-verify (modal CTA target)
```dart
// Source: lib/features/home/home_screen.dart:1279-1294 (_openPendingBalance)
final result = await Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => OutstandingBalanceScreen(balance: balance)),
);
if (result is Map && result['success'] == true) {
  await _clearPendingBalance();
} else {
  await _checkPendingBalance();  // paid outside the screen → re-verify
}
```

### Succeeded handler with rideId match (unlock trigger shape)
```dart
// Source: lib/features/home/home_screen.dart:1272-1276 + outstanding_balance_screen.dart:48-58
_socketService.onPaymentSucceeded((data) {
  // EXTEND: authoritative re-fetch first (12-02 pattern), unlock only when cleared;
  // then _clearPendingBalance() + dismiss suspension modal if open.
  _clearPendingBalance();
});
```

### 403 backstop (SUSPEND-05 — verify unchanged, both booking screens)
```dart
// Source: ride_confirmation_screen.dart:665-670, confirm_booking_screen.dart:139-144
if (result.isBalanceBlocked) {
  _openBalanceBlocked(rideId: ..., amount: ..., message: result.error);
}
// + PaymentService.bookRideWithPayment:299-314 returns PaymentResult.balanceBlocked on 403
```

### Contract-test template for new flags
```dart
// Source: test/outstanding_balance_test.dart:77-92 (global-shape test) — mirror for flags:
final b = OutstandingBalance.fromBalanceEnvelope({'success': true, 'data': {
  'rideId': '6aabc3476a4199e81748403e', 'excessAmount': 2.50,
  'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_...',
  'allowCash': false, 'accountSuspended': true, 'status': 'balance_due',
  'message': '...',
}}, '');
expect(b!.isSuspended, isTrue);
// + absent-flags test → isSuspended false; allowCash:true → false; string/int variants
```

## State of the Art

| Old Approach (pre-13) | Current Approach (Phase 13) | When Changed | Impact |
|---|---|---|---|
| Global balance → banner only, booking always allowed | Global balance + flags → banner + entry lock + modal | This phase (backend 2026-09-17 brief) | Suspended users cannot start new bookings client-side |
| 403 on create as sole booking block | 403 retained as backstop behind startup gate | This phase (guide open question → keep both) | Double protection; offline/race cases still caught at create |
| `OutstandingBalance` amount/status/url only | + `accountSuspended`/`allowCash` + `isSuspended` | This phase | Parsers stay backward compatible (safe defaults) |

**Deprecated/outdated:**
- Phase 12's `INTEGRATION-GUIDE.md` startup-balance section: superseded by this phase dir's `INTEGRATION-GUIDE.md` (stated at its top). Live trip-completion settlement (§2-3) stays Phase 12's — do not re-implement here.

## Open Questions

1. **Exact "Book Ride" / "Schedule Ride" buttons to lock**
   - What we know: Guide says lock both buttons, but home has no literal buttons — entries are the search-bar `GestureDetector`, airport tile, and `/scheduled-rides` tile. The literal Confirm/Schedule CTAs live on the two booking screens (11.1-01 compact bottom sheet).
   - What's unclear: Whether backend expects booking screens reachable-but-403-blocked, or fully pre-gated.
   - Recommendation: Lock home entries + modal (SUSPEND-02/03); leave booking screens on the 403 backstop (SUSPEND-05). Cheapest, no 11.x regression risk. Planner: 1 plan, home-only + tests.

2. **Modal auto-show vs banner-tap-only**
   - What we know: Guide says "Display a prominent modal" on startup detection. Auto-showing risks nag (Pitfall 6); banner-tap-only risks users missing the gate (but entries are locked, so they can't proceed anyway).
   - What's unclear: Backend/product preference.
   - Recommendation: Auto-show once per suspension episode (flag-guarded), banner persists as re-entry. Locked entries re-show the modal on tap so users are never dead-ended.

3. **Live `accountSuspended`/`allowCash` envelope shape**
   - What we know: Contract shape from the 2026-09-17 backend brief; live values unverified (same caveat as all Phase 12 tolerant parsing).
   - What's unclear: Bool-vs-string encoding, whether flags also appear on per-ride GET or socket events.
   - Recommendation: Tolerant `_flag` parser (bool/int/string) + contract tests pinning the brief's exact JSON; first device test logs the real `GET /payments/balance` body and confirms.

## Sources

### Primary (HIGH confidence)
- `.planning/phases/13-.../INTEGRATION-GUIDE.md` — backend contract §1 (this phase's scope); §2-3 marked Phase 12's
- `lib/features/home/home_screen.dart` — `_checkPendingBalance:1110`, `_openPendingBalance:1279`, `_registerBalanceSocketListeners:1238`, expiration dialog `:974`, banner `:1649`, entry points `:1755/:1812/:2010`
- `lib/core/models/outstanding_balance.dart` — `fromBalanceEnvelope:33`, `fromForbiddenEnvelope:144`, `fromBalanceDueEvent:161`
- `lib/features/ride/outstanding_balance_screen.dart` — online-only WebView + succeeded re-fetch close-out
- `lib/core/services/payment_service.dart:299-314` — 403 `balanceBlocked` backstop (unchanged)
- Phase 12 `12-01/12-02/12-03-SUMMARY.md` — no-regress constraints (startup online-only; receipt sheet; driver modal)
- `lib/core/api_service.dart:1121` `getGlobalPaymentBalance`, `lib/core/constants/api_constants.dart:123` `paymentBalanceGlobal` — transport exists, no change
- `test/outstanding_balance_test.dart`, `test/excess_settlement_contract_test.dart` — contract-test precedent
- `lib/core/models/error_display_helper.dart:124-132` — existing 403 `Pay now` mapper entry

### Secondary (MEDIUM confidence)
- Booking-screen 403 handlers (`ride_confirmation_screen.dart:665-757`, `confirm_booking_screen.dart:139-144`) + 11.1-01 compact CTAs — read for gating boundaries; no doc verification needed (in-repo fact)

### Tertiary (LOW confidence)
- None. No web research needed — pure in-repo integration phase against a backend brief. No `Context7`/docs lookup applies (Flutter Material patterns already established in-repo).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new libraries; all reuse verified in-repo
- Architecture: HIGH — exact file/line anchors for every requirement; precedents for dialog, lock, unlock, tests
- Pitfalls: HIGH — derived from Phase 12 summaries' verified issues + guide's own open questions

**Project context notes:** No `CLAUDE.md` in repo root; no `.agents/skills/` directory — followed existing Flutter patterns in touched files per brief. No `*-CONTEXT.md` in phase dir (only `INTEGRATION-GUIDE.md` + `.gitkeep`) — no User Constraints section. No `.planning/config.json` — Validation Architecture section omitted per researcher protocol.
**Research date:** 2026-09-17
**Valid until:** 2026-10-17 (stable in-repo domain; only backend live-shape verification outstanding)
