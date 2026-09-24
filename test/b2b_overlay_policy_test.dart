import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/models/queued_ride.dart';

void main() {
  group('shouldShowB2bOverlay', () {
    test('queued trip stays visible after previous trip ended (idle)', () {
      expect(
        shouldShowB2bOverlay(
          hasQueuedTrip: true,
          hasOffer: false,
          status: 'online',
        ),
        isTrue,
        reason: 'queued trip must not vanish when driver returns to idle',
      );
    });

    test('queued trip visible in every status', () {
      for (final status in [
        'online',
        'offline',
        'pickup',
        'arrived',
        'in_progress',
        'at_stop',
        'awaiting_cash_confirmation',
        'complete',
      ]) {
        expect(
          shouldShowB2bOverlay(
            hasQueuedTrip: true,
            hasOffer: false,
            status: status,
          ),
          isTrue,
          reason: 'queued trip hidden in status $status',
        );
      }
    });

    test('nothing renders when no queued trip and no offer', () {
      expect(
        shouldShowB2bOverlay(
          hasQueuedTrip: false,
          hasOffer: false,
          status: 'in_progress',
        ),
        isFalse,
      );
    });

    test('offer shows only during an active trip', () {
      expect(
        shouldShowB2bOverlay(
          hasQueuedTrip: false,
          hasOffer: true,
          status: 'in_progress',
        ),
        isTrue,
      );
      expect(
        shouldShowB2bOverlay(
          hasQueuedTrip: false,
          hasOffer: true,
          status: 'online',
        ),
        isFalse,
        reason: 'idle drivers get the normal request card, not the B2B card',
      );
    });
  });

  group('shouldBlockB2bOffer', () {
    test('no queued trip never blocks', () {
      expect(
        shouldBlockB2bOffer(hasQueuedTrip: false, currentRideId: 'a'),
        isFalse,
      );
    });

    test('valid queue (previousRide is active ride) blocks', () {
      expect(
        shouldBlockB2bOffer(
          hasQueuedTrip: true,
          queuedPreviousRideId: 'rideA',
          currentRideId: 'rideA',
        ),
        isTrue,
      );
    });

    test('stale queue (previous trip ended) never blocks forever', () {
      expect(
        shouldBlockB2bOffer(
          hasQueuedTrip: true,
          queuedPreviousRideId: 'rideA',
          currentRideId: 'rideC',
        ),
        isFalse,
        reason: 'stale queue must be recovered, not silently drop offers',
      );
      expect(
        shouldBlockB2bOffer(
          hasQueuedTrip: true,
          queuedPreviousRideId: 'rideA',
          currentRideId: null,
        ),
        isFalse,
      );
    });
  });
}
