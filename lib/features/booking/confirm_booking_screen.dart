import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme.dart';
import '../../core/services/payment_service.dart';

class ConfirmBookingScreen extends StatefulWidget {
  const ConfirmBookingScreen({super.key});

  @override
  State<ConfirmBookingScreen> createState() => _ConfirmBookingScreenState();
}

class _ConfirmBookingScreenState extends State<ConfirmBookingScreen> {
  bool _isLoading = false;
  final TextEditingController _notesController = TextEditingController();
  PaymentTiming _paymentTiming = PaymentTiming.payLater;

  Future<void> _confirmBooking(
    Map<String, dynamic> vehicle,
    Map<String, dynamic> destination,
    Map<String, dynamic>? pickup,
  ) async {
    setState(() => _isLoading = true);

    try {
      // Prepare location data
      final pickupLocation = pickup != null
          ? {
              'coordinates': [
                pickup['lng'] ?? -0.1278,
                pickup['lat'] ?? 51.5074,
              ],
              'address':
                  pickup['name'] ?? pickup['address'] ?? 'Current Location',
            }
          : {
              'coordinates': [-0.1278, 51.5074],
              'address': 'Current Location',
            };

      final dropoffLocation = {
        'coordinates': [
          destination['lng'] ?? -0.1240,
          destination['lat'] ?? 51.5100,
        ],
        'address':
            destination['name'] ?? destination['address'] ?? 'Destination',
      };

      // Use PaymentService for Stripe payment flow
      final result = await PaymentService.bookRideWithPayment(
        context: context,
        pickupLocation: pickupLocation,
        dropoffLocation: dropoffLocation,
        vehicleType: vehicle['id'] ?? 'car',
        distance: (vehicle['distance'] as num?)?.toDouble() ?? 5.0,
        fare: (vehicle['basePrice'] as num?)?.toDouble() ?? 15.0,
        paymentTiming: _paymentTiming,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      );

      setState(() => _isLoading = false);

      if (result.success && mounted) {
        // Show success message
        _showSuccessDialog(result.message ?? 'Booking confirmed!', result.data);
      } else if (!result.success && mounted) {
        _showErrorDialog(result.error ?? 'Payment failed');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        _showErrorDialog(e.toString());
      }
    }
  }

  void _showSuccessDialog(String message, Map<String, dynamic>? rideData) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Success'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/ride-assigned',
                (route) => false,
                arguments: rideData ?? {'success': true},
              );
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Payment Failed'),
          ],
        ),
        content: Text(error),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
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
      return const Scaffold(
        body: Center(child: Text('Error: Missing booking details')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Confirm Booking',
          style: TextStyle(color: Colors.black),
        ),
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
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
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
                      child: Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 30,
                      ),
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
                          const Icon(
                            Icons.my_location,
                            color: Colors.blue,
                            size: 16,
                          ),
                          Container(
                            height: 24,
                            width: 2,
                            color: Colors.grey[300],
                          ),
                          const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 16,
                          ),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
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
                        child: Icon(
                          Icons.local_taxi,
                          color: AppTheme.primaryColor,
                          size: 32,
                        ),
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
                  const Divider(),
                  const SizedBox(height: 16),

                  // Payment Timing Selection
                  const Text(
                    'Payment Option',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  // Pay After Ride Option
                  _buildPaymentOption(
                    title: 'Pay After Ride',
                    subtitle: 'You\'ll be charged when the ride completes',
                    icon: Icons.schedule,
                    value: PaymentTiming.payLater,
                    isSelected: _paymentTiming == PaymentTiming.payLater,
                  ),
                  const SizedBox(height: 12),

                  // Pay Now Option
                  _buildPaymentOption(
                    title: 'Pay Now',
                    subtitle: 'Pay immediately when booking',
                    icon: Icons.flash_on,
                    value: PaymentTiming.payNow,
                    isSelected: _paymentTiming == PaymentTiming.payNow,
                  ),

                  const SizedBox(height: 16),

                  // Payment Info Box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _paymentTiming == PaymentTiming.payLater
                                ? 'Your card will be authorized but not charged until the ride completes.'
                                : 'Your card will be charged immediately upon confirmation.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                      ],
                    ),
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
                onPressed: _isLoading
                    ? null
                    : () => _confirmBooking(
                        vehicle,
                        destination,
                        args?['pickup'],
                      ),
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
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _paymentTiming == PaymentTiming.payNow
                            ? 'Pay £${vehicle['basePrice']} & Confirm'
                            : 'Confirm Booking',
                        style: const TextStyle(
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

  Widget _buildPaymentOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required PaymentTiming value,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => setState(() => _paymentTiming = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.05)
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryColor.withOpacity(0.1)
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppTheme.primaryColor : Colors.grey[600],
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Radio<PaymentTiming>(
              value: value,
              groupValue: _paymentTiming,
              onChanged: (val) => setState(() => _paymentTiming = val!),
              activeColor: AppTheme.primaryColor,
            ),
          ],
        ),
      ),
    );
  }
}
