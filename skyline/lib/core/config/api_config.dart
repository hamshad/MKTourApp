import 'package:flutter_dotenv/flutter_dotenv.dart';

/// API configuration using environment variables for secure key management
/// 
/// Usage:
/// 1. Copy .env.example to .env
/// 2. Fill in your actual API keys
/// 3. The .env file is gitignored to prevent committing secrets
class ApiConfig {
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
    await dotenv.load(fileName: '.env');
  }
}
