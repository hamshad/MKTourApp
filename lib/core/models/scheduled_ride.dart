import 'vehicle.dart';

/// Simple location model used in scheduled ride payloads.
///
/// Tolerant of both `{coordinates, address}` and `{type, coordinates, address}`
/// shapes from the backend.
class AddressLocation {
  final List<double>? coordinates; // [longitude, latitude]
  final String address;

  const AddressLocation({
    this.coordinates,
    this.address = '',
  });

  factory AddressLocation.fromJson(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return AddressLocation(
        coordinates: _parseCoordinates(raw['coordinates']),
        address: (raw['address'] ?? '').toString(),
      );
    }
    if (raw is Map) {
      return AddressLocation(
        coordinates: _parseCoordinates(raw['coordinates']),
        address: (raw['address'] ?? '').toString(),
      );
    }
    return const AddressLocation();
  }

  static List<double>? _parseCoordinates(dynamic value) {
    if (value is! List || value.length < 2) return null;
    final lng = _asDouble(value[0]);
    final lat = _asDouble(value[1]);
    if (lng == null || lat == null) return null;
    return [lng, lat];
  }

  static double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() => {
        if (coordinates != null) 'coordinates': coordinates,
        'address': address,
      };
}

/// Payment metadata returned by the schedule-ride create response.
///
/// [fromMap] tolerates missing fields — caller never needs null-checks.
class ScheduledPayment {
  final String? paymentMethod;
  final String? clientSecret;
  final String? paymentUrl;
  final String? status;

  const ScheduledPayment({
    this.paymentMethod,
    this.clientSecret,
    this.paymentUrl,
    this.status,
  });

  factory ScheduledPayment.fromMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return ScheduledPayment(
        paymentMethod: raw['paymentMethod']?.toString(),
        clientSecret: raw['clientSecret']?.toString(),
        paymentUrl: raw['paymentUrl']?.toString(),
        status: raw['status']?.toString(),
      );
    }
    if (raw is Map) {
      return ScheduledPayment(
        paymentMethod: raw['paymentMethod']?.toString(),
        clientSecret: raw['clientSecret']?.toString(),
        paymentUrl: raw['paymentUrl']?.toString(),
        status: raw['status']?.toString(),
      );
    }
    return const ScheduledPayment();
  }

  Map<String, dynamic> toJson() => {
        if (paymentMethod != null) 'paymentMethod': paymentMethod,
        if (clientSecret != null) 'clientSecret': clientSecret,
        if (paymentUrl != null) 'paymentUrl': paymentUrl,
        if (status != null) 'status': status,
      };
}

/// Scheduled ride model — parses both `data` and `data.ride` response shapes.
///
/// Fields fall back to sensible defaults so `fromJson` never throws on partial
/// payloads. Used by the scheduled-rides list, pool, and driver-scheduled
/// endpoints.
class ScheduledRide {
  final String id;
  final AddressLocation pickupLocation;
  final AddressLocation dropoffLocation;
  final List<RideStop> stops;
  final String vehicleCategorySlug;
  final double fare;
  final String status;
  final bool isScheduled;
  final String? scheduledPickupTime;
  final dynamic driver; // null or map
  final dynamic user; // null or map
  final double depositAmount;
  final double distance;
  final ScheduledPayment payment;

  const ScheduledRide({
    this.id = '',
    this.pickupLocation = const AddressLocation(),
    this.dropoffLocation = const AddressLocation(),
    this.stops = const [],
    this.vehicleCategorySlug = '',
    this.fare = 0.0,
    this.status = '',
    this.isScheduled = false,
    this.scheduledPickupTime,
    this.driver,
    this.user,
    this.depositAmount = 0.0,
    this.distance = 0.0,
    this.payment = const ScheduledPayment(),
  });

  /// Tolerant factory — handles `data` as a flat ride map or `data.ride`
  /// nested shape, plus the list shape (`data: [...]`) for scheduled-list
  /// endpoints.
  factory ScheduledRide.fromJson(dynamic raw) {
    Map<String, dynamic>? ride;

    if (raw is Map<String, dynamic>) {
      // Single ride object — could be nested under "ride" key.
      ride = raw['ride'] is Map<String, dynamic>
          ? raw['ride'] as Map<String, dynamic>
          : raw;
    } else if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      ride = map['ride'] is Map<String, dynamic>
          ? map['ride'] as Map<String, dynamic>
          : map;
    }

    if (ride == null) return const ScheduledRide();

    return ScheduledRide(
      id: (ride['_id'] ?? ride['id'] ?? '').toString(),
      pickupLocation: AddressLocation.fromJson(ride['pickupLocation']),
      dropoffLocation: AddressLocation.fromJson(ride['dropoffLocation']),
      stops: parseRideStops(ride['stops']),
      vehicleCategorySlug: (ride['vehicleCategorySlug'] ?? '').toString(),
      fare: _asDouble(ride['fare']),
      status: (ride['status'] ?? '').toString(),
      isScheduled: ride['isScheduled'] == true,
      scheduledPickupTime: ride['scheduledPickupTime']?.toString(),
      driver: ride['driver'],
      user: ride['user'],
      depositAmount: _asDouble(ride['depositAmount']),
      distance: _asDouble(ride['distance']),
      payment: ScheduledPayment.fromMap(ride['payment']),
    );
  }

  /// Parse a list of scheduled rides from any list endpoint response.
  static List<ScheduledRide> listFromResponse(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => ScheduledRide.fromJson(e)).toList();
    }
    if (raw is Map<String, dynamic>) {
      final data = raw['data'];
      if (data is List) {
        return data.map((e) => ScheduledRide.fromJson(e)).toList();
      }
      // Single ride wrapped in {data: {ride: ...}}.
      return [ScheduledRide.fromJson(raw)];
    }
    return [];
  }

  static double _asDouble(dynamic value, [double fallback = 0.0]) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'pickupLocation': pickupLocation.toJson(),
        'dropoffLocation': dropoffLocation.toJson(),
        'stops': stops.map((s) => s.toJson()).toList(),
        'vehicleCategorySlug': vehicleCategorySlug,
        'fare': fare,
        'status': status,
        'isScheduled': isScheduled,
        if (scheduledPickupTime != null)
          'scheduledPickupTime': scheduledPickupTime,
        if (driver != null) 'driver': driver,
        if (user != null) 'user': user,
        'depositAmount': depositAmount,
        'distance': distance,
        'payment': payment.toJson(),
      };

  bool get isAccepted => status == 'accepted';
  bool get isScheduledOnly => isScheduled && status == 'scheduled';
}
