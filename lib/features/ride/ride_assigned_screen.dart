import 'package:flutter/material.dart';
import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
import '../../core/services/socket_service.dart';
import '../../core/api_service.dart';
import '../../core/services/navigation_service.dart';
import '../../core/services/places_service.dart';
import '../../core/services/marker_interpolation_service.dart';
import 'ride_complete_screen.dart';

class RideAssignedScreen extends StatefulWidget {
  final String rideId;
  final Map<String, dynamic>? pickup;
  final Map<String, dynamic>? dropoff;
  final double fare;
  final Map<String, dynamic>? driver; // Added initial driver data

  const RideAssignedScreen({
    super.key,
    required this.rideId,
    this.pickup,
    this.dropoff,
    this.fare = 15.50,
    this.driver,
  });

  @override
  State<RideAssignedScreen> createState() => _RideAssignedScreenState();
}

class _RideAssignedScreenState extends State<RideAssignedScreen> {
  final SocketService _socketService = SocketService();
  final ApiService _apiService = ApiService();
  final NavigationService _navigationService = NavigationService();
  final PlacesService _placesService = PlacesService();
  String _rideStatus = 'searching';

  // Locations
  late LatLng _userLocation;
  LatLng? _driverLocation;
  late LatLng _pickupLocation;
  late LatLng _dropoffLocation;

  // Map Controller
  AppleMapController? _mapController;

  // Map Elements
  Set<Annotation> _annotations = {};
  Set<Polyline> _polylines = {};

  // Driver Data
  Map<String, dynamic> _driver = {};
  String _otp = '';
  String? _currentDriverId; // Track current driver ID for room management

  // Detailed Addresses
  String _pickupAddress = '';
  String _dropoffAddress = '';

  // Navigation State
  NavigationState? _navigationState;

  // Marker Interpolation for smooth car animation
  MarkerInterpolationService? _markerInterpolation;
  StreamSubscription<InterpolatedPosition>? _interpolationSubscription;
  double _driverBearing = 0.0; // Current bearing for car rotation

