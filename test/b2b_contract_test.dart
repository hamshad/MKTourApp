import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/models/api_error.dart';
import 'package:mktours/core/models/driver_error_handler.dart';
import 'package:mktours/core/models/queued_ride.dart';

/// Back-to-back dispatch contract (phase 20-01, driver-multirequest.md §2-4).
///
/// Pins every backend payload verbatim: accept-response (§2.1A),
/// complete-response (§2.1C), ride:newRequest + ride:nextTripActivated (§3.1),
/// ride:accepted + ride:driverEnRoute (§3.2). Pure Dart, no widgets.
void main() {
  // Verbatim §2.1A accept-response data envelope.
  Map<String, dynamic> acceptData() => {
        '_id': '6741b2c45e8a1f2b3c4d5e6f',
        'user': {
          '_id': '6741a0e1234567890abcdef1',
          'name': 'Sarah Connor',
          'phone': '+447911123456',
          'profilePicture':
              'https://res.cloudinary.com/mktours/image/upload/v1/users/sarah.jpg',
        },
        'driver': '673f9b112233445566778899',
        'status': 'accepted',
        'isQueued': true,
        'previousRide': '6740f9988776655443322110',
        'pickupLocation': {
          'address': '45 Piccadilly, London W1J 0ER',
          'coordinates': [-0.1388, 51.5074],
        },
        'dropoffLocation': {
          'address': 'Baker Street Station, London NW1 6XE',
          'coordinates': [-0.1569, 51.5237],
        },
        'stops': [],
        'vehicleCategorySlug': 'saloon',
        'fare': 18.50,
        'distance': 2.4,
        'paymentMethod': 'stripe',
        'paymentStatus': 'authorized',
        'acceptedAt': '2026-09-23T18:35:00.000Z',
      };

  // Verbatim §2.1C complete-response data envelope.
  Map<String, dynamic> completeData() => {
        '_id': '6740f9988776655443322110',
        'status': 'completed',
        'fare': 22.00,
        'actualFare': 22.00,
        'hasQueuedRidePromoted': true,
        'nextRideId': '6741b2c45e8a1f2b3c4d5e6f',
      };

  // Verbatim §3.1 ride:newRequest payload.
  Map<String, dynamic> newRequest() => {
        'rideId': '6741b2c45e8a1f2b3c4d5e6f',
        'pickupLocation': {
          'address': '45 Piccadilly, London W1J 0ER',
          'coordinates': [-0.1388, 51.5074],
        },
        'dropoffLocation': {
          'address': 'Baker Street Station, London NW1 6XE',
          'coordinates': [-0.1569, 51.5237],
        },
        'stops': [],
        'fare': 18.50,
        'distance': 2.4,
        'vehicleCategorySlug': 'saloon',
        'isCongestionCharge': false,
        'congestionChargeAmount': 0,
        'isBackToBack': true,
        'message': 'New ride near your current dropoff',
        'user': {'name': 'Sarah Connor'},
      };

  // Verbatim §3.1 ride:nextTripActivated payload.
  Map<String, dynamic> nextTripActivated() => {
        'rideId': '6741b2c45e8a1f2b3c4d5e6f',
        'pickupLocation': {
          'address': '45 Piccadilly, London W1J 0ER',
          'coordinates': [-0.1388, 51.5074],
        },
        'dropoffLocation': {
          'address': 'Baker Street Station, London NW1 6XE',
          'coordinates': [-0.1569, 51.5237],
        },
        'fare': 18.50,
        'distance': 2.4,
        'stops': [],
        'vehicleCategorySlug': 'saloon',
        'user': {
          'name': 'Sarah Connor',
          'phone': '+447911123456',
          'profilePicture':
              'https://res.cloudinary.com/mktours/image/upload/v1/users/sarah.jpg',
        },
        'message': 'Your next ride is ready! Head to the pickup location.',
      };

  // Verbatim §3.2 ride:accepted payload.
  Map<String, dynamic> rideAccepted() => {
        'rideId': '6741b2c45e8a1f2b3c4d5e6f',
        'status': 'accepted',
        'isScheduled': false,
        'scheduledPickupTime': null,
        'driver': {
          'id': '673f9b112233445566778899',
          'name': 'Michael Schumacher',
          'phone': '+447822998877',
          'profilePicture':
              'https://res.cloudinary.com/mktours/image/upload/v1/drivers/michael.jpg',
          'rating': 4.95,
          'totalRides': 1420,
          'vehicle': {
            'categorySlug': 'saloon',
            'model': 'Toyota Prius 2022',
            'number': 'LD22 XYZ',
            'color': 'Silver Metallic',
          },
          'location': {
            'type': 'Point',
            'coordinates': [-0.1412, 51.5033],
          },
        },
        'pickupLocation': {
          'address': '45 Piccadilly, London W1J 0ER',
          'coordinates': [-0.1388, 51.5074],
        },
        'dropoffLocation': {
          'address': 'Baker Street Station, London NW1 6XE',
          'coordinates': [-0.1569, 51.5237],
        },
        'fare': 18.50,
        'distance': 2.4,
        'paymentMethod': 'stripe',
        'paymentStatus': 'authorized',
        'requiresPayment': false,
        'message': 'Driver accepted! Michael Schumacher is on the way.',
      };

  group('§2.1A accept-response → QueuedRide', () {
    test('parses isQueued=true + previousRide + user phone', () {
      final ride = QueuedRide.fromMap(acceptData());
      expect(ride.id, '6741b2c45e8a1f2b3c4d5e6f');
      expect(ride.status, 'accepted');
      expect(ride.isQueued, isTrue);
      expect(ride.previousRide, '6740f9988776655443322110');
      expect(ride.user.name, 'Sarah Connor');
      expect(ride.user.phone, '+447911123456');
    });

    test('parses locations, fare, payment, acceptedAt', () {
      final ride = QueuedRide.fromMap(acceptData());
      expect(ride.pickupLocation.address, '45 Piccadilly, London W1J 0ER');
      expect(ride.pickupLocation.longitude, closeTo(-0.1388, 0.0001));
      expect(ride.pickupLocation.latitude, closeTo(51.5074, 0.0001));
      expect(ride.dropoffLocation.address, contains('Baker Street'));
      expect(ride.fare, 18.50);
      expect(ride.distance, 2.4);
      expect(ride.vehicleCategorySlug, 'saloon');
      expect(ride.paymentMethod, 'stripe');
      expect(ride.paymentStatus, 'authorized');
      expect(ride.acceptedAt, '2026-09-23T18:35:00.000Z');
      expect(ride.stops, isEmpty);
    });
  });

  group('§2.1 accept errors → friendly copy', () {
    test('acceptance handler exists for accept-path errors', () {
      // Wiring pin: queued-ride + taken-ride copies live behind this handler.
      // The tear-off reference fails compilation if the handler is renamed
      // or removed; the branch predicates are asserted below.
      expect(DriverErrorHandler.handleRideAcceptanceError, isA<Function>());
    });

    test('queued-ride error matches queued branch', () {
      final error = DriverException(
        message: 'Driver already has a queued ride',
      );
      expect(error.isError('already has a queued ride'), isTrue);
    });

    test('taken-ride error matches not-available branch', () {
      final error = DriverException(message: 'Ride is not available');
      expect(error.isError('not available'), isTrue);
    });
  });

  group('§2.1C complete-response → CompletePromotion', () {
    test('parses hasQueuedRidePromoted=true + nextRideId', () {
      final promotion = CompletePromotion.fromMap(completeData());
      expect(promotion.id, '6740f9988776655443322110');
      expect(promotion.status, 'completed');
      expect(promotion.fare, 22.00);
      expect(promotion.actualFare, 22.00);
      expect(promotion.hasQueuedRidePromoted, isTrue);
      expect(promotion.nextRideId, '6741b2c45e8a1f2b3c4d5e6f');
    });

    test('no queued ride → flags false, nextRideId empty', () {
      final promotion = CompletePromotion.fromMap({
        '_id': '6740f9988776655443322110',
        'status': 'completed',
        'fare': 22.00,
        'actualFare': 22.00,
      });
      expect(promotion.hasQueuedRidePromoted, isFalse);
      expect(promotion.nextRideId, isEmpty);
    });
  });

  group('§3.1 ride:newRequest → B2bRequest', () {
    test('parses isBackToBack=true + fare 18.50', () {
      final request = B2bRequest.fromMap(newRequest());
      expect(request.rideId, '6741b2c45e8a1f2b3c4d5e6f');
      expect(request.isBackToBack, isTrue);
      expect(request.fare, 18.50);
      expect(request.distance, 2.4);
      expect(request.vehicleCategorySlug, 'saloon');
      expect(request.message, 'New ride near your current dropoff');
      expect(request.user.name, 'Sarah Connor');
    });

    test('parses congestion flags + locations', () {
      final request = B2bRequest.fromMap(newRequest());
      expect(request.isCongestionCharge, isFalse);
      expect(request.congestionChargeAmount, 0.0);
      expect(request.pickupLocation.latitude, closeTo(51.5074, 0.0001));
      expect(request.dropoffLocation.longitude, closeTo(-0.1569, 0.0001));
    });
  });

  group('§3.1 ride:nextTripActivated → NextTripActivation', () {
    test('parses user + message', () {
      final activation = NextTripActivation.fromMap(nextTripActivated());
      expect(activation.rideId, '6741b2c45e8a1f2b3c4d5e6f');
      expect(activation.user.name, 'Sarah Connor');
      expect(activation.user.phone, '+447911123456');
      expect(
        activation.user.profilePicture,
        contains('sarah.jpg'),
      );
      expect(activation.message, contains('next ride is ready'));
      expect(activation.fare, 18.50);
      expect(activation.pickupLocation.address, contains('Piccadilly'));
    });
  });

  group('§3.2 ride:accepted → AcceptedRide', () {
    test('parses driver vehicle number LD22 XYZ + requiresPayment=false', () {
      final accepted = AcceptedRide.fromMap(rideAccepted());
      expect(accepted.rideId, '6741b2c45e8a1f2b3c4d5e6f');
      expect(accepted.status, 'accepted');
      expect(accepted.isScheduled, isFalse);
      expect(accepted.driver.name, 'Michael Schumacher');
      expect(accepted.driver.vehicle.number, 'LD22 XYZ');
      expect(accepted.driver.vehicle.model, 'Toyota Prius 2022');
      expect(accepted.driver.rating, 4.95);
      expect(accepted.driver.totalRides, 1420);
      expect(accepted.requiresPayment, isFalse);
      expect(accepted.paymentMethod, 'stripe');
      expect(accepted.paymentStatus, 'authorized');
    });
  });

  group('§3.2 rider signals', () {
    test('driverEnRoute parses status + message', () {
      final enRoute = DriverEnRoute.fromMap({
        'rideId': '6741b2c45e8a1f2b3c4d5e6f',
        'status': 'accepted',
        'message': 'Your driver is on the way!',
      });
      expect(enRoute.rideId, '6741b2c45e8a1f2b3c4d5e6f');
      expect(enRoute.status, 'accepted');
      expect(enRoute.message, 'Your driver is on the way!');
    });

    test('etaUpdate parses duration + distance', () {
      final eta = EtaUpdate.fromMap({
        'rideId': '6741b2c45e8a1f2b3c4d5e6f',
        'duration': '8 mins',
        'distance': '1.8 mi',
      });
      expect(eta.rideId, '6741b2c45e8a1f2b3c4d5e6f');
      expect(eta.duration, '8 mins');
      expect(eta.distance, '1.8 mi');
    });

    test('queued cancelled parses rideId + cancelledBy', () {
      final cancelled = QueuedCancellation.fromMap({
        'rideId': '6741b2c45e8a1f2b3c4d5e6f',
        'cancelledBy': 'user',
      });
      expect(cancelled.rideId, '6741b2c45e8a1f2b3c4d5e6f');
      expect(cancelled.cancelledBy, 'user');
    });
  });

  group('malformed payloads never throw', () {
    test('missing user + null coordinates', () {
      expect(
        () => QueuedRide.fromMap({
          '_id': 'x',
          'status': 'accepted',
          'user': null,
          'pickupLocation': {'address': 'A', 'coordinates': null},
          'dropoffLocation': null,
        }),
        returnsNormally,
      );
      final ride = QueuedRide.fromMap({
        '_id': 'x',
        'status': 'accepted',
      });
      expect(ride.user.name, isEmpty);
      expect(ride.fare, 0.0);
      expect(ride.stops, isEmpty);
      expect(ride.pickupLocation.latitude, 0.0);
    });

    test('empty maps across all parsers', () {
      expect(() => NextTripActivation.fromMap({}), returnsNormally);
      expect(() => B2bRequest.fromMap({}), returnsNormally);
      expect(() => CompletePromotion.fromMap({}), returnsNormally);
      expect(() => AcceptedRide.fromMap({}), returnsNormally);
      expect(() => DriverEnRoute.fromMap({}), returnsNormally);
      expect(() => EtaUpdate.fromMap({}), returnsNormally);
      expect(() => QueuedCancellation.fromMap({}), returnsNormally);
      expect(B2bRequest.fromMap({}).isBackToBack, isFalse);
      expect(AcceptedRide.fromMap({}).driver.vehicle.number, isEmpty);
    });

    test('nested coordinates map tolerated', () {
      final location = B2bLocation.fromMap({
        'address': 'Nested',
        'coordinates': {
          'coordinates': [-0.1388, 51.5074],
        },
      });
      expect(location.latitude, closeTo(51.5074, 0.0001));
      expect(location.longitude, closeTo(-0.1388, 0.0001));
    });
  });
}
