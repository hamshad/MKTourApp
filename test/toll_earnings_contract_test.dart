import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/models/toll_breakdown.dart';

/// TOLL-06 contract tests (phase 21-04, toll_price_implementation.md §2.2
/// + §2.3).
///
/// Pins the two earnings dashboard payloads verbatim and exercises the
/// REAL shared `TollInfo` parser on each ride's `financials`, plus a
/// mirrored copy of the tolerant scalar readers used by
/// `driver_earnings_screen.dart` (same precedent as
/// `fare_estimate_balance_test.dart` — mirrors the widget expression,
/// never instantiates it). Pure Dart, no widgets.
void main() {
  // ---------------------------------------------------------------------------
  // Mirrors of the tolerant readers in driver_earnings_screen.dart.
  // ---------------------------------------------------------------------------

  /// num → double, numeric string → parsed, anything else → 0.0. Never throws.
  double numOf(dynamic v) =>
      v is num ? v.toDouble() : num.tryParse('$v')?.toDouble() ?? 0.0;

  /// `tollsReimbursedTotal` — absent/unparseable → 0.0 (never throws).
  double readTollsReimbursedTotal(Map<String, dynamic> data) =>
      numOf(data['tollsReimbursedTotal']);

  double readNetTripEarnings(Map<String, dynamic> data) =>
      numOf(data['netTripEarnings']);

  double readTotalEarnings(Map<String, dynamic> data) =>
      numOf(data['totalEarnings']);

  int readTripsCompleted(Map<String, dynamic> data) =>
      numOf(data['tripsCompleted']).toInt();

  /// `payoutStatus` — absent / non-map → null (row not rendered).
  Map<String, dynamic>? readPayoutStatus(Map<String, dynamic> data) {
    final v = data['payoutStatus'];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  /// Rendering gate for the per-ride toll line: shown only when fee > 0.
  bool showTollLine(double tollFee) => tollFee > 0;

  /// KPI tile money formatting (`£0.00` when a field is absent).
  String kpiMoney(double v) => '£${v.toStringAsFixed(2)}';

  /// Itemized toll line copy built by the rides list tile.
  String tollLineLabel(String? tollName, double fee) =>
      'Toll · ${tollName ?? 'Toll'} £${fee.toStringAsFixed(2)}';

  /// Period tab label → API `period` value (spec §2.2 dashboard tabs).
  const Map<String, String> periodTabs = {
    'Today': 'today',
    'Week': 'week',
    'Month': 'month',
    'All': 'all',
  };

  // ---------------------------------------------------------------------------
  // Verbatim §2.2 Driver Earnings Summary payload.
  // ---------------------------------------------------------------------------
  Map<String, dynamic> earningsSummaryWeek() => {
        'success': true,
        'data': {
          'period': 'week',
          'tripsCompleted': 18,
          'onlineHours': 24.5,
          'grossPassengerFares': 620.00,
          'platformDeductions': 124.00,
          'netTripEarnings': 496.00,
          'tollsReimbursedTotal': 35.60,
          'totalEarnings': 531.60,
          'payoutStatus': {
            'unsettledBalance': 310.50,
            'nextPayoutDate': '2026-10-12T00:00:00.000Z',
          },
          'currency': 'GBP',
        },
      };

  // Sparse summary — legacy backend with no toll/payout keys at all.
  Map<String, dynamic> earningsSummaryNoTolls() => {
        'success': true,
        'data': {
          'period': 'today',
          'tripsCompleted': 2,
          'netTripEarnings': 24.00,
          'totalEarnings': 24.00,
          'currency': 'GBP',
        },
      };

  // ---------------------------------------------------------------------------
  // Verbatim §2.3 Driver Earnings Rides List payload.
  // ---------------------------------------------------------------------------
  Map<String, dynamic> earningsRidesWeek() => {
        'success': true,
        'data': {
          'totalCount': 18,
          'page': 1,
          'limit': 20,
          'rides': [
            {
              'rideId': '67045b8e9a21a002b2c9e201',
              'completedAt': '2026-10-08T11:45:00.000Z',
              'paymentType': 'stripe',
              'pickupAddress': 'Birmingham City Centre',
              'dropoffAddress': 'Cannock Retail Park',
              'financials': {
                'fare': 33.00,
                'platformFee': 6.60,
                'tollFee': 8.90,
                'tollName': 'M6 Toll Highway',
                'driverEarnings': 35.30,
                'currency': 'GBP',
              },
              'isSettled': false,
            },
          ],
        },
      };

  // Legacy ride — `financials` present but no toll keys (pre-toll backend).
  Map<String, dynamic> earningsRidesNoToll() => {
        'success': true,
        'data': {
          'totalCount': 1,
          'page': 1,
          'limit': 20,
          'rides': [
            {
              'rideId': '67045b8e9a21a002b2c9e202',
              'completedAt': '2026-10-08T09:15:00.000Z',
              'paymentType': 'cash',
              'pickupAddress': 'The Shard',
              'dropoffAddress': 'Oxford Street',
              'financials': {
                'fare': 18.00,
                'platformFee': 3.60,
                'driverEarnings': 14.40,
                'currency': 'GBP',
              },
              'isSettled': true,
            },
          ],
        },
      };

  // Ride with `financials` absent entirely — row must still render.
  Map<String, dynamic> earningsRidesNoFinancials() => {
        'success': true,
        'data': {
          'totalCount': 1,
          'page': 1,
          'limit': 20,
          'rides': [
            {
              'rideId': '67045b8e9a21a002b2c9e203',
              'completedAt': '2026-10-07T18:05:00.000Z',
              'paymentType': 'stripe',
              'pickupAddress': 'Heathrow Terminal 5',
              'dropoffAddress': 'The Shard',
            },
          ],
        },
      };

  Map<String, dynamic> summaryData(Map<String, dynamic> envelope) =>
      envelope['data'] as Map<String, dynamic>;

  Map<String, dynamic> ridesData(Map<String, dynamic> envelope) =>
      envelope['data'] as Map<String, dynamic>;

  Map<String, dynamic> firstRideFinancials(Map<String, dynamic> envelope) {
    final rides = ridesData(envelope)['rides'] as List<dynamic>;
    return (rides.first as Map<String, dynamic>)['financials']
        as Map<String, dynamic>;
  }

  group('TOLL-06 earnings summary contract (spec §2.2)', () {
    test('§2.2 week fixture: tollsReimbursedTotal reads 35.60 as double', () {
      final data = summaryData(earningsSummaryWeek());
      final tolls = readTollsReimbursedTotal(data);
      expect(tolls, 35.60);
      expect(tolls, isA<double>());
      expect(readNetTripEarnings(data), 496.00);
      expect(readTotalEarnings(data), 531.60); // verbatim, never recomputed
      expect(data['totalEarnings'], 531.60); // backend authoritative
      expect(readTripsCompleted(data), 18);
      expect(data['period'], 'week');
      expect(data['onlineHours'], 24.5);
      expect(data['grossPassengerFares'], 620.00);
      expect(data['platformDeductions'], 124.00);
    });

    test('payoutStatus present → unsettledBalance + nextPayoutDate verbatim',
        () {
      final payout = readPayoutStatus(summaryData(earningsSummaryWeek()));
      expect(payout, isNotNull);
      expect(numOf(payout!['unsettledBalance']), 310.50);
      expect(payout['nextPayoutDate'], '2026-10-12T00:00:00.000Z');
    });

    test('absent tollsReimbursedTotal → 0.0, no throw', () {
      final data = summaryData(earningsSummaryNoTolls());
      expect(() => readTollsReimbursedTotal(data), returnsNormally);
      expect(readTollsReimbursedTotal(data), 0.0);
      expect(readNetTripEarnings(data), 24.00);
    });

    test('absent payoutStatus → null (row not rendered), no throw', () {
      final data = summaryData(earningsSummaryNoTolls());
      expect(() => readPayoutStatus(data), returnsNormally);
      expect(readPayoutStatus(data), isNull);
    });

    test('string-number tolls coerce to double; garbage coerces to 0.0', () {
      expect(readTollsReimbursedTotal({'tollsReimbursedTotal': '35.60'}),
          35.60);
      expect(
          readTollsReimbursedTotal({'tollsReimbursedTotal': 'n/a'}), 0.0);
      expect(readPayoutStatus({'payoutStatus': 'unsettled'}), isNull);
    });
  });

  group('TOLL-06 earnings rides contract (spec §2.3)', () {
    test('§2.3 ride financials → TollInfo.fromBreakdown toll 8.90 + name',
        () {
      final toll = TollInfo.fromBreakdown(firstRideFinancials(
        earningsRidesWeek(),
      ));
      expect(toll.tollFee, 8.90);
      expect(toll.tollName, 'M6 Toll Highway');
      expect(toll.hasToll, isTrue);
      expect(showTollLine(toll.tollFee), isTrue);
    });

    test('§2.3 headline driverEarnings 35.30 + pagination fields', () {
      final data = ridesData(earningsRidesWeek());
      expect(data['totalCount'], 18);
      expect(data['page'], 1);
      expect(data['limit'], 20);
      final rides = data['rides'] as List<dynamic>;
      final financials =
          (rides.first as Map<String, dynamic>)['financials'] as Map;
      expect(numOf(financials['driverEarnings']), 35.30);
      expect(numOf(financials['fare']), 33.00);
      expect(numOf(financials['platformFee']), 6.60);
    });

    test('legacy financials without tollFee → toll parse none, gate false',
        () {
      final toll = TollInfo.fromBreakdown(firstRideFinancials(
        earningsRidesNoToll(),
      ));
      expect(toll.tollFee, 0.0);
      expect(toll.tollName, isNull);
      expect(toll.hasToll, isFalse);
      expect(showTollLine(toll.tollFee), isFalse);
    });

    test('ride without financials at all → none, row still readable, no throw',
        () {
      final envelope = earningsRidesNoFinancials();
      final rides = ridesData(envelope)['rides'] as List<dynamic>;
      final ride = rides.first as Map<String, dynamic>;
      expect(() => TollInfo.fromBreakdown(ride['financials'] as Map?),
          returnsNormally);
      final toll = TollInfo.fromBreakdown(ride['financials'] as Map?);
      expect(toll.tollFee, 0.0);
      expect(toll.hasToll, isFalse);
      expect(showTollLine(toll.tollFee), isFalse);
      expect(ride['pickupAddress'], 'Heathrow Terminal 5');
      expect(ride['completedAt'], '2026-10-07T18:05:00.000Z');
    });
  });

  group('TOLL-06 rendering gates (earnings screen tolerant readers)', () {
    test('Tolls Reimbursed KPI: present → £35.60, absent → £0.00', () {
      expect(
        kpiMoney(readTollsReimbursedTotal(
            summaryData(earningsSummaryWeek()))),
        '£35.60',
      );
      expect(
        kpiMoney(readTollsReimbursedTotal(
            summaryData(earningsSummaryNoTolls()))),
        '£0.00',
      );
    });

    test('Net Earnings KPI reads netTripEarnings, Total Earnings verbatim',
        () {
      final data = summaryData(earningsSummaryWeek());
      expect(kpiMoney(readNetTripEarnings(data)), '£496.00');
      expect(kpiMoney(readTotalEarnings(data)), '£531.60');
    });

    test('toll line gate: fee > 0 renders labelled line, absent renders none',
        () {
      final withToll = TollInfo.fromBreakdown(
          firstRideFinancials(earningsRidesWeek()));
      expect(showTollLine(withToll.tollFee), isTrue);
      expect(tollLineLabel(withToll.tollName, withToll.tollFee),
          'Toll · M6 Toll Highway £8.90');

      final noToll = TollInfo.fromBreakdown(
          firstRideFinancials(earningsRidesNoToll()));
      expect(showTollLine(noToll.tollFee), isFalse);

      final noFinancials = TollInfo.fromBreakdown(null);
      expect(showTollLine(noFinancials.tollFee), isFalse);
    });

    test('payout row gate: present renders balance + date, absent hides row',
        () {
      final payout =
          readPayoutStatus(summaryData(earningsSummaryWeek()));
      expect(payout, isNotNull);
      expect(kpiMoney(numOf(payout!['unsettledBalance'])), '£310.50');
      expect(payout['nextPayoutDate'], '2026-10-12T00:00:00.000Z');
      expect(readPayoutStatus(summaryData(earningsSummaryNoTolls())), isNull);
    });

    test('period tabs map to API values; Yesterday intentionally unexposed',
        () {
      expect(periodTabs, {
        'Today': 'today',
        'Week': 'week',
        'Month': 'month',
        'All': 'all',
      });
      expect(periodTabs.values, isNot(contains('yesterday')));
      expect(periodTabs.keys.toList(), ['Today', 'Week', 'Month', 'All']);
    });
  });
}
