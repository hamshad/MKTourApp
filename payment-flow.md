# MK Tours — Payment Flow Integration Guide
**For Flutter App Integration | Backend v2 (Interactive Balance Flow)**

---

## Base URL
```
https://your-api-domain.com/api/v1
```
All authenticated endpoints require:
```
Authorization: Bearer <jwt_token>
Content-Type: application/json
```

---

## Table of Contents
1. [Normal Ride Payment Flow](#1-normal-ride-payment-flow)
2. [Scheduled Ride Payment Flow](#2-scheduled-ride-payment-flow)
3. [Outstanding Balance Flow](#3-outstanding-balance-flow)
4. [Socket Events Reference](#4-socket-events-reference)
5. [FCM Push Notifications Reference](#5-fcm-push-notifications-reference)
6. [Payment Status Reference](#6-payment-status-reference)
7. [Error Responses](#7-error-responses)

---

## 1. Normal Ride Payment Flow

### Flow Summary
```
[Check Balance Block] → [Fare Estimate] → [Book Ride + Hold] → [Trip Runs]
    → [Trip Ends: Two Outcomes]
        A) Final ≤ Hold  → Partial capture → DONE (payment:succeeded)
        B) Final > Hold  → Full capture + Excess PI → payment:balanceDue
                                → User pays via Payment Sheet
                                → Webhook fires → payment:succeeded
```

---

### Step 0 — Check for Outstanding Balance (Guard)

Before attempting to book, **check for a balance block** (optional pre-flight — the booking API also enforces this).

**`GET /payments/balance/:rideId`** can also be used if the app already knows a ride has a pending balance.

If the user has an outstanding balance, `POST /rides/create` will return HTTP 403. The app should intercept this and redirect to the balance payment screen.

---

### Step 1 — Get Fare Estimate

**`GET /rides/fare-estimate`**

**Query Params:**
```json
{
  "pickupLat": 52.0406,
  "pickupLon": -0.7594,
  "dropoffLat": 51.5074,
  "dropoffLon": -0.1278
}
```

**Response `200`:**
```json
{
  "success": true,
  "data": {
    "estimatedDistance": 54.2,
    "isOutOfArea": false,
    "isAirportTransfer": false,
    "isFixedZone": false,
    "isCongestionZone": false,
    "promoApplies": false,
    "categories": [
      {
        "slug": "car_4_seater",
        "name": "Standard",
        "estimatedFare": 62.50,
        "waitingTimePerMinuteRate": 0.35,
        "freeWaitingTimeMinutes": 5,
        "isCongestionCharge": false,
        "congestionChargeAmount": 0
      },
      {
        "slug": "car_5_seater",
        "name": "Executive",
        "estimatedFare": 74.00,
        "waitingTimePerMinuteRate": 0.35,
        "freeWaitingTimeMinutes": 5,
        "isCongestionCharge": false,
        "congestionChargeAmount": 0
      }
    ]
  }
}
```

---

### Step 2 — Book the Ride (Stripe pre-auth hold placed)

**`POST /rides/create`**

**Request Body:**
```json
{
  "pickupLocation": {
    "address": "Milton Keynes Central Station, MK9 1AA",
    "coordinates": [-0.7594, 52.0406]
  },
  "dropoffLocation": {
    "address": "London Euston, NW1 2RT",
    "coordinates": [-0.1278, 51.5074]
  },
  "vehicleCategorySlug": "car_4_seater",
  "distance": 54.2,
  "paymentMethod": "stripe",
  "stops": []
}
```

> **`paymentMethod`** values: `"stripe"` | `"cash"` | `"payment_link"`
>
> For the interactive payment flow (Card / Apple Pay / Google Pay), use `"stripe"`.

**Response `201` — Stripe:**
```json
{
  "success": true,
  "message": "Ride request created successfully",
  "data": {
    "_id": "ride_abc123",
    "status": "requested",
    "fare": 62.50,
    "distance": 54.2,
    "vehicleCategorySlug": "car_4_seater",
    "paymentMethod": "stripe",
    "paymentStatus": "pending",
    "pickupLocation": {
      "address": "Milton Keynes Central Station, MK9 1AA",
      "coordinates": [-0.7594, 52.0406]
    },
    "dropoffLocation": {
      "address": "London Euston, NW1 2RT",
      "coordinates": [-0.1278, 51.5074]
    },
    "waitingTimePerMinuteRate": 0.35,
    "freeWaitingTimeMinutes": 5,
    "payment": {
      "_id": "pay_xyz789",
      "stripePaymentIntentId": "pi_3abc...",
      "clientSecret": "pi_3abc..._secret_def...",
      "amount": 6875,
      "status": "intent_created"
    }
  }
}
```

> :warning: The `clientSecret` returned here is for the **base fare hold** (with a 10% buffer already included). Present this to the Stripe Payment Sheet immediately after booking so the user authorizes the hold.

**Response `403` — Outstanding Balance Block:**
```json
{
  "success": false,
  "message": "You have an outstanding balance of £3.45 from a previous ride. Please clear your balance before booking a new ride.",
  "data": {
    "outstandingBalance": 3.45,
    "rideId": "ride_prev123"
  }
}
```

> When you receive this 403, redirect the user to the balance payment screen. Call `GET /payments/balance/ride_prev123` to get the `clientSecret` for the Payment Sheet.

---

### Step 3 — Trip Runs (No action from app)

- **Wait time within hold buffer:** Backend silently increments the authorized hold. No user action needed.
- **Driver marks arrive, start, etc.:** These are ride state events, not payment events.

---

### Step 4 — Ride Completes

Driver calls `POST /rides/:id/complete`. The backend then **automatically** decides:

#### Outcome A — Final Fare ≤ Original Hold (e.g. early end or no excess wait)

You receive the `ride:completed` socket event followed immediately by `payment:succeeded`.

**Socket → `ride:completed`:**
```json
{
  "rideId": "ride_abc123",
  "status": "completed",
  "fare": 62.50,
  "actualFare": 58.00,
  "totalWaitFee": 0,
  "totalWaitMinutes": 0,
  "distance": 54.2,
  "driver": {
    "id": "driver_id",
    "name": "James T."
  },
  "message": "Ride completed successfully! Please rate your experience."
}
```

**Socket → `payment:succeeded`** (fires shortly after):
```json
{
  "rideId": "ride_abc123",
  "amount": 58.00,
  "message": "Payment processed successfully"
}
```

> Show the ride summary screen. No further payment action needed.

---

#### Outcome B — Final Fare > Original Hold (excess wait fees)

You receive `ride:completed` followed by `payment:balanceDue` (instead of `payment:succeeded`).

**Socket → `ride:completed`:**
```json
{
  "rideId": "ride_abc123",
  "status": "completed",
  "fare": 62.50,
  "actualFare": 65.95,
  "totalWaitFee": 3.45,
  "totalWaitMinutes": 9,
  "distance": 54.2,
  "driver": {
    "id": "driver_id",
    "name": "James T."
  },
  "message": "Ride completed successfully! Please rate your experience."
}
```

**Socket → `payment:balanceDue`** (fires immediately after `ride:completed`):
```json
{
  "rideId": "ride_abc123",
  "excessAmount": 3.45,
  "clientSecret": "pi_3def..._secret_ghi...",
  "isReminder": false,
  "message": "You have an outstanding balance of £3.45 for wait time. Please complete your payment."
}
```

> **Present the Stripe Payment Sheet** using this `clientSecret`. The user selects Card / Apple Pay / Google Pay and pays. This intent uses `automatic` capture — no further backend call needed.

---

### Step 5 — User Pays Balance (Stripe Payment Sheet)

No API call needed from Flutter. Once the user completes payment in the Stripe Payment Sheet:

1. Stripe fires `payment_intent.succeeded` webhook to the backend
2. Backend resolves the payment, notifies user

**Socket → `payment:succeeded`** (fired after Stripe webhook):
```json
{
  "rideId": "ride_abc123",
  "amount": 65.95,
  "message": "Balance paid successfully! Your ride is fully settled."
}
```

> Hide the balance screen. Show ride summary / rating screen.

---

### Step 6 — Re-fetch Balance Client Secret (Fallback)

If the app was backgrounded and missed the `payment:balanceDue` socket event, the user can re-enter the app and you can manually fetch the outstanding balance:

**`GET /payments/balance/:rideId`**

**Response `200` — Balance still outstanding:**
```json
{
  "success": true,
  "data": {
    "rideId": "ride_abc123",
    "excessAmount": 3.45,
    "clientSecret": "pi_3def..._secret_ghi...",
    "status": "balance_due",
    "message": "Outstanding balance of £3.45. Please complete payment."
  }
}
```

**Response `200` — Already paid:**
```json
{
  "success": true,
  "data": {
    "status": "succeeded",
    "message": "Balance already paid."
  }
}
```

**Response `404` — No outstanding balance:**
```json
{
  "success": false,
  "message": "No outstanding balance found for this ride."
}
```

---

## 2. Scheduled Ride Payment Flow

### Flow Summary
```
[Book Scheduled Ride + Full Fare Hold] → [Ride Day Arrives]
    → [Driver Accepts → Departs → Arrives]
    → [Trip Ends: Same as Normal Ride Outcome A or B]
```

---

### Step 1 — Book Scheduled Ride

**`POST /rides/schedule`**

**Request Body:**
```json
{
  "pickupLocation": {
    "address": "Milton Keynes Central Station, MK9 1AA",
    "coordinates": [-0.7594, 52.0406]
  },
  "dropoffLocation": {
    "address": "London Euston, NW1 2RT",
    "coordinates": [-0.1278, 51.5074]
  },
  "vehicleCategorySlug": "car_5_seater",
  "distance": 54.2,
  "scheduledPickupTime": "2026-09-20T14:00:00.000Z",
  "paymentMethod": "stripe",
  "preBookingNote": "Please arrive 5 mins early",
  "stops": []
}
```

> `scheduledPickupTime` must be **at least 2 hours** from now (5 minutes in development).

**Response `201`:**
```json
{
  "success": true,
  "message": "Scheduled ride created successfully",
  "data": {
    "_id": "ride_sched456",
    "status": "scheduled",
    "isScheduled": true,
    "scheduledPickupTime": "2026-09-20T14:00:00.000Z",
    "fare": 74.00,
    "distance": 54.2,
    "vehicleCategorySlug": "car_5_seater",
    "paymentMethod": "stripe",
    "paymentStatus": "pending",
    "preBookingNote": "Please arrive 5 mins early",
    "payment": {
      "_id": "pay_xyz789",
      "stripePaymentIntentId": "pi_4abc...",
      "clientSecret": "pi_4abc..._secret_jkl...",
      "amount": 8140,
      "status": "intent_created"
    }
  }
}
```

> The `clientSecret` here is for the **full estimated fare hold** (with a 10% buffer included, just like normal rides). Present this in the Stripe Payment Sheet immediately. Only after this hold is authorized is the scheduled ride officially booked.

---

### Step 2 — (Removed) Confirm Deposit Payment
*This step is no longer used, as scheduled rides now use the standard pre-auth hold flow at booking.*

---

### Step 3 — On Ride Day (Driver Accepts)

**Socket → `ride:accepted`:**
```json
{
  "rideId": "ride_sched456",
  "status": "accepted",
  "isScheduled": true,
  "scheduledPickupTime": "2026-09-20T14:00:00.000Z",
  "driver": {
    "id": "drv_001",
    "name": "James T.",
    "phone": "+447700900000",
    "rating": 4.8,
    "vehicle": {
      "model": "Toyota Prius",
      "number": "MK21 ABC",
      "color": "Black",
      "categorySlug": "car_5_seater"
    },
    "location": {
      "type": "Point",
      "coordinates": [-0.76, 52.04]
    }
  },
  "message": "Driver accepted your scheduled ride! James T. is assigned to your ride."
}
```

---

### Step 4 — Trip Completes (Same as Normal Ride)

After driver calls complete, the final fare is captured from the **pre-authorized hold** placed at booking.

- **No excess:** `payment:succeeded` fires → ride fully settled
- **Wait fee excess:** `payment:balanceDue` fires → user pays via Payment Sheet → `payment:succeeded`

> The socket payloads and endpoint for re-fetching `clientSecret` are **identical** to the Normal Ride flow (Step 4–6 above).

---

## 3. Outstanding Balance Flow

### When it triggers
The user did not pay their balance within the same session (app was killed, dismissed, etc.).

### Daily Reminder (10:00 AM every day)

**FCM Push** is sent to the user's device:
```json
{
  "notification": {
    "title": ":credit_card: Outstanding Balance — Action Required",
    "body": "You have an unpaid balance of £3.45 from your last MK Tours ride. Please pay now to continue using the app."
  },
  "data": {
    "type": "balance_due_reminder",
    "rideId": "ride_abc123",
    "excessAmount": "3.45",
    "clientSecret": "pi_3def..._secret_ghi..."
  }
}
```

> When the user taps this notification, open the balance payment screen and present the Stripe Payment Sheet using `data.clientSecret`.

**Socket → `payment:balanceDue`** (also emitted if user is connected):
```json
{
  "rideId": "ride_abc123",
  "excessAmount": 3.45,
  "clientSecret": "pi_3def..._secret_ghi...",
  "isReminder": true,
  "message": "You have an outstanding balance of £3.45. Pay now to unlock ride booking."
}
```

### Fetching Balance Manually (App Startup Check)

Call on app startup / login to check if user has a pending balance:

**`GET /payments/balance/:rideId`** — use the `rideId` from FCM data or cached local state.

> If no `rideId` is available, you can also add an endpoint to check across all rides — or use the 403 response from `POST /rides/create` as the trigger.

---

## 4. Socket Events Reference

All events received by the **user's app** via Socket.IO.

| Event | Trigger | Action Required |
|---|---|---|
| `ride:accepted` | Driver accepts | Show driver card + ETA |
| `ride:driverArrived` | Driver at pickup | Show "Driver is here" alert |
| `ride:started` | Ride begins | Show in-trip screen |
| `ride:completed` | Driver ends trip | Show fare summary |
| `ride:promoApplied` | Promo ride | Show free ride banner |
| `ride:depositConfirmed` | Deposit webhook fires | Confirm booking screen |
| `payment:succeeded` | Payment fully settled | Unlock app, show summary |
| `payment:balanceDue` | Excess after trip | **Present Stripe Payment Sheet** |
| `payment:failed` | Payment failure | Show error + retry prompt |

---

### `payment:balanceDue` — Full Payload
```json
{
  "rideId": "ride_abc123",
  "excessAmount": 3.45,
  "clientSecret": "pi_3def..._secret_ghi...",
  "isReminder": false,
  "message": "You have an outstanding balance of £3.45 for wait time. Please complete your payment."
}
```

> - `isReminder: false` → fired immediately after trip ends
> - `isReminder: true` → fired by the daily 10 AM cron job

**What to do with `clientSecret`:**
Present it to the **Stripe Payment Sheet SDK**. No additional API call is needed. Stripe handles Card / Apple Pay / Google Pay natively. After the user pays, wait for `payment:succeeded`.

---

### `payment:succeeded` — Full Payload
```json
{
  "rideId": "ride_abc123",
  "amount": 65.95,
  "message": "Payment processed successfully"
}
```
> OR for a balance clearance:
```json
{
  "rideId": "ride_abc123",
  "amount": 65.95,
  "message": "Balance paid successfully! Your ride is fully settled."
}
```

---

### `payment:failed` — Full Payload
```json
{
  "rideId": "ride_abc123",
  "failureType": "payment_failed",
  "failureReason": "Your card was declined.",
  "failureCode": "card_declined",
  "canRetry": true,
  "message": "Payment failed. Please try again."
}
```

---

### `ride:completed` — Full Payload
```json
{
  "rideId": "ride_abc123",
  "status": "completed",
  "fare": 62.50,
  "actualFare": 65.95,
  "totalWaitFee": 3.45,
  "totalWaitMinutes": 9,
  "originalFare": null,
  "isPromoRide": false,
  "distance": 54.2,
  "duration": "58 mins",
  "driver": {
    "id": "drv_001",
    "name": "James T."
  },
  "message": "Ride completed successfully! Please rate your experience."
}
```

> Check `totalWaitFee > 0` to pre-warn the user that a balance screen may follow, but **wait for `payment:balanceDue`** before presenting the Payment Sheet (do not assume it will always fire).

---

## 5. FCM Push Notifications Reference

All FCM messages include `data` fields (all values are strings per FCM spec).

### Ride Accepted
```json
{
  "notification": {
    "title": ":white_check_mark: Driver Assigned",
    "body": "Driver accepted! James T. is on the way."
  },
  "data": {
    "type": "ride_accepted",
    "rideId": "ride_abc123"
  }
}
```

### Driver Arrived at Pickup
```json
{
  "notification": {
    "title": ":round_pushpin: Driver Arrived",
    "body": "Your driver is at the pickup point. Please head to the location."
  },
  "data": {
    "type": "driver_arrived",
    "rideId": "ride_abc123"
  }
}
```

### Ride Started
```json
{
  "notification": {
    "title": ":rocket: Ride Started",
    "body": "Your ride is in progress. Enjoy the journey!"
  },
  "data": {
    "type": "ride_started",
    "rideId": "ride_abc123"
  }
}
```

### Ride Completed
```json
{
  "notification": {
    "title": ":white_check_mark: Ride Completed",
    "body": "Ride complete! Total: £65.95 (incl. wait fees: £3.45). Please rate your experience."
  },
  "data": {
    "type": "ride_completed",
    "rideId": "ride_abc123",
    "fare": "65.95",
    "totalWaitFee": "3.45",
    "isPromoRide": "false",
    "originalFare": ""
  }
}
```

### Outstanding Balance Reminder (Daily 10 AM Cron)
```json
{
  "notification": {
    "title": ":credit_card: Outstanding Balance — Action Required",
    "body": "You have an unpaid balance of £3.45 from your last MK Tours ride. Please pay now to continue using the app."
  },
  "data": {
    "type": "balance_due_reminder",
    "rideId": "ride_abc123",
    "excessAmount": "3.45",
    "clientSecret": "pi_3def..._secret_ghi..."
  }
}
```

### Deposit Confirmed (Scheduled Ride)
```json
{
  "notification": {
    "title": ":dart: Scheduled Ride Confirmed",
    "body": "Deposit paid! Your ride for 20 Sep at 2:00 PM is confirmed."
  },
  "data": {
    "type": "deposit_confirmed",
    "rideId": "ride_sched456"
  }
}
```

### Ride Cancelled (by driver/system)
```json
{
  "notification": {
    "title": ":x: Ride Cancelled",
    "body": "User cancelled the ride."
  },
  "data": {
    "type": "ride_cancelled",
    "rideId": "ride_abc123",
    "reason": "user_cancelled"
  }
}
```

### Ride Expired (No Driver Found)
```json
{
  "notification": {
    "title": ":alarm_clock: Ride Expired",
    "body": "No drivers available. Please try again."
  },
  "data": {
    "type": "ride_expired",
    "rideId": "ride_abc123"
  }
}
```

---

## 6. Payment Status Reference

| Status | Meaning | User sees |
|---|---|---|
| `intent_created` | Stripe PI created, hold not yet placed | Loading / Processing |
| `authorized` | Base hold placed on card | Booking confirmed |
| `balance_due` | Base captured, excess owed | **Balance payment screen** |
| `partially_captured` | Ride ended early, lower amount captured | Ride summary |
| `succeeded` | Fully settled (base OR base + excess) | Ride complete |
| `failed` | Payment failed | Error + retry |
| `cancelled` | Ride cancelled, hold voided | Cancelled screen |
| `refunded` | Full refund issued | Refunded |
| `partially_refunded` | Partial refund issued | Partial refund notice |

---

## 7. Error Responses

### Standard Error Shape
```json
{
  "success": false,
  "message": "Human-readable error message",
  "data": {}
}
```

### HTTP Status Codes Used

| Code | Meaning |
|---|---|
| `400` | Validation error (missing fields, invalid data) |
| `401` | Unauthenticated — invalid or expired JWT |
| `403` | Outstanding balance block — clear balance first |
| `404` | Resource not found (ride, payment, balance) |
| `500` | Internal server error |

### 403 — Outstanding Balance (on ride booking)
```json
{
  "success": false,
  "message": "You have an outstanding balance of £3.45 from a previous ride. Please clear your balance before booking a new ride.",
  "data": {
    "outstandingBalance": 3.45,
    "rideId": "ride_abc123"
  }
}
```

### 400 — Validation (scheduled ride)
```json
{
  "success": false,
  "message": "Scheduled rides must be booked at least 2 hours in advance"
}
```

---

## Quick Decision Tree for Flutter

```
App starts / user logs in
  └─► Check: does FCM/local state indicate a pending balance?
       ├─ YES → Show persistent balance banner
       │         → On tap: GET /payments/balance/:rideId
       │         → Present Stripe Payment Sheet with clientSecret
       │         → Wait for payment:succeeded socket
       └─ NO → Normal home screen

User tries to book a ride
  └─► POST /rides/create
       ├─ 201 → Ride created
       │         → Stripe paymentMethod: present Stripe Payment Sheet (base hold)
       │         → Wait for driver (ride:accepted socket)
       │
       └─ 403 → Outstanding balance
                 → Redirect to balance screen (same as above)

After ride:completed socket
  └─► Wait for next payment socket:
       ├─ payment:succeeded → Show ride summary :white_check_mark:
       └─ payment:balanceDue → Present Stripe Payment Sheet (excess)
                               → After payment: wait for payment:succeeded
```
