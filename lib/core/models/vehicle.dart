
/// Luggage capacity model
class Luggage {
  final int suitcases;
  final int smallCases;

  const Luggage({
    required this.suitcases,
    required this.smallCases,
  });

  factory Luggage.fromJson(Map<String, dynamic> json) {
    return Luggage(
      suitcases: json['suitcases'] ?? 0,
      smallCases: json['smallCases'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'suitcases': suitcases,
      'smallCases': smallCases,
    };
  }
}

/// Dynamic Vehicle Category model from the backend
class VehicleCategory {
  final String id;
  final String name;
  final String slug;
  final int seatingCapacity;
  final Luggage luggage;
  final String? icon;
  final String? description;
  final bool active;

  const VehicleCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.seatingCapacity,
    required this.luggage,
    this.icon,
    this.description,
    this.active = true,
  });

  factory VehicleCategory.fromJson(Map<String, dynamic> json) {
    return VehicleCategory(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? 'Unknown',
      slug: json['slug'] ?? '',
      seatingCapacity: json['seatingCapacity'] ?? 4,
      luggage: Luggage.fromJson(json['luggage'] ?? {}),
      icon: json['icon'],
      description: json['description'],
      active: json['active'] ?? true,
    );
  }

  /// Format slug like 'car_4_seater' into 'Car - 4 Seater'
  static String formatSlug(String? slug) {
    if (slug == null || slug.isEmpty) return 'Standard';

    final words = slug
        .split('_')
        .map((word) => word.isNotEmpty
            ? word[0].toUpperCase() + word.substring(1).toLowerCase()
            : '')
        .toList();

    if (words.length >= 2) {
      return "${words[0]} - ${words.sublist(1).join(' ')}";
    }

    return words.join(' ');
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'name': name,
      'slug': slug,
      'seatingCapacity': seatingCapacity,
      'luggage': luggage.toJson(),
      'icon': icon,
      'description': description,
      'active': active,
    };
  }
}

/// Vehicle model representing a vehicle type from the backend API
/// Matches the response from GET /api/v1/vehicles
class Vehicle {
  final String categorySlug; // Changed from VehicleType type
  final String name;
  final int capacity;
  final String icon;
  final double baseFare;
  final double perMileRate;

  const Vehicle({
    required this.categorySlug,
    required this.name,
    required this.capacity,
    required this.icon,
    required this.baseFare,
    required this.perMileRate,
  });

  /// Create Vehicle from JSON map (API response)
  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      categorySlug: json['categorySlug'] ?? 'sedan',
      name: json['name'] ?? 'Unknown',
      capacity: json['capacity'] ?? 4,
      icon: json['icon'] ?? 'car_sedan_icon',
      baseFare: (json['baseFare'] is int)
          ? (json['baseFare'] as int).toDouble()
          : (json['baseFare'] ?? 50.0),
      perMileRate: (json['perMileRate'] is int)
          ? (json['perMileRate'] as int).toDouble()
          : (json['perMileRate'] ?? 15.0),
    );
  }

  /// Convert Vehicle to JSON map
  Map<String, dynamic> toJson() {
    return {
      'categorySlug': categorySlug,
      'name': name,
      'capacity': capacity,
      'icon': icon,
      'baseFare': baseFare,
      'perMileRate': perMileRate,
    };
  }

  /// Calculate estimated fare for a given distance (in miles)
  /// Note: This is a rough estimate - actual fare comes from backend
  double estimateFare(double distanceMiles) {
    return baseFare + (perMileRate * distanceMiles);
  }

  /// Create a copy with optional overrides
  Vehicle copyWith({
    String? categorySlug,
    String? name,
    int? capacity,
    String? icon,
    double? baseFare,
    double? perMileRate,
  }) {
    return Vehicle(
      categorySlug: categorySlug ?? this.categorySlug,
      name: name ?? this.name,
      capacity: capacity ?? this.capacity,
      icon: icon ?? this.icon,
      baseFare: baseFare ?? this.baseFare,
      perMileRate: perMileRate ?? this.perMileRate,
    );
  }

  @override
  String toString() {
    return 'Vehicle(categorySlug: $categorySlug, name: $name, capacity: $capacity, baseFare: $baseFare, perMileRate: $perMileRate)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Vehicle && other.categorySlug == categorySlug;
  }

  @override
  int get hashCode => categorySlug.hashCode;
}

/// Fare estimate model from the backend API
/// Matches the response from GET /api/v1/maps/get-distance-time
class FareEstimate {
  final String distanceText;
  final String durationText;
  final double totalFare;
  final int distanceMeters;
  final int durationSeconds;
  final String currency;
  final String categorySlug; // Changed from VehicleType vehicleType

  const FareEstimate({
    required this.distanceText,
    required this.durationText,
    required this.totalFare,
    this.distanceMeters = 0,
    this.durationSeconds = 0,
    this.currency = 'GBP',
    this.categorySlug = 'car_4_seater',
  });

