import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme.dart';

class DriverRideDetailScreen extends StatelessWidget {
  final Map<String, dynamic> rideData;

  const DriverRideDetailScreen({super.key, required this.rideData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Map Header
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: _buildMap(context),
            ),
            leading: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rideData['time'] ?? '10:30 AM',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            rideData['amount'] ?? '£24.50',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Completed',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),
                  
                  // Passenger Info
                  const Text(
                    'Passenger',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 24,
                        backgroundColor: AppTheme.surfaceColor,
                        child: Icon(Icons.person, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rideData['passenger']?['name'] ?? 'Passenger',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              Icon(Icons.star, size: 14, color: Colors.amber),
                              SizedBox(width: 4),
                              Text('${rideData['passenger']?['rating'] ?? '5.0'}'),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.help_outline),
                        onPressed: () {},
                        tooltip: 'Report Issue',
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),
                  
                  // Trip Details
                  const Text(
                    'Trip Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildLocationRow(
                    Icons.my_location,
                    Colors.green,
                    'Pickup',
                    _formatTime(rideData['pickupTime']),
                    rideData['pickupLocation']?['address'] ?? 'Unknown Location',
                  ),
                  const SizedBox(height: 24),
                  _buildLocationRow(
                    Icons.location_on,
                    Colors.red,
                    'Drop-off',
                    _formatTime(rideData['dropoffTime']),
                    rideData['dropoffLocation']?['address'] ?? 'Unknown Destination',
                  ),
                  
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),
                  
                  // Fare Breakdown
                  const Text(
                    'Payment Breakdown',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFareRow('Trip Fare', '£20.00'),
                  _buildFareRow('Surge', '£2.50'),
                  _buildFareRow('Tip', '£2.00'),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(),
                  ),
                  _buildFareRow('Total Earnings', '£24.50', isTotal: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, Color color, String label, String time, String address) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(icon, color: color, size: 20),
            Container(width: 2, height: 30, color: Colors.grey[200]),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    time,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFareRow(String label, String amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? AppTheme.primaryColor : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(BuildContext context) {
    // Parse coordinates
    // Assuming GeoJSON [lng, lat]
    final pickupCoords = rideData['pickupLocation']?['coordinates'] ?? [0.0, 0.0];
    final dropoffCoords = rideData['dropoffLocation']?['coordinates'] ?? [0.0, 0.0];
    
    final pickup = LatLng(pickupCoords[1], pickupCoords[0]);
    final dropoff = LatLng(dropoffCoords[1], dropoffCoords[0]);
    
    // Center map
    final center = LatLng(
      (pickup.latitude + dropoff.latitude) / 2,
      (pickup.longitude + dropoff.longitude) / 2,
    );

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 13.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.skyline',
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: [pickup, dropoff],
              strokeWidth: 4.0,
              color: AppTheme.primaryColor,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: pickup,
              child: const Icon(Icons.location_on, color: Colors.green, size: 40),
            ),
            Marker(
              point: dropoff,
              child: const Icon(Icons.location_on, color: Colors.red, size: 40),
            ),
          ],
        ),
      ],
    );
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '--:--';
    try {
      final date = DateTime.parse(isoString).toLocal();
      return "${date.hour}:${date.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return '--:--';
    }
  }
}
