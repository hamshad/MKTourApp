import 'package:flutter_test/flutter_test.dart';

/// Contract tests for fare-estimate `outstandingBalance` parsing
/// (Phase 15 §1: backend already folds the debt into `estimatedFare`).
///
/// Mirrors the tolerant expression in
/// `VehicleSelectionWidget._normalizeCategory` without instantiating
/// the widget: `numOf(cat['outstandingBalance'] ?? cat['excessAmount'] ??
/// cat['outstanding_balance'] ?? 0)` clamped to >= 0, with `total_fare`
/// taken verbatim from `estimatedFare`.
Map<String, double> parseFareCategory(Map<String, dynamic> cat) {
  num numOf(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
  final estimatedFare = numOf(cat['estimatedFare'] ?? cat['total_fare']);
  final raw = numOf(
    cat['outstandingBalance'] ??
        cat['excessAmount'] ??
        cat['outstanding_balance'] ??
        0,
  );
  final outstanding = (raw < 0 ? 0 : raw);
  return {
    'total_fare': estimatedFare.toDouble(),
    'outstanding_balance': outstanding.toDouble(),
  };
}

void main() {
  group('fare-estimate outstandingBalance contract (brief §1)', () {
    test('brief example: estimatedFare 15 + outstandingBalance 5', () {
      final fare = parseFareCategory({
        'slug': 'standard',
        'name': 'Standard',
        'estimatedFare': 15,
        'originalFare': 15,
        'outstandingBalance': 5,
        'discount': 0,
        'isFreeRide': false,
      });
      expect(fare['total_fare'], 15.0);
      expect(fare['outstanding_balance'], 5.0);
    });

    test('missing field defaults balance to 0.0, total untouched', () {
      final fare = parseFareCategory({
        'slug': 'standard',
        'estimatedFare': 12.5,
        'originalFare': 12.5,
      });
      expect(fare['total_fare'], 12.5);
      expect(fare['outstanding_balance'], 0.0);
    });

    test('string "5" parses to 5.0', () {
      final fare = parseFareCategory({
        'slug': 'standard',
        'estimatedFare': '15',
        'outstandingBalance': '5',
      });
      expect(fare['total_fare'], 15.0);
      expect(fare['outstanding_balance'], 5.0);
    });

    test('balance is never added into total (no double-count)', () {
      final fare = parseFareCategory({
        'slug': 'standard',
        'estimatedFare': 15,
        'outstandingBalance': 5,
      });
      // Backend total is authoritative: 15 already includes the 5.
      // A double-counting implementation would yield 20 here.
      expect(fare['total_fare'], 15.0);
      expect(fare['total_fare'], isNot(20.0));
      expect(
        fare['total_fare']! + fare['outstanding_balance']!,
        isNot(15.0),
      );
    });

    test('excessAmount fallback key parses', () {
      final fare = parseFareCategory({
        'slug': 'standard',
        'estimatedFare': 15,
        'excessAmount': 3.5,
      });
      expect(fare['outstanding_balance'], 3.5);
      expect(fare['total_fare'], 15.0);
    });

    test('negative balance clamps to 0.0', () {
      final fare = parseFareCategory({
        'slug': 'standard',
        'estimatedFare': 10,
        'outstandingBalance': -4,
      });
      expect(fare['outstanding_balance'], 0.0);
      expect(fare['total_fare'], 10.0);
    });
  });
}
