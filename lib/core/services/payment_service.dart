import 'dart:convert';
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

  factory PaymentResult.failure({required String error, Map<String, dynamic>? data}) {
    return PaymentResult(success: false, error: error, data: data);
  }

  /// Structured failure for the 403 outstanding-balance block
  /// (payment-flow.md §1 Step 2, §7). Callers redirect to the balance
  /// screen using `data.rideId` instead of showing a generic error.
  factory PaymentResult.balanceBlocked({
    required String error,
    String? rideId,
    double? outstandingBalance,
  }) {
    return PaymentResult(
      success: false,
      error: error,
      data: {
        'balanceBlocked': true,
        if (rideId != null) 'rideId': rideId,
        if (outstandingBalance != null) 'outstandingBalance': outstandingBalance,
      },
    );
  }

  bool get isBalanceBlocked => data?['balanceBlocked'] == true;
}

/// Service for handling payments with Stripe
class PaymentService {
  static const String _merchantDisplayName = 'MK Tours';

  static Map<String, dynamic> _safeDecode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }

  static double? _numOrNull(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Fetch outstanding balance for a ride (payment-flow.md §1 Step 6, §3).
  /// Returns the raw envelope; `data.status == 'balance_due'` means owed.
  static Future<Map<String, dynamic>> fetchBalance(String rideId) async {
    try {
      final headers = await ApiConfig.getAuthHeaders();
      final response = await http.get(
        Uri.parse(ApiConstants.paymentBalance(rideId)),
        headers: headers,
      );
      debugPrint(
        '💰 PaymentService: fetchBalance $rideId → ${response.statusCode}',
      );
      final decoded = _safeDecode(response.body);
      if (decoded.isNotEmpty) return decoded;
      return {'success': false, 'message': 'Request failed: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  static Future<void> _presentPaymentSheet({
    required Color primaryColor,
    required String clientSecret,
  }) async {
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: _merchantDisplayName,
        style: ThemeMode.system,
        paymentMethodOrder: const ['apple_pay', 'card'],
        appearance: PaymentSheetAppearance(
          colors: PaymentSheetAppearanceColors(primary: primaryColor),
          shapes: const PaymentSheetShape(borderRadius: 12),
        ),
        applePay: const PaymentSheetApplePay(merchantCountryCode: 'GB'),
        googlePay: const PaymentSheetGooglePay(
          merchantCountryCode: 'GB',
          testEnv: false,
        ),
      ),
    );

    await Stripe.instance.presentPaymentSheet();
  }

  /// Present Stripe Payment Sheet for an existing PaymentIntent.
  ///
  /// Used by the pay_later flow when the ride completes.
  static Future<PaymentResult> payForCompletedRide({
    required BuildContext context,
    required String rideId,
    required String clientSecret,
  }) async {
    try {
      final primaryColor = Theme.of(context).primaryColor;
      debugPrint(
        '💳 PaymentService: Presenting payment sheet for ride: $rideId',
      );
      await _presentPaymentSheet(
        primaryColor: primaryColor,
        clientSecret: clientSecret,
      );
      return PaymentResult.success(
        rideId: rideId,
        message: 'Payment successful! Thank you.',
      );
    } on StripeException catch (e) {
      debugPrint(
        '⚠️ PaymentService: Stripe error (completion) - ${e.error.message}',
      );
      return PaymentResult.failure(error: StripeService.getErrorMessage(e));
    } catch (e) {
      debugPrint('❌ PaymentService: Error (completion) - $e');
      return PaymentResult.failure(
        error: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  /// Book a ride with upfront payment
  ///
  /// This method:
  /// 1. Creates a ride on the backend with mandatory paymentMethod (cash or payment_link)
  /// 2. For payment_link: returns paymentUrl for WebView (caller opens)
  /// 3. For cash: returns paymentStatus pending_collection
  /// 4. Handles 400 (missing paymentMethod) and 403 (outstanding balance) responses
  static Future<PaymentResult> bookRideWithPayment({
    required BuildContext context,
    required Map<String, dynamic> pickupLocation,
    required Map<String, dynamic> dropoffLocation,
    required String vehicleCategorySlug,
    required double distance,
    required double fare,
    // Kept for backward compatibility with callers; ignored for request body
    PaymentTiming paymentTiming = PaymentTiming.payLater,
    DateTime? scheduledAt,
    String? notes,
    List<Map<String, dynamic>>? stops,
    required String paymentMethod,
  }) async {
    // Normalize and validate paymentMethod
    final normalizedMethod = paymentMethod.trim().toLowerCase();
    if (normalizedMethod != 'cash' && normalizedMethod != 'payment_link') {
      throw ArgumentError(
        'paymentMethod must be "cash" or "payment_link", got: $paymentMethod',
      );
    }

    String? rideId;
    try {
      debugPrint('💳 PaymentService: Starting upfront payment flow');
      debugPrint(
        '💳 PaymentService: Category: $vehicleCategorySlug, Distance: $distance, Fare: $fare',
      );
      debugPrint('💳 PaymentService: paymentMethod: $normalizedMethod');

      // Step 1: Create ride and get payment intent from backend
      final headers = await ApiConfig.getAuthHeaders();

      // Determine if this is a scheduled (pre-booking) ride
      final bool isScheduled = scheduledAt != null;
      final String endpoint = isScheduled
          ? ApiConstants.scheduleRide
          : ApiConstants.createRideWithPayment;

      final requestBody = {
        'pickupLocation': pickupLocation,
        'dropoffLocation': dropoffLocation,
        'vehicleCategorySlug': vehicleCategorySlug,
        'distance': distance,
        'paymentMethod': normalizedMethod,
        if (isScheduled)
          'scheduledPickupTime': scheduledAt.toUtc().toIso8601String(),
        if (notes != null && notes.isNotEmpty)
          isScheduled ? 'preBookingNote' : 'notes': notes,
        if (stops != null && stops.isNotEmpty)
          'stops': stops
              .map(
                (stop) => {
                  'stopOrder': stop['stopOrder'],
                  'address': stop['address'],
                  'coordinates': stop['coordinates'],
                },
              )
              .toList(),
        // Include Google Places IDs for airport detection if available
        if (pickupLocation['placeId'] != null)
          'pickupPlaceId': pickupLocation['placeId'],
        if (dropoffLocation['placeId'] != null)
          'dropoffPlaceId': dropoffLocation['placeId'],
      };

      debugPrint(
        '💳 PaymentService: Creating ${isScheduled ? 'scheduled' : 'regular'} ride...',
      );
      debugPrint('💳 PaymentService: Request: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse(endpoint),
        headers: headers,
        body: jsonEncode(requestBody),
      );

      debugPrint('💳 PaymentService: Response status: ${response.statusCode}');
      debugPrint('💳 PaymentService: Response body: ${response.body}');

      if (response.statusCode != 201 && response.statusCode != 200) {
        final errorData = _safeDecode(response.body);
        final message = errorData['message']?.toString() ?? 'Failed to create ride';

        // Explicit 400: missing paymentMethod
        if (response.statusCode == 400 &&
            message.toLowerCase().contains('paymentmethod is required')) {
          debugPrint(
            '⛔ PaymentService: 400 missing paymentMethod',
          );
          return PaymentResult.failure(
            error: message,
            data: {'missingPaymentMethod': true, 'message': message},
          );
        }

        // Outstanding-balance block (payment-flow.md §7): detected by shape,
        // not just status code — backends vary (403 documented, but the
        // message test catches any status). Fields may sit under `data` or
        // top-level; both are tried so a shape drift can't strand the rider
        // on a dead-end snackbar.
        final dataObj = errorData['data'] is Map
            ? Map<String, dynamic>.from(errorData['data'] as Map)
            : <String, dynamic>{};
        final blockedRideId = dataObj['rideId']?.toString() ??
            errorData['rideId']?.toString();
        final blockedAmount = _numOrNull(dataObj['outstandingBalance']) ??
            _numOrNull(dataObj['excessAmount']) ??
            _numOrNull(dataObj['amount']) ??
            _numOrNull(errorData['outstandingBalance']) ??
            _numOrNull(errorData['excessAmount']);
        final lower = message.toLowerCase();
        final looksLikeBalance = lower.contains('outstanding balance') ||
            lower.contains('balance_due') ||
            lower.contains('balance due') ||
            (blockedRideId != null && blockedAmount != null);
        if (response.statusCode == 403 && (looksLikeBalance || blockedRideId != null)) {
          debugPrint(
            '⛔ PaymentService: balance block ride=$blockedRideId amount=$blockedAmount',
          );
          return PaymentResult.balanceBlocked(
            error: message,
            rideId: blockedRideId,
            outstandingBalance: blockedAmount,
          );
        }
        if (looksLikeBalance) {
          debugPrint(
            '⛔ PaymentService: balance-like failure on ${response.statusCode} ride=$blockedRideId amount=$blockedAmount',
          );
          return PaymentResult.balanceBlocked(
            error: message,
            rideId: blockedRideId,
            outstandingBalance: blockedAmount,
          );
        }
        throw Exception(message);
      }

      final responseData = jsonDecode(response.body);
      final rawData = responseData['data'] as Map<String, dynamic>? ?? <String, dynamic>{};

      // Parse response for both instant and scheduled rides
      // paymentUrl may live under data.payment, data.ride, or data itself
      final rideObj = rawData['ride'] is Map
          ? Map<String, dynamic>.from(rawData['ride'] as Map)
          : rawData;
      final paymentObj = rawData['payment'] is Map
          ? Map<String, dynamic>.from(rawData['payment'] as Map)
          : null;
      rideId = rideObj['_id']?.toString() ?? rideObj['id']?.toString() ?? rawData['_id']?.toString() ?? rawData['id']?.toString();
      final clientSecret = paymentObj?['clientSecret']?.toString() ??
          rideObj['clientSecret']?.toString() ??
          rawData['clientSecret']?.toString();
      final String? paymentUrl = paymentObj?['paymentUrl']?.toString() ??
          rideObj['paymentUrl']?.toString() ??
          rawData['paymentUrl']?.toString();
      final String? sessionId = paymentObj?['sessionId']?.toString() ??
          rideObj['sessionId']?.toString() ??
          rawData['sessionId']?.toString();
      final String? paymentStatus = paymentObj?['paymentStatus']?.toString() ??
          rideObj['paymentStatus']?.toString() ??
          rawData['paymentStatus']?.toString();

      debugPrint(
        '💳 PaymentService: ${isScheduled ? 'scheduled' : 'instant'} paymentMethod sent=$normalizedMethod, '
        'payObj=${paymentObj?.keys.toList()}, '
        'rideHasUrl=${rideObj['paymentUrl'] != null}, '
        'resolvedUrl=${paymentUrl != null ? 'present' : 'missing'}',
      );

      final rideData = {
        ...rideObj,
        ...rawData,
        if (clientSecret != null) 'clientSecret': clientSecret,
        if (paymentUrl != null) 'paymentUrl': paymentUrl,
        if (sessionId != null) 'sessionId': sessionId,
        if (paymentStatus != null) 'paymentStatus': paymentStatus,
        'paymentMethod': normalizedMethod,
        if (paymentObj != null) 'payment': paymentObj,
      };

      debugPrint('💳 PaymentService: Ride created: $rideId');

      // For both instant and scheduled rides with payment_link, caller opens WebView
      // For cash, paymentStatus will be pending_collection
      return PaymentResult.success(
        rideId: rideId!,
        message: isScheduled
            ? 'Scheduled ride created. Complete payment to confirm.'
            : 'Ride booked!',
        data: rideData,
      );
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
        message = 'Ride cancelled.';
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

  /// Get the user's scheduled rides
  static Future<List<Map<String, dynamic>>> getScheduledRides({
    String? status,
  }) async {
    try {
      debugPrint('📅 PaymentService: Fetching scheduled rides');
      final headers = await ApiConfig.getAuthHeaders();

      final queryParams = <String, String>{
        if (status != null) 'status': status,
      };

      final uri = Uri.parse(
        ApiConstants.scheduledRides,
      ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(uri, headers: headers);

      debugPrint(
        '📅 PaymentService: Scheduled rides response: ${response.body}',
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get scheduled rides');
      }

      final responseData = jsonDecode(response.body);
      final rides = responseData['data'] as List<dynamic>? ?? [];
      return rides.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ PaymentService: Scheduled rides error - $e');
      return [];
    }
  }

  /// Cancel a scheduled ride as user
  static Future<Map<String, dynamic>> cancelScheduledRideUser(
    String rideId, {
    String? reason,
  }) async {
    try {
      debugPrint(
        '📅 PaymentService: Cancelling scheduled ride (user): $rideId',
      );
      final headers = await ApiConfig.getAuthHeaders();

      final response = await http.post(
        Uri.parse(ApiConstants.cancelScheduledRideUser(rideId)),
        headers: {
          ...headers,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          if (reason != null) 'cancellationReason': reason,
        }),
      );

      debugPrint('📅 PaymentService: Cancel response: ${response.statusCode}');

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        throw Exception(
          errorData['message'] ?? 'Failed to cancel scheduled ride',
        );
      }

      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('❌ PaymentService: Cancel scheduled ride error - $e');
      rethrow;
    }
  }

  /// Cancel a scheduled ride as driver
  static Future<Map<String, dynamic>> cancelScheduledRideDriver(
    String rideId,
    String reason,
  ) async {
    try {
      debugPrint(
        '📅 PaymentService: Cancelling scheduled ride (driver): $rideId',
      );
      final headers = await ApiConfig.getAuthHeaders();

      final response = await http.post(
        Uri.parse(ApiConstants.cancelScheduledRideDriver(rideId)),
        headers: headers,
        body: jsonEncode({'reason': reason}),
      );

      debugPrint(
        '📅 PaymentService: Driver cancel response: ${response.statusCode}',
      );

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        throw Exception(
          errorData['message'] ?? 'Failed to cancel scheduled ride',
        );
      }

      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('❌ PaymentService: Driver cancel error - $e');
      rethrow;
    }
  }
}
