/// Vehicle type enum matching backend API values
/// Used for ride requests and vehicle selection
enum VehicleType {
  sedan('sedan', 'Economy Sedan'),
  suv('suv', 'MK Luxury SUV'),
  hatchback('hatchback', 'Compact Hatchback'),
  van('van', 'Premium Van');

  final String apiValue;
  final String displayName;

  const VehicleType(this.apiValue, this.displayName);

  /// Get VehicleType from API string value
  static VehicleType fromString(String value) {
    return VehicleType.values.firstWhere(
      (type) => type.apiValue == value.toLowerCase(),
      orElse: () => VehicleType.sedan,
    );
  }

  /// Convert to JSON-compatible string
  String toJson() => apiValue;
}

/// Extension for additional vehicle type utilities
extension VehicleTypeExtension on VehicleType {
  /// Get icon data for the vehicle type
  String get iconName {
    switch (this) {
      case VehicleType.sedan:
        return 'car_sedan_icon';
      case VehicleType.suv:
        return 'car_suv_icon';
      case VehicleType.hatchback:
        return 'car_hatchback_icon';
      case VehicleType.van:
        return 'car_van_icon';
    }
  }

  /// Get default capacity for the vehicle type
  int get defaultCapacity {
    switch (this) {
      case VehicleType.sedan:
        return 4;
      case VehicleType.suv:
        return 6;
      case VehicleType.hatchback:
        return 4;
      case VehicleType.van:
        return 8;
    }
  }
}
