import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth_provider.dart';

import 'package:latlong2/latlong.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import '../../core/api_service.dart';
import '../../core/theme.dart';
import '../../core/widgets/platform_map.dart';
import 'driver_request_panel.dart';
import 'driver_navigation_panel.dart';
import '../../core/widgets/custom_snackbar.dart';
import '../../core/models/error_display_helper.dart';
import '../../core/models/vehicle.dart';
import '../../core/services/socket_service.dart';
import '../../core/services/ride_event_dedupe.dart';
import '../../core/services/location_service.dart';
import '../../core/services/navigation_service.dart';
import '../../core/services/active_ride_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/audio_service.dart';
import '../../core/services/fcm_service.dart';
import '../../core/services/payment_service.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen>
    with WidgetsBindingObserver {
  // Status: offline, online, request, pickup, arrived, in_progress, complete
  String _status = 'offline';
  final PanelController _panelController = PanelController();

  // Location
  final LocationService _locationService = LocationService();
  LatLng _currentLocation = const LatLng(51.5085, -0.1260); // London fallback
  bool _isMapLoading = false; // Start false to show map immediately
  double _currentBearing = 0.0;
  StreamSubscription<Position>? _positionStreamSubscription;

  String? _currentRideId;
  Map<String, dynamic>? _rideData;

  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  final SocketService _socketService = SocketService();
  final NavigationService _navigationService = NavigationService();

  // Navigation State
  NavigationState? _navigationState;
  List<MapPolyline> _navigationPolylines = [];

  // Data State
  List<dynamic> _recentRides = [];
  Map<String, dynamic> _todayStats = {
    'trips': '0',
    'hours': '0.0',
    'earnings': '0.0',
  };
  bool _isHistoryLoading = false;

  // Connection status subscription for reconnection handling
  StreamSubscription<bool>? _connectionSubscription;

  // Last emitted location timestamp to throttle updates
  DateTime? _lastEmitTime;
  static const int _minEmitIntervalMs = 3000; // Minimum 3 seconds between emits

  // Location-health watchdog
  bool _locationStale = false;
  DateTime? _lastPositionUpdateTime;
  Timer? _locationWatchdog;

  // GPS health monitoring
  String? _gpsServiceProblem; // non-null when GPS is off or permission denied
  bool _noGpsSignal = false; // true when no location updates are received
  Timer? _gpsHealthTimer;
  String? _lastShownGpsWarning;

  /// Banner message describing the current location problem, or null if healthy.
  String? get _locationBannerMessage {
    if (_gpsServiceProblem != null) return _gpsServiceProblem;
    if (_noGpsSignal) {
      return 'No GPS signal received. Riders cannot see your live location — '
          'check your signal or restart location services.';
    }
    if (_locationStale) {
      return 'Location updates are delayed. Riders may see an outdated position.';
    }
    return null;
  }

  // Track if socket listeners are set up to re-register after reconnection
  bool _socketListenersSetup = false;

  // Store driverId to use in dispose without accessing context
  String? _driverId;

  // FCM notification subscriptions
  StreamSubscription<FcmNotificationData>? _fcmSubscription;
  StreamSubscription<FcmNotificationData>? _fcmForegroundSubscription;

  // Proximity guidance: set on 400 distance errors (pickup or stop), cleared
  // on success. Drives the persistent banner — never a dismiss-only toast.
  int? _proximityDistance;
  int? _proximityRequired;
  String _proximityTarget = 'pickup';

  // Free-wait policy from arrive/stop-arrive success (backend authoritative,
  // WaitFeePolicy fallback). Shown as a chip once arrived/at-stop.
  int? _freeWaitMinutes;
  double? _freeWaitRate;

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 [DriverHomeScreen] initState() initiated');
    WidgetsBinding.instance.addObserver(this);
    
    // Concurrent initialization
    _initDriver().then((_) => debugPrint('🚀 [DriverHomeScreen] _initDriver() finished'));
    _initLocation().then((_) => debugPrint('🚀 [DriverHomeScreen] _initLocation() finished'));
    _setupConnectionListener();
    _setupFcmListener();
    debugPrint('🚀 [DriverHomeScreen] initState() finished (futures pending)');
  }

  /// Listen for FCM notifications directly in the home screen
  void _setupFcmListener() {
    // Handle notification tap (user taps tray → app opens)
    _fcmSubscription = FcmService.instance.onNotificationTap.listen((data) {
      if (data.type == NotificationType.rideRequest) {
        debugPrint('🔔 [DriverHomeScreen] Received rideRequest via FCM tap');
        if (mounted &&
            RideEventDedupe.shouldHandleEvent(
              source: 'fcm-tap',
              type: data.type,
              data: data.rawData,
            )) {
          _handleNewRideRequest(data.rawData);
        }
      }
    });

    // Handle foreground FCM (app already open) — scheduled rides arrive here
    // without a socket event, so we must auto-process the push notification
    _fcmForegroundSubscription =
        FcmService.instance.onForegroundNotification.listen((data) {
      if (data.type == NotificationType.rideRequest) {
        debugPrint('🔔 [DriverHomeScreen] Received rideRequest via FCM foreground');
        if (mounted &&
            RideEventDedupe.shouldHandleEvent(
              source: 'fcm',
              type: data.type,
              data: data.rawData,
            )) {
          _handleNewRideRequest(data.rawData);
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Save driverId early to use in dispose
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    _driverId = user?['_id'] ?? user?['id'] ?? user?['userId'];
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [DriverHomeScreen] App resumed, syncing state...');

      // 0. Re-check GPS health (driver may have toggled location/permission)
      _checkGpsHealth();

      // 1. Force check socket connection
      if (!_socketService.isConnected) {
        debugPrint(
          '🔌 [DriverHomeScreen] Socket disconnected, reconnecting...',
        );
        _socketService.initSocket(forceReconnect: true);
      }

      // 2. Re-emit online status if driver is not offline
      if (_status != 'offline') {
        _emitDriverOnline();
      }

      // 3. Resume location updates if driver is online
      if (_status == 'online' && _positionStreamSubscription == null) {
        _startLocationUpdates();
      }
    } else if (state == AppLifecycleState.paused) {
      debugPrint('🔴 [DriverHomeScreen] App paused');
      // Optional: You could pause location updates here to save battery
      // But for a ride app, you probably want to keep them running
    }
  }

  /// Listen for socket reconnection and re-emit driver online status
  void _setupConnectionListener() {
    _connectionSubscription = _socketService.connectionStatus.listen((
      isConnected,
    ) {
      if (isConnected) {
        debugPrint(
          '🔄 [DriverHomeScreen] Socket reconnected, re-setting up listeners',
        );
        // Re-setup socket listeners after reconnection
        _setupSocketListeners();

        if (_status != 'offline') {
          debugPrint('🔄 [DriverHomeScreen] Re-emitting driver status');
          _emitDriverOnline();
        }

        // Auto-sync ride status if we had a disconnection gap and have an active ride
        final gap = _socketService.disconnectionGap;
        if (gap != null && gap.inSeconds > 3 && _currentRideId != null) {
          debugPrint(
            '🔄 [DriverHomeScreen] Disconnection gap: ${gap.inSeconds}s — auto-syncing ride status',
          );
          _syncRideStatus();
        }
      }
    });
  }

  /// Sync ride status with backend after reconnection gap
  Future<void> _syncRideStatus() async {
    if (_currentRideId == null) return;

    try {
      debugPrint(
        '🔄 [DriverHomeScreen] Syncing ride status for ride: $_currentRideId',
      );
      final response = await _apiService.getRideDetails(_currentRideId!);

      if (response['success'] == true && response['data'] != null) {
        final rideData = response['data'];
        final ride = rideData['ride'] ?? rideData;
        final status = ride['status']?.toString() ?? '';

        debugPrint(
          '🔄 [DriverHomeScreen] Synced ride status: $status, current UI state: $_status',
        );

        if (!mounted) return;

        // Check for terminal states — ride may have ended while disconnected
        if (status == 'cancelled' ||
            status == 'cancelled_by_user' ||
            status == 'cancelled_by_driver' ||
            status == 'expired') {
          setState(() {
            _status = 'online';
            _currentRideId = null;
            _rideData = null;
          });
          debugPrint(
            '⚠️ [DriverHomeScreen] Ride ended while disconnected ($status), returning to online',
          );
        } else if (status == 'completed') {
          setState(() {
            _status = 'online';
            _currentRideId = null;
            _rideData = null;
          });
          debugPrint(
            '✅ [DriverHomeScreen] Ride completed while disconnected, returning to online',
          );
        }
        // For active states (accepted, in_progress, etc.), the UI should already
        // reflect the correct state. Just update ride data to sync any changes.
        else if (ride != null) {
          setState(() {
            _rideData = ride is Map<String, dynamic> ? ride : null;
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ [DriverHomeScreen] Error syncing ride status: $e');
    }
  }

  Future<void> _initLocation() async {
    debugPrint('📍 [DriverHomeScreen] _initLocation() starting...');
    _fetchRideHistory(); // Background process

    // 1. Try to get last known location immediately for instant map update
    try {
      final lastKnown = await _locationService.getLastKnownLocation();
      if (lastKnown != null && mounted) {
        debugPrint("📍 [DriverHomeScreen] Instant last-known location: ${lastKnown.latitude}, ${lastKnown.longitude}");
        setState(() {
          _currentLocation = LatLng(lastKnown.latitude, lastKnown.longitude);
        });
      }
    } catch (e) {
      debugPrint('📍 [DriverHomeScreen] Error fetching last known location: $e');
    }

    // 2. Continue with getting fresh current location in background
    debugPrint("📍 [DriverHomeScreen] Requesting fresh location fix...");
    try {
      final position = await _locationService.getCurrentLocation();
      
      if (position != null && mounted) {
        debugPrint("📍 [DriverHomeScreen] Fresh location received: ${position.latitude}, ${position.longitude}");
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
        
        // Start updates if already online or needed
        if (_status == 'online') {
          _emitLocationUpdate(position.latitude, position.longitude);
        }
      } else {
        debugPrint('📍 [DriverHomeScreen] Fresh location was null or widget not mounted');
      }
    } catch (e) {
      debugPrint('📍 [DriverHomeScreen] Exception while getting fresh location: $e');
    }
    debugPrint('📍 [DriverHomeScreen] _initLocation() finished');
  }

  Future<void> _initDriver() async {
    debugPrint('🚖 [DriverHomeScreen] _initDriver() starting...');
    await _ensureUserLoaded();
    debugPrint('🚖 [DriverHomeScreen] User ensure loaded check complete');
    
    if (mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.user;
      
      if (user != null) {
        debugPrint('🚖 [DriverHomeScreen] Driver profile found: ${user['name']}');
        // Sync online status from database
        final bool isOnline = user['isOnline'] == true || user['status'] == 'online';
        
        // Check for active ride in user object
        final currentRide = user['currentRide'];
        
        setState(() {
          if (currentRide != null) {
            // Restore active ride state
            _rideData = currentRide is Map ? Map<String, dynamic>.from(currentRide as Map) : null;
            _currentRideId = _rideData?['_id']?.toString() ?? currentRide.toString();
            
            final rideStatus = _rideData?['status']?.toString().toLowerCase();
            debugPrint('🚖 [DriverHomeScreen] Active ride detected: $_currentRideId with status: $rideStatus');
            
            if (rideStatus == 'accepted') {
              _status = 'pickup';
            } else if (rideStatus == 'arrived' ||
                rideStatus == 'driver_arrived') {
              _status = 'arrived';
            } else if (rideStatus == 'in_progress') {
              _status = 'in_progress';
            } else if (rideStatus == 'at_stop') {
              _status = 'at_stop';
            } else {
              _status = 'online';
            }
          } else if (isOnline) {
            _status = 'online';
            debugPrint('🟢 [DriverHomeScreen] Driver is online in profile');
          } else {
            debugPrint('⚪ [DriverHomeScreen] Driver is offline in profile');
          }
        });

        // Trigger sync if we found an active ride
        if (_currentRideId != null) {
          debugPrint('🚖 [DriverHomeScreen] Syncing active ride data from backend...');
          _syncRideStatus();
          _fetchNavigationRoute();
        }
      } else {
        debugPrint('⚠️ [DriverHomeScreen] User is still null after _ensureUserLoaded()');
      }
      
      debugPrint('🚖 [DriverHomeScreen] Initializing Socket and listeners...');
      await _initSocketAndListeners();

      // Restore an active ride from local storage (accept -> kill app -> reopen).
      await _restoreActiveRideFromStorage();

      // H1 FIX: If an active ride was restored (e.g. a prebook ride that started
      // while the app was backgrounded/terminated), the normal 'online' entry
      // point never ran, so location streaming was never started. Without it the
      // driver map stays static and the passenger never receives
      // driver:locationUpdate (passenger appears "stuck on one screen").
      if (_currentRideId != null &&
          (_status == 'pickup' ||
              _status == 'arrived' ||
              _status == 'driver_arrived' ||
              _status == 'at_stop' ||
              _status == 'in_progress')) {
        debugPrint(
          '📍 [DriverHomeScreen] Restored active ride — starting location updates',
        );
        _startLocationUpdates();
      }
    }
    debugPrint('🚖 [DriverHomeScreen] _initDriver() finished');
  }

  Future<void> _ensureUserLoaded() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user == null) {
      debugPrint('⚠️ [DriverHomeScreen] User is null, fetching profile...');
      await authProvider.fetchDriverProfile();
    }
  }

  Future<void> _initSocketAndListeners() async {
    await _socketService.initSocket();
    if (mounted) {
      _setupSocketListeners();
      _setupNavigationListener();
      // If already online, emit goOnline
      if (_status == 'online') {
        _emitDriverOnline();
        _startLocationUpdates();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Clean up socket listeners
    _socketService.off('ride:newRequest');
    _socketService.off('ride:reminder');
    _socketService.off('ride:longRunning');
    _socketService.off('ride:expired');
    _socketService.off('ride:cancelled');
    _socketService.off('ride:cancelledByUser');
    _socketService.off('driver:status');
    _socketService.off('driver:locationUpdated');
    _socketService.off('payment:succeeded');
    _socketService.off('payment:authorized');
    _socketService.off('payment:captured');
    _socketService.off('payment:failed');
    _socketService.off('payment:cancelled');
    _socketService.off('ride:paymentSelected'); // Listener for payment choice

    // Stop and clean up notification playback if still playing
    AudioService.instance.stop();

    // Clean up streams
    _positionStreamSubscription?.cancel();
    _locationWatchdog?.cancel();
    _gpsHealthTimer?.cancel();
    _connectionSubscription?.cancel();
    _fcmSubscription?.cancel();
    _fcmForegroundSubscription?.cancel();

    // Clean up services
    _navigationService.dispose();
    _locationService.dispose();

    // Emit driver offline when disposing (if was online)
    if (_status != 'offline' && _driverId != null) {
      _socketService.emitDriverOffline(_driverId!);
    }

    debugPrint('🔴 [DriverHomeScreen] Disposed');
    super.dispose();
  }

  void _emitDriverOnline() {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    debugPrint(
      '🔍 [DriverHomeScreen] User Object: $user',
    ); // Debug print to inspect user structure

    if (user != null) {
      // Try to find ID in common fields
      final driverId = user['_id'] ?? user['id'] ?? user['userId'];

      if (driverId != null) {
        debugPrint(
          '📤 [DriverHomeScreen] Emitting driver:goOnline for $driverId',
        );
        _socketService.emitDriverOnline(driverId);
      } else {
        debugPrint(
          '⚠️ [DriverHomeScreen] Cannot emit driver:goOnline: Driver ID not found in user object',
        );
      }
    } else {
      debugPrint(
        '⚠️ [DriverHomeScreen] Cannot emit driver:goOnline: User object is null',
      );
    }
  }

  void _updateGpsWarningState() {
    final msg = _locationBannerMessage;
    if (msg != _lastShownGpsWarning) {
      _lastShownGpsWarning = msg;
      if (msg != null && mounted) {
        CustomSnackbar.show(
          context,
          message: msg,
          type: SnackbarType.warning,
        );
      }
    }
  }

  /// Detect GPS-off / permission-denied and surface it to the driver.
  Future<void> _checkGpsHealth() async {
    String? problem;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        problem = 'GPS / location services are OFF. Riders cannot see you — '
            'turn on location services.';
      } else {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          problem = 'Location permission denied. Riders cannot see you — '
              'enable it in app settings.';
        }
      }
    } catch (e) {
      debugPrint('⚠️ [DriverHomeScreen] GPS health check failed: $e');
    }
    if (mounted) {
      setState(() => _gpsServiceProblem = problem);
      _updateGpsWarningState();
    }
  }

  void _onLocationStreamError(dynamic error) {
    debugPrint('⚠️ [DriverHomeScreen] Location stream error: $error');
    _checkGpsHealth();
    if (mounted) {
      setState(() => _noGpsSignal = true);
      _updateGpsWarningState();
    }
  }

  void _startLocationUpdates() async {
    _positionStreamSubscription?.cancel();

    // Get initial location
    final position = await _locationService.getCurrentLocation();
    if (position != null && mounted) {
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
      _emitLocationUpdate(position.latitude, position.longitude);
    } else {
      // No fix at all — likely GPS off / permission denied / no signal.
      setState(() => _noGpsSignal = true);
      _updateGpsWarningState();
    }

    // Use ride tracking stream for active rides (more frequent updates)
    // or periodic stream for online status
    final bool isActiveRide = _status == 'in_progress' ||
        _status == 'pickup' ||
        _status == 'arrived' ||
        _status == 'driver_arrived' ||
        _status == 'at_stop';

    if (isActiveRide) {
      // Use high-frequency tracking for active rides (every 3 seconds, 5m distance filter)
      _positionStreamSubscription = _locationService
          .getRideTrackingStream(intervalSeconds: 3)
          .listen(_handlePositionUpdate, onError: _onLocationStreamError);

      debugPrint(
        '📍 [DriverHomeScreen] Started ride tracking stream (3s interval)',
      );
    } else {
      // Use periodic updates when just online (every 4 seconds)
      _positionStreamSubscription = _locationService
          .getPeriodicPositionStream(intervalSeconds: 4)
          .listen(_handlePositionUpdate, onError: _onLocationStreamError);

      debugPrint(
        '📍 [DriverHomeScreen] Started periodic location stream (4s interval)',
      );
    }

    // Probe GPS health now (permission/service) and re-check periodically so the
    // warning clears automatically once the driver fixes it.
    _checkGpsHealth();
    _gpsHealthTimer?.cancel();
    _gpsHealthTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _checkGpsHealth();
    });

    // Watchdog: surface "location lost" to the driver instead of failing silently.
    _locationWatchdog?.cancel();
    _locationWatchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final needsLoc = _status == 'online' ||
          _status == 'pickup' ||
          _status == 'arrived' ||
          _status == 'in_progress';
      if (!needsLoc) {
        if (_locationStale) setState(() => _locationStale = false);
        if (_noGpsSignal) {
          setState(() => _noGpsSignal = false);
          _updateGpsWarningState();
        }
        return;
      }
      final diff = _lastPositionUpdateTime == null
          ? 999999
          : DateTime.now().difference(_lastPositionUpdateTime!).inSeconds;
      final stale = diff > 15;
      if (stale != _locationStale) setState(() => _locationStale = stale);
      final noSignal = diff > 20;
      if (noSignal != _noGpsSignal) {
        setState(() => _noGpsSignal = noSignal);
        _updateGpsWarningState();
      }
    });
  }

  /// Handle incoming position updates
  void _handlePositionUpdate(Position position) {
    if (!mounted) return;

    // Calculate bearing if we have a previous location
    if (_currentLocation.latitude != 0 && _currentLocation.longitude != 0) {
      final bearing = Geolocator.bearingBetween(
        _currentLocation.latitude,
        _currentLocation.longitude,
        position.latitude,
        position.longitude,
      );
      // Only update bearing if moving significant distance or speed > 0
      if (position.speed > 0.5) {
        // moving at least 0.5 m/s
        _currentBearing = bearing;
      }
    }

    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
    });

    _lastPositionUpdateTime = DateTime.now();
    if (_locationStale) setState(() => _locationStale = false);
    if (_noGpsSignal) {
      setState(() => _noGpsSignal = false);
      _updateGpsWarningState();
    }

    // Throttle location emissions to prevent overwhelming the server
    final now = DateTime.now();
    final shouldEmit =
        _lastEmitTime == null ||
        now.difference(_lastEmitTime!).inMilliseconds >= _minEmitIntervalMs;

    if (shouldEmit &&
        (_status == 'online' ||
            _status == 'in_progress' ||
            _status == 'pickup' ||
            _status == 'arrived')) {
      _emitLocationUpdate(position.latitude, position.longitude);
      _lastEmitTime = now;

      // Update navigation route in real-time
      if (_status == 'pickup' ||
          _status == 'in_progress' ||
          _status == 'arrived') {
        _updateNavigationRoute();
      }
    }
  }

  /// Setup navigation listener for route updates
  void _setupNavigationListener() {
    _navigationService.routeUpdates.listen((state) {
      if (!mounted) return;

      final bool isNavigationMode = _status == 'pickup' ||
          _status == 'arrived' ||
          _status == 'driver_arrived' ||
          _status == 'at_stop' ||
          _status == 'in_progress';

      // If the ride has ended (or driver is not navigating), ignore late route updates
      // and ensure the map is cleared.
      if (!isNavigationMode) {
        if (_navigationState != null || _navigationPolylines.isNotEmpty) {
          setState(() {
            _clearNavigationUi();
          });
        }
        return;
      }

      setState(() {
        _navigationState = state;
        _updateNavigationPolylines();
      });
    });
  }

  void _clearNavigationUi() {
    _navigationService.clearRoute();
    _navigationState = null;
    _navigationPolylines = [];
  }

  /// Persist the current active ride so it can be restored after an app restart.
  Future<void> _persistActiveRide() async {
    if (_currentRideId == null) return;
    await ActiveRideStorage.save(
      rideId: _currentRideId!,
      role: 'driver',
      status: _status,
    );
  }

  Future<void> _clearActiveRideStorage() async {
    await ActiveRideStorage.clear();
  }

  /// Restore an active ride from local storage (covers the case where the backend
  /// profile didn't carry currentRide, e.g. accept -> kill app -> reopen).
  Future<void> _restoreActiveRideFromStorage() async {
    if (_currentRideId != null) return; // already restored from profile
    final id = await ActiveRideStorage.getRideId();
    final role = await ActiveRideStorage.getRole();
    if (id == null || role != 'driver') return;

    try {
      final response = await _apiService.getRideDetails(id);
      if (response['success'] != true) {
        await ActiveRideStorage.clear();
        return;
      }
      final raw = response['data'];
      final ride = raw is Map ? (raw['ride'] ?? raw) : null;
      if (ride == null) {
        await ActiveRideStorage.clear();
        return;
      }
      final status = (ride['status'] ?? '').toString().toLowerCase();
      if (const [
        'completed',
        'early_completed',
        'cancelled',
        'cancelled_by_user',
        'cancelled_by_driver',
        'expired',
      ].contains(status)) {
        await ActiveRideStorage.clear();
        return;
      }

      String uiStatus;
      switch (status) {
        case 'accepted':
          uiStatus = 'pickup';
          break;
        case 'arrived':
        case 'driver_arrived':
          uiStatus = 'arrived';
          break;
        case 'in_progress':
          uiStatus = 'in_progress';
          break;
        case 'at_stop':
          uiStatus = 'at_stop';
          break;
        default:
          uiStatus = 'pickup';
      }

      if (!mounted) return;
      setState(() {
        _currentRideId = id;
        _rideData = Map<String, dynamic>.from(ride as Map);
        _status = uiStatus;
      });
      await ActiveRideStorage.updateStatus(status);
      _fetchNavigationRoute();
    } catch (e) {
      debugPrint('⚠️ [DriverHomeScreen] Restore active ride failed: $e');
      await ActiveRideStorage.clear();
    }
  }

  /// Fetch navigation route based on current status
  Future<void> _fetchNavigationRoute() async {
    if (_rideData == null) return;

    LatLng destination;

    if (_status == 'pickup' || _status == 'arrived') {
      // Navigate to pickup
      final coords = _rideData!['pickupLocation']?['coordinates'] ?? [0.0, 0.0];
      destination = LatLng(coords[1], coords[0]);
    } else if (_status == 'in_progress' || _status == 'at_stop') {
      // Navigate to dropoff
      final coords =
          _rideData!['dropoffLocation']?['coordinates'] ?? [0.0, 0.0];
      destination = LatLng(coords[1], coords[0]);
    } else {
      return;
    }

    await _navigationService.fetchRoute(
      originLat: _currentLocation.latitude,
      originLng: _currentLocation.longitude,
      destLat: destination.latitude,
      destLng: destination.longitude,
    );
  }

  /// Update navigation route in real-time
  Future<void> _updateNavigationRoute() async {
    if (_rideData == null) return;

    LatLng destination;

    if (_status == 'pickup' || _status == 'arrived') {
      final coords = _rideData!['pickupLocation']?['coordinates'] ?? [0.0, 0.0];
      destination = LatLng(coords[1], coords[0]);
    } else if (_status == 'in_progress' || _status == 'at_stop') {
      final coords =
          _rideData!['dropoffLocation']?['coordinates'] ?? [0.0, 0.0];
      destination = LatLng(coords[1], coords[0]);
    } else {
      return;
    }

    await _navigationService.updateRoute(
      currentLat: _currentLocation.latitude,
      currentLng: _currentLocation.longitude,
      destLat: destination.latitude,
      destLng: destination.longitude,
    );
  }

  /// Update polylines with navigation route
  void _updateNavigationPolylines() {
    if (_navigationState != null && _navigationState!.polyline.isNotEmpty) {
      _navigationPolylines = [
        MapPolyline(
          id: 'navigation_route',
          points: _navigationState!.polyline,
          color: AppTheme.primaryColor,
          width: 5.0,
        ),
      ];
    } else {
      _navigationPolylines = [];
    }
  }

  /// Open external navigation to the current target (pickup or stop).
  Future<void> _openExternalNavigation() async {
    double? lat;
    double? lng;
    if (_proximityTarget.startsWith('stop') && _rideData != null) {
      final stops = parseRideStops(_rideData!['stops']);
      final idx = _rideData!['currentStopIndex'] is int
          ? _rideData!['currentStopIndex'] as int
          : 0;
      final current = idx >= 0 && idx < stops.length ? stops[idx] : null;
      if (current?.coordinates != null) {
        lng = current!.coordinates![0];
        lat = current.coordinates![1];
      }
    } else {
      final coords = _rideData?['pickupLocation']?['coordinates'];
      if (coords is List && coords.length >= 2) {
        lng = (coords[0] as num).toDouble();
        lat = (coords[1] as num).toDouble();
      }
    }
    if (lat == null || lng == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Persistent proximity banner — stays until arrival succeeds.
  /// Never a dismiss-only toast: always offers Retry + Open navigation.
  Widget _buildProximityBanner() {
    final distance = _proximityDistance ?? 0;
    final required = _proximityRequired ?? 100;
    final target = _proximityTarget.startsWith('stop')
        ? _proximityTarget
        : 'pickup point';
    // Stack below the GPS banner when both are visible.
    final topOffset = _locationBannerMessage != null ? 84.0 : 0.0;
    return Positioned(
      top: topOffset,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.orange[800],
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.nearby_error,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "You're ${distance}m away — within ${required}m to confirm",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  'Drive closer to the $target, then retry arrival.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _handleRideAction,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _openExternalNavigation,
                      icon: const Icon(Icons.navigation, size: 16),
                      label: const Text('Open navigation'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.orange[800],
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Free-wait chip label after arrival (backend values, policy fallback).
  String? get _freeWaitLabel {
    if (_status != 'arrived' &&
        _status != 'driver_arrived' &&
        _status != 'at_stop') {
      return null;
    }
    final mins = _freeWaitMinutes ?? WaitFeePolicy.freeMinutes;
    final rate = _freeWaitRate ?? WaitFeePolicy.perMinuteRate;
    return '$mins min free · £${rate.toStringAsFixed(2)}/min after';
  }

  /// Harvest per-ride wait policy from a backend payload (arrive /
  /// stop-arrive / ride snapshots carry `freeMinutes` + `perMinuteRate`).
  /// Falls back to [WaitFeePolicy] defaults only when the backend omits them.
  void _harvestWaitPolicy(Map<String, dynamic> data) {
    final fm = data['freeMinutes'];
    _freeWaitMinutes = fm is num
        ? fm.toInt()
        : int.tryParse(fm?.toString() ?? '') ?? WaitFeePolicy.freeMinutes;
    final rate = data['perMinuteRate'];
    _freeWaitRate = rate is num
        ? rate.toDouble()
        : double.tryParse(rate?.toString() ?? '') ??
              WaitFeePolicy.perMinuteRate;
  }

  void _emitLocationUpdate(double lat, double lng) {    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user != null) {
      final driverId = user['_id'] ?? user['id'] ?? user['userId'];

      if (driverId != null) {
        // Use the enhanced socket service method
        _socketService.emitDriverLocationUpdate(
          driverId: driverId,
          latitude: lat,
          longitude: lng,
        );
      }
    }
  }

  void _setupSocketListeners() {
    debugPrint('👂 [DriverHomeScreen] Setting up socket listeners...');

    // Clean up existing listeners before re-registering to prevent duplicates
    if (_socketListenersSetup) {
      debugPrint(
        '🧹 [DriverHomeScreen] Cleaning up old socket listeners before re-setup...',
      );
      _socketService.off('ride:newRequest');
      _socketService.off('ride:reminder');
      _socketService.off('ride:longRunning');
      _socketService.off('ride:expired');
      _socketService.off('ride:cancelled');
      _socketService.off('ride:cancelledByUser');
      _socketService.off('driver:status');
      _socketService.off('driver:locationUpdated');
      _socketService.off('payment:succeeded');
      _socketService.off('payment:authorized');
      _socketService.off('payment:captured');
      _socketService.off('payment:failed');
      _socketService.off('payment:cancelled');
      _socketService.off('ride:paymentSelected');
    }

    _socketListenersSetup = true;

    // Listen for driver status confirmation
    _socketService.on('driver:status', (data) {
      debugPrint('📩 [DriverHomeScreen] Driver status: $data');
      if (mounted && data['status'] == 'online') {
        // Successfully went online
      }
    });

    // Listen for payment selected by user
    _socketService.on('ride:paymentSelected', (data) {
      debugPrint('💳 [DriverHomeScreen] User selected payment: $data');
      if (mounted && _currentRideId == (data['bookingId'] ?? data['rideId'])) {
        setState(() {
          // Update local ride data with selected method
          if (_rideData != null) {
            _rideData!['paymentMethod'] = data['paymentMethod'];
          }
        });
        CustomSnackbar.show(
          context,
          message: 'User is paying...',
          type: SnackbarType.info,
        );
      }
    });

    // Listen for payment success to finalize ride completion
    _socketService.on('payment:succeeded', (data) {
      debugPrint('💳 [DriverHomeScreen] Payment succeeded: $data');
      if (!mounted) return;

      final rideId =
          data['bookingId']?.toString() ?? data['rideId']?.toString();
      if (rideId == _currentRideId) {
        CustomSnackbar.show(
          context,
          message: 'Payment completed! Ride finalized.',
          type: SnackbarType.success,
        );

        // Reset to online and refetch ride history
        setState(() {
          _status = 'online';
          _currentRideId = null;
          _rideData = null;
          _clearNavigationUi();
          _clearActiveRideStorage();
        });
        _fetchRideHistory();
      }
      // Stop notification playback if payment succeeded
      AudioService.instance.stop();
    });

    _socketService.on('payment:authorized', (data) {
      debugPrint('💳 [DriverHomeScreen] Payment authorized: $data');
      if (!mounted) return;

      final rideId =
          data['bookingId']?.toString() ?? data['rideId']?.toString();
      if (rideId == _currentRideId) {
        CustomSnackbar.show(
          context,
          message: 'Payment authorized by rider.',
          type: SnackbarType.info,
        );
      }
    });

    _socketService.on('payment:captured', (data) {
      debugPrint('💳 [DriverHomeScreen] Payment captured: $data');
      if (!mounted) return;

      final rideId =
          data['bookingId']?.toString() ?? data['rideId']?.toString();
      if (rideId == _currentRideId) {
        CustomSnackbar.show(
          context,
          message: 'Payment captured successfully.',
          type: SnackbarType.success,
        );
      }
    });

    _socketService.on('payment:failed', (data) {
      debugPrint('💳 [DriverHomeScreen] Payment failed: $data');
      if (!mounted) return;

      final rideId =
          data['bookingId']?.toString() ?? data['rideId']?.toString();
      if (rideId == _currentRideId) {
        CustomSnackbar.show(
          context,
          message: data['message']?.toString() ?? 'Rider payment failed.',
          type: SnackbarType.error,
        );
      }
    });

    _socketService.on('payment:cancelled', (data) {
      debugPrint('💳 [DriverHomeScreen] Payment cancelled: $data');
      if (!mounted) return;

      final rideId =
          data['bookingId']?.toString() ?? data['rideId']?.toString();
      if (rideId == _currentRideId) {
        CustomSnackbar.show(
          context,
          message: data['message']?.toString() ?? 'Rider cancelled payment.',
          type: SnackbarType.warning,
        );
      }
    });

    // Listen for location update confirmation
    _socketService.on('driver:locationUpdated', (data) {
      // Location update confirmed by server
    });

    _socketService.on('ride:newRequest', (data) {
      debugPrint('🔔 [DriverHomeScreen] New Ride Request Received: $data');
      if (mounted) {
        // FCM delivers the same request — shared guard keeps one dialog.
        if (!RideEventDedupe.shouldHandleEvent(
          source: 'socket',
          type: 'ride_request',
          data: data,
        )) {
          return;
        }
        debugPrint('🔔 [DriverHomeScreen] Triggering _handleNewRideRequest');
        _handleNewRideRequest(data);
      } else {
        debugPrint(
          '🔔 [DriverHomeScreen] Received request but widget not mounted',
        );
      }
    });

    _socketService.on('ride:scheduledCancelledByUser', (data) {
      debugPrint('❌ [DriverHomeScreen] Scheduled Ride Cancelled By User: $data');
      if (mounted) {
        final rideId = data['rideId']?.toString();
        if (_currentRideId == rideId) {
          setState(() {
            _status = 'online';
            _currentRideId = null;
            _rideData = null;
          });
        }
        CustomSnackbar.show(
          context,
          message: data['message'] ?? 'A scheduled ride was cancelled by user',
          type: SnackbarType.info,
        );
      }
    });

    _socketService.on('ride:reminder', (data) {
      debugPrint('⏰ [DriverHomeScreen] Ride Reminder: $data');
      if (mounted) {
        CustomSnackbar.show(
          context,
          message: data['message'] ?? 'Reminder: You have an upcoming ride!',
          type: SnackbarType.warning,
        );
      }
    });

    _socketService.on('ride:longRunning', (data) {
      debugPrint('⏳ [DriverHomeScreen] Ride Long Running: $data');
      if (mounted) {
        CustomSnackbar.show(
          context,
          message: 'Ride is taking longer than expected...',
          type: SnackbarType.warning,
        );
      }
    });

    _socketService.on('ride:cancelled', (data) {
      debugPrint('❌ [DriverHomeScreen] Ride Cancelled: $data');
      if (mounted) {
        final reason = data['reason'] ?? 'User cancelled the ride';
        setState(() {
          _status = 'online';
          _currentRideId = null;
          _rideData = null;
          _clearNavigationUi();
          _clearActiveRideStorage();
        });

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Ride Cancelled'),
            content: Text('The ride was cancelled.\nReason: $reason'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });

    // User cancelled the ride (before start)
    _socketService.on('ride:cancelledByUser', (data) {
      debugPrint('❌ [DriverHomeScreen] Ride Cancelled By User: $data');
      if (mounted) {
        AudioService.instance.stop();
        final cancellationFee = data['cancellationFee'] ?? 0.0;
        setState(() {
          _status = 'online';
          _currentRideId = null;
          _rideData = null;
          _clearNavigationUi();
          _clearActiveRideStorage();
        });

        final message = cancellationFee > 0
            ? 'User cancelled the ride.\nYou received £${cancellationFee.toStringAsFixed(2)} compensation.'
            : 'User cancelled the ride.';

        CustomSnackbar.show(context, message: message, type: SnackbarType.info);
      }
    });

    _socketService.on('ride:expired', (data) {
      debugPrint('⏰ [DriverHomeScreen] Ride Expired: $data');
      if (mounted) {
        AudioService.instance.stop();
        setState(() {
          _status = 'online';
          _currentRideId = null;
          _rideData = null;
          _clearNavigationUi();
          _clearActiveRideStorage();
        });
        CustomSnackbar.show(
          context,
          message: 'Ride request expired.',
          type: SnackbarType.info,
        );
      }
    });
  }

  double? _parseNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Normalise flat FCM payload into nested structure expected by ride panels.
  Map<String, dynamic> _normaliseRideData(dynamic raw) {
    if (raw is! Map<String, dynamic>) return raw is Map ? Map<String, dynamic>.from(raw) : {};

    final m = Map<String, dynamic>.from(raw);

    // Normalise booleans (FCM sends everything as strings)
    if (m['isScheduled'] is String) m['isScheduled'] = m['isScheduled'] == 'true';
    if (m['isPriority'] is String) m['isPriority'] = m['isPriority'] == 'true';

    // Normalise numeric fields that FCM sends as strings
    if (m['fare'] is String) m['fare'] = double.tryParse(m['fare']) ?? m['fare'];
    if (m['distance'] is String) m['distance'] = double.tryParse(m['distance']) ?? m['distance'];

    // Build nested pickupLocation from flat fields
    if (m['pickupLocation'] == null && (m['pickupAddress'] != null || m['pickupLat'] != null)) {
      final lat = _parseNum(m['pickupLat']);
      final lng = _parseNum(m['pickupLon']);
      m['pickupLocation'] = {
        'address': m['pickupAddress'],
        if (lat != null && lng != null)
          'coordinates': [lng, lat],
      };
    }

    // Build nested dropoffLocation from flat fields
    if (m['dropoffLocation'] == null && (m['dropoffAddress'] != null || m['dropoffLat'] != null)) {
      final lat = _parseNum(m['dropoffLat']);
      final lng = _parseNum(m['dropoffLon']);
      m['dropoffLocation'] = {
        'address': m['dropoffAddress'],
        if (lat != null && lng != null)
          'coordinates': [lng, lat],
      };
    }

    // Build nested user from flat userName
    if (m['user'] == null && m['userName'] != null) {
      m['user'] = {'name': m['userName']};
    }

    return m;
  }

  void _handleNewRideRequest(dynamic data) {
    debugPrint(
      '🔔 [DriverHomeScreen] Handling request. Current status: $_status',
    );
    // Only show request if driver is online and available
    if (_status == 'online') {
      debugPrint('🔔 [DriverHomeScreen] Starting ringtone sound...');
      // Use playRingtone for better visibility as it's meant for alerts
      // Play app custom notification sound
      AudioService.instance.playNotification();

      final normalised = _normaliseRideData(data);

      setState(() {
        _status = 'request';
        _currentRideId = normalised['rideId'] ?? normalised['_id'];
        _rideData = normalised;
      });

      // Show notification
      final isScheduled = normalised['isScheduled'] == true;
      final isFallback = normalised['isFallback']?.toString().toLowerCase() == 'true';

      String message = isScheduled ? 'Scheduled Ride Request!' : 'New Ride Request!';
      if (isFallback) {
        message = 'Open Ride Request (5-Seater)!';
      }

      CustomSnackbar.show(
        context,
        message: message,
        type: SnackbarType.success,
      );
    } else {
      debugPrint(
        '⚠️ [DriverHomeScreen] Received request but status is $_status',
      );
    }
  }

  Future<void> _toggleOnline() async {
    if (_isLoading) return;

    final bool isGoingOnline = _status == 'offline';

    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint(
        '🔵 [DriverHomeScreen] Toggling status. Current: $_status, Target: ${isGoingOnline ? 'online' : 'offline'}',
      );

      final response = await _apiService.updateDriverStatus(isGoingOnline);

      if (response['success'] == true) {
        setState(() {
          _status = isGoingOnline ? 'online' : 'offline';

          // If going offline, ensure any previous ride route is cleared from the map.
          if (!isGoingOnline) {
            _currentRideId = null;
            _rideData = null;
            _clearNavigationUi();
            AudioService.instance.stop();
          }
        });

        if (mounted) {
          CustomSnackbar.show(
            context,
            message:
                response['message'] ??
                (isGoingOnline ? 'You are now Online' : 'You are now Offline'),
            type: SnackbarType.success,
          );

          if (isGoingOnline) {
            _emitDriverOnline();
            _startLocationUpdates();
          } else {
            _positionStreamSubscription?.cancel();
            // Optional: emit driver:goOffline
          }
        }
        debugPrint(
          '🟢 [DriverHomeScreen] Status updated successfully to $_status',
        );
      } else {
        // Handle error responses, including 403 validation errors
        // Check for error code in both locations: root level or nested in 'errors' object
        final errors = response['errors'] as Map<String, dynamic>?;
        final errorCode =
            errors?['code']?.toString() ?? response['code']?.toString() ?? '';
        final errorMessage =
            response['message']?.toString() ?? 'Failed to update status';

        debugPrint('🔴 [DriverHomeScreen] Failed to update status');
        debugPrint('🔴 [DriverHomeScreen] Error Code: $errorCode');
        debugPrint('🔴 [DriverHomeScreen] Error Message: $errorMessage');

        if (mounted) {
          // Check for specific error codes
          if (errorCode == 'PROFILE_INCOMPLETE') {
            _showProfileIncompleteDialog(errorMessage);
          } else if (errorCode == 'NOT_APPROVED') {
            _showNotApprovedDialog(errorMessage);
          } else {
            CustomSnackbar.show(
              context,
              message: errorMessage,
              type: SnackbarType.error,
            );
          }
        }
      }
    } catch (e) {
      // This should rarely happen now since API service returns errors instead of throwing
      debugPrint('🔴 [DriverHomeScreen] Unexpected error updating status: $e');

      if (mounted) {
        CustomSnackbar.show(
          context,
          message: 'Unexpected error: ${e.toString()}',
          type: SnackbarType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        if (_status == 'online') {
          _fetchRideHistory();
        }
      }
    }
  }

  void _showProfileIncompleteDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Profile Incomplete'),
          ],
        ),
        content: Text(
          message.isEmpty
              ? 'Please complete your profile by uploading all required documents before going online.'
              : message,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to document checklist screen
              Navigator.pushNamed(context, '/driver/documents');
            },
            child: const Text('Complete Profile'),
          ),
        ],
      ),
    );
  }

  void _showNotApprovedDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.pending, color: Colors.blue),
            SizedBox(width: 8),
            Text('Pending Approval'),
          ],
        ),
        content: Text(
          message.isEmpty
              ? 'Your account is pending admin approval. Please wait for verification to complete before going online.'
              : message,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to document checklist screen to view status
              Navigator.pushNamed(context, '/driver/documents');
            },
            child: const Text('View Status'),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchRideHistory() async {
    if (!mounted) return;
    setState(() => _isHistoryLoading = true);

    try {
      final response = await _apiService.getDriverRides();
      if (response['success'] == true) {
        final rides = response['data'] as List<dynamic>;

        // Process today's stats
        final now = DateTime.now();
        final todayRides = rides.where((ride) {
          if (ride['createdAt'] == null) return false;
          final createdAt = DateTime.parse(ride['createdAt']);
          return createdAt.year == now.year &&
              createdAt.month == now.month &&
              createdAt.day == now.day;
        }).toList();

        double totalHours = 0;
        double totalEarnings = 0;
        for (var ride in todayRides) {
          final status = ride['status']?.toString().toLowerCase();
          if (status == 'completed' || status == 'early_completed') {
            // Get duration in minutes
            double durationMin = (ride['duration'] as num?)?.toDouble() ?? 0;

            // If duration is 0/null, calculate from timestamps
            if (durationMin == 0 && ride['acceptedAt'] != null) {
              try {
                final start = DateTime.parse(ride['acceptedAt']);
                final endInput =
                    ride['completedAt'] ??
                    ride['updatedAt'] ??
                    ride['createdAt'];
                if (endInput != null) {
                  final end = DateTime.parse(endInput);
                  durationMin = end.difference(start).inMinutes.toDouble();
                }
              } catch (e) {
                debugPrint('⚠️ [DriverStats] Error calculating duration: $e');
              }
            }

            totalHours += durationMin / 60.0;
            totalEarnings += (ride['fare'] as num?)?.toDouble() ?? 0.0;
          }
        }

        if (mounted) {
          setState(() {
            _recentRides = rides.take(5).toList();
            _todayStats = {
              'trips': todayRides.length.toString(),
              'hours': totalHours.toStringAsFixed(1),
              'earnings': totalEarnings.toStringAsFixed(2),
            };
          });
        }
      }
    } catch (e) {
      debugPrint('🔴 [DriverHomeScreen] Error fetching history: $e');
    } finally {
      if (mounted) setState(() => _isHistoryLoading = false);
    }
  }

  Future<void> _handleRideAction() async {
    if (_currentRideId == null) {
      CustomSnackbar.show(
        context,
        message: 'Error: No active ride',
        type: SnackbarType.error,
      );
      return;
    }
    // In-flight guard: both arrive and start buttons route here.
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      if (_status == 'request') {
        // Accept Ride
        debugPrint('🚖 [DriverHomeScreen] Accepting ride: $_currentRideId');

        // Ensure the socket is connected so the ride:accept event reaches
        // the backend reliably. On iOS the socket drops more often, so we
        // force a reconnect instead of silently skipping the emit.
        if (!_socketService.isConnected) {
          debugPrint(
            '🔌 [DriverHomeScreen] Socket not connected, forcing reconnect before accept',
          );
          await _socketService.initSocket(forceReconnect: true);
        }

        // Always emit ride:accept via socket (emitReliable queues if still
        // reconnecting). The backend uses this event to broadcast to the
        // passenger — the REST call alone may not trigger the push.
        debugPrint('🔌 [DriverHomeScreen] Emitting ride:accept via socket');
        _socketService.emitRideAccept(_currentRideId!);

        // Always call REST API as a reliable fallback/method if socket is shaky or as primary
        final response = await _apiService.acceptRide(_currentRideId!);
        if (response['success'] == true) {
          AudioService.instance.stop();
          setState(() {
            _status = 'pickup';
            if (response['data'] != null) {
              final newData = response['data'] as Map<String, dynamic>;
              _rideData = {...?_rideData, ...newData};
              _currentRideId = newData['_id']?.toString() ?? _currentRideId;
            }
          });
          _persistActiveRide();
          CustomSnackbar.show(
            context,
            message: 'Ride Accepted!',
            type: SnackbarType.success,
          );
          // Fetch navigation route to pickup
          _fetchNavigationRoute();
        } else {
          CustomSnackbar.show(
            context,
            message: 'Failed to accept: ${response['message']}',
            type: SnackbarType.error,
          );
        }
      } else if (_status == 'pickup') {
        // Arrive at Pickup
        // Get current location
        final pos = _currentLocation;

        final response = await _apiService.arriveAtPickup(
          _currentRideId!,
          pos.latitude,
          pos.longitude,
        );

        if (response['success'] == true) {
          final data = response['data'] is Map<String, dynamic>
              ? response['data'] as Map<String, dynamic>
              : <String, dynamic>{};
          setState(() {
            _status = 'arrived';
            // Proximity resolved — drop the banner.
            _proximityDistance = null;
            _proximityRequired = null;
            // Backend-authoritative wait policy; WaitFeePolicy fallback.
            _harvestWaitPolicy(data);
            if (response['data'] != null) {
              final newData = response['data'] as Map<String, dynamic>;
              _rideData = {...?_rideData, ...newData};
            }
          });
          _persistActiveRide();
          CustomSnackbar.show(
            context,
            message: 'You have arrived!',
            type: SnackbarType.success,
          );
        } else {
          final errors = response['errors'];
          final distance = errors is Map ? errors['distance'] : null;
          if (distance != null) {
            // Proximity error: persistent banner + mapper copy (never a
            // dismiss-only toast — banner stays until arrival succeeds).
            final distInt = distance is num
                ? distance.toInt()
                : int.tryParse(distance.toString()) ?? 0;
            final reqRaw = errors is Map ? errors['required'] : null;
            final reqInt = reqRaw is num
                ? reqRaw.toInt()
                : int.tryParse(reqRaw?.toString() ?? '') ?? 100;
            setState(() {
              _proximityDistance = distInt;
              _proximityRequired = reqInt;
              _proximityTarget = 'pickup';
            });
          }
          if (!mounted) return;
          ErrorDisplayHelper.showRideError(
            context,
            response['message']?.toString() ?? 'Failed to arrive',
            errors: response['errors'],
            onAction: _handleRideAction,
          );
        }
      } else if (_status == 'arrived' || _status == 'driver_arrived') {
        // One-tap start — no code entry on the driver side.
        await _startRideNoOtp();
      } else if (_status == 'at_stop') {
        // Main action mirrors the per-stop card: resume the trip.
        await _handleStopResume();
      } else if (_status == 'in_progress') {
        // Complete Ride — GPS is mandatory, never a silent fail.
        if (!_gpsOkForCompletion()) {
          _showGpsBlockedDialog();
          return;
        }
        final pos = _currentLocation;
        final response = await _apiService.completeRide(
          _currentRideId!,
          pos.latitude,
          pos.longitude,
        );
        if (response['success'] == true) {
          final paymentMethod = _rideData?['paymentMethod'];
          final rideResult = response['data'] as Map<String, dynamic>? ?? {};
          final summary = FareSummary.fromJson({
            ...?_rideData,
            ...rideResult,
          });
          setState(() {
            _rideData = {...?_rideData, ...rideResult};
          });
          final bool isPromoFreeRide =
              rideResult['isPromoRide'] == true &&
              (rideResult['fare'] is num
                      ? (rideResult['fare'] as num).toDouble()
                      : 0.0) ==
                  0.0;

          if (paymentMethod == 'cash' && isPromoFreeRide) {
            // Fully discounted promo ride — no cash to collect, auto-finalize
            final confirmResponse = await _apiService.confirmCashCollection(
              _currentRideId!,
            );
            if (confirmResponse['success'] == true) {
              setState(() {
                _status = 'online';
                _currentRideId = null;
                _rideData = null;
                _clearNavigationUi();
              });
              _fetchRideHistory();
              if (!mounted) return;
              _showFareSummary(
                summary: summary,
                headline: 'Promotional ride complete',
                subline: 'No cash to collect.',
              );
            } else {
              if (!mounted) return;
              ErrorDisplayHelper.showRideError(
                context,
                confirmResponse['message']?.toString() ?? 'Failed to finalize',
                errors: confirmResponse['errors'],
              );
            }
          } else if (paymentMethod == 'cash') {
          setState(() {
            _status = 'awaiting_cash_confirmation';
          });
          _persistActiveRide();
          if (!mounted) return;
          _showFareSummary(
            summary: summary,
            headline: 'Ride completed',
            subline: 'Collect cash from the passenger.',
          );
          } else {
            setState(() {
              _status = 'online';
              _currentRideId = null;
              _rideData = null;
              _clearNavigationUi();
            });
            _fetchRideHistory();
            if (!mounted) return;
            _showFareSummary(
              summary: summary,
              headline: 'Ride completed successfully',
              subline: null,
            );
          }
        } else {
          if (!mounted) return;
          ErrorDisplayHelper.showRideError(
            context,
            response['message']?.toString() ?? 'Failed to complete',
            errors: response['errors'],
            onAction: _handleRideAction,
          );
        }
      } else if (_status == 'awaiting_cash_confirmation') {
        // Confirm Cash Collection
        final response = await _apiService.confirmCashCollection(
          _currentRideId!,
        );
        if (response['success'] == true) {
          CustomSnackbar.show(
            context,
            message: 'Cash collected. Ride finalized.',
            type: SnackbarType.success,
          );
          // Reset to online
          setState(() {
            _status = 'online';
            _currentRideId = null;
            _rideData = null;
            _clearNavigationUi();
            _clearActiveRideStorage();
          });
          _fetchRideHistory();
        } else {
          if (!mounted) return;
          ErrorDisplayHelper.showRideError(
            context,
            response['message']?.toString() ?? 'Failed to confirm cash',
            errors: response['errors'],
            onAction: _handleRideAction,
          );
        }
      }
    } catch (e) {
      CustomSnackbar.show(
        context,
        message: 'Error: $e',
        type: SnackbarType.error,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// GPS must be healthy to complete — a silent fail would strand payment.
  bool _gpsOkForCompletion() {
    return _gpsServiceProblem == null && !_noGpsSignal;
  }

  /// Blocking guidance when GPS is unavailable at completion time.
  void _showGpsBlockedDialog() {
    final detail = _gpsServiceProblem ??
        'No GPS signal received. Completion needs your current location.';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Location needed to complete'),
        content: Text(
          '$detail\n\nMove somewhere with a clear signal, then retry. '
          'The trip stays open — nothing is lost.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await Geolocator.openLocationSettings();
              } catch (_) {
                // Settings can't be opened on some platforms — ignore.
              }
            },
            child: const Text('Open settings'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _handleRideAction();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Fare receipt after completion: actualFare + accumulated wait totals.
  void _showFareSummary({
    required FareSummary summary,
    required String headline,
    String? subline,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(headline),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Trip total'),
                Text(
                  '£${summary.actualFare.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Base fare £${summary.fare.toStringAsFixed(2)}'),
            Text(
              'Wait ${summary.totalWaitMinutes} min · '
              '£${summary.totalWaitFee.toStringAsFixed(2)} fees',
            ),
            if (subline != null) ...[
              const SizedBox(height: 12),
              Text(
                subline,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// Current stop label for proximity guidance ("stop #2").
  String get _currentStopLabel {
    final stops = parseRideStops(_rideData?['stops']);
    final idx = (_rideData?['currentStopIndex'] as num?)?.toInt() ?? 0;
    final active = stops.firstWhere(
      (s) => !s.isCompleted,
      orElse: () => const RideStop(),
    );
    final order = active.stopOrder != 0 ? active.stopOrder : idx + 1;
    return 'stop #$order';
  }

  /// Mark arrival at the current intermediate stop (100m enforced backend).
  /// Proximity errors reuse the persistent banner pattern from pickup.
  Future<void> _handleStopArrive() async {
    if (_currentRideId == null) return;
    final manageLoading = !_isLoading;
    if (manageLoading) setState(() => _isLoading = true);
    try {
      final response = await _apiService.stopArrive(
        _currentRideId!,
        _currentLocation.latitude,
        _currentLocation.longitude,
      );
      if (response['success'] == true) {
        final data = response['data'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(response['data'] as Map)
            : <String, dynamic>{};
        setState(() {
          _status = 'at_stop';
          _proximityDistance = null;
          _proximityRequired = null;
          // Stop-arrive may carry an updated per-ride policy — harvest it.
          _harvestWaitPolicy(data);
          _rideData = {...?_rideData, ...data};
        });
        _persistActiveRide();
        if (!mounted) return;
        CustomSnackbar.show(
          context,
          message: 'Arrived at ${_currentStopLabel} — waiting time started.',
          type: SnackbarType.success,
        );
        _fetchNavigationRoute();
      } else {
        final errors = response['errors'];
        final distance = errors is Map ? errors['distance'] : null;
        if (distance != null) {
          final distInt = distance is num
              ? distance.toInt()
              : int.tryParse(distance.toString()) ?? 0;
          final reqRaw = errors is Map ? errors['required'] : null;
          final reqInt = reqRaw is num
              ? reqRaw.toInt()
              : int.tryParse(reqRaw?.toString() ?? '') ?? 100;
          setState(() {
            _proximityDistance = distInt;
            _proximityRequired = reqInt;
            _proximityTarget = _currentStopLabel;
          });
        }
        if (!mounted) return;
        ErrorDisplayHelper.showRideError(
          context,
          response['message']?.toString() ?? 'Failed to arrive at stop',
          errors: response['errors'],
          onAction: _handleStopArrive,
        );
      }
    } catch (e) {
      if (!mounted) return;
      CustomSnackbar.show(
        context,
        message: 'Error: $e',
        type: SnackbarType.error,
      );
    } finally {
      if (manageLoading && mounted) setState(() => _isLoading = false);
    }
  }

  /// Resume from the stop — backend accrues the leg wait fee into totals.
  Future<void> _handleStopResume() async {
    if (_currentRideId == null) return;
    final manageLoading = !_isLoading;
    if (manageLoading) setState(() => _isLoading = true);
    try {
      final response = await _apiService.stopResume(_currentRideId!);
      if (response['success'] == true) {
        final data = response['data'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(response['data'] as Map)
            : <String, dynamic>{};
        final totalFee = data['totalWaitFee'] is num
            ? (data['totalWaitFee'] as num).toDouble()
            : null;
        final totalMins = data['totalWaitMinutes'] is num
            ? (data['totalWaitMinutes'] as num).toInt()
            : null;
        setState(() {
          _status = 'in_progress';
          _proximityDistance = null;
          _proximityRequired = null;
          _rideData = {...?_rideData, ...data};
        });
        _persistActiveRide();
        if (!mounted) return;
        CustomSnackbar.show(
          context,
          message: totalFee != null
              ? 'Trip resumed — wait total £${totalFee.toStringAsFixed(2)}'
                  '${totalMins != null ? ' ($totalMins min)' : ''}.'
              : 'Trip resumed.',
          type: SnackbarType.success,
        );
        _fetchNavigationRoute();
      } else {
        if (!mounted) return;
        ErrorDisplayHelper.showRideError(
          context,
          response['message']?.toString() ?? 'Failed to resume trip',
          errors: response['errors'],
          onAction: _handleStopResume,
        );
      }
    } catch (e) {
      if (!mounted) return;
      CustomSnackbar.show(
        context,
        message: 'Error: $e',
        type: SnackbarType.error,
      );
    } finally {
      if (manageLoading && mounted) setState(() => _isLoading = false);
    }
  }

  void _declineRide() {
    if (_currentRideId == null) return;

    AudioService.instance.stop();

    // Just reset to online state without calling API
    setState(() {
      _status = 'online';
      _currentRideId = null;
      _rideData = null;
      _clearNavigationUi();
    });
  }

  /// Driver-cancel reasons (flow doc example uses vehicle_breakdown;
  /// ApiService historically sent vehicle_issue — both offered).
  static const List<Map<String, String>> _driverCancelReasons = [
    {'value': 'rider_no_show', 'label': 'Rider no-show'},
    {'value': 'rider_unreachable', 'label': 'Rider unreachable'},
    {'value': 'safety_concern', 'label': 'Safety concern'},
    {'value': 'vehicle_breakdown', 'label': 'Vehicle breakdown'},
    {'value': 'vehicle_issue', 'label': 'Vehicle issue'},
    {'value': 'driver_no_show', 'label': "Can't make it"},
  ];

  /// End-early reasons per the ride-flow contract.
  static const List<Map<String, String>> _endEarlyReasons = [
    {'value': 'user_requested', 'label': 'Rider requested'},
    {'value': 'wrong_destination', 'label': 'Wrong destination'},
    {'value': 'rider_misbehavior', 'label': 'Rider misbehavior'},
    {'value': 'safety_concern', 'label': 'Safety concern'},
    {'value': 'vehicle_issue', 'label': 'Vehicle issue'},
  ];

  /// Show cancellation reason picker and cancel the ride
  void _showCancellationReasonDialog() {
    String? selectedReason;
    bool showReasonError = false;
    bool sheetLoading = false;
    String? sheetError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cancel Ride'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select a reason for cancellation:'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _driverCancelReasons
                      .map(
                        (reason) => ChoiceChip(
                          label: Text(reason['label']!),
                          selected: selectedReason == reason['value'],
                          onSelected: sheetLoading
                              ? null
                              : (selected) => setDialogState(() {
                                    selectedReason =
                                        selected ? reason['value'] : null;
                                    showReasonError = false;
                                  }),
                        ),
                      )
                      .toList(),
                ),
                if (showReasonError) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Please select a reason to continue.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
                if (sheetError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    sheetError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sheetLoading ? null : () => Navigator.pop(context),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: sheetLoading
                  ? null
                  : () async {
                      if (selectedReason == null) {
                        // Required selection — inline guidance, never raw 400.
                        setDialogState(() => showReasonError = true);
                        return;
                      }
                      setDialogState(() {
                        sheetLoading = true;
                        sheetError = null;
                      });
                      final outcome = await _performDriverCancel(
                        selectedReason!,
                      );
                      if (!mounted) return;
                      if (!outcome['ok']) {
                        // Failure stays on the sheet with mapper copy.
                        setDialogState(() {
                          sheetLoading = false;
                          sheetError = outcome['message'];
                        });
                        return;
                      }
                      Navigator.pop(context);
                      _resolveDriverCancelOutcome(outcome);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: sheetLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Cancel Ride',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cancel ride by driver with a reason.
  ///
  /// Returns an outcome map instead of touching UI directly so the sheet
  /// can stay open on failure: `{ok, reassigned, penalty, message}`.
  Future<Map<String, dynamic>> _performDriverCancel(String reason) async {
    if (_currentRideId == null) {
      return {'ok': false, 'message': 'No active ride.'};
    }

    final isScheduled = _rideData?['isScheduled'] == true;

    try {
      Map<String, dynamic> response;
      if (isScheduled) {
        response = await PaymentService.cancelScheduledRideDriver(
          _currentRideId!,
          reason,
        );
      } else {
        response = await _apiService.cancelRideByDriver(
          _currentRideId!,
          reason: reason,
        );
      }

      if (response['success'] != true) {
        final info = RideErrorMapper.map(
          response['message']?.toString() ?? 'Failed to cancel ride',
          response['errors'],
        );
        return {'ok': false, 'message': '${info.title}: ${info.copy}'};
      }

      // Pre-pickup cancel auto-reassigns: the ride lives on without this
      // driver. That's an outcome, not an error.
      final data = response['data'];
      final reassigned = response['reassigned'] == true ||
          (data is Map && data['reassigned'] == true);
      final penalty = isScheduled && data is Map
          ? data['driverPenaltyAmount']
          : null;
      return {
        'ok': true,
        'reassigned': reassigned,
        'penalty': penalty is num ? penalty.toDouble() : null,
      };
    } catch (e) {
      debugPrint('Error cancelling ride: $e');
      return {
        'ok': false,
        'message':
            'Error cancelling ride: ${e.toString().replaceAll('Exception: ', '')}',
      };
    }
  }

  /// Apply a successful driver-cancel outcome: reassigned → info + queue,
  /// full cancel → confirmation + exit.
  void _resolveDriverCancelOutcome(Map<String, dynamic> outcome) {
    final reassigned = outcome['reassigned'] == true;
    final penalty = outcome['penalty'] as double?;
    if (!mounted) return;
    setState(() {
      _status = 'online';
      _currentRideId = null;
      _rideData = null;
      _clearNavigationUi();
      _clearActiveRideStorage();
    });

    if (reassigned) {
      CustomSnackbar.show(
        context,
        message: 'Reassigned to another driver — you are back in the queue.',
        type: SnackbarType.info,
      );
      return;
    }

    var message = 'Ride cancelled.';
    if (penalty != null) {
      message += ' A £${penalty.toStringAsFixed(2)} penalty was applied.';
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ride cancelled'),
        content: Text('$message\nYou are back online.'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show end ride early dialog with reason selection
  void _showEndRideEarlyDialog() {
    String? selectedReason;
    bool showReasonError = false;
    bool sheetLoading = false;
    String? sheetError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('End Ride Early'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The fare will be adjusted based on actual distance traveled.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                const Text('Select a reason:'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _endEarlyReasons
                      .map(
                        (reason) => ChoiceChip(
                          label: Text(reason['label']!),
                          selected: selectedReason == reason['value'],
                          onSelected: sheetLoading
                              ? null
                              : (selected) => setDialogState(() {
                                    selectedReason =
                                        selected ? reason['value'] : null;
                                    showReasonError = false;
                                  }),
                        ),
                      )
                      .toList(),
                ),
                if (showReasonError) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Please select a reason to continue.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
                if (sheetError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    sheetError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sheetLoading ? null : () => Navigator.pop(context),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: sheetLoading
                  ? null
                  : () async {
                      if (selectedReason == null) {
                        setDialogState(() => showReasonError = true);
                        return;
                      }
                      setDialogState(() {
                        sheetLoading = true;
                        sheetError = null;
                      });
                      final outcome = await _performEndEarly(selectedReason!);
                      if (!mounted) return;
                      if (!outcome['ok']) {
                        // Failure stays on the sheet with mapper copy.
                        setDialogState(() {
                          sheetLoading = false;
                          sheetError = outcome['message'];
                        });
                        return;
                      }
                      Navigator.pop(context);
                      _resolveEndEarlyOutcome(outcome);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: sheetLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'End Ride',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// End the ride early with adjusted fare.
  ///
  /// Returns an outcome map so the sheet can stay open on failure:
  /// `{ok, adjustedFare, actualDistance, paymentMethod, message}`.
  Future<Map<String, dynamic>> _performEndEarly(String reason) async {
    if (_currentRideId == null) {
      return {'ok': false, 'message': 'No active ride.'};
    }

    try {
      final response = await _apiService.endRideEarly(
        _currentRideId!,
        latitude: _currentLocation.latitude,
        longitude: _currentLocation.longitude,
        reason: reason,
      );

      if (response['success'] != true) {
        final info = RideErrorMapper.map(
          response['message']?.toString() ?? 'Failed to end ride',
          response['errors'],
        );
        return {'ok': false, 'message': '${info.title}: ${info.copy}'};
      }

      final data = response['data'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(response['data'] as Map)
          : <String, dynamic>{};
      final ride = data['ride'] is Map
          ? Map<String, dynamic>.from(data['ride'] as Map)
          : <String, dynamic>{};
      double asDouble(dynamic v) =>
          v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;
      return {
        'ok': true,
        'adjustedFare': asDouble(
          data['adjustedFare'] ?? data['fare'] ?? ride['fare'],
        ),
        'actualDistance': asDouble(
          data['actualDistance'] ?? ride['actualDistance'],
        ),
        'paymentMethod': _rideData?['paymentMethod'],
      };
    } catch (e) {
      debugPrint('Error ending ride early: $e');
      return {'ok': false, 'message': 'Error ending ride'};
    }
  }

  /// Apply a successful end-early outcome: show adjusted fare + distance,
  /// then route cash rides to collection, others back online.
  void _resolveEndEarlyOutcome(Map<String, dynamic> outcome) {
    final adjustedFare = (outcome['adjustedFare'] as num?)?.toDouble() ?? 0.0;
    final actualDistance =
        (outcome['actualDistance'] as num?)?.toDouble() ?? 0.0;
    final paymentMethod = outcome['paymentMethod'];
    if (!mounted) return;

    if (paymentMethod == 'cash') {
      setState(() {
        _status = 'awaiting_cash_confirmation';
      });
      _persistActiveRide();
      _showEndEarlySummary(
        adjustedFare: adjustedFare,
        actualDistance: actualDistance,
        subline: 'Collect cash from the passenger.',
      );
    } else {
      setState(() {
        _status = 'online';
        _currentRideId = null;
        _rideData = null;
        _clearNavigationUi();
        _clearActiveRideStorage();
      });
      _fetchRideHistory();
      // payment:succeeded socket will finalize
      _showEndEarlySummary(
        adjustedFare: adjustedFare,
        actualDistance: actualDistance,
        subline: null,
      );
    }
  }

  /// Outcome dialog: adjusted fare + actual distance, never a bare toast.
  void _showEndEarlySummary({
    required double adjustedFare,
    required double actualDistance,
    String? subline,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ride ended early'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Adjusted fare'),
                Text(
                  '£${adjustedFare.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Distance traveled ${actualDistance.toStringAsFixed(1)} mi',
            ),
            if (subline != null) ...[
              const SizedBox(height: 12),
              Text(
                subline,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// One-tap start: backend starts the ride from driver_arrived
  /// state with an empty body. Wrong-state 400s go through RideErrorMapper.
  Future<void> _startRideNoOtp() async {
    if (_currentRideId == null) return;

    try {
      final response = await _apiService.startRide(_currentRideId!);
      if (response['success'] == true) {
        setState(() {
          _status = 'in_progress';
          if (response['data'] != null) {
            final newData = response['data'] as Map<String, dynamic>;
            _rideData = {...?_rideData, ...newData};
          }
        });
        _persistActiveRide();
        CustomSnackbar.show(
          context,
          message: 'Trip Started.',
          type: SnackbarType.success,
        );
        // Fetch navigation route to dropoff
        _fetchNavigationRoute();
      } else {
        if (!mounted) return;
        ErrorDisplayHelper.showRideError(
          context,
          response['message']?.toString() ?? 'Failed to start ride',
          errors: response['errors'],
          onAction: _handleRideAction,
        );
      }
    } catch (e) {
      CustomSnackbar.show(
        context,
        message: 'Error: $e',
        type: SnackbarType.error,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SlidingUpPanel(
            controller: _panelController,
            minHeight: _getPanelMinHeight(),
            maxHeight: _getPanelMaxHeight(),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            parallaxEnabled: true,
            parallaxOffset: 0.5,
            body: _buildMapBackground(),
            panel: _buildPanelContent(),
            boxShadow: [
              BoxShadow(blurRadius: 20.0, color: Colors.black.withOpacity(0.1)),
            ],
          ),
        ],
      ),
    );
  }

  double _getPanelMinHeight() {
    switch (_status) {
      case 'offline':
      case 'online':
        return 160;
      case 'request':
        return 320; // Increased to accommodate message banner and prevent overflow
      case 'pickup':
      case 'arrived':
      case 'in_progress':
        return 200;
      case 'complete':
        return 0; // Hidden, overlay takes over
      default:
        return 160;
    }
  }

  double _getPanelMaxHeight() {
    return MediaQuery.of(context).size.height * 0.8;
  }

  Widget _buildMapBackground() {
    if (_isMapLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }

    // Get dynamic destination
    double destLat = 51.5074;
    double destLng = -0.1278;

    if (_rideData != null) {
      if (_status == 'pickup') {
        final coords =
            _rideData!['pickupLocation']?['coordinates'] ?? [0.0, 0.0];
        destLat = coords[1];
        destLng = coords[0];
      } else if (_status == 'in_progress') {
        final coords =
            _rideData!['dropoffLocation']?['coordinates'] ?? [0.0, 0.0];
        destLat = coords[1];
        destLng = coords[0];
      }
    }

    bool isNavigationMode = _status == 'pickup' ||
        _status == 'in_progress' ||
        _status == 'arrived' ||
        _status == 'driver_arrived' ||
        _status == 'at_stop';

    return Stack(
      children: [
        PlatformMap(
          initialLat: _currentLocation.latitude,
          initialLng: _currentLocation.longitude,
          bearing: isNavigationMode ? _currentBearing : 0.0,
          tilt: isNavigationMode ? 45.0 : 0.0,
          markers: [
            MapMarker(
              id: 'driver',
              lat: _currentLocation.latitude,
              lng: _currentLocation.longitude,
              child: const Icon(
                Icons.directions_car,
                color: AppTheme.primaryColor,
                size: 40,
              ),
              title: 'Driver',
            ),
            if (_status == 'pickup' || _status == 'in_progress')
              MapMarker(
                id: 'destination',
                lat: destLat,
                lng: destLng,
                child: Icon(
                  Icons.location_on,
                  color: _status == 'pickup' ? Colors.green : Colors.red,
                  size: 40,
                ),
                title: _status == 'pickup' ? 'Pickup' : 'Dropoff',
              ),
          ],
          polylines: _navigationPolylines.isNotEmpty
              ? _navigationPolylines
              : [
                  if (_status == 'pickup' || _status == 'in_progress')
                    MapPolyline(
                      id: 'route',
                      points: [_currentLocation, LatLng(destLat, destLng)],
                      color: AppTheme.primaryColor,
                      width: 4.0,
                    ),
                ],
        ),

        // Top Bar (Earnings & Status) - Only show when not in full ride flow or make it collapsible
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Earnings Pill
                    // GestureDetector(
                    //   onTap: () =>
                    //       Navigator.pushNamed(context, '/driver-earnings'),
                    //   child: Container(
                    //     padding: const EdgeInsets.symmetric(
                    //       horizontal: 16,
                    //       vertical: 8,
                    //     ),
                    //     decoration: BoxDecoration(
                    //       color: Colors.white,
                    //       borderRadius: BorderRadius.circular(24),
                    //       boxShadow: [
                    //         BoxShadow(
                    //           color: Colors.black.withValues(alpha: 0.1),
                    //           blurRadius: 10,
                    //         ),
                    //       ],
                    //     ),
                    //     child: Row(
                    //       children: [
                    //         Icon(
                    //           Icons.account_balance_wallet,
                    //           color: AppTheme.primaryColor,
                    //         ),
                    //         SizedBox(width: 8),
                    //         Text(
                    //           '£${_todayStats['earnings']}',
                    //           style: GoogleFonts.outfit(
                    //             fontWeight: FontWeight.bold,
                    //             fontSize: 16,
                    //             color: AppTheme.textPrimary,
                    //           ),
                    //         ),
                    //       ],
                    //     ),
                    //   ),
                    // ),

                    // Profile Button
                    CircleAvatar(
                      backgroundColor: Colors.white,
                      child: IconButton(
                        icon: const Icon(Icons.person, color: Colors.black),
                        onPressed: () =>
                            Navigator.pushNamed(context, '/driver-profile'),
                      ),
                    ),
                  ],
                ),
                if (_status == 'online') ...[const SizedBox(height: 16)],
              ],
            ),
          ),
        ),

        // Location-lost / GPS-health warning
        if (_locationBannerMessage != null) _buildGpsWarningBanner(),

        // Proximity guidance — persistent until arrival succeeds
        if (_proximityDistance != null &&
            (_status == 'pickup' || _status == 'in_progress'))
          _buildProximityBanner(),

        // Complete Trip Overlay
        if (_status == 'complete')
          Container(
            color: Colors.black.withOpacity(0.7),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(32),
                margin: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Trip Completed!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You earned £${(_rideData?['fare'] ?? 0.0).toStringAsFixed(2)}',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGpsWarningBanner() {
    final message = _locationBannerMessage ?? '';
    final isHardFailure = _gpsServiceProblem != null;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isHardFailure ? Colors.red : Colors.orange,
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
              Icon(
                isHardFailure ? Icons.location_off : Icons.gps_off,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              if (isHardFailure)
                TextButton(
                  onPressed: () async {
                    try {
                      await Geolocator.openLocationSettings();
                    } catch (_) {
                      // Settings can't be opened on some platforms — ignore.
                    }
                  },
                  child: const Text(
                    'SETTINGS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanelContent() {
    if (_status == 'offline' || _status == 'online') {
      return _buildOfflineOnlineContent();
    } else if (_status == 'request') {
      return DriverRequestPanel(
        rideData: _rideData,
        onAccept: _handleRideAction,
        onDecline: _declineRide,
        isLoading: _isLoading,
      );
    } else if (_status == 'pickup' ||
        _status == 'arrived' ||
        _status == 'driver_arrived' ||
        _status == 'in_progress' ||
        _status == 'at_stop' ||
        _status == 'awaiting_payment' ||
        _status == 'awaiting_cash_confirmation') {
      final stops = parseRideStops(_rideData?['stops']);
      final stopIndex =
          (_rideData?['currentStopIndex'] as num?)?.toInt() ?? 0;
      final waitMinutes =
          (_rideData?['totalWaitMinutes'] as num?)?.toInt();
      final waitFee = _rideData?['totalWaitFee'] is num
          ? (_rideData!['totalWaitFee'] as num).toDouble()
          : null;
      final farePreview = FareSummary.parse(_rideData).actualFare;
      return DriverNavigationPanel(
        // Backend may report driver_arrived; panel treats it as arrived
        // (same one-tap Start Trip action).
        status: _status == 'driver_arrived' ? 'arrived' : _status,
        rideData: _rideData,
        onAction: _handleRideAction,
        onCancel: _showCancellationReasonDialog,
        onEndEarly: _showEndRideEarlyDialog,
        navigationState: _navigationState,
        isLoading: _isLoading,
        freeWaitLabel: _freeWaitLabel,
        freeWaitMinutes: _freeWaitMinutes,
        perMinuteRate: _freeWaitRate,
        stops: stops,
        currentStopIndex: stopIndex,
        onStopArrive: _handleStopArrive,
        onStopResume: _handleStopResume,
        totalWaitMinutes: waitMinutes,
        totalWaitFee: waitFee,
        farePreview: farePreview > 0 ? farePreview : null,
      );
    } else {
      return _buildOfflineOnlineContent();
    }
  }

  Widget _buildOfflineOnlineContent() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Handle
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Prominent Toggle Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GestureDetector(
              onTap: _toggleOnline,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _status == 'online'
                        ? [Colors.redAccent, Colors.red]
                        : [const Color(0xFFFF6B35), const Color(0xFFFF8E53)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (_status == 'online'
                                  ? Colors.red
                                  : const Color(0xFFFF6B35))
                              .withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Center(
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _status == 'online' ? 'GO OFFLINE' : 'GO ONLINE',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 36),

          // Content section
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Today's Summary Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Today's Summary",
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/driver-ride-history');
                        },
                        child: Text(
                          'See All',
                          style: GoogleFonts.outfit(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Stats row
                  Row(
                    children: [
                      _buildStatCard(
                        'Trips',
                        _todayStats['trips']!,
                        Icons.local_taxi_outlined,
                      ),
                      const SizedBox(width: 16),
                      _buildStatCard(
                        'Hours',
                        _todayStats['hours']!,
                        Icons.access_time_rounded,
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Recent Activity Header
                  Text(
                    'Recent Activity',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Activity List
                  if (_isHistoryLoading && _recentRides.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_recentRides.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            Icon(
                              Icons.history,
                              size: 48,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No recent rides yet',
                              style: GoogleFonts.outfit(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._recentRides.map((ride) => _buildRideItem(ride)),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Icon(icon, color: AppTheme.primaryColor, size: 20),
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRideItem(dynamic ride) {
    final createdAt = DateTime.parse(ride['createdAt']);
    final timeStr = DateFormat('hh:mm a').format(createdAt);
    final isCancelled = ride['status'].toString().contains('cancelled');
    final pickupAddr = ride['pickupLocation']?['address'] ?? 'Unknown Pickup';

    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, '/driver-ride-detail', arguments: ride);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isCancelled
                    ? Colors.red.withOpacity(0.1)
                    : AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.history,
                color: isCancelled ? Colors.red : AppTheme.primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pickupAddr,
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeStr,
                    style: GoogleFonts.outfit(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '£${(ride['fare'] ?? 0.0).toStringAsFixed(2)}',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: isCancelled ? Colors.red : AppTheme.primaryColor,
                  ),
                ),
                if (isCancelled)
                  Text(
                    'Cancelled',
                    style: GoogleFonts.outfit(
                      color: Colors.red,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
