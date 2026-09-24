/// Typed parsers for the back-to-back (B2B) dispatch contract
/// (`driver-multirequest.md` §2-3).
///
/// Plan 20-01 is the transport foundation: driver (20-02) and rider (20-03)
/// UI plans build on these parsers, so every backend payload shape is pinned
/// here with never-throw `fromMap` factories in the `PromoStatus.fromMap`
/// tolerant style (plain maps, missing keys default, no throws).
library;

/// Ride location with an address and [longitude, latitude] coordinates.
///
/// Tolerates both the canonical `[lon, lat]` list and the nested
/// `{coordinates: [lon, lat]}` map shape.
class B2bLocation {
  /// Human-readable address.
  final String address;

  /// Longitude (first element of the coordinates pair).
  final double longitude;

  /// Latitude (second element of the coordinates pair).
  final double latitude;

  const B2bLocation({
    this.address = '',
    this.longitude = 0.0,
    this.latitude = 0.0,
  });

  /// Parses a location map. Never throws: missing/invalid input yields an
  /// empty location.
  factory B2bLocation.fromMap(dynamic raw) {
    if (raw is! Map) return const B2bLocation();
    final map = Map<String, dynamic>.from(raw);
    var coords = map['coordinates'];
    // Tolerate {coordinates: {coordinates: [...]}} nesting.
    if (coords is Map && coords['coordinates'] is List) {
      coords = coords['coordinates'];
    }
    var lon = 0.0;
    var lat = 0.0;
    if (coords is List && coords.length >= 2) {
      lon = (coords[0] as num?)?.toDouble() ?? 0.0;
      lat = (coords[1] as num?)?.toDouble() ?? 0.0;
    }
    return B2bLocation(
      address: map['address']?.toString() ?? '',
      longitude: lon,
      latitude: lat,
    );
  }
}

/// Minimal rider profile carried on B2B payloads.
class B2bRider {
  /// Rider id (`_id` or `id`).
  final String id;

  /// Rider display name.
  final String name;

  /// Rider phone (may be absent on `ride:newRequest`).
  final String phone;

  /// Rider avatar URL.
  final String profilePicture;

  const B2bRider({
    this.id = '',
    this.name = '',
    this.phone = '',
    this.profilePicture = '',
  });

  /// Parses a rider map. Never throws: missing/invalid input yields an
  /// empty rider.
  factory B2bRider.fromMap(dynamic raw) {
    if (raw is! Map) return const B2bRider();
    final map = Map<String, dynamic>.from(raw);
    return B2bRider(
      id: (map['_id'] ?? map['id'])?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      profilePicture: map['profilePicture']?.toString() ?? '',
    );
  }
}

/// Queued trip from the accept-response (§2.1A).
///
/// `POST /rides/:id/accept` while the driver is `in_progress` returns
/// `status: 'accepted'` with `isQueued: true` plus the `previousRide` id of
/// the still-active trip.
class QueuedRide {
  /// Ride id.
  final String id;

  /// Rider who booked the queued trip.
  final B2bRider user;

  /// Backend status (expected `'accepted'` while queued).
  final String status;

  /// True while the trip waits behind the active trip.
  final bool isQueued;

  /// Id of the still-active trip this ride is queued behind.
  final String previousRide;

  /// Queued pickup point.
  final B2bLocation pickupLocation;

  /// Queued dropoff point.
  final B2bLocation dropoffLocation;

  /// Intermediate stops (defaults to empty).
  final List<Map<String, dynamic>> stops;

  /// Vehicle category slug (e.g. `saloon`).
  final String vehicleCategorySlug;

  /// Quoted fare.
  final double fare;

  /// Trip distance.
  final double distance;

  /// Payment method (`stripe`, `cash`, …).
  final String paymentMethod;

  /// Payment status (`authorized`, …).
  final String paymentStatus;

  /// ISO timestamp of acceptance.
  final String acceptedAt;

  const QueuedRide({
    this.id = '',
    this.user = const B2bRider(),
    this.status = '',
    this.isQueued = false,
    this.previousRide = '',
    this.pickupLocation = const B2bLocation(),
    this.dropoffLocation = const B2bLocation(),
    this.stops = const [],
    this.vehicleCategorySlug = '',
    this.fare = 0.0,
    this.distance = 0.0,
    this.paymentMethod = '',
    this.paymentStatus = '',
    this.acceptedAt = '',
  });

