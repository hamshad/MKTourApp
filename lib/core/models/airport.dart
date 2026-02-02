/// Airport model representing an airport with fixed pricing
class Airport {
  final String id;
  final String name;
  final String placeId;
  final String address;
  final AirportCoordinates coordinates;
  final Map<String, double> pricing;
  final bool isActive;

  const Airport({
    required this.id,
    required this.name,
    required this.placeId,
    required this.address,
    required this.coordinates,
    required this.pricing,
    this.isActive = true,
  });

  /// Create Airport from JSON map (API response)
  factory Airport.fromJson(Map<String, dynamic> json) {
    final coordsJson = json['coordinates'] as Map<String, dynamic>;
    final pricingJson = json['pricing'] as Map<String, dynamic>;

    return Airport(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      placeId: json['placeId'] ?? '',
      address: json['address'] ?? '',
      coordinates: AirportCoordinates.fromJson(coordsJson),
      pricing: (pricingJson).map(
        (key, value) => MapEntry(
          key,
          (value is int) ? value.toDouble() : (value as num).toDouble(),
        ),
      ),
      isActive: json['isActive'] ?? true,
    );
  }

  /// Get price for a specific vehicle category
  double? getPriceForCategory(String categorySlug) {
    return pricing[categorySlug];
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'name': name,
      'placeId': placeId,
      'address': address,
      'coordinates': coordinates.toJson(),
      'pricing': pricing,
      'isActive': isActive,
    };
  }

  @override
  String toString() {
    return 'Airport(name: $name, placeId: $placeId, address: $address)';
  }
}

/// Airport coordinates model
class AirportCoordinates {
  final double lat;
  final double lng;

  const AirportCoordinates({
    required this.lat,
    required this.lng,
  });

  factory AirportCoordinates.fromJson(Map<String, dynamic> json) {
    return AirportCoordinates(
      lat: (json['lat'] is int)
          ? (json['lat'] as int).toDouble()
          : (json['lat'] ?? 0.0),
      lng: (json['lng'] is int)
          ? (json['lng'] as int).toDouble()
          : (json['lng'] ?? 0.0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lng': lng,
    };
  }
}
