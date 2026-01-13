import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';

class VehicleSelectionScreen extends StatefulWidget {
  const VehicleSelectionScreen({super.key});

  @override
  State<VehicleSelectionScreen> createState() => _VehicleSelectionScreenState();
}

class _VehicleSelectionScreenState extends State<VehicleSelectionScreen> {
  final PanelController _panelController = PanelController();
  int _selectedVehicleIndex = 0;
  
  // Route points (Mock)
  final List<LatLng> _route = [
    const LatLng(51.5074, -0.1278), // Start
    const LatLng(51.5080, -0.1260),
    const LatLng(51.5090, -0.1250),
    const LatLng(51.5100, -0.1240), // End
  ];

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final destination = args?['destination'] ?? {'name': 'Destination', 'address': ''};

    return Scaffold(
      body: Stack(
        children: [
          // Map with Route
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
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _route,
                    strokeWidth: 4.0,
                    color: AppTheme.primaryColor,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _route.first,
                    width: 20,
                    height: 20,
                    child: const Icon(Icons.my_location, color: Colors.blue),
                  ),
                  Marker(
                    point: _route.last,
                    width: 30,
                    height: 30,
                    child: const Icon(Icons.location_on, color: Colors.red, size: 30),
                  ),
                ],
              ),
            ],
          ),
          
          // Back Button
          Positioned(
            top: 50,
            left: 20,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // Vehicle Selection Panel
          SlidingUpPanel(
            controller: _panelController,
            minHeight: 400,
            maxHeight: 600,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            panel: Column(
              children: [
                const SizedBox(height: 12),
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
                const SizedBox(height: 16),
                Text(
                  'Choose a ride',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: AppConstants.vehicleTypes.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final vehicle = AppConstants.vehicleTypes[index];
                      final isSelected = _selectedVehicleIndex == index;
                      
                      return InkWell(
                        onTap: () => setState(() => _selectedVehicleIndex = index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.surfaceColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: isSelected ? Border.all(color: AppTheme.primaryColor, width: 2) : null,
                          ),
                          child: Row(
                            children: [
                              // Vehicle Image/Icon
                              Container(
                                width: 80,
                                height: 60,
                                margin: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.local_taxi,
                                  size: 40,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                              
                              // Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          vehicle['name'],
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.person, size: 14, color: AppTheme.textSecondary),
                                        Text(
                                          '${vehicle['capacity'] ?? vehicle['seats'] ?? 4}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '12:05 PM drop-off',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              // Price (use baseFare or basePrice for backwards compatibility)
                              Padding(
                                padding: const EdgeInsets.only(right: 16),
                                child: Text(
                                  '£${vehicle['baseFare'] ?? vehicle['basePrice']}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                
                // Payment & Book Button
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.payment, color: AppTheme.textPrimary),
                          const SizedBox(width: 12),
                          const Text(
                            'Personal • Visa **** 4242',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {},
                            child: const Text('Switch'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () {
                            final selectedVehicle = AppConstants.vehicleTypes[_selectedVehicleIndex];
                            Navigator.pushNamed(
                              context, 
                              '/confirm-booking',
                              arguments: {
                                'vehicle': selectedVehicle,
                                'destination': destination,
                              },
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Choose ${AppConstants.vehicleTypes[_selectedVehicleIndex]['name']}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
