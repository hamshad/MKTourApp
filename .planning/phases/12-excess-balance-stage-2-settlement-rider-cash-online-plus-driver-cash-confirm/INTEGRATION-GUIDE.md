# Excess Balance Stage 2 Settlement — Mobile Integration Guide (Backend Contract)

Source: backend team brief, 2026-09-17. Saved as planning reference for Phase 12.

## 1. Rider App Integration

### A. Live Trip Completion Screen (When Excess Balance Due)

When a ride finishes with extra charges (wait fees / extra distance), present two buttons for Stage 2 payment:

**1. Rider taps "Pay Cash to Driver":**
- API: `POST /api/v1/payments/balance/:rideId/select-method`, body `{ "paymentMethod": "cash" }`
- UI state: spinner/message "Waiting for driver to confirm cash receipt..."

**2. Rider taps "Pay Online":**
- API: `POST /api/v1/payments/balance/:rideId/select-method`, body `{ "paymentMethod": "payment_link" }`
- UI state: launch returned `paymentUrl` in WebView

**3. Listen for socket event `payment:succeeded`:**
- Action: when driver confirms cash or Stripe payment completes, close the settlement screen and navigate to rating/home screen.

### B. App Startup Balance Check (`GET /api/v1/payments/balance`)

- If the rider opens the app later with an unpaid balance from a previous trip: show the outstanding balance popup with ONLY the "Pay Online" button (cash option hidden since the driver is no longer present).

## 2. Driver App Integration

### A. Listen for socket event `payment:excessCashRequested`

- Listener: `socket.on('payment:excessCashRequested', (data) => ...)`
- UI state: modal dialog on driver's screen: "Collect Cash: £X — Passenger requested to pay £X excess balance in cash." + `[ Confirm Cash Received ]`

### B. Driver taps "Confirm Cash Received"

- API: `POST /api/v1/payments/balance/:rideId/confirm-driver-cash`, header `Authorization: Bearer <driver_token>`
- UI state: close modal, toast "Cash payment confirmed! Ride fully completed."

### C. Listen for socket event `payment:excessCashCancelled`

- Listener: `socket.on('payment:excessCashCancelled', (data) => ...)`
- UI state: if the passenger switches back to online payment while in the car, automatically close the driver's cash confirmation modal.

## Notes / Open Questions for Planning

- New endpoints not yet in app: `POST /payments/balance/:rideId/select-method`, `POST /payments/balance/:rideId/confirm-driver-cash`.
- New socket events not yet handled: `payment:excessCashRequested`, `payment:excessCashCancelled` (rider already handles `payment:succeeded`, `payment:balanceDue`).
- Relation to existing `OutstandingBalanceScreen` (post-trip + startup balance via WebView): Stage 2 live-settlement screen is a new surface for the in-car case; startup case stays online-only.
- Driver side: this repo is rider + driver in one codebase — confirm driver cash modal lives in driver flow (driver_home_screen / trip execution).
