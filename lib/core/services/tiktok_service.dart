import 'package:flutter/foundation.dart';
import 'package:tiktok_events_sdk/tiktok_events_sdk.dart';

import '../config/api_config.dart';

/// Wrapper around `tiktok_events_sdk` for TikTok Events tracking.
///
/// Keys come from [ApiConfig] (.env). All values are blank by default —
/// fill them in manually later. [initialize] no-ops while keys are blank,
/// so the app runs fine before configuration.
class TikTokService {
  TikTokService._();

  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  /// Initialize the TikTok Events SDK. Safe to call with blank keys (skips).
  ///
  /// Only the current platform's keys are required — e.g. iOS initializes
  /// with just TIKTOK_IOS_APP_ID + TIKTOK_IOS_TIKTOK_ID, Android IDs may
  /// stay blank (and vice versa).
  static Future<void> initialize() async {
    if (_initialized) return;

    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final ready =
        isIos ? ApiConfig.isTikTokIosConfigured : ApiConfig.isTikTokAndroidConfigured;

    if (!ready) {
      debugPrint(
        '📊 TikTokService: ${isIos ? 'iOS' : 'Android'} keys blank, skipping init. '
        'Fill TIKTOK_* in .env to enable.',
      );
      return;
    }

    try {
      await TikTokEventsSdk.initSdk(
        androidAppId: ApiConfig.tiktokAndroidAppId,
        tikTokAndroidId: ApiConfig.tiktokAndroidTikTokId,
        iosAppId: ApiConfig.tiktokIosAppId,
        tiktokIosId: ApiConfig.tiktokIosTikTokId,
        isDebugMode: kDebugMode,
        logLevel:
            kDebugMode ? TikTokLogLevel.debug : TikTokLogLevel.none,
        androidOptions: const TikTokAndroidOptions(),
        iosOptions: const TikTokIosOptions(),
      );

      // Apply access token (app secret) if provided, without re-init.
      if (ApiConfig.tiktokAccessToken.isNotEmpty) {
        await TikTokEventsSdk.updateAccessToken(
          accessToken: ApiConfig.tiktokAccessToken,
        );
      }

      _initialized = true;
      debugPrint('📊 TikTokService: initialized');
    } catch (e) {
      debugPrint('📊 TikTokService: init failed: $e');
    }
  }

  /// Associate events with a user. No-op until [initialize] succeeds.
  static Future<void> identify({
    required String externalId,
    String? externalUserName,
    String? phoneNumber,
    String? email,
  }) async {
    if (!_initialized) return;
    try {
      await TikTokEventsSdk.identify(
        identifier: TikTokIdentifier(
          externalId: externalId,
          externalUserName: externalUserName,
          phoneNumber: phoneNumber,
          email: email,
        ),
      );
    } catch (e) {
      debugPrint('📊 TikTokService: identify failed: $e');
    }
  }

  /// Log a custom or predefined TikTok event. No-op until initialized.
  static Future<void> logEvent(
    String eventName, {
    String? eventId,
    EventProperties? properties,
  }) async {
    if (!_initialized) return;
    try {
      await TikTokEventsSdk.logEvent(
        event: TikTokEvent(
          eventName: eventName,
          eventId: eventId,
          properties: properties,
        ),
      );
    } catch (e) {
      debugPrint('📊 TikTokService: logEvent failed: $e');
    }
  }

  /// Clear user identification (call on logout). No-op until initialized.
  static Future<void> logout() async {
    if (!_initialized) return;
    try {
      await TikTokEventsSdk.logout();
    } catch (e) {
      debugPrint('📊 TikTokService: logout failed: $e');
    }
  }

  /// Toggle tracking at runtime (GDPR/CCPA opt-in/out). No-op until initialized.
  static Future<void> setTrackingEnabled({required bool enabled}) async {
    if (!_initialized) return;
    try {
      await TikTokEventsSdk.setTrackingEnabled(enabled: enabled);
    } catch (e) {
      debugPrint('📊 TikTokService: setTrackingEnabled failed: $e');
    }
  }

  /// Force-flush pending events. No-op until initialized.
  static Future<void> flush() async {
    if (!_initialized) return;
    try {
      await TikTokEventsSdk.flush();
    } catch (e) {
      debugPrint('📊 TikTokService: flush failed: $e');
    }
  }
}
