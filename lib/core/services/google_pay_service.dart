import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Native Android Google Pay service via platform channel
class GooglePayService {
  static const _channel = MethodChannel('com.mokshasolutions.mktours/googlepay');

  /// Check if Google Pay is available on this device
  static Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isGooglePayAvailable', {
        'testEnv': _isTestMode,
      });
      debugPrint('💳 [GooglePay] Available: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('❌ [GooglePay] Availability check failed: $e');
      return false;
    }
  }

  /// Request a Google Pay payment.
  ///
  /// Returns a map with:
  ///   `success: true, token: "..."` on success
  ///   `success: false, error: "..."` on failure
  static Future<Map<String, dynamic>> requestPayment({
    required double amount,
    String currencyCode = 'GBP',
    String merchantName = 'MK Tours',
  }) async {
    final stripeKey = dotenv.env['STRIPE_PUBLISHABLE_KEY'] ?? '';
    // Format amount as string with 2 decimal places
    final amountStr = amount.toStringAsFixed(2);

    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('💳 [GooglePay] ============ NATIVE PAY REQUEST ============');
    debugPrint('💳 [GooglePay] Amount: $amountStr $currencyCode');
    debugPrint('💳 [GooglePay] Merchant: $merchantName');
    debugPrint('💳 [GooglePay] Test mode: $_isTestMode');
    debugPrint('💳 [GooglePay] Stripe key present: ${stripeKey.isNotEmpty}');

    try {
      final result = await _channel.invokeMethod<Map>('requestPayment', {
        'amount': amountStr,
        'currencyCode': currencyCode,
        'merchantName': merchantName,
        'stripePublishableKey': stripeKey,
        'testEnv': _isTestMode,
      });

      if (result == null) {
        return {'success': false, 'error': 'No result from Google Pay'};
      }

      final map = Map<String, dynamic>.from(result);
      debugPrint('💳 [GooglePay] Result: success=${map['success']}');
      return map;
    } on PlatformException catch (e) {
      debugPrint('❌ [GooglePay] PlatformException: ${e.message}');
      return {'success': false, 'error': e.message ?? 'Platform error'};
    } catch (e) {
      debugPrint('❌ [GooglePay] Error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  static bool get _isTestMode {
    final flag = (dotenv.env['GOOGLE_PAY_TEST_ENV'] ?? '').toLowerCase();
    if (flag == 'true' || flag == 'false') {
      return flag == 'true';
    }

    final key = dotenv.env['STRIPE_PUBLISHABLE_KEY'] ?? '';
    return key.startsWith('pk_test_');
  }
}
