import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/features/home/home_screen.dart';

void main() {
  group('restored rider screen arguments', () {
    final ride = <String, dynamic>{
      '_id': 'ride-1',
      'status': 'driver_arrived',
      'fare': 18.5,
      'pickupLocation': {
        'address': 'Pickup',
        'coordinates': [-0.1, 51.5],
      },
      'dropoffLocation': {
        'address': 'Dropoff',
        'coordinates': [-0.2, 51.6],
      },
      'driver': {'_id': 'driver-1', 'name': 'Test Driver'},
      'paymentMethod': 'cash',
    };

    test('keeps authoritative arrival status in assigned screen', () {
      final screen = restoredRideAssignedScreen(rideId: 'ride-1', ride: ride);

      expect(screen.initialStatus, 'driver_arrived');
      expect(screen.driver?['_id'], 'driver-1');
      expect(screen.pickup?['address'], 'Pickup');
      expect(screen.fare, 18.5);
    });

    test('canonicalizes server arrived alias', () {
      final screen = restoredRideAssignedScreen(
        rideId: 'ride-1',
        ride: {...ride, 'status': 'arrived'},
      );

      expect(screen.initialStatus, 'driver_arrived');
    });
  });

  group('global start ownership', () {
    test('live owner bypasses shared dedupe consumption', () {
      var dedupeCalls = 0;

      final shouldHandle = shouldHandleGlobalRideStart(
        rideId: 'ride-1',
        liveTrackingRideId: 'ride-1',
        consumeDedupe: () {
          dedupeCalls++;
          return true;
        },
      );

      expect(shouldHandle, isFalse);
      expect(dedupeCalls, 0);
    });

    test('unowned global handler consumes dedupe', () {
      var dedupeCalls = 0;

      final shouldHandle = shouldHandleGlobalRideStart(
        rideId: 'ride-1',
        liveTrackingRideId: 'other-ride',
        consumeDedupe: () {
          dedupeCalls++;
          return true;
        },
      );

      expect(shouldHandle, isTrue);
      expect(dedupeCalls, 1);
    });
  });
}
