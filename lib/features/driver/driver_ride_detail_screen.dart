import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';

class DriverRideDetailScreen extends StatefulWidget {
  final Map<String, dynamic> rideData;

  const DriverRideDetailScreen({super.key, required this.rideData});

  @override
  State<DriverRideDetailScreen> createState() => _DriverRideDetailScreenState();
}

class _DriverRideDetailScreenState extends State<DriverRideDetailScreen> {
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    // Map bounds will be fitted in onMapCreated
  }

  void _fitMapBounds() {
    if (_mapController == null) return;

    final pickupCoords =
        widget.rideData['pickupLocation']?['coordinates'] ?? [0.0, 0.0];
    final dropoffCoords =
        widget.rideData['dropoffLocation']?['coordinates'] ?? [0.0, 0.0];

    final pickup = LatLng(pickupCoords[1], pickupCoords[0]);
    final dropoff = LatLng(dropoffCoords[1], dropoffCoords[0]);

    final bounds = LatLngBounds(
      southwest: LatLng(
        pickup.latitude < dropoff.latitude ? pickup.latitude : dropoff.latitude,
        pickup.longitude < dropoff.longitude ? pickup.longitude : dropoff.longitude,
      ),
      northeast: LatLng(
        pickup.latitude > dropoff.latitude ? pickup.latitude : dropoff.latitude,
        pickup.longitude > dropoff.longitude ? pickup.longitude : dropoff.longitude,
      ),
    );

    // Fit the map to show both markers with padding
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fare = _toDouble(widget.rideData['fare']);
    final tip = _toDouble(widget.rideData['tip']);
    final surge = _toDouble(widget.rideData['surge']);
    final bool isPromoRide = widget.rideData['isPromoRide'] == true;
    final double originalFare = _toDouble(widget.rideData['originalFare']);
    // Drivers always see the original fare (the amount they earn),
    // not the discounted fare the passenger pays.
    final double displayFare = isPromoRide && originalFare > 0 ? originalFare : fare;
    final total = displayFare + tip + surge;
    final status = (widget.rideData['status'] ?? 'completed').toString();
    final passenger = widget.rideData['user'] is Map
        ? widget.rideData['user'] as Map<String, dynamic>
        : widget.rideData['passenger'] is Map
            ? widget.rideData['passenger'] as Map<String, dynamic>
            : widget.rideData['userData'] is Map
                ? widget.rideData['userData'] as Map<String, dynamic>
                : null;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Map Header
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(background: _buildMap(context)),
            leading: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDateTime(widget.rideData['createdAt']),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatCurrency(total),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _statusLabel(status),
                          style: TextStyle(
                            color: _statusColor(status),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),

                  // Passenger Info
                  const Text(
                    'Passenger',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 24,
                        backgroundColor: AppTheme.surfaceColor,
                        child: Icon(
                          Icons.person,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            passenger?['name'] ?? 'Passenger',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              Icon(Icons.star, size: 14, color: Colors.amber),
                              SizedBox(width: 4),
                              Text(
                                '${passenger?['rating'] ?? '5.0'}',
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.help_outline),
                        onPressed: () {},
                        tooltip: 'Report Issue',
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),

                  // Trip Details
                  const Text(
                    'Trip Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildLocationRow(
                    Icons.my_location,
                    Colors.green,
                    'Pickup',
                    _formatTime(widget.rideData['pickupTime'] ?? widget.rideData['acceptedAt']),
                    widget.rideData['pickupLocation']?['address'] ??
                        'Unknown Location',
                  ),
                  const SizedBox(height: 24),
                  _buildLocationRow(
                    Icons.location_on,
                    Colors.red,
                    'Drop-off',
                    _formatTime(widget.rideData['dropoffTime'] ?? widget.rideData['completedAt']),
                    widget.rideData['dropoffLocation']?['address'] ??
                        'Unknown Destination',
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),

                  // Fare Breakdown
                  Row(
                    children: [
                      const Text(
                        'Payment Breakdown',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      if (widget.rideData['isAirportTransfer'] == true) ...[
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
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (isPromoRide)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFF22C55E).withOpacity(0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('🎁', style: TextStyle(fontSize: 12)),
                            SizedBox(width: 6),
                            Text(
                              'Promo ride — passenger fare was discounted. Your earnings are unchanged.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF16A34A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  _buildFareRow('Trip Fare', _formatCurrency(displayFare)),
                  if (surge > 0) _buildFareRow('Surge', _formatCurrency(surge)),
                  if (tip > 0) _buildFareRow('Tip', _formatCurrency(tip)),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(),
                  ),
                  _buildFareRow('Total Earnings', _formatCurrency(total), isTotal: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  String _formatCurrency(double value) => '£${value.toStringAsFixed(2)}';

  String _formatDateTime(dynamic isoString) {
    if (isoString == null) return '--:--';
    try {
      final date = DateTime.parse(isoString.toString()).toLocal();
      return DateFormat('hh:mm a').format(date);
    } catch (_) {
      return '--:--';
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'Completed';
      case 'early_completed':
      case 'earlycompleted':
        return 'Ended Early';
      case 'cancelled':
      case 'cancelled_by_user':
      case 'cancelled_by_driver':
        return 'Cancelled';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'early_completed':
      case 'earlycompleted':
        return Colors.orange;
      case 'cancelled':
      case 'cancelled_by_user':
      case 'cancelled_by_driver':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _buildLocationRow(
    IconData icon,
    Color color,
    String label,
    String time,
    String address,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(icon, color: color, size: 20),
            Container(width: 2, height: 30, color: Colors.grey[200]),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    time,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFareRow(String label, String amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? AppTheme.primaryColor : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(BuildContext context) {
    // Parse coordinates
    // Assuming GeoJSON [lng, lat]
    final pickupCoords =
        widget.rideData['pickupLocation']?['coordinates'] ?? [0.0, 0.0];
    final dropoffCoords =
        widget.rideData['dropoffLocation']?['coordinates'] ?? [0.0, 0.0];

    final pickup = LatLng(pickupCoords[1], pickupCoords[0]);
    final dropoff = LatLng(dropoffCoords[1], dropoffCoords[0]);

    // Create curved polyline points
    final curvedPoints = _createCurvedPolyline(pickup, dropoff);

    // Calculate appropriate center and zoom
    final center = LatLng(
      (pickup.latitude + dropoff.latitude) / 2,
      (pickup.longitude + dropoff.longitude) / 2,
    );

    // Create Google Maps markers
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: pickup,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Pickup'),
      ),
      Marker(
        markerId: const MarkerId('dropoff'),
        position: dropoff,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Drop-off'),
      ),
    };

    // Create Google Maps polyline
    final polylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId('route'),
        points: curvedPoints,
        color: AppTheme.primaryColor,
        width: 5,
        geodesic: true,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: center,
        zoom: 13.0,
      ),
      markers: markers,
      polylines: polylines,
      onMapCreated: (GoogleMapController controller) {
        _mapController = controller;
        // Fit bounds after map is created
        Future.delayed(const Duration(milliseconds: 500), _fitMapBounds);
      },
      mapType: MapType.normal,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }

  /// Creates a curved polyline between two points using quadratic Bezier curve
  List<LatLng> _createCurvedPolyline(LatLng start, LatLng end) {
    final List<LatLng> points = [];
    
    // Calculate midpoint
    final midLat = (start.latitude + end.latitude) / 2;
    final midLng = (start.longitude + end.longitude) / 2;
    
    // Calculate perpendicular offset for the curve
    // The curve will bulge perpendicular to the line connecting start and end
    final latDiff = end.latitude - start.latitude;
    final lngDiff = end.longitude - start.longitude;
    final distance = (latDiff * latDiff + lngDiff * lngDiff);
    
    // Create a control point offset perpendicular to the line
    // Reduce offset for very short distances
    final offsetFactor = distance > 0.0001 ? 0.15 : 0.05;
    final controlLat = midLat + (lngDiff * offsetFactor);
    final controlLng = midLng - (latDiff * offsetFactor);
    
    final controlPoint = LatLng(controlLat, controlLng);
    
    // Generate points along a quadratic bezier curve
    const int segments = 30; // Increased for smoother curve
    for (int i = 0; i <= segments; i++) {
      final t = i / segments;
      final nt = 1 - t;
      
      // Quadratic bezier formula: B(t) = (1-t)²P0 + 2(1-t)tP1 + t²P2
      final lat = nt * nt * start.latitude +
          2 * nt * t * controlPoint.latitude +
          t * t * end.latitude;
      final lng = nt * nt * start.longitude +
          2 * nt * t * controlPoint.longitude +
          t * t * end.longitude;
      
      points.add(LatLng(lat, lng));
    }
    
    return points;
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '--:--';
    try {
      final date = DateTime.parse(isoString).toLocal();
      return "${date.hour}:${date.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return '--:--';
    }
  }
}
