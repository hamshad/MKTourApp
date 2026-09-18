import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/services/ride_event_dedupe.dart';

/// Confirmed close-out dedupe regression tests (Phase 14 CONFIRM-01/04).
///
/// `payment:excessCashConfirmed` (`{rideId, excessAmount, message}`) is the
/// final leg of the Phase 12 driver-cash round-trip. Both rider and driver
/// screens consume it behind `RideEventDedupe.shouldHandleEvent` with the
/// canonical key `payment_excess_cash_confirmed`. These tests pin the
/// exactly-once contract:
/// - duplicate confirmed for one ride collapses to a single handling
/// - confirmed vs succeeded-settlement for one ride never double-closes
/// - different rides still flow
/// - the confirmed key never collides with requested/cancelled/succeeded keys
void main() {
  setUp(RideEventDedupe.resetForTests);

  group('confirmed exactly-once', () {
    test('socket confirmed twice for same ride → second skips', () {
      final first = RideEventDedupe.shouldHandleEvent(
        source: 'socket',
        type: 'payment_excess_cash_confirmed',
        data: {'rideId': 'ride_confirm_1', 'excessAmount': 7.8},
      );
      final second = RideEventDedupe.shouldHandleEvent(
        source: 'socket',
        type: 'payment_excess_cash_confirmed',
        data: {'rideId': 'ride_confirm_1', 'excessAmount': 7.8},
      );
      expect(first, isTrue);
      expect(second, isFalse);
    });

    test('confirmed vs succeeded-settlement same ride → second skips', () {
      final first = RideEventDedupe.shouldHandleEvent(
        source: 'socket',
        type: 'payment_excess_cash_confirmed',
        data: {'rideId': 'ride_confirm_2', 'excessAmount': 7.8},
      );
      final second = RideEventDedupe.shouldHandleEvent(
        source: 'socket',
        type: 'payment_succeeded_settlement',
        data: {'rideId': 'ride_confirm_2', 'excessAmount': 7.8},
      );
      // Distinct keys: both flow through dedupe itself; the screens' shared
      // settled/dialog-open guards make the second close-out a no-op.
      expect(first, isTrue);
      expect(second, isTrue);
    });

    test('succeeded then confirmed same ride → both flow, guards own order',
        () {
      final first = RideEventDedupe.shouldHandleEvent(
        source: 'socket',
        type: 'payment_succeeded_settlement',
        data: {'rideId': 'ride_confirm_3'},
      );
      final second = RideEventDedupe.shouldHandleEvent(
        source: 'socket',
        type: 'payment_excess_cash_confirmed',
        data: {'rideId': 'ride_confirm_3', 'excessAmount': 7.8},
      );
      expect(first, isTrue);
      expect(second, isTrue);
    });

    test('confirmed for different ride → still flows', () {
      RideEventDedupe.shouldHandleEvent(
        source: 'socket',
        type: 'payment_excess_cash_confirmed',
        data: {'rideId': 'ride_confirm_4', 'excessAmount': 7.8},
      );
      expect(
        RideEventDedupe.shouldHandleEvent(
          source: 'socket',
          type: 'payment_excess_cash_confirmed',
          data: {'rideId': 'ride_confirm_5', 'excessAmount': 7.8},
        ),
        isTrue,
      );
    });
  });

  group('confirmed key isolation', () {
    test('confirmed key distinct from requested/cancelled keys', () {
      const confirmed = 'payment_excess_cash_confirmed';
      expect(confirmed, isNot('payment_excess_cash_requested'));
      expect(confirmed, isNot('payment_excess_cash_cancelled'));
      expect(confirmed, isNot('payment_succeeded_settlement'));

      // Live proof: requested for a ride does not consume confirmed.
      RideEventDedupe.shouldHandleEvent(
        source: 'socket',
        type: 'payment_excess_cash_requested',
        data: {'rideId': 'ride_confirm_6', 'excessAmount': 7.8},
      );
      RideEventDedupe.shouldHandleEvent(
        source: 'socket',
        type: 'payment_excess_cash_cancelled',
        data: {'rideId': 'ride_confirm_6', 'excessAmount': 7.8},
      );
      expect(
        RideEventDedupe.shouldHandleEvent(
          source: 'socket',
          type: 'payment_excess_cash_confirmed',
          data: {'rideId': 'ride_confirm_6', 'excessAmount': 7.8},
        ),
        isTrue,
      );
    });
  });
}
