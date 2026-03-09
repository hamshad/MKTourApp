import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as latlong;
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/widgets/platform_map.dart';
import '../../core/auth_provider.dart';

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

    if (pickupLat != null && pickupLng != null && dropoffLat != null && dropoffLng != null) {
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
