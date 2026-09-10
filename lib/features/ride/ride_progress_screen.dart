import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme.dart';
import '../../core/widgets/platform_map.dart';
import '../../core/widgets/ride_searching_overlay.dart';
import '../../core/services/socket_service.dart';
import '../../core/services/navigation_service.dart';
import '../../core/services/places_service.dart';
import '../../core/api_service.dart';
import '../../core/models/vehicle.dart';
import 'ride_complete_screen.dart';

class RideProgressScreen extends StatefulWidget {
  final String? rideId;
  final List<RideStop>? initialStops;
  final Map<String, dynamic>? driver;

  const RideProgressScreen({
    super.key,
    this.rideId,
    this.initialStops,
    this.driver,
  });

  @override
  State<RideProgressScreen> createState() => _RideProgressScreenState();
}

class _RideProgressScreenState extends State<RideProgressScreen> {
  String _status = 'Finding your driver...';
  String _rideStatus = 'accepted';
  double _progress = 0.2;

  // Live Tracking
  final SocketService _socketService = SocketService();
  final NavigationService _navigationService = NavigationService();
  final PlacesService _placesService = PlacesService();
  final ApiService _apiService = ApiService();
  LatLng _driverLocation = const LatLng(51.5074, -0.1278); // Default fallback
  LatLng _userLocation = const LatLng(51.5085, -0.1260); // Default user loc
  LatLng _dropoffLocation = const LatLng(51.5100, -0.1250); // Default dropoff

  // Navigation
  NavigationState? _navigationState;
  List<MapPolyline> _polylines = [];
  String _dropoffAddress = 'Destination';
  double _bearing = 0.0;
  double _tilt = 45.0; // Navigation tilt

  // Location-health watchdog (so a dead feed doesn't look like a hard freeze)
  bool _locationStale = false;
  DateTime? _lastLocationUpdateTime;
  Timer? _staleTimer;

  // ── Trip progress: stops + wait state ──────────────────────────────────
  List<RideStop> _stops = [];
  int _currentStopIndex = 0;
  String? _atStopAddress;
  DateTime? _waitStartedAt;
  Duration _elapsedWait = Duration.zero;
  Timer? _waitTickTimer;
  int _totalWaitMinutes = 0;
  double _totalWaitFee = 0.0;

  // Per-ride wait policy from backend payloads (`freeMinutes` /
  // `perMinuteRate` on stop-update / resume / ride-detail snapshots).
  // Null → [WaitFeePolicy] defaults. Harvested wherever stops/totals are.
  int? _freeWaitMinutes;
  double? _freeWaitRate;

  // Socket freshness: last at_stop/resume/status event. Polling fallback
  // hydrates from the API when the socket goes quiet.
  DateTime? _lastSocketEventAt;
  Timer? _pollTimer;

  // Status-sequence navigation guard: the completed event (socket + poll)
  // must push the receipt exactly once — never the same route twice (the
  // known payment-loop bug class).
  String? _lastNavigatedStatus;
  bool _isNavigatingToReceipt = false;

