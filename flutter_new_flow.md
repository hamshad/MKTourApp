Here is the complete API documentation reflecting the **latest ride flow updates** from the recent git commit (`major ride flow change`).

All request and response examples are in valid JSON format for direct integration with your Flutter app.

---

### :key: Key Changes in the Latest Git Commit
1. **No-OTP Ride Start**: `POST /rides/:id/start` no longer requires an OTP body parameter.
2. **Intermediate Stops Flow**: Added `POST /rides/:id/stop/arrive` and `POST /rides/:id/stop/resume` endpoints to manage multi-stop trips.
3. **Waiting Time & Fee Aggregation**: Automatic 5-minute free window + £0.35/min rate computed per stop and pickup, populating `totalWaitFee` and `actualFare`.
4. **Driver Cancellation Auto Re-Assignment**: Driver cancelling before pickup auto-reassigns to nearby eligible drivers without terminating the user's ride.

---

## :bookmark_tabs: Common Headers
For all authenticated endpoints below, pass:
```json
{
  "Authorization": "Bearer <JWT_ACCESS_TOKEN>",
  "Content-Type": "application/json"
}
```

---

## 1. Fare Estimate (Pre-Booking)
Calculates fare estimates across all vehicle categories (incorporates discounts, tariffs, and congestion charges).

- **Method**: `GET`
- **Endpoint**: `/rides/fare-estimate`
- **Access**: User

### Query Parameters
`pickupLon`, `pickupLat`, `dropoffLon`, `dropoffLat`, `distance` (in miles), `stops` (optional JSON string)

### Example Request URL
```
GET /rides/fare-estimate?pickupLon=-0.7594&pickupLat=52.0406&dropoffLon=-0.7650&dropoffLat=52.0500&distance=3.5
```

### Success Response (`200 OK`)
```json
{
  "success": true,
  "message": "Fare estimates fetched successfully",
  "data": [
    {
      "categorySlug": "standard",
      "categoryName": "Standard",
      "seatingCapacity": 4,
      "estimatedFare": 12.50,
      "originalFare": 12.50,
      "isPromoApplied": false,
      "isCongestionCharge": false,
      "congestionChargeAmount": 0
    },
    {
      "categorySlug": "executive",
      "categoryName": "Executive",
      "seatingCapacity": 4,
      "estimatedFare": 18.00,
      "originalFare": 18.00,
      "isPromoApplied": false,
      "isCongestionCharge": false,
      "congestionChargeAmount": 0
    }
  ]
}
```

### Error Response (`400 Bad Request`)
```json
{
  "success": false,
  "message": "pickupLon, pickupLat, dropoffLon, dropoffLat, and distance are required",
  "errors": null
}
```

---

## 2. Create Instant Ride Request
Creates an immediate ride request and notifies nearby online drivers.

- **Method**: `POST`
- **Endpoint**: `/rides/create`
- **Access**: User

### Request Body
```json
{
  "pickupLocation": {
    "address": "Milton Keynes Central Station",
    "coordinates": [-0.7594, 52.0406]
  },
  "dropoffLocation": {
    "address": "Bletchley Park, Milton Keynes",
    "coordinates": [-0.7650, 52.0500]
  },
  "vehicleCategorySlug": "standard",
  "distance": 3.5,
  "duration": 12,
  "stops": [
    {
      "stopOrder": 1,
      "address": "Midsummer Boulevard",
      "coordinates": [-0.7610, 52.0430]
    }
  ]
}
```

### Success Response (`201 Created`)
```json
{
  "success": true,
  "message": "Ride request created successfully",
  "data": {
    "_id": "66df1a2b3c4d5e6f7a8b9c0d",
    "user": "66de0f1a2b3c4d5e6f7a8b9c",
    "status": "requested",
    "vehicleCategorySlug": "standard",
    "pickupLocation": {
      "type": "Point",
      "coordinates": [-0.7594, 52.0406],
      "address": "Milton Keynes Central Station"
    },
    "dropoffLocation": {
      "type": "Point",
      "coordinates": [-0.7650, 52.0500],
      "address": "Bletchley Park, Milton Keynes"
    },
    "stops": [
      {
        "stopOrder": 1,
        "address": "Midsummer Boulevard",
        "coordinates": [-0.7610, 52.0430],
        "status": "pending",
        "waitTimeMinutes": 0,
        "waitFee": 0
      }
    ],
    "fare": 12.50,
    "distance": 3.5,
    "duration": 12,
    "isScheduled": false,
    "createdAt": "2026-09-09T15:00:00.000Z"
  }
}
```

