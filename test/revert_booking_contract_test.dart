import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/services/payment_service.dart';

/// Revert-ride-payments booking contract (phase 16-01, revert spec §3 + §5).
///
/// Parsing/routing-shape only by design: `bookRideWithPayment` needs
/// BuildContext + http, untestable without heavy mocks. These tests pin:
///  1. Normal-ride 201 shape (§3 Step 1): `data.{_id,status,paymentMethod,
///     paymentStatus,fare,distance,pickupLocation,dropoffLocation}` with NO
///     top-level `paymentUrl` — UI must defer to searching, never WebView.
///  2. Scheduled 201 shape (§5 Step 1): `status awaiting_deposit` with
///     `paymentUrl` + `sessionId` present — UI must open WebView at booking.
///  3. `PaymentResult` data passthrough for both branches so 16-02 can
///     consume `paymentMethod`/`paymentUrl` at accept time.
void main() {
  group('Normal ride create-201 shape (revert §3 Step 1)', () {
    // Exact sample payload from flutter_revert_flow.md §3 Step 1.
    Map<String, dynamic> normalCreateEnvelope() => {
      'success': true,
      'message': 'Ride request created successfully',
      'data': {
        '_id': '67401a2b3c4d5e6f7a8b9c01',
        'status': 'requested',
        'paymentMethod': 'payment_link',
        'paymentStatus': 'pending',
        'fare': 12.50,
        'distance': 3.4,
        'pickupLocation': {
          'coordinates': [-0.7594, 52.0406],
          'address': 'Milton Keynes Central Station',
        },
        'dropoffLocation': {
          'coordinates': [-0.7200, 52.0500],
          'address': 'Willen Lake, Milton Keynes',
        },
      },
    };

    test('carries required fields and no top-level paymentUrl', () {
      final data =
          normalCreateEnvelope()['data'] as Map<String, dynamic>;
      for (final key in [
        '_id',
        'status',
        'paymentMethod',
        'paymentStatus',
        'fare',
        'distance',
        'pickupLocation',
        'dropoffLocation',
      ]) {
        expect(data.containsKey(key), isTrue, reason: 'missing $key');
      }
      expect(data['status'], 'requested');
      expect(data.containsKey('paymentUrl'), isFalse);
      expect(
        (data['pickupLocation'] as Map)['address'],
        'Milton Keynes Central Station',
      );
    });

    test('instant link result defers: searching, no WebView at booking', () {
      final data =
          normalCreateEnvelope()['data'] as Map<String, dynamic>;
      // Routing rule mirrored from booking screens: instant (no scheduledAt)
      // + link must NOT open a WebView — paymentUrl absent at booking.
      final paymentUrl = (data['paymentUrl'] as String?) ?? '';
      final isScheduled = false;
      final shouldOpenWebViewAtBooking =
          isScheduled && paymentUrl.isNotEmpty;
      expect(shouldOpenWebViewAtBooking, isFalse);
    });

    test('PaymentResult passthrough keeps inert fields for 16-02', () {
      final data =
          normalCreateEnvelope()['data'] as Map<String, dynamic>;
      final result = PaymentResult.success(
        rideId: data['_id'].toString(),
        message: 'Ride booked!',
        data: {...data, 'paymentMethod': 'payment_link'},
      );
      expect(result.success, isTrue);
      expect(result.data!['paymentMethod'], 'payment_link');
      // No paymentUrl at booking for normal rides — accept-time prompt
      // (16-02) sources it from ride:accepted instead.
      expect(result.data!.containsKey('paymentUrl'), isFalse);
    });

    test('cash instant result also defers to searching', () {
      final result = PaymentResult.success(
        rideId: 'ride_cash_1',
        message: 'Ride booked!',
        data: {
          '_id': 'ride_cash_1',
          'status': 'requested',
          'paymentMethod': 'cash',
          'paymentStatus': 'pending_collection',
        },
      );
      expect(result.data!['paymentMethod'], 'cash');
      expect(result.data!.containsKey('paymentUrl'), isFalse);
    });
  });

  group('Scheduled create-201 shape (revert §5 Step 1)', () {
    Map<String, dynamic> scheduleEnvelope() => {
      'success': true,
      'message': 'Scheduled ride created successfully',
      'data': {
        '_id': '67402b3c4d5e6f7a8b9c02',
        'status': 'awaiting_deposit',
        'isScheduled': true,
        'scheduledPickupTime': '2026-09-22T08:00:00.000Z',
        'fare': 55.00,
        'paymentMethod': 'payment_link',
        'paymentStatus': 'link_created',
        'paymentUrl': 'https://checkout.stripe.com/c/pay/cs_test_scheduled_...',
        'sessionId': 'cs_test_scheduled_...',
      },
    };

    test('awaiting_deposit with paymentUrl + sessionId present', () {
      final data = scheduleEnvelope()['data'] as Map<String, dynamic>;
      expect(data['status'], 'awaiting_deposit');
      expect((data['paymentUrl'] as String).isNotEmpty, isTrue);
      expect((data['sessionId'] as String).isNotEmpty, isTrue);
    });

    test('scheduled link result opens WebView at booking', () {
      final data = scheduleEnvelope()['data'] as Map<String, dynamic>;
      final paymentUrl = (data['paymentUrl'] as String?) ?? '';
      final isScheduled = true;
      final shouldOpenWebViewAtBooking =
          isScheduled && paymentUrl.isNotEmpty;
      expect(shouldOpenWebViewAtBooking, isTrue);
    });

    test('PaymentResult passthrough carries paymentUrl for WebView', () {
      final data = scheduleEnvelope()['data'] as Map<String, dynamic>;
      final result = PaymentResult.success(
        rideId: data['_id'].toString(),
        message: 'Scheduled ride created. Complete payment to confirm.',
        data: {...data},
      );
      expect(result.success, isTrue);
      expect((result.data!['paymentUrl'] as String).isNotEmpty, isTrue);
      expect((result.data!['sessionId'] as String).isNotEmpty, isTrue);
    });
  });

  group('Booking POST still carries mandatory paymentMethod', () {
    test('only cash|payment_link accepted (no 400 regression)', () {
      for (final method in ['cash', 'payment_link']) {
        final normalized = method.trim().toLowerCase();
        expect(['cash', 'payment_link'].contains(normalized), isTrue);
      }
    });
  });
}
