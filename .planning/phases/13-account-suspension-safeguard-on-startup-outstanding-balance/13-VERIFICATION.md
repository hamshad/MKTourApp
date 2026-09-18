---
phase: 13-account-suspension-safeguard-on-startup-outstanding-balance
verified: 2026-09-18T07:30:00Z
status: passed
score: 7/7 must-haves verified
---

# Phase 13: Account Suspension Safeguard on Startup Outstanding Balance Verification Report

**Phase Goal:** Startup suspension gate — on GET /payments/balance with accountSuspended:true + allowCash:false, lock Book/Schedule buttons and show pay-online-only modal; unlock on payment:succeeded. Live in-car settlement stays in Phase 12.
**Verified:** 2026-09-18T07:30:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Startup GET /payments/balance envelope with accountSuspended:true + allowCash:false parses to isSuspended true | ✓ VERIFIED | `outstanding_balance.dart:31` getter `accountSuspended && !allowCash`; parsed at `:82-83` (envelope) and `:189-190` (socket/FCM event); contract test "brief exact §1 JSON" passes (6/6 green) |
| 2 | Envelope without suspension flags parses to isSuspended false (today's behavior preserved) | ✓ VERIFIED | Safe fallbacks `_flag(..., fallback:false/true)` at `:82-83`; backward-compat + conjunction tests pass |
| 3 | 403 booking block path still returns PaymentResult.balanceBlocked on both booking screens | ✓ VERIFIED | `payment_service.dart:299,309` returns `balanceBlocked`; `confirm_booking_screen.dart:139,246` + `ride_confirmation_screen.dart:665` call `_openBalanceBlocked` on `isBalanceBlocked`; zero edits to these files (diff shows only model + home + test) |
| 4 | Suspended user cannot start a booking from home (search bar, airport tile, scheduled tile locked or re-show modal) | ✓ VERIFIED | Three guards first-statement in onTap: search bar `:1944`, airport tile `:2005`, scheduled tile `:2208` — each `if (_isSuspended) { _showSuspensionModal(); return; }`, existing navigation preserved below |
| 5 | Suspended user sees a non-dismissible 'Account Temporarily Suspended' modal with amount and a single Pay-Online CTA (no cash option) | ✓ VERIFIED | `_showSuspensionModal` `:1371-1479`: `barrierDismissible:false` (`:1382`), title 'Account Temporarily Suspended', amount label `£X.XX`, backend message + 'Cash is not available after leaving the vehicle', single CTA `Pay £X Online Now` → `OutstandingBalanceScreen(balance:...)`; single-show-site `_maybeShowSuspensionModal` (`:1365`) with `_suspensionModalOpen` flag + `ModalRoute.isCurrent` guard + `runAfterFrame` posting; no cash button added to `outstanding_balance_screen.dart` (only pre-existing socket listener + fallback string) |
| 6 | Tapping Pay opens OutstandingBalanceScreen WebView flow; success clears banner, unlocks entries, dismisses modal | ✓ VERIFIED | Modal CTA pushes `OutstandingBalanceScreen(balance: balance)`, on return success map → `_clearPendingBalance()` else `_checkPendingBalance()` re-verify; `_clearPendingBalance` resets `_isSuspended=false`, nulls `_pendingBalance`, silently pops modal via `_closeSuspensionModalIfOpen` |
| 7 | payment:succeeded unlocks only after authoritative re-fetch shows balance cleared (no unlock on unrelated captures) | ✓ VERIFIED | `onPaymentSucceeded` handler re-fetches `getGlobalPaymentBalance` first; unlocks only on `data == null` or `status == succeeded`; still-owed → refresh `_pendingBalance`/`_isSuspended` in memory and stay locked; resume path funnels through same `_clearPendingBalance` — no separate unlock path |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | --------- | ------ | ------- |
| `lib/core/models/outstanding_balance.dart` | accountSuspended/allowCash fields + isSuspended getter + tolerant flag parser | ✓ VERIFIED | Fields `:13-14`, getter `:31`, `_flag` helper `:36-45`, wired at `:82-83` + `:189-190`; succeeded branches default not-suspended; `fromSelectMethodEnvelope`/`fromForbiddenEnvelope` untouched |
| `test/suspension_contract_test.dart` | Flag-parsing contract tests pinning INTEGRATION-GUIDE.md §1 JSON | ✓ VERIFIED | 123 lines (min 40); 6 cases: exact brief JSON, backward compat, conjunction, string/int tolerance, socket event, succeeded; `flutter test` 6/6 passed |
| `lib/features/home/home_screen.dart` | Suspension flag + entry locks + single-shot modal + unlock wiring | ✓ VERIFIED | `_isSuspended` (`:77`) + `_suspensionModalOpen` (`:78`); set in `_persistPendingBalance` (`:1244`), per-ride fallback (`:1330`), FCM/socket paths; reset in `_clearPendingBalance`; 3 entry guards + modal show site + hardened succeeded handler + silent dismiss; `flutter test` on contract file green |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `test/suspension_contract_test.dart` | `lib/core/models/outstanding_balance.dart` | `fromBalanceEnvelope` with brief's exact JSON | WIRED | Test imports model, calls `fromBalanceEnvelope`/`fromBalanceDueEvent` with §1 JSON; passes |
| `lib/features/home/home_screen.dart` | `lib/core/models/outstanding_balance.dart` | `parsed.isSuspended` sets `_isSuspended` | WIRED | `rg isSuspended` hits `:1170` (startup check), `:1241/:1244` (persist), `:1330` (fallback); all write sites set from parsed model |
| `lib/features/home/home_screen.dart` | `lib/features/ride/outstanding_balance_screen.dart` | modal CTA pushes OutstandingBalanceScreen, result clears balance | WIRED | `OutstandingBalanceScreen(balance: balance)` in modal CTA + `_openPendingBalance`; success → `_clearPendingBalance()`, else `_checkPendingBalance()` re-verify |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| SUSPEND-01 | 13-01 | Parse accountSuspended/allowCash flags into OutstandingBalance | ✓ SATISFIED | Tolerant `_flag` parser + contract tests, all green |
| SUSPEND-02 | 13-02 | Lock Book + Schedule booking entry points while suspended | ✓ SATISFIED | 3 home entry guards re-show modal |
| SUSPEND-03 | 13-02 | Suspension modal with Pay-Online WebView (online-only, no cash) | ✓ SATISFIED | Non-dismissible modal, single CTA, no cash UI added |
| SUSPEND-04 | 13-02 | Unlock on payment:succeeded / balance-clear re-fetch | ✓ SATISFIED | Authoritative re-fetch before unlock; silent modal dismiss |
| SUSPEND-05 | 13-01 | Keep 403 create-block as backstop (verify, no behavior change) | ✓ SATISFIED | Backstop file:line evidence confirmed; zero edits to payment_service/booking screens/mapper |

Note: No REQUIREMENTS.md exists in repo (per task brief); IDs verified against PLAN frontmatter + SUMMARYs + RESEARCH.md instead. All 5 IDs claimed across the two plans (13-01: SUSPEND-01/05; 13-02: SUSPEND-02/03/04). No orphaned IDs.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| `outstanding_balance.dart` | 56,109,145,166,169 | `return null` | ℹ️ Info | Legitimate parser guards for malformed envelopes, not stubs |
| `outstanding_balance_screen.dart` | 154 | "Try cash or pull to refresh" string | ℹ️ Info | Pre-existing fallback copy, not a cash button; no cash CTA added by this phase |
| — | — | TODO/FIXME/PLACEHOLDER | — | None found in touched files |

Phase scope respected: `git diff` from phase base shows only `outstanding_balance.dart` + `home_screen.dart` + `suspension_contract_test.dart` (+ planning docs). Phase 12 files (`excess_settlement_sheet.dart`, `ride_complete_screen.dart`, `driver_home_screen.dart`, `payment_service.dart`, `socket_service.dart`) untouched. Commits `ce0dd86`, `2a9d7ba`, `bb94e4f`, `647efa0`, `024b51d` all present.

### Human Verification Required

None blocking — all automated checks pass. Suggested device checks (advisory, not gating): visual appearance of the suspension modal; end-to-end Stripe WebView payment unlocking entries; modal not re-appearing over the open payment screen after background/foreground cycle; live backend flag encoding matches tolerant parser.

### Gaps Summary

No gaps. Phase goal achieved: suspended accounts lock all three home booking entries and face a single-shot non-dismissible pay-online-only modal; payment clears banner + flag + modal via authoritative re-fetch; 403 backstop intact; live in-car settlement untouched in Phase 12 scope. Ready to proceed.

---

_Verified: 2026-09-18T07:30:00Z_
_Verifier: Claude (gsd-verifier)_
