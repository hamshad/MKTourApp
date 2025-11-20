import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme.dart';

class RideProgressScreen extends StatefulWidget {
  const RideProgressScreen({super.key});

  @override
  State<RideProgressScreen> createState() => _RideProgressScreenState();
}

class _RideProgressScreenState extends State<RideProgressScreen> {
  String _status = 'Finding your driver...';
  double _progress = 0.2;
  
  @override
  void initState() {
    super.initState();
    _simulateRideProgress();
  }
  
  void _simulateRideProgress() async {
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() { _status = 'Driver is on the way'; _progress = 0.4; });
    
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() { _status = 'Driver has arrived'; _progress = 0.6; });
    
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() { _status = 'Heading to destination'; _progress = 0.8; });
    
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() { _status = 'You have arrived!'; _progress = 1.0; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map
          FlutterMap(
            options: MapOptions(
              initialCenter: const LatLng(51.5085, -0.1260),
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.skyline',
              ),
              MarkerLayer(
                markers: [
                  const Marker(
                    point: LatLng(51.5074, -0.1278),
                    width: 30,
                    height: 30,
                    child: Icon(Icons.local_taxi, color: Colors.black, size: 30),
                  ),
                ],
              ),
            ],
          ),
          
          // Status Panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  
                  // Status
                  Text(
                    _status,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Colors.grey[100],
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                  ),
                  const SizedBox(height: 24),
                  
                  // Driver Info
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: AppTheme.surfaceColor,
                        child: Icon(Icons.person, size: 28, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Michael',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Row(
                            children: [
                              const Text(
                                'Toyota Prius • ABC 123',
                                style: TextStyle(color: AppTheme.textSecondary),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.star, size: 12, color: Colors.amber),
                                    SizedBox(width: 2),
                                    Text(
                                      '4.9',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                      Column(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.phone, color: AppTheme.primaryColor),
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: const Icon(Icons.message, color: AppTheme.primaryColor),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {},
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Cancel Ride',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.grey[100],
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Share Status',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
