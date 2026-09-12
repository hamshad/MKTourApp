import 'package:flutter/material.dart';
import '../../core/api_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/widgets/platform_map.dart';
import '../../core/widgets/route_map_helpers.dart';
import '../../core/services/places_service.dart';
import '../../core/models/vehicle.dart';

class RideDetailScreen extends StatefulWidget {
  final String rideId;

  const RideDetailScreen({super.key, required this.rideId});

  @override
  State<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends State<RideDetailScreen> {
  final ApiService _apiService = ApiService();
  final PlacesService _placesService = PlacesService();
  Map<String, dynamic>? _rideDetails;
  bool _isLoading = true;
  String? _error;

  List<LatLng> _routePoints = [];
  LatLngBounds? _routeBounds;

  @override
  void initState() {
    super.initState();
    _fetchRideDetails();
  }

  Future<void> _fetchRideDetails() async {
    try {
      final details = await _apiService.getRideDetails(widget.rideId);
      if (mounted) {
        setState(() {
          _rideDetails = details['data'];
          _isLoading = false;
        });

        // After ride details load, fetch the road-following route polyline
        await _fetchRoutePolyline();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchRoutePolyline() async {
    if (_rideDetails == null) return;

    final pickup = _rideDetails!['pickupLocation'];
    final dropoff = _rideDetails!['dropoffLocation'];
    if (pickup == null || dropoff == null) return;

    final pickupLat = pickup['coordinates'][1];
    final pickupLng = pickup['coordinates'][0];
    final dropoffLat = dropoff['coordinates'][1];
    final dropoffLng = dropoff['coordinates'][0];

    debugPrint('🗺️ [RideDetailScreen] Fetching route via get-directions...');
    // Multi-stop: send the ride's stops as waypoints so the polyline traces
    // pickup → stops → dropoff. No stops → plain origin/destination.
    final stops = parseRideStops(_rideDetails!['stops']);
    if (stops.isNotEmpty) {
      debugPrint(
        '🗺️ [RideDetailScreen] Including ${stops.length} stop(s) as waypoints',
      );
    }
    final directions = await _placesService.getDirections(
      (pickupLat as num).toDouble(),
      (pickupLng as num).toDouble(),
      (dropoffLat as num).toDouble(),
      (dropoffLng as num).toDouble(),
      stops: stops,
    );

    if (!mounted) return;

    if (directions != null &&
        directions['polyline'] is List &&
        (directions['polyline'] as List).isNotEmpty) {
      final polylinePoints = (directions['polyline'] as List)
          .cast<Map<String, double>>();

      final points = polylinePoints
          .map((p) => LatLng(p['lat'] ?? 0.0, p['lng'] ?? 0.0))
          .where((p) => !(p.latitude == 0.0 && p.longitude == 0.0))
          .toList();

      setState(() {
        _routePoints = points;
        _routeBounds = points.isNotEmpty
            ? LatLngBounds.fromPoints(points)
            : null;
      });

      debugPrint(
        '✅ [RideDetailScreen] Route loaded. Points: ${_routePoints.length}',
      );
      return;
    }

    // Fallback: straight line (still via stops so markers match the list).
    debugPrint(
      '⚠️ [RideDetailScreen] Directions missing/empty. Using straight-line fallback.',
    );
    final stopPoints = RouteMapHelpers.stopPoints(
      parseRideStops(_rideDetails!['stops']),
    );
    final fallback = [
      LatLng(pickupLat.toDouble(), pickupLng.toDouble()),
      ...stopPoints,
      LatLng(dropoffLat.toDouble(), dropoffLng.toDouble()),
    ];
    setState(() {
      _routePoints = fallback;
      _routeBounds = LatLngBounds.fromPoints(fallback);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ride Details')),
        body: Center(child: Text('Error: $_error')),
      );
    }

    if (_rideDetails == null) {
      return const Scaffold(body: Center(child: Text('No ride details found')));
    }

    final pickup = _rideDetails!['pickupLocation'];
    final dropoff = _rideDetails!['dropoffLocation'];
    final pickupLat = pickup['coordinates'][1];
    final pickupLng = pickup['coordinates'][0];
    final dropoffLat = dropoff['coordinates'][1];
    final dropoffLng = dropoff['coordinates'][0];

    final markers = [
      MapMarker(
        id: 'pickup',
        lat: pickupLat,
        lng: pickupLng,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Icon(Icons.my_location, color: Colors.white, size: 16),
        ),
        title: 'Pickup',
      ),
      // Numbered intermediate stops (Uber/Bolt style).
      ...RouteMapHelpers.stopMarkers(
        parseRideStops(_rideDetails!['stops']),
        statuses: parseRideStops(
          _rideDetails!['stops'],
        ).map((s) => s.status).toList(),
      ),
      MapMarker(
        id: 'dropoff',
        lat: dropoffLat,
        lng: dropoffLng,
        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
        title: 'Dropoff',
      ),
    ];

    final polylines = _routePoints.isNotEmpty
        ? _routePoints
        : [
            LatLng(pickupLat.toDouble(), pickupLng.toDouble()),
            LatLng(dropoffLat.toDouble(), dropoffLng.toDouble()),
          ];

    return Scaffold(
      body: Stack(
        children: [
          PlatformMap(
            initialLat: pickupLat,
            initialLng: pickupLng,
            markers: markers,
            polylines: [
              ...RouteMapHelpers.routePolylines(polylines, color: Colors.black),
            ],
            bounds: _routeBounds ?? LatLngBounds.fromPoints(polylines),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _rideDetails!['status'].toString().toUpperCase(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _rideDetails!['status'] == 'cancelled'
                              ? Colors.red
                              : Colors.green,
                        ),
                      ),
                      Text(
                        '\$${_rideDetails!['fare']}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Cancellation Reason
                  if (_rideDetails!['status'] == 'cancelled' &&
                      _rideDetails!['cancellationReason'] != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade100),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Reason: ${_rideDetails!['cancellationReason']}',
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Intermediate stops + wait-fee chip (new flow).
                  // No verification codes are shown anywhere in the ride flow.
                  Builder(
                    builder: (context) {
                      final stops = parseRideStops(_rideDetails!['stops']);
                      final totalWaitFee =
                          ((_rideDetails!['totalWaitFee'] as num?) ?? 0)
                              .toDouble();
                      final totalWaitMinutes =
                          ((_rideDetails!['totalWaitMinutes'] as num?) ?? 0)
                              .toInt();
                      if (stops.isEmpty && totalWaitFee <= 0) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (totalWaitFee > 0)
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.amber.shade200,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 18,
                                    color: Colors.amber.shade800,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Wait $totalWaitMinutes min (${WaitFeePolicy.freeMinutes} free) · £${totalWaitFee.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.amber.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ...stops.map(
                            (stop) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: stop.isCompleted
                                          ? Colors.green
                                          : stop.isArrived
                                              ? Colors.blue
                                              : Colors.grey.shade400,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${stop.stopOrder}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      stop.address.isNotEmpty
                                          ? stop.address
                                          : 'Stop ${stop.stopOrder}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    stop.status,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                  ),

                  // Driver & Vehicle Info
                  if (_rideDetails!['driver'] != null) ...[
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage:
                              _rideDetails!['driver']['profilePicture'] != null
                              ? NetworkImage(
                                  _rideDetails!['driver']['profilePicture'],
                                )
                              : null,
                          child:
                              _rideDetails!['driver']['profilePicture'] == null
                              ? const Icon(Icons.person, color: Colors.grey)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _rideDetails!['driver']['name'] ?? 'Driver',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.star,
                                    size: 14,
                                    color: Colors.amber,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_rideDetails!['driver']['rating'] ?? '-'}',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _rideDetails!['driver']['vehicle']?['model'] ??
                                  'Vehicle',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _rideDetails!['driver']['vehicle']?['number'] ??
                                  '',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                  ],

                  _buildLocationRow(Icons.my_location, pickup['address']),
                  const SizedBox(height: 16),
                  _buildLocationRow(Icons.location_on, dropoff['address']),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, String address) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            address,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
