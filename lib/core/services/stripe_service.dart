import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Service for handling Stripe initialization and configuration
class StripeService {
  static bool _isInitialized = false;

  /// Initialize Stripe with publishable key from environment
  /// Call this once in main() before runApp()
  static Future<void> init() async {
    if (_isInitialized) {
      debugPrint('💳 StripeService: Already initialized');
      return;
    }

    try {
      final publishableKey = dotenv.env['STRIPE_PUBLISHABLE_KEY'] ?? '';

      if (publishableKey.isEmpty ||
          publishableKey == 'pk_test_YOUR_PUBLISHABLE_KEY') {
        debugPrint('⚠️ StripeService: No valid Stripe publishable key found');
        debugPrint(
          '⚠️ StripeService: Please set STRIPE_PUBLISHABLE_KEY in .env file',
        );
        return;
      }

      Stripe.publishableKey = publishableKey;

      // Optional: Set merchant identifier for Apple Pay
      Stripe.merchantIdentifier = 'merchant.com.mktours';

      await Stripe.instance.applySettings();

      _isInitialized = true;
      debugPrint('✅ StripeService: Initialized successfully');
    } catch (e) {
      debugPrint('❌ StripeService: Failed to initialize - $e');
      rethrow;
    }
  }

  /// Check if Stripe is properly initialized
  static bool get isInitialized => _isInitialized;

  /// Get readable error message from Stripe exceptions
  static String getErrorMessage(dynamic error) {
    if (error is StripeException) {
      switch (error.error.code) {
        case FailureCode.Canceled:
          return 'Payment was cancelled';
        case FailureCode.Failed:
          return 'Payment failed. Please try again.';
        case FailureCode.Timeout:
          return 'Payment timed out. Please try again.';
        default:
          return error.error.message ?? 'Payment failed';
      }
    }
    return error?.toString() ?? 'An unexpected error occurred';
  }
}
