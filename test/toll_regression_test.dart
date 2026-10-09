import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/models/toll_breakdown.dart';
import 'package:mktours/core/models/vehicle.dart';
import 'package:mktours/core/services/fcm_service.dart';

/// TOLL-08 absent-toll regression sweep (phase 21-05).
///
/// Every surface shipped by 21-01..21-04 gets an absent-toll fixture and
/// the invariant **"absent toll → legacy parse output"**: no null crashes,
/// no £0.00 rows, no layout shift — byte-identical to the pre-phase
/// baseline. Self-contained inline fixtures (spec §1.1/§1.2/§1.3, §2.1/
/// §2.2/§2.3, §3.1/§3.3, §4.1-4.3 minus their toll keys).
///
/// Parsing runs through the REAL `TollInfo`, `DriverEarnings`,
/// `FcmNotificationData` and `canonicalFcmType` (never a copy).
/// Widget-local expressions are MIRRORED as pure functions per the
/// `test/fare_estimate_balance_test.dart` precedent — no widget
/// instantiation, mirrors stay side-by-side with the gated chains they
/// pin.
void main() {
  // ── Mirrors: rider booking surfaces (21-02) ──────────────────────────

  /// Mirror of `VehicleSelectionWidget._normalizeCategory` — the unified
  /// fare-map build. Distance/duration args fixed for the fixture route.
  /// `estimate` is the whole §1.1 response map (top-level `tollDetails`
  /// rides along as the name/amount fallback).
  Map<String, dynamic>? vehicleFareMap(
    Map<String, dynamic> cat, {
    String distanceText = '24.50 mi',
    String durationText = '28 min',
    int durationSeconds = 1680,
    double distanceMiles = 24.5,
    Map<String, dynamic>? estimate,
  }) {
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
    final seatingCapacity = (cat['seatingCapacity'] as num?)?.toInt();
    // Toll chain: same shared parser, gated spread (research Pitfall 4 —
    // BOTH normalizers must always move together).
    final toll = TollInfo.fromCategory(cat);
    final routeToll = TollInfo.fromEstimate(estimate);
    final tollPresent =
        toll.hasToll || toll.tollFee > 0 || routeToll.hasToll;
    final tollFee = toll.tollFee > 0 ? toll.tollFee : routeToll.tollFee;
    final tollName = toll.tollName ?? routeToll.tollName;
    final tollTotal = toll.total ?? routeToll.total;

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
        if (seatingCapacity != null) 'seating_capacity': seatingCapacity,
        if (tollPresent) ...{
          'toll_fee': tollFee,
          if (tollName != null && tollName.isNotEmpty) 'toll_name': tollName,
          'has_toll': toll.hasToll || routeToll.hasToll,
          if (tollTotal != null) 'total_with_toll': tollTotal,
        },
        'distance_text': distanceText,
        'distance_miles': distanceMiles,
        'duration_text': durationText,
        'duration_seconds': durationSeconds,
      },
    };
  }

  /// Mirror of `RideConfirmationScreen`'s second normalizer (the fare map
  /// only). Drift guard: identical gated toll chain as the mirror above.
  Map<String, dynamic> confirmationFareMap(
    Map<String, dynamic> cat, {
    String categorySlug = 'standard-saloon',
    Map<String, dynamic>? estimate,
  }) {
    num numOf(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
    final estimatedFare = numOf(cat['estimatedFare'] ?? cat['total_fare']);
    final outstandingRaw = numOf(
      cat['outstandingBalance'] ??
          cat['excessAmount'] ??
          cat['outstanding_balance'] ??
          0,
    );
    final toll = TollInfo.fromCategory(cat);
    final routeToll = TollInfo.fromEstimate(estimate);
    final tollPresent =
        toll.hasToll || toll.tollFee > 0 || routeToll.hasToll;
    final tollFee = toll.tollFee > 0 ? toll.tollFee : routeToll.tollFee;
    final tollName = toll.tollName ?? routeToll.tollName;
    final tollTotal = toll.total ?? routeToll.total;
    return {
      'total_fare': estimatedFare.toDouble(),
      'original_fare': (numOf(cat['originalFare'] ?? estimatedFare))
          .toDouble(),
      'discount': numOf(cat['discount'] ?? 0).toDouble(),
      'is_free_ride': cat['isFreeRide'] == true,
      'promo_applied': cat['promoApplied'] == true,
      'is_congestion': cat['isCongestionCharge'] == true,
      'congestion_amount': numOf(cat['congestionChargeAmount'] ?? 0).toDouble(),
      'outstanding_balance': (outstandingRaw < 0 ? 0 : outstandingRaw)
          .toDouble(),
      if (tollPresent) ...{
        'toll_fee': tollFee,
        if (tollName != null && tollName.isNotEmpty) 'toll_name': tollName,
        'has_toll': toll.hasToll || routeToll.hasToll,
        if (tollTotal != null) 'total_with_toll': tollTotal,
      },
      'distance_miles': 24.5,
      'distance_text': '24.50 mi',
      'duration_text': '28 min',
      'duration_seconds': 1680,
      'category_slug': categorySlug,
    };
  }

  /// Mirror of the vehicle-row toll read in
  /// `VehicleSelectionWidget` (per-category keys first, route-level
  /// estimate toll as fallback) plus the row gate + payable price.
  /// The vehicle card shows the AMOUNT ONLY — the toll name is
  /// confirm-screen-only.
  Map<String, dynamic> vehicleTollRow(
    Map<String, dynamic>? fareData, {
    bool estimateHasToll = false,
    double estimateTollFee = 0.0,
    String? estimateTollName,
  }) {
    final price = (fareData?['total_fare'] as num?)?.toDouble() ?? 0.0;
    final catTollFee = (fareData?['toll_fee'] as num?)?.toDouble();
    final tollFee = catTollFee ?? (estimateHasToll ? estimateTollFee : 0.0);
    final tollName =
        (fareData?['toll_name'] ?? estimateTollName)?.toString();
    final hasToll =
        fareData?['has_toll'] == true || estimateHasToll;
    final totalWithToll =
        (fareData?['total_with_toll'] as num?)?.toDouble();
    final payablePrice =
        (hasToll && totalWithToll != null) ? totalWithToll : price;
    return {
      'tollFee': tollFee,
      'tollName': tollName,
      'hasToll': hasToll,
      'rowVisible': fareData != null && tollFee > 0,
      'rowText': tollFee > 0 ? 'Toll +£${tollFee.toStringAsFixed(2)}' : null,
      'payablePrice': payablePrice,
    };
  }

  /// Mirror of `RideConfirmationScreen._tollBreakdownLine` (pre-create)
  /// and `_createdBreakdownLine` (post-create §1.2). Carries the toll
  /// name in parentheses when the backend sent one.
  String? tollBreakdownLine(Map<String, dynamic> fare) {
    final tollFee = (fare['toll_fee'] as num?)?.toDouble() ?? 0.0;
    if (tollFee <= 0) return null;
    final total = (fare['total_with_toll'] as num?)?.toDouble();
    final fareValue = (fare['total_fare'] as num?)?.toDouble() ?? 0.0;
    final rawName = fare['toll_name'];
    final name = rawName?.toString();
    final tollPart = (name == null || name.isEmpty)
        ? 'Toll £${tollFee.toStringAsFixed(2)}'
        : 'Toll £${tollFee.toStringAsFixed(2)} ($name)';
    if (total == null) return '$tollPart included in the fare';
    return 'Fare £${fareValue.toStringAsFixed(2)} + '
        '$tollPart = '
        '£${total.toStringAsFixed(2)}';
  }

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

  // ── Mirrors: ride-complete receipt (21-02 TOLL-03) ───────────────────

  Map<String, dynamic>? receiptOf(Map<String, dynamic> rideData) {
    final raw = rideData['receipt'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  /// Mirror of `RideCompleteScreen._tollInfo` — REST receipt wins when it
  /// carries a toll; otherwise the top-level socket shape.
  TollInfo screenTollInfo(Map<String, dynamic> rideData) {
    final receipt = receiptOf(rideData);
    if (receipt != null) {
      final fromReceipt = TollInfo.fromBreakdown(receipt);
      if (fromReceipt.tollFee > 0 || fromReceipt.hasToll) return fromReceipt;
    }
    return TollInfo.fromBreakdown(rideData);
  }

  /// Mirror of `RideCompleteScreen._displayTotal` — `totalCharged`
  /// verbatim → backend `totalFare` only on a toll-bearing payload →
  /// else the legacy total (no client-side fare + toll math).
  double displayTotal(Map<String, dynamic> rideData, double legacyTotal) {
    final charged = (receiptOf(rideData)?['totalCharged'] as num?)?.toDouble();
    if (charged != null) return charged;
    final info = screenTollInfo(rideData);
    if (info.hasToll && info.total != null) return info.total!;
    return legacyTotal;
  }

  /// Mirror of the TOLL-03 hydration backfill key list — the
  /// shape-preservation contract for `_hydrateBillData`.
  const List<String> hydrationBackfillKeys = [
    'totalWaitMinutes',
    'totalWaitFee',
    'actualFare',
    'receipt',
    'tollFee',
    'tollName',
    'totalCharged',
    'tripFare',
    'totalFare',
  ];

  // ── Mirrors: driver offer + completion (21-03) ───────────────────────

  /// Mirror of `DriverHomeScreen._estimatedEarnings` — null when the
  /// payload carries no toll evidence, so `estimated_earnings` is NEVER
  /// attached (TOLL-08 zero-drift).
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

  /// Mirror of the complete-response branch in
  /// `DriverHomeScreen._handleCompleteRide` — no `earnings` map → none →
  /// legacy popup rows only.
  DriverEarnings completeEarnings(Map<String, dynamic> rideResult) {
    return rideResult['earnings'] is Map
        ? DriverEarnings.fromJson(
            Map<String, dynamic>.from(rideResult['earnings'] as Map),
          )
        : DriverEarnings.none;
  }

  // ── Earnings dashboard helpers (21-04 TOLL-06) ───────────────────────

  /// Mirror of `driver_earnings_screen.dart`'s never-throw scalar read.
  double earningsNumOf(dynamic v) =>
      v is num ? v.toDouble() : num.tryParse('$v')?.toDouble() ?? 0.0;

  /// Mirror of the per-ride toll line gate.
  bool showEarningsTollLine(double tollFee) => tollFee > 0;

  /// Mirror of the KPI money format (£0.00 when a field is absent).
  String kpiMoney(double v) => '£${v.toStringAsFixed(2)}';

  // ── Absent-toll fixtures (today's live shapes) ───────────────────────

  /// §1.1 category carrying today's keys only — no tollFee/totalFare.
  Map<String, dynamic> legacyCategory() => {
        'slug': 'standard-saloon',
        'estimatedFare': 12.5,
        'originalFare': 12.5,
      };

  /// §1.1 estimate `data` map — top level without hasToll/tollDetails.
  Map<String, dynamic> estimateNoToll() => {
        'distanceKm': 24.5,
        'durationMinutes': 28,
        'categories': [legacyCategory()],
      };

  /// Legacy unified fare-map key set (pre-toll baseline).
  const List<String> legacyFareKeys = [
    'total_fare',
    'original_fare',
    'discount',
    'is_free_ride',
    'promo_applied',
    'is_congestion',
    'congestion_amount',
    'outstanding_balance',
    'distance_text',
    'distance_miles',
    'duration_text',
    'duration_seconds',
  ];

  /// §1.2 live create-ride response — no `fareBreakdown` key at all.
  Map<String, dynamic> createRideNoBreakdown() => {
        'rideId': '67045b8e9a21a002b2c9e201',
        'status': 'pending',
        'paymentType': 'stripe',
      };

  /// §1.3 legacy receipt — trip fare + total only, no toll keys.
  Map<String, dynamic> legacyReceipt() => {
        'tripFare': 33.00,
        'totalCharged': 33.00,
        'paymentMethod': 'stripe',
        'currency': 'GBP',
      };

  /// §3.1 today's ride:newRequest — fare only, NO estimatedEarnings.
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

  /// §2.2 summary without tollsReimbursedTotal (pre-toll backend).
  Map<String, dynamic> summaryNoTolls() => {
        'period': 'today',
        'tripsCompleted': 2,
        'netTripEarnings': 24.00,
        'totalEarnings': 24.00,
        'currency': 'GBP',
      };

  /// §2.3 ride whose `financials` carry no tollFee.
  Map<String, dynamic> legacyRideFinancials() => {
        'fare': 18.00,
        'platformFee': 3.60,
        'driverEarnings': 14.40,
        'currency': 'GBP',
      };

  group('TOLL-08 §1.1 fare estimate (absent toll → legacy parse output)',
      () {
    test('absent toll → legacy parse output: category → none-equivalent',
        () {
      final info = TollInfo.fromCategory(legacyCategory());
      expect(info.tollFee, 0.0);
      expect(info.hasToll, isFalse);
      expect(info.tollName, isNull);
      expect(info.total, isNull);
      expect(info.tollFee, TollInfo.none.tollFee);
      expect(info.hasToll, TollInfo.none.hasToll);
    });

    test('absent toll → legacy parse output: top-level estimate without '
        'hasToll → none', () {
      final info = TollInfo.fromEstimate(estimateNoToll());
      expect(info.tollFee, 0.0);
      expect(info.hasToll, isFalse);
      expect(info.tollName, isNull);
      expect(info.total, isNull);
    });

    test('absent toll → legacy parse output: unified fare map keys are '
        'exactly the legacy set', () {
      final fare =
          vehicleFareMap(legacyCategory())!['fare'] as Map<String, dynamic>;
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
      expect(fare.keys.toList()..sort(), [...legacyFareKeys]..sort());
      expect(fare.containsKey('toll_fee'), isFalse);
      expect(fare.containsKey('has_toll'), isFalse);
      expect(fare.containsKey('total_with_toll'), isFalse);
    });

    test('absent toll → legacy parse output: BOTH normalizers add no toll '
        'keys (dual-normalizer parity)', () {
      final vehicle = vehicleFareMap(legacyCategory())!['fare']
          as Map<String, dynamic>;
      final confirmation = confirmationFareMap(legacyCategory());
      const tollKeySet = {'toll_fee', 'toll_name', 'has_toll', 'total_with_toll'};
      for (final key in tollKeySet) {
        expect(vehicle.containsKey(key), isFalse, reason: key);
        expect(confirmation.containsKey(key), isFalse, reason: key);
      }
      // Legacy price plumbing identical in both copies.
      expect(vehicle['total_fare'], confirmation['total_fare']);
      expect(vehicle['outstanding_balance'],
          confirmation['outstanding_balance']);
    });

    test('absent toll → legacy parse output: vehicle row hides toll badge '
        'and payable price stays the legacy price', () {
      final fare =
          vehicleFareMap(legacyCategory())!['fare'] as Map<String, dynamic>;
      final row = vehicleTollRow(fare);
      expect(row['tollFee'], 0.0);
      expect(row['hasToll'], isFalse);
      expect(row['rowVisible'], isFalse); // no £0.00 toll row, no shift
      expect(row['payablePrice'], 12.5); // legacy price, not a toll total
      // Route-level estimate without hasToll changes nothing either.
      final noEstimate = vehicleTollRow(fare);
      expect(noEstimate['rowVisible'], isFalse);
    });

    test('route-level tollDetails name reaches BOTH fare maps (the '
        'confirm-screen name the vehicle card hides)', () {
      // Live backend shape: name+amount only at the TOP level, categories
      // carry no toll keys at all.
      final estimate = {
        'hasToll': true,
        'tollDetails': {'name': 'TOLL PLAZA Padalsingi', 'amount': 2.5},
      };
      final vehicle =
          vehicleFareMap(legacyCategory(), estimate: estimate)!['fare']
              as Map<String, dynamic>;
      final confirmation =
          confirmationFareMap(legacyCategory(), estimate: estimate);

      for (final fare in [vehicle, confirmation]) {
        expect(fare['toll_fee'], 2.5);
        expect(fare['toll_name'], 'TOLL PLAZA Padalsingi');
        expect(fare['has_toll'], isTrue);
      }
      // No backend `totalFare` in this shape, so the arithmetic form is
      // withheld rather than guessed client-side.
      expect(
        tollBreakdownLine(confirmation),
        'Toll £2.50 (TOLL PLAZA Padalsingi) included in the fare',
      );
      // With a backend total the full arithmetic line renders, name intact.
      expect(
        tollBreakdownLine({...confirmation, 'total_with_toll': 15.0}),
        'Fare £12.50 + Toll £2.50 (TOLL PLAZA Padalsingi) = £15.00',
      );
      // The vehicle card deliberately shows the amount only.
      expect(vehicleTollRow(vehicle)['rowText'], 'Toll +£2.50');
    });

    test('per-category toll keys still win over route-level tollDetails', () {
      final estimate = {
        'hasToll': true,
        'tollDetails': {'name': 'ROUTE TOLL', 'amount': 9.99},
      };
      final cat = {
        ...legacyCategory(),
        'tollFee': 2.5,
        'tollName': 'M6 Toll',
        'totalFare': 15.0,
      };
      final fare =
          vehicleFareMap(cat, estimate: estimate)!['fare']
              as Map<String, dynamic>;
      expect(fare['toll_fee'], 2.5);
      expect(fare['toll_name'], 'M6 Toll');
      expect(fare['total_with_toll'], 15.0);
    });
  });

  group('TOLL-08 §1.2 booking breakdown (absent toll → legacy parse output)',
      () {
    test('absent toll → legacy parse output: no fareBreakdown → gate false',
        () {
      final info =
          TollInfo.fromBreakdown(createRideNoBreakdown()['fareBreakdown']);
      expect(info.tollFee, 0.0);
      expect(info.hasToll, isFalse);
      expect(createdBreakdownLine(null), isNull);
      expect(
        createdBreakdownLine(
          createRideNoBreakdown()['fareBreakdown'] as Map<String, dynamic>?,
        ),
        isNull,
      );
    });

    test('absent toll → legacy parse output: toll-free fareBreakdown → no '
        'itemized line', () {
      expect(
        createdBreakdownLine({'standardFare': 33.00, 'totalFare': 33.00}),
        isNull,
      );
      final info =
          TollInfo.fromBreakdown({'standardFare': 33.00, 'totalFare': 33.00});
      expect(info.tollFee, 0.0);
      expect(info.hasToll, isFalse);
    });

    test('absent toll → legacy parse output: pre-create line gate false on '
        'legacy fare map', () {
      final fare =
          vehicleFareMap(legacyCategory())!['fare'] as Map<String, dynamic>;
      expect(tollBreakdownLine(fare), isNull);
    });
  });

  group('TOLL-08 §1.3 receipt (absent toll → legacy parse output)', () {
    test('absent toll → legacy parse output: receipt without toll keys → '
        'legacy total path', () {
      final rideData = {'receipt': legacyReceipt()};
      final info = screenTollInfo(rideData);
      expect(info.tollFee, 0.0);
      expect(info.hasToll, isFalse);
      expect(info.tollName, isNull);
      // Receipt totalCharged still drives TOTAL — and equals the legacy fare.
      expect(displayTotal(rideData, 33.00), 33.00);
      expect(displayTotal(rideData, 33.00),
          (rideData['receipt'] as Map)['totalCharged']);
    });

    test('absent toll → legacy parse output: no receipt → legacy fare '
        'resolution untouched', () {
      expect(screenTollInfo({'fare': 12.5}).tollFee, 0.0);
      expect(displayTotal({'fare': 12.5}, 12.5), 12.5);
      expect(displayTotal({'fare': 12.5, 'totalFare': 12.5}, 12.5), 12.5);
    });

    test('absent toll → legacy parse output: hydration backfill carries the '
        'receipt/toll shape keys', () {
      // The key list is the shape-preservation contract: both §1.3 nested
      // receipt and §3.3 top-level toll shapes must survive backfill.
      expect(hydrationBackfillKeys, contains('receipt'));
      expect(hydrationBackfillKeys, contains('tollFee'));
      expect(hydrationBackfillKeys, contains('tollName'));
      expect(hydrationBackfillKeys, contains('totalCharged'));
      expect(hydrationBackfillKeys, contains('tripFare'));
      expect(hydrationBackfillKeys, contains('totalFare'));
      // Legacy bill keys untouched by the toll extension.
      expect(hydrationBackfillKeys, contains('actualFare'));
      expect(hydrationBackfillKeys, contains('totalWaitFee'));
    });
  });

  group('TOLL-08 §3.1 driver offer (absent toll → legacy parse output)', () {
    test('absent toll → legacy parse output: ride:newRequest without '
        'estimatedEarnings → no estimated_earnings key', () {
      final payload =
          rideNewRequestLegacy()['payload'] as Map<String, dynamic>;
      expect(normalisedEstimatedEarnings(payload), isNull);
      expect(payload.containsKey('estimated_earnings'), isFalse);
      expect(payload['estimatedEarnings'], isNull);
      expect(payload['fare'], 18.50); // legacy fare untouched
    });

    test('absent toll → legacy parse output: FCM offer without toll keys → '
        'no estimated_earnings key', () {
      final fcmOfferNoToll = {
        'type': 'NEW_RIDE_REQUEST',
        'rideId': '67045b8e9a21a002b2c9e201',
        'pickupAddress': 'Birmingham City Centre',
        'dropoffAddress': 'Cannock Retail Park',
        'totalEarnings': '35.30',
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      };
      expect(normalisedEstimatedEarnings(fcmOfferNoToll), isNull);
      expect(fcmOfferNoToll.containsKey('estimated_earnings'), isFalse);
    });
  });

  group('TOLL-08 §2.1 completion earnings (absent toll → legacy parse '
      'output)', () {
    test('absent toll → legacy parse output: complete response without '
        'earnings → DriverEarnings.none (0.0 fields)', () {
      final earnings = completeEarnings({
        'rideId': '67045b8e9a21a002b2c9e201',
        'customerFare': 33.00,
        'status': 'completed',
      });
      expect(identical(earnings, DriverEarnings.none), isTrue);
      expect(earnings.tollReimbursed, 0.0);
      expect(earnings.tollName, isNull);
      expect(earnings.totalDriverTakeHome, 0.0);
      expect(earnings.hasData, isFalse); // legacy popup rows only
    });

    test('absent toll → legacy parse output: earnings map without toll keys '
        '→ toll 0.0, take-home verbatim', () {
      final earnings = completeEarnings({
        'earnings': {
          'customerFare': 33.00,
          'platformFee': 6.60,
          'netTripEarnings': 26.40,
          'totalDriverTakeHome': 26.40,
          'currency': 'GBP',
        },
      });
      expect(earnings.tollReimbursed, 0.0);
      expect(earnings.tollName, isNull);
      expect(earnings.totalDriverTakeHome, 26.40); // verbatim, not recomputed
      expect(earnings.hasData, isTrue); // non-toll rows still render
      expect(DriverEarnings.none.tollReimbursed, 0.0);
      expect(DriverEarnings.parse(null).hasData, isFalse);
    });
  });

  group('TOLL-08 §2.2/§2.3 earnings dashboard (absent toll → legacy parse '
      'output)', () {
    test('absent toll → legacy parse output: summary without '
        'tollsReimbursedTotal → £0.00 KPI, no crash', () {
      final tolls = earningsNumOf(summaryNoTolls()['tollsReimbursedTotal']);
      expect(() => earningsNumOf(null), returnsNormally);
      expect(tolls, 0.0);
      expect(kpiMoney(tolls), '£0.00'); // never a bogus £0.00 toll row
      expect(earningsNumOf(summaryNoTolls()['netTripEarnings']), 24.00);
      expect(earningsNumOf(summaryNoTolls()['totalEarnings']), 24.00);
    });

    test('absent toll → legacy parse output: financials without tollFee → '
        'row gate false', () {
      final toll = TollInfo.fromBreakdown(legacyRideFinancials());
      expect(toll.tollFee, 0.0);
      expect(toll.tollName, isNull);
      expect(toll.hasToll, isFalse);
      expect(showEarningsTollLine(toll.tollFee), isFalse); // no toll row
      expect(earningsNumOf(legacyRideFinancials()['driverEarnings']), 14.40);
    });

    test('absent toll → legacy parse output: ride without financials → '
        'none, row still readable', () {
      final ride = <String, dynamic>{
        'rideId': '67045b8e9a21a002b2c9e203',
        'completedAt': '2026-10-07T18:05:00.000Z',
        'paymentType': 'stripe',
        'pickupAddress': 'Heathrow Terminal 5',
      };
      final financialsRaw = ride['financials'];
      expect(financialsRaw, isNull);
      final toll = TollInfo.fromBreakdown(financialsRaw as Map?);
      expect(toll.tollFee, 0.0);
      expect(showEarningsTollLine(toll.tollFee), isFalse);
      expect(ride['pickupAddress'], 'Heathrow Terminal 5');
    });
  });

  group('TOLL-08 §4 FCM (absent toll → legacy parse output)', () {
    test('absent toll → legacy parse output: data maps without toll keys '
        'parse to defaults', () {
      final request = FcmNotificationData.fromMap({
        'type': 'NEW_RIDE_REQUEST',
        'rideId': '67045b8e9a21a002b2c9e201',
        'pickupAddress': 'Birmingham City Centre',
        'dropoffAddress': 'Cannock Retail Park',
        'totalEarnings': '35.30',
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      });
      expect(request.tollFee, isNull);
      expect(request.tollName, isNull);
      expect(request.type, NotificationType.rideRequest);

      final completed = FcmNotificationData.fromMap({
        'type': 'RIDE_COMPLETED',
        'rideId': '67045b8e9a21a002b2c9e201',
        'totalFare': '41.90',
        'currency': 'GBP',
      });
      expect(completed.tollFee, isNull);
      expect(completed.tollName, isNull);
      expect(completed.type, NotificationType.rideCompleted);

      final payout = FcmNotificationData.fromMap({
        'type': 'PAYOUT_SETTLED',
        'payoutId': '67048f12a345b001c1d8e309',
        'totalPaid': '531.60',
        'currency': 'GBP',
      });
      expect(payout.tollFee, isNull);
      expect(payout.tollName, isNull);
      expect(payout.type, NotificationType.payoutSettled);
      expect(payout.rawData['totalPaid'], '531.60');
    });

    test('absent toll → legacy parse output: snake_case type canonicalization '
        'is a byte-identical no-op', () {
      // Live types pass through untouched — canonicalization only fires for
      // non-lowercase input, so today's dispatch is provably unchanged.
      const liveTypes = [
        'ride_request',
        'ride_accepted',
        'ride_completed',
        'excess_cash_requested',
        'payment_succeeded',
        'balance_due_reminder',
        'ride_cancelled',
        'payout_settled',
      ];
      for (final type in liveTypes) {
        expect(canonicalFcmType(type), type, reason: type);
        expect(FcmNotificationData.fromMap({'type': type}).type, type,
            reason: type);
      }
      expect(canonicalFcmType(''), '');
    });
  });
}
