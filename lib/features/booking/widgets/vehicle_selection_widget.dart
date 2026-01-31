import 'package:flutter/material.dart';
import '../../../core/services/places_service.dart';
import '../../../core/services/vehicle_service.dart';
import '../../../core/models/vehicle.dart';
import '../../../core/theme.dart';

class VehicleSelectionWidget extends StatefulWidget {
  final Function(String) onVehicleSelected;
  final Function(
    String categorySlug,
    String categoryName,
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
  String _selectedCategorySlug = '';
  final VehicleService _vehicleService = VehicleService();
  final PlacesService _placesService = PlacesService();
  List<VehicleCategory> _categories = [];
  bool _isLoadingCategories = true;
  Map<String, Map<String, dynamic>> _fareEstimates = {};
  bool _isFetchingFares = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  /// Load vehicle categories from backend API
  Future<void> _loadCategories() async {
    debugPrint('🚗 VehicleSelectionWidget: Loading categories from API...');
    setState(() => _isLoadingCategories = true);

    try {
      final categories = await _vehicleService.getVehicleCategories();
      if (mounted) {
        setState(() {
          _categories = categories;
          _isLoadingCategories = false;
          if (categories.isNotEmpty) {
            _selectedCategorySlug = categories.first.slug;
          }
        });
        debugPrint(
          '✅ VehicleSelectionWidget: Loaded ${categories.length} categories',
        );

        // Fetch fare estimates for all categories if locations are available
        _fetchFareEstimates();
      }
    } catch (e) {
      debugPrint('❌ VehicleSelectionWidget: Error loading categories: $e');
      if (mounted) {
        setState(() {
          _categories = _vehicleService.defaultCategories;
          _isLoadingCategories = false;
          if (_categories.isNotEmpty) {
            _selectedCategorySlug = _categories.first.slug;
          }
        });
      }
    }
  }

  /// Fetch fare estimates for all vehicle categories from backend
  Future<void> _fetchFareEstimates() async {
    if (widget.pickupLat == null ||
        widget.pickupLng == null ||
        widget.dropoffLat == null ||
        widget.dropoffLng == null) {
      debugPrint(
        '⚠️ VehicleSelectionWidget: Missing coordinates for fare estimation',
      );
      return;
    }

    setState(() => _isFetchingFares = true);

    for (final category in _categories) {
      try {
        final result = await _placesService.getDistanceAndFare(
          originLat: widget.pickupLat!,
          originLng: widget.pickupLng!,
          destLat: widget.dropoffLat!,
          destLng: widget.dropoffLng!,
          categorySlug: category.slug,
        );

        if (mounted && result != null) {
          setState(() {
            _fareEstimates[category.slug] = result;
          });
          debugPrint(
            '✅ VehicleSelectionWidget: Got fare for ${category.slug}: £${result['total_fare']}',
          );
        }
      } catch (e) {
        debugPrint(
          '❌ VehicleSelectionWidget: Error getting fare for ${category.slug}: $e',
        );
      }
    }

    if (mounted) {
      setState(() => _isFetchingFares = false);
    }
  }

  /// Get icon for vehicle category
  IconData _getVehicleIcon(String slug) {
    if (slug.contains('suv')) return Icons.directions_car_filled;
    if (slug.contains('van') || slug.contains('bus')) return Icons.airport_shuttle;
    if (slug.contains('hatchback')) return Icons.car_rental;
    return Icons.directions_car;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingCategories) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Choose a ride',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),

        // Categories list (fetched from API)
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _categories.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final category = _categories[index];
            final isSelected = _selectedCategorySlug == category.slug;

            // Get fare estimate
            final fareData = _fareEstimates[category.slug];
            final price = fareData?['total_fare'] ?? 0.0;
            final durationText = fareData?['duration_text'] ?? 'Calculating...';

            return InkWell(
              onTap: () {
                setState(() => _selectedCategorySlug = category.slug);
                widget.onVehicleSelected(category.slug);
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
                        _getVehicleIcon(category.slug),
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
                            category.name == category.slug || category.name == 'Unknown'
                              ? VehicleCategory.formatSlug(category.slug)
                              : category.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                'Up to ${category.seatingCapacity} people',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.luggage, size: 14, color: Colors.grey[500]),
                              Text(
                                ' ${category.luggage.suitcases}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.shopping_bag, size: 14, color: Colors.grey[500]),
                              Text(
                                ' ${category.luggage.smallCases}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                          if (fareData != null) ...[
                             const SizedBox(height: 4),
                             Text(
                                durationText,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.primaryColor.withOpacity(0.8),
                                  fontWeight: FontWeight.w500,
                                ),
                             ),
                          ],
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  price > 0 ? '£${price.toStringAsFixed(2)}' : 'N/A',
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
                                fontSize: 11,
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
      ),

        const SizedBox(height: 16),

        // Select Vehicle button
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: widget.isLoading || _selectedCategorySlug.isEmpty
                  ? null
                  : () {
                      final category = _categories.firstWhere(
                        (c) => c.slug == _selectedCategorySlug,
                        orElse: () => _categories.first,
                      );

                      // Use fare data from backend if available
                      final fareData =
                          _fareEstimates[_selectedCategorySlug] ??
                          {
                            'total_fare': 0.0,
                            'distance_text': 'Calculation pending',
                            'duration_text': 'Calculating...',
                            'duration_seconds': 600,
                          };

                      widget.onSelectVehicle(
                        _selectedCategorySlug,
                        category.name,
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
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Confirm ${(_categories.isNotEmpty && _selectedCategorySlug.isNotEmpty) ? _categories.firstWhere((c) => c.slug == _selectedCategorySlug).name : ""}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
