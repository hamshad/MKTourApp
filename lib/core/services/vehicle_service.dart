import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../config/api_config.dart';
import '../models/vehicle.dart';

/// Service for fetching vehicle categories from the backend API
/// Handles caching and fallback to default categories
class VehicleService {
  static final VehicleService _instance = VehicleService._internal();
  factory VehicleService() => _instance;
  VehicleService._internal();

  /// Cached categories list
  List<VehicleCategory>? _cachedCategories;
  DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 30);

  /// Default categories to use when API is unavailable
  static const List<Map<String, dynamic>> _defaultCategoriesJson = [
    {
      'id': 'cat_sedan',
      'slug': 'car_4_seater',
      'name': 'Car 4 Seater',
      'seatingCapacity': 4,
      'luggage': {'suitcases': 2, 'smallCases': 2},
      'icon': 'car_sedan_icon',
      'active': true,
    },
    {
      'id': 'cat_suv',
      'slug': 'suv_6_seater',
      'name': 'SUV 6 Seater',
      'seatingCapacity': 6,
      'luggage': {'suitcases': 4, 'smallCases': 2},
      'icon': 'car_suv_icon',
      'active': true,
    },
    {
      'id': 'cat_van',
      'slug': 'mpv_8_seater',
      'name': 'MPV 8 Seater',
      'seatingCapacity': 8,
      'luggage': {'suitcases': 6, 'smallCases': 4},
      'icon': 'car_van_icon',
      'active': true,
    },
  ];

  /// Get default categories as VehicleCategory objects
  List<VehicleCategory> get defaultCategories =>
      _defaultCategoriesJson.map((json) => VehicleCategory.fromJson(json)).toList();

  /// Fetch active vehicle categories from the backend API
  Future<List<VehicleCategory>> getVehicleCategories({bool forceRefresh = false}) async {
    // Return cached categories if available and not expired
    if (!forceRefresh &&
        _cachedCategories != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      debugPrint('🚗 [VehicleService] Returning cached categories');
      return _cachedCategories!;
    }

    debugPrint('🚗 [VehicleService] Fetching categories from API...');
    debugPrint('🚗 [VehicleService] URL: ${ApiConstants.getActiveCategories()}');

    try {
      final headers = await ApiConfig.getAuthHeaders();

      final response = await http.get(
        Uri.parse(ApiConstants.getActiveCategories()),
        headers: headers,
      );

      debugPrint('🚗 [VehicleService] Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        debugPrint('🚗 [VehicleService] Response Body: ${response.body}');

        if (responseData['success'] == true && responseData['data'] != null) {
          final List<dynamic> categoriesJson = responseData['data'];
          final categories = categoriesJson
              .map((json) => VehicleCategory.fromJson(json))
              .toList();

          // Cache the result
          _cachedCategories = categories;
          _cacheTime = DateTime.now();

          debugPrint(
            '✅ [VehicleService] Successfully fetched ${categories.length} categories',
          );
          return categories;
        }
      }

      // API call failed or returned error - use fallback
      debugPrint(
        '⚠️ [VehicleService] API returned error, using default categories',
      );
      return defaultCategories;
    } catch (e) {
      debugPrint('❌ [VehicleService] Error fetching categories: $e');
      debugPrint('⚠️ [VehicleService] Using default categories as fallback');
      return defaultCategories;
    }
  }

  /// Get a specific category by slug
  Future<VehicleCategory?> getCategoryBySlug(String slug) async {
    final categories = await getVehicleCategories();
    try {
      return categories.firstWhere((v) => v.slug == slug);
    } catch (e) {
      debugPrint('⚠️ [VehicleService] Category slug $slug not found');
      return null;
    }
  }

  /// Clear the cache
  void clearCache() {
    _cachedCategories = null;
    _cacheTime = null;
    debugPrint('🗑️ [VehicleService] Cache cleared');
  }

  /// Convert Category list to legacy Map format for backwards compatibility
  List<Map<String, dynamic>> categoriesToLegacyFormat(List<VehicleCategory> categories) {
    return categories
        .map(
          (v) => {
            'id': v.slug,
            'type': v.slug,
            'slug': v.slug,
            'name': v.name,
            'description': v.description ?? 'Comfortable ride for up to ${v.seatingCapacity} people',
            'seats': v.seatingCapacity,
            'capacity': v.seatingCapacity,
            'luggage': v.luggage.toJson(),
            'icon': v.icon ?? 'car_sedan_icon',
            'image': _getVehicleImage(v.slug),
          },
        )
        .toList();
  }

  /// Get vehicle image path based on slug (fallback mapping)
  String _getVehicleImage(String slug) {
    if (slug.contains('suv')) return 'assets/car_suv.png';
    if (slug.contains('van')) return 'assets/car_van.png';
    if (slug.contains('hatchback')) return 'assets/car_hatchback.png';
    return 'assets/car_sedan.png';
  }

  /// Legacy methods upkeep
  Future<List<Vehicle>> getActiveVehicles({bool forceRefresh = false}) async {
      final categories = await getVehicleCategories(forceRefresh: forceRefresh);
      return categories.map((c) => Vehicle(
          categorySlug: c.slug,
          name: c.name,
          capacity: c.seatingCapacity,
          icon: c.icon ?? 'car_sedan_icon',
          baseFare: 0, // Not available directly in category response
          perMileRate: 0,
      )).toList();
  }
}

