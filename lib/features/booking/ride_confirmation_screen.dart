import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/api_service.dart';
import '../../core/services/places_service.dart';
import '../../core/services/payment_service.dart';
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
  String? _fareError; // Error message if fare fetch fails
  Map<String, dynamic>? _dynamicFareData;
  PaymentTiming _paymentTiming = PaymentTiming.payLater;

  // Route polyline points - initialized synchronously from passed data
  late List<lat_lng.LatLng> _routePoints;
  late fmap.LatLngBounds? _routeBounds;

  @override
  void initState() {
    super.initState();
    // Initialize route synchronously from passed polyline
    _initializeRouteSync();
    // Only fetch fare asynchronously
    _fetchDirectionsAndFare();
  }

  /// Initialize route polyline synchronously from passed data
  void _initializeRouteSync() {
    final pickupCoords = widget.pickupLocation['coordinates'] as List;
    final dropoffCoords = widget.dropoffLocation['coordinates'] as List;

    debugPrint('🗺️ RideConfirmationScreen: Initializing route...');
    debugPrint('   → Polyline provided: ${widget.polyline != null}');
    debugPrint('   → Polyline length: ${widget.polyline?.length ?? 0}');

    // If polyline was passed in, use it directly (synchronous)
    if (widget.polyline != null && widget.polyline!.isNotEmpty) {
      final points = <lat_lng.LatLng>[];

      // Debug: Check the first item type
      if (widget.polyline!.isNotEmpty) {
        final firstItem = widget.polyline!.first;
        debugPrint('   → First polyline item type: ${firstItem.runtimeType}');
        debugPrint('   → First polyline item: $firstItem');
      }

      for (var p in widget.polyline!) {
        if (p is lat_lng.LatLng) {
          points.add(p);
        } else if (p is Map) {
          points.add(
            lat_lng.LatLng(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble(),
            ),
          );
        } else {
          // Try to handle other LatLng types (e.g., from latlong2 without prefix)
          try {
            // Access latitude and longitude dynamically
            final lat = (p as dynamic).latitude as double;
            final lng = (p as dynamic).longitude as double;
            points.add(lat_lng.LatLng(lat, lng));
          } catch (e) {
            debugPrint('   ⚠️ Could not convert point: $p (${p.runtimeType})');
          }
        }
      }

      debugPrint('   → Converted points: ${points.length}');

      if (points.isNotEmpty) {
        _routePoints = points;
        _routeBounds = fmap.LatLngBounds.fromPoints(points);
        debugPrint(
          '   → Bounds: SW(${_routeBounds!.southWest.latitude}, ${_routeBounds!.southWest.longitude}) NE(${_routeBounds!.northEast.latitude}, ${_routeBounds!.northEast.longitude})',
        );
        debugPrint(
          '✅ RideConfirmationScreen: Using provided polyline (${points.length} points)',
        );
        return;
      }
    }

    // Fallback: straight line between pickup and dropoff (synchronous)
    debugPrint(
      '⚠️ RideConfirmationScreen: No polyline provided, using straight line',
    );
    _routePoints = [
      lat_lng.LatLng(
        (pickupCoords[1] as num).toDouble(),
        (pickupCoords[0] as num).toDouble(),
      ),
      lat_lng.LatLng(
        (dropoffCoords[1] as num).toDouble(),
        (dropoffCoords[0] as num).toDouble(),
      ),
    ];
    _routeBounds = fmap.LatLngBounds.fromPoints(_routePoints);
  }

  Future<void> _fetchDirectionsAndFare() async {
    debugPrint('🚀 RideConfirmationScreen: Initializing fare fetch...');
    setState(() {
      _isFetchingFare = true;
      _fareError = null; // Clear any previous error
    });

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
          _fareError = null;
        });
        debugPrint(
          '✅ RideConfirmationScreen: Dynamic fare fetched: £${_dynamicFareData!['total_fare']}',
        );
      } else if (mounted) {
        setState(() {
          _isFetchingFare = false;
          _fareError =
              'Unable to calculate fare for this route. Please try a different location.';
        });
        debugPrint(
          '❌ RideConfirmationScreen: Fare API returned null - cannot proceed',
        );
      }
    } catch (e) {
      debugPrint('❌ RideConfirmationScreen: Error fetching fare: $e');
      if (mounted) {
        setState(() {
          _isFetchingFare = false;
          _fareError =
              'Failed to calculate fare. Please check your connection and try again.';
        });
      }
    }
  }

  /// Retry fetching fare after an error
  void _retryFetchFare() {
    _fetchDirectionsAndFare();
  }

  Map<String, dynamic> get _currentFareData =>
      _dynamicFareData ?? widget.fareData;

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
    // Proceed with Pay Later (Auth now, charge later) by default
    _processBooking(PaymentTiming.payLater);

    /* Original Pay Now / Pay Later selection logic - Commented for future iteration
    // Show payment choice popup
    final PaymentTiming?
    selectedTiming = await showModalBottomSheet<PaymentTiming>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Choose Payment Option',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 24),

              // Pay Now Option
              _buildPopupOption(
                context,
                title: 'Pay Now',
                subtitle:
                    'Pay £${_fare.toStringAsFixed(2)} immediately via Stripe',
                icon: Icons.flash_on,
                color: Colors.orange,
                value: PaymentTiming.payNow,
              ),

              const SizedBox(height: 12),

              // Pay Later Option
              _buildPopupOption(
                context,
                title: 'Pay After Ride',
                subtitle: 'Authorize card now, charge after completion',
                icon: Icons.schedule,
                color: Colors.blue,
                value: PaymentTiming.payLater,
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: Text(
                  'Your payment is securely processed by Stripe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selectedTiming != null) {
      _processBooking(selectedTiming);
    }
    */
  }

  /* Commented out for now - used in _confirmRide's bottom sheet
  Widget _buildPopupOption(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required PaymentTiming value,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(context, value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[200]!),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
  */

  Future<void> _processBooking(PaymentTiming timing) async {
    debugPrint(
      '🚀 RideConfirmationScreen: Processing booking with timing: $timing',
    );
    setState(() {
      _paymentTiming = timing;
      _isLoading = true;
    });

    try {
      final distanceMiles =
          _currentFareData['distance_miles'] ??
          ((_currentFareData['distance_meters'] ?? 0) * 0.000621371);

      // Use PaymentService to handle both API call and Stripe payment sheet
      final result = await PaymentService.bookRideWithPayment(
        context: context,
        pickupLocation: widget.pickupLocation,
        dropoffLocation: widget.dropoffLocation,
        vehicleType: widget.vehicleType,
        distance: (distanceMiles as num).toDouble(),
        fare: _fare,
        paymentTiming: timing,
      );

      if (mounted) {
        setState(() => _isLoading = false);

        if (result.success) {
          debugPrint(
            '🏠 RideConfirmationScreen: Ride confirmed, returning to Home with searching state',
          );
          // Pop and pass the ride data back to Home Screen
          Navigator.of(
            context,
          ).pop({
            'status': 'searching',
            'ride': result.data,
            'confirmationData': {
              'pickupLocation': widget.pickupLocation,
              'dropoffLocation': widget.dropoffLocation,
              'vehicleType': widget.vehicleType,
              'vehicleName': widget.vehicleName,
              'fareData': widget.fareData,
              'polyline': widget.polyline,
            },
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'Failed to book ride'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ RideConfirmationScreen: Error scaling booking: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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

  /// Build a static map snapshot showing the route from pickup to dropoff
  Widget _buildMapSnapshot() {
    final pickupCoords = widget.pickupLocation['coordinates'] as List;
    final dropoffCoords = widget.dropoffLocation['coordinates'] as List;

    debugPrint('🗺️ RideConfirmationScreen: Building static map snapshot');
    debugPrint('   → Route points: ${_routePoints.length}');

    final markers = [
      MapMarker(
        id: 'pickup',
        lat: pickupCoords[1],
        lng: pickupCoords[0],
        title: 'Pickup',
        markerColor: Colors.green, // Green marker for pickup
      ),
      MapMarker(
        id: 'dropoff',
        lat: dropoffCoords[1],
        lng: dropoffCoords[0],
        title: 'Dropoff',
        markerColor: Colors.red, // Red marker for dropoff
      ),
    ];

    return Container(
      height: 200, // Slightly taller for better visibility
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
          polylines: _routePoints.isNotEmpty
              ? [
                  MapPolyline(
                    id: 'route_confirmation',
                    points: _routePoints,
                    color: AppTheme.primaryColor,
                    width: 5.0, // Thicker line
                  ),
                ]
              : [],
          bounds: _routeBounds,
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
            Icons.straighten,
            'Distance',
            _isFetchingFare ? '...' : _distanceText,
          ),
          const Divider(height: 24),
          _buildDetailRow(
            Icons.access_time,
            'Duration',
            _isFetchingFare ? '...' : _durationText,
          ),
          const Divider(height: 24),
          _buildDetailRow(
            Icons.schedule,
            'ETA',
            _isFetchingFare ? '...' : _estimatedArrival,
          ),
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
            'Payment Method',
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
                child: const Icon(
                  Icons.credit_card,
                  color: AppTheme.primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Stripe Secure Payment',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      _paymentTiming == PaymentTiming.payNow
                          ? 'Pay Now'
                          : 'Pay After Ride',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Icon(Icons.lock_outline, color: Colors.grey[400], size: 18),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    // Check if there's a fare error
    final hasError = _fareError != null;

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
            // Error Message (if any)
            if (hasError) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.red.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _fareError!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Fare Row (only show if no error)
            if (!hasError)
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

            if (!hasError) const SizedBox(height: 16),

            // Button Row
            SizedBox(
              width: double.infinity,
              height: 54,
              child: hasError
                  ? ElevatedButton.icon(
                      onPressed: _isFetchingFare ? null : _retryFetchFare,
                      icon: _isFetchingFare
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(
                        _isFetchingFare ? 'Retrying...' : 'Retry',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    )
                  : ElevatedButton(
                      onPressed: (_isLoading || _isFetchingFare)
                          ? null
                          : _confirmRide,
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
