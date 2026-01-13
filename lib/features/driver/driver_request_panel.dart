import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/services/places_service.dart';
import '../../core/enums/vehicle_type.dart';

class DriverRequestPanel extends StatefulWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final Map<String, dynamic>? rideData;

  const DriverRequestPanel({
    super.key,
    required this.onAccept,
    required this.onDecline,
    this.rideData,
  });

  @override
  State<DriverRequestPanel> createState() => _DriverRequestPanelState();
}

class _DriverRequestPanelState extends State<DriverRequestPanel> {
  final PlacesService _placesService = PlacesService();
  String _pickupAddress = '';
  String _dropoffAddress = '';
  bool _isLoadingAddresses = true;

  @override
  void initState() {
    super.initState();
    _fetchDetailedAddresses();
  }

  Future<void> _fetchDetailedAddresses() async {
    if (widget.rideData == null) {
      setState(() => _isLoadingAddresses = false);
      return;
    }

    // Fetch pickup address
    if (widget.rideData!['pickupLocation']?['coordinates'] != null) {
      final pickupCoords = widget.rideData!['pickupLocation']['coordinates'];
      final pickupLat = pickupCoords[1];
      final pickupLng = pickupCoords[0];
      
      final pickupAddr = await _placesService.getAddressFromLatLng(pickupLat, pickupLng);
      if (mounted) {
        setState(() {
          _pickupAddress = pickupAddr ?? widget.rideData!['pickupLocation']?['address'] ?? 'Pickup Location';
        });
      }
    }

    // Fetch dropoff address
    if (widget.rideData!['dropoffLocation']?['coordinates'] != null) {
      final dropoffCoords = widget.rideData!['dropoffLocation']['coordinates'];
      final dropoffLat = dropoffCoords[1];
      final dropoffLng = dropoffCoords[0];
      
      final dropoffAddr = await _placesService.getAddressFromLatLng(dropoffLat, dropoffLng);
      if (mounted) {
        setState(() {
          _dropoffAddress = dropoffAddr ?? widget.rideData!['dropoffLocation']?['address'] ?? 'Dropoff Location';
        });
      }
    }

    if (mounted) {
      setState(() => _isLoadingAddresses = false);
    }
  }

  /// Get display name for vehicle type from backend
  /// Handles the exact backend keys: sedan, suv, hatchback, van
  String _getVehicleDisplayName(String? vehicleType) {
    if (vehicleType == null) return 'Standard';
    
    try {
      final type = VehicleType.fromString(vehicleType);
      return type.displayName;
    } catch (e) {
      // Fallback for unknown types
      return vehicleType.substring(0, 1).toUpperCase() + vehicleType.substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
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
          const SizedBox(height: 20),
          
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'New Ride Request',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
                child: Text(
                  '2 mins away',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Passenger Info Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: 30, color: AppTheme.textSecondary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.rideData?['user']?['name'] ?? 'Passenger',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Display vehicle type from backend
                      Text(
                        _getVehicleDisplayName(widget.rideData?['vehicleType']),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Display fare from backend (already calculated with surge/night/weekend)
                    Text(
                      '£${(widget.rideData?['fare'] ?? 0.0).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    Text(
                      'Est. Fare',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Route Details
          Row(
            children: [
              Column(
                children: [
                  const Icon(Icons.my_location, color: AppTheme.primaryColor, size: 20),
                  Container(
                    height: 30,
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  const Icon(Icons.location_on, color: Colors.red, size: 20),
                ],
              ),
              const SizedBox(width: 16),
               Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isLoadingAddresses 
                        ? 'Loading address...'
                        : (_pickupAddress.isNotEmpty ? _pickupAddress : (widget.rideData?['pickupLocation']?['address'] ?? 'Pickup Location')),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: _isLoadingAddresses ? Colors.grey : AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _isLoadingAddresses 
                        ? 'Loading address...'
                        : (_dropoffAddress.isNotEmpty ? _dropoffAddress : (widget.rideData?['dropoffLocation']?['address'] ?? 'Dropoff Location')),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: _isLoadingAddresses ? Colors.grey : AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      '${(widget.rideData?['distance'] ?? 0.0).toStringAsFixed(1)} mi trip',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const Spacer(),
          
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onDecline,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    side: BorderSide(color: Colors.red.withOpacity(0.5), width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Decline',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: widget.onAccept,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    backgroundColor: AppTheme.primaryColor,
                    elevation: 8,
                    shadowColor: AppTheme.primaryColor.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Accept Ride',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
