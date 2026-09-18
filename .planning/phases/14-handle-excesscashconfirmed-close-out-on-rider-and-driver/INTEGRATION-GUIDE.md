# excessCashConfirmed Close-Out — Backend Contract (Phase 14)

Source: backend team brief, 2026-09-18. Verified gap: `grep excessCashConfirmed lib/` returns
zero hits — the event is unhandled on both apps.

## Cash round-trip (recap — Phases 12 + debug fixes already cover these)

### 1. Rider selects cash

- Endpoint: `POST /api/v1/payments/balance/:rideId/select-method`, body `{ "paymentMethod": "cash" }`
- Server socket event to driver: `payment:excessCashRequested`

```json
{
  "rideId": "6aad22f368a3e5d6d9e45760",
  "excessAmount": 7.80,
  "message": "Passenger requested to pay £7.80 excess balance in cash. Please collect cash and tap confirm."
}
```

### 2. Driver confirms cash received (NEW — unhandled)

- Endpoint: `POST /api/v1/payments/balance/:rideId/confirm-driver-cash`
- Headers: `Authorization: Bearer <DRIVER_JWT>`
- Server socket event to user AND driver: `payment:excessCashConfirmed`

```json
{
  "rideId": "6aad22f368a3e5d6d9e45760",
  "excessAmount": 7.80,
  "message": "Driver confirmed cash receipt for excess balance. Thank you!"
}
```

## Phase 14 scope

- Rider: on `payment:excessCashConfirmed`, close the "Waiting for driver to confirm..." state in `ExcessSettlementSheet`, show settled confirmation, navigate home/rating. (Today the rider likely waits on `payment:succeeded` — confirm whether backend ALSO emits `succeeded` for this flow; if yes, confirmed is a faster UX signal + thank-you copy.)
- Driver: on `payment:excessCashConfirmed`, close the Collect-Cash modal (if still open), show "Cash excess payment confirmed!" toast.
- Socket plumbing: passthrough + dedupe following the Phase 12 / excessCashRequested patterns (FCM type, if any, TBD — brief shows socket only).
- Relation to `payment:succeeded`: determine whether both fire; avoid double close-out (reuse settled-flag pattern from the 404 fix).
