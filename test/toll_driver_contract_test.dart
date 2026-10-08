import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/models/toll_breakdown.dart';
import 'package:mktours/core/models/vehicle.dart';

/// Driver-side toll contract tests (21-03, toll_price_implementation.md
/// §3.1 incoming offer, §4.1 FCM dispatch, §2.1 completion earnings,
/// §3.3 driver ride:completed).
///
/// Fixtures are pinned VERBATIM from the spec. The widget-local
/// `_normaliseRideData` map assembly is MIRRORED here (fare_estimate_balance
/// precedent: pure Dart, no widget instantiation); the toll parsing itself
/// runs through the REAL shared `TollInfo` parser — never a copy.
///
/// Gates: every absent-toll fixture must produce NO `estimated_earnings`
/// key (TOLL-08 zero-drift: today's cards render byte-identically).
Map<String, dynamic>? normalisedEstimatedEarnings(Map<String, dynamic> m) {
  double? parseNum(dynamic v) =>
      v is num ? v.toDouble() : v is String ? double.tryParse(v) : null;

  final raw = m['estimatedEarnings'];
  Map? source;
  if (raw is Map) {
    source = raw;
  } else if (m.containsKey('tollFee') ||
      m.containsKey('tollName') ||
      m.containsKey('hasToll') ||
      m.containsKey('toll_fee')) {
    // FCM NEW_RIDE_REQUEST carries toll keys at the top level of data.
    source = m;
  } else {
    return null;
  }
  final info = TollInfo.fromBreakdown(source);
  final netFare = parseNum(source['netFare'] ?? source['net_fare']) ?? 0.0;
  final totalTakeHome = parseNum(source['totalEstimatedTakeHome']) ??
      parseNum(source['totalEarnings']) ??
      info.total;
  return {
    'net_fare': netFare,
    'toll_reimbursement': info.tollFee,
    'toll_name': info.tollName,
    'total_take_home': totalTakeHome,
  };
}

