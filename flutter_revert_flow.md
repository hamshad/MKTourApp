. Overview of Flow Changes
Ride Type	Booking Time Behavior	Payment Timing	Driver Acceptance
Normal Ride	Dispatched immediately to nearby drivers. User app shows "Searching for drivers...". No upfront payment.	After driver accepts, before driver arrives.	Driver accepts -> User receives ride:accepted with paymentUrl -> User is prompted to pay.
Scheduled Ride	Full payment initialized upfront. Ride is in awaiting_deposit (not in driver pool yet). User pays immediately.	Upfront at booking.	Once paid, ride enters driver pool (scheduled). Driver claims it -> User receives ride:accepted (requiresPayment: false).
3. Normal Rides Flow & API Specifications
Step 1: User Books Normal Ride
Endpoint: POST /api/v1/rides/create
Auth: User Bearer Token
Request Body:
json
{
  "pickupLocation": {
    "coordinates": [-0.7594, 52.0406],
    "address": "Milton Keynes Central Station"
  },
  "dropoffLocation": {
    "coordinates": [-0.7200, 52.0500],
    "address": "Willen Lake, Milton Keynes"
  },
  "vehicleCategorySlug": "standard-saloon",
  "paymentMethod": "payment_link",
  "stops": []
}
Success Response (HTTP 201):
json
{
  "success": true,
  "message": "Ride request created successfully",
  "data": {
    "_id": "67401a2b3c4d5e6f7a8b9c01",
    "status": "requested",
    "paymentMethod": "payment_link",
    "paymentStatus": "pending",
    "fare": 12.50,
    "distance": 3.4,
    "pickupLocation": {
      "coordinates": [-0.7594, 52.0406],
      "address": "Milton Keynes Central Station"
    },
    "dropoffLocation": {
      "coordinates": [-0.7200, 52.0500],
      "address": "Willen Lake, Milton Keynes"
    }
  }
}
Mobile Action:
User App: Transition to "Searching for nearby drivers..." screen. Do NOT open payment link yet.
Driver App: Nearby drivers receive Socket event ride:newRequest and FCM push notification.
Step 2: Driver Accepts Normal Ride
Endpoint: POST /api/v1/rides/:id/accept
Auth: Driver Bearer Token
Request Body: {} (empty)
Success Response (HTTP 200):
json
{
  "success": true,
  "message": "Ride accepted successfully",
  "data": {
    "_id": "67401a2b3c4d5e6f7a8b9c01",
    "status": "accepted",
    "driver": "674011112222333344445555",
    "fare": 12.50,
    "paymentMethod": "payment_link",
    "paymentStatus": "link_created"
  }
}
Socket Event Emitted to User: ride:accepted
json
{
  "rideId": "67401a2b3c4d5e6f7a8b9c01",
  "status": "accepted",
  "isScheduled": false,
  "scheduledPickupTime": null,
  "driver": {
    "id": "674011112222333344445555",
    "name": "John Doe",
    "phone": "+447123456789",
    "profilePicture": "https://...",
    "rating": 4.9,
    "totalRides": 142,
    "vehicle": {
      "categorySlug": "standard-saloon",
      "model": "Toyota Prius",
      "number": "MK21 ABC",
      "color": "Silver"
    },
    "location": {
      "coordinates": [-0.7550, 52.0420]
    }
  },
  "pickupLocation": {
    "coordinates": [-0.7594, 52.0406],
    "address": "Milton Keynes Central Station"
  },
  "dropoffLocation": {
    "coordinates": [-0.7200, 52.0500],
    "address": "Willen Lake, Milton Keynes"
  },
  "fare": 12.50,
  "distance": 3.4,
  "paymentMethod": "payment_link",
  "paymentStatus": "link_created",
  "paymentUrl": "https://checkout.stripe.com/c/pay/cs_test_...",
  "amount": 1250,
  "currency": "GBP",
  "requiresPayment": true,
  "message": "Driver accepted! John Doe is on the way. Please complete your payment of £12.50 before driver arrives."
}
Mobile Action:
User App:
Display driver details and assigned car on map.
If requiresPayment: true, display a payment modal / banner: "Pay £12.50 before driver arrives" with a "Pay Now" button that opens paymentUrl in an in-app WebView or browser.
If paymentMethod === 'cash', requiresPayment is false. Show: "Driver on the way. Pay £12.50 in cash to driver."
Driver App: Transition to "Navigate to Pickup" screen. Show user pickup address and map route.
Step 3: User Completes Payment (Online)
When user completes checkout on paymentUrl, Stripe sends a webhook to the backend.
Socket Event Emitted to BOTH User and Driver: payment:authorized
json
{
  "rideId": "67401a2b3c4d5e6f7a8b9c01",
  "amount": 12.50,
  "message": "Payment authorized - ride can proceed"
}
Mobile Action:
User App: Close payment WebView, update payment banner to "Payment Authorized :white_check_mark:".
Driver App: Update status to "Customer Paid / Authorized :white_check_mark:".
Step 4: Driver Arrives at Pickup
Endpoint: POST /api/v1/rides/:id/arrive
Auth: Driver Bearer Token
Request Body:
json
{
  "latitude": 52.0406,
  "longitude": -0.7594
}
Success Response (HTTP 200):
json
{
  "success": true,
  "message": "Arrival confirmed. Ready to start ride.",
  "data": {
    "rideId": "67401a2b3c4d5e6f7a8b9c01",
    "status": "driver_arrived",
    "isDriverAtPickup": true,
    "arrivedAtPickupAt": "2026-09-21T13:30:00.000Z"
  }
}
Socket Event Emitted to User: ride:driverArrived
Mobile Action:
User App: Show "Driver has arrived at pickup point".
Driver App: Show "Waiting for rider (5 minutes free wait time)".
Step 5: Driver Starts the Ride
Endpoint: POST /api/v1/rides/:id/start
Auth: Driver Bearer Token
Request Body: {} (empty)
Success Response (HTTP 200):
json
{
  "success": true,
  "message": "Ride started successfully",
  "data": {
    "_id": "67401a2b3c4d5e6f7a8b9c01",
    "status": "in_progress",
    "startedAt": "2026-09-21T13:33:00.000Z"
  }
}
Socket Event Emitted to User: ride:started
Mobile Action: Both apps enter "Trip in Progress" mode, navigating to destination / intermediate stops.
Step 6: Driver Completes the Ride
Endpoint: POST /api/v1/rides/:id/complete
Auth: Driver Bearer Token
Request Body:
json
{
  "latitude": 52.0500,
  "longitude": -0.7200
}
Success Response (HTTP 200):
json
{
  "success": true,
  "message": "Ride completed successfully",
  "data": {
    "_id": "67401a2b3c4d5e6f7a8b9c01",
    "status": "completed",
    "fare": 12.50,
    "actualFare": 12.50,
    "totalWaitMinutes": 0,
    "totalWaitFee": 0,
    "paymentStatus": "succeeded"
  }
}
Socket Event Emitted to User: ride:completed
Mobile Action:
User App: Show receipt & rating screen (POST /api/v1/rides/:id/rate).
Driver App: Show earnings summary screen.
4. Normal Rides Error Cases & Fallbacks
Error 1: User Wants to Switch Payment Method (e.g. from Payment Link to Cash, or vice versa)
Allowed when ride is in requested, accepted, or driver_arrived.
Endpoint: POST /api/v1/rides/:id/select-payment
Auth: User Bearer Token
Request Body:
json
{
  "paymentMethod": "cash"
}
Success Response (HTTP 200):
json
{
  "success": true,
  "message": "Payment method selected successfully",
  "data": {
    "ride": {
      "paymentMethod": "cash",
      "amount": 1250,
      "currency": "GBP",
      "status": "accepted",
      "paymentUrl": null
    }
  }
}
Socket Event Emitted to Driver: ride:paymentSelected
json
{
  "rideId": "67401a2b3c4d5e6f7a8b9c01",
  "paymentMethod": "cash",
  "message": "User selected cash payment"
}
Mobile Action:
User App: Dismiss payment link, update UI to show cash collection.
Driver App: Update UI: "Collect £12.50 Cash from rider at end of trip".
Error 2: User App Disconnects / Re-opens After Driver Accepts
The user can retrieve current ride state at any time:
Endpoint: GET /api/v1/rides/:id
Response: Returns the ride object populated with payment details, including paymentUrl, paymentStatus, status, and driver.
User App Action: Check if status === 'accepted' and paymentMethod === 'payment_link' and paymentStatus !== 'authorized'. If so, show the "Pay Now" button with paymentUrl.
Error 3: User Cancels Before Ride Starts
Endpoint: POST /api/v1/rides/:id/cancel/user
Auth: User Bearer Token
Request Body:
json
{
  "reason": "Changed my mind"
}
Response (HTTP 200):
json
{
  "success": true,
  "message": "Ride cancelled successfully",
  "data": {
    "ride": {
      "status": "cancelled_by_user",
      "cancellationFee": 0
    }
  }
}
Mobile Action:
If user had not paid yet (before acceptance or unpaid): No refund needed.
If user paid and cancelled within grace period: Backend issues full automatic refund.
5. Scheduled Rides Flow & API Specifications
Step 1: User Books Scheduled Ride (Full Upfront Payment)
Validation: Minimum 2 hours in advance (5 minutes in development), Maximum 30 days.
Endpoint: POST /api/v1/rides/schedule
Auth: User Bearer Token
Request Body:
json
{
  "pickupLocation": {
    "coordinates": [-0.7594, 52.0406],
    "address": "Milton Keynes Central Station"
  },
  "dropoffLocation": {
    "coordinates": [-0.4614, 51.8747],
    "address": "London Luton Airport (LTN)"
  },
  "vehicleCategorySlug": "executive-saloon",
  "scheduledPickupTime": "2026-09-22T08:00:00.000Z",
  "paymentMethod": "payment_link",
  "preBookingNote": "Luggage assistance needed"
}
Success Response (HTTP 201):
json
{
  "success": true,
  "message": "Scheduled ride created successfully",
  "data": {
    "_id": "67402b3c4d5e6f7a8b9c02",
    "status": "awaiting_deposit",
    "isScheduled": true,
    "scheduledPickupTime": "2026-09-22T08:00:00.000Z",
    "fare": 55.00,
    "paymentMethod": "payment_link",
    "paymentStatus": "link_created",
    "paymentUrl": "https://checkout.stripe.com/c/pay/cs_test_scheduled_...",
    "sessionId": "cs_test_scheduled_..."
  }
}
Mobile Action:
User App: Immediately open paymentUrl in an in-app WebView / browser for upfront payment.
Step 2: User Pays for Scheduled Ride Upfront
When payment completes on paymentUrl, Stripe webhook updates ride status = 'scheduled' and depositStatus = 'paid'.
Ride is now activated into the Driver Pool.
Socket Event Emitted to User: ride:depositConfirmed
json
{
  "rideId": "67402b3c4d5e6f7a8b9c02",
  "amount": 55.00,
  "message": "Deposit paid! Your scheduled ride is confirmed."
}
Mobile Action:
User App: Close WebView, display "Scheduled Ride Confirmed for 22 Sep, 08:00 AM".
Step 3: Driver Views & Claims Scheduled Ride from Pool
Drivers browse the scheduled ride open pool:
Endpoint: GET /api/v1/rides/scheduled/pool
Auth: Driver Bearer Token
Success Response (HTTP 200):
json
{
  "success": true,
  "message": "Scheduled rides pool retrieved successfully",
  "data": [
    {
      "_id": "67402b3c4d5e6f7a8b9c02",
      "status": "scheduled",
      "isScheduled": true,
      "scheduledPickupTime": "2026-09-22T08:00:00.000Z",
      "fare": 55.00,
      "distance": 24.5,
      "pickupLocation": { "address": "Milton Keynes Central Station" },
      "dropoffLocation": { "address": "London Luton Airport (LTN)" },
      "vehicleCategorySlug": "executive-saloon",
      "user": {
        "name": "Sarah Connor",
        "phone": "+447987654321"
      }
    }
  ]
}
Driver accepts the scheduled ride:
Endpoint: POST /api/v1/rides/:id/accept
Auth: Driver Bearer Token
Socket Event Emitted to User: ride:accepted
json
{
  "rideId": "67402b3c4d5e6f7a8b9c02",
  "status": "accepted",
  "isScheduled": true,
  "scheduledPickupTime": "2026-09-22T08:00:00.000Z",
  "driver": {
    "id": "674011112222333344445555",
    "name": "John Doe",
    "phone": "+447123456789"
  },
  "fare": 55.00,
  "requiresPayment": false,
  "message": "Driver accepted your scheduled ride! John Doe is assigned to your ride."
}
Socket Event Emitted to All Other Drivers: ride:unavailable (removes ride from other drivers' pool view).
Mobile Action:
User App: Update UI: "Driver John Doe has been assigned to your scheduled ride". No payment prompt shown (requiresPayment: false).
Driver App: Add ride to driver's "My Scheduled Rides" tab (GET /api/v1/rides/scheduled/driver).
6. Scheduled Rides Error Cases & Fallbacks
Error 1: Booking Time Violation
If user tries to schedule less than 2 hours in advance (or > 30 days):
Response (HTTP 400):
json
{
  "success": false,
  "message": "Scheduled rides must be booked at least 2 hours in advance"
}
User App Action: Show alert instructing user to choose a pickup time at least 2 hours from now.
Error 2: No Driver Claims Scheduled Ride (10 Mins Past Pickup Time)
The backend cron checks every minute. If 10 minutes pass after scheduledPickupTime without any driver claiming:
Backend marks status = 'expired', executes a 100% full refund via Stripe, and notifies the user.
Socket Event Emitted to User: ride:scheduledExpired
json
{
  "rideId": "67402b3c4d5e6f7a8b9c02",
  "message": "No driver was found for your scheduled ride. Your payment will be refunded."
}
FCM Push to User: Title: ":disappointed: No Driver Available", Body: "We could not find a driver for your scheduled ride. Your payment will be refunded."
User App Action: Show apology dialog with confirmation of automatic refund.
Error 3: Driver Cancels Claimed Scheduled Ride
Driver calls POST /api/v1/rides/:id/cancel/scheduled/driver.
Backend applies a 10% penalty liability to the driver, sets isPriority: true, and re-broadcasts the ride to nearby drivers with an expanded radius.
User receives notification that a new driver is being assigned.
7. Checklist for Frontend / Mobile Developers
#	Task	App	Details
1	Do not prompt payment at booking for normal rides	User	After POST /rides/create, transition to searching screen.
2	Prompt payment on ride:accepted	User	Listen to ride:accepted. If requiresPayment: true, display payment modal / button with paymentUrl.
3	Listen to payment:authorized	User & Driver	When received, update UI to show payment is confirmed / authorized.
4	Immediate full payment for scheduled rides	User	After POST /rides/schedule, immediately open paymentUrl in WebView before adding to pool.
5	Payment method switching	User	Call POST /rides/:id/select-payment with { "paymentMethod": "cash" } or { "paymentMethod": "payment_link" } if user wants to change payment.
6	Handle requiresPayment: false for scheduled rides	User	When driver accepts scheduled ride, requiresPayment is false. Do not prompt user for payment again.
