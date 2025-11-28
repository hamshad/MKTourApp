import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import '../../core/theme.dart';
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
  // final ApiService _apiService = ApiService();
  String _rideStatus = 'searching';
  Timer? _statusTimer;
  
  final LatLng _userLocation = const LatLng(51.5074, -0.1278);
  final LatLng _driverLocation = const LatLng(51.5080, -0.1280);

  // Mock Driver Data
  final Map<String, dynamic> _driver = {
    'name': 'John Doe',
    'vehicle': 'Toyota Prius',
    'plate': 'AB12 CDE',
    'rating': 4.8
  };

  @override
  void initState() {
    super.initState();
    // Poll for status updates every 3 seconds
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _updateRideStatus();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _updateRideStatus() async {
    // In a real app, we would fetch status from API
    // final status = await _apiService.getRideStatus(widget.rideId);
    // if (mounted && status['status'] != null) {
    //   setState(() {
    //     _rideStatus = status['status'];
    //   });
    // }
  }

  void _simulateNextStatus() {
    setState(() {
      switch (_rideStatus) {
        case 'searching':
          _rideStatus = 'driver_assigned';
          break;
        case 'driver_assigned':
          _rideStatus = 'driver_arrived';
          break;
        case 'driver_arrived':
          _rideStatus = 'in_progress';
          break;
        case 'in_progress':
          _rideStatus = 'completed';
          break;
      }
    });
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
                  
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Theme.of(context).primaryColor,
                        child: Text(
                          _driver['name'][0],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _driver['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            Row(
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 16),
                                const SizedBox(width: 4),
                                Text('${_driver['rating']}'),
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
                                  _driver['vehicle'],
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
                      _buildInfoColumn('Vehicle', _driver['vehicle']),
                      _buildInfoColumn('Plate', _driver['plate']),
                      _buildInfoColumn('Color', 'White'), // Mock color
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Debug Simulation Button
          Positioned(
            bottom: 200,
            right: 16,
            child: FloatingActionButton.extended(
              onPressed: _simulateNextStatus,
              label: const Text('Simulate'),
              icon: const Icon(Icons.play_arrow),
              backgroundColor: Colors.orange,
            ),
          ),
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
