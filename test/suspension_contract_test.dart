import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/models/outstanding_balance.dart';

/// Suspension-flag contract (Phase 13 INTEGRATION-GUIDE.md §1).
///
/// Backend still sends `accountSuspended` + `allowCash` flags (Phase 13),
/// but Phase 15 removes the suspension UX entirely — booking now silently
/// includes the balance. `isSuspended` getter always returns false.
/// Fields retained for backend compat; tests pin parsing, not UX.
void main() {
  group('Suspension flags (backend compat — Phase 15 removes UX)', () {
    test('brief exact §1 JSON parses fields but isSuspended=false (UX removed)', () {
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
      expect(b!.isSuspended, isFalse); // UX removed per Phase 15
      expect(b.isOwed, isTrue);
      expect(b.amount, 2.50);
      expect(b.hasPaymentUrl, isTrue);
      expect(b.accountSuspended, isTrue); // parsed for compat
      expect(b.allowCash, isFalse); // parsed for compat
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

    test('suspended flag with cash allowed — isSuspended always false', () {
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
      expect(b.isSuspended, isFalse); // UX removed per Phase 15
    });

    test('string and int flag variants parse tolerantly (compat)', () {
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
      expect(suspended!.isSuspended, isFalse); // UX removed per Phase 15
      expect(suspended.accountSuspended, isTrue);
      expect(suspended.allowCash, isFalse);

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
      expect(cleared.accountSuspended, isFalse);
      expect(cleared.allowCash, isTrue);
    });

    test('fromBalanceDueEvent with flags parses fields but isSuspended=false', () {
      final b = OutstandingBalance.fromBalanceDueEvent({
        'rideId': '6aabc3476a4199e81748403e',
        'excessAmount': 2.50,
        'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_123',
        'accountSuspended': true,
        'allowCash': false,
        'message': 'You have an outstanding balance.',
      });
      expect(b.isSuspended, isFalse); // UX removed per Phase 15
      expect(b.isOwed, isTrue);
      expect(b.amount, 2.50);
      expect(b.accountSuspended, isTrue);
      expect(b.allowCash, isFalse);
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