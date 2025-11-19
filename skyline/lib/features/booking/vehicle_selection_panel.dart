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
  bool _bookNow = true;
  
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
    print('🚗 VEHICLE SELECTION: Screen loaded');
    print('🚗 VEHICLE SELECTION: Destination = $destination');

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
                    color: Theme.of(context).primaryColor,
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
            minHeight: 320,
            maxHeight: 450,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            panel: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
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
                  const SizedBox(height: 16),
                  Text(
                    'Select your ride',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 20),
                  // Vehicle List
                  SizedBox(
                    height: 140,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: AppConstants.vehicleTypes.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final vehicle = AppConstants.vehicleTypes[index];
                        final isSelected = _selectedVehicleIndex == index;
                        
                        return GestureDetector(
                          onTap: () => setState(() => _selectedVehicleIndex = index),
                          child: Container(
                            width: 120,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.05) : Colors.white,
                              border: Border.all(
                                color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade200,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Icon placeholder
                                Icon(
                                  Icons.local_taxi, 
                                  size: 40, 
                                  color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  vehicle['name'],
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Theme.of(context).primaryColor : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '£${vehicle['basePrice']}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Book Now / Later Toggle
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _bookNow = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _bookNow ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: _bookNow ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 4,
                                  )
                                ] : [],
                              ),
                              child: Center(
                                child: Text(
                                  'Book Now',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _bookNow ? Colors.black : Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _bookNow = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: !_bookNow ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: !_bookNow ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 4,
                                  )
                                ] : [],
                              ),
                              child: Center(
                                child: Text(
                                  'Schedule',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: !_bookNow ? Colors.black : Colors.grey,
                                  ),
                                ),
                              ),
                            ),
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
                        final selectedVehicle = AppConstants.vehicleTypes[_selectedVehicleIndex];
                        print('🚗 VEHICLE SELECTION: Selected vehicle: ${selectedVehicle['name']}');
                        print('🚗 VEHICLE SELECTION: Navigating to /confirm-booking');
                        Navigator.pushNamed(
                          context, 
                          '/confirm-booking',
                          arguments: {
                            'vehicle': selectedVehicle,
                            'destination': destination,
                          },
                        );
                      },
                      child: Text('Choose ${AppConstants.vehicleTypes[_selectedVehicleIndex]['name']}'),
                    ),
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
