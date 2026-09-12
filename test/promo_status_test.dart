import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/models/promo_status.dart';

void main() {
  group('PromoStatus 4-state parsing', () {
    test('Scenario A none: 2 rides, 3 until eligible, all flags false', () {
      final status = PromoStatus.fromMap({
        'completedRides': 2,
        'ridesUntilEligible': 3,
        'promoStatus': 'none',
        'isEligible': false,
        'isPending': false,
        'isClaimed': false,
        'message': 'Complete 3 more rides to earn a free ride',
      });

      expect(status.completedRides, 2);
      expect(status.ridesUntilEligible, 3);
      expect(status.state, PromoState.none);
      expect(status.isEligible, isFalse);
      expect(status.isPending, isFalse);
      expect(status.isClaimed, isFalse);
    });

    test('Scenario B eligible: 5 rides, isEligible true', () {
      final status = PromoStatus.fromMap({
        'completedRides': 5,
        'ridesUntilEligible': 0,
        'promoStatus': 'eligible',
        'isEligible': true,
        'isPending': false,
        'isClaimed': false,
        'message': 'You have earned a free ride',
      });

      expect(status.completedRides, 5);
      expect(status.state, PromoState.eligible);
      expect(status.isEligible, isTrue);
      expect(status.isPending, isFalse);
      expect(status.isClaimed, isFalse);
    });

    test('Scenario C pending: locked/booked free ride, isPending true', () {
      final status = PromoStatus.fromMap({
        'completedRides': 5,
        'ridesUntilEligible': 0,
        'promoStatus': 'pending',
        'isEligible': false,
        'isPending': true,
        'isClaimed': false,
        'message': 'Your free ride is locked to your booked ride',
      });

      expect(status.state, PromoState.pending);
      expect(status.isEligible, isFalse);
      expect(status.isPending, isTrue);
      expect(status.isClaimed, isFalse);
      expect(
        status.message.toLowerCase(),
        anyOf([contains('locked'), contains('booked')]),
      );
    });

    test('Scenario D claimed: isClaimed true', () {
      final status = PromoStatus.fromMap({
        'completedRides': 6,
        'ridesUntilEligible': 0,
        'promoStatus': 'claimed',
        'isEligible': false,
        'isPending': false,
        'isClaimed': true,
        'message': 'Free ride already claimed',
      });

      expect(status.state, PromoState.claimed);
      expect(status.isClaimed, isTrue);
      expect(status.isEligible, isFalse);
      expect(status.isPending, isFalse);
    });

    test('Malformed fallback: missing keys default to none, no throw', () {
      expect(() => PromoStatus.fromMap({}), returnsNormally);
      final status = PromoStatus.fromMap({});

      expect(status.state, PromoState.none);
      expect(status.completedRides, 0);
      expect(status.ridesUntilEligible, 0);
      expect(status.isEligible, isFalse);
      expect(status.isPending, isFalse);
      expect(status.isClaimed, isFalse);
      expect(status.message, '');
    });

    test('Unknown promoStatus string defaults to none', () {
      final status = PromoStatus.fromMap({'promoStatus': 'mystery'});

      expect(status.state, PromoState.none);
      expect(status.rawStatus, 'mystery');
    });
  });

  group('PromoStatus error envelopes', () {
    test('401 envelope surfaces auth failure without throw', () {
      final envelope = {
        'success': false,
        'statusCode': 401,
        'message': 'Unauthorized',
      };

      expect(() => PromoStatus.fromMap({}), returnsNormally);
      expect(envelope['success'], isFalse);
      expect(envelope['statusCode'], 401);
    });

    test('500 envelope surfaces retryable failure without throw', () {
      final envelope = {
        'success': false,
        'statusCode': 500,
        'message': 'Internal server error',
      };

      expect(() => PromoStatus.fromMap({}), returnsNormally);
      expect(envelope['success'], isFalse);
      expect(envelope['statusCode'], 500);
    });
  });
}
