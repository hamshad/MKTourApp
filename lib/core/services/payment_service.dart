import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../constants/api_constants.dart';
import 'stripe_service.dart';

/// Payment timing options for ride booking
enum PaymentTiming {
  /// Payment is authorized but not captured until ride completes
  payLater,

  /// Payment is captured immediately when booking
  payNow,
}

/// Result of a payment operation
class PaymentResult {
  final bool success;
  final String? rideId;
  final String? message;
  final String? error;
  final Map<String, dynamic>? data;

  PaymentResult({
    required this.success,
    this.rideId,
    this.message,
    this.error,
    this.data,
  });

  factory PaymentResult.success({
    required String rideId,
    required String message,
    Map<String, dynamic>? data,
  }) {
    return PaymentResult(
      success: true,
      rideId: rideId,
      message: message,
      data: data,
    );
  }

  factory PaymentResult.failure({required String error}) {
    return PaymentResult(success: false, error: error);
  }
}

/// Service for handling payments with Stripe
class PaymentService {
  /// Book a ride with Stripe payment
  ///
  /// This method:
  /// 1. Creates a ride on the backend and gets a payment intent
  /// 2. Presents the Stripe payment sheet
  /// 3. Returns the result of the booking
  static Future<PaymentResult> bookRideWithPayment({
    required BuildContext context,
    required Map<String, dynamic> pickupLocation,
    required Map<String, dynamic> dropoffLocation,
    required String vehicleType,
    required double distance,
    required double fare,
    PaymentTiming paymentTiming = PaymentTiming.payLater,
    String? notes,
  }) async {
    try {
      debugPrint('💳 PaymentService: Starting payment flow');
      debugPrint(
        '💳 PaymentService: Vehicle: $vehicleType, Distance: $distance, Fare: $fare',
      );
      debugPrint('💳 PaymentService: Payment timing: ${paymentTiming.name}');

      // Step 1: Create ride and get payment intent from backend
      final headers = await ApiConfig.getAuthHeaders();

      final requestBody = {
        'pickupLocation': pickupLocation,
        'dropoffLocation': dropoffLocation,
        'vehicleType': vehicleType,
        'distance': distance,
        'fare': fare,
        'paymentTiming': paymentTiming == PaymentTiming.payNow
            ? 'pay_now'
            : 'pay_later',
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      };

      debugPrint('💳 PaymentService: Creating ride with payment intent...');
      debugPrint('💳 PaymentService: Request: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse(ApiConstants.createRideWithPayment),
        headers: headers,
        body: jsonEncode(requestBody),
      );

      debugPrint('💳 PaymentService: Response status: ${response.statusCode}');
      debugPrint('💳 PaymentService: Response body: ${response.body}');

      if (response.statusCode != 201 && response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to create ride');
      }

      final responseData = jsonDecode(response.body);
      final rideData = responseData['data'];

      final String clientSecret = rideData['clientSecret'];
      final String rideId = rideData['_id'] ?? rideData['id'];

      debugPrint('💳 PaymentService: Ride created: $rideId');
      debugPrint(
        '💳 PaymentService: Got client secret, initializing payment sheet...',
      );

      // Step 2: Initialize Payment Sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'MK Tours',
          style: ThemeMode.system,
          appearance: PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(
              primary: Theme.of(context).primaryColor,
            ),
            shapes: const PaymentSheetShape(borderRadius: 12),
          ),
          // Enable Apple Pay and Google Pay
          applePay: const PaymentSheetApplePay(merchantCountryCode: 'GB'),
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'GB',
            testEnv: true, // Set to false in production
          ),
        ),
      );

      debugPrint('💳 PaymentService: Payment sheet initialized, presenting...');

      // Step 3: Present Payment Sheet
      await Stripe.instance.presentPaymentSheet();

      debugPrint('✅ PaymentService: Payment successful!');

      // Step 4: Return success result
      final message = paymentTiming == PaymentTiming.payNow
          ? 'Payment successful! Your ride is confirmed.'
          : 'Payment authorized! You\'ll be charged after the ride completes.';

      return PaymentResult.success(
        rideId: rideId,
        message: message,
        data: rideData,
      );
    } on StripeException catch (e) {
      debugPrint('⚠️ PaymentService: Stripe error - ${e.error.message}');
      return PaymentResult.failure(error: StripeService.getErrorMessage(e));
    } catch (e) {
      debugPrint('❌ PaymentService: Error - $e');
      return PaymentResult.failure(
        error: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  /// Cancel a ride and process refund
  ///
  /// The backend handles the refund logic:
  /// - Full refund if cancelled within grace period
  /// - Partial refund if cancelled after grace period (before ride starts)
  /// - No refund after ride starts
  static Future<PaymentResult> cancelRideWithRefund(String rideId) async {
    try {
      debugPrint('💳 PaymentService: Cancelling ride: $rideId');

      final headers = await ApiConfig.getAuthHeaders();

      final response = await http.post(
        Uri.parse(ApiConstants.cancelRideByUser(rideId)),
        headers: headers,
      );

      debugPrint(
        '💳 PaymentService: Cancel response status: ${response.statusCode}',
      );
      debugPrint('💳 PaymentService: Cancel response body: ${response.body}');

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to cancel ride');
      }

      final responseData = jsonDecode(response.body);
      final data = responseData['data'];

      final cancellationFee = data['cancellationFee'] ?? 0;
      final paymentStatus = data['paymentStatus'] ?? '';

      String message;
      if (paymentStatus == 'refunded') {
        message = 'Ride cancelled. Full refund processed.';
      } else if (paymentStatus == 'partially_refunded') {
        message =
            'Ride cancelled. Partial refund processed (£$cancellationFee cancellation fee).';
      } else if (paymentStatus == 'cancelled') {
        message = 'Ride cancelled. Payment authorization released.';
      } else {
        message = 'Ride cancelled successfully.';
      }

      return PaymentResult.success(
        rideId: rideId,
        message: message,
        data: data,
      );
    } catch (e) {
      debugPrint('❌ PaymentService: Cancel error - $e');
      return PaymentResult.failure(
        error: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  /// Get payment history for the current user
  static Future<List<Map<String, dynamic>>> getPaymentHistory({
    int limit = 10,
    String? status,
  }) async {
    try {
      debugPrint('💳 PaymentService: Fetching payment history');

      final headers = await ApiConfig.getAuthHeaders();

      final queryParams = <String, String>{
        'limit': limit.toString(),
        if (status != null) 'status': status,
      };

      final uri = Uri.parse(
        ApiConstants.paymentHistory,
      ).replace(queryParameters: queryParams);

      final response = await http.get(uri, headers: headers);

      debugPrint(
        '💳 PaymentService: History response status: ${response.statusCode}',
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get payment history');
      }

      final responseData = jsonDecode(response.body);
      final payments = responseData['data'] as List<dynamic>? ?? [];

      return payments.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ PaymentService: History error - $e');
      return [];
    }
  }

  /// Get details of a specific payment
  static Future<Map<String, dynamic>?> getPaymentDetails(
    String paymentId,
  ) async {
    try {
      debugPrint('💳 PaymentService: Fetching payment details: $paymentId');

      final headers = await ApiConfig.getAuthHeaders();

      final response = await http.get(
        Uri.parse(ApiConstants.paymentDetails(paymentId)),
        headers: headers,
      );

      debugPrint(
        '💳 PaymentService: Details response status: ${response.statusCode}',
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get payment details');
      }

      final responseData = jsonDecode(response.body);
      return responseData['data'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('❌ PaymentService: Details error - $e');
      return null;
    }
  }
}
