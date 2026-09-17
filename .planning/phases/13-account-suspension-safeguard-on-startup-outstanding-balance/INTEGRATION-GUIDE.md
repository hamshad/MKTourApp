# Account Suspension Safeguard + Stage 2 Settlement — Updated Mobile Integration Guide (Backend Contract)

Source: backend team brief (updated), 2026-09-17. Saved as planning reference for Phase 13.
Supersedes the startup-balance section of Phase 12's INTEGRATION-GUIDE.md; live trip-completion
settlement stays in Phase 12.

## 1. Account Suspension Safeguard (Rider App Startup)

When a rider has an unpaid Stage 2 excess balance from a previous ride, their account is
temporarily suspended from requesting any new rides (normal or scheduled).

On App Startup / Home Screen Load:

1. Rider app calls `GET /api/v1/payments/balance`.
2. Backend response (when outstanding balance exists):

```json
{
  "success": true,
  "data": {
    "rideId": "6aabc3476a4199e81748403e",
    "excessAmount": 2.50,
    "paymentUrl": "https://checkout.stripe.com/c/pay/cs_test_...",
    "allowCash": false,
    "accountSuspended": true,
    "status": "balance_due",
    "message": "You have an outstanding balance of £2.50 from a previous ride. Account is temporarily suspended from booking new rides. Please pay online to restore access."
  }
}
```

3. Rider app UI action:
- Detect `accountSuspended: true` and `allowCash: false`.
- Lock/disable the "Book Ride" and "Schedule Ride" buttons.
- Display a prominent modal:

> Account Temporarily Suspended
> You have an unpaid balance of £2.50 from a previous ride. Cash is not available after leaving the vehicle. Please pay online to restore account access.
> [ Pay £2.50 Online Now ]

- Tapping "Pay Online Now" launches `paymentUrl` in WebView.
- Once Stripe confirms payment via socket `payment:succeeded` or webhook, the app unlocks and allows new bookings.

## 2. Rider App Integration (Live Trip Completion Screen)

When rider is in the car at trip completion with an excess balance (Phase 12 scope, repeated here for completeness):

1. Option A — Pay Cash to Driver: `POST /api/v1/payments/balance/:rideId/select-method` with `{"paymentMethod": "cash"}`. UI spinner: "Waiting for driver to confirm cash receipt..."
2. Option B — Pay Online: same endpoint with `{"paymentMethod": "payment_link"}`. UI: launch `paymentUrl` in WebView.
3. Listen for socket `payment:succeeded`: close modal, show "Ride fully settled!", navigate home.

## 3. Driver App Integration (Live Trip Completion Screen)

Phase 12 scope, repeated here for completeness:

1. Listen for socket `payment:excessCashRequested`: modal "Collect Cash: £2.50 — Passenger requested to pay £2.50 excess balance in cash." + `[ Confirm Cash Received ]`.
2. Driver taps confirm: `POST /api/v1/payments/balance/:rideId/confirm-driver-cash` with `Authorization: Bearer <driver_token>`. UI: close modal, toast "Cash excess payment confirmed! Ride fully completed."
3. Listen for socket `payment:excessCashCancelled`: auto-close the driver's cash modal if passenger switches back to online.

## Notes / Open Questions for Planning (Phase 13 scope)

- New response fields on `GET /payments/balance`: `allowCash`, `accountSuspended`. Existing app parses `GET /payments/balance` globally on home mount (`getGlobalPaymentBalance` → pending-balance banner) — extend to lock Book/Schedule buttons + suspension modal.
- Check: does the 403 on `POST /rides/create` remain as backstop, or does the backend now rely purely on startup suspension? Keep handling both.
- Unlock trigger: socket `payment:succeeded` (already listened) or re-fetch balance → `data: null` (already means clear). Reuse existing clear-banner path.
- `allowCash: false` after leaving vehicle vs `true` in-car: startup modal shows Pay Online only; confirm Phase 12 live screen still offers both.