### Error Response (`400 Bad Request`)
```json
{
  "success": false,
  "message": "Pickup and dropoff locations are required",
  "errors": null
}
```

---

## 3. Accept Ride
Driver accepts a requested ride.

- **Method**: `POST`
- **Endpoint**: `/rides/:id/accept`
- **Access**: Driver

### Request Body
```json
{}
```

### Success Response (`200 OK`)
```json
{
  "success": true,
  "message": "Ride accepted successfully",
  "data": {
    "_id": "66df1a2b3c4d5e6f7a8b9c0d",
    "status": "accepted",
    "driver": "66dd8f1a2b3c4d5e6f7a8b9c",
    "user": "66de0f1a2b3c4d5e6f7a8b9c",
    "acceptedAt": "2026-09-09T15:02:00.000Z"
  }
}
```

### Error Response (`400 Bad Request`)
```json
{
  "success": false,
  "message": "Ride is not available",
  "errors": null
}
```

---

## 4. Driver Arrives at Pickup
Confirms driver has reached pickup. Enforces 100m proximity check and starts the 5-min free waiting timer.

- **Method**: `POST`
- **Endpoint**: `/rides/:id/arrive`
- **Access**: Driver

### Request Body
```json
{
  "latitude": 52.0406,
  "longitude": -0.7594
}
```

### Success Response (`200 OK`)
```json
{
  "success": true,
  "message": "Arrival confirmed. Ready to start ride.",
  "data": {
    "isAtPickup": true,
    "arrivedAt": "2026-09-09T15:05:00.000Z",
    "freeMinutes": 5,
    "perMinuteRate": 0.35
  }
}
```

### Error Response (`400 Bad Request` - Location Out of Range)
```json
{
  "success": false,
  "message": "You must be within 100 meters of the pickup location",
  "errors": {
    "distance": 250,
    "required": 100
  }
}
```

---

## 5. Select Payment Method
Passenger selects Cash or Card/Stripe payment method after driver arrives.

- **Method**: `POST`
- **Endpoint**: `/rides/:id/select-payment`
- **Access**: User

### Request Body
```json
{
  "paymentMethod": "cash"
}
```
*(Options: `"cash"`, `"stripe"`, `"payment_link"`)*

### Success Response (`200 OK`)
```json
{
  "success": true,
  "message": "Payment method selected successfully",
  "data": {
    "ride": {
      "paymentMethod": "cash",
      "clientSecret": null,
      "amount": 12.50,
      "currency": "gbp",
      "status": "in_progress",
      "paymentUrl": null
    }
  }
}
```

### Error Response (`400 Bad Request`)
```json
{
  "success": false,
  "message": "Invalid payment method",
  "errors": null
}
```

---

## 6. Start Ride *(OTP Removed)*
Starts trip when passenger boards vehicle. No OTP code required in payload.

- **Method**: `POST`
- **Endpoint**: `/rides/:id/start`
- **Access**: Driver

### Request Body
```json
{}
```

### Success Response (`200 OK`)
```json
{
  "success": true,
  "message": "Ride started successfully",
  "data": {
    "_id": "66df1a2b3c4d5e6f7a8b9c0d",
    "status": "in_progress",
    "startedAt": "2026-09-09T15:08:00.000Z",
    "pickupWait": {
      "arrivedAt": "2026-09-09T15:00:00.000Z",
      "startedAt": "2026-09-09T15:08:00.000Z",
      "waitTimeMinutes": 3,
      "waitFee": 1.05
    }
  }
}
```

