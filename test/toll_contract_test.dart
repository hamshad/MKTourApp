import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/models/toll_breakdown.dart';
import 'package:mktours/core/services/fcm_service.dart';

/// Toll contract tests (phase 21-01, toll_price_implementation.md §3.2 + §4).
///
/// Pins every backend payload verbatim: §3.2 `ride:accepted` with
/// `fareDetails {standardFare 33.00, tollFee 8.90, tollName, totalFare
/// 41.90, currency}`, §4.1 `NEW_RIDE_REQUEST`, §4.2 `RIDE_COMPLETED`,
/// §4.3 `PAYOUT_SETTLED` FCM data maps (string numbers), plus absent-toll
/// variants. Exercises the REAL shared parser (`TollInfo`) and the FCM type
/// canonicalization — never mirrors them. Pure Dart, no widgets.
void main() {
  // Verbatim §3.2 ride:accepted payload (event envelope + fareDetails).
  Map<String, dynamic> rideAccepted() => {
        'event': 'ride:accepted',
        'payload': {
          'rideId': '67045b8e9a21a002b2c9e201',
          'driver': {
            'driverId': '67039a8c1f93a001a1c8d009',
            'name': 'David Smith',
            'phoneNumber': '+447700900123',
            'rating': 4.92,
            'car': {
              'model': 'Toyota Prius',
              'color': 'Silver',
              'licensePlate': 'WP19 XYZ',
            },
            'currentLocation': {'lat': 52.4850, 'lng': -1.8910},
          },
          'fareDetails': {
            'standardFare': 33.00,
            'tollFee': 8.90,
            'tollName': 'M6 Toll Highway',
            'totalFare': 41.90,
            'currency': 'GBP',
          },
        },
      };

  // Absent-toll variant of §3.2 — no fareDetails key at all.
  Map<String, dynamic> rideAcceptedNoFareDetails() => {
        'event': 'ride:accepted',
        'payload': {
          'rideId': '67045b8e9a21a002b2c9e201',
          'driver': {
            'driverId': '67039a8c1f93a001a1c8d009',
            'name': 'David Smith',
          },
        },
      };

  // Verbatim §4.1 NEW_RIDE_REQUEST data map (string numbers).
  Map<String, dynamic> fcmNewRideRequest() => {
        'type': 'NEW_RIDE_REQUEST',
        'rideId': '67045b8e9a21a002b2c9e201',
        'pickupAddress': 'Birmingham City Centre',
        'dropoffAddress': 'Cannock Retail Park',
        'totalEarnings': '35.30',
        'tollFee': '8.90',
        'tollName': 'M6 Toll Highway',
        'hasToll': 'true',
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      };

  // Verbatim §4.2 RIDE_COMPLETED data map (string numbers).
  Map<String, dynamic> fcmRideCompleted() => {
        'type': 'RIDE_COMPLETED',
        'rideId': '67045b8e9a21a002b2c9e201',
        'totalFare': '41.90',
        'tollFee': '8.90',
        'tollName': 'M6 Toll Highway',
        'currency': 'GBP',
      };

  // Verbatim §4.3 PAYOUT_SETTLED data map (string numbers).
  Map<String, dynamic> fcmPayoutSettled() => {
        'type': 'PAYOUT_SETTLED',
        'payoutId': '67048f12a345b001c1d8e309',
        'totalPaid': '531.60',
        'tollReimbursements': '35.60',
        'currency': 'GBP',
      };

  // Absent-toll variants — no toll keys anywhere (TOLL-08 tolerance).
  Map<String, dynamic> fcmNewRideRequestNoToll() => {
        'type': 'NEW_RIDE_REQUEST',
        'rideId': '67045b8e9a21a002b2c9e201',
        'pickupAddress': 'Birmingham City Centre',
        'dropoffAddress': 'Cannock Retail Park',
        'totalEarnings': '35.30',
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      };

  Map<String, dynamic> fcmRideCompletedNoToll() => {
        'type': 'RIDE_COMPLETED',
        'rideId': '67045b8e9a21a002b2c9e201',
        'totalFare': '41.90',
        'currency': 'GBP',
      };

  Map<String, dynamic> fcmPayoutSettledNoToll() => {
        'type': 'PAYOUT_SETTLED',
        'payoutId': '67048f12a345b001c1d8e309',
        'totalPaid': '531.60',
        'currency': 'GBP',
      };

  group('TOLL-07 §3.2 ride:accepted fareDetails → TollInfo', () {
    test('parses tollFee 8.90 + tollName + total 41.90 + hasToll true', () {
      final payload = rideAccepted()['payload'] as Map<String, dynamic>;
      final info = TollInfo.fromBreakdown(payload['fareDetails']);
      expect(info.tollFee, 8.90);
      expect(info.tollName, 'M6 Toll Highway');
      expect(info.total, 41.90);
      expect(info.hasToll, isTrue);
    });

    test('absent fareDetails → none-equivalent (0.0 / false / null total)', () {
      final payload =
          rideAcceptedNoFareDetails()['payload'] as Map<String, dynamic>;
      final info = TollInfo.fromBreakdown(payload['fareDetails']);
      expect(info.tollFee, 0.0);
      expect(info.hasToll, isFalse);
      expect(info.tollName, isNull);
      expect(info.total, isNull);
      expect(info.tollFee, TollInfo.none.tollFee);
      expect(info.hasToll, TollInfo.none.hasToll);
    });

    test('TollInfo never throws on malformed / empty input', () {
      expect(() => TollInfo.fromBreakdown(null), returnsNormally);
      expect(() => TollInfo.fromBreakdown(const {}), returnsNormally);
      expect(
        () => TollInfo.fromBreakdown({
          'tollFee': 'not-a-number',
          'hasToll': 'maybe',
          'totalFare': null,
        }),
        returnsNormally,
      );
      final junk = TollInfo.fromBreakdown({
        'tollFee': 'not-a-number',
        'hasToll': 'maybe',
      });
      expect(junk.tollFee, 0.0);
      expect(junk.hasToll, isFalse);
    });
  });

  group('TOLL-07 §4 FCM UPPERCASE types canonicalize onto handlers', () {
    test('§4.1 NEW_RIDE_REQUEST resolves to ride_request', () {
      final data = FcmNotificationData.fromMap(fcmNewRideRequest());
      expect(data.type, NotificationType.rideRequest);
      expect(data.type, 'ride_request');
    });

    test('§4.2 RIDE_COMPLETED resolves to ride_completed', () {
      final data = FcmNotificationData.fromMap(fcmRideCompleted());
      expect(data.type, NotificationType.rideCompleted);
      expect(data.type, 'ride_completed');
    });

    test('§4.3 PAYOUT_SETTLED resolves to payout_settled (known type)', () {
      final data = FcmNotificationData.fromMap(fcmPayoutSettled());
      expect(data.type, NotificationType.payoutSettled);
      expect(data.type, 'payout_settled');
    });

    test('FCM string toll numbers coerced to double', () {
      final request = FcmNotificationData.fromMap(fcmNewRideRequest());
      expect(request.tollFee, 8.90);
      expect(request.tollFee, isA<double>());
      final completed = FcmNotificationData.fromMap(fcmRideCompleted());
      expect(completed.tollFee, 8.90);
      expect(completed.tollName, 'M6 Toll Highway');
    });

    test('rawData still carries original keys verbatim', () {
      final request = FcmNotificationData.fromMap(fcmNewRideRequest());
      expect(request.rawData['tollName'], 'M6 Toll Highway');
      expect(request.rawData['hasToll'], 'true');
      expect(request.rawData['totalEarnings'], '35.30');
      final completed = FcmNotificationData.fromMap(fcmRideCompleted());
      expect(completed.rawData['tollFee'], '8.90');
      final payout = FcmNotificationData.fromMap(fcmPayoutSettled());
      expect(payout.rawData['tollReimbursements'], '35.60');
      expect(payout.rawData['totalPaid'], '531.60');
    });

    test('PAYOUT_SETTLED parses without crash and without tollFee', () {
      final payout = FcmNotificationData.fromMap(fcmPayoutSettled());
      expect(payout.type, NotificationType.payoutSettled);
      expect(payout.tollFee, isNull);
      expect(payout.rideId, isNull);
      expect(payout.rawData['payoutId'], '67048f12a345b001c1d8e309');
    });

    test('REGRESSION: live snake_case types stay byte-identical', () {
      expect(
        FcmNotificationData.fromMap({'type': 'ride_request'}).type,
        'ride_request',
      );
      expect(
        FcmNotificationData.fromMap({'type': 'ride_completed'}).type,
        'ride_completed',
      );
      expect(
        FcmNotificationData.fromMap({
          'type': 'excess_cash_requested',
        }).type,
        'excess_cash_requested',
      );
      expect(
        FcmNotificationData.fromMap({
          'type': 'payment_succeeded',
        }).type,
        'payment_succeeded',
      );
    });

    test('absent toll keys → null tollFee, no crash (TOLL-08)', () {
      final request = FcmNotificationData.fromMap(fcmNewRideRequestNoToll());
      expect(request.type, NotificationType.rideRequest);
      expect(request.tollFee, isNull);
      expect(request.tollName, isNull);
      final completed = FcmNotificationData.fromMap(fcmRideCompletedNoToll());
      expect(completed.type, NotificationType.rideCompleted);
      expect(completed.tollFee, isNull);
      final payout = FcmNotificationData.fromMap(fcmPayoutSettledNoToll());
      expect(payout.type, NotificationType.payoutSettled);
      expect(payout.tollFee, isNull);
      expect(payout.tollName, isNull);
    });
  });
}
