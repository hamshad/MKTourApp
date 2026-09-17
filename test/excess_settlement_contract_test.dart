import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/models/outstanding_balance.dart';

/// Stage 2 settlement contract tests (phase 12-01).
///
/// `POST /payments/balance/:rideId/select-method` envelopes are unverified
/// against the live backend (research open question 1), so the parser
/// tolerates every known shape and these tests pin them: flat `paymentUrl`,
/// nested `data.payment.paymentUrl`, each amount key, cash selection without
/// `paymentUrl`, and the list-envelope shape. Every case asserts amount +
/// paymentUrl-or-null.
void main() {
  group('fromSelectMethodEnvelope payment_link shapes', () {
    test('flat paymentUrl + excessAmount', () {
      final b = OutstandingBalance.fromSelectMethodEnvelope({
        'success': true,
        'data': {
          'rideId': 'ride_stage2_1',
          'excessAmount': 2.75,
          'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_stage2',
          'status': 'balance_due',
          'message': 'Pay £2.75 online.',
        },
      }, '');
      expect(b, isNotNull);
      expect(b!.rideId, 'ride_stage2_1');
      expect(b.amount, 2.75);
      expect(b.isOwed, isTrue);
      expect(b.paymentUrl, 'https://checkout.stripe.com/c/pay/cs_test_stage2');
      expect(b.hasPaymentUrl, isTrue);
    });

    test('nested data.payment.paymentUrl', () {
      final b = OutstandingBalance.fromSelectMethodEnvelope({
        'success': true,
        'data': {
          'rideId': 'ride_stage2_2',
          'excessAmount': 2.75,
          'status': 'balance_due',
          'payment': {
            'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_nested',
          },
        },
      }, '');
      expect(b, isNotNull);
      expect(b!.amount, 2.75);
      expect(b.paymentUrl, 'https://checkout.stripe.com/c/pay/cs_test_nested');
      expect(b.hasPaymentUrl, isTrue);
    });

    test('outstandingBalance amount key', () {
      final b = OutstandingBalance.fromSelectMethodEnvelope({
        'success': true,
        'data': {
          'rideId': 'ride_stage2_3',
          'outstandingBalance': 1.20,
          'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_ob',
          'status': 'balance_due',
        },
      }, '');
      expect(b, isNotNull);
      expect(b!.amount, 1.20);
      expect(b.hasPaymentUrl, isTrue);
    });

    test('amount key variant', () {
      final b = OutstandingBalance.fromSelectMethodEnvelope({
        'success': true,
        'data': {
          'rideId': 'ride_stage2_4',
          'amount': 4.00,
          'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_amt',
          'status': 'balance_due',
        },
      }, '');
      expect(b, isNotNull);
      expect(b!.amount, 4.00);
      expect(b.hasPaymentUrl, isTrue);
    });
  });

  group('fromSelectMethodEnvelope cash selection', () {
    test('cash envelope has amount but no paymentUrl', () {
      final b = OutstandingBalance.fromSelectMethodEnvelope({
        'success': true,
        'data': {
          'rideId': 'ride_stage2_cash',
          'excessAmount': 2.75,
          'status': 'balance_due',
          'message': 'Waiting for driver to confirm cash receipt...',
        },
      }, '');
      expect(b, isNotNull);
      expect(b!.amount, 2.75);
      expect(b.paymentUrl, isNull);
      expect(b.hasPaymentUrl, isFalse);
      expect(b.isOwed, isTrue);
    });

    test('succeeded status parses as paid with zero amount', () {
      final b = OutstandingBalance.fromSelectMethodEnvelope({
        'success': true,
        'data': {'rideId': 'ride_stage2_paid', 'status': 'succeeded'},
      }, 'ride_stage2_paid');
      expect(b, isNotNull);
      expect(b!.isPaid, isTrue);
      expect(b.amount, 0);
      expect(b.paymentUrl, isNull);
    });
  });

  group('fromSelectMethodEnvelope envelope tolerance', () {
    test('list envelope uses first entry', () {
      final b = OutstandingBalance.fromSelectMethodEnvelope({
        'success': true,
        'data': [
          {
            'rideId': 'r_stage2_1',
            'excessAmount': 0.90,
            'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_list',
            'status': 'balance_due',
          },
        ],
      }, '');
      expect(b, isNotNull);
      expect(b!.rideId, 'r_stage2_1');
      expect(b.amount, 0.90);
      expect(b.hasPaymentUrl, isTrue);
    });

    test('empty data returns null', () {
      expect(
        OutstandingBalance.fromSelectMethodEnvelope(
          {'success': false, 'data': null},
          '',
        ),
        isNull,
      );
    });

    test('fallback rideId used when envelope omits it', () {
      final b = OutstandingBalance.fromSelectMethodEnvelope({
        'success': true,
        'data': {'excessAmount': 3.10, 'status': 'balance_due'},
      }, 'ride_fallback_9');
      expect(b, isNotNull);
      expect(b!.rideId, 'ride_fallback_9');
      expect(b.amount, 3.10);
      expect(b.paymentUrl, isNull);
    });
  });
}
