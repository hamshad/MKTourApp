# Phase 15 — Outstanding Balance: Silent Booking + Fare Transparency (Backend Integration Guide)

Source: backend team brief, 2026-09-19. Zero change to core booking logic / payment sheet. Minor UI/UX for pricing transparency.

## 1. Endpoints impacted

### GET /api/v1/rides/fare-estimate
Per-category payload now includes `outstandingBalance`. `estimatedFare` and `originalFare` ALREADY include the balance. Do NO client-side math.

```json
{
  "success": true,
  "message": "Fare estimate calculated successfully",
  "data": {
    "isPromoEligible": false,
    "categories": [
      {
        "slug": "standard",
        "name": "Standard",
        "estimatedFare": 15,
        "originalFare": 15,
        "outstandingBalance": 5,
        "discount": 0,
        "isFreeRide": false
      }
    ]
  }
}
```

### POST /api/v1/rides/create & POST /api/v1/rides/schedule
No longer return 403 when user has unpaid balance. No request/response structural changes. Returned `clientSecret` / `payment_link` / cash fare automatically cover combined total (ride fare + old debt).

## 2. Sockets & FCM
No structural changes. Fare properties on `ride:completed`, `ride:started`, etc. reflect combined total. FCM fare amounts reflect combined total. `payment:balanceDue` still emitted when wait-time fees exceed hold; ignoring it no longer hard-blocks next booking.

## 3. Implementation flow (mobile)
1. **Pre-booking:** call fare-estimate → check `outstandingBalance` on selected category → if > 0 show line item / info banner (e.g. "Includes £5.00 unpaid balance from a previous ride"). Use `estimatedFare` as-is.
2. **Booking:** call create as normal → Stripe sheet amount auto-covers fare + debt.
3. **Cancel/refund:** zero mobile effort. Success → backend clears old debt. Cancel + intent voided → backend un-links debt, retains on account for next attempt.
