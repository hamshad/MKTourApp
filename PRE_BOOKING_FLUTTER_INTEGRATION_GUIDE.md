# Flutter Integration Guide: Pre-Booking Feature

This guide documents backend integration requirements for Flutter apps.
It includes endpoints, payloads, socket events, notification payload mapping, and expected UI flow.

No implementation code is included.

## Table of Contents

1. [User App Changes](#1-user-app-changes)
2. [Driver App Changes](#2-driver-app-changes)
3. [Socket Events (New)](#3-socket-events-new)
4. [FCM Notifications (New)](#4-fcm-notifications-new)
5. [End-to-End Flow](#5-end-to-end-flow)
6. [Key Differences from Regular Rides](#6-key-differences-from-regular-rides)
7. [UI Screens Needed](#7-ui-screens-needed)

## 1. User App Changes

### 1.1 Create a Scheduled Ride

**Endpoint**: `POST /rides/schedule`  
**Auth**: Bearer token (User)

**Request Body**:

```json
{
  "pickupLocation": {
    "coordinates": [longitude, latitude],
    "address": "123 High Street, Milton Keynes"
  },
  "pickupPlaceId": "ChIJ...",
  "dropoffLocation": {
    "coordinates": [longitude, latitude],
    "address": "Luton Airport"
  },
  "dropoffPlaceId": "ChIJ...",
  "vehicleCategorySlug": "comfort",
  "scheduledPickupTime": "2026-03-07T14:00:00.000Z",
  "preBookingNote": "2 suitcases, please wait at Terminal 1",
  "distance": 25.4
}
```

**Response (201)**:

```json
{
  "success": true,
  "message": "Scheduled ride created. Please pay the deposit to confirm.",
  "data": {
    "ride": {
      "_id": "660f...",
      "status": "scheduled",
      "isScheduled": true,
      "scheduledPickupTime": "2026-03-07T14:00:00.000Z",
      "fare": 45.0,
      "depositAmount": 4.5,
      "depositStatus": "pending",
      "pickupLocation": {},
      "dropoffLocation": {},
      "vehicleCategorySlug": "comfort"
    },
    "payment": {
      "id": "660f...",
      "clientSecret": "pi_xxx_secret_yyy",
      "amount": 4.5,
      "currency": "gbp"
    }
  }
}
```

**Flutter Action**:

- Show ride summary with deposit amount (10% of fare).
- Use `payment.clientSecret` with Stripe SDK to collect card payment for deposit.
- After Stripe success, either:
  - call `POST /rides/:id/confirm-deposit`, or
  - wait for webhook-driven confirmation socket event.
- Payment method type is `card` (`paymentMethodTypes: ['card']`).

**Important**:

- `clientSecret` is a Stripe PaymentIntent secret and should be used with `Stripe.instance.confirmPayment()` in Flutter.
- If user leaves without paying, ride auto-cancels after 30 minutes.

### 1.2 Confirm Deposit (Optional Fallback)

**Endpoint**: `POST /rides/:id/confirm-deposit`  
**Auth**: Bearer token (User)

Webhook (`payment_intent.succeeded`) also sets `depositStatus: 'paid'`. This endpoint is a fallback if webhook processing is delayed.

**Request**: No body.

**Response (200)**:

```json
{
  "success": true,
  "message": "Deposit confirmed. Your ride is scheduled!",
  "data": {
    "rideId": "660f...",
    "scheduledPickupTime": "2026-03-07T14:00:00.000Z",
    "depositAmount": 4.5
  }
}
```

### 1.3 Get User Scheduled Rides

**Endpoint**: `GET /rides/scheduled`  
**Auth**: Bearer token (User)  
**Query**: `?status=scheduled` (optional; defaults to active statuses)

**Response (200)**:

```json
{
  "success": true,
  "message": "Scheduled rides retrieved",
  "data": [
    {
      "_id": "660f...",
      "status": "scheduled",
      "isScheduled": true,
      "scheduledPickupTime": "2026-03-07T14:00:00.000Z",
      "fare": 45.0,
      "depositAmount": 4.5,
      "depositStatus": "paid",
      "pickupLocation": {
        "coordinates": [-0.756, 52.041],
        "address": "123 High Street, Milton Keynes"
      },
      "dropoffLocation": {
        "coordinates": [-0.368, 51.874],
        "address": "Luton Airport"
      },
      "vehicleCategorySlug": "comfort",
      "preBookingNote": "2 suitcases",
      "driver": null,
      "depositPayment": {
        "status": "succeeded",
        "amount": 450
      }
    }
  ]
}
```

**Flutter Action**:

- Add a `My Scheduled Rides` section/tab.
- Each card should show pickup, dropoff, scheduled time, fare, deposit status, and assigned driver if available.
- Allow cancellation from this list.

### 1.4 Cancel Scheduled Ride (User)

**Endpoint**: `POST /rides/:id/cancel/scheduled/user`  
**Auth**: Bearer token (User)

**Request**: No body.

**Response (200)**:

```json
{
  "success": true,
  "message": "Scheduled ride cancelled successfully",
  "data": {
    "ride": {},
    "depositRefunded": true,
    "cancellationFee": 0
  }
}
```

**Cancellation Rules**:

- Within 4 hours of booking: free, deposit refunded.
- Pickup is 3+ hours away: free, deposit refunded.
- After 4 hours and pickup is less than 3 hours away: deposit forfeited (10% fare).

**Response fields to show**:

- `depositRefunded: true`: show refund message (`Your deposit of £X.XX will be refunded`).
- `depositRefunded: false`: show forfeiture message (`Your deposit of £X.XX has been forfeited as a cancellation fee`).
- `cancellationFee`: show charged fee (`0` if free).

**Compatibility Note**:

- Existing `POST /rides/:id/cancel/user` still works for scheduled rides and auto-routes to scheduled cancellation logic.

### 1.5 Payment at Arrival (Remaining 90%)

No new endpoint required. Existing flow remains:

- Driver arrives -> user receives `ride:driverArrived` socket event.
- User selects payment method -> `POST /rides/:id/select-payment`.
- Backend deducts already-paid 10% deposit from total fare.

Example: Fare `£45.00`, deposit `£4.50`, remaining `£40.50`.

Example response from `select-payment`:

```json
{
  "amount": 4050,
  "currency": "GBP",
  "paymentMethod": "payment_link"
}
```

**Note**: No additional UI logic required for calculation; backend returns reduced amount.

## 2. Driver App Changes

### 2.1 Receive Scheduled Ride Requests

Drivers continue receiving `ride:newRequest` socket events with extra scheduling fields.

**Socket Event**: `ride:newRequest`

```json
{
  "rideId": "660f...",
  "pickupLocation": {
    "coordinates": [-0.756, 52.041],
    "address": "123 High Street"
  },
  "dropoffLocation": {
    "coordinates": [-0.368, 51.874],
    "address": "Luton Airport"
  },
  "fare": 45.0,
  "distance": 25.4,
  "vehicleCategorySlug": "comfort",
  "isScheduled": true,
  "scheduledPickupTime": "2026-03-07T14:00:00.000Z",
  "isPriority": false,
  "user": {
    "name": "John Doe"
  }
}
```

**Flutter Action**:

- If `isScheduled == true`, render a Scheduled Ride variant card.
- Show `Scheduled Ride` badge and scheduled pickup date/time prominently.
- If `isPriority == true`, show `Priority - Driver Needed!` badge.
- Accept with existing endpoint: `POST /rides/:id/accept`.

### 2.2 Accept Scheduled Ride

**Endpoint**: `POST /rides/:id/accept`  
**Auth**: Bearer token (Driver)

No API changes. Response includes `isScheduled: true` and `scheduledPickupTime` when applicable.

### 2.3 Cancel Scheduled Ride (Driver)

**Endpoint**: `POST /rides/:id/cancel/scheduled/driver`  
**Auth**: Bearer token (Driver)

**Request Body**:

```json
{
  "reason": "vehicle_issue"
}
```

Valid reasons:

- `rider_no_show`
- `safety_concern`
- `rider_unreachable`
- `vehicle_issue`
- `driver_no_show`

**Response (200)**:

```json
{
  "success": true,
  "message": "Scheduled ride driver cancelled. Ride flagged for priority re-assignment.",
  "data": {
    "_id": "660f...",
    "status": "scheduled",
    "driver": null,
    "isPriority": true,
    "driverPenaltyAmount": 4.5
  }
}
```

**Flutter Action**:

- Show warning before confirm: `Cancelling a scheduled ride will incur a 10% penalty (£X.XX)`.
- After cancellation, remove from driver's active rides.
- Ride returns to pool and is re-broadcast to other drivers.

### 2.4 Scheduled Ride Reminders

Drivers receive reminders through FCM and Socket events.

**Flutter Action**:

- On reminder, show local notification/in-app reminder card.
- 1-hour reminder text: `You have a scheduled pickup in 1 hour at [address]`.
- 15-min reminder text: `Scheduled pickup in 15 minutes at [address]`.

## 3. Socket Events (New)

### 3.1 User App Listeners

| Event | When | Payload |
|---|---|---|
| `ride:depositConfirmed` | Deposit payment confirmed via Stripe webhook | `{ rideId, amount, message }` |
| `ride:scheduledActivated` | Ride activated (60 min before pickup) | `{ rideId, message, scheduledPickupTime }` |
| `ride:scheduledDriverCancelled` | Driver cancelled scheduled ride | `{ rideId, message, isPriority }` |
| `ride:reminder` | 1-hour or 15-min pre-pickup reminder | `{ rideId, reminderType, scheduledPickupTime, message }` |
| `ride:depositTimeout` | Deposit not paid within 30 min | `{ rideId, message }` |
| `ride:scheduledExpired` | No driver found 45 min after pickup time | `{ rideId, message }` |
| `ride:noShow` | User marked no-show | `{ rideId, message, depositForfeited }` |
| `ride:accepted` | Driver accepted (existing event) | Existing payload + `isScheduled`, `scheduledPickupTime` |
| `ride:driverArrived` | Driver arrived (existing event) | Existing payload |

### 3.2 Driver App Listeners

| Event | When | Payload |
|---|---|---|
| `ride:newRequest` | Scheduled ride broadcast to drivers | Existing payload + `isScheduled`, `scheduledPickupTime`, `isPriority` |
| `ride:scheduledCancelledByUser` | User cancelled scheduled ride | `{ rideId, message }` |
| `ride:reminder` | 1-hour or 15-min pre-pickup reminder | `{ rideId, reminderType, scheduledPickupTime, message }` |

## 4. FCM Notifications (New)

### 4.1 User App Notifications

| Type (`data.type`) | Title | Trigger |
|---|---|---|
| `scheduled_reminder_1hr` | `Ride Reminder` | 1 hour before pickup |
| `scheduled_reminder_15min` | `Ride Starting Soon!` | 15 min before pickup |
| `scheduled_ride_activated` | `Finding Your Driver` | Ride enters matching |
| `scheduled_driver_cancelled` | `Driver Changed` | Driver cancelled, re-broadcasting |
| `deposit_timeout` | `Booking Expired` | Deposit not paid within 30 min |
| `scheduled_ride_expired` | `No Driver Available` | No driver found; deposit refunded |
| `scheduled_no_show` | `Ride Cancelled - No Show` | User did not show up |

### 4.2 Driver App Notifications

| Type (`data.type`) | Title | Trigger |
|---|---|---|
| `scheduled_reminder_1hr` | `Scheduled Ride Reminder` | 1 hour before pickup |
| `scheduled_reminder_15min` | `Pickup in 15 Minutes!` | 15 min before pickup |
| `ride_request` + `isScheduled: true` | `Scheduled Ride Available` | Scheduled ride broadcast |
| `ride_request` + `isPriority: true` | `Priority Ride - Driver Needed!` | Priority re-broadcast |
| `scheduled_ride_cancelled_by_user` | `Scheduled Ride Cancelled` | User cancelled |

## 5. End-to-End Flow

### 5.1 User App Flow

1. User opens Schedule Ride screen.
2. User enters locations + date/time + optional note.
3. Validate scheduling window: minimum 1 hour from now, maximum 30 days.
4. Call `POST /rides/schedule`.
5. Show summary + 10% deposit.
6. Open Stripe payment using returned `clientSecret` (card method).
7. On success, call `POST /rides/:id/confirm-deposit` (optional fallback) or wait for `ride:depositConfirmed`.
8. Show `Ride Scheduled` confirmation.
9. Display ride in `My Scheduled Rides` (`GET /rides/scheduled`).
10. Receive reminders via FCM + socket (1 hour and 15 minutes).
11. Handle `ride:scheduledActivated` and show searching state.
12. Handle `ride:accepted` and continue existing ride flow.
13. On arrival, use existing `select-payment` flow for remaining 90%.
14. Ride continues through normal start/completion lifecycle.

### 5.2 Driver App Flow

1. Receive `ride:newRequest` with `isScheduled` and optional `isPriority`.
2. Render scheduled request UI card with date/time and badges.
3. Accept via `POST /rides/:id/accept`.
4. Store under upcoming scheduled rides.
5. Receive reminder notifications/events at 1 hour and 15 minutes.
6. Follow existing arrival and start flow (`/arrive`, `/start` with OTP).
7. If needed, cancel via `POST /rides/:id/cancel/scheduled/driver` and show penalty warning.
8. Ride is re-broadcast (priority) and not permanently closed due to driver cancellation.
9. Otherwise ride completes as normal.

## 6. Key Differences from Regular Rides

| Aspect | Regular Ride | Scheduled Ride |
|---|---|---|
| Payment | Full fare at driver arrival | 10% deposit upfront + 90% at arrival |
| Status progression | `requested -> accepted -> ...` | `scheduled -> requested -> accepted -> ...` |
| Driver matching | Immediate broadcast | Activated by cron 60 min before pickup |
| User cancellation | Grace period from acceptance | 4-hour free window from booking |
| Driver cancellation | No penalty | 10% penalty + priority re-broadcast |
| Expiry | ~1 minute no-response timeout | 45 min past pickup time |
| New fields | N/A | `isScheduled`, `scheduledPickupTime`, `depositAmount`, `depositStatus` |

## 7. UI Screens Needed

### 7.1 User App

- Schedule Ride screen: existing location fields + date/time picker + optional note.
- Deposit payment sheet: Stripe card payment for 10% deposit.
- Scheduled ride confirmation screen with ride details.
- My Scheduled Rides list with cancellation option.
- Cancellation dialog showing refund or forfeiture impact.

### 7.2 Driver App

- Scheduled Ride Request card: variant with scheduled date/time + priority badge.
- Cancel Scheduled Ride dialog with 10% penalty warning.
- Upcoming Scheduled Rides list (optional).
