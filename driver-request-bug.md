Here are only the specific endpoints, requests/responses, socket events, and FCM notifications directly related to preventing a driver from seeing or accepting rides while currently in a ride:

1. The Accept Ride Endpoint (POST /api/v1/rides/:id/accept)
When a driver attempts to accept a ride while already in an active ride (accepted, driver_arrived, in_progress, or at_stop):

• Method: POST.
• URL: /api/v1/rides/:id/accept.
• Headers:.
• http.
• Authorization: Bearer <driver_jwt_token>.
• Content-Type: application/json.
• .
• Request Body: None (empty {}).
Error Response (400 Bad Request)
This error is now guaranteed to trigger whenever the driver has an active ride (including intermediate stops):

json
{
  "success": false,
  "message": "Driver already has an active ride or an upcoming scheduled ride starting within 30 minutes"
}
(If another driver already claimed it in the meantime):

json
{
  "success": false,
  "message": "Ride is not available"
}

2. Socket.IO: ride:newRequest (Suppressed for Active Drivers)

• Event Name: ride:newRequest.
• Target Room: driver:<driverId>.
• What Changed:.
◦ Previously: Emitted to the driver even while in a ride..
◦ Now: The server checks getBusyDriverIds(). If the driver has an active ride, this event is completely suppressed and never sent to the driver..
(For reference, the payload shape that is now blocked while on a trip):

json
{
  "rideId": "66f1234567890abcdef12345",
  "pickupLocation": {
    "type": "Point",
    "coordinates": [-0.1278, 51.5074],
    "address": "10 Downing Street, London"
  },
  "dropoffLocation": {
    "type": "Point",
    "coordinates": [-0.1410, 51.5014],
    "address": "Buckingham Palace, London"
  },
  "stops": [],
  "fare": 18.50,
  "distance": 1.4,
  "vehicleCategorySlug": "saloon",
  "isCongestionCharge": false,
  "congestionChargeAmount": 0,
  "isScheduled": false,
  "scheduledPickupTime": null,
  "message": "This is a Saloon request. It pays the standard Saloon fare.",
  "user": {
    "name": "John Doe"
  }
}

3. Socket.IO: ride:accept (Guard on Driver Socket)
If the driver app emits ride:accept over socket while already in an active ride:

• Event Name (Client ➔ Server): ride:accept.
• json.
• {.
•   "rideId": "66f1234567890abcdef12345",.
•   "userId": "66f001122334455667788990".
• }.
• .
• Server Response (Server ➔ Driver):.
◦ Event Name: error.
• Payload:.
• json.
• {.
•   "message": "Cannot accept ride: You already have an active ride".
• }.
◦ .
• (The user is not notified, and the ride is not accepted)..

4. FCM Push Notification (Suppressed for Active Drivers)

• Notification Type: ride_request.
• What Changed:.
◦ Previously: Online drivers received background push notifications for nearby ride requests even while on a trip..
◦ Now: FCM push notifications are blocked and not sent to any driver who currently has an active ride..
(The payload that is now suppressed):

json
{
  "type": "ride_request",
  "rideId": "66f1234567890abcdef12345",
  "fare": "18.50",
  "distance": "1.4",
  "vehicleCategorySlug": "saloon",
  "isCongestionCharge": "false",
  "congestionChargeAmount": "0",
  "pickupAddress": "10 Downing Street, London",
  "pickupLat": "51.5074",
  "pickupLon": "-0.1278",
  "dropoffAddress": "Buckingham Palace, London",
  "dropoffLat": "51.5014",
  "dropoffLon": "-0.1410"
}

5. Scheduled Pool Rides (GET /api/v1/rides/scheduled/pool)

• URL: /api/v1/rides/scheduled/pool.
• What Changed:.
◦ Previously: Drivers on a ride could see open pool rides scheduled to start in 5–10 minutes..
◦ Now: If the driver currently has an active ride, any pool rides with scheduledPickupTime <= now + 30 minutes are filtered out of the returned array. Only future rides starting after 30 minutes will appear..