  @override
  void initState() {
    super.initState();
    _stops = List<RideStop>.from(widget.initialStops ?? const <RideStop>[]);
    _initSocketListener();
    _fetchDetailedAddress();
    _setupNavigation();

    // If no driver:locationUpdate arrives for a while, show a retry state
    // instead of leaving the passenger silently stuck on one screen.
    _staleTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final stale = _lastLocationUpdateTime == null ||
          DateTime.now().difference(_lastLocationUpdateTime!).inSeconds > 20;
      if (stale != _locationStale) setState(() => _locationStale = stale);
    });

    // Polling fallback every 15s when the socket is stale — the UI never
    // freezes on missed at_stop/resume events.
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      final last = _lastSocketEventAt;
      final stale = last == null ||
          DateTime.now().difference(last).inSeconds > 15;
      if (stale) _pollTripState();
    });
  }


  Future<void> _initSocketListener() async {
    await _socketService.initSocket();

    // Listen for driver location updates
    _socketService.on('driver:locationUpdate', (data) {
       debugPrint('📍 [RideProgressScreen] Driver location update: $data');
       if (data != null && data['latitude'] != null && data['longitude'] != null && mounted) {
          setState(() {
             _driverLocation = LatLng(
               double.parse(data['latitude'].toString()),
               double.parse(data['longitude'].toString())
             );
             _lastLocationUpdateTime = DateTime.now();
             _locationStale = false;
          });
       }
    });

    // Listen for ride status updates
    _socketService.on('ride:statusUpdate', (data) {
       if (mounted) {
          _lastSocketEventAt = DateTime.now();
          final newStatus = data['status'];
          if (newStatus == 'at_stop') {
            // Backend may broadcast the stop wait over the generic status
            // channel instead of the stop-specific events — drive the same
            // waiting-at-stop chip, checklist, and totals. Handled outside
            // the setState below (it manages its own).
            _applyStopState(
              data is Map<String, dynamic>
                  ? data
                  : data is Map
                      ? Map<String, dynamic>.from(data)
                      : <String, dynamic>{},
            );
            return;
          }
          setState(() {
             if (newStatus == 'accepted') {
                _status = 'Driver is on the way';
                _rideStatus = 'accepted';
                _progress = 0.4;
             } else if (newStatus == 'arrived' ||
                 newStatus == 'driver_arrived') {
                _status = 'Driver has arrived';
                _rideStatus = 'arrived';
                _progress = 0.6;
             } else if (newStatus == 'in_progress') {
                _status = 'Heading to destination';
                _rideStatus = 'in_progress';
                _progress = 0.8;
              } else if (newStatus == 'completed') {
                 _status = 'You have arrived!';
                 _rideStatus = 'completed';
                 _progress = 1.0;
              }
           });
           if (newStatus == 'completed') _maybeNavigateToReceipt(data);
        }
     });

    // Stop arrival: backend sets status to at_stop with currentStopIndex +
    // stops[]. Drives the "Waiting at {address}" chip + live wait timer.
    _socketService.onStopUpdate((data) {
      if (!mounted) return;
      debugPrint('🛑 [RideProgressScreen] Stop update: $data');
      _lastSocketEventAt = DateTime.now();
      _applyStopState(
        data is Map<String, dynamic>
            ? data
            : data is Map
                ? Map<String, dynamic>.from(data)
                : <String, dynamic>{},
      );
    });

    // Trip resume: backend flips back to in_progress with accumulated
    // totalWaitMinutes/totalWaitFee.
    _socketService.onTripResumed((data) {
      if (!mounted) return;
      debugPrint('▶️ [RideProgressScreen] Trip resumed: $data');
      _lastSocketEventAt = DateTime.now();
      final map = data is Map<String, dynamic>
          ? data
          : data is Map
              ? Map<String, dynamic>.from(data)
              : <String, dynamic>{};
      final stops = parseRideStops(map['stops']);
      setState(() {
        _rideStatus = 'in_progress';
        _status = 'Heading to destination';
        _progress = 0.9;
        if (stops.isNotEmpty) _stops = stops;
        _harvestWaitPolicy(map);
        if (map['currentStopIndex'] != null) {
          _currentStopIndex = _asInt(map['currentStopIndex'], _currentStopIndex);
        }
        if (map['totalWaitMinutes'] != null) {
          _totalWaitMinutes = _asInt(map['totalWaitMinutes']);
        }
        if (map['totalWaitFee'] != null) {
          _totalWaitFee = _asDouble(map['totalWaitFee']);
        }
        _atStopAddress = null;
        _waitStartedAt = null;
        _elapsedWait = Duration.zero;
      });
      _stopWaitTicker();
    });
  }

  /// Shared at_stop applier: stop-specific socket events, the generic
  /// `ride:statusUpdate` channel, and the polling fallback all converge here
  /// so the waiting-at-stop chip, stop checklist, and live totals always
  /// reflect the same backend payload.
  void _applyStopState(Map<String, dynamic> map) {
    if (!mounted) return;
    final stops = parseRideStops(map['stops']);
    final index = _asInt(map['currentStopIndex'], _currentStopIndex);
    setState(() {
      _rideStatus = 'at_stop';
      _status = 'Waiting at stop';
      _progress = 0.85;
      if (stops.isNotEmpty) _stops = stops;
      _currentStopIndex = index;
      _atStopAddress = _stopAddressAt(index);
      _waitStartedAt = DateTime.now();
      _elapsedWait = Duration.zero;
      _harvestWaitPolicy(map);
      if (map['totalWaitMinutes'] != null) {
        _totalWaitMinutes = _asInt(map['totalWaitMinutes']);
      }
      if (map['totalWaitFee'] != null) {
        _totalWaitFee = _asDouble(map['totalWaitFee']);
      }
    });
    _startWaitTicker();
  }

  static int _asInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
  static double _asDouble(dynamic value, [double fallback = 0.0]) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  /// Backend per-ride wait policy wins; [WaitFeePolicy] defaults apply only
  /// when the payload omits them.
  void _harvestWaitPolicy(Map<String, dynamic> map) {
    final fm = map['freeMinutes'];
    if (fm != null) {
      _freeWaitMinutes = fm is num
          ? fm.toInt()
          : int.tryParse(fm.toString()) ?? WaitFeePolicy.freeMinutes;
    }
    final rate = map['perMinuteRate'];
    if (rate != null) {
      _freeWaitRate = rate is num
          ? rate.toDouble()
          : double.tryParse(rate.toString()) ?? WaitFeePolicy.perMinuteRate;
    }
  }

  String? _stopAddressAt(int index) {    if (_stops.isEmpty) return null;
    final idx = index.clamp(0, _stops.length - 1);
    final address = _stops[idx].address;
    return address.isEmpty ? null : address;
  }

  /// Polling fallback: hydrate stops/wait totals/status from the API when
  /// the socket feed is stale. Same data the socket handlers consume, so
  /// the UI converges instead of freezing.
  Future<void> _pollTripState() async {
    final rideId = widget.rideId;
    if (rideId == null || rideId.isEmpty) return;
    try {
      final response = await _apiService.getRideDetails(rideId);
      if (!mounted) return;
      if (response['success'] != true || response['data'] == null) return;
      final rawData = response['data'];
      // API nests the ride under data.ride — unwrap like home_screen does.
      final raw = rawData is Map ? (rawData['ride'] ?? rawData) : rawData;
      final map = raw is Map<String, dynamic>
          ? raw
          : raw is Map
              ? Map<String, dynamic>.from(raw)
              : <String, dynamic>{};
      final status = map['status']?.toString();
      final stops = parseRideStops(map['stops']);
      setState(() {
        if (status != null && status.isNotEmpty) {
          _rideStatus = status;
          if (status == 'at_stop') {
            _status = 'Waiting at stop';
            _progress = 0.85;
          } else if (status == 'in_progress') {
            _status = 'Heading to destination';
            _progress = 0.9;
          } else if (status == 'completed') {
            _status = 'You have arrived!';
            _progress = 1.0;
          }
        }
        if (stops.isNotEmpty) _stops = stops;
        _harvestWaitPolicy(map);
        if (map['currentStopIndex'] != null) {
          _currentStopIndex = _asInt(map['currentStopIndex'], _currentStopIndex);
        }
        if (_rideStatus == 'at_stop') {
          _atStopAddress = _stopAddressAt(_currentStopIndex);
          _waitStartedAt ??= DateTime.now();
          _startWaitTicker();
        } else if (_rideStatus == 'in_progress') {
          _atStopAddress = null;
          _stopWaitTicker();
        }
        if (map['totalWaitMinutes'] != null) {
          _totalWaitMinutes = _asInt(map['totalWaitMinutes']);
        }
        if (map['totalWaitFee'] != null) {
          _totalWaitFee = _asDouble(map['totalWaitFee']);
        }
      });
      if (status == 'completed') _maybeNavigateToReceipt(map);
    } catch (e) {
      debugPrint('⚠️ [RideProgressScreen] Poll fallback failed: $e');
    }
  }

  /// Guarded receipt navigation: fires exactly once per completed ride.
  /// Both the socket `completed` event and the polling fallback converge
  /// here; the status-sequence check drops every duplicate push.
  Future<void> _maybeNavigateToReceipt(dynamic eventData) async {
    if (!mounted) return;
    if (_lastNavigatedStatus == 'completed' || _isNavigatingToReceipt) return;
    _isNavigatingToReceipt = true;
    try {
      Map<String, dynamic> rideData = {};
      if (eventData is Map<String, dynamic>) {
        rideData = eventData;
      } else if (eventData is Map) {
        rideData = Map<String, dynamic>.from(eventData);
      }
      // Hydrate the full receipt payload when the event is status-only.
      final rideId = widget.rideId;
      if ((rideData['fare'] == null || rideData['actualFare'] == null) &&
          rideId != null &&
          rideId.isNotEmpty) {
        try {
          final response = await _apiService.getRideDetails(rideId);
          if (response['success'] == true && response['data'] != null) {
            final rawData = response['data'];
            final raw = rawData is Map ? (rawData['ride'] ?? rawData) : rawData;
            rideData = raw is Map<String, dynamic>
                ? raw
                : raw is Map
                    ? Map<String, dynamic>.from(raw)
                    : rideData;
          }
        } catch (e) {
          debugPrint('⚠️ [RideProgressScreen] Receipt hydrate failed: $e');
        }
      }
      if (!mounted) return;
      _lastNavigatedStatus = 'completed';
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RideCompleteScreen(rideData: rideData),
        ),
      );
    } finally {
      _isNavigatingToReceipt = false;
    }
  }

  void _startWaitTicker() {    _waitTickTimer?.cancel();
    _waitStartedAt ??= DateTime.now();
    _waitTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _waitStartedAt == null) return;
      setState(() {
        _elapsedWait = DateTime.now().difference(_waitStartedAt!);
      });
    });
  }

  void _stopWaitTicker() {
    _waitTickTimer?.cancel();
    _waitTickTimer = null;
  }

  String _formatWait(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Fetch detailed address for dropoff location
  Future<void> _fetchDetailedAddress() async {
    final address = await _placesService.getAddressFromLatLng(
      _dropoffLocation.latitude,
      _dropoffLocation.longitude,
    );
    if (mounted) {
      setState(() {
        _dropoffAddress = address ?? 'Destination';
      });
    }
  }

  /// Setup navigation
  Future<void> _setupNavigation() async {
    // Listen to navigation updates
    _navigationService.routeUpdates.listen((state) {
      if (mounted) {
        setState(() {
          _navigationState = state;
          _bearing = state.bearing;
          _updatePolylines();
        });
      }
    });

    // Fetch initial route
    await _fetchNavigationRoute();
  }

  /// Fetch navigation route from current location to dropoff
  Future<void> _fetchNavigationRoute() async {
    await _navigationService.fetchRoute(
      originLat: _driverLocation.latitude,
      originLng: _driverLocation.longitude,
      destLat: _dropoffLocation.latitude,
      destLng: _dropoffLocation.longitude,
    );
  }

  /// Update navigation route in real-time
  Future<void> _updateNavigationRoute() async {
    await _navigationService.updateRoute(
      currentLat: _driverLocation.latitude,
      currentLng: _driverLocation.longitude,
      destLat: _dropoffLocation.latitude,
      destLng: _dropoffLocation.longitude,
    );
  }

  /// Update polylines with navigation route
  void _updatePolylines() {
    if (_navigationState != null && _navigationState!.polyline.isNotEmpty) {
      _polylines = [
        MapPolyline(
          id: 'navigation_route',
          points: _navigationState!.polyline,
          color: AppTheme.primaryColor,
          width: 5.0,
        ),
      ];
    }
  }

  @override
  void dispose() {
    _staleTimer?.cancel();
    _pollTimer?.cancel();
    _waitTickTimer?.cancel();
    _socketService.off('driver:locationUpdate');
    _socketService.off('ride:statusUpdate');
    _socketService.offStopUpdate();
    _socketService.offTripResumed();
    _navigationService.dispose();
    super.dispose();
  }

  /// Reconnect socket + clear stale state if the driver feed went quiet.
  Future<void> _retryTracking() async {
    await _socketService.initSocket(forceReconnect: true);
    setState(() {
      _locationStale = false;
      _lastLocationUpdateTime = DateTime.now();
    });
  }

  /// Cancel is blocked once the trip is underway — friendly copy instead of
  /// a dead button or a backend 400.
  void _handleCancelAttempt() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cannot cancel after start'),
        content: const Text(
          'Your trip has already started and can no longer be cancelled. '
          'Please contact your driver if you need to end the trip early.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map
          PlatformMap(
            initialLat: _driverLocation.latitude,
            initialLng: _driverLocation.longitude,
            bearing: _bearing,
            tilt: _tilt,
            markers: [
              MapMarker(
                id: 'driver',
                lat: _driverLocation.latitude,
                lng: _driverLocation.longitude,
                child: const Icon(Icons.directions_car, color: AppTheme.primaryColor, size: 40),
                title: 'Driver',
              ),
              MapMarker(
                id: 'user',
                lat: _userLocation.latitude,
                lng: _userLocation.longitude,
                child: const Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
                title: 'You',
              ),
              MapMarker(
                id: 'dropoff',
                lat: _dropoffLocation.latitude,
                lng: _dropoffLocation.longitude,
                child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                title: 'Destination',
              ),
            ],
            polylines: _polylines,
          ),

          // Back Button
          Positioned(
            top: 40,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // Stale-location notice (driver feed went quiet — offer retry)
          if (_locationStale)
            Positioned(
              top: 92,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.gps_off, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "Driver location unavailable",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _retryTracking,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      child: const Text(
                        'Retry',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Status Panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                  const SizedBox(height: 24),

                  // Status
                  Text(
                    _status,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStatusTimeline(),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Colors.grey[100],
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                  ),
                  const SizedBox(height: 16),

                  // At-stop waiting chip with live timer
                  if (_rideStatus == 'at_stop') ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.hourglass_bottom,
                            color: Colors.orange.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _atStopAddress != null
                                  ? 'Waiting at $_atStopAddress'
                                  : 'Waiting at stop',
                              style: TextStyle(
                                color: Colors.orange.shade800,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade700,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _formatWait(_elapsedWait),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Wait-fee chip with running totals
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          color: AppTheme.primaryColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_freeWaitMinutes ?? WaitFeePolicy.freeMinutes} min free · '
                            '£${(_freeWaitRate ?? WaitFeePolicy.perMinuteRate).toStringAsFixed(2)}/min after',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          _totalWaitMinutes > 0 || _totalWaitFee > 0
                              ? '⏳ $_totalWaitMinutes min · £${_totalWaitFee.toStringAsFixed(2)}'
                              : 'No wait yet',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Stops checklist
                  if (_stops.isNotEmpty) ...[
                    const Text(
                      'Stops',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._stops.asMap().entries.map((entry) {
                      final stop = entry.value;
                      final IconData icon;
                      final Color color;
                      if (stop.isCompleted) {
                        icon = Icons.check_circle;
                        color = Colors.green;
                      } else if (stop.isArrived) {
                        icon = Icons.hourglass_bottom;
                        color = Colors.orange;
                      } else {
                        icon = Icons.radio_button_unchecked;
                        color = Colors.grey;
                      }
                      final label = stop.address.isEmpty
                          ? 'Stop ${stop.stopOrder == 0 ? entry.key + 1 : stop.stopOrder}'
                          : stop.address;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(icon, color: color, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                             if (stop.waitTimeMinutes > 0)
                               Text(
                                 '⏳ ${stop.waitTimeMinutes} min · £${stop.waitFee.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                  fontFeatures: [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                  ],

                  // Route Info
                  if (_navigationState != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.navigation, color: AppTheme.primaryColor, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                _navigationState!.distanceText,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Icon(Icons.schedule, color: AppTheme.primaryColor, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                _navigationState!.etaText,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Driver Info
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: AppTheme.surfaceColor,
                        child: Icon(Icons.person, size: 28, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (widget.driver?['name']?.toString()) ?? 'Michael',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Row(
                            children: [
                              const Text(
                                'Toyota Prius • ABC 123',
                                style: TextStyle(color: AppTheme.textSecondary),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.star, size: 12, color: Colors.amber),
                                    SizedBox(width: 2),
                                    Text(
                                      '4.9',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                      Column(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.phone, color: AppTheme.primaryColor),
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: const Icon(Icons.message, color: AppTheme.primaryColor),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Actions
                  Padding(
                    padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                          onPressed: _handleCancelAttempt,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.close, color: Colors.red),
                                SizedBox(width: 8),
                                Text(
                                  'Cancel Ride',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.grey[100],
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Share Status',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.textPrimary,
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
              ),
            ),
          ),
          ),

        ],
      ),
    );
  }

  /// Status timeline: accepted → arrived → in_progress → at_stop → completed.
  /// at_stop highlights only while waiting; completed seals the trail.
  Widget _buildStatusTimeline() {
    const steps = ['accepted', 'arrived', 'in_progress', 'at_stop', 'completed'];
    const labels = ['Accepted', 'Arrived', 'Trip', 'Stop', 'Done'];
    var activeUpTo = steps.indexOf(_rideStatus);
    if (activeUpTo < 0) {
      activeUpTo = _rideStatus == 'driver_arrived' ? 1 : 2;
    }
    // While waiting at a stop the trip step stays done and stop is active.
    // Once resumed/completed, the stop step reads as passed-through.
    final stopPassed = _rideStatus == 'in_progress' || _rideStatus == 'completed';
    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final leftStep = i ~/ 2;
          final done = leftStep < activeUpTo ||
              (leftStep == 3 && stopPassed);
          return Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: done ? AppTheme.primaryColor : Colors.grey[200],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }
        final stepIndex = i ~/ 2;
        final isStop = stepIndex == 3;
        final done = stepIndex < activeUpTo || (isStop && stopPassed);
        final active = stepIndex == activeUpTo && !(isStop && stopPassed);
        final Color color;
        if (done) {
          color = AppTheme.primaryColor;
        } else if (active) {
          color = isStop ? Colors.orange : AppTheme.primaryColor;
        } else {
          color = Colors.grey[300]!;
        }
        return Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: done || active ? color : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: done
                  ? const Icon(Icons.check, color: Colors.white, size: 13)
                  : active
                      ? Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      : null,
            ),
            const SizedBox(height: 4),
            Text(
              labels[stepIndex],
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: done || active
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
              ),
            ),
          ],
        );
      }),
    );
  }
}
