import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/services/places_service.dart';
import '../../../core/services/vehicle_service.dart';
import '../../../core/models/vehicle.dart';
import '../../../core/models/error_display_helper.dart';
import '../../../core/models/toll_breakdown.dart';
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
  onPrebookVehicle; // Callback for prebook button
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
  // Route-level toll from the fare-estimate TOP-LEVEL map (§1.1
  // `hasToll`/`tollDetails`) — fallback for categories that carry no
  // per-category toll keys. Parsed once per fetch via TollInfo.fromEstimate.
  TollInfo? _estimateToll;
  bool _isFetchingFares = false;
  String? _fareError;
  String? _fareErrorAction;
  // Fetch generation: a slow earlier response (e.g. no-stops route) must
  // not repopulate estimates after a newer stops-change fetch started.
  int _fareFetchGen = 0;

  /// Check if current fetch generation is stale (a newer fetch started).
  bool _isStale(int gen) => gen != _fareFetchGen;

  @override
  void didUpdateWidget(VehicleSelectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Stops change the price — refetch estimates when stops or route change.
    if (oldWidget.stops != widget.stops ||
        oldWidget.pickupLat != widget.pickupLat ||
        oldWidget.pickupLng != widget.pickupLng ||
        oldWidget.dropoffLat != widget.dropoffLat ||
        oldWidget.dropoffLng != widget.dropoffLng ||
        oldWidget.distance != widget.distance) {
      // Drop stale estimates immediately: keeping them made old (no-stops)
      // fares selectable while the refetch ran — booking at the base fare.
      // Empty map + _isFetchingFares shows the fare skeleton instead.
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

        // Fetch fare estimates only once route distance is known —
        // fetching with distance 0.0 first causes a visible fare flip
        // when the real-distance refetch lands.
        if (widget.distance != null) {
          _fetchFareEstimates();
        }
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
    final gen = ++_fareFetchGen;

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
      // Use new fare-estimate endpoint which handles promo logically
      Map<String, dynamic>? promoData;
      try {
        promoData = await _placesService.getFareEstimate(
          pickupLat: widget.pickupLat!,
          pickupLon: widget.pickupLng!,
          dropoffLat: widget.dropoffLat!,
          dropoffLon: widget.dropoffLng!,
          distance: widget.distance ?? 0.0,
          stops: widget.stops,
        );
      } on Exception catch (e) {
        // getFareEstimate throws on 400 with the backend error message
        debugPrint('🔴 [VehicleSelectionWidget] Fare estimate failed: $e');
if (mounted && !_isStale(gen)) {
          final info = RideErrorMapper.map(e.toString());
          setState(() {
            _fareError = '${info.title}: ${info.copy}';
            _fareErrorAction = info.actionLabel ?? 'Try again';
          });
        }
        promoData = null; // Will trigger fallback
      }

      if (_isStale(gen)) {
        // A newer fetch (stops/route change) superseded this one — it owns
        // _isFetchingFares and the estimate map now.
        return;
      }

      if (mounted && promoData != null) {
        // Extract shared distance/duration from API response top-level
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
          // Top-level toll (§1.1 hasToll/tollDetails) — parsed once for the
          // whole route; per-category toll keys still win when present.
          _estimateToll = TollInfo.fromEstimate(promoData);
          _fareError = null;
          _fareErrorAction = null;
          final List<dynamic> categories = (promoData?['categories'] as List<dynamic>?) ?? [];
          for (var cat in categories) {
            if (cat is! Map) continue;
            final normalized = _normalizeCategory(
              Map<String, dynamic>.from(cat),
              distanceText: distanceText,
              durationText: durationText,
              durationSeconds: duration is Map
                  ? (duration['seconds'] as num?)?.toInt() ?? 0
                  : 0,
              // Top-level routed distance (includes stops) — the per-category
              // objects carry no numeric distance, and without this the
              // booking screens send distance 0.0 so backend underprices.
              distanceMiles: (estimatedDistance as num?)?.toDouble(),
            );
            if (normalized != null) {
              _fareEstimates[normalized['slug'] as String] = normalized['fare'];
            }
          }
        });
        debugPrint('✅ VehicleSelectionWidget: Got promo-aware fare estimates');
        // Only fill categories the promo batch did NOT return — never
        // overwrite promo-aware fares with sequential ones (they differ).
        if (mounted && !_isStale(gen)) {
          final missing = _categories
              .where((c) => !_fareEstimates.containsKey(c.slug))
              .map((c) => c.slug)
              .toList();
          if (missing.isNotEmpty) {
            await _promoteFallbackFares(gen, onlySlugs: missing);
          }
        }
        return;
      }

      // Fallback: sequential fare estimates (only if promo endpoint failed)
      debugPrint('⚠️ Falling back to sequential fare estimates');
      await _promoteFallbackFares(gen);
    } catch (e) {
      debugPrint('❌ VehicleSelectionWidget: Error fetching fare estimates: $e');
      if (mounted && !_isStale(gen)) {
        final info = RideErrorMapper.map(e.toString());
        setState(() {
          _fareError = '${info.title}: ${info.copy}';
          _fareErrorAction = info.actionLabel ?? 'Try again';
        });
      }
    }

    if (mounted && !_isStale(gen)) {
      setState(() => _isFetchingFares = false);
    }
  }

  /// Fallback to sequential per-category fare estimates (used when
  /// the promo-aware batch endpoint fails, e.g. service area restriction,
  /// or when specific categories are missing from the batch response).
  Future<void> _promoteFallbackFares(int gen, {List<String>? onlySlugs}) async {
    debugPrint('⚠️ Promoting fallback sequential fare estimates');
    final targets = onlySlugs == null
        ? _categories
        : _categories.where((c) => onlySlugs.contains(c.slug)).toList();
    for (final category in targets) {
      if (_isStale(gen)) break;
      try {
        final result = await _placesService.getDistanceAndFare(
          originLat: widget.pickupLat!,
          originLng: widget.pickupLng!,
          destLat: widget.dropoffLat!,
          destLng: widget.dropoffLng!,
          categorySlug: category.slug,
        );

        if (mounted && result != null && !_isStale(gen)) {
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

  /// Normalize one fare-estimate category into the card's unified shape.
  ///
  /// Handles the new flow shape (`categorySlug`, `estimatedFare`,
  /// `isPromoApplied`, `isCongestionCharge`, `congestionChargeAmount`,
  /// `seatingCapacity`) and the legacy promo shape (`slug`, `promoApplied`,
  /// `discount`, `isFreeRide`). Returns null when the entry has no slug.
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
    // Backend already folds unpaid balance into estimatedFare — surface the
    // split only, never add it to the total (no double-count).
    final outstandingRaw = numOf(
      cat['outstandingBalance'] ??
          cat['excessAmount'] ??
          cat['outstanding_balance'] ??
          0,
    );
    final outstandingBalance = (outstandingRaw < 0 ? 0 : outstandingRaw);
    final seatingCapacity = (cat['seatingCapacity'] as num?)?.toInt();
    // Toll chain (§1.1 per-category tollFee/totalFare via the shared
    // never-throw parser). Absent-toll categories add NO keys — the fare
    // map stays byte-identical to today's shape (TOLL-08 baseline).
    // `slug`/`estimatedFare` chains above stay first/authoritative.
    final toll = TollInfo.fromCategory(cat);
    // Route-level estimate toll is the fallback exactly as in the card row:
    // the backend commonly sends `tollDetails {name, amount}` at the TOP
    // level only, so a per-category parse finds the fee but no name. Without
    // this the confirm screen — which reads `toll_name` off the fare map —
    // would lose the name the vehicle card showed. Per-category keys still
    // win, so a spec-shaped response is unchanged (TOLL-08 baseline intact:
    // when no toll exists anywhere, the spread below adds NO keys).
    final routeToll = _estimateToll;
    final tollPresent =
        toll.hasToll || toll.tollFee > 0 || (routeToll?.hasToll ?? false);
    final tollFee = toll.tollFee > 0 ? toll.tollFee : (routeToll?.tollFee ?? 0.0);
    final tollName = toll.tollName ?? routeToll?.tollName;
    final tollTotal = toll.total ?? routeToll?.total;

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
        if (tollPresent) ...{
          'toll_fee': tollFee,
          if (tollName != null && tollName.isNotEmpty) 'toll_name': tollName,
          'has_toll': toll.hasToll || (routeToll?.hasToll ?? false),
          if (tollTotal != null) 'total_with_toll': tollTotal,
        },
        'distance_text': distanceText,
        'distance_miles': distanceMiles ?? 0.0,
        'duration_text': durationText,
        'duration_seconds': durationSeconds,
      },
    };
  }

  /// Get icon for vehicle category
  IconData _getVehicleIcon(String slug) {
    if (slug.contains('suv')) return Icons.directions_car_filled;
    if (slug.contains('van') || slug.contains('bus'))
      return Icons.airport_shuttle;
    if (slug.contains('hatchback')) return Icons.car_rental;
    return Icons.directions_car;
  }

  Widget _buildVehicleIconWidget(VehicleCategory category, bool isSelected) {
    if (category.icon != null && category.icon!.isNotEmpty) {
      if (category.icon!.startsWith('data:image/svg')) {
        try {
          if (category.icon!.contains(';base64,')) {
            final base64String = category.icon!.split(';base64,').last;
            // Pad the base64 string if necessary
            String normalizedBase64 = base64String;
            while (normalizedBase64.length % 4 != 0) {
              normalizedBase64 += '=';
            }
            return SvgPicture.memory(
              base64Decode(normalizedBase64),
              width: 32,
              height: 32,
              colorFilter: ColorFilter.mode(
                isSelected ? AppTheme.primaryColor : Colors.grey[700]!,
                BlendMode.srcIn,
              ),
            );
          } else {
            final parts = category.icon!.split(',');
            if (parts.length > 1) {
              final rawSvg = Uri.decodeComponent(parts.sublist(1).join(','));
              return SvgPicture.string(
                rawSvg,
                width: 32,
                height: 32,
                colorFilter: ColorFilter.mode(
                  isSelected ? AppTheme.primaryColor : Colors.grey[700]!,
                  BlendMode.srcIn,
                ),
              );
            }
          }
        } catch (e) {
          debugPrint('Error parsing SVG icon: $e');
        }
      } else if (category.icon!.startsWith('<svg')) {
        // Direct SVG string
        try {
          return SvgPicture.string(
            category.icon!,
            width: 32,
            height: 32,
            colorFilter: ColorFilter.mode(
              isSelected ? AppTheme.primaryColor : Colors.grey[700]!,
              BlendMode.srcIn,
            ),
          );
        } catch (e) {
          debugPrint('Error parsing SVG string: $e');
        }
      } else if (category.icon!.startsWith('http')) {
        // Network SVG or Image
        if (category.icon!.endsWith('.svg') ||
            category.icon!.contains('.svg?')) {
          return SvgPicture.network(
            category.icon!,
            width: 32,
            height: 32,
            colorFilter: ColorFilter.mode(
              isSelected ? AppTheme.primaryColor : Colors.grey[700]!,
              BlendMode.srcIn,
            ),
          );
        } else {
          return Image.network(
            category.icon!,
            width: 32,
            height: 32,
            color: isSelected ? AppTheme.primaryColor : Colors.grey[700],
          );
        }
      }
    }

    // Fallback
    return Icon(
      _getVehicleIcon(category.slug),
      size: 32,
      color: isSelected ? AppTheme.primaryColor : Colors.grey[700],
    );
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

    if (_categories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
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
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Try a different pickup or destination.',
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
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.successColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.successColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.card_giftcard,
                  color: AppTheme.successColor,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your free MK ride discount is applied — save up to £${(_promoResponse!['promoCapAmount'] as num?)?.toStringAsFixed(2) ?? "0.00"}!',
                    style: const TextStyle(
                      color: AppTheme.successColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Fare estimate failure → inline retry row, never silent empty list.
        if (_fareError != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _fareError!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _isFetchingFares ? null : _fetchFareEstimates,
                  child: Text(_fareErrorAction ?? 'Retry'),
                ),
              ],
            ),
          ),

        // "Book now or later" - Top text outside the box
        const Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 14, bottom: 0),
          child: Text(
            'Book now or later',
            style: TextStyle(
              fontSize: 20,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        if (_promoResponse != null && _promoResponse!['isOutOfArea'] == true)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Text(
              '* Location is outside the Milton Keynes area',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),

        // Box containing "Choose a ride" and vehicle list
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // "Choose a ride" title inside the box
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    'Choose a ride',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                ),

                // Categories list (fetched from API)
                Expanded(
                  child: showFareSkeleton
                      ? ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _categories.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Row(
                              children: [
                                Container(
                                  width: 60,
                                  height: 50,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 120,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        width: 80,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _categories.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final category = _categories[index];
                            final isSelected =
                                _selectedCategorySlug == category.slug;

                            // Get fare estimate
                            final fareData = _fareEstimates[category.slug];
                            final price =
                                (fareData?['total_fare'] as num?)?.toDouble() ??
                                0.0;
                            final seatingCapacity =
                                (fareData?['seating_capacity'] as num?)
                                    ?.toInt() ??
                                category.seatingCapacity;
                            final durationText =
                                fareData?['duration_text']
                                        ?.toString()
                                        .isNotEmpty ==
                                    true
                                ? fareData!['duration_text'] as String
                                : 'Calculating...';

                            // Toll (§1.1, TOLL-01): per-category toll keys win; the
                            // route-level estimate toll (hasToll/tollDetails) is the
                            // fallback when the category entry carries none — never both,
                            // so a spec-shaped response shows the toll exactly once.
                            final catTollFee = (fareData?['toll_fee'] as num?)
                                ?.toDouble();
                            final tollFee =
                                catTollFee ??
                                ((_estimateToll?.hasToll ?? false)
                                    ? _estimateToll!.tollFee
                                    : 0.0);
                            final hasToll =
                                fareData?['has_toll'] == true ||
                                (_estimateToll?.hasToll ?? false);
                            final totalWithToll =
                                (fareData?['total_with_toll'] as num?)
                                    ?.toDouble();
                            // Backend-authoritative payable total (spec totalFare) when the
                            // category carries a toll; otherwise today's price untouched.
                            final payablePrice =
                                (hasToll && totalWithToll != null)
                                ? totalWithToll
                                : price;

                            return InkWell(
                              onTap: () {
                                setState(
                                  () => _selectedCategorySlug = category.slug,
                                );
                                widget.onVehicleSelected(category.slug);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.surfaceColor
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: isSelected
                                      ? Border.all(
                                          color: AppTheme.primaryColor,
                                          width: 2,
                                        )
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    // Vehicle Icon
                                    Container(
                                      width: 60,
                                      height: 50,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: _buildVehicleIconWidget(
                                        category,
                                        isSelected,
                                      ),
                                    ),

                                    // Details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            category.name == category.slug ||
                                                    category.name == 'Unknown'
                                                ? VehicleCategory.formatSlug(
                                                    category.slug,
                                                  )
                                                : category.name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          // Wrap (not Row + Expanded): the seating
                                          // capacity must never be ellipsized. Icon +
                                          // number keeps it compact; when space runs out
                                          // the chips wrap to a second row instead.
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 2,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.people_alt,
                                                    size: 14,
                                                    color: Colors.grey[500],
                                                  ),
                                                  Text(
                                                    ' $seatingCapacity',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.luggage,
                                                    size: 14,
                                                    color: Colors.grey[500],
                                                  ),
                                                  Text(
                                                    ' ${category.luggage.suitcases}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.shopping_bag,
                                                    size: 14,
                                                    color: Colors.grey[500],
                                                  ),
                                                  Text(
                                                    ' ${category.luggage.smallCases}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          if (fareData != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              durationText,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.primaryColor
                                                    .withOpacity(0.8),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),

// Price (from backend)
                                     //
                                     // Align(centerRight) is required: a loose Flexible
                                     // shrink-wraps to its widest child, so without it the
                                     // column sits at the START of its slot and the price /
                                     // toll / distance float away from the card's right edge.
                                     Flexible(
                                       child: Align(
                                         alignment: Alignment.centerRight,
                                         child: Padding(
                                           padding: const EdgeInsets.only(
                                             right: 12,
                                           ),
                                           child: Column(
                                             crossAxisAlignment:
                                                 CrossAxisAlignment.end,
                                             children: [
                                            _isFetchingFares && fareData == null
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.end,
                                                    children: [
                                                      if (fareData?['promo_applied'] ==
                                                              true &&
                                                          fareData?['original_fare'] !=
                                                              null) ...[
                                                        Text(
                                                          '£${(fareData!['original_fare'] as num).toStringAsFixed(2)}',
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight
                                                                    .normal,
                                                            color: Colors
                                                                .grey[500],
                                                            decoration:
                                                                TextDecoration
                                                                    .lineThrough,
                                                          ),
                                                        ),
                                                        Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                              fareData?['is_free_ride'] ==
                                                                      true
                                                                  ? 'FREE'
                                                                  : '£${payablePrice.toStringAsFixed(2)}',
                                                              style: TextStyle(
                                                                fontSize: 18,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color:
                                                                    fareData?['is_free_ride'] ==
                                                                        true
                                                                    ? AppTheme
                                                                          .successColor
                                                                    : (isSelected
                                                                          ? AppTheme.primaryColor
                                                                          : AppTheme.textPrimary),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 4,
                                                            ),
                                                            const Icon(
                                                              Icons
                                                                  .card_giftcard,
                                                              size: 16,
                                                              color: AppTheme
                                                                  .successColor,
                                                            ),
                                                            const SizedBox(
                                                              width: 4,
                                                            ),
                                                            Text(
                                                              '-£${(fareData!['discount'] as num).toStringAsFixed(2)}',
                                                              style: const TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: AppTheme
                                                                    .successColor,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ] else ...[
Text(
                                                           payablePrice > 0
                                                               ? '£${payablePrice.toStringAsFixed(2)}'
                                                               : 'N/A',
                                                           maxLines: 1,
                                                           softWrap: false,
                                                           textAlign:
                                                               TextAlign.right,
                                                           style: TextStyle(
                                                             fontSize: 18,
                                                             fontWeight:
                                                                 FontWeight.bold,
                                                             color: isSelected
                                                                 ? AppTheme
                                                                       .primaryColor
                                                                 : AppTheme
                                                                       .textPrimary,
                                                           ),
                                                         ),
                                                      ],
                                                    ],
                                                  ),
                                            // Toll (§1.1, TOLL-01): minimal one-line caption
                                            // between the price and the distance — amount only,
                                            // the toll name is deliberately NOT surfaced here
                                            // (it lives on the confirm screen). Absent/0 omits
                                            // the widget entirely — no £0.00, no layout shift
                                            // (TOLL-08). `softWrap: false` + explicit right align keeps its
                                            // right edge locked to the price's regardless of
                                            // font size differences.
                                            if (fareData != null && tollFee > 0)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 2,
                                                ),
                                                child: Text(
                                                  'Toll +£${tollFee.toStringAsFixed(2)}',
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  textAlign: TextAlign.right,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.blue.shade800,
                                                  ),
                                                ),
                                              ),
                                            if (fareData != null)
                                              Text(
                                                fareData['distance_text'] ?? '',
                                                maxLines: 1,
                                                softWrap: false,
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[500],
                                                ),
                                              ),
                                            // Congestion charge badge (new flow)
                                            if (fareData?['is_congestion'] ==
                                                true)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color:
                                                        Colors.amber.shade200,
                                                  ),
                                                ),
                                                child: Text(
                                                  '+£${((fareData!['congestion_amount'] as num?) ?? 0).toStringAsFixed(2)} congestion',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        Colors.amber.shade800,
                                                  ),
                                                ),
                                              ),
// Outstanding-balance split (Phase 15): caption under
                                            // the selected-category price when the fare map
                                            // carries balance > 0. Backend total shown as-is.
                                            if (isSelected &&
                                                ((fareData?['outstanding_balance']
                                                                as num?)
                                                            ?.toDouble() ??
                                                        0.0) >
                                                    0)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 2,
                                                ),
                                                child: Text(
                                                  'incl. £${((fareData!['outstanding_balance'] as num).toDouble()).toStringAsFixed(2)} balance',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                    color:
                                                        Colors.amber.shade800,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),

        // Select Vehicle button and Prebook button
        Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            children: [
              // Prebook button - Small text button with icon
              if (widget.onPrebookVehicle != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: widget.isLoading || _selectedCategorySlug.isEmpty
                        ? null
                        : () {
                            final category = _categories.firstWhere(
                              (c) => c.slug == _selectedCategorySlug,
                              orElse: () => _categories.first,
                            );

                            final fareData =
                                _fareEstimates[_selectedCategorySlug] ??
                                {
                                  'total_fare': 0.0,
                                  'distance_text': 'Calculation pending',
                                  'duration_text': 'Calculating...',
                                  'duration_seconds': 600,
                                  'outstanding_balance': 0.0,
                                };

                            widget.onPrebookVehicle?.call(
                              _selectedCategorySlug,
                              category.name,
                              fareData,
                            );
                          },
                    icon: const Icon(Icons.calendar_month, size: 18),
                    label: const Text(
                      'Prebook',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              // Confirm button - Full width primary button
              SizedBox(
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
                                'outstanding_balance': 0.0,
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
            ],
          ),
        ),
      ],
    );
  }
}
