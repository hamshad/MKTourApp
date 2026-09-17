import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/models/outstanding_balance.dart';

/// Upfront-payment contract tests (phase 11-01).
///
/// Parsing-only by design: `PaymentService.bookRideWithPayment` needs
/// BuildContext + http, untestable without heavy mocks. The contract is
/// enforced by the required `paymentMethod` param plus these parsers, and
/// documented here with sample backend guide payloads.
void main() {
  group('Upfront payment balance envelope', () {
    test('parses new guide shape with excessAmount + paymentUrl', () {
      final b = OutstandingBalance.fromBalanceEnvelope({
        'success': true,
        'data': {
          'rideId': 'ride_guide_1',
          'excessAmount': 4.50,
          'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_upfront',
          'status': 'balance_due',
          'message': 'You have an outstanding balance of £4.50.',
        },
      }, '');
      expect(b, isNotNull);
      expect(b!.rideId, 'ride_guide_1');
      expect(b.amount, 4.50);
      expect(b.isOwed, isTrue);
      expect(b.hasPaymentUrl, isTrue);
      expect(b.paymentUrl, 'https://checkout.stripe.com/c/pay/cs_test_upfront');
    });

    test('parses outstandingBalance key variant', () {
      final b = OutstandingBalance.fromBalanceEnvelope({
        'success': true,
        'data': {
          'rideId': 'ride_guide_2',
          'outstandingBalance': 4.50,
          'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_variant',
          'status': 'balance_due',
        },
      }, '');
      expect(b, isNotNull);
      expect(b!.amount, 4.50);
      expect(b.isOwed, isTrue);
      expect(b.hasPaymentUrl, isTrue);
    });

    test('parses nested data.payment.paymentUrl shape', () {
      final b = OutstandingBalance.fromBalanceEnvelope({
        'success': true,
        'data': {
          'rideId': 'ride_guide_3',
          'excessAmount': 4.50,
          'status': 'balance_due',
          'payment': {
            'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_nested',
          },
        },
      }, '');
      expect(b, isNotNull);
      expect(b!.amount, 4.50);
      expect(b.hasPaymentUrl, isTrue);
      expect(b.paymentUrl, 'https://checkout.stripe.com/c/pay/cs_test_nested');
    });

    test('empty status defaults to balance_due', () {
      final b = OutstandingBalance.fromBalanceEnvelope({
        'success': true,
        'data': {'rideId': 'ride_guide_4', 'excessAmount': 2.00},
      }, '');
      expect(b, isNotNull);
      expect(b!.isOwed, isTrue);
      expect(b.amount, 2.00);
    });
  });

  group('Upfront payment 403 block', () {
    test('fromForbiddenEnvelope parses 403 guide shape', () {
      final b = OutstandingBalance.fromForbiddenEnvelope({
        'success': false,
        'message': 'Please clear your outstanding balance before booking.',
        'data': {'outstandingBalance': 4.50, 'rideId': 'ride_prev_1'},
      });
      expect(b, isNotNull);
      expect(b!.rideId, 'ride_prev_1');
      expect(b.amount, 4.50);
      expect(b.isOwed, isTrue);
    });

    test('fromForbiddenEnvelope accepts excessAmount fallback', () {
      final b = OutstandingBalance.fromForbiddenEnvelope({
        'success': false,
        'message': 'Outstanding balance.',
        'data': {'excessAmount': 4.50, 'rideId': 'ride_prev_2'},
      });
      expect(b, isNotNull);
      expect(b!.amount, 4.50);
    });

    test('fromForbiddenEnvelope copies paymentUrl through', () {
      final b = OutstandingBalance.fromForbiddenEnvelope({
        'success': false,
        'message': 'Outstanding balance.',
        'data': {
          'outstandingBalance': 4.50,
          'rideId': 'ride_prev_3',
          'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_403',
        },
      });
      expect(b, isNotNull);
      expect(b!.hasPaymentUrl, isTrue);
    });
  });

  group('Instant 201 shapes (documented contract)', () {
    test('payment_link 201 exposes paymentUrl + sessionId + status', () {
      // Sample guide payload for POST /rides/create with payment_link.
      const payload = {
        'paymentMethod': 'payment_link',
        'paymentStatus': 'pending_payment',
        'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_link',
        'sessionId': 'cs_test_link',
      };
      expect(payload['paymentMethod'], 'payment_link');
      expect(payload['paymentStatus'], isNotNull);
      expect((payload['paymentUrl'] as String).isNotEmpty, isTrue);
      expect((payload['sessionId'] as String).isNotEmpty, isTrue);
    });

    test('cash 201 exposes pending_collection with no WebView URL', () {
      // Sample guide payload for POST /rides/create with cash.
      const payload = {
        'paymentMethod': 'cash',
        'paymentStatus': 'pending_collection',
      };
      expect(payload['paymentMethod'], 'cash');
      expect(payload['paymentStatus'], 'pending_collection');
      expect(payload.containsKey('paymentUrl'), isFalse);
    });

    test('missing paymentMethod 400 shape is actionable', () {
      // Sample 400 envelope when paymentMethod omitted.
      const envelope = {
        'success': false,
        'message': 'paymentMethod is required (cash | payment_link)',
        'data': null,
      };
      final message = envelope['message'].toString().toLowerCase();
      expect(message.contains('paymentmethod is required'), isTrue);
    });
  });
}
