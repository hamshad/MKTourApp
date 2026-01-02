import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as latlong;
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/widgets/platform_map.dart';
import '../../core/auth_provider.dart';

class RideDetailScreen extends StatefulWidget {
  final String rideId;
  final Map<String, dynamic>? initialData;

  const RideDetailScreen({
    super.key,
    required this.rideId,
    this.initialData,
  });

  @override
  State<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends State<RideDetailScreen> {
  Map<String, dynamic>? _rideData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _rideData = widget.initialData;
    _fetchRideDetails();
  }

  Future<void> _fetchRideDetails() async {
    final details = await Provider.of<AuthProvider>(context, listen: false)
        .fetchRideDetails(widget.rideId);
    
    if (mounted) {
      setState(() {
        if (details != null) {
          _rideData = details;
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Extract coordinates
    double? pickupLat;
    double? pickupLng;
    double? dropoffLat;
    double? dropoffLng;

    if (_rideData != null) {
      final pickup = _rideData!['pickupLocation'];
      final dropoff = _rideData!['dropoffLocation'];

      if (pickup is Map && pickup['coordinates'] != null) {
        // GeoJSON is [lng, lat]
        final coords = pickup['coordinates'];
        if (coords is List && coords.length >= 2) {
          pickupLng = (coords[0] as num).toDouble();
          pickupLat = (coords[1] as num).toDouble();
        }
      }

      if (dropoff is Map && dropoff['coordinates'] != null) {
        final coords = dropoff['coordinates'];
        if (coords is List && coords.length >= 2) {
          dropoffLng = (coords[0] as num).toDouble();
          dropoffLat = (coords[1] as num).toDouble();
        }
      }
    }

    List<MapMarker> markers = [];
    fmap.LatLngBounds? bounds;

    if (pickupLat != null && pickupLng != null) {
      markers.add(MapMarker(
        id: 'pickup',
        lat: pickupLat,
        lng: pickupLng,
        title: 'Pickup',
        child: const Icon(Icons.my_location, color: Colors.green, size: 40),
      ));
    }

    if (dropoffLat != null && dropoffLng != null) {
      markers.add(MapMarker(
        id: 'dropoff',
        lat: dropoffLat,
        lng: dropoffLng,
        title: 'Dropoff',
        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
      ));
    }

    if (markers.isNotEmpty) {
      bounds = fmap.LatLngBounds.fromPoints(
        markers.map((m) => latlong.LatLng(m.lat, m.lng)).toList(),
      );
    }

    final driver = (_rideData?['driver'] is Map) ? _rideData!['driver'] : null;
    final vehicle = (driver != null && driver['vehicle'] is Map) ? driver['vehicle'] : null;
    final dateStr = _rideData?['createdAt'];
    final status = _rideData?['status']?.toString().toUpperCase() ?? 'UNKNOWN';
    final price = _rideData?['fare'] != null ? '£${_rideData!['fare']}' : '£0.00';
    final destination = _rideData?['dropoffLocation'] is Map ? _rideData!['dropoffLocation']['address'] ?? 'Unknown Destination' : 'Unknown Destination';
    final pickupAddress = _rideData?['pickupLocation'] is Map ? _rideData!['pickupLocation']['address'] ?? 'Unknown Pickup' : 'Unknown Pickup';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Ride Details',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: _isLoading && _rideData == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Map View
                  SizedBox(
                    height: 250,
                    width: double.infinity,
                    child: PlatformMap(
                      initialLat: pickupLat ?? 37.7749,
                      initialLng: pickupLng ?? -122.4194,
                      markers: markers,
                      bounds: bounds,
                      onTap: (lat, lng) {
                        debugPrint('Map tapped at: $lat, $lng');
                      },
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              dateStr != null ? dateStr.substring(0, 10) : 'Unknown Date', // Simple formatting
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: status == 'CANCELED' 
                                    ? Colors.red.withValues(alpha: 0.1) 
                                    : Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: status == 'CANCELED' ? Colors.red : Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Vehicle/Driver Info
                        if (driver != null)
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
                                    vehicle != null ? '${vehicle['model']} (${vehicle['color']})' : 'Unknown Vehicle',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    '${vehicle != null ? vehicle['number'] : ''} • ${driver['name']}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  if (driver['rating'] != null)
                                    Row(
                                      children: [
                                        const Icon(Icons.star, size: 14, color: Colors.amber),
                                        const SizedBox(width: 4),
                                        Text(
                                          driver['rating'].toString(),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          )
                        else
                          const Text('Driver details not available'),
                        
                        const SizedBox(height: 24),
                        Divider(color: AppTheme.borderColor),
                        const SizedBox(height: 24),
                        
                        // Trip Details
                        _buildLocationRow(
                          icon: Icons.my_location,
                          color: Colors.green,
                          text: pickupAddress,
                          time: 'Pickup',
                        ),
                        _buildDottedLine(),
                        _buildLocationRow(
                          icon: Icons.location_on,
                          color: Colors.red,
                          text: destination,
                          time: 'Dropoff',
                        ),
                        
                        const SizedBox(height: 24),
                        Divider(color: AppTheme.borderColor),
                        const SizedBox(height: 24),
                        
                        // Payment
                        const Text(
                          'Payment',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Trip Fare',
                              style: TextStyle(
                                fontSize: 16,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              price,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // Help Button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {},
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: AppTheme.borderColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Get Help with this Ride',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
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
    );
  }

  Widget _buildLocationRow({
    required IconData icon,
    required Color color,
    required String text,
    required String time,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDottedLine() {
    return Container(
      margin: const EdgeInsets.only(left: 9, top: 4, bottom: 4),
      height: 24,
      width: 2,
      decoration: BoxDecoration(
        color: AppTheme.borderColor,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
