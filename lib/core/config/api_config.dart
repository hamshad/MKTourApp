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
    debugPrint('🔑 ApiConfig: Retrieved auth token: ${token != null ? '${token.substring(0, 10)}...' : 'null'}');
    return token;
  }
  
  /// Get headers with Authorization for API requests
  static Future<Map<String, String>> getAuthHeaders() async {
    final token = await getAuthToken();
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    debugPrint('📋 ApiConfig: Generated headers with ${token != null ? 'auth' : 'no auth'}');
    return headers;
  }
  
  /// Generate a new session token for Places API billing cycle
  /// Call this when user opens the search bar
  static String generateSessionToken() {
    _currentSessionToken = _uuid.v4();
    debugPrint('🎫 ApiConfig: Generated new session token: $_currentSessionToken');
    return _currentSessionToken!;
  }
  
  /// Get the current session token (or generate one if none exists)
  static String get sessionToken {
    if (_currentSessionToken == null) {
      debugPrint('🎫 ApiConfig: No session token exists, generating new one...');
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
