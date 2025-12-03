import 'package:flutter/material.dart';
import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
import '../../core/services/socket_service.dart';
import '../../core/services/socket_service.dart';
import '../../core/api_service.dart';
import 'ride_complete_screen.dart';

class RideAssignedScreen extends StatefulWidget {
  final String rideId;
  final Map<String, dynamic>? pickup;
  final Map<String, dynamic>? dropoff;
  final double fare;

  const RideAssignedScreen({
    super.key,
    required this.rideId,
    this.pickup,
    this.dropoff,
    this.fare = 15.50,
  });

  @override
  State<RideAssignedScreen> createState() => _RideAssignedScreenState();
}

class _RideAssignedScreenState extends State<RideAssignedScreen> {
  final SocketService _socketService = SocketService();
  final ApiService _apiService = ApiService();
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

  @override
  void initState() {
    super.initState();
    _initializeLocations();
    _setupSocketListeners();
  }

  void _initializeLocations() {
    // Default to London if not provided (mock)
    final pickupCoords = widget.pickup?['coordinates'] ??
        [51.5074, -0.1278]; // Lat, Lng
    final dropoffCoords = widget.dropoff?['coordinates'] ??
        [51.509865, -0.118092];

    // Handle different coordinate formats if necessary (e.g. [lng, lat] from mongo vs [lat, lng])
    // Assuming [lat, lng] for now based on previous code usage, but standard GeoJSON is [lng, lat].
    // Let's stick to what was likely working or standard mock:
    _userLocation = LatLng(pickupCoords[0], pickupCoords[1]);
    _pickupLocation = LatLng(pickupCoords[0], pickupCoords[1]);
    _dropoffLocation = LatLng(dropoffCoords[0], dropoffCoords[1]);

    _updateAnnotations();
  }

  void _setupSocketListeners() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    debugPrint('🔌 [RideAssignedScreen] Initializing socket listeners...');

    _socketService.initSocket().then((_) {
      if (user != null) {
        debugPrint(
            '📤 [RideAssignedScreen] Emitting user:goOnline for user: ${user['_id']}');
        _socketService.emit('user:goOnline', {'userId': user['_id']});
      } else {
        debugPrint(
            '⚠️ [RideAssignedScreen] User is null, cannot emit user:goOnline');
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

          if (data['driver']?['location'] != null) {
            final coords = data['driver']['location']['coordinates'];
            _driverLocation = LatLng(coords[1], coords[0]);
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
        setState(() {
          final coords = data['location']['coordinates'];
          _driverLocation = LatLng(coords[1], coords[0]);
          _updateAnnotations();
        });
      }
    });

    _socketService.on('ride:started', (data) {
      if (mounted) {
        debugPrint('🚀 [RideAssignedScreen] Ride Started: $data');
        setState(() {
          _rideStatus = 'in_progress';
          _updateAnnotations();
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
            content: const Text('Your ride request has expired. Please try again.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Go back to previous screen (likely home)
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
  Widget build(BuildContext context) {
    if (_rideStatus == 'completed') {
      return RideCompleteScreen(rideData: {
        'bookingId': widget.rideId,
        'driver': _driver,
        'fare': widget.fare,
      });
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
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildStatusPanel(),
          ),
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
            _buildLocationRow(Icons.my_location, 'Pickup',
                widget.pickup?['address'] ?? 'Current Location'),
            const SizedBox(height: 16),
            _buildLocationRow(Icons.location_on, 'Dropoff',
                widget.dropoff?['address'] ?? 'Destination'),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Estimated Fare: £${widget.fare.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                // Text('Distance: 5.2 km'), // Mock distance for now
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  // Cancel logic with reason
                  _apiService.cancelRide(widget.rideId, reason: "user_cancelled");
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.close),
                label: const Text('Cancel Request'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ] else
            ...[
              // Driver Assigned / In Progress UI
              if (_rideStatus == 'driver_arrived')
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.notifications_active, size: 16,
                          color: Colors.green),
                      SizedBox(width: 8),
                      Text(
                        'Driver is waiting at pickup point',
                        style: TextStyle(
                            color: Colors.green, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),

              // OTP Display
              if (_otp.isNotEmpty && _rideStatus == 'driver_assigned')
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.accentColor.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      const Text('Share OTP with Driver', 
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('OTP: ',
                              style: TextStyle(fontWeight: FontWeight.bold)),
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
              if (_otp.isNotEmpty && _rideStatus == 'driver_assigned')
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
                    backgroundColor: Theme
                        .of(context)
                        .primaryColor,
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
                            const Icon(
                                Icons.star, color: Colors.amber, size: 16),
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
                          Icons.phone, color: Colors.green, size: 20),
                    ),
                    onPressed: () {
                      // Call driver (mock)
                    },
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme
                            .of(context)
                            .primaryColor
                            .withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.message, color: Theme
                          .of(context)
                          .primaryColor, size: 20),
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
                      'Vehicle', _driver['vehicle']?['model'] ?? 'Car'),
                  _buildInfoColumn(
                      'Plate', _driver['vehicle']?['number'] ?? '---'),
                  _buildInfoColumn(
                      'Color', _driver['vehicle']?['color'] ?? '---'),
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
              Text(label, style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12)),
              Text(address, style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
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
