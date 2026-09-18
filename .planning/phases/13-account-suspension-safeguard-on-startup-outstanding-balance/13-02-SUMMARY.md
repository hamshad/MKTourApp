---
phase: 13-account-suspension-safeguard-on-startup-outstanding-balance
plan: 02
subsystem: payments
tags: [account-suspension, outstanding-balance, home-gate, flutter]

# Dependency graph
requires:
  - phase: 12-excess-balance-stage-2-settlement-rider-cash-online-plus-driver-cash-confirm
    provides: [OutstandingBalance model, OutstandingBalanceScreen WebView flow, payment:succeeded flow]
  - phase: 13-01 suspension-flag parsing foundation
    provides: [isSuspended conjunction getter, tolerant flag parser]
provides:
  - Home startup suspension gate (entry locks + pay-online-only modal + authoritative unlock)
affects: [booking screens, payment service]

# Tech tracking
tech-stack:
  added: []
  patterns: [single-show-site guarded modal, authoritative re-fetch before unlock, silent dialog pop on clear]

key-files:
  created: []
  modified: [lib/features/home/home_screen.dart]

key-decisions:
  - "Suspended entry guards re-show the modal (not a toast) so every booking path funnels to pay-online"
  - "payment:succeeded unlocks only after authoritative getGlobalPaymentBalance shows data null or status succeeded"
  - "FCM-sourced fallback balances derive suspension from parsed flags; empty-rideId re-fetch updates in-memory only"

patterns-established:
  - "Single-show-site modal: _maybeShowSuspensionModal (guard + runAfterFrame) → _showSuspensionModal (open flag + isCurrent route guard)"
  - "Silent dialog close via captured dialog context, mirroring 12-03 _excessCashDialogOpen precedent"

requirements-completed: [SUSPEND-02, SUSPEND-03, SUSPEND-04]

# Metrics
duration: 3min
completed: 2026-09-18
---

# Phase 13 Plan 02: Home Startup Suspension Gate Summary

**Home screen locks search/airport/scheduled entries while suspended and shows a single-shot non-dismissible pay-online modal, unlocking only on authoritative clear; all in `home_screen.dart`, Phase 11/12 untouched.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-09-18T07:00:41Z
- **Completed:** 2026-09-18T07:03:05Z
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments
- Suspension state (`_isSuspended` from `parsed.isSuspended`) derived in `_persistPendingBalance` + per-ride fallback, reset in `_clearPendingBalance`; search bar, airport tile, scheduled tile re-show the modal while suspended
- Non-dismissible 'Account Temporarily Suspended' modal with amount + backend message + no-cash copy and single `Pay £X Online Now` CTA into the existing `OutstandingBalanceScreen` WebView flow; single show site with open-flag + `isCurrent` route guard, `runAfterFrame` posting from startup/socket/FCM paths
- Authoritative unlock: `payment:succeeded` re-fetches global balance first, clears only on `data == null` or `status == succeeded`, refreshes amount and stays locked otherwise; `_clearPendingBalance` silently pops the modal; resume path reuses the same clear method

## Task Commits

Each task was committed atomically:

1. **Task 1: Suspension state + entry-point lock** - `bb94e4f` (feat)
2. **Task 2: Single-shot non-dismissible suspension modal** - `647efa0` (feat)
3. **Task 3: Unlock on succeeded + clear re-fetch with modal dismiss** - `024b51d` (feat)

**Plan metadata:** _(pending final docs commit)_

## Files Created/Modified
- `lib/features/home/home_screen.dart` - Suspension flag + 3 entry guards + modal show site + hardened succeeded handler + silent modal dismiss on clear

## Decisions Made
- Entry guards re-show the modal instead of navigating or toasting: every booking path funnels to the single pay-online CTA, matching the brief's lock/disable intent
- `payment:succeeded` never unlocks directly: unrelated mid-trip captures fire the same event, so the handler re-fetches `getGlobalPaymentBalance` and unlocks only on `data == null` / `status == succeeded` (Pitfall 2)
- Empty-rideId still-owed re-fetch updates `_pendingBalance`/`_isSuspended` in memory only (no persistence write with an empty key)
- FCM `paymentSucceeded`/`cashCollected` keeps the direct-clear path: backend-pushed success is authoritative, unlike the broadcast socket event

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Derived suspension flag in per-ride fallback setState**
- **Found during:** Task 1 (entry-point lock)
- **Issue:** Plan listed `_checkPendingBalance`, `_persistPendingBalance`, `_clearPendingBalance` for flag wiring, but `_checkPersistedRideBalance` sets `_pendingBalance` directly via `setState`, bypassing `_persistPendingBalance` — a stale `_isSuspended` could survive a fallback refresh
- **Fix:** Set `_isSuspended = parsed.isSuspended` in that direct `setState` too
- **Files modified:** lib/features/home/home_screen.dart
- **Verification:** `rg -n "_isSuspended" lib/features/home/home_screen.dart` shows all write sites; `flutter analyze` clean
- **Committed in:** bb94e4f (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Closes a stale-flag hole in an existing fallback path; no scope creep, no persistence-key changes.

## Issues Encountered
- Task 1's `flutter analyze` showed 3 `undefined_method _showSuspensionModal` errors — expected forward reference to the Task 2 method; resolved by the Task 2 commit, final analyze shows zero errors
- `flutter analyze` reports pre-existing warnings in unrelated code (unused imports/fields, deprecated `withOpacity`); touched logic is clean

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 13 complete (13-01 + 13-02): startup suspension gate enforced, ready for phase transition
- SUSPEND-02/03/04 verified: 3 locked entries, pay-online-only modal, authoritative unlock; `rg -in 'cash'` on `outstanding_balance_screen.dart` shows no cash button added; `git status` shows only `home_screen.dart` modified

---
*Phase: 13-account-suspension-safeguard-on-startup-outstanding-balance*
*Completed: 2026-09-18*

## Self-Check: PASSED
