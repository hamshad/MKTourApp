import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import '../../core/theme.dart';
import '../../core/api_service.dart';
import '../../core/services/socket_service.dart';
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
  String _rideStatus = 'searching';
  
  final LatLng _userLocation = const LatLng(51.5074, -0.1278);
  LatLng _driverLocation = const LatLng(51.5080, -0.1280); // Mutable to update

  // Driver Data
  Map<String, dynamic> _driver = {};
  String _otp = '';

  @override
  void initState() {
    super.initState();
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    // Ensure socket is connected
    _socketService.initSocket();

    // Listen for ride acceptance
    _socketService.on('ride:accepted', (data) {
      if (mounted) {
        debugPrint('🚗 [RideAssignedScreen] Ride Accepted: $data');
        setState(() {
          _rideStatus = 'driver_assigned';
          _driver = data['driver'] ?? {};
          _otp = data['otp'] ?? ''; // Assuming OTP comes in this event or we have it from booking
          // Update driver location if provided
          if (data['driver']?['location'] != null) {
            final coords = data['driver']['location']['coordinates'];
            _driverLocation = LatLng(coords[1], coords[0]);
          }
        });
      }
    });

    // Listen for driver location updates
    _socketService.on('driver:locationChanged', (data) {
      if (mounted && (_rideStatus == 'driver_assigned' || _rideStatus == 'in_progress')) {
        debugPrint('📍 [RideAssignedScreen] Driver Location Updated: $data');
        setState(() {
          final coords = data['location']['coordinates'];
          _driverLocation = LatLng(coords[1], coords[0]);
        });
      }
    });

    // Listen for ride start
    _socketService.on('ride:started', (data) {
      if (mounted) {
        debugPrint('🚀 [RideAssignedScreen] Ride Started');
        setState(() {
          _rideStatus = 'in_progress';
        });
      }
    });

    // Listen for ride completion
    _socketService.on('ride:completed', (data) {
      if (mounted) {
        debugPrint('✅ [RideAssignedScreen] Ride Completed');
        setState(() {
          _rideStatus = 'completed';
        });
      }
    });
  }

  @override
  void dispose() {
    // Clean up listeners if needed, or rely on SocketService to handle it
    // _socketService.off('ride:accepted'); // Optional: implement off in SocketService if strict cleanup needed
    super.dispose();
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
      default:
        return 'Connecting...';
    }
  }

  @override
  Widget build(BuildContext context) {
    // If ride is completed, show completion screen
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
          // Map
          FlutterMap(
            options: MapOptions(
              initialCenter: _userLocation,
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.skyline',
              ),
              MarkerLayer(
                markers: [
                  // User location
                  Marker(
                    point: _userLocation,
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                  // Driver location (only if assigned)
                  if (_rideStatus != 'searching')
                    Marker(
                      point: _driverLocation,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.local_taxi, size: 40, color: Colors.black),
                    ),
                ],
              ),
            ],
          ),

          // Status Banner
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (_rideStatus == 'searching')
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _rideStatus == 'driver_arrived' 
                            ? Colors.green.withValues(alpha: 0.1)
                            : Theme.of(context).primaryColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _rideStatus == 'driver_arrived' ? Icons.location_on : Icons.directions_car,
                        color: _rideStatus == 'driver_arrived' ? Colors.green : Theme.of(context).primaryColor,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getStatusText(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (_rideStatus == 'driver_assigned')
                          Text(
                            'Arriving in 5 mins',
                            style: TextStyle(color: AppTheme.textSecondary),
                          )
                        else if (_rideStatus == 'in_progress')
                          Text(
                            'Heading to destination',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Driver Card (only if assigned)
          if (_rideStatus != 'searching')
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
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
                  if (_rideStatus == 'driver_arrived')
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.notifications_active, size: 16, color: Colors.green),
                          SizedBox(width: 8),
                          Text(
                            'Driver is waiting at pickup point',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  
                  // OTP Display
                  if (_otp.isNotEmpty && _rideStatus == 'driver_assigned')
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('OTP: ', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            _otp,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accentColor,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
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
                          child: const Icon(Icons.phone, color: Colors.green, size: 20),
                        ),
                        onPressed: () {
                          // Call driver (mock)
                        },
                      ),
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.message, color: Theme.of(context).primaryColor, size: 20),
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
                      _buildInfoColumn('Vehicle', _driver['vehicle']?['model'] ?? 'Car'),
                      _buildInfoColumn('Plate', _driver['vehicle']?['number'] ?? '---'),
                      _buildInfoColumn('Color', _driver['vehicle']?['color'] ?? '---'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Simulation button removed
        ],
      ),
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
