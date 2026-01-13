import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../config/api_config.dart';
import '../models/vehicle.dart';
import '../enums/vehicle_type.dart';

/// Service for fetching vehicle types from the backend API
/// Handles caching and fallback to default vehicles
class VehicleService {
  static final VehicleService _instance = VehicleService._internal();
  factory VehicleService() => _instance;
  VehicleService._internal();

  /// Cached vehicles list
  List<Vehicle>? _cachedVehicles;
  DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 30);

  /// Default vehicles to use when API is unavailable
  static const List<Map<String, dynamic>> _defaultVehiclesJson = [
    {
      'type': 'sedan',
      'name': 'Economy Sedan',
      'capacity': 4,
      'icon': 'car_sedan_icon',
      'baseFare': 50.0,
      'perMileRate': 15.0,
    },
    {
      'type': 'suv',
      'name': 'MK Luxury SUV',
      'capacity': 6,
      'icon': 'car_suv_icon',
      'baseFare': 100.0,
      'perMileRate': 25.0,
    },
    {
      'type': 'hatchback',
      'name': 'Compact Hatchback',
      'capacity': 4,
      'icon': 'car_hatchback_icon',
      'baseFare': 40.0,
      'perMileRate': 12.0,
    },
    {
      'type': 'van',
      'name': 'Premium Van',
      'capacity': 8,
      'icon': 'car_van_icon',
      'baseFare': 120.0,
      'perMileRate': 30.0,
    },
  ];

  /// Get default vehicles as Vehicle objects
  List<Vehicle> get defaultVehicles =>
      _defaultVehiclesJson.map((json) => Vehicle.fromJson(json)).toList();

  /// Fetch active vehicles from the backend API
  /// Returns cached vehicles if available and not expired
  Future<List<Vehicle>> getActiveVehicles({bool forceRefresh = false}) async {
    // Return cached vehicles if available and not expired
    if (!forceRefresh &&
        _cachedVehicles != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      debugPrint('🚗 [VehicleService] Returning cached vehicles');
      return _cachedVehicles!;
    }

    debugPrint('🚗 [VehicleService] Fetching vehicles from API...');
    debugPrint('🚗 [VehicleService] URL: ${ApiConstants.getActiveVehicles()}');

    try {
      final headers = await ApiConfig.getAuthHeaders();

      final response = await http.get(
        Uri.parse(ApiConstants.getActiveVehicles()),
        headers: headers,
      );

      debugPrint(
        '🚗 [VehicleService] Response Status: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        debugPrint('🚗 [VehicleService] Response Body: ${response.body}');

        if (responseData['success'] == true && responseData['data'] != null) {
          final List<dynamic> vehiclesJson = responseData['data'];
          final vehicles =
              vehiclesJson.map((json) => Vehicle.fromJson(json)).toList();

          // Cache the result
          _cachedVehicles = vehicles;
          _cacheTime = DateTime.now();

          debugPrint(
            '✅ [VehicleService] Successfully fetched ${vehicles.length} vehicles',
          );
          return vehicles;
        }
      }

      // API call failed or returned error - use fallback
      debugPrint(
        '⚠️ [VehicleService] API returned error, using default vehicles',
      );
      return defaultVehicles;
    } catch (e) {
      debugPrint('❌ [VehicleService] Error fetching vehicles: $e');
      debugPrint('⚠️ [VehicleService] Using default vehicles as fallback');
      return defaultVehicles;
    }
  }

  /// Get a specific vehicle by type
  Future<Vehicle?> getVehicleByType(VehicleType type) async {
    final vehicles = await getActiveVehicles();
    try {
      return vehicles.firstWhere((v) => v.type == type);
    } catch (e) {
      debugPrint('⚠️ [VehicleService] Vehicle type ${type.apiValue} not found');
      return null;
    }
  }

  /// Clear the vehicles cache
  void clearCache() {
    _cachedVehicles = null;
    _cacheTime = null;
    debugPrint('🗑️ [VehicleService] Cache cleared');
  }

  /// Convert Vehicle list to legacy Map format for backwards compatibility
  /// with existing UI components that expect Map<String, dynamic>
  List<Map<String, dynamic>> vehiclesToLegacyFormat(List<Vehicle> vehicles) {
    return vehicles
        .map((v) => {
              'id': v.type.apiValue,
              'type': v.type.apiValue,
              'name': v.name,
              'description': _getVehicleDescription(v.type),
              'seats': v.capacity,
              'capacity': v.capacity,
              'basePrice': v.baseFare,
              'baseFare': v.baseFare,
              'pricePerMile': v.perMileRate,
              'perMileRate': v.perMileRate,
              'icon': v.icon,
              'image': _getVehicleImage(v.type),
            })
        .toList();
  }

  /// Get vehicle description based on type
  String _getVehicleDescription(VehicleType type) {
    switch (type) {
      case VehicleType.sedan:
        return 'Affordable, everyday rides';
      case VehicleType.suv:
        return 'Premium rides with more space';
      case VehicleType.hatchback:
        return 'Compact and economical';
      case VehicleType.van:
        return 'Perfect for groups and luggage';
    }
  }

  /// Get vehicle image path based on type
  String _getVehicleImage(VehicleType type) {
    switch (type) {
      case VehicleType.sedan:
        return 'assets/car_sedan.png';
      case VehicleType.suv:
        return 'assets/car_suv.png';
      case VehicleType.hatchback:
        return 'assets/car_hatchback.png';
      case VehicleType.van:
        return 'assets/car_van.png';
    }
  }
}
