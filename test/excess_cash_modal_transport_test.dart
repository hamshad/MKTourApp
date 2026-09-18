import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/services/fcm_service.dart';
import 'package:mktours/core/services/ride_event_dedupe.dart';

/// Driver excess-cash modal transport tests (debug driver-excess-cash-no-modal).
///
/// Regression: the driver received the FCM `excess_cash_requested` banner
/// but no Collect-Cash modal, because (1) the socket handler required a
/// `_currentRideId` match that can never hold after online-pay completion
/// nulls it, and (2) the FCM type was unmapped so the in-app stream never
/// raised the modal. These tests pin the shared exactly-once contract:
/// FCM + socket keys unify, first transport wins, second skips.
void main() {
  setUp(RideEventDedupe.resetForTests);

  group('canonicalExcessCashDedupeType', () {
    test('FCM requested maps to socket key', () {
      expect(
        canonicalExcessCashDedupeType(NotificationType.excessCashRequested),
        'payment_excess_cash_requested',
      );
    });

    test('FCM cancelled maps to socket key', () {
      expect(
        canonicalExcessCashDedupeType(NotificationType.excessCashCancelled),
        'payment_excess_cash_cancelled',
      );
    });

    test('unrelated types pass through', () {
      expect(canonicalExcessCashDedupeType('ride_request'), 'ride_request');
    });
  });

  group('FCM + socket exactly-once', () {
    test('socket second skips after FCM first (same ride)', () {
      final fcmType = canonicalExcessCashDedupeType(
        NotificationType.excessCashRequested,
      );
      final first = RideEventDedupe.shouldHandleEvent(
        source: 'fcm',
        type: fcmType,
        data: {'rideId': 'ride_excess_1', 'excessAmount': 2.1},
      );
      final second = RideEventDedupe.shouldHandleEvent(
        source: 'socket',
        type: 'payment_excess_cash_requested',
        data: {'rideId': 'ride_excess_1', 'excessAmount': 2.1},
      );
      expect(first, isTrue);
      expect(second, isFalse);
    });

    test('FCM second skips after socket first (same ride)', () {
      final first = RideEventDedupe.shouldHandleEvent(
        source: 'socket',
        type: 'payment_excess_cash_requested',
        data: {'rideId': 'ride_excess_2', 'excessAmount': 2.1},
      );
      final second = RideEventDedupe.shouldHandleEvent(
        source: 'fcm',
        type: canonicalExcessCashDedupeType(
          NotificationType.excessCashRequested,
        ),
        data: {'rideId': 'ride_excess_2', 'excessAmount': 2.1},
      );
      expect(first, isTrue);
      expect(second, isFalse);
    });

    test('different ride still flows', () {
      RideEventDedupe.shouldHandleEvent(
        source: 'fcm',
        type: canonicalExcessCashDedupeType(
          NotificationType.excessCashRequested,
        ),
        data: {'rideId': 'ride_excess_3'},
      );
      expect(
        RideEventDedupe.shouldHandleEvent(
          source: 'socket',
          type: 'payment_excess_cash_requested',
          data: {'rideId': 'ride_excess_4'},
        ),
        isTrue,
      );
    });
  });
}
