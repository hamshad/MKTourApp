# Phase 15 Research — Outstanding Balance Silent Booking + Fare Transparency

## Current codebase (verified 2026-09-19)
- `lib/core/services/places_service.dart#getFareEstimate` returns `body['data']` unwrapped; categories flow into `VehicleSelectionWidget._fetchFareEstimates` → `_normalizeCategory` (`lib/features/booking/widgets/vehicle_selection_widget.dart:258`). Normalizer reads `estimatedFare/total_fare`, `originalFare`, promo, congestion — **ignores `outstandingBalance`** (dropped field). Fare map keys: `total_fare`, `original_fare`, `discount`, `is_free_ride`, `promo_applied`, `is_congestion`, `congestion_amount`, `distance_*`, `duration_*`.
- Fare map flows: `VehicleSelectionWidget.onSelectVehicle/onPrebookVehicle(fareData)` → `destination_search_screen.dart` pass-through → `RideConfirmationScreen(fareData)` (`_currentFareData`, `_fare` = `total_fare`) and legacy `ConfirmBookingScreen` (`vehicle['basePrice']`).
- Booking: `PaymentService.bookRideWithPayment` (`lib/core/services/payment_service.dart:259`) treats 403 + balance-shape as `PaymentResult.balanceBlocked` → both booking screens redirect to `OutstandingBalanceScreen` via `_openBalanceBlocked`. Per new contract this 403 **stops firing for unpaid balance** — handler becomes dormant backstop (keep for suspension/other 403s, must not dead-end).
- `OutstandingBalance` model (`lib/core/models/outstanding_balance.dart`) already parses `outstandingBalance/excessAmount/amount` keys for balance envelopes — pattern to reuse for tolerance.
- Tests: `test/outstanding_balance_test.dart`, `test/upfront_payment_contract_test.dart` — contract-test pattern exists; no fare-estimate parser test yet.

## What to do (no alternatives — backend contract fixed)
1. `_normalizeCategory`: parse `outstandingBalance` tolerant (`outstandingBalance ?? excessAmount ?? 0`, num-or-string), carry as `outstanding_balance: double` in fare map. Never recompute `total_fare` — backend total authoritative.
2. UI: per-category transparency — smallest effective surface is (a) selected-category line under price on vehicle cards and/or (b) banner on `RideConfirmationScreen` + `ConfirmBookingScreen` reading `_currentFareData['outstanding_balance']` / `vehicle['outstanding_balance']`. Show only when > 0: "Includes £X.XX unpaid balance from a previous ride". Keep promo/congestion rendering intact; free-ride (`is_free_ride`) + balance edge: banner still shows if balance > 0 (backend total authoritative).
3. Booking: no request changes; keep `isBalanceBlocked` branch as backstop (other 403s e.g. suspension), verify success path needs no edit. No socket/FCM/client-math changes. No cancel/refund logic.
4. Tests: new `test/fare_estimate_balance_test.dart` — brief §1 JSON → normalizer-equivalent parse asserts `outstanding_balance == 5`, `total_fare == 15` untouched, missing field → 0, string "5" → 5.0. `flutter test` + `flutter analyze` on touched files.

## Pitfalls
- Do NOT add `outstandingBalance` to `total_fare` — double-counts; backend already added.
- `destination_search_screen.dart` constructs fallback `fareData` maps — ensure key survives pass-through (or re-derive from selected category).
- Legacy `ConfirmBookingScreen` uses `vehicle['basePrice']`, not fare map — banner needs `vehicle['outstanding_balance']` threaded from `VehicleSelectionWidget.onSelectVehicle` fare arg or dropped (document if confirm screen can't see it; ride_confirmation is primary).
- Keep `payment:balanceDue` listener behavior unchanged.
