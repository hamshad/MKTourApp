import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/services/places_service.dart';
import '../../core/models/vehicle.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/auth_provider.dart';

class DriverRequestPanel extends StatefulWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final Map<String, dynamic>? rideData;
  final bool isLoading;
  final String? acceptError;

  /// Full stacked queue. When absent, falls back to `[rideData]` so
  /// previews/tests calling with only `rideData` render exactly like today.
  final List<Map<String, dynamic>>? requests;

  /// Index into [requests] of the visible card. 0 = newest.
  final int requestIndex;

  /// Called with the newly selected index when the driver cycles cards
  /// (chevrons, dots, background rows). Never triggers accept/decline.
  final ValueChanged<int>? onSelectRequest;

  const DriverRequestPanel({
    super.key,
    required this.onAccept,
    required this.onDecline,
    this.rideData,
    this.isLoading = false,
    this.acceptError,
    this.requests,
    this.requestIndex = 0,
    this.onSelectRequest,
  });

  @override
  State<DriverRequestPanel> createState() => _DriverRequestPanelState();
}

class _DriverRequestPanelState extends State<DriverRequestPanel> {
  final PlacesService _placesService = PlacesService();
  String _pickupAddress = '';
  String _dropoffAddress = '';
  bool _isLoadingAddresses = true;

  static const int _addressCacheCapacity = 20;

  /// Bounded per-ride geocode cache: canonical rideId → {pickup, dropoff}.
  /// Display data only — fare/distance/passenger always read live.
  final Map<String, Map<String, String>> _addressCache = {};

