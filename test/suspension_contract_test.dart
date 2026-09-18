import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/models/outstanding_balance.dart';

/// Suspension-flag contract (Phase 13 INTEGRATION-GUIDE.md §1).
///
/// Pins the backend's exact startup-balance JSON:
/// `accountSuspended:true + allowCash:false` => [isSuspended] true.
/// Absent flags preserve today's behavior (not suspended).
void main() {
  group('Suspension flags', () {
    test('brief exact §1 JSON parses to suspended', () {
      final b = OutstandingBalance.fromBalanceEnvelope({
        'success': true,
        'data': {
          'rideId': '6aabc3476a4199e81748403e',
          'excessAmount': 2.50,
          'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_123',
          'allowCash': false,
          'accountSuspended': true,
          'status': 'balance_due',
          'message':
              'You have an outstanding balance of £2.50 from a previous ride. '
              'Account is temporarily suspended from booking new rides. '
              'Please pay online to restore access.',
        },
      }, '6aabc3476a4199e81748403e');
      expect(b, isNotNull);
      expect(b!.isSuspended, isTrue);
      expect(b.isOwed, isTrue);
      expect(b.amount, 2.50);
      expect(b.hasPaymentUrl, isTrue);
      expect(b.accountSuspended, isTrue);
      expect(b.allowCash, isFalse);
    });

    test('same JSON minus flags stays not-suspended (backward compat)', () {
      final b = OutstandingBalance.fromBalanceEnvelope({
        'success': true,
        'data': {
          'rideId': '6aabc3476a4199e81748403e',
          'excessAmount': 2.50,
          'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_123',
          'status': 'balance_due',
          'message': 'You have an outstanding balance of £2.50.',
        },
      }, '6aabc3476a4199e81748403e');
      expect(b, isNotNull);
      expect(b!.isSuspended, isFalse);
      expect(b.isOwed, isTrue);
      expect(b.accountSuspended, isFalse);
      expect(b.allowCash, isTrue);
    });

    test('suspended flag with cash allowed is not suspended (conjunction)', () {
      final b = OutstandingBalance.fromBalanceEnvelope({
        'success': true,
        'data': {
          'rideId': 'r1',
          'excessAmount': 2.50,
          'accountSuspended': true,
          'allowCash': true,
          'status': 'balance_due',
        },
      }, 'r1');
      expect(b, isNotNull);
      expect(b!.accountSuspended, isTrue);
      expect(b.allowCash, isTrue);
      expect(b.isSuspended, isFalse);
    });

    test('string and int flag variants parse tolerantly', () {
      final suspended = OutstandingBalance.fromBalanceEnvelope({
        'success': true,
        'data': {
          'rideId': 'r1',
          'excessAmount': 1.0,
          'accountSuspended': 'true',
          'allowCash': 0,
          'status': 'balance_due',
        },
      }, 'r1');
      expect(suspended, isNotNull);
      expect(suspended!.isSuspended, isTrue);

      final cleared = OutstandingBalance.fromBalanceEnvelope({
        'success': true,
        'data': {
          'rideId': 'r1',
          'excessAmount': 1.0,
          'accountSuspended': 'false',
          'allowCash': '1',
          'status': 'balance_due',
        },
      }, 'r1');
      expect(cleared, isNotNull);
      expect(cleared!.isSuspended, isFalse);
    });

    test('fromBalanceDueEvent with flags parses to suspended', () {
      final b = OutstandingBalance.fromBalanceDueEvent({
        'rideId': '6aabc3476a4199e81748403e',
        'excessAmount': 2.50,
        'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_123',
        'accountSuspended': true,
        'allowCash': false,
        'message': 'You have an outstanding balance.',
      });
      expect(b.isSuspended, isTrue);
      expect(b.isOwed, isTrue);
      expect(b.amount, 2.50);
    });

    test('succeeded envelope is paid and never suspended', () {
      final b = OutstandingBalance.fromBalanceEnvelope({
        'success': true,
        'data': {'status': 'succeeded', 'message': 'Balance already paid.'},
      }, 'r1');
      expect(b, isNotNull);
      expect(b!.isPaid, isTrue);
      expect(b.isSuspended, isFalse);
    });
  });
}
