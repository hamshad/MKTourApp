import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/models/queued_ride.dart';
import 'package:mktours/features/driver/widgets/b2b_offer_card.dart';

void main() {
  group('queued trip shows on exactly one surface', () {
    test('banner shows and sheet row hides while not dismissed', () {
      expect(
        shouldShowB2bOverlay(
          hasQueuedTrip: true,
          hasOffer: false,
          status: 'in_progress',
        ),
        isTrue,
      );
      expect(
        shouldShowB2bSheetRow(hasQueuedTrip: true, bannerDismissed: false),
        isFalse,
      );
    });

    test('swiping the banner hands it to the sheet row, never both', () {
      expect(
        shouldShowB2bOverlay(
          hasQueuedTrip: true,
          hasOffer: false,
          status: 'in_progress',
          bannerDismissed: true,
        ),
        isFalse,
      );
      expect(
        shouldShowB2bSheetRow(hasQueuedTrip: true, bannerDismissed: true),
        isTrue,
      );
    });

    test('dismissal still respects the offer card independently', () {
      expect(
        shouldShowB2bOverlay(
          hasQueuedTrip: false,
          hasOffer: true,
          status: 'in_progress',
          bannerDismissed: true,
        ),
        isTrue,
        reason: 'a pending offer is not the dismissed banner',
      );
    });

    test('no queued trip means neither surface', () {
      expect(
        shouldShowB2bSheetRow(hasQueuedTrip: false, bannerDismissed: true),
        isFalse,
      );
    });
  });

  group('B2bDismissibleBanner', () {
    testWidgets('swipe up dismisses exactly once', (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: B2bDismissibleBanner(
              rideId: 'rideB',
              onDismissed: () => dismissed++,
              child: const SizedBox(height: 80, child: Text('Next trip queued')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.text('Next trip queued'),
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      expect(dismissed, 1);
    });

    testWidgets('small drag keeps the banner', (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: B2bDismissibleBanner(
              rideId: 'rideB',
              onDismissed: () => dismissed++,
              child: const SizedBox(height: 80, child: Text('Next trip queued')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.text('Next trip queued'),
        const Offset(0, -6),
      );
      await tester.pumpAndSettle();
      expect(dismissed, 0);
      expect(find.text('Next trip queued'), findsOneWidget);
    });
  });

  group('mergeB2bOfferData', () {
    test('thin FCM payload never erases rich socket locations', () {
      final rich = {
        'rideId': 'r1',
        'fare': '18.50',
        'isBackToBack': true,
        'pickupLocation': {
          'address': '45 Piccadilly',
          'coordinates': [-0.1388, 51.5074],
        },
        'dropoffLocation': {
          'address': 'Baker Street',
          'coordinates': [-0.1569, 51.5237],
        },
      };
      final thin = {
        'rideId': 'r1',
        'fare': '18.50',
        'isBackToBack': 'true',
      };
      final merged = mergeB2bOfferData(rich, thin);
      final data = B2bOfferData.fromMap(merged);
      expect(data.pickupLabel, '45 Piccadilly');
      expect(data.dropoffLabel, 'Baker Street');
      expect(data.hasBothPoints, isTrue);
    });

    test('server details fill gaps in a thin first payload', () {
      final thin = {'rideId': 'r1', 'fare': '18.50'};
      final details = {
        'rideId': 'r1',
        'pickupLocation': {
          'address': '45 Piccadilly',
          'coordinates': [-0.1388, 51.5074],
        },
        'dropoffLocation': {
          'address': 'Baker Street',
          'coordinates': [-0.1569, 51.5237],
        },
      };
      final data = B2bOfferData.fromMap(mergeB2bOfferData(thin, details));
      expect(data.pickupLabel, '45 Piccadilly');
      expect(data.dropoffLabel, 'Baker Street');
      expect(data.hasBothPoints, isTrue);
    });

    test('nested maps merge key-wise instead of replacing wholesale', () {
      final current = {
        'rideId': 'r1',
        'pickupLocation': {'address': 'Piccadilly'},
      };
      final incoming = {
        'rideId': 'r1',
        'pickupLocation': {'coordinates': [-0.1388, 51.5074]},
      };
      final merged = mergeB2bOfferData(current, incoming);
      final pickup = merged['pickupLocation'] as Map;
      expect(pickup['address'], 'Piccadilly');
      expect(pickup['coordinates'], [-0.1388, 51.5074]);
    });

    test('null incoming values never overwrite good data', () {
      final current = {
        'rideId': 'r1',
        'pickupLocation': {'address': 'Piccadilly'},
      };
      final merged = mergeB2bOfferData(current, {
        'rideId': 'r1',
        'pickupLocation': null,
      });
      expect(
        (merged['pickupLocation'] as Map)['address'],
        'Piccadilly',
      );
    });
  });

  group('shouldDeferPromotionForCash', () {
    test('cash duty outranks the queued trip', () {
      expect(
        shouldDeferPromotionForCash(
          status: 'awaiting_cash_confirmation',
          hasQueuedTrip: true,
        ),
        isTrue,
        reason: 'cash confirm must not be skipped by the promotion event',
      );
    });

    test('online and active trips promote immediately', () {
      expect(
        shouldDeferPromotionForCash(
          status: 'in_progress',
          hasQueuedTrip: true,
        ),
        isFalse,
      );
      expect(
        shouldDeferPromotionForCash(
          status: 'awaiting_cash_confirmation',
          hasQueuedTrip: false,
        ),
        isFalse,
      );
    });
  });

  group('decideB2bCompletion', () {
    test('promotion landing mid-request means Trip A is superseded', () {
      expect(
        decideB2bCompletion(
          completingRideId: 'rideA',
          activeRideId: 'rideB',
          responseSaysPromoted: false,
          hasQueuedTrip: false,
          isCash: false,
        ),
        B2bCompletionAction.superseded,
        reason: 'Trip A must never touch state owned by Trip B',
      );
    });

    test('superseded wins even when flags or cash are present', () {
      expect(
        decideB2bCompletion(
          completingRideId: 'rideA',
          activeRideId: 'rideB',
          responseSaysPromoted: true,
          hasQueuedTrip: false,
          isCash: true,
        ),
        B2bCompletionAction.superseded,
        reason:
            'Trip A reading Trip B cash state is what painted '
            "'Confirm Cash Collected' over Trip B",
      );
    });

    test('online ride with flags promotes immediately', () {
      expect(
        decideB2bCompletion(
          completingRideId: 'rideA',
          activeRideId: 'rideA',
          responseSaysPromoted: true,
          hasQueuedTrip: true,
          isCash: false,
        ),
        B2bCompletionAction.promote,
      );
    });

    test('online ride without flags waits for the event', () {
      expect(
        decideB2bCompletion(
          completingRideId: 'rideA',
          activeRideId: 'rideA',
          responseSaysPromoted: false,
          hasQueuedTrip: true,
          isCash: false,
        ),
        B2bCompletionAction.waitForPromotion,
      );
    });

    test('cash ride collects first, promotion deferred', () {
      expect(
        decideB2bCompletion(
          completingRideId: 'rideA',
          activeRideId: 'rideA',
          responseSaysPromoted: true,
          hasQueuedTrip: true,
          isCash: true,
        ),
        B2bCompletionAction.awaitCashThenPromote,
      );
      expect(
        decideB2bCompletion(
          completingRideId: 'rideA',
          activeRideId: 'rideA',
          responseSaysPromoted: false,
          hasQueuedTrip: true,
          isCash: true,
        ),
        B2bCompletionAction.awaitCash,
      );
    });

    test('plain completion finalizes', () {
      expect(
        decideB2bCompletion(
          completingRideId: 'rideA',
          activeRideId: 'rideA',
          responseSaysPromoted: false,
          hasQueuedTrip: false,
          isCash: false,
        ),
        B2bCompletionAction.finalize,
      );
    });
  });

  group('B2bOfferData address/coord extraction', () {
    test('nested socket payload resolves both addresses and coords', () {
      final data = B2bOfferData.fromMap({
        'rideId': 'r1',
        'fare': 18.5,
        'distance': 2.4,
        'user': {'name': 'Sarah Connor'},
        'pickupLocation': {
          'address': '45 Piccadilly, London W1J 0ER',
          'coordinates': [-0.1388, 51.5074],
        },
        'dropoffLocation': {
          'address': 'Baker Street Station, London NW1 6XE',
          'coordinates': [-0.1569, 51.5237],
        },
      });
      expect(data.pickupAddress, contains('Piccadilly'));
      expect(data.dropoffAddress, contains('Baker Street'));
      expect(data.pickupLat, 51.5074);
      expect(data.pickupLng, -0.1388);
      expect(data.dropoffLat, 51.5237);
      expect(data.hasBothPoints, isTrue);
      expect(data.fareLabel, '£18.50');
      expect(data.distanceLabel, '2.4 mi');
      expect(data.riderName, 'Sarah Connor');
    });

    test('flat FCM payload resolves addresses and coords', () {
      final data = B2bOfferData.fromMap({
        'rideId': 'r1',
        'pickupAddress': 'Flat pickup',
        'pickupLat': '51.5',
        'pickupLon': '-0.1',
        'dropoffAddress': 'Flat dropoff',
        'dropoffLat': 51.6,
        'dropoffLon': -0.2,
      });
      expect(data.pickupLabel, 'Flat pickup');
      expect(data.dropoffLabel, 'Flat dropoff');
      expect(data.pickupLat, 51.5);
      expect(data.dropoffLng, -0.2);
      expect(data.hasBothPoints, isTrue);
    });

    test('GeoJSON point without address falls back to coordinates label', () {
      final data = B2bOfferData.fromMap({
        'pickupLocation': {
          'type': 'Point',
          'coordinates': [-0.1388, 51.5074],
        },
        'dropoffLocation': {
          'type': 'Point',
          'coordinates': [-0.1569, 51.5237],
        },
      });
      expect(data.pickupAddress, isEmpty);
      expect(data.pickupLabel, contains('51.5074'));
      expect(data.dropoffLabel, contains('51.5237'));
      expect(data.hasBothPoints, isTrue);
    });

    test('lat/lng object and string coordinate pairs both resolve', () {
      final object = B2bOfferData.fromMap({
        'pickupLocation': {'lat': 51.5074, 'lng': -0.1388},
        'dropoffLocation': {'latitude': 51.5237, 'longitude': -0.1569},
      });
      expect(object.pickupLat, 51.5074);
      expect(object.pickupLng, -0.1388);
      expect(object.dropoffLat, 51.5237);

      final geoJsonString = B2bOfferData.fromMap({
        'pickupLocation': {'coordinates': '[-0.1388, 51.5074]'},
        'dropoffLocation': {'coordinates': '[-0.1569, 51.5237]'},
      });
      expect(geoJsonString.pickupLat, 51.5074);
      expect(geoJsonString.pickupLng, -0.1388);
      expect(geoJsonString.dropoffLat, 51.5237);
      expect(geoJsonString.dropoffLng, -0.1569);
      expect(geoJsonString.hasBothPoints, isTrue);
    });

    test('partial payload keeps whatever exists, never throws', () {
      final data = B2bOfferData.fromMap({'fare': '9.99'});
      expect(data.pickupLabel, 'Pickup');
      expect(data.dropoffLabel, 'Dropoff');
      expect(data.hasBothPoints, isFalse);
      expect(data.fareLabel, '£9.99');
      expect(B2bOfferData.fromMap(const {}).distanceLabel, isEmpty);
    });
  });

  group('B2bOfferCard', () {
    Widget wrap(B2bOfferData data, {VoidCallback? onQueue, VoidCallback? onSkip}) {
      return MaterialApp(
        home: Scaffold(
          body: B2bOfferCard(
            data: data,
            onQueue: onQueue ?? () {},
            onSkip: onSkip ?? () {},
          ),
        ),
      );
    }

    setUp(() {
      // Real map view is a platform view; stub it in widget tests.
      B2bRoutePreview.mapBuilder = (data, lat, lng) => ColoredBox(
        color: const Color(0xFFE8EAED),
        child: Center(
          child: Text(
            'map:${data.pickupLat},${data.pickupLng}->'
            '${data.dropoffLat},${data.dropoffLng}',
            style: const TextStyle(fontSize: 10),
          ),
        ),
      );
    });

    tearDown(() => B2bRoutePreview.mapBuilder = null);

    final sample = B2bOfferData.fromMap({
      'fare': 18.5,
      'distance': 2.4,
      'vehicleCategorySlug': 'saloon',
      'user': {'name': 'Sarah Connor'},
      'pickupLocation': {
        'address': '45 Piccadilly, London W1J 0ER',
        'coordinates': [-0.1388, 51.5074],
      },
      'dropoffLocation': {
        'address': 'Baker Street Station, London NW1 6XE',
        'coordinates': [-0.1569, 51.5237],
      },
    });

    testWidgets('shows pickup, dropoff, fare, distance and rider', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(sample));
      await tester.pumpAndSettle();
      expect(find.textContaining('Piccadilly'), findsOneWidget);
      expect(find.textContaining('Baker Street'), findsOneWidget);
      expect(find.text('£18.50'), findsOneWidget);
      expect(find.text('2.4 mi'), findsOneWidget);
      expect(find.text('Sarah Connor'), findsOneWidget);
    });

    testWidgets('renders without coords and hides preview map', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const B2bOfferData(pickupAddress: 'A', dropoffAddress: 'B')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Route preview unavailable'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('preview map receives both points and the driver position', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: B2bOfferCard(
              data: sample,
              driverLat: 19.86,
              driverLng: 75.31,
              onQueue: () {},
              onSkip: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('map:51.5074,-0.1388->51.5237,-0.1569'),
        findsOneWidget,
      );
    });

    testWidgets('queue and skip fire their callbacks', (tester) async {
      var queued = 0;
      var skipped = 0;
      await tester.pumpWidget(
        wrap(sample, onQueue: () => queued++, onSkip: () => skipped++),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Queue trip'));
      await tester.tap(find.text('Skip'));
      expect(queued, 1);
      expect(skipped, 1);
    });

    testWidgets('busy state blocks actions and shows spinner', (tester) async {
      var queued = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: B2bOfferCard(
              data: sample,
              busy: true,
              onQueue: () => queued++,
              onSkip: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      // Busy swaps the CTA label for a spinner, so the action is asserted
      // through the disabled InkWell instead of a text tap.
      final inkWell = tester.widget<InkWell>(
        find.descendant(
          of: find.byType(Material).last,
          matching: find.byType(InkWell),
        ),
      );
      expect(inkWell.onTap, isNull);
      expect(queued, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('inline accept error is visible', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: B2bOfferCard(
              data: sample,
              error: 'You already have a queued next trip.',
              onQueue: () {},
              onSkip: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('You already have a queued next trip.'),
        findsOneWidget,
      );
    });

    testWidgets('enriching state shows the loading hint', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: B2bOfferCard(
              data: const B2bOfferData(),
              enriching: true,
              onQueue: () {},
              onSkip: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Loading pickup details…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });
  });
}
