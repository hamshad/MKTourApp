Here is the complete, production-ready API specification, Socket.io contract, and FCM notification breakdown for both the User Mobile App and Driver Mobile App under the trust-based model (upfront toll detection, zero driver commission on tolls, 100% reimbursement).

SECTION 1: User Mobile App Specifications
1.1 Fare Estimate
Called when user sets pickup and dropoff destinations on the map.

Method / Endpoint: GET /api/v1/rides/fare-estimate
Headers: Authorization: Bearer <user_jwt_token>
Query Parameters:
pickupLat (float, required): 52.4862
pickupLng (float, required): -1.8904
dropoffLat (float, required): 52.6000
dropoffLng (float, required): -1.9000
vehicleCategoryId (string, optional): Category ID if pre-selected.
Success Scenario (200 OK)
json
{
  "success": true,
  "message": "Fare estimated successfully",
  "data": {
    "distanceKm": 24.5,
    "durationMinutes": 28,
    "hasToll": true,
    "tollDetails": {
      "name": "M6 Toll Highway",
      "amount": 8.90,
      "currency": "GBP"
    },
    "categories": [
      {
        "vehicleCategoryId": "67041a8e2b83a001a1c8f101",
        "categoryName": "Standard Saloon",
        "baseFare": 3.50,
        "distanceFare": 25.00,
        "timeFare": 4.50,
        "standardRideFare": 33.00,
        "tollFee": 8.90,
        "totalFare": 41.90,
        "currency": "GBP"
      },
      {
        "vehicleCategoryId": "67041a8e2b83a001a1c8f102",
        "categoryName": "Executive / MPV",
        "baseFare": 5.00,
        "distanceFare": 32.00,
        "timeFare": 6.00,
        "standardRideFare": 43.00,
        "tollFee": 11.50,
        "totalFare": 54.50,
        "currency": "GBP"
      }
    ]
  }
}
Error Scenarios
400 Bad Request (Missing Coordinates):
json
{ "success": false, "message": "Pickup and dropoff coordinates are required" }
404 Not Found (Outside Service Area):
json
{ "success": false, "message": "Pickup location is outside our operational service area" }
1.2 Book / Create Ride
Called when user confirms booking with chosen payment method.

Method / Endpoint: POST /api/v1/rides/create (or /api/v1/rides/schedule for advance bookings)
Headers: Authorization: Bearer <user_jwt_token>, Content-Type: application/json
Request Body
json
{
  "pickup": {
    "address": "Birmingham City Centre",
    "location": { "lat": 52.4862, "lng": -1.8904 }
  },
  "dropoff": {
    "address": "Cannock Retail Park",
    "location": { "lat": 52.6000, "lng": -1.9000 }
  },
  "vehicleCategoryId": "67041a8e2b83a001a1c8f101",
  "paymentType": "stripe",
  "scheduledTime": null
}
Success Scenario (201 Created)
json
{
  "success": true,
  "message": "Ride requested successfully",
  "data": {
    "rideId": "67045b8e9a21a002b2c9e201",
    "status": "pending",
    "fareBreakdown": {
      "standardFare": 33.00,
      "tollFee": 8.90,
      "tollName": "M6 Toll Highway",
      "isTollIncurred": true,
      "totalFare": 41.90,
      "currency": "GBP"
    },
    "paymentType": "stripe",
    "paymentStatus": "hold_placed"
  }
}
Error Scenarios
402 Payment Required (Card hold / payment intent failed):
json
{ "success": false, "message": "Payment method authorization failed. Please check card details." }
409 Conflict (User already has an active ongoing ride):
json
{ "success": false, "message": "You already have an ongoing active trip" }
1.3 Ride Details & Final Receipt
Called on ride completion or from user's trip history.

Method / Endpoint: GET /api/v1/rides/:rideId
Headers: Authorization: Bearer <user_jwt_token>
Success Scenario (200 OK)
json
{
  "success": true,
  "data": {
    "rideId": "67045b8e9a21a002b2c9e201",
    "status": "completed",
    "pickup": { "address": "Birmingham City Centre" },
    "dropoff": { "address": "Cannock Retail Park" },
    "driver": {
      "name": "David Smith",
      "carModel": "Toyota Prius (Silver)",
      "plateNumber": "WP19 XYZ"
    },
    "receipt": {
      "tripFare": 33.00,
      "tollFee": 8.90,
      "tollName": "M6 Toll Highway",
      "totalCharged": 41.90,
      "paymentMethod": "stripe",
      "currency": "GBP"
    },
    "completedAt": "2026-10-08T11:45:00.000Z"
  }
}
SECTION 2: Driver Mobile App Specifications
2.1 Complete Ride
Called when driver slides to finish the trip at the destination.

