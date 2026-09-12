Viewed ride.routes.js:1-120
Searched for "ride.routes"
Viewed app.js:1-146
Here is the complete API specification for integrating the scheduled ride flow in your Flutter apps (both User and Driver side).
---
## 👤 USER SIDE APIS
### 1. Create Scheduled Ride
* **Endpoint**: `POST /api/v1/rides/schedule`
* **Headers**: `Authorization: Bearer <user_token>`, `Content-Type: application/json`
* **Description**: Create a scheduled ride at least 2 hours in advance (up to 30 days) with optional multi-stops (up to 3 intermediate stops) and full upfront payment.
#### Success Request:
```json
{
  "pickupLocation": {
    "coordinates": [-0.7594, 52.0406],
    "address": "Milton Keynes Central Station, MK9 1LA"
  },
  "dropoffLocation": {
    "coordinates": [-0.7201, 52.0350],
    "address": "Bletchley Park, MK3 6EB"
  },
  "stops": [
    {
      "coordinates": [-0.7500, 52.0380],
      "address": "Centre MK Shopping Centre, MK9 3EP"
    }
  ],
  "pickupTime": "2026-09-11T10:00:00.000Z",
  "vehicleCategorySlug": "saloon",
  "paymentMethod": "stripe",
  "preBookingNote": "Luggage in boot please"
}
```
#### Success Response (`201 Created`):
```json
{
  "success": true,
  "message": "Scheduled ride created successfully. Full payment initialized.",
  "data": {
    "ride": {
      "_id": "66e07a1b9f1d2e0012ab3456",
      "user": "66d01234567890abcdef1234",
      "pickupLocation": {
        "type": "Point",
        "coordinates": [-0.7594, 52.0406],
        "address": "Milton Keynes Central Station, MK9 1LA"
      },
      "dropoffLocation": {
        "type": "Point",
        "coordinates": [-0.7201, 52.0350],
        "address": "Bletchley Park, MK3 6EB"
      },
      "stops": [
        {
          "type": "Point",
          "coordinates": [-0.7500, 52.0380],
          "address": "Centre MK Shopping Centre, MK9 3EP",
          "stopOrder": 1,
          "status": "pending"
        }
      ],
      "vehicleCategorySlug": "saloon",
      "fare": 18.50,
      "distance": 5.4,
      "status": "scheduled",
      "isScheduled": true,
      "scheduledPickupTime": "2026-09-11T10:00:00.000Z",
      "depositAmount": 0,
      "createdAt": "2026-09-10T16:40:00.000Z"
    },
    "payment": {
      "paymentMethod": "stripe",
      "clientSecret": "pi_3Nxyz123456_secret_abc123",
      "status": "requires_payment_method"
    }
  }
}
```
#### Error Response (`400 Bad Request` - Booking Window < 2 Hours):
```json
{
  "success": false,
  "message": "Scheduled rides must be booked at least 2 hours in advance"
}
```
#### Error Response (`400 Bad Request` - Booking > 30 Days):
```json
{
  "success": false,
  "message": "Scheduled rides cannot be booked more than 30 days in advance"
}
```
---
### 2. Get User's Scheduled Rides
* **Endpoint**: `GET /api/v1/rides/scheduled`
* **Headers**: `Authorization: Bearer <user_token>`
* **Description**: Returns all scheduled/pre-booked rides booked by the user.
#### Success Response (`200 OK`):
```json
{
  "success": true,
  "count": 1,
  "data": [
    {
      "_id": "66e07a1b9f1d2e0012ab3456",
      "pickupLocation": {
        "address": "Milton Keynes Central Station, MK9 1LA",
        "coordinates": [-0.7594, 52.0406]
      },
      "dropoffLocation": {
        "address": "Bletchley Park, MK3 6EB",
        "coordinates": [-0.7201, 52.0350]
      },
      "stops": [
        {
          "address": "Centre MK Shopping Centre, MK9 3EP",
          "coordinates": [-0.7500, 52.0380],
          "stopOrder": 1,
          "status": "pending"
        }
      ],
      "vehicleCategorySlug": "saloon",
      "fare": 18.50,
      "status": "scheduled",
      "isScheduled": true,
      "scheduledPickupTime": "2026-09-11T10:00:00.000Z",
      "driver": null
    }
  ]
}
```
---
### 3. Cancel Scheduled Ride by User
* **Endpoint**: `POST /api/v1/rides/:id/cancel/scheduled/user`
* **Headers**: `Authorization: Bearer <user_token>`, `Content-Type: application/json`
#### Request Body:
```json
{
  "cancellationReason": "Change of plans"
}
```
#### Success Response (`200 OK`):
```json
{
  "success": true,
  "message": "Scheduled ride cancelled successfully. Full refund issued.",
  "data": {
    "rideId": "66e07a1b9f1d2e0012ab3456",
    "status": "cancelled",
    "refundIssued": true
  }
}
```
---
## 🚗 DRIVER SIDE APIS
### 1. Get Open Pool Scheduled Rides
* **Endpoint**: `GET /api/v1/rides/scheduled/pool`
* **Headers**: `Authorization: Bearer <driver_token>`
* **Description**: Returns all available, unassigned scheduled rides across Milton Keynes filtered by driver vehicle capacity. Excludes rides that conflict with the driver's schedule within 30 minutes.
#### Success Response (`200 OK`):
```json
{
  "success": true,
  "count": 1,
  "data": [
    {
      "_id": "66e07a1b9f1d2e0012ab3456",
      "user": {
        "_id": "66d01234567890abcdef1234",
        "name": "John Doe",
        "phone": "+447123456789",
        "profilePicture": "https://example.com/avatar.jpg"
      },
      "pickupLocation": {
        "address": "Milton Keynes Central Station, MK9 1LA",
        "coordinates": [-0.7594, 52.0406]
      },
      "dropoffLocation": {
        "address": "Bletchley Park, MK3 6EB",
        "coordinates": [-0.7201, 52.0350]
      },
      "stops": [
        {
          "address": "Centre MK Shopping Centre, MK9 3EP",
          "coordinates": [-0.7500, 52.0380],
          "stopOrder": 1
        }
      ],
      "vehicleCategorySlug": "saloon",
      "fare": 18.50,
      "distance": 5.4,
      "status": "scheduled",
      "isScheduled": true,
      "scheduledPickupTime": "2026-09-11T10:00:00.000Z"
    }
  ]
}
```
---
### 2. Claim / Accept Scheduled Ride (or Normal Ride)
* **Endpoint**: `POST /api/v1/rides/:id/accept`
* **Headers**: `Authorization: Bearer <driver_token>`
* **Description**: Claim an open pool scheduled ride or accept a normal ride request.
#### Success Response (`200 OK`):
```json
{
  "success": true,
  "message": "Ride accepted successfully",
  "data": {
    "_id": "66e07a1b9f1d2e0012ab3456",
    "driver": "66d9998877665544332211aa",
    "status": "accepted",
    "acceptedAt": "2026-09-10T16:42:00.000Z",
    "isScheduled": true,
    "scheduledPickupTime": "2026-09-11T10:00:00.000Z"
  }
}
```
#### Error Response (`400 Bad Request` - 30-Minute Schedule Conflict):
```json
{
  "success": false,
  "message": "Cannot accept ride: You have another scheduled ride within 30 minutes of this pickup time"
}
```
#### Error Response (`400 Bad Request` - Driver Busy with Ongoing Ride Right Now):
```json
{
  "success": false,
  "message": "Driver already has an active ride or an upcoming scheduled ride starting within 30 minutes"
}
```
#### Error Response (`400 Bad Request` - Ride Already Taken by Another Driver):
```json
{
  "success": false,
  "message": "Ride is not available"
}
```
---
### 3. Get Driver's Claimed Scheduled Rides ("My Scheduled Rides")
* **Endpoint**: `GET /api/v1/rides/scheduled/driver`
* **Headers**: `Authorization: Bearer <driver_token>`
* **Description**: Returns all claimed scheduled rides assigned to the driver.
#### Success Response (`200 OK`):
```json
{
  "success": true,
  "count": 1,
  "data": [
    {
      "_id": "66e07a1b9f1d2e0012ab3456",
      "user": {
        "_id": "66d01234567890abcdef1234",
        "name": "John Doe",
        "phone": "+447123456789",
        "profilePicture": "https://example.com/avatar.jpg"
      },
      "pickupLocation": {
        "address": "Milton Keynes Central Station, MK9 1LA",
        "coordinates": [-0.7594, 52.0406]
      },
      "dropoffLocation": {
        "address": "Bletchley Park, MK3 6EB",
        "coordinates": [-0.7201, 52.0350]
      },
      "stops": [],
      "vehicleCategorySlug": "saloon",
      "fare": 18.50,
      "status": "accepted",
      "isScheduled": true,
      "scheduledPickupTime": "2026-09-11T10:00:00.000Z"
    }
  ]
}
```
---
### 4. Driver Intermediate Stop Management Endpoints
Used during multi-stop journeys for both normal and scheduled rides:
#### a) Arrive at Intermediate Stop: `POST /api/v1/rides/:id/stop/arrive`
```json
// Success Response (200 OK)
{
  "success": true,
  "message": "Arrived at stop 1",
  "data": {
    "rideId": "66e07a1b9f1d2e0012ab3456",
    "currentStopIndex": 0,
    "stopStatus": "arrived"
  }
}
```
#### b) Depart / Resume Trip from Intermediate Stop: `POST /api/v1/rides/:id/stop/resume`
```json
// Success Response (200 OK)
{
  "success": true,
  "message": "Resuming trip to next destination",
  "data": {
    "rideId": "66e07a1b9f1d2e0012ab3456",
    "currentStopIndex": 1,
    "completedStop": "Centre MK Shopping Centre, MK9 3EP"
  }
}
```
