import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/models/error_display_helper.dart';
import '../../../core/models/toll_breakdown.dart';
import '../../../core/models/vehicle.dart';
import '../../../core/services/places_service.dart';
import '../../../core/services/vehicle_service.dart';
import '../../../core/theme.dart';

class VehicleSelectionWidget extends StatefulWidget {
  final Function(String) onVehicleSelected;
  final Function(
    String categorySlug,
    String categoryName,
    Map<String, dynamic> fareData,
  )
  onSelectVehicle;
  final Function(
    String categorySlug,
    String categoryName,
    Map<String, dynamic> fareData,
  )?
  onPrebookVehicle;
  final bool isLoading;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  final double? distance;
  final String? durationText;
  final Map<String, double>? fixedFareByCategory;
  final List<Map<String, dynamic>>? stops;

  const VehicleSelectionWidget({
    super.key,
    required this.onVehicleSelected,
    required this.onSelectVehicle,
    this.onPrebookVehicle,
    this.isLoading = false,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.distance,
    this.durationText,
    this.fixedFareByCategory,
    this.stops,
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
  Map<String, dynamic>? _promoResponse;
  TollInfo? _estimateToll;
  bool _isFetchingFares = false;
  String? _fareError;
  String? _fareErrorAction;
  int _fareFetchGen = 0;

  static const double _cardRadius = 16;
  static const double _pageHorizontal = 16;

  @override
  void didUpdateWidget(VehicleSelectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.stops != widget.stops ||
        oldWidget.pickupLat != widget.pickupLat ||
        oldWidget.pickupLng != widget.pickupLng ||
        oldWidget.dropoffLat != widget.dropoffLat ||
        oldWidget.dropoffLng != widget.dropoffLng ||
        oldWidget.distance != widget.distance) {
      _fareEstimates = {};
      _promoResponse = null;
      _estimateToll = null;
      _fetchFareEstimates();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    debugPrint('🚗 VehicleSelectionWidget: Loading categories from API...');
    setState(() => _isLoadingCategories = true);

    try {
      final categories = await _vehicleService.getVehicleCategories();
      if (!mounted) return;

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
      _fetchFareEstimates();
    } catch (e) {
      debugPrint('❌ VehicleSelectionWidget: Error loading categories: $e');
      if (!mounted) return;

      setState(() {
        _categories = _vehicleService.defaultCategories;
        _isLoadingCategories = false;
        if (_categories.isNotEmpty) {
          _selectedCategorySlug = _categories.first.slug;
        }
      });
    }
  }

  Future<void> _fetchFareEstimates() async {
    final gen = ++_fareFetchGen;
    bool stale() => gen != _fareFetchGen;

    if (widget.fixedFareByCategory != null) {
      setState(() => _isFetchingFares = true);

      for (final category in _categories) {
        final fixedPrice = widget.fixedFareByCategory?[category.slug] ?? 0.0;
        _fareEstimates[category.slug] = {
          'total_fare': fixedPrice,
          'distance_text': 'Fixed fare',
          'duration_text': 'Airport transfer',
          'duration_seconds': 0,
          'is_fixed_fare': true,
          'outstanding_balance': 0.0,
        };
      }

      if (mounted) {
        setState(() => _isFetchingFares = false);
      }
      return;
    }

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

    try {
      final promoData = await _placesService.getFareEstimate(
        pickupLat: widget.pickupLat!,
        pickupLon: widget.pickupLng!,
        dropoffLat: widget.dropoffLat!,
        dropoffLon: widget.dropoffLng!,
        distance: widget.distance ?? 0.0,
        stops: widget.stops,
      );

      if (stale()) return;

      if (mounted && promoData != null) {
        final estimatedDistance = promoData['estimatedDistance'];
        final duration = promoData['duration'];
        final distanceText = estimatedDistance != null
            ? '${(estimatedDistance as num).toStringAsFixed(2)} mi'
            : (widget.distance != null
                  ? '${widget.distance!.toStringAsFixed(1)} mi'
                  : '');
        final durationText =
            (duration is Map ? duration['text'] : null) ??
            widget.durationText ??
            '';

        setState(() {
          _promoResponse = promoData;
          _estimateToll = TollInfo.fromEstimate(promoData);
          _fareError = null;
          _fareErrorAction = null;

          final List<dynamic> categories = promoData['categories'] ?? [];
          for (var cat in categories) {
            if (cat is! Map) continue;

            final normalized = _normalizeCategory(
              Map<String, dynamic>.from(cat),
              distanceText: distanceText,
              durationText: durationText,
              durationSeconds: duration is Map
                  ? (duration['seconds'] as num?)?.toInt() ?? 0
                  : 0,
              distanceMiles: (estimatedDistance as num?)?.toDouble(),
            );

            if (normalized != null) {
              _fareEstimates[normalized['slug'] as String] = normalized['fare'];
            }
          }
        });

        debugPrint('✅ VehicleSelectionWidget: Got promo-aware fare estimates');
      } else {
        if (mounted) {
          final info = RideErrorMapper.map(
            'pickupLon, pickupLat, dropoffLon, dropoffLat, and distance are required',
          );
          setState(() {
            _fareError = '${info.title}: ${info.copy}';
            _fareErrorAction = info.actionLabel ?? 'Try again';
          });
        }

        debugPrint('⚠️ Falling back to sequential fare estimates');
        for (final category in _categories) {
          if (stale()) break;

          try {
            final result = await _placesService.getDistanceAndFare(
              originLat: widget.pickupLat!,
              originLng: widget.pickupLng!,
              destLat: widget.dropoffLat!,
              destLng: widget.dropoffLng!,
              categorySlug: category.slug,
            );

            if (mounted && result != null && !stale()) {
              setState(() {
                _fareEstimates[category.slug] = result;
              });
            }
          } catch (e) {
            debugPrint(
              '❌ VehicleSelectionWidget: Error getting fare for ${category.slug}: $e',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('❌ VehicleSelectionWidget: Error fetching fare estimates: $e');
      if (mounted && !stale()) {
        final info = RideErrorMapper.map(e.toString());
        setState(() {
          _fareError = '${info.title}: ${info.copy}';
          _fareErrorAction = info.actionLabel ?? 'Try again';
        });
      }
    }

    if (mounted && !stale()) {
      setState(() => _isFetchingFares = false);
    }
  }

  Map<String, dynamic>? _normalizeCategory(
    Map<String, dynamic> cat, {
    required String distanceText,
    required String durationText,
    required int durationSeconds,
    double? distanceMiles,
  }) {
    final slug = (cat['slug'] ?? cat['categorySlug'])?.toString();
    if (slug == null || slug.isEmpty) return null;

    num numOf(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

    final estimatedFare = numOf(cat['estimatedFare'] ?? cat['total_fare']);
    final originalFare = numOf(
      cat['originalFare'] ?? cat['original_fare'] ?? estimatedFare,
    );
    final promoApplied =
        cat['promoApplied'] == true || cat['isPromoApplied'] == true;
    final isFreeRide =
        cat['isFreeRide'] == true || (promoApplied && estimatedFare == 0);
    final discount = numOf(cat['discount'] ?? (originalFare - estimatedFare));
    final isCongestion = cat['isCongestionCharge'] == true;
    final congestionAmount = numOf(cat['congestionChargeAmount'] ?? 0);
    final outstandingRaw = numOf(
      cat['outstandingBalance'] ??
          cat['excessAmount'] ??
          cat['outstanding_balance'] ??
          0,
    );
    final outstandingBalance = outstandingRaw < 0 ? 0 : outstandingRaw;
    final seatingCapacity = (cat['seatingCapacity'] as num?)?.toInt();
    final toll = TollInfo.fromCategory(cat);

    return {
      'slug': slug,
      'fare': {
        'total_fare': estimatedFare.toDouble(),
        'original_fare': originalFare.toDouble(),
        'discount': (discount < 0 ? 0 : discount).toDouble(),
        'is_free_ride': isFreeRide,
        'promo_applied': promoApplied,
        'is_congestion': isCongestion,
        'congestion_amount': congestionAmount.toDouble(),
        'outstanding_balance': outstandingBalance.toDouble(),
        if (seatingCapacity != null) 'seating_capacity': seatingCapacity,
        if (toll.hasToll || toll.tollFee > 0) ...{
          'toll_fee': toll.tollFee,
          if (toll.tollName != null) 'toll_name': toll.tollName,
          'has_toll': toll.hasToll,
          if (toll.total != null) 'total_with_toll': toll.total,
        },
        'distance_text': distanceText,
        'distance_miles': distanceMiles ?? 0.0,
        'duration_text': durationText,
        'duration_seconds': durationSeconds,
      },
    };
  }

  String _categoryDisplayName(VehicleCategory category) {
    return category.name == category.slug || category.name == 'Unknown'
        ? VehicleCategory.formatSlug(category.slug)
        : category.name;
  }

  IconData _getVehicleIcon(String slug) {
    if (slug.contains('suv')) return Icons.directions_car_filled;
    if (slug.contains('van') || slug.contains('bus')) {
      return Icons.airport_shuttle;
    }
    if (slug.contains('hatchback')) return Icons.car_rental;
    return Icons.directions_car;
  }

  Widget _buildVehicleIconWidget(VehicleCategory category, bool isSelected) {
    final activeColor = isSelected ? AppTheme.primaryColor : Colors.grey[700]!;

    if (category.icon != null && category.icon!.isNotEmpty) {
      if (category.icon!.startsWith('data:image/svg')) {
        try {
          if (category.icon!.contains(';base64,')) {
            final base64String = category.icon!.split(';base64,').last;
            var normalizedBase64 = base64String;
            while (normalizedBase64.length % 4 != 0) {
              normalizedBase64 += '=';
            }
            return SvgPicture.memory(
              base64Decode(normalizedBase64),
              width: 34,
              height: 34,
              colorFilter: ColorFilter.mode(activeColor, BlendMode.srcIn),
            );
          }

          final parts = category.icon!.split(',');
          if (parts.length > 1) {
            final rawSvg = Uri.decodeComponent(parts.sublist(1).join(','));
            return SvgPicture.string(
              rawSvg,
              width: 34,
              height: 34,
              colorFilter: ColorFilter.mode(activeColor, BlendMode.srcIn),
            );
          }
        } catch (e) {
          debugPrint('Error parsing SVG icon: $e');
        }
      } else if (category.icon!.startsWith('<svg')) {
        try {
          return SvgPicture.string(
            category.icon!,
            width: 34,
            height: 34,
            colorFilter: ColorFilter.mode(activeColor, BlendMode.srcIn),
          );
        } catch (e) {
          debugPrint('Error parsing SVG string: $e');
        }
      } else if (category.icon!.startsWith('http')) {
        if (category.icon!.endsWith('.svg') ||
            category.icon!.contains('.svg?')) {
          return SvgPicture.network(
            category.icon!,
            width: 34,
            height: 34,
            colorFilter: ColorFilter.mode(activeColor, BlendMode.srcIn),
          );
        }

        return Image.network(
          category.icon!,
          width: 34,
          height: 34,
          color: activeColor,
        );
      }
    }

    return Icon(_getVehicleIcon(category.slug), size: 34, color: activeColor);
  }

  Widget _buildMetaItem({
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final resolvedColor = color ?? Colors.grey[600]!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: resolvedColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            height: 1.15,
            fontWeight: FontWeight.w500,
            color: resolvedColor,
          ),
        ),
      ],
    );
  }

  Widget _buildTollInline({
    required String? tollName,
    required double tollFee,
  }) {
    final label = (tollName == null || tollName.isEmpty)
        ? 'Toll +£${tollFee.toStringAsFixed(2)}'
        : 'Toll · $tollName +£${tollFee.toStringAsFixed(2)}';

    return SizedBox(
      width: double.infinity,
      child: Row(
        children: [
          Icon(Icons.toll_rounded, size: 16, color: Colors.blue.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(
                fontSize: 13,
                height: 1.15,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFare({
    required Map<String, dynamic>? fareData,
    required double payablePrice,
    required bool isSelected,
  }) {
    if (_isFetchingFares && fareData == null) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final isPromo = fareData?['promo_applied'] == true;
    final isFree = fareData?['is_free_ride'] == true;
    final originalFare = (fareData?['original_fare'] as num?)?.toDouble();
    final discount = (fareData?['discount'] as num?)?.toDouble() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (isPromo && originalFare != null)
          Text(
            '£${originalFare.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
              decoration: TextDecoration.lineThrough,
              fontWeight: FontWeight.w500,
              height: 1.1,
            ),
          ),
        if (isPromo && originalFare != null) const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              isFree
                  ? 'FREE'
                  : payablePrice > 0
                  ? '£${payablePrice.toStringAsFixed(2)}'
                  : 'N/A',
              style: TextStyle(
                fontSize: 19,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: isFree
                    ? AppTheme.successColor
                    : (isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.textPrimary),
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 15),
              ),
            ],
          ],
        ),
        if (isPromo && discount > 0) ...[
          const SizedBox(height: 3),
          Text(
            'Save £${discount.toStringAsFixed(2)}',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.15,
              fontWeight: FontWeight.w600,
              color: AppTheme.successColor,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVehicleRow({
    required VehicleCategory category,
    required Map<String, dynamic>? fareData,
    required bool isSelected,
    required bool isLast,
  }) {
    final price = (fareData?['total_fare'] as num?)?.toDouble() ?? 0.0;
    final seatingCapacity =
        (fareData?['seating_capacity'] as num?)?.toInt() ??
        category.seatingCapacity;
    final durationText =
        fareData?['duration_text']?.toString().isNotEmpty == true
        ? fareData!['duration_text'] as String
        : 'Calculating...';

    final catTollFee = (fareData?['toll_fee'] as num?)?.toDouble();
    final tollFee =
        catTollFee ??
        ((_estimateToll?.hasToll ?? false) ? _estimateToll!.tollFee : 0.0);
    final tollName = (fareData?['toll_name'] ?? _estimateToll?.tollName)
        ?.toString();
    final hasToll =
        fareData?['has_toll'] == true || (_estimateToll?.hasToll ?? false);
    final totalWithToll = (fareData?['total_with_toll'] as num?)?.toDouble();
    final payablePrice = (hasToll && totalWithToll != null)
        ? totalWithToll
        : price;

    final balance =
        (fareData?['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
    final isCongestion = fareData?['is_congestion'] == true;
    final congestionAmount =
        (fareData?['congestion_amount'] as num?)?.toDouble() ?? 0.0;
    final distanceText = fareData?['distance_text']?.toString() ?? '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _selectedCategorySlug = category.slug);
        widget.onVehicleSelected(category.slug);
      },
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryColor.withOpacity(0.055)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(_cardRadius),
              border: Border.all(
                color: isSelected
                    ? AppTheme.primaryColor.withOpacity(0.28)
                    : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryColor.withOpacity(0.10)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(_cardRadius),
                      ),
                      child: Center(
                        child: _buildVehicleIconWidget(category, isSelected),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  _categoryDisplayName(category),
                                  softWrap: true,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    height: 1.15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.15,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 112,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    _buildFare(
                                      fareData: fareData,
                                      payablePrice: payablePrice,
                                      isSelected: isSelected,
                                    ),
                                    if (distanceText.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        distanceText,
                                        textAlign: TextAlign.right,
                                        softWrap: false,
                                        style: TextStyle(
                                          fontSize: 11,
                                          height: 1.1,
                                          color: Colors.grey[500],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 12,
                            runSpacing: 5,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildMetaItem(
                                icon: Icons.person_outline_rounded,
                                label: '$seatingCapacity',
                              ),
                              _buildMetaItem(
                                icon: Icons.luggage_outlined,
                                label: '${category.luggage.suitcases}',
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 17,
                                    color: AppTheme.primaryColor,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    durationText,
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.15,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (tollFee > 0) ...[
                            const SizedBox(height: 7),
                            _buildTollInline(
                              tollName: tollName,
                              tollFee: tollFee,
                            ),
                          ],
                          if (isCongestion && congestionAmount > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              '+£${congestionAmount.toStringAsFixed(2)} congestion',
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber.shade800,
                              ),
                            ),
                          ],
                          if (isSelected && balance > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Includes £${balance.toStringAsFixed(2)} balance',
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber.shade800,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isLast)
            Padding(
              padding: const EdgeInsets.only(left: 102, right: 14),
              child: Divider(
                height: 1,
                thickness: 1,
                color: Colors.grey.shade200,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSkeletonRow({required bool isLast}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 74,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 15,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: 165,
                  height: 11,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 90,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 56,
                height: 17,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 42,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPromoBanner() {
    final cap = (_promoResponse?['promoCapAmount'] as num?)?.toDouble() ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        _pageHorizontal,
        4,
        _pageHorizontal,
        12,
      ),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.successColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.successColor.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.successColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_offer_outlined,
              color: AppTheme.successColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your free MK ride discount is applied — save up to £${cap.toStringAsFixed(2)}.',
              style: TextStyle(
                color: AppTheme.successColor,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFareError() {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        _pageHorizontal,
        4,
        _pageHorizontal,
        12,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Colors.red.shade700,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _fareError!,
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
          TextButton(
            onPressed: _isFetchingFares ? null : _fetchFareEstimates,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              _fareErrorAction ?? 'Retry',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  String _selectedCategoryName() {
    if (_categories.isEmpty || _selectedCategorySlug.isEmpty) return '';
    final category = _categories.firstWhere(
      (c) => c.slug == _selectedCategorySlug,
      orElse: () => _categories.first,
    );
    return _categoryDisplayName(category);
  }

  Map<String, dynamic> _selectedFareData() {
    return _fareEstimates[_selectedCategorySlug] ??
        {
          'total_fare': 0.0,
          'distance_text': 'Calculation pending',
          'duration_text': 'Calculating...',
          'duration_seconds': 600,
          'outstanding_balance': 0.0,
        };
  }

  void _handlePrebook() {
    if (widget.onPrebookVehicle == null ||
        widget.isLoading ||
        _selectedCategorySlug.isEmpty) {
      return;
    }

    final category = _categories.firstWhere(
      (c) => c.slug == _selectedCategorySlug,
      orElse: () => _categories.first,
    );

    widget.onPrebookVehicle?.call(
      _selectedCategorySlug,
      _categoryDisplayName(category),
      _selectedFareData(),
    );
  }

  void _handleConfirm() {
    if (widget.isLoading || _selectedCategorySlug.isEmpty) return;

    final category = _categories.firstWhere(
      (c) => c.slug == _selectedCategorySlug,
      orElse: () => _categories.first,
    );

    widget.onSelectVehicle(
      _selectedCategorySlug,
      _categoryDisplayName(category),
      _selectedFareData(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingCategories) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_categories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.directions_car_outlined,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                'No rides available',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Try a different pickup or destination.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    final showFareSkeleton =
        _isFetchingFares && _fareEstimates.isEmpty && _fareError == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_promoResponse != null && _promoResponse!['promoApplies'] == true)
          _buildPromoBanner(),
        if (_fareError != null) _buildFareError(),
        const Padding(
          padding: EdgeInsets.fromLTRB(_pageHorizontal, 6, _pageHorizontal, 10),
          child: Text(
            'Book now or later',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        if (_promoResponse != null && _promoResponse!['isOutOfArea'] == true)
          Padding(
            padding: const EdgeInsets.only(
              left: _pageHorizontal,
              right: _pageHorizontal,
              bottom: 8,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_off_outlined,
                  size: 14,
                  color: Colors.grey[500],
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Location is outside the Milton Keynes area',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: showFareSkeleton
              ? ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) => Column(
                    children: [
                      _buildSkeletonRow(
                        isLast: index == _categories.length - 1,
                      ),
                      if (index != _categories.length - 1)
                        Divider(
                          height: 1,
                          thickness: 1,
                          indent: 102,
                          endIndent: 16,
                          color: Colors.grey.shade100,
                        ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    final isLast = index == _categories.length - 1;
                    return Column(
                      children: [
                        _buildVehicleRow(
                          category: category,
                          fareData: _fareEstimates[category.slug],
                          isSelected: _selectedCategorySlug == category.slug,
                          isLast: isLast,
                        ),
                        if (!isLast)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: Colors.grey.shade200,
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            _pageHorizontal,
            6,
            _pageHorizontal,
            12 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            children: [
              if (widget.onPrebookVehicle != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: widget.isLoading || _selectedCategorySlug.isEmpty
                        ? null
                        : _handlePrebook,
                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: const Text(
                      'Prebook',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: widget.isLoading || _selectedCategorySlug.isEmpty
                      ? null
                      : _handleConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    disabledBackgroundColor: Colors.grey.shade300,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.grey.shade500,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  child: widget.isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Confirm ${_selectedCategoryName()}',
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
