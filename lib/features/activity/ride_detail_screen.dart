import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as latlong;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/widgets/platform_map.dart';
import '../../core/widgets/route_map_helpers.dart';
import '../../core/services/places_service.dart';
import '../../core/auth_provider.dart';
import '../../core/models/vehicle.dart';

class RideDetailScreen extends StatefulWidget {
  final String rideId;
  final Map<String, dynamic>? initialData;

  const RideDetailScreen({
    super.key,
    required this.rideId,
    this.initialData,
  });

  @override
  State<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends State<RideDetailScreen> {
  Map<String, dynamic>? _rideData;
  bool _isLoading = true;
  final PlacesService _placesService = PlacesService();
  List<latlong.LatLng> _routePoints = [];

  @override
  void initState() {
    super.initState();
    _rideData = widget.initialData;
    _fetchRideDetails();
  }

  Future<void> _fetchRideDetails() async {
    final details = await Provider.of<AuthProvider>(context, listen: false)
        .fetchRideDetails(widget.rideId);
    
    if (mounted) {
      setState(() {
        if (details != null) {
          _rideData = details;
        }
        _isLoading = false;
      });
      await _fetchRoutePolyline();
    }
  }

  /// Real road route via get-directions, tracing through stops when present.
  Future<void> _fetchRoutePolyline() async {
    final data = _rideData;
    if (data == null) return;
    final pickup = data['pickupLocation'];
    final dropoff = data['dropoffLocation'];
    if (pickup is! Map || dropoff is! Map) return;
    final pCoords = pickup['coordinates'];
    final dCoords = dropoff['coordinates'];
    if (pCoords is! List || dCoords is! List) return;
    if (pCoords.length < 2 || dCoords.length < 2) return;
    final pLng = (pCoords[0] as num).toDouble();
    final pLat = (pCoords[1] as num).toDouble();
    final dLng = (dCoords[0] as num).toDouble();
    final dLat = (dCoords[1] as num).toDouble();
    final stops = parseRideStops(data['stops']);
    try {
      final directions = await _placesService.getDirections(
        pLat,
        pLng,
        dLat,
        dLng,
        stops: stops,
      );
      if (!mounted) return;
      if (directions != null &&
          directions['polyline'] is List &&
          (directions['polyline'] as List).isNotEmpty) {
        setState(() {
          _routePoints = (directions['polyline'] as List).map((p) {
            final m = Map<String, dynamic>.from(p as Map);
            return latlong.LatLng(
              (m['lat'] as num).toDouble(),
              (m['lng'] as num).toDouble(),
            );
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('⚠️ [ActivityRideDetail] waypoint route failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Extract coordinates
    double? pickupLat;
    double? pickupLng;
    double? dropoffLat;
    double? dropoffLng;

    if (_rideData != null) {
      final pickup = _rideData!['pickupLocation'];
      final dropoff = _rideData!['dropoffLocation'];

      if (pickup is Map && pickup['coordinates'] != null) {
        // GeoJSON is [lng, lat]
        final coords = pickup['coordinates'];
        if (coords is List && coords.length >= 2) {
          pickupLng = (coords[0] as num).toDouble();
          pickupLat = (coords[1] as num).toDouble();
        }
      }

      if (dropoff is Map && dropoff['coordinates'] != null) {
        final coords = dropoff['coordinates'];
        if (coords is List && coords.length >= 2) {
          dropoffLng = (coords[0] as num).toDouble();
          dropoffLat = (coords[1] as num).toDouble();
        }
      }
    }

    List<MapMarker> markers = [];
    List<MapPolyline> polylines = [];
    fmap.LatLngBounds? bounds;

    if (pickupLat != null && pickupLng != null) {
      markers.add(MapMarker(
        id: 'pickup',
        lat: pickupLat,
        lng: pickupLng,
        title: 'Pickup',
        child: const Icon(Icons.my_location, color: Colors.green, size: 40),
      ));
    }

    if (dropoffLat != null && dropoffLng != null) {
      markers.add(MapMarker(
        id: 'dropoff',
        lat: dropoffLat,
        lng: dropoffLng,
        title: 'Dropoff',
        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
      ));
    }

    // Numbered intermediate stops (Uber/Bolt style).
    final rideStops = parseRideStops(_rideData?['stops']);
    if (rideStops.isNotEmpty) {
      markers.addAll(
        RouteMapHelpers.stopMarkers(
          rideStops,
          statuses: rideStops.map((s) => s.status).toList(),
        ),
      );
    }

    if (_routePoints.isNotEmpty) {
      // Real road route (already traces through stops via waypoints).
      polylines.addAll(
        RouteMapHelpers.routePolylines(
          _routePoints,
          color: AppTheme.primaryColor,
        ),
      );
    } else if (pickupLat != null && pickupLng != null && dropoffLat != null && dropoffLng != null) {
      // Create a curved polyline between pickup and dropoff
      final start = latlong.LatLng(pickupLat, pickupLng);
      final end = latlong.LatLng(dropoffLat, dropoffLng);

      // Generate curved points
      final curvedPoints = _generateCurvedPoints(start, end);

      polylines.add(MapPolyline(
        id: 'route',
        points: curvedPoints,
        color: AppTheme.primaryColor,
        width: 4,
      ));
    }

    if (markers.isNotEmpty) {
      bounds = fmap.LatLngBounds.fromPoints(
        markers.map((m) => latlong.LatLng(m.lat, m.lng)).toList(),
      );
    }

    final driver = (_rideData?['driver'] is Map) ? _rideData!['driver'] : null;
    final vehicle = (driver != null && driver['vehicle'] is Map) ? driver['vehicle'] : null;
    final dateStr = _rideData?['createdAt'];
    final status = _rideData?['status']?.toString().toUpperCase() ?? 'UNKNOWN';
    final bool isPromoRide = _rideData?['isPromoRide'] == true;
    final double rawFare = (_rideData?['fare'] as num?)?.toDouble() ?? 0.0;
    final double originalFare = (_rideData?['originalFare'] as num?)?.toDouble() ?? 0.0;
    // For display: show actual fare; if promo, also show original fare
    final price = '\u00a3${rawFare.toStringAsFixed(2)}';
    final destination = _rideData?['dropoffLocation'] is Map ? _rideData!['dropoffLocation']['address'] ?? 'Unknown Destination' : 'Unknown Destination';
    final pickupAddress = _rideData?['pickupLocation'] is Map ? _rideData!['pickupLocation']['address'] ?? 'Unknown Pickup' : 'Unknown Pickup';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Ride Details',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: _isLoading && _rideData == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Map View
                  SizedBox(
                    height: 250,
                    width: double.infinity,
                    child: PlatformMap(
                      initialLat: pickupLat ?? 37.7749,
                      initialLng: pickupLng ?? -122.4194,
                      markers: markers,
                      polylines: polylines,
                      bounds: bounds,
                      onTap: (lat, lng) {
                        debugPrint('Map tapped at: $lat, $lng');
                      },
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              dateStr != null ? dateStr.substring(0, 10) : 'Unknown Date', // Simple formatting
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: status == 'CANCELED' 
                                    ? Colors.red.withValues(alpha: 0.1) 
                                    : Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: status == 'CANCELED' ? Colors.red : Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Vehicle/Driver Info
                        if (driver != null)
                          Row(
                            children: [
                              const CircleAvatar(
                                radius: 24,
                                backgroundColor: AppTheme.surfaceColor,
                                child: Icon(Icons.person, color: AppTheme.textSecondary),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    vehicle != null ? '${vehicle['model']} (${vehicle['color']})' : 'Unknown Vehicle',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    '${vehicle != null ? vehicle['number'] : ''} • ${driver['name']}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  if (driver['rating'] != null)
                                    Row(
                                      children: [
                                        const Icon(Icons.star, size: 14, color: Colors.amber),
                                        const SizedBox(width: 4),
                                        Text(
                                          driver['rating'].toString(),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          )
                        else
                          const Text('Driver details not available'),
                        
                        const SizedBox(height: 24),
                        Divider(color: AppTheme.borderColor),
                        const SizedBox(height: 24),
                        
                        // Trip Details
                        _buildLocationRow(
                          icon: Icons.my_location,
                          color: Colors.green,
                          text: pickupAddress,
                          time: 'Pickup',
                        ),
                        _buildDottedLine(),
                        _buildLocationRow(
                          icon: Icons.location_on,
                          color: Colors.red,
                          text: destination,
                          time: 'Dropoff',
                        ),

                        // Intermediate stops
                        ..._buildStopsList(_rideData),

                        // Scheduled pickup time
                        if (_rideData?['scheduledPickupTime'] != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.primaryColor.withOpacity(0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 18,
                                  color: AppTheme.primaryColor,
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Scheduled Pickup',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      DateFormat('EEE, MMM dd · h:mm a')
                                          .format(
                                        DateTime.parse(
                                          _rideData!['scheduledPickupTime'],
                                        ).toLocal(),
                                      ),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),
                        Divider(color: AppTheme.borderColor),
                        const SizedBox(height: 24),
                        
                        // Payment
                        Row(
                          children: [
                            const Text(
                              'Payment',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            if (_rideData?['isAirportTransfer'] == true) ...[
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.flight, color: Colors.blue, size: 12),
                                    SizedBox(width: 4),
                                    Text(
                                      'Airport',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (isPromoRide) ...[    
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF22C55E).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: const Color(0xFF22C55E).withOpacity(0.4)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('🎁', style: TextStyle(fontSize: 11)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Free Ride',
                                      style: TextStyle(
                                        color: Color(0xFF16A34A),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Original fare row (promo rides only)
                        if (isPromoRide && originalFare > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Original Fare',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                Text(
                                  '£${originalFare.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Trip Fare',
                              style: TextStyle(
                                fontSize: 16,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              isPromoRide && rawFare == 0 ? '£0.00 (Free!)' : price,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isPromoRide && rawFare == 0
                                    ? const Color(0xFF22C55E)
                                    : AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),

                        // Deposit / payment status for scheduled rides
                        if (_rideData?['isScheduled'] == true) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Deposit',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              _buildDepositStatusChip(_rideData),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildLocationRow({
    required IconData icon,
    required Color color,
    required String text,
    required String time,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildStopsList(Map<String, dynamic>? rideData) {
    if (rideData == null || rideData['stops'] == null) return [];
    final stops = parseRideStops(rideData['stops']);
    if (stops.isEmpty) return [];
    return [
      const SizedBox(height: 16),
      ...stops.asMap().entries.map((entry) {
        final i = entry.key;
        final stop = entry.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  stop.address.isNotEmpty ? stop.address : 'Stop ${i + 1}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _stopStatusColor(stop.status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  stop.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: _stopStatusColor(stop.status),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    ];
  }

  Widget _buildDottedLine() {
    return Container(
      margin: const EdgeInsets.only(left: 9, top: 4, bottom: 4),
      height: 24,
      width: 2,
      decoration: BoxDecoration(
        color: AppTheme.borderColor,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Color _stopStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'in_progress':
        return Colors.orange;
      case 'pending':
      default:
        return Colors.grey;
    }
  }

  Widget _buildDepositStatusChip(Map<String, dynamic>? rideData) {
    final depositAmount = (rideData?['depositAmount'] as num?)?.toDouble() ?? 0.0;
    final depositStatus = rideData?['depositStatus']?.toString() ?? 'pending';
    final payment = rideData?['payment'];
    final paymentStatus = payment is Map ? payment['status']?.toString() : null;

    Color chipColor;
    String chipText;

    if (depositStatus == 'paid' || paymentStatus == 'succeeded') {
      chipColor = Colors.green;
      chipText = 'Paid';
    } else if (paymentStatus == 'requires_payment_method' ||
        paymentStatus == 'requires_action') {
      chipColor = Colors.orange;
      chipText = 'Awaiting Payment';
    } else if (depositAmount > 0) {
      chipColor = Colors.orange;
      chipText = '£${depositAmount.toStringAsFixed(2)} Pending';
    } else {
      chipColor = Colors.green;
      chipText = 'No Deposit';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        chipText,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: chipColor,
        ),
      ),
    );
  }

  /// Generates points for a curved polyline between two LatLng points.
  List<latlong.LatLng> _generateCurvedPoints(
      latlong.LatLng start, latlong.LatLng end) {
    const int segments = 20;
    final List<latlong.LatLng> points = [];

    // Midpoint calculation
    final double midLat = (start.latitude + end.latitude) / 2;
    final double midLng = (start.longitude + end.longitude) / 2;

    // Calculate perpendicular offset for curves
    // A simple heuristic: offset based on a fraction of the distance between points
    final double diffLat = end.latitude - start.latitude;
    final double diffLng = end.longitude - start.longitude;

    // Control point for a simple quadratic Bezier curve
    // Adding an offset perpendicular to the line start-end
    const double curveIntensity = 0.25;
    final double controlLat = midLat + (diffLng * curveIntensity);
    final double controlLng = midLng - (diffLat * curveIntensity);

    for (int i = 0; i <= segments; i++) {
      final double t = i / segments;

      // Quadratic Bezier formula: B(t) = (1-t)^2*P0 + 2(1-t)*t*P1 + t^2*P2
      final double lat = (1 - t) * (1 - t) * start.latitude +
          2 * (1 - t) * t * controlLat +
          t * t * end.latitude;
      final double lng = (1 - t) * (1 - t) * start.longitude +
          2 * (1 - t) * t * controlLng +
          t * t * end.longitude;

      points.add(latlong.LatLng(lat, lng));
    }

    return points;
  }
}