  /// Same canonical keys as the home-screen queue (rideId/bookingId/_id/id).
  static String? _canonicalRideId(Map<String, dynamic>? r) {
    if (r == null) return null;
    for (final k in ['rideId', 'bookingId', '_id', 'id']) {
      final v = r[k]?.toString();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  void _storeInAddressCache(String rideId, String pickup, String dropoff) {
    _addressCache.remove(rideId); // refresh recency on rewrite
    while (_addressCache.length >= _addressCacheCapacity) {
      _addressCache.remove(_addressCache.keys.first); // oldest-first eviction
    }
    _addressCache[rideId] = {'pickup': pickup, 'dropoff': dropoff};
  }

  @override
  void initState() {
    super.initState();
    _fetchDetailedAddresses();
  }

  @override
  void didUpdateWidget(DriverRequestPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cycling cards swaps rideData — key on canonical rideId. Same card
    // (parent rebuild with a new map instance) keeps shown addresses with
    // no refetch. A seen card serves from cache instantly; only a cache
    // miss hits PlacesService. Background rows reuse payload strings.
    final oldId = _canonicalRideId(oldWidget.rideData);
    final newId = _canonicalRideId(widget.rideData);
    if (oldId == newId) return;
    final cached = newId != null ? _addressCache[newId] : null;
    if (cached != null) {
      setState(() {
        _pickupAddress = cached['pickup'] ?? '';
        _dropoffAddress = cached['dropoff'] ?? '';
        _isLoadingAddresses = false;
      });
    } else {
      setState(() {
        _pickupAddress = '';
        _dropoffAddress = '';
        _isLoadingAddresses = true;
      });
      _fetchDetailedAddresses();
    }
  }

  /// Effective stack: explicit `requests` when non-empty, else `[rideData]`.
  List<Map<String, dynamic>> get _effectiveRequests {
    if (widget.requests != null && widget.requests!.isNotEmpty) {
      return widget.requests!;
    }
    if (widget.rideData != null) return [widget.rideData!];
    return const [];
  }

  int get _effectiveIndex {
    final n = _effectiveRequests.length;
    if (n == 0) return 0;
    if (widget.requestIndex < 0) return 0;
    if (widget.requestIndex >= n) return n - 1;
    return widget.requestIndex;
  }

  void _selectRequest(int i) {
    final n = _effectiveRequests.length;
    if (n <= 1) return;
    var next = i % n;
    if (next < 0) next += n;
    if (next == _effectiveIndex) return;
    widget.onSelectRequest?.call(next);
  }

  /// Payload address string without any geocode lookup (background rows).
  static String _payloadAddress(Map<String, dynamic> r, bool pickup) {
    final key = pickup ? 'pickupLocation' : 'dropoffLocation';
    final loc = r[key];
    if (loc is Map && loc['address']?.toString().isNotEmpty == true) {
      return loc['address'].toString();
    }
    return pickup ? 'Pickup Location' : 'Dropoff Location';
  }

  static String _requestName(Map<String, dynamic> r) {
    final user = r['user'];
    if (user is Map && user['name']?.toString().isNotEmpty == true) {
      return user['name'].toString();
    }
    return 'Passenger';
  }

  static String _requestFare(Map<String, dynamic> r) {
    final fare = double.tryParse(r['fare']?.toString() ?? '') ?? 0.0;
    return '£${fare.toStringAsFixed(2)}';
  }

  static String _requestDistance(Map<String, dynamic> r) {
    final d = double.tryParse(r['distance']?.toString() ?? '') ?? 0.0;
    return '${d.toStringAsFixed(1)} mi';
  }

  Future<void> _fetchDetailedAddresses() async {
    if (widget.rideData == null) {
      setState(() => _isLoadingAddresses = false);
      return;
    }

    final rideId = _canonicalRideId(widget.rideData);
    final cached = rideId != null ? _addressCache[rideId] : null;
    if (cached != null) {
      // Cache hit (e.g. initState after a rebuild reseeded state) — no fetch.
      if (mounted) {
        setState(() {
          _pickupAddress = cached['pickup'] ?? '';
          _dropoffAddress = cached['dropoff'] ?? '';
          _isLoadingAddresses = false;
        });
      }
      return;
    }

    // Fetch pickup address
    if (widget.rideData!['pickupLocation']?['coordinates'] != null) {
      final pickupCoords = widget.rideData!['pickupLocation']['coordinates'];
      final pickupLat = pickupCoords[1];
      final pickupLng = pickupCoords[0];

      final pickupAddr = await _placesService.getAddressFromLatLng(
        pickupLat,
        pickupLng,
      );
      if (mounted) {
        setState(() {
          _pickupAddress =
              pickupAddr ??
              widget.rideData!['pickupLocation']?['address'] ??
              'Pickup Location';
        });
      }
    }

    // Fetch dropoff address
    if (widget.rideData!['dropoffLocation']?['coordinates'] != null) {
      final dropoffCoords = widget.rideData!['dropoffLocation']['coordinates'];
      final dropoffLat = dropoffCoords[1];
      final dropoffLng = dropoffCoords[0];

      final dropoffAddr = await _placesService.getAddressFromLatLng(
        dropoffLat,
        dropoffLng,
      );
      if (mounted) {
        setState(() {
          _dropoffAddress =
              dropoffAddr ??
              widget.rideData!['dropoffLocation']?['address'] ??
              'Dropoff Location';
        });
      }
    }

    if (mounted) {
      // Store what is actually displayed so a revisit serves from cache.
      // Guard on rideId: a rapid card flip may leave this fetch stale.
      if (rideId != null &&
          _canonicalRideId(widget.rideData) == rideId &&
          (_pickupAddress.isNotEmpty || _dropoffAddress.isNotEmpty)) {
        _storeInAddressCache(
          rideId,
          _pickupAddress.isNotEmpty
              ? _pickupAddress
              : (widget.rideData!['pickupLocation']?['address']?.toString() ??
                    'Pickup Location'),
          _dropoffAddress.isNotEmpty
              ? _dropoffAddress
              : (widget.rideData!['dropoffLocation']?['address']?.toString() ??
                    'Dropoff Location'),
        );
      }
      setState(() => _isLoadingAddresses = false);
    }
  }

  /// Get display name for vehicle type from backend
  /// Handles the exact backend keys: sedan, suv, hatchback, van
  String _getVehicleDisplayName(String? vehicleCategorySlug) {
    return VehicleCategory.formatSlug(vehicleCategorySlug);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: SingleChildScrollView(
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
          const SizedBox(height: 10),
          // Ride Message / Fallback Alert Banner
          Builder(
            builder: (context) {
              final driverUser = Provider.of<AuthProvider>(context, listen: false).user;
              final driverCategory = driverUser?['vehicle']?['categorySlug']?.toString();
              final requestedCategory = widget.rideData?['vehicleCategorySlug']?.toString();
              final isFallback = widget.rideData?['isFallback']?.toString().toLowerCase() == 'true';
              final hasMessage = widget.rideData?['message'] != null || widget.rideData?['fallbackNote'] != null;
              
              // Hide message if categories match AND it's not a fallback
              // (Redundant for a driver to see "This is a 4-seater request" if they ARE a 4-seater)
              // Normalizing slugs by lowercasing for comparison
              final bool shouldHideMessage = !isFallback && 
                                           driverCategory != null && 
                                           requestedCategory != null && 
                                           driverCategory.toLowerCase() == requestedCategory.toLowerCase();
              
              if (hasMessage && !shouldHideMessage) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isFallback 
                        ? Colors.orange[50] 
                        : AppTheme.primaryColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isFallback
                          ? Colors.orange[200]!
                          : AppTheme.primaryColor.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                       Icon(
                         isFallback
                             ? Icons.info_outline
                             : Icons.message_outlined,
                         color: isFallback
                             ? Colors.orange[800]
                             : AppTheme.primaryColor,
                         size: 20,
                       ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.rideData?['message'] ?? 
                          widget.rideData?['fallbackNote'] ?? 
                          'This is a specialized ride request.',
                          style: TextStyle(
                            color: isFallback
                                ? Colors.orange[900]
                                : AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.rideData?['isScheduled'] == true
                    ? 'Scheduled Ride Request'
                    : 'New Ride Request',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_effectiveRequests.length > 1)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.primaryColor.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        '${_effectiveIndex + 1} of ${_effectiveRequests.length}',
                        style: const TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
              if (widget.rideData?['isFallback']?.toString().toLowerCase() == 'true')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'FALLBACK',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (widget.rideData?['isPriority'] == true)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.rideData?['isFallback']?.toString().toLowerCase() == 'true')
                      const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'PRIORITY',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ],
              ),
            ],
          ),
          // Stack cycling controls (only when 2+ queued) — snug row with
          // 44px+ touch targets; tight spacing so no dead gap sits below it.
          if (_effectiveRequests.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    iconSize: 26,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    color: AppTheme.primaryColor,
                    tooltip: 'Previous request',
                    onPressed: widget.isLoading
                        ? null
                        : () => _selectRequest(_effectiveIndex - 1),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      _effectiveRequests.length,
                      (i) => GestureDetector(
                        onTap: widget.isLoading
                            ? null
                            : () => _selectRequest(i),
                        child: Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _effectiveIndex
                                ? AppTheme.primaryColor
                                : Colors.grey[300],
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    iconSize: 26,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    color: AppTheme.primaryColor,
                    tooltip: 'Next request',
                    onPressed: widget.isLoading
                        ? null
                        : () => _selectRequest(_effectiveIndex + 1),
                  ),
                ],
              ),
            ),
          // Tight when stacked (cycle row sits snug); unchanged for single.
          if (_effectiveRequests.length > 1)
            const SizedBox(height: 2)
          else
            const SizedBox(height: 12),
          if (widget.rideData?['isScheduled'] == true)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, color: AppTheme.primaryColor, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '📅 Scheduled Pickup',
                          style: TextStyle(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          DateFormat('EEEE, MMM d @ hh:mm a').format(
                            DateTime.parse(widget.rideData!['scheduledPickupTime']).toLocal(),
                          ),
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // Tight when stacked; single-request gap unchanged.
          if (_effectiveRequests.length > 1)
            const SizedBox(height: 12)
          else
            const SizedBox(height: 24),

          // Passenger Info Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.rideData?['isFallback']?.toString().toLowerCase() == 'true' 
                  ? Colors.orange[50]!.withOpacity(0.3) 
                  : Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.rideData?['isFallback']?.toString().toLowerCase() == 'true'
                    ? Colors.orange[200]!
                    : Colors.grey[200]!,
                width: widget.rideData?['isFallback']?.toString().toLowerCase() == 'true' ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: widget.rideData?['isFallback']?.toString().toLowerCase() == 'true'
                      ? Colors.orange[100]
                      : Colors.white,
                  child: Icon(
                    widget.rideData?['isFallback']?.toString().toLowerCase() == 'true'
                        ? Icons.swap_calls
                        : Icons.person,
                    size: 30,
                    color: widget.rideData?['isFallback']?.toString().toLowerCase() == 'true'
                        ? Colors.orange[800]
                        : AppTheme.textSecondary,
                  ),
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
                      Row(
                        children: [
                          // Show driver's own vehicle type here
                          Builder(
                            builder: (context) {
                              final driverUser =
                                  Provider.of<AuthProvider>(context, listen: false)
                                      .user;
                              final driverCategory =
                                  driverUser?['vehicle']?['categorySlug']?.toString();
                              return Text(
                                _getVehicleDisplayName(driverCategory),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.textSecondary,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Display fare from backend (already calculated with surge/night/weekend)
                    Text(
                      '£${double.tryParse(widget.rideData?['fare']?.toString() ?? '0.0')?.toStringAsFixed(2) ?? '0.00'}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.rideData?['isAirportTransfer'] == true) ...[
                          const Icon(
                            Icons.flight,
                            size: 14,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          widget.rideData?['isFallback']?.toString().toLowerCase() == 'true'
                              ? 'Standard 5-Seater Rate'
                              : 'Est. Fare',
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.rideData?['isFallback']?.toString().toLowerCase() == 'true'
                                ? Colors.orange[800]
                                : Colors.grey[500],
                            fontWeight: widget.rideData?['isFallback']?.toString().toLowerCase() == 'true'
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
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
                  const Icon(
                    Icons.my_location,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
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
                          : (_pickupAddress.isNotEmpty
                                ? _pickupAddress
                                : (widget.rideData?['pickupLocation']?['address'] ??
                                      'Pickup Location')),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: _isLoadingAddresses
                            ? Colors.grey
                            : AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _isLoadingAddresses
                          ? 'Loading address...'
                          : (_dropoffAddress.isNotEmpty
                                ? _dropoffAddress
                                : (widget.rideData?['dropoffLocation']?['address'] ??
                                      'Dropoff Location')),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: _isLoadingAddresses
                            ? Colors.grey
                            : AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      '${double.tryParse(widget.rideData?['distance']?.toString() ?? '0.0')?.toStringAsFixed(1) ?? '0.0'} mi trip',
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

          // Accept Error Banner
          if (widget.acceptError != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700], size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.acceptError!,
                      style: TextStyle(
                        color: Colors.red[800],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Action Buttons — pinned directly under the visible card
          // (route details + error banner), independent of stack size.
          // Single-request layout unchanged (no extra gap injected).
          if (_effectiveRequests.length > 1 && widget.acceptError == null)
            const SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                  onPressed: widget.isLoading ? null : widget.onDecline,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    side: BorderSide(
                      color: Colors.red.withOpacity(0.5),
                      width: 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: widget.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.red,
                          ),
                        )
                      : const Text(
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
                  onPressed: widget.isLoading ? null : widget.onAccept,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    backgroundColor: AppTheme.primaryColor,
                    elevation: 8,
                    shadowColor: AppTheme.primaryColor.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: widget.isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Accept Ride',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                ),
              ),
            ],
            ),
          ),

          // Other stacked requests — compact strip BELOW the action bar so
          // Accept/Decline never dive down the sheet. Payload strings only.
          if (_effectiveRequests.length > 1) ...[
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Other requests (${_effectiveRequests.length - 1})',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                ...List.generate(_effectiveRequests.length, (i) {
                  if (i == _effectiveIndex) return const SizedBox.shrink();
                  final r = _effectiveRequests[i];
                  return GestureDetector(
                    onTap: widget.isLoading ? null : () => _selectRequest(i),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            size: 16,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _requestName(r),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  _payloadAddress(r, true),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _requestFare(r),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                              Text(
                                _requestDistance(r),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
      ),
    );
  }
}