  /// Parses the `data` map of the §2.1A accept-response envelope.
  /// Never throws: missing optional keys default.
  factory QueuedRide.fromMap(Map<String, dynamic> data) {
    return QueuedRide(
      id: (data['_id'] ?? data['id'] ?? data['rideId'])?.toString() ?? '',
      user: B2bRider.fromMap(data['user']),
      status: data['status']?.toString() ?? '',
      isQueued: data['isQueued'] == true,
      previousRide: data['previousRide']?.toString() ?? '',
      pickupLocation: B2bLocation.fromMap(data['pickupLocation']),
      dropoffLocation: B2bLocation.fromMap(data['dropoffLocation']),
      stops: _stringMapList(data['stops']),
      vehicleCategorySlug: data['vehicleCategorySlug']?.toString() ?? '',
      fare: (data['fare'] as num?)?.toDouble() ?? 0.0,
      distance: (data['distance'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: data['paymentMethod']?.toString() ?? '',
      paymentStatus: data['paymentStatus']?.toString() ?? '',
      acceptedAt: data['acceptedAt']?.toString() ?? '',
    );
  }
}

/// Next-trip activation from `ride:nextTripActivated` (§3.1).
///
/// Emitted when the driver completes trip A: trip B becomes active and the
/// driver app navigates to its pickup.
class NextTripActivation {
  /// Promoted ride id.
  final String rideId;

  /// Next pickup point.
  final B2bLocation pickupLocation;

  /// Next dropoff point.
  final B2bLocation dropoffLocation;

  /// Quoted fare.
  final double fare;

  /// Trip distance.
  final double distance;

  /// Intermediate stops (defaults to empty).
  final List<Map<String, dynamic>> stops;

  /// Vehicle category slug.
  final String vehicleCategorySlug;

  /// Rider profile.
  final B2bRider user;

  /// Backend message (e.g. "Your next ride is ready! …").
  final String message;

  const NextTripActivation({
    this.rideId = '',
    this.pickupLocation = const B2bLocation(),
    this.dropoffLocation = const B2bLocation(),
    this.fare = 0.0,
    this.distance = 0.0,
    this.stops = const [],
    this.vehicleCategorySlug = '',
    this.user = const B2bRider(),
    this.message = '',
  });

  /// Parses the `ride:nextTripActivated` payload. Never throws.
  factory NextTripActivation.fromMap(Map<String, dynamic> data) {
    return NextTripActivation(
      rideId: (data['rideId'] ?? data['_id'] ?? data['id'])?.toString() ?? '',
      pickupLocation: B2bLocation.fromMap(data['pickupLocation']),
      dropoffLocation: B2bLocation.fromMap(data['dropoffLocation']),
      fare: (data['fare'] as num?)?.toDouble() ?? 0.0,
      distance: (data['distance'] as num?)?.toDouble() ?? 0.0,
      stops: _stringMapList(data['stops']),
      vehicleCategorySlug: data['vehicleCategorySlug']?.toString() ?? '',
      user: B2bRider.fromMap(data['user']),
      message: data['message']?.toString() ?? '',
    );
  }
}

/// Incoming B2B request from `ride:newRequest` (§3.1).
///
/// Dispatched when a new ride matches the driver's dropoff vicinity;
/// `isBackToBack: true` marks it as queueable behind the active trip.
class B2bRequest {
  /// Requested ride id.
  final String rideId;

  /// Requested pickup point.
  final B2bLocation pickupLocation;

  /// Requested dropoff point.
  final B2bLocation dropoffLocation;

  /// Intermediate stops (defaults to empty).
  final List<Map<String, dynamic>> stops;

  /// Quoted fare.
  final double fare;

  /// Trip distance.
  final double distance;

  /// Vehicle category slug.
  final String vehicleCategorySlug;

  /// Congestion-charge flag.
  final bool isCongestionCharge;

  /// Congestion-charge amount.
  final double congestionChargeAmount;

  /// True when queueable behind the active trip.
  final bool isBackToBack;

  /// Backend message (e.g. "New ride near your current dropoff").
  final String message;

  /// Requesting rider (name only on this event).
  final B2bRider user;

  const B2bRequest({
    this.rideId = '',
    this.pickupLocation = const B2bLocation(),
    this.dropoffLocation = const B2bLocation(),
    this.stops = const [],
    this.fare = 0.0,
    this.distance = 0.0,
    this.vehicleCategorySlug = '',
    this.isCongestionCharge = false,
    this.congestionChargeAmount = 0.0,
    this.isBackToBack = false,
    this.message = '',
    this.user = const B2bRider(),
  });

  /// Parses the `ride:newRequest` payload. Never throws.
  factory B2bRequest.fromMap(Map<String, dynamic> data) {
    return B2bRequest(
      rideId: (data['rideId'] ?? data['_id'] ?? data['id'])?.toString() ?? '',
      pickupLocation: B2bLocation.fromMap(data['pickupLocation']),
      dropoffLocation: B2bLocation.fromMap(data['dropoffLocation']),
      stops: _stringMapList(data['stops']),
      fare: (data['fare'] as num?)?.toDouble() ?? 0.0,
      distance: (data['distance'] as num?)?.toDouble() ?? 0.0,
      vehicleCategorySlug: data['vehicleCategorySlug']?.toString() ?? '',
      isCongestionCharge: data['isCongestionCharge'] == true,
      congestionChargeAmount:
          (data['congestionChargeAmount'] as num?)?.toDouble() ?? 0.0,
      isBackToBack: data['isBackToBack'] == true,
      message: data['message']?.toString() ?? '',
      user: B2bRider.fromMap(data['user']),
    );
  }
}

/// Promotion flags from the complete-response (§2.1C).
///
/// `POST /rides/:id/complete` on trip A returns these when trip B is
/// promoted in the database.
class CompletePromotion {
  /// Completed ride id.
  final String id;

  /// Backend status (expected `'completed'`).
  final String status;

  /// Final fare.
  final double fare;

  /// Authoritative charged fare.
  final double actualFare;

  /// True when a queued ride was promoted by this completion.
  final bool hasQueuedRidePromoted;

  /// Promoted ride id (empty when nothing was queued).
  final String nextRideId;

  const CompletePromotion({
    this.id = '',
    this.status = '',
    this.fare = 0.0,
    this.actualFare = 0.0,
    this.hasQueuedRidePromoted = false,
    this.nextRideId = '',
  });

  /// Parses the `data` map of the §2.1C complete-response envelope.
  /// Never throws.
  factory CompletePromotion.fromMap(Map<String, dynamic> data) {
    return CompletePromotion(
      id: (data['_id'] ?? data['id'] ?? data['rideId'])?.toString() ?? '',
      status: data['status']?.toString() ?? '',
      fare: (data['fare'] as num?)?.toDouble() ?? 0.0,
      actualFare: (data['actualFare'] as num?)?.toDouble() ?? 0.0,
      hasQueuedRidePromoted: data['hasQueuedRidePromoted'] == true,
      nextRideId: data['nextRideId']?.toString() ?? '',
    );
  }
}

/// Driver vehicle details from `ride:accepted` (§3.2).
class AcceptedDriverVehicle {
  /// Vehicle category slug.
  final String categorySlug;

  /// Vehicle model description.
  final String model;

  /// Registration plate.
  final String number;

  /// Vehicle colour.
  final String color;

  const AcceptedDriverVehicle({
    this.categorySlug = '',
    this.model = '',
    this.number = '',
    this.color = '',
  });

  /// Parses the nested `vehicle` map. Never throws.
  factory AcceptedDriverVehicle.fromMap(dynamic raw) {
    if (raw is! Map) return const AcceptedDriverVehicle();
    final map = Map<String, dynamic>.from(raw);
    return AcceptedDriverVehicle(
      categorySlug: map['categorySlug']?.toString() ?? '',
      model: map['model']?.toString() ?? '',
      number: map['number']?.toString() ?? '',
      color: map['color']?.toString() ?? '',
    );
  }
}

/// Driver profile from `ride:accepted` (§3.2).
class AcceptedDriver {
  /// Driver id.
  final String id;

  /// Driver display name.
  final String name;

  /// Driver phone.
  final String phone;

  /// Driver avatar URL.
  final String profilePicture;

  /// Driver rating.
  final double rating;

  /// Lifetime completed rides.
  final int totalRides;

  /// Assigned vehicle.
  final AcceptedDriverVehicle vehicle;

  /// Driver longitude (from `location.coordinates`).
  final double longitude;

  /// Driver latitude (from `location.coordinates`).
  final double latitude;

  const AcceptedDriver({
    this.id = '',
    this.name = '',
    this.phone = '',
    this.profilePicture = '',
    this.rating = 0.0,
    this.totalRides = 0,
    this.vehicle = const AcceptedDriverVehicle(),
    this.longitude = 0.0,
    this.latitude = 0.0,
  });

  /// Parses the nested `driver` map. Never throws.
  factory AcceptedDriver.fromMap(dynamic raw) {
    if (raw is! Map) return const AcceptedDriver();
    final map = Map<String, dynamic>.from(raw);
    var lon = 0.0;
    var lat = 0.0;
    final location = map['location'];
    if (location is Map) {
      final coords = location['coordinates'];
      if (coords is List && coords.length >= 2) {
        lon = (coords[0] as num?)?.toDouble() ?? 0.0;
        lat = (coords[1] as num?)?.toDouble() ?? 0.0;
      }
    }
    return AcceptedDriver(
      id: (map['id'] ?? map['_id'])?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      profilePicture: map['profilePicture']?.toString() ?? '',
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      totalRides: (map['totalRides'] as num?)?.toInt() ?? 0,
      vehicle: AcceptedDriverVehicle.fromMap(map['vehicle']),
      longitude: lon,
      latitude: lat,
    );
  }
}

/// Rider-side acceptance from `ride:accepted` (§3.2).
///
/// Lives here (not in UI files) so the rider plan (20-03) reuses one
/// canonical parser for the driver-profile payload.
class AcceptedRide {
  /// Accepted ride id.
  final String rideId;

  /// Backend status (expected `'accepted'`).
  final String status;

  /// Scheduled marker.
  final bool isScheduled;

  /// Assigned driver profile.
  final AcceptedDriver driver;

  /// Pickup point.
  final B2bLocation pickupLocation;

  /// Dropoff point.
  final B2bLocation dropoffLocation;

  /// Quoted fare.
  final double fare;

  /// Trip distance.
  final double distance;

  /// Payment method.
  final String paymentMethod;

  /// Payment status.
  final String paymentStatus;

  /// True when the rider must still pay.
  final bool requiresPayment;

  /// Backend message.
  final String message;

  const AcceptedRide({
    this.rideId = '',
    this.status = '',
    this.isScheduled = false,
    this.driver = const AcceptedDriver(),
    this.pickupLocation = const B2bLocation(),
    this.dropoffLocation = const B2bLocation(),
    this.fare = 0.0,
    this.distance = 0.0,
    this.paymentMethod = '',
    this.paymentStatus = '',
    this.requiresPayment = false,
    this.message = '',
  });

  /// Parses the `ride:accepted` payload. Never throws.
  factory AcceptedRide.fromMap(Map<String, dynamic> data) {
    return AcceptedRide(
      rideId: (data['rideId'] ?? data['_id'] ?? data['id'])?.toString() ?? '',
      status: data['status']?.toString() ?? '',
      isScheduled: data['isScheduled'] == true,
      driver: AcceptedDriver.fromMap(data['driver']),
      pickupLocation: B2bLocation.fromMap(data['pickupLocation']),
      dropoffLocation: B2bLocation.fromMap(data['dropoffLocation']),
      fare: (data['fare'] as num?)?.toDouble() ?? 0.0,
      distance: (data['distance'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: data['paymentMethod']?.toString() ?? '',
      paymentStatus: data['paymentStatus']?.toString() ?? '',
      requiresPayment: data['requiresPayment'] == true,
      message: data['message']?.toString() ?? '',
    );
  }
}

/// Coerces a stops list to string-keyed maps, dropping non-map entries.
/// Never throws: non-list input yields an empty list.
List<Map<String, dynamic>> _stringMapList(dynamic raw) {
  if (raw is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final entry in raw) {
    if (entry is Map) {
      out.add(Map<String, dynamic>.from(entry));
    }
  }
  return out;
}

/// Driver-en-route signal from `ride:driverEnRoute` (§3.2).
///
/// Emitted when the driver finishes trip A and heads to rider B.
class DriverEnRoute {
  /// Ride id.
  final String rideId;

  /// Backend status (expected `'accepted'`).
  final String status;

  /// Backend message (e.g. "Your driver is on the way!").
  final String message;

  const DriverEnRoute({
    this.rideId = '',
    this.status = '',
    this.message = '',
  });

  /// Parses the `ride:driverEnRoute` payload. Never throws.
  factory DriverEnRoute.fromMap(Map<String, dynamic> data) {
    return DriverEnRoute(
      rideId: (data['rideId'] ?? data['_id'] ?? data['id'])?.toString() ?? '',
      status: data['status']?.toString() ?? '',
      message: data['message']?.toString() ?? '',
    );
  }
}

/// Real-time ETA update from `ride:etaUpdate` (§3.2).
class EtaUpdate {
  /// Ride id.
  final String rideId;

  /// Human-readable duration (e.g. "8 mins").
  final String duration;

  /// Human-readable distance (e.g. "1.8 mi").
  final String distance;

  const EtaUpdate({
    this.rideId = '',
    this.duration = '',
    this.distance = '',
  });

  /// Parses the `ride:etaUpdate` payload. Never throws.
  factory EtaUpdate.fromMap(Map<String, dynamic> data) {
    return EtaUpdate(
      rideId: (data['rideId'] ?? data['_id'] ?? data['id'])?.toString() ?? '',
      duration: data['duration']?.toString() ?? '',
      distance: data['distance']?.toString() ?? '',
    );
  }
}

/// Queued-ride cancellation from `ride:cancelled` (§3.1).
///
/// Emitted if rider B cancels the queued ride while the driver is on trip A.
class QueuedCancellation {
  /// Cancelled ride id.
  final String rideId;

  /// Who cancelled (`user` or `driver`).
  final String cancelledBy;

  const QueuedCancellation({
    this.rideId = '',
    this.cancelledBy = '',
  });

  /// Parses the `ride:cancelled` payload. Never throws.
  factory QueuedCancellation.fromMap(Map<String, dynamic> data) {
    return QueuedCancellation(
      rideId: (data['rideId'] ?? data['_id'] ?? data['id'])?.toString() ?? '',
      cancelledBy: data['cancelledBy']?.toString() ?? '',
    );
  }
}

/// Merges a newer B2B payload into the one already held, never letting a
/// thinner payload erase richer data.
///
/// The same offer arrives over two transports with different richness: the
/// socket `ride:newRequest` carries nested pickup/dropoff, while the FCM
/// data message carries only `rideId`/`fare`/`isBackToBack`. Last-write-wins
/// would blank the addresses; this keeps whichever side has real values.
Map<String, dynamic> mergeB2bOfferData(
  Map<String, dynamic>? current,
  Map<String, dynamic> incoming,
) {
  if (current == null) return Map<String, dynamic>.from(incoming);
  final merged = Map<String, dynamic>.from(current);
  incoming.forEach((key, value) {
    if (value == null) return;
    final existing = merged[key];
    final existingEmpty =
        existing == null ||
        existing == '' ||
        (existing is Map && existing.isEmpty) ||
        (existing is List && existing.isEmpty);
    if (existingEmpty) {
      merged[key] = value;
      return;
    }
    if (existing is Map && value is Map) {
      merged[key] = {
        ...existing,
        ...value.map((k, v) => MapEntry(k.toString(), v)),
      };
    }
  });
  return merged;
}

/// Driver statuses during which an active trip owns the screen.
const List<String> kB2bBusyStatuses = [
  'pickup',
  'arrived',
  'driver_arrived',
  'in_progress',
  'at_stop',
  'awaiting_cash_confirmation',
  'awaiting_payment',
];

/// Whether the back-to-back overlay (offer card / queued pill) renders.
///
/// Pure policy so the driver screen and tests share one decision:
/// - A queued trip is ALWAYS visible, including after the previous trip
///   ended (driver idle between trips) — hiding it stranded the driver with
///   an invisible queue and blocked every new B2B offer.
/// - A pending offer only shows while a trip is active; idle drivers get the
///   normal request card instead.
bool shouldShowB2bOverlay({
  required bool hasQueuedTrip,
  required bool hasOffer,
  required String status,
}) {
  if (hasQueuedTrip) return true;
  if (!hasOffer) return false;
  return kB2bBusyStatuses.contains(status);
}

/// Whether an incoming B2B offer must be dropped because a queue is held.
///
/// A queued trip whose `previousRide` is not the current active ride is
/// stale (its trip ended without promotion) — it must not block new offers
/// forever; the caller recovers it from the server instead.
bool shouldBlockB2bOffer({
  required bool hasQueuedTrip,
  String? queuedPreviousRideId,
  String? currentRideId,
}) {
  if (!hasQueuedTrip) return false;
  final previous = queuedPreviousRideId;
  if (previous == null || previous.isEmpty) return true;
  if (currentRideId == null || currentRideId.isEmpty) return false;
  return previous == currentRideId;
}
