import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/services/places_service.dart';
import '../../../core/theme.dart';

class VehicleSelectionWidget extends StatefulWidget {
  final Function(String) onVehicleSelected;
  final VoidCallback onBookRide;
  final bool isLoading;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;

  const VehicleSelectionWidget({
    super.key,
    required this.onVehicleSelected,
    required this.onBookRide,
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
  final PlacesService _placesService = PlacesService();
  String _selectedVehicle = 'standard';
  bool _isFetchingFares = false;

  // Vehicle types with their backend IDs
  final List<Map<String, dynamic>> _vehicles = [
    {
      'id': 'standard',
      'name': 'Standard',
      'icon': Icons.directions_car,
      'description': 'Affordable, everyday rides',
      'seats': 4,
    },
    {
      'id': 'executive',
      'name': 'Executive',
      'icon': Icons.directions_car_filled,
      'description': 'Premium rides for business',
      'seats': 4,
    },
    {
      'id': 'xl',
      'name': 'XL',
      'icon': Icons.airport_shuttle,
      'description': 'More space for groups',
      'seats': 6,
    },
  ];

  // Dynamic fare data fetched from backend
  Map<String, Map<String, dynamic>> _fareData = {};

  @override
  void initState() {
    super.initState();
    debugPrint('🚗 VehicleSelectionWidget: initState called');
    _fetchAllFares();
  }

  @override
  void didUpdateWidget(VehicleSelectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refetch fares if coordinates change
    if (oldWidget.pickupLat != widget.pickupLat ||
        oldWidget.pickupLng != widget.pickupLng ||
        oldWidget.dropoffLat != widget.dropoffLat ||
        oldWidget.dropoffLng != widget.dropoffLng) {
      debugPrint('🚗 VehicleSelectionWidget: Coordinates changed, refetching fares...');
      _fetchAllFares();
    }
  }

  /// Fetch fares for all vehicle types from backend
  Future<void> _fetchAllFares() async {
    if (widget.pickupLat == null ||
        widget.pickupLng == null ||
        widget.dropoffLat == null ||
        widget.dropoffLng == null) {
      debugPrint('⚠️ VehicleSelectionWidget: Missing coordinates, skipping fare fetch');
      return;
    }

    debugPrint('🚗 VehicleSelectionWidget: Fetching fares for all vehicle types...');
    debugPrint('📍 Pickup: (${widget.pickupLat}, ${widget.pickupLng})');
    debugPrint('📍 Dropoff: (${widget.dropoffLat}, ${widget.dropoffLng})');
    
    setState(() => _isFetchingFares = true);

    try {
      // Fetch fares for all vehicle types in parallel
      debugPrint('🔄 VehicleSelectionWidget: Starting parallel fare requests for ${_vehicles.length} vehicle types');
      
      final futures = _vehicles.map((vehicle) async {
        debugPrint('   → Requesting fare for: ${vehicle['id']}');
        final data = await _placesService.getDistanceAndFare(
          originLat: widget.pickupLat!,
          originLng: widget.pickupLng!,
          destLat: widget.dropoffLat!,
          destLng: widget.dropoffLng!,
          vehicleType: vehicle['id'],
        );
        return MapEntry(vehicle['id'] as String, data);
      }).toList();

      final results = await Future.wait(futures);

      if (mounted) {
        setState(() {
          for (final entry in results) {
            if (entry.value != null) {
              _fareData[entry.key] = entry.value!;
              debugPrint('✅ VehicleSelectionWidget: ${entry.key} → £${entry.value!['total_fare']}, ${entry.value!['duration_text']}');
            } else {
              debugPrint('⚠️ VehicleSelectionWidget: ${entry.key} → No fare data received');
            }
          }
          _isFetchingFares = false;
        });
        debugPrint('✅ VehicleSelectionWidget: All fares fetched successfully');
      }
    } catch (e) {
      debugPrint('❌ VehicleSelectionWidget: Error fetching fares: $e');
      if (mounted) {
        setState(() => _isFetchingFares = false);
      }
    }
  }

  /// Calculate ETA drop-off time based on duration
  String _getDropoffTime(int durationSeconds) {
    final now = DateTime.now();
    final dropoffTime = now.add(Duration(seconds: durationSeconds));
    final formatted = DateFormat('h:mm a').format(dropoffTime);
    debugPrint('⏱️ VehicleSelectionWidget: ETA calculated: $formatted (${durationSeconds}s from now)');
    return formatted;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Choose a ride',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        
        // Loading indicator while fetching fares
        if (_isFetchingFares)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),

        // Vehicle list
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _vehicles.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final vehicle = _vehicles[index];
            final vehicleId = vehicle['id'] as String;
            final isSelected = _selectedVehicle == vehicleId;
            final fareInfo = _fareData[vehicleId];
            
            // Get dynamic price or show loading
            final price = fareInfo?['total_fare'];
            final durationSeconds = fareInfo?['duration_seconds'] as int?;
            final dropoffTime = durationSeconds != null 
                ? _getDropoffTime(durationSeconds) 
                : null;
            
            return InkWell(
              onTap: () {
                setState(() => _selectedVehicle = vehicleId);
                widget.onVehicleSelected(vehicleId);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.surfaceColor : Colors.transparent,
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
                        vehicle['icon'] as IconData,
                        size: 32,
                        color: isSelected ? AppTheme.primaryColor : Colors.grey[700],
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
                                vehicle['name'] as String,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.person, size: 14, color: Colors.grey[600]),
                              Text(
                                '${vehicle['seats']}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dropoffTime != null 
                                ? '$dropoffTime drop-off' 
                                : vehicle['description'] as String,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Price
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: price != null
                          ? Text(
                              '£${price.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            )
                          : _isFetchingFares
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  '—',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[400],
                                  ),
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        
        const SizedBox(height: 16),
        
        // Book button
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: widget.isLoading || _isFetchingFares 
                  ? null 
                  : widget.onBookRide,
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
                      'Book ${_vehicles.firstWhere((v) => v['id'] == _selectedVehicle)['name']}',
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
