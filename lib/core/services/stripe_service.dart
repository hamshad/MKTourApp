import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io' show Platform;

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

  /// Confirm a PaymentIntent using a Google Pay token from native Android
  /// The tokenJsonStr is the raw Stripe token JSON returned by native Google Pay
  static Future<void> confirmWithToken(String clientSecret, String tokenJsonStr) async {
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('💳 [Stripe] ============ CONFIRM WITH GOOGLE PAY TOKEN ============');

    try {
      // Parse the Stripe token JSON from Google Pay
      final tokenObj = jsonDecode(tokenJsonStr);
      final tokenId = tokenObj['id'] as String;

      debugPrint('💳 [Stripe] Token ID: $tokenId');
      debugPrint('💳 [Stripe] Client Secret: ${clientSecret.substring(0, 20)}...');

      await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: clientSecret,
        data: PaymentMethodParams.cardFromToken(
          paymentMethodData: PaymentMethodDataCardFromToken(
            token: tokenId,
          ),
        ),
      );

      debugPrint('✅ [Stripe] Payment confirmed with Google Pay token!');
      debugPrint('═══════════════════════════════════════════════════════════');
    } catch (e) {
      debugPrint('❌ [Stripe] Token confirmation failed: $e');
      debugPrint('═══════════════════════════════════════════════════════════');
      rethrow;
    }
  }

  /// Process payment with provided client secret
  /// For Android: Shows Google Pay as primary option
  /// For iOS: Shows Apple Pay as primary option
  static Future<void> processPayment(
    String clientSecret, {
    bool forceCardOnly = false,
  }) async {
    try {
      final isAndroid = Platform.isAndroid;
      final isIOS = Platform.isIOS;

      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('💳 [Stripe] ============ PAYMENT INITIALIZATION ============');
      debugPrint('💳 [Stripe] Platform: ${isAndroid ? 'ANDROID' : isIOS ? 'IOS' : 'OTHER'}');
      debugPrint('💳 [Stripe] Client Secret: ${clientSecret.substring(0, 20)}...');
      
      // Check platform pay support
      final platformPaySupported = await Stripe.instance.isPlatformPaySupported();
      debugPrint('💳 [Stripe] Platform Pay Supported: $platformPaySupported');

      // For Android, we use Google Pay with special configuration
      if (isAndroid) {
        debugPrint('💳 [Stripe] 🤖 ANDROID DETECTED - Configuring Google Pay');
        debugPrint('💳 [Stripe] Setting up Google Pay with merchant country: GB');

        final paymentMethodOrder = forceCardOnly
          ? const ['card']
          : const ['google_pay', 'card'];

        final flag = (dotenv.env['GOOGLE_PAY_TEST_ENV'] ?? '').toLowerCase();
        final bool googlePayTestEnv = flag == 'true'
          ? true
          : flag == 'false'
            ? false
            : (Stripe.publishableKey).startsWith('pk_test_');

        final googlePayConfig = forceCardOnly
          ? null
          : PaymentSheetGooglePay(
            merchantCountryCode: 'GB',
            testEnv: googlePayTestEnv,
            currencyCode: 'GBP',
            );
        
        await Stripe.instance.initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            paymentIntentClientSecret: clientSecret,
            merchantDisplayName: 'MK Tours',
            style: ThemeMode.light,
            // Disable Link to show Google Pay
            allowsDelayedPaymentMethods: false,
            // Important: Google Pay must be first for Android
            paymentMethodOrder: paymentMethodOrder,
            appearance: PaymentSheetAppearance(
              colors: const PaymentSheetAppearanceColors(
                primary: Color(0xFF22C55E), // Green for consistency
              ),
              shapes: const PaymentSheetShape(borderRadius: 12),
            ),
            // Google Pay configuration for Android
            googlePay: googlePayConfig,
          ),
        );
        debugPrint(
          '💳 [Stripe] ✅ ${forceCardOnly ? 'Card-only' : 'Google Pay'} payment sheet initialized (Link disabled)',
        );
      } 
      // For iOS, use Apple Pay
      else if (isIOS) {
        debugPrint('💳 [Stripe] 🍎 IOS DETECTED - Configuring Apple Pay');
        
        await Stripe.instance.initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            paymentIntentClientSecret: clientSecret,
            merchantDisplayName: 'MK Tours',
            style: ThemeMode.light,
            paymentMethodOrder: const ['apple_pay', 'card'],
            appearance: PaymentSheetAppearance(
              colors: const PaymentSheetAppearanceColors(
                primary: Color(0xFF22C55E),
              ),
              shapes: const PaymentSheetShape(borderRadius: 12),
            ),
            applePay: const PaymentSheetApplePay(merchantCountryCode: 'GB'),
          ),
        );
        debugPrint('💳 [Stripe] ✅ Apple Pay payment sheet initialized');
      }
      // Fallback for other platforms
      else {
        debugPrint('💳 [Stripe] ⚠️  UNKNOWN PLATFORM - Using card only');
        
        await Stripe.instance.initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            paymentIntentClientSecret: clientSecret,
            merchantDisplayName: 'MK Tours',
            style: ThemeMode.light,
            paymentMethodOrder: const ['card'],
            appearance: PaymentSheetAppearance(
              colors: const PaymentSheetAppearanceColors(
                primary: Color(0xFF22C55E),
              ),
              shapes: const PaymentSheetShape(borderRadius: 12),
            ),
          ),
        );
      }

      debugPrint('💳 [Stripe] 📱 Opening payment sheet...');
      await Stripe.instance.presentPaymentSheet();
      
      debugPrint('✅ [Stripe] Payment successful!');
      debugPrint('═══════════════════════════════════════════════════════════');
    } catch (e) {
      debugPrint('❌ [Stripe] Payment failed: $e');
      debugPrint('═══════════════════════════════════════════════════════════');
      throw e;
    }
  }
}
