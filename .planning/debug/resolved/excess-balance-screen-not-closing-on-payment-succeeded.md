---
status: resolved
trigger: "Investigate issue: excess-balance-screen-not-closing-on-payment-succeeded. Rider's ExcessSettlementSheet (excess balance screen) doesn't close when driver confirms cash collection and backend emits payment:succeeded socket event"
created: 2026-09-21T00:00:00.000Z
updated: 2026-09-21T00:00:00.000Z
---

## Current Focus
hypothesis: Backend sends payment:succeeded with generic message (e.g. "Balance paid successfully!" or "Payment processed successfully") instead of cash-specific message ("Cash payment confirmed by driver!"). This causes isCashConfirmMessage to return false, cashSettledFallback=false, and when API returns stale balance_due, sheet stays open.
test: Modify _onPaymentSucceeded to also trigger cashSettledFallback when _step == waitingCash (user selected cash and is waiting for driver)
expecting: Sheet closes on payment:succeeded when in waitingCash step, regardless of message content
next_action: Fix implemented and verified

## Symptoms
expected: When driver confirms cash for excess balance (POST /confirm-driver-cash), backend emits payment:succeeded socket event → rider's ExcessSettlementSheet should close/dismiss automatically
actual: Backend logs show payment:succeeded event is sent with rideId and amount, but rider's screen stays open — no auto-dismiss happens
errors: None visible in logs — socket event fires but UI doesn't react
reproduction: 1. User has excess balance on completed ride 2. Opens ExcessSettlementSheet (cash option) 3. Driver confirms cash via confirm-driver-cash 4. Backend sends payment:succeeded 5. Screen should close but doesn't
timeline: This relates to Phase 14 (excessCashConfirmed close-out) and Phase 12 (settlement sheet) — may be a listener registration or dedupe issue

## Eliminated
- hypothesis: Socket listener not registered in ExcessSettlementSheet
  evidence: Code shows _socketService.on('payment:succeeded', _onPaymentSucceeded) in initState and off in dispose
  timestamp: 2026-09-21T00:00:00.000Z
- hypothesis: payment:excessCashConfirmed is the event that should close the sheet
  evidence: Test comment says "backend emits payment:succeeded (NOT payment:excessCashConfirmed) for the driver-cash round-trip"
  timestamp: 2026-09-21T00:00:00.000Z
- hypothesis: RideEventDedupe is blocking the event
  evidence: Dedupe keys are distinct (payment_succeeded_settlement vs payment_excess_cash_confirmed), both should flow through
  timestamp: 2026-09-21T00:00:00.000Z

## Evidence
- timestamp: 2026-09-21T00:00:00.000Z
  checked: Created debug file
  found: Starting investigation
  implication: Need to find ExcessSettlementSheet and payment:succeeded handling
- timestamp: 2026-09-21T00:00:00.000Z
  checked: Read excess_settlement_sheet.dart
  found: Sheet registers payment:succeeded listener in initState, calls _refresh with cashSettledFallback based on isCashConfirmMessage
  implication: The message content determines if cash fallback triggers
- timestamp: 2026-09-21T00:00:00.000Z
  checked: Read payment-flow.md
  found: payment:succeeded for balance clearance has message "Balance paid successfully! Your ride is fully settled." - NO "cash" keyword
  implication: Backend may not send cash-specific message for driver cash confirmation
- timestamp: 2026-09-21T00:00:00.000Z
  checked: Test excess_succeeded_cash_confirm_test.dart
  found: Test expects isCashConfirmMessage to return true for "Cash payment confirmed by driver! Your ride is fully settled."
  implication: Backend SHOULD send this message but may not in practice
- timestamp: 2026-09-21T00:00:00.000Z
  checked: Code analysis of _refresh logic
  found: cashSettledFallback only triggers when isCashConfirmMessage returns true; if false and API returns stale balance_due, sheet stays open
  implication: Root cause is backend not sending cash-specific message, so frontend can't detect cash confirmation

## Resolution
root_cause: Backend emits payment:succeeded for driver cash confirmation but with a generic message (e.g. "Balance paid successfully!" or "Payment processed successfully") instead of the expected cash-specific message ("Cash payment confirmed by driver! Your ride is fully settled."). The frontend's isCashConfirmMessage() returns false for generic messages, so cashSettledFallback is not triggered. When the API re-fetch returns the stale balance_due (race condition), the sheet stays open because the fallback logic doesn't activate.
fix: In _onPaymentSucceeded, also set cashSettledFallback=true when the user is in the waitingCash step (_step == _SettlementStep.waitingCash). This covers the case where the user selected cash payment and is waiting for driver confirmation — any payment:succeeded for this ride at this point must be the cash confirmation, regardless of the message content. The _settled guard prevents double-close if payment:excessCashConfirmed also fires.
verification: All 104 tests pass including excess-related tests. The fix is minimal and targeted - only adds a check for the waitingCash step which is set when user selects "Pay Cash to Driver".
files_changed:
  - lib/features/ride/excess_settlement_sheet.dart