  // Connection status subscription
  StreamSubscription<bool>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _initializeLocations();
    _setupInitialState();
    _setupSocketListeners();
    _setupConnectionListener();
    _fetchDetailedAddresses();
    _setupNavigationListener();
  }

  void _setupInitialState() {
    if (widget.driver != null) {
      _rideStatus = 'driver_assigned';
      _driver = widget.driver!;
      _otp = widget.driver!['otp'] ?? widget.driver!['verificationOTP'] ?? '';

      // Extract driver ID and join their location room
      _currentDriverId =
          _driver['_id']?.toString() ?? _driver['id']?.toString();
      if (_currentDriverId != null) {
        _socketService.joinDriverRoom(_currentDriverId!);
      }

      if (_driver['location'] != null) {
        final coords = _driver['location']['coordinates'];
        _driverLocation = LatLng(coords[1], coords[0]);

        // Initialize marker interpolation with driver's initial position
        _initMarkerInterpolation(latlong2.LatLng(coords[1], coords[0]));
      }
    }
  }

  /// Initialize the marker interpolation service for smooth car animation
  void _initMarkerInterpolation(latlong2.LatLng initialPosition) {
    _markerInterpolation?.dispose();
    _interpolationSubscription?.cancel();

    _markerInterpolation = MarkerInterpolationService(
      initialPosition: initialPosition,
      interpolationDurationMs: 2000, // 2 second smooth animation
    );

    // Listen to interpolated positions and update the marker
    _interpolationSubscription = _markerInterpolation!.positionStream.listen((
      interpolated,
    ) {
      if (mounted) {
        setState(() {
          _driverLocation = LatLng(
            interpolated.position.latitude,
            interpolated.position.longitude,
          );
          _driverBearing = interpolated.bearing;
          _updateAnnotations();
        });
      }
    });

    debugPrint('🚗 [RideAssignedScreen] Marker interpolation initialized');
  }

  /// Setup listener for connection status changes (reconnection handling)
  void _setupConnectionListener() {
    _connectionSubscription = _socketService.connectionStatus.listen((
      isConnected,
    ) {
      if (isConnected && _currentDriverId != null) {
        // Rejoin driver room on reconnection
        debugPrint(
          '🔄 [RideAssignedScreen] Reconnected, rejoining driver room',
        );
        _socketService.joinDriverRoom(_currentDriverId!);
      }
    });
  }

  void _initializeLocations() {
    // Use provided coordinates or default to 0,0 (will be updated by socket/map fit)
    final pickupCoords = widget.pickup?['coordinates'] ?? [0.0, 0.0];
    final dropoffCoords = widget.dropoff?['coordinates'] ?? [0.0, 0.0];

    // MongoDB GeoJSON is [lng, lat], but we need to be careful.
    // Based on DestinationSearchScreen, we are passing [lng, lat].
    // LatLng takes (lat, lng).

    if (widget.pickup != null) {
      _userLocation = LatLng(pickupCoords[1], pickupCoords[0]);
      _pickupLocation = LatLng(pickupCoords[1], pickupCoords[0]);
    } else {
      _userLocation = const LatLng(0, 0);
      _pickupLocation = const LatLng(0, 0);
    }

    if (widget.dropoff != null) {
      _dropoffLocation = LatLng(dropoffCoords[1], dropoffCoords[0]);
    } else {
      _dropoffLocation = const LatLng(0, 0);
    }

    _updateAnnotations();
  }

  /// Fetch detailed addresses for pickup and dropoff
  Future<void> _fetchDetailedAddresses() async {
    if (widget.pickup != null) {
      final address = await _placesService.getAddressFromLatLng(
        _pickupLocation.latitude,
        _pickupLocation.longitude,
      );
      if (mounted) {
        setState(() {
          _pickupAddress =
              address ?? widget.pickup?['address'] ?? 'Pickup Location';
        });
      }
    }

    if (widget.dropoff != null) {
      final address = await _placesService.getAddressFromLatLng(
        _dropoffLocation.latitude,
        _dropoffLocation.longitude,
      );
      if (mounted) {
        setState(() {
          _dropoffAddress =
              address ?? widget.dropoff?['address'] ?? 'Dropoff Location';
        });
      }
    }
  }

  /// Setup navigation listener for route updates
  void _setupNavigationListener() {
    _navigationService.routeUpdates.listen((state) {
      if (mounted) {
        setState(() {
          _navigationState = state;
          _updatePolylines();
        });
      }
    });
  }

  void _setupSocketListeners() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    debugPrint('🔌 [RideAssignedScreen] Initializing socket listeners...');

    _socketService.initSocket().then((_) {
      if (user != null) {
        debugPrint(
          '📤 [RideAssignedScreen] Emitting user:goOnline for user: ${user['_id']}',
        );
        _socketService.emit('user:goOnline', {'userId': user['_id']});
      } else {
        debugPrint(
          '⚠️ [RideAssignedScreen] User is null, cannot emit user:goOnline',
        );
      }
    });

    _socketService.on('user:status', (data) {
      debugPrint('📩 [RideAssignedScreen] User status: ${data['status']}');
    });

    _socketService.on('ride:accepted', (data) {
      if (mounted) {
        debugPrint('✅ [RideAssignedScreen] Ride Accepted: $data');
        setState(() {
          _rideStatus = 'driver_assigned';
          _driver = data['driver'] ?? {};
          _otp = data['otp'] ?? data['verificationOTP'] ?? '';

          // Extract driver ID and join their location room for real-time updates
          _currentDriverId =
              _driver['_id']?.toString() ?? _driver['id']?.toString();
          if (_currentDriverId != null) {
            _socketService.joinDriverRoom(_currentDriverId!);
            debugPrint(
              '🚗 [RideAssignedScreen] Joined driver room: driver:$_currentDriverId',
            );
          }

          if (data['driver']?['location'] != null) {
            final coords = data['driver']['location']['coordinates'];
            _driverLocation = LatLng(coords[1], coords[0]);

            // Initialize marker interpolation for smooth car animation
            _initMarkerInterpolation(latlong2.LatLng(coords[1], coords[0]));

            // Fetch navigation route from driver to pickup
            _fetchNavigationRoute();
          }
          _updateAnnotations();
          _fitBounds();
        });
      }
    });

    _socketService.on('driver:locationChanged', (data) {
      debugPrint('📍 [RideAssignedScreen] Driver Location Updated: $data');
      if (mounted &&
          (_rideStatus == 'driver_assigned' || _rideStatus == 'in_progress')) {
        // Use marker interpolation for smooth animation instead of direct update
        if (data['location']?['coordinates'] != null) {
          final coords = data['location']['coordinates'];
          final newPosition = latlong2.LatLng(coords[1], coords[0]);

          if (_markerInterpolation != null) {
            // Smooth interpolation to new position
            _markerInterpolation!.updatePosition(newPosition);
          } else {
            // Fallback: initialize interpolation if not set up
            _initMarkerInterpolation(newPosition);
          }

          // Update navigation route in real-time (don't need to update annotations here,
          // the interpolation stream handles that)
          _updateNavigationRoute();
        }
      }
    });

    _socketService.on('ride:started', (data) {
      if (mounted) {
        debugPrint('🚀 [RideAssignedScreen] Ride Started: $data');
        setState(() {
          _rideStatus = 'in_progress';
          _updateAnnotations();
          // Switch to navigation from current to dropoff
          _fetchNavigationRoute();
          _fitBounds();
        });
      }
    });

    _socketService.on('ride:completed', (data) {
      if (mounted) {
        debugPrint('🏁 [RideAssignedScreen] Ride Completed: $data');
        setState(() {
          _rideStatus = 'completed';
        });
      }
    });

    _socketService.on('ride:driverArrived', (data) {
      if (mounted) {
        debugPrint('🚖 [RideAssignedScreen] Driver Arrived: $data');
        setState(() {
          _rideStatus = 'driver_arrived';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver has arrived!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });

    _socketService.on('ride:otpExpired', (data) {
      if (mounted) {
        debugPrint('🔄 [RideAssignedScreen] OTP Expired: $data');
        setState(() {
          _otp = data['newOTP'] ?? _otp;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New OTP: $_otp'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    });

    _socketService.on('ride:cancelled', (data) {
      if (mounted) {
        debugPrint('❌ [RideAssignedScreen] Ride Cancelled: $data');
        final reason = data['reason'] ?? 'Unknown reason';
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Ride Cancelled'),
            content: Text('The ride was cancelled.\nReason: $reason'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Go back
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });

    _socketService.on('ride:expired', (data) {
      if (mounted) {
        debugPrint('⚠️ [RideAssignedScreen] Ride Expired: $data');
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Ride Expired'),
            content: const Text(
              'Your ride request has expired. Please try again.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(
                    context,
                  ); // Go back to previous screen (likely home)
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });

    _socketService.on('ride:longRunning', (data) {
      if (mounted) {
        debugPrint('⏳ [RideAssignedScreen] Ride Long Running: $data');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your ride is taking longer than expected...'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });
  }

  void _updateAnnotations() {
    final Set<Annotation> newAnnotations = {};

    // Pickup Marker (User)
    newAnnotations.add(
      Annotation(
        annotationId: AnnotationId('pickup'),
        position: _pickupLocation,
        icon: BitmapDescriptor.defaultAnnotation,
        infoWindow: const InfoWindow(title: 'Pickup'),
      ),
    );

    // Dropoff Marker
    if (_rideStatus == 'in_progress') {
      newAnnotations.add(
        Annotation(
          annotationId: AnnotationId('dropoff'),
          position: _dropoffLocation,
          icon: BitmapDescriptor.defaultAnnotation,
          infoWindow: const InfoWindow(title: 'Dropoff'),
        ),
      );
    }

    // Driver Marker
    if (_driverLocation != null && _rideStatus != 'searching') {
      newAnnotations.add(
        Annotation(
          annotationId: AnnotationId('driver'),
          position: _driverLocation!,
          icon: BitmapDescriptor.defaultAnnotation,
          infoWindow: InfoWindow(title: _driver['name'] ?? 'Driver'),
        ),
      );
    }

    setState(() {
      _annotations = newAnnotations;
    });
  }

  /// Fetch navigation route based on current ride status
  Future<void> _fetchNavigationRoute() async {
    if (_driverLocation == null) return;

    LatLng origin = _driverLocation!;
    LatLng destination;

    if (_rideStatus == 'driver_assigned' || _rideStatus == 'driver_arrived') {
      // Driver navigating to pickup
      destination = _pickupLocation;
    } else if (_rideStatus == 'in_progress') {
      // Driver navigating to dropoff
      destination = _dropoffLocation;
    } else {
      return;
    }

    await _navigationService.fetchRoute(
      originLat: origin.latitude,
      originLng: origin.longitude,
      destLat: destination.latitude,
      destLng: destination.longitude,
    );
  }

  /// Update navigation route in real-time
  Future<void> _updateNavigationRoute() async {
    if (_driverLocation == null) return;

    LatLng destination;

    if (_rideStatus == 'driver_assigned' || _rideStatus == 'driver_arrived') {
      destination = _pickupLocation;
    } else if (_rideStatus == 'in_progress') {
      destination = _dropoffLocation;
    } else {
      return;
    }

    await _navigationService.updateRoute(
      currentLat: _driverLocation!.latitude,
      currentLng: _driverLocation!.longitude,
      destLat: destination.latitude,
      destLng: destination.longitude,
    );
  }

  /// Update polylines with navigation route
  void _updatePolylines() {
    final Set<Polyline> newPolylines = {};

    if (_navigationState != null && _navigationState!.polyline.isNotEmpty) {
      // Convert LatLng to Apple Maps LatLng format
      final points = _navigationState!.polyline
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();

      newPolylines.add(
        Polyline(
          polylineId: PolylineId('navigation_route'),
          points: points,
          color: AppTheme.primaryColor,
          width: 5,
        ),
      );
    }

    setState(() {
      _polylines = newPolylines;
    });
  }

  void _fitBounds() {
    if (_mapController == null) return;

    List<LatLng> points = [_pickupLocation];
    if (_driverLocation != null) points.add(_driverLocation!);
    if (_rideStatus == 'in_progress') points.add(_dropoffLocation);

    if (points.length > 1) {
      double minLat = points.first.latitude;
      double maxLat = points.first.latitude;
      double minLng = points.first.longitude;
      double maxLng = points.first.longitude;

      for (var point in points) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }

      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          50.0,
        ),
      );
    }
  }

  String _getStatusText() {
    switch (_rideStatus) {
      case 'searching':
        return 'Finding your driver...';
      case 'driver_assigned':
        return 'Driver is on the way';
      case 'driver_arrived':
        return 'Driver has arrived';
      case 'in_progress':
        return 'Trip in progress';
      case 'completed':
        return 'Trip completed';
      case 'expired':
        return 'Ride expired';
      default:
        return 'Connecting...';
    }
  }

  @override
  void dispose() {
    // Clean up marker interpolation
    _interpolationSubscription?.cancel();
    _markerInterpolation?.dispose();

    // Clean up connection listener
    _connectionSubscription?.cancel();

    // Leave driver room if we were tracking one
    if (_currentDriverId != null) {
      _socketService.leaveDriverRoom(_currentDriverId!);
    }

    // Clean up socket listeners
    _socketService.off('ride:accepted');
    _socketService.off('driver:locationChanged');
    _socketService.off('ride:started');
    _socketService.off('ride:completed');
    _socketService.off('ride:driverArrived');
    _socketService.off('ride:otpExpired');
    _socketService.off('ride:cancelled');
    _socketService.off('ride:expired');
    _socketService.off('ride:longRunning');
    _socketService.off('user:status');

    // Clean up navigation
    _navigationService.dispose();

    debugPrint('🔴 [RideAssignedScreen] Disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_rideStatus == 'completed') {
      return RideCompleteScreen(
        rideData: {
          'bookingId': widget.rideId,
          'driver': _driver,
          'fare': widget.fare,
        },
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          AppleMap(
            initialCameraPosition: CameraPosition(
              target: _userLocation,
              zoom: 14.0,
            ),
            annotations: _annotations,
            polylines: _polylines,
            onMapCreated: (controller) {
              _mapController = controller;
              if (_rideStatus != 'searching') {
                _fitBounds();
              }
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
          ),

          // Status Panel
          Positioned(bottom: 0, left: 0, right: 0, child: _buildStatusPanel()),
        ],
      ),
    );
  }

  Widget _buildStatusPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_rideStatus == 'searching') ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text(
              'Finding Nearby Drivers...',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Searching for drivers near you...'),
            const SizedBox(height: 24),
            _buildLocationRow(
              Icons.my_location,
              'Pickup',
              _pickupAddress.isNotEmpty
                  ? _pickupAddress
                  : (widget.pickup?['address'] ?? 'Current Location'),
            ),
            const SizedBox(height: 16),
            _buildLocationRow(
              Icons.location_on,
              'Dropoff',
              _dropoffAddress.isNotEmpty
                  ? _dropoffAddress
                  : (widget.dropoff?['address'] ?? 'Destination'),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Estimated Fare: £${widget.fare.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                // Text('Distance: 5.2 km'), // Mock distance for now
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  // Cancel logic with reason
                  _apiService.cancelRide(
                    widget.rideId,
                    reason: "user_cancelled",
                  );
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.close),
                label: const Text('Cancel Request'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ] else ...[
            // Driver Assigned / In Progress UI
            if (_rideStatus == 'driver_arrived')
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.notifications_active,
                      size: 16,
                      color: Colors.green,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Driver is waiting at pickup point',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

            // OTP Display
            if (_otp.isNotEmpty &&
                (_rideStatus == 'driver_assigned' ||
                    _rideStatus == 'driver_arrived'))
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.accentColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Share OTP with Driver',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'OTP: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _otp,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accentColor,
                            letterSpacing: 4,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // Large OTP Display Dialog Trigger (Optional, or auto-show)
            if (_otp.isNotEmpty &&
                (_rideStatus == 'driver_assigned' ||
                    _rideStatus == 'driver_arrived'))
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Center(
                  child: Text(
                    'Share OTP with Driver',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              ),

            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Theme.of(context).primaryColor,
                  backgroundImage: _driver['profilePicture'] != null
                      ? NetworkImage(_driver['profilePicture'])
                      : null,
                  child: _driver['profilePicture'] == null
                      ? Text(
                          (_driver['name'] ?? 'D')[0],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _driver['name'] ?? 'Driver',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text('${_driver['rating'] ?? 5.0}'),
                          const SizedBox(width: 8),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _driver['vehicle']?['model'] ?? 'Car',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.phone,
                      color: Colors.green,
                      size: 20,
                    ),
                  ),
                  onPressed: () {
                    // Call driver (mock)
                  },
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.message,
                      color: Theme.of(context).primaryColor,
                      size: 20,
                    ),
                  ),
                  onPressed: () {
                    // Message driver (mock)
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoColumn(
                  'Vehicle',
                  _driver['vehicle']?['model'] ?? 'Car',
                ),
                _buildInfoColumn(
                  'Plate',
                  _driver['vehicle']?['number'] ?? '---',
                ),
                _buildInfoColumn(
                  'Color',
                  _driver['vehicle']?['color'] ?? '---',
                ),
              ],
            ),
            if (_rideStatus == 'in_progress') ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Emergency logic
                  },
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('Emergency / Help'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, String label, String address) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              Text(
                address,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ],
    );
  }
}
