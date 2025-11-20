import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/api_service.dart';
import '../../core/theme.dart';

class ConfirmBookingScreen extends StatefulWidget {
  const ConfirmBookingScreen({super.key});

  @override
  State<ConfirmBookingScreen> createState() => _ConfirmBookingScreenState();
}

class _ConfirmBookingScreenState extends State<ConfirmBookingScreen> {
  bool _isLoading = false;
  final TextEditingController _notesController = TextEditingController();

  Future<void> _confirmBooking(Map<String, dynamic> vehicle, Map<String, dynamic> destination) async {
    setState(() => _isLoading = true);
    
    // Call API
    final apiService = ApiService();
    final result = await apiService.bookRide({
      'pickup': 'Current Location',
      'destination': destination['name'],
      'vehicleType': vehicle['id'],
      'notes': _notesController.text,
    });
    
    setState(() => _isLoading = false);
    
    if (result['success'] == true && mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context, 
        '/ride-assigned', 
        (route) => false,
        arguments: result,
      );
    } else {
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final vehicle = args?['vehicle'];
    final destinationArg = args?['destination'];
    
    final Map<String, dynamic> destination;
    if (destinationArg is Map<String, dynamic>) {
      destination = destinationArg;
    } else if (destinationArg is String) {
      destination = {'name': destinationArg, 'address': ''};
    } else {
      destination = {'name': 'Unknown destination', 'address': ''};
    }

    if (vehicle == null) {
      return const Scaffold(body: Center(child: Text('Error: Missing booking details')));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Confirm Booking', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Map Snapshot (Mock)
          SizedBox(
            height: 200,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: const LatLng(51.5085, -0.1260),
                initialZoom: 14.0,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
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
                      width: 20,
                      height: 20,
                      child: Icon(Icons.my_location, color: Colors.blue),
                    ),
                    const Marker(
                      point: LatLng(51.5100, -0.1240),
                      width: 30,
                      height: 30,
                      child: Icon(Icons.location_on, color: Colors.red, size: 30),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Trip Details
                  Row(
                    children: [
                      Column(
                        children: [
                          const Icon(Icons.my_location, color: Colors.blue, size: 16),
                          Container(height: 24, width: 2, color: Colors.grey[300]),
                          const Icon(Icons.location_on, color: Colors.red, size: 16),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Current Location',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              destination['name'],
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                  
                  // Vehicle Info
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.local_taxi, color: AppTheme.primaryColor, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vehicle['name'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            '12:05 PM drop-off',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        '£${vehicle['basePrice']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Notes
                  TextField(
                    controller: _notesController,
                    decoration: InputDecoration(
                      hintText: 'Add a note for driver...',
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.edit_note),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Payment
                  Row(
                    children: [
                      const Icon(Icons.payment, color: Colors.grey),
                      const SizedBox(width: 12),
                      const Text('Visa **** 4242'),
                      const Spacer(),
                      TextButton(
                        onPressed: () {},
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Confirm Button
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : () => _confirmBooking(vehicle, destination),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Confirm Booking',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