### Error Response (`400 Bad Request`)
```json
{
  "success": false,
  "message": "Ride must be in driver_arrived state to start",
  "errors": null
}
```

---

## 7. Driver Arrives at Intermediate Stop *(New Flow)*
Driver marks arrival at an intermediate stop. Verifies 100m proximity and sets ride status to `at_stop`.

- **Method**: `POST`
- **Endpoint**: `/rides/:id/stop/arrive`
- **Access**: Driver

### Request Body
```json
{
  "latitude": 52.0430,
  "longitude": -0.7610
}
```

### Success Response (`200 OK`)
```json
{
  "success": true,
  "message": "Arrived at stop successfully",
  "data": {
    "rideId": "66df1a2b3c4d5e6f7a8b9c0d",
    "currentStopIndex": 0,
    "status": "at_stop",
    "stops": [
      {
        "stopOrder": 1,
        "address": "Midsummer Boulevard",
        "coordinates": [-0.7610, 52.0430],
        "status": "arrived",
        "arrivedAt": "2026-09-09T15:12:00.000Z",
        "waitTimeMinutes": 0,
        "waitFee": 0
      }
    ]
  }
}
```

### Error Response (`400 Bad Request`)
```json
{
  "success": false,
  "message": "You must be within 100 meters of Stop #1 (Midsummer Boulevard)",
  "errors": {
    "distance": 180,
    "required": 100
  }
}
```

---

## 8. Driver Resumes Journey from Stop *(New Flow)*
Driver departs stop. Computes stop wait fee (5 free mins, £0.35/min thereafter), updates total trip wait fees, and transitions status back to `in_progress`.

- **Method**: `POST`
- **Endpoint**: `/rides/:id/stop/resume`
- **Access**: Driver

### Request Body
```json
{}
```

### Success Response (`200 OK`)
```json
{
  "success": true,
  "message": "Trip resumed successfully",
  "data": {
    "rideId": "66df1a2b3c4d5e6f7a8b9c0d",
    "currentStopIndex": 1,
    "status": "in_progress",
    "totalWaitMinutes": 5,
    "totalWaitFee": 1.75,
    "stops": [
      {
        "stopOrder": 1,
        "address": "Midsummer Boulevard",
        "coordinates": [-0.7610, 52.0430],
        "status": "completed",
        "arrivedAt": "2026-09-09T15:12:00.000Z",
        "departedAt": "2026-09-09T15:22:00.000Z",
        "waitTimeMinutes": 5,
        "waitFee": 1.75
      }
    ]
  }
}
```

### Error Response (`400 Bad Request`)
```json
{
  "success": false,
  "message": "Ride must be at a stop to resume",
  "errors": null
}
```

---

## 9. Complete Ride
Driver completes ride at dropoff location. Calculates total fare including base fare + accumulated wait fees (`actualFare`).

- **Method**: `POST` (or `PATCH`)
- **Endpoint**: `/rides/:id/complete`
- **Access**: Driver

### Request Body
```json
{
  "latitude": 52.0500,
  "longitude": -0.7650
}
```

### Success Response (`200 OK`)
```json
{
  "success": true,
  "message": "Ride completed successfully",
  "data": {
    "_id": "66df1a2b3c4d5e6f7a8b9c0d",
    "status": "completed",
    "fare": 12.50,
    "totalWaitMinutes": 5,
    "totalWaitFee": 1.75,
    "actualFare": 14.25,
    "paymentStatus": "pending_collection",
    "completedAt": "2026-09-09T15:30:00.000Z"
  }
}
```

### Error Response (`400 Bad Request`)
```json
{
  "success": false,
  "message": "Latitude and longitude are required to complete ride",
  "errors": null
}
```

---

## 10. Confirm Cash Collection
Driver confirms physical cash received from passenger.

- **Method**: `POST`
- **Endpoint**: `/rides/:id/confirm-cash`
- **Access**: Driver

### Request Body
```json
{}
```

