import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../core/theme.dart';

class ConfirmBookingScreen extends StatefulWidget {
  const ConfirmBookingScreen({super.key});

  @override
  State<ConfirmBookingScreen> createState() => _ConfirmBookingScreenState();
}

class _ConfirmBookingScreenState extends State<ConfirmBookingScreen> {
  bool _isLoading = false;

  Future<void> _confirmBooking(Map<String, dynamic> vehicle, Map<String, dynamic> destination) async {
    setState(() => _isLoading = true);
    
    print('✅ CONFIRM BOOKING: Booking ride...');
    print('✅ CONFIRM BOOKING: Vehicle = ${vehicle['name']}');
    print('✅ CONFIRM BOOKING: Destination = ${destination['name']}');
    
    // Call API
    final apiService = ApiService();
    final result = await apiService.bookRide({
      'pickup': 'Current Location',
      'destination': destination['name'],
      'vehicleType': vehicle['id'],
    });
    
    setState(() => _isLoading = false);
    
    if (result['success'] == true && mounted) {
      print('✅ CONFIRM BOOKING: Booking successful!');
      print('✅ CONFIRM BOOKING: OTP = ${result['otp']}');
      print('✅ CONFIRM BOOKING: Navigating to /ride-assigned');
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
    
    // Handle both Map and String types for destination
    final Map<String, dynamic> destination;
    if (destinationArg is Map<String, dynamic>) {
      destination = destinationArg;
    } else if (destinationArg is String) {
      destination = {'name': destinationArg, 'address': ''};
    } else {
      destination = {'name': 'Unknown destination', 'address': ''};
    }
    
    print('✅ CONFIRM BOOKING: Screen loaded');
    print('✅ CONFIRM BOOKING: Vehicle = ${vehicle?['name']}');
    print('✅ CONFIRM BOOKING: Destination = ${destination['name']}');

    if (vehicle == null) {
      return const Scaffold(body: Center(child: Text('Error: Missing booking details')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Booking'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Route Summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.my_location, color: Colors.blue, size: 20),
                      const SizedBox(width: 12),
                      const Text('Current Location', style: TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 9),
                    height: 20,
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: Colors.grey.shade300, width: 2)),
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.red, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          destination['name'], 
                          style: const TextStyle(fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Vehicle Summary
            Text('Vehicle', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.local_taxi, color: Theme.of(context).primaryColor),
              ),
              title: Text(vehicle['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(vehicle['description']),
              trailing: Text(
                '£${vehicle['basePrice']}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 32),
            
            // Payment Method
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Payment Method'),
                Row(
                  children: [
                    const Icon(Icons.apple, size: 20),
                    const SizedBox(width: 4),
                    const Text('Apple Pay', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Text('Change', style: TextStyle(color: Theme.of(context).primaryColor)),
                  ],
                ),
              ],
            ),
            
            const Spacer(),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : () => _confirmBooking(vehicle, destination),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Confirm Booking'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
