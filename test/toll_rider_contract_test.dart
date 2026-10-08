import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/models/toll_breakdown.dart';

/// Rider toll contract tests (phase 21-02, toll_price_implementation.md §1.1
/// fare estimate, §1.2 create-ride fareBreakdown, §1.3 receipt).
///
/// Fixtures are inlined VERBATIM from the spec alongside absent-toll
/// variants (TOLL-08 baseline: today's shapes must parse unchanged).
/// Parsing asserts exercise the REAL shared parser (`TollInfo`) — never a
/// mirror of it. The normalizer expression tests mirror only the
/// widget-local unified fare-map build, following the
/// `test/fare_estimate_balance_test.dart:11-25` precedent (no widget
/// instantiation).
///
/// Mirrors `VehicleSelectionWidget._normalizeCategory` /
/// `RideConfirmationScreen._fetchFareEstimateWithStops` — both copies carry
/// the identical toll chain (drift guard: `TollInfo.fromCategory` in both).
Map<String, dynamic>? normalizeCategoryFare(Map<String, dynamic> cat) {
  final slug = (cat['slug'] ?? cat['categorySlug'])?.toString();
  if (slug == null || slug.isEmpty) return null;

  num numOf(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
  final estimatedFare = numOf(cat['estimatedFare'] ?? cat['total_fare']);
  final originalFare = numOf(
    cat['originalFare'] ?? cat['original_fare'] ?? estimatedFare,
  );
  final promoApplied =
      cat['promoApplied'] == true || cat['isPromoApplied'] == true;
  final isFreeRide =
      cat['isFreeRide'] == true || (promoApplied && estimatedFare == 0);
  final discount = numOf(cat['discount'] ?? (originalFare - estimatedFare));
  final isCongestion = cat['isCongestionCharge'] == true;
  final congestionAmount = numOf(cat['congestionChargeAmount'] ?? 0);
  final outstandingRaw = numOf(
    cat['outstandingBalance'] ??
        cat['excessAmount'] ??
        cat['outstanding_balance'] ??
        0,
  );
  final outstandingBalance = (outstandingRaw < 0 ? 0 : outstandingRaw);
  final toll = TollInfo.fromCategory(cat);

  return {
    'slug': slug,
    'fare': {
      'total_fare': estimatedFare.toDouble(),
      'original_fare': originalFare.toDouble(),
      'discount': (discount < 0 ? 0 : discount).toDouble(),
      'is_free_ride': isFreeRide,
      'promo_applied': promoApplied,
      'is_congestion': isCongestion,
      'congestion_amount': congestionAmount.toDouble(),
      'outstanding_balance': outstandingBalance.toDouble(),
      if (toll.hasToll || toll.tollFee > 0) ...{
        'toll_fee': toll.tollFee,
        if (toll.tollName != null) 'toll_name': toll.tollName,
        'has_toll': toll.hasToll,
        if (toll.total != null) 'total_with_toll': toll.total,
      },
      'distance_text': '24.50 mi',
      'distance_miles': 24.5,
      'duration_text': '28 min',
      'duration_seconds': 1680,
    },
  };
}

/// Mirrors `RideConfirmationScreen._tollBreakdownLine` — the pre-create
/// spec §5 breakdown line built from the normalized category fare map.
/// Values verbatim; null when toll absent OR the backend sent no
/// `total_with_toll` (never computes `fare + toll` client-side).
String? tollBreakdownLine(Map<String, dynamic> fare) {
  final tollFee = (fare['toll_fee'] as num?)?.toDouble() ?? 0.0;
  if (tollFee <= 0) return null;
  final total = (fare['total_with_toll'] as num?)?.toDouble();
  if (total == null) return null;
  final fareValue = (fare['total_fare'] as num?)?.toDouble() ?? 0.0;
  return 'Fare £${fareValue.toStringAsFixed(2)} + '
      'Toll £${tollFee.toStringAsFixed(2)} = '
      '£${total.toStringAsFixed(2)}';
}

/// Mirrors `RideConfirmationScreen._createdBreakdownLine` — the
/// post-create §1.2 line from the raw create-ride `fareBreakdown`.
/// Legacy rendering gate: absent or toll-free → null (renders nothing).
String? createdBreakdownLine(Map<String, dynamic>? fareBreakdown) {
  if (fareBreakdown == null) return null;
  final info = TollInfo.fromBreakdown(fareBreakdown);
  if (info.tollFee <= 0) return null;
  final fare = (fareBreakdown['standardFare'] as num?)?.toDouble();
  final total = info.total;
  if (fare == null || total == null) return null;
  return 'Fare £${fare.toStringAsFixed(2)} + '
      'Toll £${info.tollFee.toStringAsFixed(2)} = '
      '£${total.toStringAsFixed(2)}';
}

/// Mirrors `RideCompleteScreen._tollInfo` — the REST §1.3 receipt wins
/// when it carries a toll; otherwise the socket §3.3 top-level map.
TollInfo screenTollInfo(Map<String, dynamic> rideData) {
  final raw = rideData['receipt'];
  if (raw is Map) {
    final fromReceipt = TollInfo.fromBreakdown(Map<String, dynamic>.from(raw));
    if (fromReceipt.tollFee > 0 || fromReceipt.hasToll) return fromReceipt;
  }
  return TollInfo.fromBreakdown(rideData);
}

/// Mirrors `RideCompleteScreen._displayTotal` — receipt `totalCharged`
/// verbatim → else backend `totalFare` when a toll arrived → else the
/// legacy total passed in. Never computes fare + toll.
double displayTotal(Map<String, dynamic> rideData, double legacyTotal) {
  final raw = rideData['receipt'];
  if (raw is Map) {
    final charged = (raw['totalCharged'] as num?)?.toDouble();
    if (charged != null) return charged;
  }
  final info = screenTollInfo(rideData);
  if (info.hasToll && info.total != null) return info.total!;
  return legacyTotal;
}

void main() {
  // Verbatim §1.1 fare-estimate `data` map (both spec categories incl.
  // tollFee/totalFare + top-level hasToll/tollDetails).
  Map<String, dynamic> fareEstimate() => {
        'success': true,
        'message': 'Fare estimated successfully',
        'data': {
          'distanceKm': 24.5,
          'durationMinutes': 28,
          'hasToll': true,
          'tollDetails': {
            'name': 'M6 Toll Highway',
            'amount': 8.90,
            'currency': 'GBP',
          },
          'categories': [
            {
              'vehicleCategoryId': '67041a8e2b83a001a1c8f101',
              'categoryName': 'Standard Saloon',
              'baseFare': 3.50,
              'distanceFare': 25.00,
              'timeFare': 4.50,
              'standardRideFare': 33.00,
              'tollFee': 8.90,
              'totalFare': 41.90,
              'currency': 'GBP',
            },
            {
              'vehicleCategoryId': '67041a8e2b83a001a1c8f102',
              'categoryName': 'Executive / MPV',
              'baseFare': 5.00,
              'distanceFare': 32.00,
              'timeFare': 6.00,
              'standardRideFare': 43.00,
              'tollFee': 11.50,
              'totalFare': 54.50,
              'currency': 'GBP',
            },
          ],
        },
      };

  // Today's shape: slug + estimatedFare only, no toll keys anywhere.
  Map<String, dynamic> absentTollCategory() => {
        'slug': 'standard-saloon',
        'estimatedFare': 12.5,
        'originalFare': 12.5,
      };

  group('TOLL-01 §1.1 fare estimate → TollInfo + normalizer chain', () {
    test('category 1: tollFee 8.90 + totalFare 41.90, hasToll true', () {
      final data = fareEstimate()['data'] as Map<String, dynamic>;
      final cat = (data['categories'] as List).first as Map<String, dynamic>;
      final info = TollInfo.fromCategory(cat);
      expect(info.tollFee, 8.90);
      expect(info.total, 41.90);
      expect(info.hasToll, isTrue);
      // Spec categories carry no per-category tollName — route-level only.
      expect(info.tollName, isNull);
    });

    test('category 2: tollFee 11.50 + totalFare 54.50, hasToll true', () {
      final data = fareEstimate()['data'] as Map<String, dynamic>;
      final cat = (data['categories'] as List)[1] as Map<String, dynamic>;
      final info = TollInfo.fromCategory(cat);
      expect(info.tollFee, 11.50);
      expect(info.total, 54.50);
      expect(info.hasToll, isTrue);
    });

    test('top-level hasToll/tollDetails → TollInfo.fromEstimate', () {
      final data = fareEstimate()['data'] as Map<String, dynamic>;
      final info = TollInfo.fromEstimate(data);
      expect(info.tollFee, 8.90);
      expect(info.tollName, 'M6 Toll Highway');
      expect(info.hasToll, isTrue);
      // Top-level map carries no totalFare — total stays null, never computed.
      expect(info.total, isNull);
    });

    test('absent-toll category → none-equivalent parse (TOLL-08)', () {
      final info = TollInfo.fromCategory(absentTollCategory());
      expect(info.tollFee, 0.0);
      expect(info.hasToll, isFalse);
      expect(info.tollName, isNull);
      expect(info.total, isNull);
      expect(info.tollFee, TollInfo.none.tollFee);
      expect(info.hasToll, TollInfo.none.hasToll);
    });

    test('normalizer adds toll keys for the spec category', () {
      final data = fareEstimate()['data'] as Map<String, dynamic>;
      final cat = Map<String, dynamic>.from(
        (data['categories'] as List).first as Map,
      );
      // The live shape carries the category slug key; the verbatim spec
      // fixture omits it (slug gate behaviour is pinned separately below).
      cat['slug'] = 'standard-saloon';
      final fare = normalizeCategoryFare(cat)!['fare'] as Map<String, dynamic>;
      expect(fare['toll_fee'], 8.90);
      expect(fare['has_toll'], isTrue);
      expect(fare['total_with_toll'], 41.90);
      // `estimatedFare ?? total_fare` chain untouched (spec category has
      // neither key): totals stay verbatim from the backend keys only —
      // no client-side fare+toll arithmetic.
      expect(fare['total_fare'], 0.0);
      expect(
        fare['total_fare'],
        isNot((fare['toll_fee'] as num) + 8.90),
      );
    });

    test('normalizer is byte-identical to today for absent-toll category',
        () {
      final fare =
          normalizeCategoryFare(absentTollCategory())!['fare']
              as Map<String, dynamic>;
      expect(fare, {
        'total_fare': 12.5,
        'original_fare': 12.5,
        'discount': 0.0,
        'is_free_ride': false,
        'promo_applied': false,
        'is_congestion': false,
        'congestion_amount': 0.0,
        'outstanding_balance': 0.0,
        'distance_text': '24.50 mi',
        'distance_miles': 24.5,
        'duration_text': '28 min',
        'duration_seconds': 1680,
      });
      expect(fare.containsKey('toll_fee'), isFalse);
      expect(fare.containsKey('has_toll'), isFalse);
      expect(fare.containsKey('total_with_toll'), isFalse);
    });

    test('normalizer returns null for missing/empty slug (gate untouched)',
        () {
      expect(normalizeCategoryFare({'estimatedFare': 10}), isNull);
      expect(normalizeCategoryFare({'slug': '', 'estimatedFare': 10}), isNull);
    });

    test('TollInfo never throws on malformed category/estimate input', () {
      expect(() => TollInfo.fromCategory(null), returnsNormally);
      expect(() => TollInfo.fromCategory(const {}), returnsNormally);
      expect(
        () => TollInfo.fromCategory({
          'tollFee': 'not-a-number',
          'totalFare': null,
        }),
        returnsNormally,
      );
      expect(() => TollInfo.fromEstimate(null), returnsNormally);
      expect(() => TollInfo.fromEstimate({'tollDetails': 'junk'}), returnsNormally);
    });
  });

  // Verbatim §1.2 create-ride 201 `fareBreakdown`.
  Map<String, dynamic> fareBreakdown() => {
        'standardFare': 33.00,
        'tollFee': 8.90,
        'tollName': 'M6 Toll Highway',
        'isTollIncurred': true,
        'totalFare': 41.90,
        'currency': 'GBP',
      };

  // Live backend today: create-ride response carries NO fareBreakdown.
  Map<String, dynamic> createRideNoBreakdown() => {
        'rideId': '67045b8e9a21a002b2c9e201',
        'status': 'pending',
        'paymentType': 'stripe',
        'paymentStatus': 'hold_placed',
      };

  group('TOLL-02 §1.2 create-ride fareBreakdown → booking breakdown', () {
    test('§1.2 fareBreakdown parses tollFee/tollName/totalFare verbatim',
        () {
      final info = TollInfo.fromBreakdown(fareBreakdown());
      expect(info.tollFee, 8.90);
      expect(info.tollName, 'M6 Toll Highway');
      expect(info.total, 41.90);
      // hasToll via the explicit `isTollIncurred` flag (spec §1.2).
      expect(info.hasToll, isTrue);
    });

    test('itemized line is byte-exact spec §5 copy', () {
      expect(
        createdBreakdownLine(fareBreakdown()),
        'Fare £33.00 + Toll £8.90 = £41.90',
      );
      // Backend total verbatim: the line's total equals the fixture's
      // totalFare — never 33.00 + 8.90 computed client-side (identical
      // result here, but the value must come from the backend key).
      final info = TollInfo.fromBreakdown(fareBreakdown());
      expect(info.total, 41.90);
    });

    test('absent fareBreakdown → none parse + legacy gate false', () {
      final info = TollInfo.fromBreakdown(
        createRideNoBreakdown()['fareBreakdown'],
      );
      expect(info.tollFee, 0.0);
      expect(info.hasToll, isFalse);
      expect(info.total, isNull);
      // Legacy rendering gate: no fareBreakdown / no toll → no line.
      expect(createdBreakdownLine(null), isNull);
      expect(
        createdBreakdownLine(createRideNoBreakdown()['fareBreakdown']
            as Map<String, dynamic>?),
        isNull,
      );
      expect(
        createdBreakdownLine({'standardFare': 33.00, 'totalFare': 33.00}),
        isNull,
      );
    });

    test('pre-create line from category map (spec §5 booking screen)', () {
      expect(
        tollBreakdownLine({
          'total_fare': 33.00,
          'toll_fee': 8.90,
          'has_toll': true,
          'total_with_toll': 41.90,
        }),
        'Fare £33.00 + Toll £8.90 = £41.90',
      );
    });

    test('pre-create gate: absent toll → no line (byte-identical today)',
        () {
      expect(
        tollBreakdownLine({
          'total_fare': 12.5,
          'original_fare': 12.5,
          'discount': 0.0,
          'is_free_ride': false,
          'promo_applied': false,
          'is_congestion': false,
          'congestion_amount': 0.0,
          'outstanding_balance': 0.0,
        }),
        isNull,
      );
    });

    test('toll present but backend total absent → line withheld (no math)',
        () {
      expect(
        tollBreakdownLine({'total_fare': 33.00, 'toll_fee': 8.90}),
        isNull,
      );
      expect(
        createdBreakdownLine({'standardFare': 33.00, 'tollFee': 8.90}),
        isNull,
      );
    });
  });

  // Verbatim §1.3 ride-details payload with nested `receipt`.
  Map<String, dynamic> rideDetailsWithReceipt() => {
        'success': true,
        'data': {
          'rideId': '67045b8e9a21a002b2c9e201',
          'status': 'completed',
          'pickup': {'address': 'Birmingham City Centre'},
          'dropoff': {'address': 'Cannock Retail Park'},
          'driver': {
            'name': 'David Smith',
            'carModel': 'Toyota Prius (Silver)',
            'plateNumber': 'WP19 XYZ',
          },
          'receipt': {
            'tripFare': 33.00,
            'tollFee': 8.90,
            'tollName': 'M6 Toll Highway',
            'totalCharged': 41.90,
            'paymentMethod': 'stripe',
            'currency': 'GBP',
          },
          'completedAt': '2026-10-08T11:45:00.000Z',
        },
      };

  // Verbatim §3.3 ride:completed PASSENGER payload (top-level toll keys).
  Map<String, dynamic> rideCompletedSocket() => {
        'event': 'ride:completed',
        'payload': {
          'rideId': '67045b8e9a21a002b2c9e201',
          'fare': 33.00,
          'tollFee': 8.90,
          'tollName': 'M6 Toll Highway',
          'totalFare': 41.90,
          'paymentType': 'stripe',
          'paymentStatus': 'paid',
          'currency': 'GBP',
        },
      };

  // Absent-toll receipt (today's shape) and a bare legacy ride map.
  Map<String, dynamic> receiptNoToll() => {
        'tripFare': 33.00,
        'totalCharged': 33.00,
        'paymentMethod': 'stripe',
        'currency': 'GBP',
      };

  group('TOLL-03 §1.3 receipt / §3.3 socket → receipt card', () {
    test('§1.3 receipt parses tollFee/tollName/totalCharged verbatim', () {
      final data = rideDetailsWithReceipt()['data'] as Map<String, dynamic>;
      final info = TollInfo.fromBreakdown(data['receipt']);
      expect(info.tollFee, 8.90);
      expect(info.tollName, 'M6 Toll Highway');
      expect(info.total, 41.90); // totalCharged passthrough
      expect(info.hasToll, isTrue);
    });

    test('§3.3 socket payload parses fare/toll/totalFare verbatim', () {
      final payload =
          rideCompletedSocket()['payload'] as Map<String, dynamic>;
      final info = TollInfo.fromBreakdown(payload);
      expect(info.tollFee, 8.90);
      expect(info.tollName, 'M6 Toll Highway');
      expect(info.total, 41.90); // totalFare passthrough
      expect(info.hasToll, isTrue);
      expect(payload['fare'], 33.00); // fare stays the component, not total
    });

    test('displayed total == backend total, never fare + toll computed',
        () {
      // REST §1.3: TOTAL line takes receipt.totalCharged VERBATIM.
      final rest = rideDetailsWithReceipt()['data'] as Map<String, dynamic>;
      expect(displayTotal(rest, 33.00), 41.90);
      expect(displayTotal(rest, 33.00), (rest['receipt'] as Map)['totalCharged']);

      // Socket §3.3: TOTAL line takes the backend totalFare verbatim.
      final socket = rideCompletedSocket()['payload'] as Map<String, dynamic>;
      expect(displayTotal(socket, 33.00), 41.90);
      expect(displayTotal(socket, 33.00), socket['totalFare']);

      // Backend total that is NOT fare + toll: client math would say
      // 42.90, the receipt says 41.90 — displayed total must be 41.90.
      expect(
        displayTotal({
          'receipt': {'tripFare': 34.00, 'tollFee': 8.90, 'totalCharged': 41.90},
        }, 34.00),
        41.90,
      );
      expect(34.00 + 8.90, isNot(41.90));
    });

    test('toll row visible for both REST §1.3 and socket §3.3 shapes', () {
      final rest = rideDetailsWithReceipt()['data'] as Map<String, dynamic>;
      expect(screenTollInfo(rest).tollFee, 8.90);
      expect(screenTollInfo(rest).tollName, 'M6 Toll Highway');
      final socket = rideCompletedSocket()['payload'] as Map<String, dynamic>;
      expect(screenTollInfo(socket).tollFee, 8.90);
      expect(screenTollInfo(socket).tollName, 'M6 Toll Highway');
    });

    test('absent toll keys → no row, legacy total path (TOLL-08)', () {
      expect(screenTollInfo({'receipt': receiptNoToll()}).tollFee, 0.0);
      expect(screenTollInfo({'receipt': receiptNoToll()}).hasToll, isFalse);
      // Receipt totalCharged still drives the TOTAL line (33.00 == legacy).
      expect(displayTotal({'receipt': receiptNoToll()}, 33.00), 33.00);
      // No receipt, no toll: legacy resolution untouched.
      expect(displayTotal({'fare': 12.5}, 12.5), 12.5);
      // No receipt, toll-free top-level fare keys: still legacy.
      expect(displayTotal({'fare': 12.5, 'totalFare': 12.5}, 12.5), 12.5);
    });

    test('TollInfo never throws on malformed receipt shapes', () {
      expect(() => TollInfo.fromBreakdown({'receipt': 'junk'}), returnsNormally);
      expect(
        () => screenTollInfo({
          'receipt': {'tollFee': 'abc', 'totalCharged': null},
        }),
        returnsNormally,
      );
    });
  });
}
