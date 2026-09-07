import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// API configuration using environment variables for secure key management
///
/// Usage:
/// 1. Copy .env.example to .env
/// 2. Fill in your actual API keys
/// 3. The .env file is gitignored to prevent committing secrets
class ApiConfig {
  static const Uuid _uuid = Uuid();

  /// Current session token for Places API billing optimization
  static String? _currentSessionToken;

  /// Google Places API key for autocomplete and geocoding
  static String get placesApiKey {
    return dotenv.env['PLACES_API_KEY'] ?? '';
  }

  /// Google Maps API key for Android
  static String get mapsApiKeyAndroid {
    return dotenv.env['MAPS_API_KEY_ANDROID'] ?? '';
  }

  /// Google Maps API key for iOS
  static String get mapsApiKeyIOS {
    return dotenv.env['MAPS_API_KEY_IOS'] ?? '';
  }

  /// TikTok Events SDK - Android App ID (blank until added manually)
  static String get tiktokAndroidAppId {
    return dotenv.env['TIKTOK_ANDROID_APP_ID'] ?? '';
  }

  /// TikTok Events SDK - Android TikTok ID (blank until added manually)
  static String get tiktokAndroidTikTokId {
    return dotenv.env['TIKTOK_ANDROID_TIKTOK_ID'] ?? '';
  }

  /// TikTok Events SDK - iOS App ID (blank until added manually)
  static String get tiktokIosAppId {
    return dotenv.env['TIKTOK_IOS_APP_ID'] ?? '';
  }

  /// TikTok Events SDK - iOS TikTok ID (blank until added manually)
  static String get tiktokIosTikTokId {
    return dotenv.env['TIKTOK_IOS_TIKTOK_ID'] ?? '';
  }

  /// TikTok Events SDK - Access Token / App Secret (blank until added manually)
  static String get tiktokAccessToken {
    return dotenv.env['TIKTOK_ACCESS_TOKEN'] ?? '';
  }

  /// True when all TikTok Events SDK keys are configured
  static bool get isTikTokConfigured {
    return tiktokAndroidAppId.isNotEmpty &&
        tiktokAndroidTikTokId.isNotEmpty &&
        tiktokIosAppId.isNotEmpty &&
        tiktokIosTikTokId.isNotEmpty;
  }

  /// True when iOS TikTok keys are configured (Android may be blank)
  static bool get isTikTokIosConfigured {
    return tiktokIosAppId.isNotEmpty && tiktokIosTikTokId.isNotEmpty;
  }

  /// True when Android TikTok keys are configured (iOS may be blank)
  static bool get isTikTokAndroidConfigured {
    return tiktokAndroidAppId.isNotEmpty &&
        tiktokAndroidTikTokId.isNotEmpty;
  }

  /// Initialize environment variables
  /// Call this once in main() before runApp()
  static Future<void> initialize() async {
    debugPrint('🔧 ApiConfig: Initializing environment variables...');
    await dotenv.load(fileName: '.env');
    debugPrint('✅ ApiConfig: Environment loaded successfully');
  }

  /// Get the current user's JWT token from SharedPreferences
  static Future<String?> getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    debugPrint(
      '🔑 ApiConfig: Retrieved auth token: ${token != null ? '${token.substring(0, 10)}...' : 'null'}',
    );
    return token;
  }

  /// Get headers with Authorization for API requests
  static Future<Map<String, String>> getAuthHeaders() async {
    final token = await getAuthToken();
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    debugPrint(
      '📋 ApiConfig: Generated headers with ${token != null ? 'auth' : 'no auth'}',
    );
    return headers;
  }

  /// Generate a new session token for Places API billing cycle
  /// Call this when user opens the search bar
  static String generateSessionToken() {
    _currentSessionToken = _uuid.v4();
    debugPrint(
      '🎫 ApiConfig: Generated new session token: $_currentSessionToken',
    );
    return _currentSessionToken!;
  }

  /// Get the current session token (or generate one if none exists)
  static String get sessionToken {
    if (_currentSessionToken == null) {
      debugPrint(
        '🎫 ApiConfig: No session token exists, generating new one...',
      );
    }
    return _currentSessionToken ?? generateSessionToken();
  }

  /// Clear the session token after place selection is complete
  /// This closes the billing cycle
  static void clearSessionToken() {
    debugPrint('🧹 ApiConfig: Clearing session token (billing cycle closed)');
    _currentSessionToken = null;
  }
}
