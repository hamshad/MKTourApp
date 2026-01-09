import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/services/places_service.dart';
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

  final List<Map<String, dynamic>> _vehicles = [
    {
      'id': 'sedan',
      'name': 'Sedan',
      'icon': Icons.directions_car,
      'description': 'Comfortable rides for up to 4',
      'seats': 4,
      'price': 15.50,
      'duration_mins': 12,
    },
    {
      'id': 'suv',
      'name': 'SUV',
      'icon': Icons.directions_car_filled,
      'description': 'Spacious rides with extra room',
      'seats': 6,
      'price': 22.00,
      'duration_mins': 15,
    },
    {
      'id': 'hatchback',
      'name': 'Hatchback',
      'icon': Icons.car_rental,
      'description': 'Compact and affordable',
      'seats': 4,
      'price': 12.00,
      'duration_mins': 10,
    },
    {
      'id': 'van',
      'name': 'Van',
      'icon': Icons.airport_shuttle,
      'description': 'Perfect for groups & luggage',
      'seats': 8,
      'price': 35.00,
      'duration_mins': 18,
    },
  ];

  @override
  void initState() {
    super.initState();
    debugPrint('🚗 VehicleSelectionWidget: Simplified version initialized');
  }

  /// Calculate ETA drop-off time (Mock version)
  String _getDropoffTime(int durationMinutes) {
    final now = DateTime.now();
    final dropoffTime = now.add(Duration(minutes: durationMinutes));
    return DateFormat('h:mm a').format(dropoffTime);
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
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
            
            final price = vehicle['price'] as double;
            final durationMins = vehicle['duration_mins'] as int;
            final dropoffTime = _getDropoffTime(durationMins);

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
                        vehicle['icon'] as IconData,
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
                            vehicle['name'] as String,
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
                                '${vehicle['seats']} Seats',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
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
                        (v) => v['id'] == _selectedVehicle,
                      );
                      
                      final mockFareData = {
                        'total_fare': vehicle['price'],
                        'distance_text': 'Calculation pending',
                        'duration_text': '${vehicle['duration_mins']} mins',
                        'duration_seconds': (vehicle['duration_mins'] as int) * 60,
                      };

                      debugPrint('🚗 VehicleSelectionWidget: Select Vehicle pressed (Simplified)');
                      
                      widget.onSelectVehicle(
                        _selectedVehicle,
                        vehicle['name'] as String,
                        mockFareData,
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
                      'Select ${_vehicles.firstWhere((v) => v['id'] == _selectedVehicle)['name']}',
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
