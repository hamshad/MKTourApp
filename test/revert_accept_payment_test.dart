import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/features/ride/accept_payment_utils.dart';

/// Accept-time payment parsing (phase 16-02, revert spec §3 Step 2).
///
/// Pins the `ride:accepted` payload contract: `requiresPayment:true` +
/// `paymentUrl` → prompt; cash → cash copy; scheduled → silent; paid status
/// → silent even with a URL; minor-unit amount + currency formatting.
void main() {
  // Exact §3 Step 2 link-accept sample (trimmed to payment-relevant keys).
  Map<String, dynamic> linkAccepted() => {
        'rideId': '67401a2b3c4d5e6f7a8b9c01',
        'status': 'accepted',
        'isScheduled': false,
        'fare': 12.50,
        'paymentMethod': 'payment_link',
        'paymentStatus': 'link_created',
        'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_...',
        'amount': 1250,
        'currency': 'GBP',
        'requiresPayment': true,
      };

  group('requiresPayment:true link accept → show prompt', () {
    test('parses prompt fields from §3 Step 2 payload', () {
      final parsed = AcceptedPayment.parse(linkAccepted());
      expect(parsed.requiresPayment, isTrue);
      expect(parsed.paymentUrl, isNotNull);
      expect(parsed.showPrompt, isTrue);
      expect(parsed.showCashCopy, isFalse);
    });

    test('fare label uses minor-unit amount + currency', () {
      final parsed = AcceptedPayment.parse(linkAccepted());
      expect(parsed.fareLabel, '£12.50');
    });
  });

  group('cash accept → cash copy, zero prompt', () {
    test('paymentMethod:cash + requiresPayment:false', () {
      final parsed = AcceptedPayment.parse({
        ...linkAccepted(),
        'paymentMethod': 'cash',
        'paymentStatus': 'pending_collection',
        'paymentUrl': null,
        'requiresPayment': false,
      });
      expect(parsed.showPrompt, isFalse);
      expect(parsed.showCashCopy, isTrue);
    });
  });

  group('scheduled accept → silent', () {
    test('isScheduled:true + requiresPayment:false shows no prompt', () {
      final parsed = AcceptedPayment.parse({
        'rideId': 'ride_sched_1',
        'status': 'accepted',
        'isScheduled': true,
        'fare': 55.00,
        'requiresPayment': false,
      });
      expect(parsed.showPrompt, isFalse);
      expect(parsed.showCashCopy, isFalse);
    });
  });

  group('paid status → silent even with URL present', () {
    test('paymentStatus:authorized suppresses prompt', () {
      final parsed = AcceptedPayment.parse({
        ...linkAccepted(),
        'paymentStatus': 'authorized',
      });
      expect(parsed.showPrompt, isFalse);
      expect(isPaidPaymentStatus('authorized'), isTrue);
    });

    test('paymentStatus:succeeded suppresses prompt', () {
      final parsed = AcceptedPayment.parse({
        ...linkAccepted(),
        'paymentStatus': 'succeeded',
      });
      expect(parsed.showPrompt, isFalse);
      expect(isPaidPaymentStatus('SUCCEEDED'), isTrue);
    });

    test('link_created is not a paid status', () {
      expect(isPaidPaymentStatus('link_created'), isFalse);
      expect(isPaidPaymentStatus('pending'), isFalse);
      expect(isPaidPaymentStatus(null), isFalse);
    });
  });

  group('amount formatting', () {
    test('minor units 1250 + GBP → £12.50', () {
      expect(
        formatAcceptFare(amountMinor: 1250, fare: null, currency: 'GBP'),
        '£12.50',
      );
    });

    test('falls back to decimal fare when amount absent', () {
      expect(
        formatAcceptFare(amountMinor: null, fare: 12.5, currency: 'GBP'),
        '£12.50',
      );
    });

    test('unknown currency prefixes code', () {
      expect(
        formatAcceptFare(amountMinor: 1000, fare: null, currency: 'XYZ'),
        'XYZ 10.00',
      );
    });
  });

  group('shouldShowPayPrompt guards', () {
    test('scheduled never prompts even with requiresPayment:true', () {
      expect(
        shouldShowPayPrompt(
          requiresPayment: true,
          paymentMethod: 'payment_link',
          paymentStatus: 'link_created',
          isScheduled: true,
        ),
        isFalse,
      );
    });

    test('cash method never prompts', () {
      expect(
        shouldShowPayPrompt(
          requiresPayment: true,
          paymentMethod: 'cash',
          paymentStatus: 'pending',
          isScheduled: false,
        ),
        isFalse,
      );
    });
  });
}
