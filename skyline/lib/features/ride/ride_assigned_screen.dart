import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import '../../core/theme.dart';
import '../../core/api_service.dart';

class RideAssignedScreen extends StatefulWidget {
  const RideAssignedScreen({super.key});

  @override
  State<RideAssignedScreen> createState() => _RideAssignedScreenState();
}

class _RideAssignedScreenState extends State<RideAssignedScreen> {
  final ApiService _apiService = ApiService();
  String _rideStatus = 'driver_assigned';
  Timer? _statusTimer;
  
  final LatLng _userLocation = const LatLng(51.5074, -0.1278);
  final LatLng _driverLocation = const LatLng(51.5080, -0.1280);

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
    final status = await _apiService.getRideStatus();
    if (mounted && status['status'] != null) {
      setState(() {
        _rideStatus = status['status'];
      });
    }
  }

  String _getStatusText() {
    switch (_rideStatus) {
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
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final driver = args?['driver'] ?? {'name': 'John Doe', 'vehicle': 'Toyota Prius', 'plate': 'AB12 CDE', 'rating': 4.8};
    final eta = args?['eta'] ?? '5 mins';
    final fare = args?['fare'] ?? 15.50;

    // If ride is completed, show completion screen
    if (_rideStatus == 'completed') {
      return _buildCompletionScreen(fare);
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
                  // Driver location
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
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _rideStatus == 'driver_arrived' ? Icons.flag : Icons.directions_car,
                      color: Theme.of(context).primaryColor,
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
                            'Arriving in $eta',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Driver Card
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Theme.of(context).primaryColor,
                        child: Text(
                          driver['name'][0],
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
                              driver['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            Row(
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 16),
                                const SizedBox(width: 4),
                                Text('${driver['rating']}'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.phone, color: Colors.green),
                        onPressed: () {
                          // Call driver (mock)
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.message, color: Theme.of(context).primaryColor),
                        onPressed: () {
                          // Message driver (mock)
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vehicle',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                          Text(
                            driver['vehicle'],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Plate Number',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                          Text(
                            driver['plate'],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_rideStatus == 'driver_arrived') ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() => _rideStatus = 'in_progress');
                        },
                        child: const Text('Start Trip'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionScreen(double fare) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  size: 80,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Trip Completed',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Thank you for riding with us!',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Fare', style: TextStyle(fontSize: 18)),
                    Text(
                      '£${fare.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                  },
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
