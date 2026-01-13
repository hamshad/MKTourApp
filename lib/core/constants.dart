import 'enums/vehicle_type.dart';

class AppConstants {
  // Use 10.0.2.2 for Android Emulator, localhost for iOS Simulator
  // For simplicity in this mockup, we might need to adjust based on platform or just use localhost if running on iOS Sim
  static const String apiBaseUrl = 'http://localhost:3000/api';

  /// Vehicle types matching backend API
  /// Keys use the exact backend 'type' values: sedan, suv, hatchback, van
  static const List<Map<String, dynamic>> vehicleTypes = [
    {
      'id': 'sedan',
      'type': 'sedan',
      'name': 'Economy Sedan',
      'description': 'Affordable, everyday rides',
      'seats': 4,
      'capacity': 4,
      'basePrice': 50.0,
      'baseFare': 50.0,
      'pricePerMile': 15.0,
      'perMileRate': 15.0,
      'icon': 'car_sedan_icon',
      'image': 'assets/car_sedan.png',
    },
    {
      'id': 'suv',
      'type': 'suv',
      'name': 'MK Luxury SUV',
      'description': 'Premium rides with more space',
      'seats': 6,
      'capacity': 6,
      'basePrice': 100.0,
      'baseFare': 100.0,
      'pricePerMile': 25.0,
      'perMileRate': 25.0,
      'icon': 'car_suv_icon',
      'image': 'assets/car_suv.png',
    },
    {
      'id': 'hatchback',
      'type': 'hatchback',
      'name': 'Compact Hatchback',
      'description': 'Compact and economical',
      'seats': 4,
      'capacity': 4,
      'basePrice': 40.0,
      'baseFare': 40.0,
      'pricePerMile': 12.0,
      'perMileRate': 12.0,
      'icon': 'car_hatchback_icon',
      'image': 'assets/car_hatchback.png',
    },
    {
      'id': 'van',
      'type': 'van',
      'name': 'Premium Van',
      'description': 'Perfect for groups and luggage',
      'seats': 8,
      'capacity': 8,
      'basePrice': 120.0,
      'baseFare': 120.0,
      'pricePerMile': 30.0,
      'perMileRate': 30.0,
      'icon': 'car_van_icon',
      'image': 'assets/car_van.png',
    },
  ];

  /// Get vehicle by type string
  static Map<String, dynamic>? getVehicleByType(String type) {
    try {
      return vehicleTypes.firstWhere(
        (v) => v['type'] == type.toLowerCase() || v['id'] == type.toLowerCase(),
      );
    } catch (e) {
      return vehicleTypes.first; // Return sedan as default
    }
  }

  /// Get VehicleType enum from type string
  static VehicleType getVehicleTypeEnum(String type) {
    return VehicleType.fromString(type);
  }
}

