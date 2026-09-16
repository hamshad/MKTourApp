import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/models/outstanding_balance.dart';

void main() {
  group('OutstandingBalance', () {
    test('fromBalanceEnvelope parses balance_due with paymentUrl', () {
      final b = OutstandingBalance.fromBalanceEnvelope({
        'success': true,
        'data': {
          'rideId': 'ride_abc123',
          'excessAmount': 3.45,
          'paymentUrl': 'https://pay.example/xyz',
          'status': 'balance_due',
          'message': 'Outstanding balance of £3.45.',
        },
      }, 'ride_abc123');
      expect(b, isNotNull);
      expect(b!.isOwed, isTrue);
      expect(b.amount, 3.45);
      expect(b.hasPaymentUrl, isTrue);
    });

    test('fromBalanceEnvelope paid status has zero amount', () {
      final b = OutstandingBalance.fromBalanceEnvelope({
        'success': true,
        'data': {'status': 'succeeded', 'message': 'Balance already paid.'},
      }, 'ride_abc123');
      expect(b, isNotNull);
      expect(b!.isPaid, isTrue);
      expect(b.amount, 0);
    });

    test('fromForbiddenEnvelope parses 403 block', () {
      final b = OutstandingBalance.fromForbiddenEnvelope({
        'success': false,
        'message': 'You have an outstanding balance.',
        'data': {'outstandingBalance': 3.45, 'rideId': 'ride_prev123'},
      });
      expect(b, isNotNull);
      expect(b!.rideId, 'ride_prev123');
      expect(b.amount, 3.45);
      expect(b.isOwed, isTrue);
    });

    test('fromForbiddenEnvelope null without rideId', () {
      expect(
        OutstandingBalance.fromForbiddenEnvelope({
          'success': false,
          'data': {'outstandingBalance': 3.45},
        }),
        isNull,
      );
    });

    test('fromBalanceDueEvent parses socket payload', () {
      final b = OutstandingBalance.fromBalanceDueEvent({
        'rideId': 'ride_abc123',
        'excessAmount': 3.45,
        'isReminder': true,
        'message': 'Pay now to unlock ride booking.',
      });
      expect(b.rideId, 'ride_abc123');
      expect(b.amount, 3.45);
      expect(b.isReminder, isTrue);
    });

    test('global check data null means clear (no parse)', () {
      expect(
        OutstandingBalance.fromBalanceEnvelope(
          {'success': true, 'data': null},
          '',
        ),
        isNull,
      );
    });

    test('global check data object parses without fallback rideId', () {      final b = OutstandingBalance.fromBalanceEnvelope({
        'success': true,
        'data': {
          'rideId': '6aaa658998260742ce06a2a8',
          'excessAmount': 1.20,
          'clientSecret': 'pi_xxx_secret_yyy',
          'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_123',
          'status': 'balance_due',
          'message': 'You have an outstanding balance of £1.20.',
        },
      }, '');
      expect(b, isNotNull);
      expect(b!.rideId, '6aaa658998260742ce06a2a8');
      expect(b.isOwed, isTrue);
      expect(b.hasPaymentUrl, isTrue);
    });

    test('fromBalanceDueEvent carries link paymentUrl (backend v2)', () {
      final b = OutstandingBalance.fromBalanceDueEvent({
        'rideId': '6aaa658998260742ce06a2a8',
        'excessAmount': 1.20,
        'clientSecret': 'pi_3UGFfwQtj7jwWbc005X1TeOk_secret_qjDTamnkSaI09B7JjUxYQEpE6',
        'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_123',
        'isReminder': false,
        'message': 'You have an outstanding balance of £1.20 for wait time.',
      });
      expect(b.amount, 1.20);
      expect(b.isReminder, isFalse);
      expect(b.hasPaymentUrl, isTrue);
      expect(
        b.paymentUrl,
        'https://checkout.stripe.com/c/pay/cs_test_123',
      );
    });

    test('list envelope uses first entry', () {
      final b = OutstandingBalance.fromBalanceEnvelope({
        'success': true,
        'data': [
          {'rideId': 'r1', 'excessAmount': 0.90, 'status': 'balance_due'},
        ],
      }, '');
      expect(b, isNotNull);
      expect(b!.rideId, 'r1');
      expect(b.amount, 0.90);
      expect(b.isOwed, isTrue);
    });
  });
}
