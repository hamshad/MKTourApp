import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/api_service.dart';
import '../../core/services/places_service.dart';
import '../ride/ride_assigned_screen.dart';
import '../../core/widgets/platform_map.dart';
import 'package:latlong2/latlong.dart' as lat_lng;
import 'package:flutter_map/flutter_map.dart' as fmap;

/// Ride Confirmation Screen - Shows ride details before final booking
/// Displays pickup, dropoff, vehicle type, distance, duration, and fare
class RideConfirmationScreen extends StatefulWidget {
  final Map<String, dynamic> pickupLocation;
  final Map<String, dynamic> dropoffLocation;
  final String vehicleType;
  final String vehicleName;
  final Map<String, dynamic> fareData;
  final List<dynamic>? polyline; // Added polyline

  const RideConfirmationScreen({
    super.key,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.vehicleType,
    required this.vehicleName,
    required this.fareData,
    this.polyline,
  });

  @override
  State<RideConfirmationScreen> createState() => _RideConfirmationScreenState();
}

class _RideConfirmationScreenState extends State<RideConfirmationScreen> {
  final ApiService _apiService = ApiService();
  final PlacesService _placesService = PlacesService();
  bool _isLoading = false;
  bool _isFetchingFare = true;
  Map<String, dynamic>? _dynamicFareData;

  @override
  void initState() {
    super.initState();
    _fetchDirectionsAndFare();
  }

  Future<void> _fetchDirectionsAndFare() async {
    debugPrint('🚀 RideConfirmationScreen: Initializing fare fetch...');
    setState(() => _isFetchingFare = true);

    try {
      final pickupLat = widget.pickupLocation['coordinates'][1];
      final pickupLng = widget.pickupLocation['coordinates'][0];
      final dropoffLat = widget.dropoffLocation['coordinates'][1];
      final dropoffLng = widget.dropoffLocation['coordinates'][0];

      final result = await _placesService.getDistanceAndFare(
        originLat: pickupLat,
        originLng: pickupLng,
        destLat: dropoffLat,
        destLng: dropoffLng,
        vehicleType: widget.vehicleType,
      );

      if (mounted && result != null) {
        setState(() {
          _dynamicFareData = result;
          _isFetchingFare = false;
        });
        debugPrint('✅ RideConfirmationScreen: Dynamic fare fetched: £${_dynamicFareData!['total_fare']}');
      } else if (mounted) {
        setState(() => _isFetchingFare = false);
        debugPrint('⚠️ RideConfirmationScreen: Dynamic fare fetch failed, using initial partial data');
      }
    } catch (e) {
      debugPrint('❌ RideConfirmationScreen: Error fetching dynamic fare: $e');
      if (mounted) {
        setState(() => _isFetchingFare = false);
      }
    }
  }

  Map<String, dynamic> get _currentFareData => _dynamicFareData ?? widget.fareData;

  String get _pickupAddress =>
      widget.pickupLocation['address'] ?? 'Pickup Location';
  String get _dropoffAddress =>
      widget.dropoffLocation['address'] ?? 'Dropoff Location';

  double get _fare => (_currentFareData['total_fare'] is int)
      ? (_currentFareData['total_fare'] as int).toDouble()
      : (_currentFareData['total_fare'] ?? 0.0);

  String get _distanceText => _currentFareData['distance_text'] ?? '';
  String get _durationText => _currentFareData['duration_text'] ?? '';
  int get _durationSeconds => _currentFareData['duration_seconds'] ?? 0;

  String get _estimatedArrival {
    final now = DateTime.now();
    final arrival = now.add(Duration(seconds: _durationSeconds));
    return DateFormat('h:mm a').format(arrival);
  }