void main() {
  // Verbatim §3.1 ride:newRequest payload (event envelope + estimatedEarnings).
  Map<String, dynamic> rideNewRequest() => {
        'event': 'ride:newRequest',
        'payload': {
          'rideId': '67045b8e9a21a002b2c9e201',
          'pickup': {
            'address': 'Birmingham City Centre',
            'lat': 52.4862,
            'lng': -1.8904,
          },
          'dropoff': {
            'address': 'Cannock Retail Park',
            'lat': 52.6000,
            'lng': -1.9000,
          },
          'distanceKm': 24.5,
          'estimatedMinutes': 28,
          'paymentType': 'stripe',
          'estimatedEarnings': {
            'netFare': 26.40,
            'tollReimbursement': 8.90,
            'tollName': 'M6 Toll Highway',
            'totalEstimatedTakeHome': 35.30,
            'currency': 'GBP',
          },
          'countdownSeconds': 20,
        },
      };

  // Today's legacy ride:newRequest — fare only, NO estimatedEarnings.
  Map<String, dynamic> rideNewRequestLegacy() => {
        'event': 'ride:newRequest',
        'payload': {
          'rideId': '67045b8e9a21a002b2c9e202',
          'pickup': {'address': 'Birmingham City Centre'},
          'dropoff': {'address': 'Cannock Retail Park'},
          'distanceKm': 12.0,
          'estimatedMinutes': 15,
          'paymentType': 'cash',
          'fare': 18.50,
          'countdownSeconds': 20,
        },
      };

  // Verbatim §4.1 NEW_RIDE_REQUEST data map (ALL numbers are strings).
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

  // §4.1 variant with no toll keys (push-originated toll-less offer).
  Map<String, dynamic> fcmNewRideRequestNoToll() => {
        'type': 'NEW_RIDE_REQUEST',
        'rideId': '67045b8e9a21a002b2c9e201',
        'pickupAddress': 'Birmingham City Centre',
        'dropoffAddress': 'Cannock Retail Park',
        'totalEarnings': '35.30',
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      };

  group('TOLL-04 §3.1 ride:newRequest estimatedEarnings → intake', () {
    test('normalized map carries net/toll/name/take-home from payload', () {
      final payload =
          rideNewRequest()['payload'] as Map<String, dynamic>;
      final earnings = normalisedEstimatedEarnings(payload);
      expect(earnings, isNotNull);
      expect(earnings!['net_fare'], 26.40);
      expect(earnings['toll_reimbursement'], 8.90);
      expect(earnings['toll_name'], 'M6 Toll Highway');
      expect(earnings['total_take_home'], 35.30);
    });

    test('toll values parsed by REAL TollInfo (never a mirror)', () {
      final payload =
          rideNewRequest()['payload'] as Map<String, dynamic>;
      final info = TollInfo.fromBreakdown(payload['estimatedEarnings']);
      expect(info.tollFee, 8.90);
      expect(info.tollName, 'M6 Toll Highway');
      expect(info.total, 35.30);
      expect(info.hasToll, isTrue);
    });

    test('absent estimatedEarnings → NO estimated_earnings key (TOLL-08)',
        () {
      final payload =
          rideNewRequestLegacy()['payload'] as Map<String, dynamic>;
      expect(normalisedEstimatedEarnings(payload), isNull);
      expect(payload.containsKey('estimated_earnings'), isFalse);
      // Toll parse on the legacy fare-only payload: nothing to find.
      expect(payload['estimatedEarnings'], isNull);
    });
  });

  group('TOLL-04 §4.1 FCM NEW_RIDE_REQUEST string toll keys → same shape', () {
    test('tollFee "8.90" coerces to 8.90 double, take-home from totalEarnings',
        () {
      final earnings = normalisedEstimatedEarnings(fcmNewRideRequest());
      expect(earnings, isNotNull);
      expect(earnings!['toll_reimbursement'], 8.90);
      expect(earnings['toll_reimbursement'], isA<double>());
      expect(earnings['toll_name'], 'M6 Toll Highway');
      expect(earnings['total_take_home'], 35.30);
      // FCM carries no netFare — defaults to 0.0, never null, never throws.
      expect(earnings['net_fare'], 0.0);
    });

    test('badge gate holds: push offer renders exactly like socket offer', () {
      final socket = normalisedEstimatedEarnings(
        rideNewRequest()['payload'] as Map<String, dynamic>,
      );
      final push = normalisedEstimatedEarnings(fcmNewRideRequest());
      expect(socket!['toll_reimbursement'], push!['toll_reimbursement']);
      expect(socket['toll_name'], push['toll_name']);
    });

    test('FCM without toll keys → NO estimated_earnings key', () {
      expect(normalisedEstimatedEarnings(fcmNewRideRequestNoToll()), isNull);
    });
  });

  // ── TOLL-05: completion earnings popup + driver ride:completed enrich ──

  // Verbatim §2.1 complete-ride `data.earnings` (REST — primary popup source).
  Map<String, dynamic> earnings21() => {
        'customerFare': 33.00,
        'platformCommissionPercent': 20,
        'platformFee': 6.60,
        'netTripEarnings': 26.40,
        'tollReimbursed': 8.90,
        'tollName': 'M6 Toll Highway',
        'totalDriverTakeHome': 35.30,
        'currency': 'GBP',
      };

  // Verbatim §3.3 ride:completed payload TO DRIVER (enrich-only source).
  Map<String, dynamic> rideCompletedDriverPayload() => {
        'event': 'ride:completed',
        'payload': {
          'rideId': '67045b8e9a21a002b2c9e201',
          'customerFare': 33.00,
          'platformFeeDeducted': 6.60,
          'tollReimbursement': 8.90,
          'netTakeHome': 35.30,
          'paymentType': 'stripe',
          'currency': 'GBP',
        },
      };

  group('TOLL-05 §2.1 complete earnings → DriverEarnings', () {
    test('parses every field, take-home pinned VERBATIM (no arithmetic)',
        () {
      final e = DriverEarnings.fromJson(earnings21());
      expect(e.customerFare, 33.00);
      expect(e.platformFee, 6.60);
      expect(e.netTripEarnings, 26.40);
      expect(e.tollReimbursed, 8.90);
      expect(e.tollName, 'M6 Toll Highway');
      // Passthrough pin: the popup shows 35.30 because the backend said
      // so — never because the UI computed 26.40 + 8.90 itself.
      expect(e.totalDriverTakeHome, 35.30);
      expect(e.hasData, isTrue);
    });

    test('absent earnings → none: toll 0.0, legacy popup rows only', () {
      expect(DriverEarnings.none.tollReimbursed, 0.0);
      expect(DriverEarnings.none.totalDriverTakeHome, 0.0);
      expect(DriverEarnings.none.hasData, isFalse);
      // Complete responses without an `earnings` map land here.
      expect(DriverEarnings.parse(null).hasData, isFalse);
      expect(DriverEarnings.parse('junk').tollReimbursed, 0.0);
      expect(DriverEarnings.parse({'tollReimbursed': 'nope'}).hasData,
          isFalse);
    });

    test('string numbers coerce, malformed values never throw', () {
      final e = DriverEarnings.fromJson({
        'customerFare': '33.00',
        'platformFee': '6.60',
        'netTripEarnings': '26.40',
        'tollReimbursed': '8.90',
        'totalDriverTakeHome': '35.30',
      });
      expect(e.tollReimbursed, 8.90);
      expect(e.totalDriverTakeHome, 35.30);
      expect(
        () => DriverEarnings.fromJson({
          'customerFare': null,
          'tollReimbursed': {},
          'totalDriverTakeHome': [],
        }),
        returnsNormally,
      );
    });
  });

  group('TOLL-05 §3.3 driver ride:completed payload → alias parse', () {
    test('tollReimbursement alias + platformFeeDeducted + netTakeHome', () {
      final payload =
          rideCompletedDriverPayload()['payload'] as Map<String, dynamic>;
      final e = DriverEarnings.fromJson(payload);
      // §3.3 spelling: tollReimbursement (not tollReimbursed) parses.
      expect(e.tollReimbursed, 8.90);
      expect(e.platformFee, 6.60);
      expect(e.totalDriverTakeHome, 35.30);
      // Enrich-only payload carries no net-trip split.
      expect(e.netTripEarnings, 0.0);
      expect(e.hasData, isTrue);
    });

    test('§2.1 and §3.3 agree on toll + take-home (one popup, two transports)',
        () {
      final rest = DriverEarnings.fromJson(earnings21());
      final socket = DriverEarnings.fromJson(
        rideCompletedDriverPayload()['payload'] as Map<String, dynamic>,
      );
      expect(socket.tollReimbursed, rest.tollReimbursed);
      expect(socket.totalDriverTakeHome, rest.totalDriverTakeHome);
    });

    test('driver payload without toll → toll 0.0, enrich gate stays shut', () {
      final e = DriverEarnings.fromJson({
        'rideId': '67045b8e9a21a002b2c9e201',
        'customerFare': 33.00,
        'netTakeHome': 26.40,
      });
      expect(e.tollReimbursed, 0.0);
      expect(e.tollName, isNull);
    });
  });
}
