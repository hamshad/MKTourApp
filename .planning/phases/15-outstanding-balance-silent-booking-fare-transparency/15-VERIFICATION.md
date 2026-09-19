---
phase: 15-outstanding-balance-silent-booking-fare-transparency
verified: 2026-09-19T00:00:00Z
status: passed
score: 7/7 must-haves verified
---

# Phase 15: Outstanding Balance Silent Booking + Fare Transparency Verification Report

**Phase Goal:** Silent outstanding-balance booking — fare-estimate outstandingBalance surfaced as "Includes £X unpaid balance" transparency on booking screens, create/schedule succeed without 403, Stripe auto-covers the combined total with zero client-side fare math.
**Verified:** 2026-09-19T00:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Fare-estimate categories carrying outstandingBalance parse without error | ✓ VERIFIED | `vehicle_selection_widget.dart:283-289` tolerant `numOf(cat['outstandingBalance'] ?? cat['excessAmount'] ?? cat['outstanding_balance'] ?? 0)` clamped >= 0; mirrors existing numOf/congestion pattern |
| 2 | Parsed fare map exposes the balance separately while displayed total stays exactly the backend estimatedFare | ✓ VERIFIED | `total_fare: estimatedFare.toDouble()` (line 295) untouched; `outstanding_balance` separate key (line 302); contract test `no double-count` asserts total 15.0 ≠ 20.0 |
| 3 | Categories without the new field behave exactly as before (balance defaults to 0) | ✓ VERIFIED | `?? 0` default in normalizer + `outstanding_balance: 0.0` in fixed-fare (134) and both calculation-pending fallbacks (910, 951); contract test missing-field → 0.0 |
| 4 | Rider selecting a category with unpaid balance sees an 'Includes £X.XX unpaid balance' line before confirming | ✓ VERIFIED | Three surfaces: `ride_confirmation_screen.dart:2022` banner via `_outstandingBalance` getter (331-332) gated `> 0` (1847); `confirm_booking_screen.dart:991` banner with tolerant num-or-string read (959-966); `vehicle_selection_widget.dart:857` selected-card `incl. £X.XX balance` caption gated `isSelected && > 0` (849-853) |
| 5 | Booking with unpaid balance succeeds via the normal create flow (no 403 dead-end for balance) | ✓ VERIFIED | `_processBooking` (533) / `_confirmBooking` (67) / `_handleScheduleRide` (204) all call `PaymentService.bookRideWithPayment` unchanged; `isBalanceBlocked → _openBalanceBlocked` branches retained as dormant backstop with updated comments (ride_confirmation 668-671) |
| 6 | Stripe/payment-link amount covers the combined total with zero client-side fare math | ✓ VERIFIED | Banners display backend `total_fare` as-is; no `total + balance` arithmetic anywhere in booking surfaces; `git diff` shows zero payment-service/socket/FCM/cancel-refund changes |
| 7 | Cancel/refund edge cases need no app logic (backend owns re-link/clear) | ✓ VERIFIED | Diff scoped to 3 booking UI files + test; `git diff 06cadaf~1..HEAD -- lib/core/services/ lib/core/socket/ lib/features/ride/` empty; no socket/FCM edits |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | ----------- | ------ | ------- |
| `lib/features/booking/widgets/vehicle_selection_widget.dart` | outstandingBalance parsing in _normalizeCategory + fare map key | ✓ VERIFIED | Exists, 997 lines substantive, contains `outstanding_balance` ×7 incl. tolerant parse + caption + fallbacks; wired (imported/used by both booking screens) |
| `test/fare_estimate_balance_test.dart` | Contract tests pinning brief §1 JSON behavior | ✓ VERIFIED | Exists, 99 lines (> 40 min), 6 tests green-pattern: brief example, missing default, string tolerance, no-double-count, excessAmount fallback, negative clamp |
| `lib/features/booking/ride_confirmation_screen.dart` | Balance transparency banner on primary booking screen | ✓ VERIFIED | Exists, contains `outstanding_balance` + `Includes £… unpaid balance` banner (2004-2033), getter + conditional slot (1847); wired to `_currentFareData` |
| `lib/features/booking/confirm_booking_screen.dart` | Balance transparency on legacy confirm screen | ✓ VERIFIED | Exists, contains `outstanding` banner (957-1004) with tolerant read; wired to `vehicle['outstanding_balance']`; booking calls unchanged |
| `lib/features/booking/widgets/vehicle_selection_widget.dart` (card caption) | Selected-category balance line under price | ✓ VERIFIED | Same file second role: caption lines 846-864, selected-only, `> 0` gated; wired to `fareData['outstanding_balance']` |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `vehicle_selection_widget.dart` | fare-estimate category JSON | `_normalizeCategory` tolerant parse | WIRED | Pattern `outstandingBalance` found at 284; fallback chain + clamp verified |
| `ride_confirmation_screen.dart` | `_currentFareData['outstanding_balance']` | conditional banner when balance > 0 | WIRED | Getter (331-332) + `if (!hasError && _outstandingBalance > 0)` (1847) + `_buildBalanceBanner()` (2004) |
| `confirm_booking_screen.dart` | `PaymentService.bookRideWithPayment` success path | unchanged booking call; isBalanceBlocked kept as dormant backstop only | WIRED | Pattern `isBalanceBlocked` found (141, 248); success path untouched; backstop comments accurate |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| BAL-01 | 15-01 | Parse `outstandingBalance` per fare-estimate category without altering totals | ✓ SATISFIED | Normalizer lines 281-302; totals byte-identical |
| BAL-02 | 15-01 | Contract tests pin brief §1 JSON (total 15, balance 5, no double-count) | ✓ SATISFIED | 6 tests in `test/fare_estimate_balance_test.dart` |
| BAL-03 | 15-02 | Booking screens show "Includes £X.XX unpaid balance" line/banner when balance > 0 | ✓ SATISFIED | Banners on both screens + selected-card caption |
| BAL-04 | 15-02 | Create/schedule succeed with balance owing (403 backstop retained dormant); no socket/FCM/cancel-refund changes | ✓ SATISFIED | Booking calls unchanged; empty service/socket diff |

Note: no REQUIREMENTS.md exists in this project; authoritative requirement list is Phase 15 entry in `.planning/ROADMAP.md` (BAL-01..04). All 4 IDs appear in PLAN frontmatter (15-01: BAL-01, BAL-02; 15-02: BAL-03, BAL-04). Zero orphaned requirements.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| `vehicle_selection_widget.dart` | 267 | `return null` | ℹ️ Info | Legitimate nullable guard (`slug == null \|\| empty`), not a stub |
| — | — | TODO/FIXME/placeholder/Not-implemented/coming-soon | — | None found in touched booking files |

### Human Verification Required

None blocking. Optional manual QA (visual + live-backend, not verifiable programmatically):
- Banner copy/layout on small screens with long balance values
- End-to-end booking with real unpaid balance confirming Stripe amount covers fare + debt
- Zero-balance rendering pixel-identical to pre-phase screenshots

### Gaps Summary

No gaps. All 7 must-have truths verified against actual code: tolerant parsing without touching totals, contract tests pinning the brief §1 example, transparency copy on all three booking surfaces gated on balance > 0, unchanged booking success path with 403 retained as documented dormant backstop, zero client-side fare math, zero socket/FCM/cancel-refund edits. Commits `06cadaf`, `6f9ce5b`, `c1fece5`, `06acdd2` present in log. Pre-existing unstaged 1-line change in `lib/core/constants/api_constants.dart` is out of scope and untouched by this phase.

---

_Verified: 2026-09-19T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