  Future<void> _confirmRide() async {
    debugPrint('🚀 RideConfirmationScreen: Confirming ride...');
    setState(() => _isLoading = true);

    try {
      // Calculate distance in km from meters
      final distanceKm = (_currentFareData['distance_meters'] ?? 0) / 1000;

      final rideData = {
        'pickupLocation': widget.pickupLocation,
        'dropoffLocation': widget.dropoffLocation,
        'vehicleType': widget.vehicleType,
        'distance': distanceKm,
        'fare': _fare,
      };

      debugPrint(
        '🚀 RideConfirmationScreen: Creating ride with data: $rideData',
      );

      final response = await _apiService.createRide(rideData);

      debugPrint('✅ RideConfirmationScreen: Ride created successfully');
      debugPrint('📋 RideConfirmationScreen: Response: $response');

      if (mounted) {
        setState(() => _isLoading = false);

        debugPrint('🏠 RideConfirmationScreen: Ride confirmed, returning to Home with searching state');
        
        // Pop and pass the ride data back to Home Screen
        Navigator.of(context).pop({
          'status': 'searching',
          'ride': response['data'],
        });
      }
    } catch (e) {
      debugPrint('❌ RideConfirmationScreen: Error creating ride: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to book ride: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Confirm Ride',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Map Snapshot
                  _buildMapSnapshot(),

                  const SizedBox(height: 16),

                  // Route Card
                  _buildRouteCard(),

                  const SizedBox(height: 16),

                  // Vehicle Card
                  _buildVehicleCard(),

                  const SizedBox(height: 16),

                  // Trip Details Card
                  _buildTripDetailsCard(),

                  const SizedBox(height: 16),

                  // Payment Card
                  _buildPaymentCard(),
                ],
              ),
            ),
          ),

          // Bottom Confirm Button
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildRouteCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Pickup
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PICKUP',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _pickupAddress,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Dotted line
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Row(
              children: [
                Column(
                  children: List.generate(
                    3,
                    (index) => Container(
                      width: 2,
                      height: 6,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: Colors.grey[300],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Dropoff
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DROP-OFF',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _dropoffAddress,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMapSnapshot() {
    // Convert List<dynamic> from directions API or List<LatLng> to lat_lng.LatLng
    final List<lat_lng.LatLng> points = [];
    if (widget.polyline != null) {
      for (var p in widget.polyline!) {
        // Handle different possible types for the polyline points
        if (p is lat_lng.LatLng) {
          points.add(p);
        } else if (p is Map) {
          points.add(lat_lng.LatLng(
            (p['lat'] as num).toDouble(),
            (p['lng'] as num).toDouble(),
          ));
        }
      }
    }

    final bounds =
        points.isNotEmpty ? fmap.LatLngBounds.fromPoints(points) : null;

    final pickupCoords = widget.pickupLocation['coordinates'] as List;
    final dropoffCoords = widget.dropoffLocation['coordinates'] as List;

    final markers = [
      MapMarker(
        id: 'pickup',
        lat: pickupCoords[1],
        lng: pickupCoords[0],
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
          width: 8,
          height: 8,
        ),
        title: 'Pickup',
      ),
      MapMarker(
        id: 'dropoff',
        lat: dropoffCoords[1],
        lng: dropoffCoords[0],
        child: const Icon(Icons.location_on, color: Colors.red, size: 28),
        title: 'Dropoff',
      ),
    ];

    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: PlatformMap(
          initialLat: pickupCoords[1],
          initialLng: pickupCoords[0],
          markers: markers,
          polylines: points.isNotEmpty
              ? [
                  MapPolyline(
                    id: 'route',
                    points: points,
                    color: AppTheme.primaryColor,
                    width: 4.0,
                  ),
                ]
              : [],
          bounds: bounds,
          interactive: false,
        ),
      ),
    );
  }

  Widget _buildVehicleCard() {
    IconData vehicleIcon;
    switch (widget.vehicleType) {
      case 'suv':
        vehicleIcon = Icons.directions_car_filled;
        break;
      case 'hatchback':
        vehicleIcon = Icons.car_rental;
        break;
      case 'van':
        vehicleIcon = Icons.airport_shuttle;
        break;
      default:
        vehicleIcon = Icons.directions_car;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(vehicleIcon, size: 32, color: AppTheme.primaryColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.vehicleName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                _isFetchingFare
                    ? Container(
                        margin: const EdgeInsets.only(top: 4),
                        width: 100,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      )
                    : Text(
                        'Estimated arrival: $_estimatedArrival',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trip Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
              Icons.straighten, 'Distance', _isFetchingFare ? '...' : _distanceText),
          const Divider(height: 24),
          _buildDetailRow(
              Icons.access_time, 'Duration', _isFetchingFare ? '...' : _durationText),
          const Divider(height: 24),
          _buildDetailRow(
              Icons.schedule, 'ETA', _isFetchingFare ? '...' : _estimatedArrival),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.money, color: Colors.green[700], size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Cash',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fare Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Fare',
                  style: TextStyle(fontSize: 16, color: AppTheme.textPrimary),
                ),
                _isFetchingFare
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primaryColor,
                        ),
                      )
                    : Text(
                        '£${_fare.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
              ],
            ),
            const SizedBox(height: 16),
            // Confirm Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed:
                    (_isLoading || _isFetchingFare) ? null : _confirmRide,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Confirm Ride',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