  /// Create FareEstimate from JSON map (API response)
  factory FareEstimate.fromJson(Map<String, dynamic> json) {
    return FareEstimate(
      distanceText: json['distance_text'] ?? '',
      durationText: json['duration_text'] ?? '',
      totalFare: (json['total_fare'] is int)
          ? (json['total_fare'] as int).toDouble()
          : (json['total_fare'] ?? 0.0),
      distanceMeters: json['distance_meters'] ?? 0,
      durationSeconds: json['duration_seconds'] ?? 0,
      currency: json['currency'] ?? 'GBP',
      categorySlug: json['vehicleCategorySlug'] ?? json['categorySlug'] ?? 'car_4_seater',
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'distance_text': distanceText,
      'duration_text': durationText,
      'total_fare': totalFare,
      'distance_meters': distanceMeters,
      'duration_seconds': durationSeconds,
      'currency': currency,
      'categorySlug': categorySlug,
    };
  }

  /// Get distance in miles
  double get distanceMiles => distanceMeters * 0.000621371;

  /// Get duration in minutes
  int get durationMinutes => (durationSeconds / 60).round();

  @override
  String toString() {
    return 'FareEstimate(distance: $distanceText, duration: $durationText, fare: $totalFare $currency)';
  }
}

/// Ride request model for creating a new ride
/// Matches the request body for POST /api/v1/rides
class RideRequest {
  final Map<String, dynamic> pickupLocation;
  final Map<String, dynamic> dropoffLocation;
  final String vehicleCategorySlug; // Changed from VehicleType vehicleType
  final double distance;
  final String paymentTiming;
  final String? pickupPlaceId; // Google Places ID for airport detection
  final String? dropoffPlaceId; // Google Places ID for airport detection

  const RideRequest({
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.vehicleCategorySlug,
    required this.distance,
    this.paymentTiming = 'pay_later',
    this.pickupPlaceId,
    this.dropoffPlaceId,
  });

  /// Create RideRequest from components
  factory RideRequest.create({
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    required double dropoffLat,
    required double dropoffLng,
    required String dropoffAddress,
    required String categorySlug, // Changed from VehicleType vehicleType
    required double distanceMiles,
    String paymentTiming = 'pay_later',
  }) {
    return RideRequest(
      pickupLocation: {
        'coordinates': [pickupLng, pickupLat], // [longitude, latitude]
        'address': pickupAddress,
      },
      dropoffLocation: {
        'coordinates': [dropoffLng, dropoffLat], // [longitude, latitude]
        'address': dropoffAddress,
      },
      vehicleCategorySlug: categorySlug,
      distance: distanceMiles,
      paymentTiming: paymentTiming,
    );
  }

  /// Convert to JSON map for API request
  Map<String, dynamic> toJson() {
    return {
      'pickupLocation': pickupLocation,
      'dropoffLocation': dropoffLocation,
      'vehicleCategorySlug': vehicleCategorySlug, // Updated field name
      'distance': distance,
      'paymentTiming': paymentTiming,
      if (pickupPlaceId != null) 'pickupPlaceId': pickupPlaceId,
      if (dropoffPlaceId != null) 'dropoffPlaceId': dropoffPlaceId,
    };
  }
}

/// End ride early request model
/// Matches the request body for PATCH /api/v1/rides/{rideId}/end-early
class EndRideEarlyRequest {
  final double driverLat;
  final double driverLon;
  final String earlyEndReason;

  const EndRideEarlyRequest({
    required this.driverLat,
    required this.driverLon,
    required this.earlyEndReason,
  });

  /// Valid reasons for ending a ride early
  static const List<String> validReasons = [
    'user_requested',
    'rider_misbehavior',
    'safety_concern',
    'wrong_destination',
    'vehicle_issue',
  ];

  /// Convert to JSON map for API request
  Map<String, dynamic> toJson() {
    return {
      'driverLat': driverLat,
      'driverLon': driverLon,
      'earlyEndReason': earlyEndReason,
    };
  }
}

/// End ride early response model
/// Matches the response from PATCH /api/v1/rides/{rideId}/end-early
class EndRideEarlyResponse {
  final String status;
  final double actualDistance;
  final double fare;
  final String paymentStatus;

  const EndRideEarlyResponse({
    required this.status,
    required this.actualDistance,
    required this.fare,
    required this.paymentStatus,
  });

  /// Create from JSON map (API response)
  factory EndRideEarlyResponse.fromJson(Map<String, dynamic> json) {
    return EndRideEarlyResponse(
      status: json['status'] ?? 'early_completed',
      actualDistance: (json['actualDistance'] is int)
          ? (json['actualDistance'] as int).toDouble()
          : (json['actualDistance'] ?? 0.0),
      fare: (json['fare'] is int)
          ? (json['fare'] as int).toDouble()
          : (json['fare'] ?? 0.0),
      paymentStatus: json['paymentStatus'] ?? 'pending',
    );
  }

  @override
  String toString() {
    return 'EndRideEarlyResponse(status: $status, actualDistance: $actualDistance, fare: $fare, paymentStatus: $paymentStatus)';
  }
}
