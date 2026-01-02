import 'package:flutter/material.dart';
import '../../core/api_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/widgets/platform_map.dart';

class RideDetailScreen extends StatefulWidget {
  final String rideId;

  const RideDetailScreen({super.key, required this.rideId});

  @override
  State<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends State<RideDetailScreen> {
  final ApiService _apiService = ApiService();
  Map<String, dynamic>? _rideDetails;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchRideDetails();
  }

  Future<void> _fetchRideDetails() async {
    try {
      final details = await _apiService.getRideDetails(widget.rideId);
      if (mounted) {
        setState(() {
          _rideDetails = details['data'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ride Details')),
        body: Center(child: Text('Error: $_error')),
      );
    }

    if (_rideDetails == null) {
      return const Scaffold(
        body: Center(child: Text('No ride details found')),
      );
    }

    final pickup = _rideDetails!['pickupLocation'];
    final dropoff = _rideDetails!['dropoffLocation'];
    final pickupLat = pickup['coordinates'][1];
    final pickupLng = pickup['coordinates'][0];
    final dropoffLat = dropoff['coordinates'][1];
    final dropoffLng = dropoff['coordinates'][0];

    final markers = [
      MapMarker(
        id: 'pickup',
        lat: pickupLat,
        lng: pickupLng,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Icon(Icons.my_location, color: Colors.white, size: 16),
        ),
        title: 'Pickup',
      ),
      MapMarker(
        id: 'dropoff',
        lat: dropoffLat,
        lng: dropoffLng,
        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
        title: 'Dropoff',
      ),
    ];

    final polylines = [
      LatLng(pickupLat, pickupLng),
      LatLng(dropoffLat, dropoffLng),
    ];

    return Scaffold(
      body: Stack(
        children: [
          PlatformMap(
            initialLat: pickupLat,
            initialLng: pickupLng,
            markers: markers,
            polylines: [
              MapPolyline(
                id: 'route',
                points: polylines,
                color: Colors.black,
                width: 4.0,
              ),
            ],
            bounds: LatLngBounds.fromPoints(polylines),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _rideDetails!['status'].toString().toUpperCase(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _rideDetails!['status'] == 'cancelled' ? Colors.red : Colors.green,
                        ),
                      ),
                      Text(
                        '\$${_rideDetails!['fare']}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Cancellation Reason
                  if (_rideDetails!['status'] == 'cancelled' && _rideDetails!['cancellationReason'] != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade100),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Reason: ${_rideDetails!['cancellationReason']}',
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // OTP
                  if ((_rideDetails!['status'] == 'driver_assigned' || _rideDetails!['status'] == 'driver_arrived') && 
                      (_rideDetails!['verificationOTP'] != null || _rideDetails!['otp'] != null)) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('OTP', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          Text(
                            _rideDetails!['verificationOTP'] ?? _rideDetails!['otp'] ?? '',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Driver & Vehicle Info
                  if (_rideDetails!['driver'] != null) ...[
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage: _rideDetails!['driver']['profilePicture'] != null 
                              ? NetworkImage(_rideDetails!['driver']['profilePicture']) 
                              : null,
                          child: _rideDetails!['driver']['profilePicture'] == null 
                              ? const Icon(Icons.person, color: Colors.grey) 
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _rideDetails!['driver']['name'] ?? 'Driver',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.star, size: 14, color: Colors.amber),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_rideDetails!['driver']['rating'] ?? 5.0}',
                                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _rideDetails!['driver']['vehicle']?['model'] ?? 'Vehicle',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _rideDetails!['driver']['vehicle']?['number'] ?? '',
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                  ],

                  _buildLocationRow(Icons.my_location, pickup['address']),
                  const SizedBox(height: 16),
                  _buildLocationRow(Icons.location_on, dropoff['address']),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, String address) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            address,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