Method / Endpoint: POST /api/v1/rides/:rideId/complete
Headers: Authorization: Bearer <driver_jwt_token>, Content-Type: application/json
Request Body
json
{
  "lat": 52.6001,
  "lng": -1.9002
}
Success Scenario (200 OK)
json
{
  "success": true,
  "message": "Ride completed successfully",
  "data": {
    "rideId": "67045b8e9a21a002b2c9e201",
    "status": "completed",
    "earnings": {
      "customerFare": 33.00,
      "platformCommissionPercent": 20,
      "platformFee": 6.60,
      "netTripEarnings": 26.40,
      "tollReimbursed": 8.90,
      "tollName": "M6 Toll Highway",
      "totalDriverTakeHome": 35.30,
      "currency": "GBP"
    },
    "cashAction": {
      "isCashTrip": false,
      "cashToCollectFromCustomer": 0.00,
      "amountOwedToPlatform": 0.00
    }
  }
}
(If it was a Cash Trip, cashToCollectFromCustomer = £41.90, and amountOwedToPlatform = £6.60 deducted from driver's digital wallet).

Error Scenarios
400 Bad Request (Trip not in ongoing/started state):
json
{ "success": false, "message": "Ride cannot be completed as it is currently in 'arrived' status" }
403 Forbidden (Driver attempting to complete someone else's trip):
json
{ "success": false, "message": "You are not the assigned driver for this trip" }
2.2 Driver Earnings Summary
Powers the driver's Earnings Dashboard (tabs: Today, Week, Month, All).

Method / Endpoint: GET /api/v1/drivers/earnings/summary
Headers: Authorization: Bearer <driver_jwt_token>
Query Parameters:
period (string, required): today | yesterday | week | month | all
Success Scenario (200 OK)
json
{
  "success": true,
  "data": {
    "period": "week",
    "tripsCompleted": 18,
    "onlineHours": 24.5,
    "grossPassengerFares": 620.00,
    "platformDeductions": 124.00,
    "netTripEarnings": 496.00,
    "tollsReimbursedTotal": 35.60,
    "totalEarnings": 531.60,
    "payoutStatus": {
      "unsettledBalance": 310.50,
      "nextPayoutDate": "2026-10-12T00:00:00.000Z"
    },
    "currency": "GBP"
  }
}
2.3 Driver Earnings Rides List
Powers the driver's itemized ride list in their Earnings screen.

Method / Endpoint: GET /api/v1/drivers/earnings/rides
Headers: Authorization: Bearer <driver_jwt_token>
Query Parameters:
period (string, optional): today | yesterday | week | month | all
page (integer, optional): 1
limit (integer, optional): 20
Success Scenario (200 OK)
json
{
  "success": true,
  "data": {
    "totalCount": 18,
    "page": 1,
    "limit": 20,
    "rides": [
      {
        "rideId": "67045b8e9a21a002b2c9e201",
        "completedAt": "2026-10-08T11:45:00.000Z",
        "paymentType": "stripe",
        "pickupAddress": "Birmingham City Centre",
        "dropoffAddress": "Cannock Retail Park",
        "financials": {
          "fare": 33.00,
          "platformFee": 6.60,
          "tollFee": 8.90,
          "tollName": "M6 Toll Highway",
          "driverEarnings": 35.30,
          "currency": "GBP"
        },
        "isSettled": false
      }
    ]
  }
}
SECTION 3: Socket.io Real-Time Events Contract
3.1 Event: ride:newRequest (Server $\to$ Nearby Drivers)
Sent to online drivers within dispatch radius.

json
{
  "event": "ride:newRequest",
  "payload": {
    "rideId": "67045b8e9a21a002b2c9e201",
    "pickup": {
      "address": "Birmingham City Centre",
      "lat": 52.4862,
      "lng": -1.8904
    },
    "dropoff": {
      "address": "Cannock Retail Park",
      "lat": 52.6000,
      "lng": -1.9000
    },
    "distanceKm": 24.5,
    "estimatedMinutes": 28,
    "paymentType": "stripe",
    "estimatedEarnings": {
      "netFare": 26.40,
      "tollReimbursement": 8.90,
      "tollName": "M6 Toll Highway",
      "totalEstimatedTakeHome": 35.30,
      "currency": "GBP"
    },
    "countdownSeconds": 20
  }
}
Driver UI shows a clear badge: Includes £8.90 Toll Reimbursement.

3.2 Event: ride:accepted (Server $\to$ User)
Sent to the passenger once a driver accepts.

json
{
  "event": "ride:accepted",
  "payload": {
    "rideId": "67045b8e9a21a002b2c9e201",
    "driver": {
      "driverId": "67039a8c1f93a001a1c8d009",
      "name": "David Smith",
      "phoneNumber": "+447700900123",
      "rating": 4.92,
      "car": {
        "model": "Toyota Prius",
        "color": "Silver",
        "licensePlate": "WP19 XYZ"
      },
      "currentLocation": { "lat": 52.4850, "lng": -1.8910 }
    },
    "fareDetails": {
      "standardFare": 33.00,
      "tollFee": 8.90,
      "tollName": "M6 Toll Highway",
      "totalFare": 41.90,
      "currency": "GBP"
    }
  }
}
3.3 Event: ride:completed (Server $\to$ User & Driver)
Payload to Passenger:
json
{
  "event": "ride:completed",
  "payload": {
    "rideId": "67045b8e9a21a002b2c9e201",
    "fare": 33.00,
    "tollFee": 8.90,
    "tollName": "M6 Toll Highway",
    "totalFare": 41.90,
    "paymentType": "stripe",
    "paymentStatus": "paid",
    "currency": "GBP"
  }
}
Payload to Driver:
json
{
  "event": "ride:completed",
  "payload": {
    "rideId": "67045b8e9a21a002b2c9e201",
    "customerFare": 33.00,
    "platformFeeDeducted": 6.60,
    "tollReimbursement": 8.90,
    "netTakeHome": 35.30,
    "paymentType": "stripe",
    "currency": "GBP"
  }
}
SECTION 4: Firebase Cloud Messaging (FCM) Specifications
4.1 Driver Incoming Ride Request (App in Background / Locked)
Sent when a ride is dispatched to a driver who has the app in background or phone locked.

json
{
  "notification": {
    "title": "New Ride Request • £35.30",
    "body": "Cannock Retail Park (24.5 km) - Includes £8.90 Toll"
  },
  "data": {
    "type": "NEW_RIDE_REQUEST",
    "rideId": "67045b8e9a21a002b2c9e201",
    "pickupAddress": "Birmingham City Centre",
    "dropoffAddress": "Cannock Retail Park",
    "totalEarnings": "35.30",
    "tollFee": "8.90",
    "tollName": "M6 Toll Highway",
    "hasToll": "true",
    "click_action": "FLUTTER_NOTIFICATION_CLICK"
  },
  "android": {
    "priority": "high",
    "notification": {
      "channel_id": "ride_dispatch_channel",
      "sound": "ride_alert"
    }
  },
  "apns": {
    "headers": {
      "apns-priority": "10"
    },
    "payload": {
      "aps": {
        "sound": "ride_alert.caf"
      }
    }
  }
}
4.2 User Ride Completed Receipt Push
Sent to passenger upon driver completing the trip.

json
{
  "notification": {
    "title": "Ride Completed - £41.90",
    "body": "Thank you for riding with MK Tours. Your receipt is ready."
  },
  "data": {
    "type": "RIDE_COMPLETED",
    "rideId": "67045b8e9a21a002b2c9e201",
    "totalFare": "41.90",
    "tollFee": "8.90",
    "tollName": "M6 Toll Highway",
    "currency": "GBP"
  }
}
4.3 Driver Weekly Settlement / Payout Paid Push
Sent to driver when Admin clicks "Settle Payout".

json
{
  "notification": {
    "title": "Payout Processed • £531.60",
    "body": "Your weekly payout has been initiated, including £35.60 toll reimbursements."
  },
  "data": {
    "type": "PAYOUT_SETTLED",
    "payoutId": "67048f12a345b001c1d8e309",
    "totalPaid": "531.60",
    "tollReimbursements": "35.60",
    "currency": "GBP"
  }
}
SECTION 5: Summary of Changes Checklist
Component	User Mobile App	Driver Mobile App
Estimate Screen	Show tollFee row & totalFare in vehicle category list.	N/A
Booking Screen	Breakdown shows Fare: £33.00 + Toll: £8.90 = £41.90.	N/A
Incoming Offer Screen	N/A	Show green badge: Includes £8.90 Toll Reimbursement.
Ride Completed Screen	Itemized receipt showing fare and toll fee.	Trip earnings popup: Net Fare (£26.40) + Toll (£8.90) = £35.30.
Earnings Tab	N/A	New KPI tile or row: Tolls Reimbursed (£) next to Net Earnings.
