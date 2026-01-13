import 'package:flutter/material.dart';
import '../../../core/services/places_service.dart';
import '../../../core/services/vehicle_service.dart';
import '../../../core/models/vehicle.dart';
import '../../../core/enums/vehicle_type.dart';
import '../../../core/theme.dart';

class VehicleSelectionWidget extends StatefulWidget {
  final Function(String) onVehicleSelected;
  final Function(
    String vehicleType,
    String vehicleName,
    Map<String, dynamic> fareData,
  )
  onSelectVehicle;
  final bool isLoading;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;

  const VehicleSelectionWidget({
    super.key,
    required this.onVehicleSelected,
    required this.onSelectVehicle,
    this.isLoading = false,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
  });

  @override
  State<VehicleSelectionWidget> createState() => _VehicleSelectionWidgetState();
}

class _VehicleSelectionWidgetState extends State<VehicleSelectionWidget> {
  String _selectedVehicle = 'sedan';
  final VehicleService _vehicleService = VehicleService();
  final PlacesService _placesService = PlacesService();
  List<Vehicle> _vehicles = [];
  bool _isLoadingVehicles = true;
  Map<String, Map<String, dynamic>> _fareEstimates = {};
  bool _isFetchingFares = false;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  /// Load vehicles from backend API
  Future<void> _loadVehicles() async {
    debugPrint('🚗 VehicleSelectionWidget: Loading vehicles from API...');
    setState(() => _isLoadingVehicles = true);

    try {
      final vehicles = await _vehicleService.getActiveVehicles();
      if (mounted) {
        setState(() {
          _vehicles = vehicles;
          _isLoadingVehicles = false;
          // Default to first vehicle (sedan)
          if (vehicles.isNotEmpty) {
            _selectedVehicle = vehicles.first.type.apiValue;
          }
        });
        debugPrint('✅ VehicleSelectionWidget: Loaded ${vehicles.length} vehicles');
        
        // Fetch fare estimates for all vehicles if locations are available
        _fetchFareEstimates();
      }
    } catch (e) {
      debugPrint('❌ VehicleSelectionWidget: Error loading vehicles: $e');
      if (mounted) {
        setState(() {
          _vehicles = _vehicleService.defaultVehicles;
          _isLoadingVehicles = false;
        });
      }
    }
  }

  /// Fetch fare estimates for all vehicle types from backend
  Future<void> _fetchFareEstimates() async {
    if (widget.pickupLat == null || 
        widget.pickupLng == null ||
        widget.dropoffLat == null ||
        widget.dropoffLng == null) {
      debugPrint('⚠️ VehicleSelectionWidget: Missing coordinates for fare estimation');
      return;
    }

    setState(() => _isFetchingFares = true);

    for (final vehicle in _vehicles) {
      try {
        // Call backend API: GET /api/v1/maps/get-distance-time
        final result = await _placesService.getDistanceAndFare(
          originLat: widget.pickupLat!,
          originLng: widget.pickupLng!,
          destLat: widget.dropoffLat!,
          destLng: widget.dropoffLng!,
          vehicleType: vehicle.type.apiValue,
        );

        if (mounted && result != null) {
          setState(() {
            _fareEstimates[vehicle.type.apiValue] = result;
          });
          debugPrint('✅ VehicleSelectionWidget: Got fare for ${vehicle.type.apiValue}: £${result['total_fare']}');
        }
      } catch (e) {
        debugPrint('❌ VehicleSelectionWidget: Error getting fare for ${vehicle.type.apiValue}: $e');
      }
    }

    if (mounted) {
      setState(() => _isFetchingFares = false);
    }
  }

  /// Get icon for vehicle type
  IconData _getVehicleIcon(VehicleType type) {
    switch (type) {
      case VehicleType.sedan:
        return Icons.directions_car;
      case VehicleType.suv:
        return Icons.directions_car_filled;
      case VehicleType.hatchback:
        return Icons.car_rental;
      case VehicleType.van:
        return Icons.airport_shuttle;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingVehicles) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Choose a ride',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),

        // Vehicle list (fetched from API)
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _vehicles.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final vehicle = _vehicles[index];
            final vehicleId = vehicle.type.apiValue;
            final isSelected = _selectedVehicle == vehicleId;
            
            // Get fare estimate from backend or use base fare
            final fareData = _fareEstimates[vehicleId];
            final price = fareData?['total_fare'] ?? vehicle.baseFare;
            final durationSeconds = fareData?['duration_seconds'] ?? 600;
            final durationText = fareData?['duration_text'] ?? '${(durationSeconds / 60).round()} mins';

            return InkWell(
              onTap: () {
                setState(() => _selectedVehicle = vehicleId);
                widget.onVehicleSelected(vehicleId);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.surfaceColor
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: AppTheme.primaryColor, width: 2)
                      : null,
                ),
                child: Row(
                  children: [
                    // Vehicle Icon
                    Container(
                      width: 60,
                      height: 50,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getVehicleIcon(vehicle.type),
                        size: 32,
                        color: isSelected
                            ? AppTheme.primaryColor
                            : Colors.grey[700],
                      ),
                    ),

                    // Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vehicle.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.person,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${vehicle.capacity} Seats',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(width: 16),
                              if (fareData != null) ...[
                                Icon(
                                  Icons.schedule,
                                  size: 14,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  durationText,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Price (from backend)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _isFetchingFares && fareData == null
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  '£${price.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected 
                                        ? AppTheme.primaryColor 
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                          if (fareData != null)
                            Text(
                              fareData['distance_text'] ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // Select Vehicle button
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: widget.isLoading
                  ? null
                  : () {
                      final vehicle = _vehicles.firstWhere(
                        (v) => v.type.apiValue == _selectedVehicle,
                        orElse: () => _vehicles.first,
                      );
                      
                      // Use fare data from backend if available
                      final fareData = _fareEstimates[_selectedVehicle] ?? {
                        'total_fare': vehicle.baseFare,
                        'distance_text': 'Calculation pending',
                        'duration_text': 'Calculating...',
                        'duration_seconds': 600,
                      };

                      debugPrint('🚗 VehicleSelectionWidget: Select Vehicle pressed');
                      debugPrint('🚗 VehicleSelectionWidget: Type: $_selectedVehicle, Fare: £${fareData['total_fare']}');
                      
                      widget.onSelectVehicle(
                        _selectedVehicle,
                        vehicle.name,
                        fareData,
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: widget.isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Select ${_vehicles.firstWhere((v) => v.type.apiValue == _selectedVehicle, orElse: () => _vehicles.first).name}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