### Success Response (`200 OK`)
```json
{
  "success": true,
  "message": "Cash collection confirmed successfully",
  "data": {
    "ride": {
      "_id": "66df1a2b3c4d5e6f7a8b9c0d",
      "paymentStatus": "succeeded",
      "paymentMethod": "cash"
    },
    "paymentStatus": "succeeded"
  }
}
```

### Error Response (`400 Bad Request`)
```json
{
  "success": false,
  "message": "Ride must be completed before confirming cash collection",
  "errors": null
}
```

---

## 11. Cancel Ride (User)
User cancels an active ride before it starts.

- **Method**: `POST`
- **Endpoint**: `/rides/:id/cancel/user`
- **Access**: User

### Request Body
```json
{
  "reason": "changed_my_mind"
}
```

### Success Response (`200 OK`)
```json
{
  "success": true,
  "message": "Ride cancelled successfully",
  "data": {
    "ride": {
      "_id": "66df1a2b3c4d5e6f7a8b9c0d",
      "status": "cancelled_by_user",
      "cancellationReason": "changed_my_mind",
      "cancellationFee": 0
    },
    "cancellationFee": 0,
    "refundStatus": "refunded"
  }
}
```

### Error Response (`400 Bad Request`)
```json
{
  "success": false,
  "message": "Cannot cancel ride after it has started",
  "errors": null
}
```

---

## 12. Cancel Ride (Driver)
Driver cancels a ride.
- **Before Pickup**: Auto-reassigns to other nearby drivers (Ride status remains `requested`, returns `reassigned: true`).
- **At Pickup**: Full cancellation with status `cancelled_by_driver`.

- **Method**: `POST`
- **Endpoint**: `/rides/:id/cancel/driver`
- **Access**: Driver

### Request Body
```json
{
  "reason": "vehicle_breakdown"
}
```

### Success Response — Reassigned Path (`200 OK`)
```json
{
  "success": true,
  "message": "Ride reassigned to other drivers",
  "data": {
    "ride": {
      "_id": "66df1a2b3c4d5e6f7a8b9c0d",
      "status": "requested",
      "reassignmentCount": 1,
      "isPriority": true
    },
    "reassigned": true,
    "reassignmentCount": 1
  }
}
```

### Success Response — Full Cancellation Path (`200 OK`)
```json
{
  "success": true,
  "message": "Ride cancelled successfully",
  "data": {
    "_id": "66df1a2b3c4d5e6f7a8b9c0d",
    "status": "cancelled_by_driver",
    "cancellationReason": "vehicle_breakdown"
  }
}
```

### Error Response (`400 Bad Request`)
```json
{
  "success": false,
  "message": "Cancellation reason is required",
  "errors": null
}
```

---

## 13. End Ride Early
Driver terminates trip early before reaching final dropoff (e.g. passenger request).

- **Method**: `POST` (or `PATCH`)
- **Endpoint**: `/rides/:id/end-early`
- **Access**: Driver

### Request Body
```json
{
  "latitude": 52.0420,
  "longitude": -0.7610,
  "reason": "user_requested"
}
```

### Success Response (`200 OK`)
```json
{
  "success": true,
  "message": "Ride ended successfully",
  "data": {
    "ride": {
      "_id": "66df1a2b3c4d5e6f7a8b9c0d",
      "status": "early_completed",
      "fare": 8.50,
      "actualDistance": 2.1,
      "earlyEndReason": "user_requested"
    },
    "adjustedFare": 8.50,
    "actualDistance": 2.1
  }
}
```

---

## 14. Rate Ride
User leaves rating & optional text review.

- **Method**: `POST`
- **Endpoint**: `/rides/:id/rate`
- **Access**: User

### Request Body
```json
{
  "rating": 5,
  "feedback": "Great service and clean car!"
}
```

### Success Response (`200 OK`)
```json
{
  "success": true,
  "message": "Ride rated successfully",
  "data": {
    "_id": "66df1a2b3c4d5e6f7a8b9c0d",
    "rating": 5,
    "feedback": "Great service and clean car!"
  }
}
```

### Error Response (`400 Bad Request`)
```json
{
  "success": false,
  "message": "Rating must be between 1 and 5",
  "errors": null
}
```
