import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import '../../core/services/audio_service.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
import '../../core/services/socket_service.dart';
import '../../core/api_service.dart';
import '../../core/services/navigation_service.dart';
import '../../core/services/places_service.dart';
import '../../core/services/marker_interpolation_service.dart';
import '../../core/services/payment_service.dart';
import '../../core/services/stripe_service.dart';
import '../../core/models/error_display_helper.dart';
import '../../core/widgets/platform_map.dart';
import '../../core/widgets/connection_status_banner.dart';
import 'ride_complete_screen.dart';
import 'payment_webview_screen.dart';

class RideAssignedScreen extends StatefulWidget {
  final String rideId;
  final Map<String, dynamic>? pickup;
  final Map<String, dynamic>? dropoff;
  final double fare;
  final Map<String, dynamic>? driver; // Added initial driver data
  final String? paymentTiming; // 'pay_now' or 'pay_later'
  final String? clientSecret; // for pay_later (saved from createRide)
  final bool isScheduled;

  const RideAssignedScreen({
    super.key,
    required this.rideId,
    this.pickup,
    this.dropoff,
    this.fare = 15.50,
    this.driver,
    this.paymentTiming,
    this.clientSecret,
    this.isScheduled = false,
  });

  @override
  State<RideAssignedScreen> createState() => _RideAssignedScreenState();
}

class _RideAssignedScreenState extends State<RideAssignedScreen>
    with WidgetsBindingObserver {
  final SocketService _socketService = SocketService();
  final ApiService _apiService = ApiService();
  final NavigationService _navigationService = NavigationService();
  final PlacesService _placesService = PlacesService();
  String _rideStatus = 'searching';
  String? _reassignMessage;

  bool _isValidDriver(dynamic driver) {
    if (driver is! Map) return false;
    if (driver.isEmpty) return false;
    final id = driver['_id'] ?? driver['id'];
    final name = driver['name'];
    final idOk = id != null && id.toString().trim().isNotEmpty;
    final nameOk = name != null && name.toString().trim().isNotEmpty;
    return idOk || nameOk;
  }

  String _normalizeRideStatus(dynamic status, bool hasValidDriver) {
    final statusStr = status?.toString() ?? '';
    if (statusStr.isEmpty || statusStr == 'requested') {
      return 'searching';
    }

    if (!hasValidDriver &&
        (statusStr == 'accepted' ||
            statusStr == 'driver_arrived' ||
            statusStr == 'in_progress')) {
      return 'searching';
    }

    return statusStr;
  }

  // Locations (using latlong2 for cross-platform compatibility)
  late latlong2.LatLng _userLocation;
  latlong2.LatLng? _driverLocation;
  late latlong2.LatLng _pickupLocation;
  late latlong2.LatLng _dropoffLocation;

  // Map Elements (using cross-platform types)
  List<MapMarker> _markers = [];
  List<MapPolyline> _polylines = [];

  // Driver Data
  Map<String, dynamic> _driver = {};
  String? _currentDriverId; // Track current driver ID for room management

  // Detailed Addresses
  String _pickupAddress = '';
  String _dropoffAddress = '';

  // Navigation State
  NavigationState? _navigationState;

  // Marker Interpolation for smooth car animation
  MarkerInterpolationService? _markerInterpolation;
  StreamSubscription<InterpolatedPosition>? _interpolationSubscription;

  // Connection status subscription
  StreamSubscription<bool>? _connectionSubscription;

  // ETA tracking
  Timer? _etaTimer;
  String _etaText = 'Calculating...';
  int _etaMinutes = 0;

  // ETA coordination: socket ETA (realtime, per location update) wins over
  // fallback HTTP ETA (30s timer, slow response). Without this, a stale
  // fallback response overwrites fresher socket values -> ETA jumps 11-4-5
  // and can show e.g. 11min even as driver reaches pickup.
  DateTime? _lastSocketEtaAt;
  int _etaRequestSeq = 0;

  // Cancellation state
  bool _isCancelling = false;
  bool _isProcessingPayment = false;
  bool _isAwaitingPaymentConfirmation = false;
  Map<String, dynamic>? _pendingPaymentRideData;
  bool _isPaymentMethodSelected = false;
  String _selectedPaymentMethodDisplay = '';

  // Chrome Custom Tab payment link tracking
  // Payment link now uses PaymentWebViewScreen (direct result via Navigator)

  // Prevent concurrent socket listener re-registration (initState vs reconnect)
  bool _setupInProgress = false;

  // Promo (Free Ride) state
  bool _isPromoRide = false;
  bool _promoFullyCovered = false;
  double _promoOriginalFare = 0.0;
  double? _currentFare;
  double? _completedFare; // actual fare captured from ride:completed event
  Map<String, dynamic>? _completedRideData; // full ride:completed payload

  // Scheduled ride flag — set from widget param and confirmed from live ride data
  bool _isScheduled = false;
  
  // Deferred payment data for scheduled airport rides (waiting for ride:earlyCompleted)
  Map<String, dynamic>? _deferredPaymentSuccessData;

  // Payment sheet/loading guards — prevent stacked sheets and popping wrong routes.
  // Without these, every API/WebView failure re-showed the same sheet -> infinite loop.
  bool _isPaymentSheetOpen = false;
  bool _isPaymentLoadingShowing = false;
  int _paymentRetryCount = 0;
  static const int _maxPaymentRetries = 3;
  // In-flight guard: blocks double-tap on payment rows while a
  // select-payment request (or Stripe sheet) is still running.
  bool _isSelectingPayment = false;
  // Receipt navigation guard: completed events fan out from several sources
  // (socket, FCM, pay-later completion) — the receipt pushes exactly once.
  bool _didNavigateToReceipt = false;
  // Inline sheet error (e.g. invalid-method 400) — rendered inside the
  // bottom sheet so the rider stays on the sheet instead of dead-ending.
  String? _paymentSheetError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeLocations();
    _setupInitialState();
    _setupSocketListeners();
    _setupConnectionListener();
    _fetchDetailedAddresses();
    _setupNavigationListener();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [RideAssignedScreen] App resumed, syncing state...');

      // 1. Force check socket connection
      if (!_socketService.isConnected) {
        debugPrint(
          '🔌 [RideAssignedScreen] Socket disconnected, reconnecting...',
        );
        _socketService.initSocket(forceReconnect: true);
      }

      // 2. Re-emit online status and rejoin driver room
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.user;
      if (user != null) {
        final userId = user['_id'] ?? user['id'] ?? user['userId'];
        if (userId != null) {
          _socketService.emitUserOnline(userId);
        }
      }

      // Rejoin driver room if we have a driver
      if (_currentDriverId != null) {
        debugPrint(
          '🔄 [RideAssignedScreen] Rejoining driver room: $_currentDriverId',
        );
        _socketService.joinDriverRoom(_currentDriverId!);
      }

      // 3. CRITICAL: Manual Sync Fallback
      _syncRideStatus();
    }
  }

  /// Sync ride status with backend when app resumes
  Future<void> _syncRideStatus() async {
    try {
      debugPrint(
        '🔄 [RideAssignedScreen] Syncing ride status for ride: ${widget.rideId}',
      );
      final response = await _apiService.getRideDetails(widget.rideId);

      if (response['success'] == true && response['data'] != null) {
        final rideData = response['data'];

        // Capture promo info from sync
        final bool isPromo = rideData['isPromoRide'] == true;
        // Backend may omit promoFullyCovered; infer it from fare == 0 when it's a promo ride
        final double? currentFare = rideData['fare'] != null
            ? (rideData['fare'] as num).toDouble()
            : null;
        final bool fullyCovered =
            rideData['promoFullyCovered'] == true ||
            (isPromo && currentFare != null && currentFare == 0.0);
        final double? originalFare = rideData['originalFare'] != null
            ? (rideData['originalFare'] as num).toDouble()
            : null;

        if (mounted) {
          setState(() {
            _isPromoRide = isPromo;
            _promoFullyCovered = fullyCovered;
            if (originalFare != null) _promoOriginalFare = originalFare;
            if (currentFare != null) _currentFare = currentFare;
          });
        }

        final status = rideData['status'];
        final driverData = rideData['driver'];
        final hasValidDriver = _isValidDriver(driverData);
        final normalizedStatus = _normalizeRideStatus(status, hasValidDriver);

        debugPrint(
          '🔄 [RideAssignedScreen] Synced ride status: $status (normalized: $normalizedStatus), current UI state: $_rideStatus',
        );

        // If backend says it's in a different state than our UI
        if (normalizedStatus != _rideStatus) {
          debugPrint(
            '⚠️ [RideAssignedScreen] Status mismatch detected! Backend: $status, UI: $_rideStatus',
          );

          // Update UI to match backend state
          if (mounted) {
            setState(() {
              _rideStatus = normalizedStatus;

              // Update driver data only when valid
              if (hasValidDriver) {
                _driver = driverData as Map<String, dynamic>;

                // Update driver location
                if (_driver['location'] != null) {
                  final coords = _driver['location']['coordinates'];
                  final newLocation = latlong2.LatLng(coords[1], coords[0]);

                  if (_driverLocation == null) {
                    _driverLocation = newLocation;
                    _initMarkerInterpolation(newLocation);
                  } else {
                    _markerInterpolation?.updatePosition(newLocation);
                  }
                }
              }

              _updateMarkers();
            });

            debugPrint(
              '✅ [RideAssignedScreen] UI updated to match backend status: $status',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [RideAssignedScreen] Error syncing ride status: $e');
    }
  }

  void _setupInitialState() {
    debugPrint('🚀 [RideAssignedScreen] Setting up initial state...');
    debugPrint('🚀 [RideAssignedScreen] widget.driver: ${widget.driver}');

    // Initialise scheduled flag from widget param
    _isScheduled = widget.isScheduled;

    final bool hasValidInitialDriver = _isValidDriver(widget.driver);

    if (hasValidInitialDriver) {
      debugPrint('✅ [RideAssignedScreen] Initial driver data provided');
      _rideStatus = 'accepted';
      _driver = widget.driver as Map<String, dynamic>;

      debugPrint('👤 [RideAssignedScreen] Initial driver: $_driver');

      // Extract driver ID and join their location room
      _currentDriverId =
          _driver['_id']?.toString() ?? _driver['id']?.toString();
      if (_currentDriverId != null) {
        _socketService.joinDriverRoom(_currentDriverId!);
        debugPrint(
          '🚗 [RideAssignedScreen] Joined driver room: driver:$_currentDriverId',
        );

        // Start tracking driver location in real-time
        _socketService.startTrackingDriver(_currentDriverId!);
      }

      if (_driver['location'] != null) {
        final coords = _driver['location']['coordinates'];
        debugPrint('📍 [RideAssignedScreen] Initial driver location: $coords');
        _driverLocation = latlong2.LatLng(coords[1], coords[0]);

        // Initialize marker interpolation with driver's initial position
        _initMarkerInterpolation(latlong2.LatLng(coords[1], coords[0]));

        // Start periodic ETA updates with real traffic data
        _startETAUpdates();
      }
    } else {
      debugPrint(
        '⏳ [RideAssignedScreen] No initial driver data, waiting for socket event...',
      );
    }
  }

  /// Initialize the marker interpolation service for smooth car animation
  void _initMarkerInterpolation(latlong2.LatLng initialPosition) {
    _markerInterpolation?.dispose();
    _interpolationSubscription?.cancel();

    _markerInterpolation = MarkerInterpolationService(
      initialPosition: initialPosition,
      interpolationDurationMs: 2000, // 2 second smooth animation
    );

    // Listen to interpolated positions and update the marker
    _interpolationSubscription = _markerInterpolation!.positionStream.listen((
      interpolated,
    ) {
      if (mounted) {
        // Only update if position actually changed (prevent infinite rebuilds)
        final newLocation = latlong2.LatLng(
          interpolated.position.latitude,
          interpolated.position.longitude,
        );

        // Check if position changed by more than ~1 meter
        final distance = const latlong2.Distance().as(
          latlong2.LengthUnit.Meter,
          _driverLocation ?? newLocation,
          newLocation,
        );

        if (distance > 1.0 || _driverLocation == null) {
          setState(() {
            _driverLocation = newLocation;
            _updateMarkers();
          });
        }
      }
    });

    debugPrint('🚗 [RideAssignedScreen] Marker interpolation initialized');
  }

  void _setupConnectionListener() {
    _connectionSubscription = _socketService.connectionStatus.listen((
      isConnected,
    ) {
      if (isConnected) {
        if (_currentDriverId != null) {
          debugPrint(
            '🔄 [RideAssignedScreen] Reconnected, rejoining driver room',
          );
          _socketService.joinDriverRoom(_currentDriverId!);
        }

        // Re-emit user online
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final user = authProvider.user;
        if (user != null) {
          final userId = user['_id'] ?? user['id'] ?? user['userId'];
          if (userId != null) {
            _socketService.emitUserOnline(userId);
          }
        }

        // CRITICAL: Re-register socket event listeners in case the socket
        // was recreated (initSocket forceReconnect disposes old socket,
        // losing all event listeners registered via socket.on()).
        debugPrint(
          '🔄 [RideAssignedScreen] Reconnected — re-registering socket event listeners',
        );
        _setupSocketListeners();

        // Auto-sync ride status after any disconnection gap > 3 seconds
        final gap = _socketService.disconnectionGap;
        if (gap != null && gap.inSeconds > 3) {
          debugPrint(
            '🔄 [RideAssignedScreen] Disconnection gap: ${gap.inSeconds}s — auto-syncing ride status',
          );
          _syncRideStatus();
        }
      }
    });
  }

  void _initializeLocations() {
    // Use provided coordinates or default to 0,0 (will be updated by socket/map fit)
    final pickupCoords = widget.pickup?['coordinates'] ?? [0.0, 0.0];
    final dropoffCoords = widget.dropoff?['coordinates'] ?? [0.0, 0.0];

    // MongoDB GeoJSON is [lng, lat], but we need to be careful.
    // Based on DestinationSearchScreen, we are passing [lng, lat].
    // latlong2.LatLng takes (lat, lng).

    if (widget.pickup != null) {
      _userLocation = latlong2.LatLng(pickupCoords[1], pickupCoords[0]);
      _pickupLocation = latlong2.LatLng(pickupCoords[1], pickupCoords[0]);
    } else {
      _userLocation = const latlong2.LatLng(0, 0);
      _pickupLocation = const latlong2.LatLng(0, 0);
    }

    if (widget.dropoff != null) {
      _dropoffLocation = latlong2.LatLng(dropoffCoords[1], dropoffCoords[0]);
    } else {
      _dropoffLocation = const latlong2.LatLng(0, 0);
    }

    _updateMarkers();
  }

  /// Fetch detailed addresses for pickup and dropoff
  Future<void> _fetchDetailedAddresses() async {
    if (widget.pickup != null) {
      final address = await _placesService.getAddressFromLatLng(
        _pickupLocation.latitude,
        _pickupLocation.longitude,
      );
      if (mounted) {
        setState(() {
          _pickupAddress =
              address ?? widget.pickup?['address'] ?? 'Pickup Location';
        });
      }
    }

    if (widget.dropoff != null) {
      final address = await _placesService.getAddressFromLatLng(
        _dropoffLocation.latitude,
        _dropoffLocation.longitude,
      );
      if (mounted) {
        setState(() {
          _dropoffAddress =
              address ?? widget.dropoff?['address'] ?? 'Dropoff Location';
        });
      }
    }
  }

  /// Setup navigation listener for route updates
  void _setupNavigationListener() {
    _navigationService.routeUpdates.listen((state) {
      if (mounted) {
        setState(() {
          _navigationState = state;
          _updatePolylines();
        });
      }
    });
  }

  Future<void> _setupSocketListeners() async {
    // CRITICAL: Prevent concurrent re-registration (initState vs reconnect)
    if (_setupInProgress) return;
    _setupInProgress = true;
    try {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    debugPrint('🔌 [RideAssignedScreen] Initializing socket listeners...');

    await _socketService.initSocket(
      forceReconnect: false,
    ); // Don't force here, already connected from HomeScreen

    // CRITICAL: Remove any existing listeners to prevent duplicates
    debugPrint(
      '🧹 [RideAssignedScreen] Cleaning up existing socket listeners...',
    );
    _socketService.off('ride:accepted');
    _socketService.off('driver:locationChanged');
    _socketService.off('ride:started');
    _socketService.off('ride:completed');
    _socketService.off('ride:driverArrived');
    _socketService.off('ride:cancelled');
    _socketService.off('ride:cancelledByDriver');
    _socketService.off('ride:earlyCompleted');
    _socketService.off('ride:expired');
    _socketService.off('payment:succeeded');
    _socketService.off('payment:authorized');
    _socketService.off('payment:failed');
    _socketService.off('ride:longRunning');
    _socketService.off('user:status');
    _socketService.off('ride:promoApplied');
    _socketService.offDriverReassigning();
    _socketService.offPaymentSelected();

    // Ensure we are joined to the driver room after socket init
    if (_currentDriverId != null) {
      debugPrint(
        '🔄 [RideAssignedScreen] Re-confirming join driver room: driver:$_currentDriverId',
      );
      _socketService.joinDriverRoom(_currentDriverId!);
    }

    if (user != null) {
      debugPrint(
        '📤 [RideAssignedScreen] Emitting user:goOnline for user: ${user['_id']}',
      );
      _socketService.emit('user:goOnline', {'userId': user['_id']});
    } else {
      debugPrint(
        '⚠️ [RideAssignedScreen] User is null, cannot emit user:goOnline',
      );
    }

    _socketService.on('user:status', (data) {
      debugPrint('📩 [RideAssignedScreen] User status: ${data['status']}');
    });

    _socketService.onDriverReassigning((data) {
      debugPrint(
        '═══════════════════════════════════════════════════════',
      );
      debugPrint('🔄 [RideAssignedScreen] DRIVER REASSIGNING EVENT RECEIVED');
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('📦 [RideAssignedScreen] Reassign data: $data');

      if (!mounted || !context.mounted) return;

      final message =
          data['message']?.toString() ??
          'Your driver had an unexpected issue. We\'re assigning you a new driver.';
      final reassignmentCount = data['reassignmentCount'];

      scheduleMicrotask(() {
        if (!mounted || !context.mounted) return;

        setState(() {
          // Ride is still alive — reset to searching for a new driver.
          // Clear the old driver so the UI shows "finding new driver".
          _rideStatus = 'searching';
          _driver = {};
          _driverLocation = null;
          _currentDriverId = null;
          _reassignMessage = message;
        });

        // Leave the old driver's location room if joined.
        // (joinDriverRoom is keyed by driver id; old id already cleared above)

        if (reassignmentCount != null) {
          debugPrint(
            '🔄 [RideAssignedScreen] Reassignment count: $reassignmentCount',
          );
        }

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    });

    _setupPaymentSelectedListener();

    _socketService.on('ride:accepted', (data) {
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('✅ [RideAssignedScreen] RIDE ACCEPTED EVENT RECEIVED');
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('📦 [RideAssignedScreen] Full data: $data');
      debugPrint('📦 [RideAssignedScreen] Data type: ${data.runtimeType}');

      // Log individual fields for debugging
      debugPrint('🔑 [RideAssignedScreen] rideId: ${data['rideId']}');
      debugPrint('🔑 [RideAssignedScreen] status: ${data['status']}');
      debugPrint('🔑 [RideAssignedScreen] message: ${data['message']}');
      debugPrint('👤 [RideAssignedScreen] driver object: ${data['driver']}');

      // Extract driver data
      final driverData = data['driver'];
      if (driverData != null) {
        debugPrint(
          '👤 [RideAssignedScreen] Driver ID: ${driverData['id'] ?? driverData['_id']}',
        );
        debugPrint(
          '👤 [RideAssignedScreen] Driver name: ${driverData['name']}',
        );
        debugPrint(
          '👤 [RideAssignedScreen] Driver phone: ${driverData['phone']}',
        );
        debugPrint(
          '👤 [RideAssignedScreen] Driver rating: ${driverData['rating']}',
        );
        debugPrint('🚗 [RideAssignedScreen] Vehicle: ${driverData['vehicle']}');
        debugPrint(
          '📍 [RideAssignedScreen] Driver location: ${driverData['location']}',
        );
      } else {
        debugPrint('⚠️ [RideAssignedScreen] Driver data is NULL!');
      }

      if (!_isValidDriver(driverData)) {
        debugPrint(
          '⚠️ [RideAssignedScreen] Invalid driver data received, ignoring ride:accepted.',
        );
        return;
      }

      // CRITICAL: Check mounted AND context validity before setState
      if (!mounted || !context.mounted) {
        debugPrint(
          '⚠️ [RideAssignedScreen] Widget not mounted, ignoring ride:accepted',
        );
        return;
      }

      // Use scheduleMicrotask for reliable iOS execution
      debugPrint(
        '📍 [RideAssignedScreen] Scheduling ride:accepted state update...',
      );
      scheduleMicrotask(() {
        if (!mounted || !context.mounted) return;

        setState(() {
          _rideStatus = 'accepted';
          _driver = driverData as Map<String, dynamic>;
          _reassignMessage = null;

          // Capture fare & promo info eagerly so we don't need an extra
          // API call when the driver arrives.
          if (data['fare'] != null) {
            final double acceptedFare = (data['fare'] as num).toDouble();
            _currentFare = acceptedFare;
            if (acceptedFare == 0.0) {
              _isPromoRide = true;
              _promoFullyCovered = true;
            }
          }
          if (data['isPromoRide'] == true) _isPromoRide = true;
          if (data['originalFare'] != null) {
            _promoOriginalFare = (data['originalFare'] as num).toDouble();
          }

          debugPrint('👤 [RideAssignedScreen] Extracted driver: $_driver');

          // Extract driver ID and join their location room for real-time updates
          _currentDriverId =
              _driver['_id']?.toString() ?? _driver['id']?.toString();
          if (_currentDriverId != null) {
            _socketService.joinDriverRoom(_currentDriverId!);
            debugPrint(
              '🚗 [RideAssignedScreen] Joined driver room: driver:$_currentDriverId',
            );
          } else {
            debugPrint(
              '⚠️ [RideAssignedScreen] Could not extract driver ID from: $_driver',
            );
          }

          if (data['driver']?['location'] != null) {
            final coords = data['driver']['location']['coordinates'];
            debugPrint('📍 [RideAssignedScreen] Driver coordinates: $coords');
            _driverLocation = latlong2.LatLng(coords[1], coords[0]);

            // Initialize marker interpolation for smooth car animation
            _initMarkerInterpolation(latlong2.LatLng(coords[1], coords[0]));

            // Fetch navigation route from driver to pickup
            _fetchNavigationRoute();

            // Start tracking driver location in real-time
            if (_currentDriverId != null) {
              _socketService.startTrackingDriver(_currentDriverId!);
              // Start periodic ETA updates with real traffic data
              _startETAUpdates();
            }
          } else {
            debugPrint('⚠️ [RideAssignedScreen] Driver location is NULL');
          }
          _updateMarkers();
        });

        debugPrint('═══════════════════════════════════════════════════════');
        debugPrint(
          '✅ [RideAssignedScreen] State updated - Status: $_rideStatus',
        );
        debugPrint('═══════════════════════════════════════════════════════');
      });
    });

    _socketService.on('driver:locationChanged', (data) {
      debugPrint('📍 [RideAssignedScreen] Driver Location Updated: $data');

      // CRITICAL: Check mounted AND context validity
      if (!mounted || !context.mounted) {
        debugPrint(
          '⚠️ [RideAssignedScreen] Widget not mounted, ignoring location update',
        );
        return;
      }

      // Handle location updates based on ride status:
      // - driver_assigned/accepted: Car moving toward pickup
      // - driver_arrived: Car stationary at pickup (still update position for accuracy)
      // - in_progress: Car moving toward destination
      if (_rideStatus == 'accepted' ||
          _rideStatus == 'driver_arrived' ||
          _rideStatus == 'in_progress') {
        // Use marker interpolation for smooth animation instead of direct update
        if (data['location']?['coordinates'] != null) {
          final coords = data['location']['coordinates'];
          final newPosition = latlong2.LatLng(coords[1], coords[0]);

          if (_markerInterpolation != null) {
            // Smooth interpolation to new position
            // For driver_arrived, we still update but car appears stationary at pickup
            _markerInterpolation!.updatePosition(newPosition);
          } else {
            // Fallback: initialize interpolation if not set up
            _initMarkerInterpolation(newPosition);
          }

          // CRITICAL: Extract ETA from socket event (server-calculated with traffic)
          // This is more efficient than calling Distance Matrix API repeatedly
          // NOTE: Manual-arrival only. eta.status == 'driver_arrived' from
          // proximity must NOT trigger arrival UI. Arrival UI fires only on
          // explicit ride:driverArrived socket event / FCM driver_arrived,
          // which backend sends after driver taps "arrived at pickup"
          // (POST /rides/:id/arrive).
          if (data['eta'] != null && _rideStatus == 'accepted') {
            final eta = data['eta'];

            final duration = eta['duration'] as String?; // e.g., "5 mins"
            final isGoingToPickup = eta['isGoingToPickup'] as bool? ?? true;

            if (duration != null && isGoingToPickup) {
              // Full duration string may be "1 hour 11 mins" - parse all parts.
              final minutes = _parseEtaMinutes(duration);

              _lastSocketEtaAt = DateTime.now();
              setState(() {
                _etaText = duration;
                _etaMinutes = minutes;
              });

              debugPrint(
                '🕐 [RideAssignedScreen] ETA from socket: $_etaText ($_etaMinutes mins)',
              );
            }
          }

          // Update navigation route in real-time (don't need to update annotations here,
          // the interpolation stream handles that)
          // Skip route updates when driver has arrived (car is stationary)
          if (_rideStatus != 'driver_arrived') {
            _updateNavigationRoute();
          }
        }
      }
    });

    _socketService.on('ride:started', (data) {
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('🚀 [RideAssignedScreen] RIDE STARTED EVENT RECEIVED');
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint(
        '📦 [RideAssignedScreen] Platform: iOS=${Platform.isIOS}, Android=${Platform.isAndroid}',
      );
      debugPrint('📦 [RideAssignedScreen] Full data: $data');
      debugPrint('📦 [RideAssignedScreen] Data type: ${data.runtimeType}');
      debugPrint('📦 [RideAssignedScreen] Mounted: $mounted');
      debugPrint('📦 [RideAssignedScreen] Context mounted: ${context.mounted}');

      if (!mounted || !context.mounted) {
        debugPrint(
          '⚠️ [RideAssignedScreen] Widget not mounted, skipping handler',
        );
        return;
      }

      // Stop tracking driver location updates (ride has started)
      if (_currentDriverId != null) {
        debugPrint(
          '🛑 [RideAssignedScreen] Stopping driver tracking for: $_currentDriverId',
        );
        _socketService.stopTrackingDriver(_currentDriverId!);
      }

      // Stop ETA updates (no longer needed)
      _stopETAUpdates();

      // Use scheduleMicrotask for reliable iOS execution
      debugPrint(
        '📍 [RideAssignedScreen] Scheduling ride:started state update...',
      );
      scheduleMicrotask(() {
        if (!mounted || !context.mounted) {
          debugPrint('⚠️ [RideAssignedScreen] Widget unmounted in microtask');
          return;
        }

        debugPrint('✅ [RideAssignedScreen] Updating UI to in_progress state');
        debugPrint('   → Current status before setState: $_rideStatus');
        setState(() {
          _rideStatus = 'in_progress';
          _updateMarkers();
          // Switch to navigation from current to dropoff
          _fetchNavigationRoute();
        });
        debugPrint('✅ [RideAssignedScreen] Ride started state update complete');
        debugPrint('   → New status after setState: $_rideStatus');
        debugPrint('   → Widget is still mounted: $mounted');
      });
    });

    _socketService.on('ride:completed', (data) {
      if (!mounted) return;
      debugPrint('🏁 [RideAssignedScreen] Ride Completed: $data');

      // If this is an early completion that's also triggering ride:completed,
      // we ignore it if we already have the adjusted fare data.
      if (data['status'] == 'early_completed') {
        debugPrint('ℹ️ [RideAssignedScreen] Ignoring ride:completed as it is marked as early_completed');
        return;
      }

      final timing = widget.paymentTiming ?? data['paymentTiming']?.toString();
      final bool isPayLater = timing == 'pay_later';
      final completedFare = (data['fare'] as num?)?.toDouble() ?? widget.fare;
      final completedDistance = (data['distance'] as num?)?.toDouble();
      final bool promoRide = data['isPromoRide'] == true;
      final double? promoOriginalFare = (data['originalFare'] as num?)
          ?.toDouble();

      if (isPayLater) {
        setState(() {
          _isPromoRide = promoRide;
          if (promoOriginalFare != null) _promoOriginalFare = promoOriginalFare;
          _completedFare = completedFare;
          _completedRideData = data is Map<String, dynamic> ? data : null;
        });
        _handlePayLaterCompletion(
          fare: completedFare,
          distance: completedDistance,
          rideData: data is Map<String, dynamic> ? data : null,
        );
        return;
      }

      setState(() {
        _isPromoRide = promoRide;
        if (promoOriginalFare != null) _promoOriginalFare = promoOriginalFare;
        _completedFare = completedFare;

        // For scheduled rides: merge deferred payment data into completed data
        // so payment method (payment_link) is preserved, not lost or defaulted to cash
        if (_isScheduled && _deferredPaymentSuccessData != null) {
          final rawData = data is Map<String, dynamic> ? data : <String, dynamic>{};
          _completedRideData = {
            ..._deferredPaymentSuccessData!,
            ...rawData,
          };
          _deferredPaymentSuccessData = null;
        } else {
          _completedRideData = data is Map<String, dynamic> ? data : null;
        }

        _rideStatus = 'completed';
      });
    });

    // Listen for promo applied event (user's 6th ride within Milton Keynes)
    _socketService.on('ride:promoApplied', (data) {
      if (!mounted) return;
      debugPrint('🎁 [RideAssignedScreen] Promo Applied: $data');
      final originalFare = (data['originalFare'] as num?)?.toDouble() ?? 0.0;
      final newFare = (data['fare'] as num?)?.toDouble() ?? 0.0;
      final promoMessage =
          data['message']?.toString() ??
          'Your free MK ride has been applied! This ride is on us.';

      if (mounted) {
        setState(() {
          _isPromoRide = true;
          _promoOriginalFare = originalFare;
          _currentFare = newFare;
          if (newFare == 0) _promoFullyCovered = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Text('🎁  ', style: TextStyle(fontSize: 18)),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Free Ride Applied!',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        promoMessage,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF22C55E),
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    // New listener for Payment Link Authorization (happens when user pays via link)
    _socketService.on('payment:authorized', (data) {
      if (!mounted) return;
      debugPrint('✅ [RideAssignedScreen] Payment Authorized: $data');

      final eventRideId = data['rideId']?.toString();
      if (eventRideId != null && eventRideId != widget.rideId) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment authorized! Ride can now begin.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );

      setState(() {
        _isPaymentMethodSelected = true;
        // Optionally close WebView if it's open (handled by user navigation usually)
      });
    });

    // New listener for Payment Failure (expired link or failed payment)
    _socketService.on('payment:failed', (data) {
      if (!mounted) return;
      debugPrint('❌ [RideAssignedScreen] Payment Failed: $data');

      final eventRideId = data['rideId']?.toString();
      if (eventRideId != null && eventRideId != widget.rideId) return;

      final message = data['message'] ?? 'Payment failed. Please try again.';

      // Show error
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Payment Failed'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                _showPaymentSelectionModal(); // Allow retry
              },
              child: const Text('Select Payment Method'),
            ),
          ],
        ),
      );

      setState(() {
        _isPaymentMethodSelected = false;
      });
    });

    _socketService.on('payment:succeeded', (data) {
      if (!mounted || !context.mounted) return;

      debugPrint('✅ [RideAssignedScreen] Payment Succeeded: $data');

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      String? eventRideId;
      if (data is Map) {
        eventRideId =
            data['bookingId']?.toString() ??
            data['rideId']?.toString() ??
            data['_id']?.toString();
      }

      if (eventRideId != null && eventRideId != widget.rideId) {
        return;
      }

      final bool hasPendingConfirmation =
          _isAwaitingPaymentConfirmation || _pendingPaymentRideData != null;

      if (!hasPendingConfirmation && _rideStatus != 'completed') {
        debugPrint(
          'ℹ️ [RideAssignedScreen] Payment succeeded without pending state; showing success screen anyway.',
        );
      }

      final Map<String, dynamic> mergedRideData = {
        if (_pendingPaymentRideData != null) ..._pendingPaymentRideData!,
        if (data is Map<String, dynamic>) ...data,
      };

      // For scheduled airport rides, defer showing the success screen until ride:earlyCompleted
      // arrives (which contains the correct originalFare). Store the payment data temporarily.
      if (_isScheduled) {
        debugPrint(
          '⏳ [RideAssignedScreen] Deferring success screen for scheduled ride; waiting for ride:earlyCompleted...',
        );
        setState(() {
          _deferredPaymentSuccessData = mergedRideData;
        });
        return;
      }

      _showPaymentSuccessScreen(mergedRideData);
    });

    _socketService.on('ride:driverArrived', (data) {
      debugPrint('🚖 [RideAssignedScreen] Driver Arrived via event: $data');
      _handleDriverArrival(data);
    });

    _socketService.on('ride:cancelled', (data) {
      if (mounted) {
        debugPrint('❌ [RideAssignedScreen] Ride Cancelled: $data');
        final reason = data['reason'] ?? 'Unknown reason';
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Ride Cancelled'),
            content: Text('The ride was cancelled.\nReason: $reason'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Go back
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });

    // Driver cancelled the ride (before start)
    _socketService.on('ride:cancelledByDriver', (data) {
      if (mounted) {
        debugPrint('❌ [RideAssignedScreen] Ride Cancelled By Driver: $data');
        // Reassigned path: backend keeps the ride alive (`reassigned: true`,
        // status back to `requested`) — rider stays in flow with a banner,
        // no refund panic.
        final nested = data['data'];
        final reassigned = data['reassigned'] == true ||
            (nested is Map && nested['reassigned'] == true);
        if (reassigned) {
          final count = data['reassignmentCount'] ??
              (nested is Map ? nested['reassignmentCount'] : null);
          setState(() {
            _rideStatus = 'searching';
            _driver = {};
            _driverLocation = null;
            _currentDriverId = null;
            _reassignMessage = data['message']?.toString() ??
                'Your driver cancelled — finding you another driver…';
            if (count is num) {
              debugPrint(
                '🔄 [RideAssignedScreen] Reassignment count: $count',
              );
            }
          });
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_reassignMessage!),
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        final reason = data['reason'] ?? 'Unknown reason';
        final refundStatus = data['refundStatus'] ?? 'processing';
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Ride Cancelled'),
            content: Text(
              'Driver cancelled the ride.\nReason: $reason\n\nFull refund is $refundStatus.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/home',
                    (route) => false,
                  );
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });

    // Ride ended early by driver (during ride)
    _socketService.on('ride:earlyCompleted', (data) {
      if (mounted) {
        debugPrint('🏁 [RideAssignedScreen] Ride Early Completed: $data');
        final double fare = (data['fare'] as num?)?.toDouble() ?? 0.0;
        final double originalFare =
            (data['originalFare'] as num?)?.toDouble() ?? widget.fare;
        final double actualDistance =
            (data['actualDistance'] as num?)?.toDouble() ?? 0.0;
        final reason = data['reason'] ?? 'Driver ended ride early';

        setState(() {
          _rideStatus = 'early_completed';
        });

        final timing =
            widget.paymentTiming ?? data['paymentTiming']?.toString();
        final bool isPayLater = timing == 'pay_later';

        if (isPayLater) {
          _handlePayLaterCompletion(
            fare: fare,
            distance: actualDistance,
            earlyCompleted: true,
            extraRideData: {
              'originalFare': originalFare,
              'actualDistance': actualDistance,
              'reason': reason,
              'paymentMethod': data['paymentMethod'],
            },
          );
          return;
        }

        // If we have deferred payment data (from payment:succeeded for scheduled airport rides),
        // use that with the early completion data to show the complete screen directly
        if (_deferredPaymentSuccessData != null && _isScheduled) {
          debugPrint(
            '✅ [RideAssignedScreen] Using deferred payment data for scheduled airport ride early completion',
          );
          final completeRideData = {
            ..._deferredPaymentSuccessData!,
            'fare': fare,
            'originalFare': originalFare,
            'actualDistance': actualDistance,
            'earlyCompleted': true,
            'isScheduled': true,
            'isAirportTransfer': data['isAirportTransfer'] ?? false,
            'reason': reason,
            'paymentMethod': data['paymentMethod'] ?? _deferredPaymentSuccessData!['paymentMethod'],
          };
          _deferredPaymentSuccessData = null;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => RideCompleteScreen(rideData: completeRideData),
            ),
          );
          return;
        }

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Ride Ended Early'),
            content: Text(
              'Your ride was ended early.\n\n'
              'Original fare: £${originalFare.toStringAsFixed(2)}\n'
              'Adjusted fare: £${fare.toStringAsFixed(2)}\n'
              'Distance traveled: ${actualDistance.toStringAsFixed(1)} mi\n\n'
              'Reason: $reason',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RideCompleteScreen(
                        rideData: {
                          'bookingId': widget.rideId,
                          'driver': _driver,
                          'fare': fare,
                          'originalFare': originalFare,
                          'actualDistance': actualDistance,
                          'earlyCompleted': true,
                          'isScheduled': _isScheduled || widget.isScheduled,
                          'isAirportTransfer': data['isAirportTransfer'] ?? false,
                          'paymentMethod': data['paymentMethod'],
                          'paymentStatus': 'pending',
                        },
                      ),
                    ),
                  );
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });

    _socketService.on('ride:expired', (data) {
      if (mounted) {
        debugPrint('⚠️ [RideAssignedScreen] Ride Expired: $data');
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Ride Expired'),
            content: const Text(
              'Your ride request has expired. Please try again.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(
                    context,
                  ); // Go back to previous screen (likely home)
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });

    _socketService.on('ride:longRunning', (data) {
      if (mounted) {
        debugPrint('⏳ [RideAssignedScreen] Ride Long Running: $data');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your ride is taking longer than expected...'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });
  } finally {
    _setupInProgress = false;
  }
}

  // Payment method selected by the passenger (`paymentMethod` + status).
  // Updates the assigned screen live so trip start reflects the chosen
  // method without a restart or a stale "select payment" prompt.
  void _setupPaymentSelectedListener() {
    _socketService.onPaymentSelected((data) {
      if (!mounted || !context.mounted) return;
      debugPrint('💳 [RideAssignedScreen] Payment selected: $data');
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final eventRideId =
          map['rideId']?.toString() ?? map['bookingId']?.toString() ?? map['_id']?.toString();
      if (eventRideId != null && eventRideId != widget.rideId) return;
      final method = map['paymentMethod']?.toString() ?? '';
      setState(() {
        _isPaymentMethodSelected = true;
        if (method.isNotEmpty) _selectedPaymentMethodDisplay = method;
      });
    });
  }

  void _updateMarkers() {
    final List<MapMarker> newMarkers = [];

    // Pickup Marker (User location) - Green
    newMarkers.add(
      MapMarker(
        id: 'pickup',
        lat: _pickupLocation.latitude,
        lng: _pickupLocation.longitude,
        title: 'Pickup',
        markerColor: Colors.green,
      ),
    );

    // Dropoff Marker - Red (show when driver arrived or ride in progress)
    if (_rideStatus == 'driver_arrived' || _rideStatus == 'in_progress') {
      newMarkers.add(
        MapMarker(
          id: 'dropoff',
          lat: _dropoffLocation.latitude,
          lng: _dropoffLocation.longitude,
          title: 'Dropoff',
          markerColor: Colors.red,
        ),
      );
    }

    // Driver/Car Marker - Different colors based on status
    // - driver_assigned: Blue (car moving toward pickup)
    // - driver_arrived: Cyan (car stationary at pickup)
    // - in_progress: Purple (car moving toward destination)
    if (_driverLocation != null && _rideStatus != 'searching') {
      Color driverMarkerColor;
      String driverTitle = _driver['name'] ?? 'Driver';

      switch (_rideStatus) {
        case 'accepted':
          driverMarkerColor = Colors.blue;
          driverTitle = '${_driver['name'] ?? 'Driver'} (Coming to you)';
          break;
        case 'driver_arrived':
          driverMarkerColor = Colors.cyan;
          driverTitle = '${_driver['name'] ?? 'Driver'} (Arrived)';
          break;
        case 'in_progress':
          driverMarkerColor = Colors.purple;
          driverTitle = '${_driver['name'] ?? 'Driver'} (In transit)';
          break;
        default:
          driverMarkerColor = Colors.blue;
      }

      newMarkers.add(
        MapMarker(
          id: 'driver',
          lat: _driverLocation!.latitude,
          lng: _driverLocation!.longitude,
          title: driverTitle,
          markerColor: driverMarkerColor,
        ),
      );
    }

    // Don't call setState here - let the caller handle it
    _markers = newMarkers;
  }

  /// Fetch navigation route based on current ride status
  /// - driver_assigned: Fetch route from driver to pickup (car moving toward user)
  /// - driver_arrived: No route needed (car is stationary at pickup)
  /// - in_progress: Fetch route from current position to dropoff (car moving to destination)
  Future<void> _fetchNavigationRoute() async {
    if (_driverLocation == null) return;

    latlong2.LatLng origin = _driverLocation!;
    latlong2.LatLng destination;

    if (_rideStatus == 'accepted') {
      // Driver navigating to pickup
      destination = _pickupLocation;
    } else if (_rideStatus == 'in_progress') {
      // Driver navigating to dropoff
      destination = _dropoffLocation;
    } else if (_rideStatus == 'driver_arrived') {
      // Car is stationary - no navigation route needed
      setState(() {
        _polylines = [];
      });
      return;
    } else {
      return;
    }

    await _navigationService.fetchRoute(
      originLat: origin.latitude,
      originLng: origin.longitude,
      destLat: destination.latitude,
      destLng: destination.longitude,
    );
  }

  /// Update navigation route in real-time
  /// Called when driver location changes to update the polyline
  Future<void> _updateNavigationRoute() async {
    if (_driverLocation == null) return;

    latlong2.LatLng destination;

    if (_rideStatus == 'accepted') {
      destination = _pickupLocation;
    } else if (_rideStatus == 'in_progress') {
      // For in_progress, the user said "using the polyline from pickup to dropoff"
      // However, to keep it "moving", we'll update the route from current driver location
      destination = _dropoffLocation;
    } else {
      // driver_arrived or other states - no route updates needed
      return;
    }

    await _navigationService.updateRoute(
      currentLat: _driverLocation!.latitude,
      currentLng: _driverLocation!.longitude,
      destLat: destination.latitude,
      destLng: destination.longitude,
    );
  }

  /// Update polylines with navigation route
  void _updatePolylines() {
    final List<MapPolyline> newPolylines = [];

    if (_navigationState != null && _navigationState!.polyline.isNotEmpty) {
      newPolylines.add(
        MapPolyline(
          id: 'navigation_route',
          points: _navigationState!.polyline,
          color: AppTheme.primaryColor,
          width: 5,
        ),
      );
    }

    setState(() {
      _polylines = newPolylines;
    });
  }

  /// Parse ETA duration text to total minutes.
  /// "5 mins" -> 5, "1 hour 11 mins" -> 71. The old first-number-only regex
  /// returned 1 for hour+ durations (number right in text, wrong in badge).
  int _parseEtaMinutes(String duration) {
    final numbers = RegExp(
      r'(\d+)',
    ).allMatches(duration).map((m) => int.parse(m.group(1)!)).toList();
    if (numbers.isEmpty) return 0;
    final lower = duration.toLowerCase();
    if (lower.contains('hour') || lower.contains('hr')) {
      final mins = numbers.length > 1 ? numbers[1] : 0;
      return numbers[0] * 60 + mins;
    }
    return numbers[0];
  }

  /// Calculate ETA using Distance Matrix API with real traffic data
  /// This is a FALLBACK method - normally ETA comes from driver:locationChanged event
  /// Called periodically to ensure ETA is available even if socket misses updates
  Future<void> _calculateETA() async {
    if (_driverLocation == null) return;

    // Only calculate ETA when driver is heading to pickup
    if (_rideStatus != 'accepted') return;

    // Snapshot origin + sequence: a slow response must not overwrite
    // fresher socket ETA that arrived while this request was in flight.
    final requestOrigin = _driverLocation!;
    final requestSeq = ++_etaRequestSeq;

    try {
      debugPrint(
        '🕐 [RideAssignedScreen] Calculating ETA with traffic data...',
      );

      // Use Distance Matrix API to get real-time travel time with traffic
      final result = await _placesService.getDistanceAndFare(
        originLat: _driverLocation!.latitude,
        originLng: _driverLocation!.longitude,
        destLat: _pickupLocation.latitude,
        destLng: _pickupLocation.longitude,
        categorySlug: 'car_4_seater', // Default category for ETA calculation
      );

      if (result != null && mounted) {
        // Drop superseded responses (a newer fallback request started).
        if (requestSeq != _etaRequestSeq) return;
        // Status may have changed mid-flight (arrived/started) - don't touch ETA.
        if (_rideStatus != 'accepted') return;
        // Socket is realtime: if it delivered ETA recently, this slower
        // fallback value is older info - don't overwrite fresher display.
        final socketEtaAt = _lastSocketEtaAt;
        if (socketEtaAt != null &&
            DateTime.now().difference(socketEtaAt).inSeconds < 45) {
          debugPrint(
            '🕐 [RideAssignedScreen] Skipping stale fallback ETA (socket is fresh)',
          );
          return;
        }
        // Origin moved on while request was in flight - response is stale.
        final movedMeters = const latlong2.Distance().as(
          latlong2.LengthUnit.Meter,
          requestOrigin,
          _driverLocation ?? requestOrigin,
        );
        if (movedMeters > 300) {
          debugPrint(
            '🕐 [RideAssignedScreen] Skipping stale fallback ETA (driver moved ${movedMeters.toStringAsFixed(0)}m during request)',
          );
          return;
        }

        final durationSeconds = result['duration_seconds'] as int? ?? 0;
        final durationText =
            result['duration_text'] as String? ?? 'Calculating...';

        setState(() {
          _etaMinutes = (durationSeconds / 60).ceil();
          _etaText = durationText;
        });

        debugPrint(
          '🕐 [RideAssignedScreen] ETA updated: $_etaText ($_etaMinutes mins)',
        );
      }
    } catch (e) {
      debugPrint('⚠️ [RideAssignedScreen] Error calculating ETA: $e');
    }
  }

  /// Start periodic ETA updates as a fallback
  /// NOTE: ETA is primarily provided by driver:locationChanged socket event
  /// This fallback ensures we have ETA even if socket updates are missed
  void _startETAUpdates() {
    // Cancel any existing timer
    _etaTimer?.cancel();

    // Calculate immediately as initial fallback
    _calculateETA();

    // Fallback update every 30 seconds (socket provides real-time updates)
    // Increased from 20s since socket now provides ETA with each location update
    _etaTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_rideStatus == 'accepted' && _driverLocation != null) {
        _calculateETA();
      } else {
        // Stop timer if ride status changes
        timer.cancel();
      }
    });

    debugPrint(
      '⏱️ [RideAssignedScreen] Started fallback ETA updates (every 30s)',
    );
  }

  /// Stop ETA updates
  void _stopETAUpdates() {
    _etaTimer?.cancel();
    _etaTimer = null;
    debugPrint('⏱️ [RideAssignedScreen] Stopped ETA updates');
  }

  /// Show cancellation confirmation dialog
  void _showCancellationConfirmation() {
    // Determine if ride has been accepted (driver assigned)
    final bool hasDriverAssigned =
        _rideStatus == 'accepted' || _rideStatus == 'driver_arrived';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Ride?'),
        content: Text(
          hasDriverAssigned
              ? 'Are you sure you want to cancel this ride?\n\n'
                    'Note: A cancellation fee may apply if cancelled after the grace period (2 minutes after driver acceptance).'
              : 'Are you sure you want to cancel your ride request?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No, Keep Ride'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelRide();
            },
            child: Text('Yes, Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// Cancel the ride using the appropriate API endpoint
  Future<void> _cancelRide() async {
    if (_isCancelling) return;

    setState(() => _isCancelling = true);

    try {
      // Use the new cancelRideByUser endpoint for proper cancellation handling
      final response = await _apiService.cancelRideByUser(widget.rideId);

      if (!mounted) return;

      if (response['success'] == true) {
        final data = response['data'];
        final cancellationFee = data?['cancellationFee'] ?? 0.0;
        final refundStatus = data?['refundStatus'] ?? 'refunded';

        if (cancellationFee > 0) {
          // Show cancellation fee dialog
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Cancellation Fee'),
              content: Text(
                'Your ride has been cancelled.\n\n'
                'A cancellation fee of £${cancellationFee.toStringAsFixed(2)} was charged.\n'
                'Refund status: $refundStatus',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/home',
                      (route) => false,
                    );
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          // Full refund - show success message and navigate home
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ride cancelled.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        }
      } else {
        // Handle error cases
        final message = response['message'] ?? 'Failed to cancel ride';
        final error = response['error'];

        if (error == 'Bad Request' && message.contains('started')) {
          // Ride already started
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Cannot Cancel'),
              content: const Text(
                'Ride has already started. Please ask driver to end ride early if needed.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint('🔴 [RideAssignedScreen] Cancel error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel ride: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCancelling = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Clean up ETA timer
    _stopETAUpdates();

    // Clean up marker interpolation
    _interpolationSubscription?.cancel();
    _markerInterpolation?.dispose();

    // Clean up connection listener
    _connectionSubscription?.cancel();

    // Stop tracking and leave driver room if we were tracking one
    if (_currentDriverId != null) {
      _socketService.stopTrackingDriver(_currentDriverId!);
      _socketService.leaveDriverRoom(_currentDriverId!);
    }

    // Clean up socket listeners
    _socketService.off('driver:locationChanged');
    _socketService.off('ride:started');
    _socketService.off('ride:completed');
    _socketService.off('ride:driverArrived');
    _socketService.off('ride:cancelledByDriver');
    _socketService.off('ride:earlyCompleted');
    _socketService.off('payment:succeeded');
    _socketService.off('payment:authorized');
    _socketService.off('payment:failed');
    _socketService.off('ride:longRunning');
    _socketService.off('ride:promoApplied');
    _socketService.offDriverReassigning();
    _socketService.offPaymentSelected();

    // Clean up navigation
    _navigationService.dispose();

    debugPrint('🔴 [RideAssignedScreen] Disposed');
    super.dispose();
  }

  void _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      debugPrint('Could not launch dialer for $phoneNumber');
    }
  }

  void _launchWhatsApp(String phoneNumber) async {
    // Clean phone number: remove non-digits
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'\D'), '');
    final whatsappUrl = Uri.parse("https://wa.me/$cleanNumber");

    if (await canLaunchUrl(whatsappUrl)) {
      await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Could not launch WhatsApp for $phoneNumber');
    }
  }

  void _handleDriverArrival([Map<String, dynamic>? socketData]) {
    if (!mounted || !context.mounted) return;

    if (socketData?['isScheduled'] == true) {
      setState(() { _isScheduled = true; });
    }

    AudioService.instance.playNotification();

    setState(() {
      _rideStatus = 'driver_arrived';
      _driverLocation = _pickupLocation;
      _polylines = [];
      _updateMarkers();
    });

    _showDriverArrivedDialog();

    if (_currentFare == null) {
      _apiService.getRideDetails(widget.rideId).then((response) {
        if (mounted && response['success'] == true && response['data'] != null) {
          final rideData = response['data'];
          final double? fare = rideData['fare'] != null
              ? (rideData['fare'] as num).toDouble()
              : null;
          setState(() {
            _isPromoRide = rideData['isPromoRide'] == true;
            _promoFullyCovered = rideData['promoFullyCovered'] == true ||
                (_isPromoRide && fare != null && fare == 0.0);
            if (rideData['originalFare'] != null) {
              _promoOriginalFare = (rideData['originalFare'] as num).toDouble();
            }
            if (fare != null) _currentFare = fare;
            if (rideData['isScheduled'] == true) _isScheduled = true;
          });
        }
      }).catchError((e) {
        debugPrint('⚠️ [RideAssignedScreen] Pre-dialog ride sync failed: $e');
      });
    } else {
      debugPrint(
        '🚖 [RideAssignedScreen] Fare already known ($_currentFare), skipping API call.',
      );
    }
  }

  /// Show visual message dialog when driver arrives
  void _showDriverArrivedDialog() {
    final driverName = _driver['name'] ?? 'Your driver';
    final vehicleModel = _driver['vehicle']?['model'] ?? 'Vehicle';
    final vehicleNumber =
        _driver['vehicle']?['number'] ??
        _driver['vehicle']?['vehicleNumber'] ??
        '';
    final vehicleColor = _driver['vehicle']?['color'] ?? '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.green.shade50, Colors.white],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.white,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              const Text(
                'Driver Has Arrived!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Subtitle
              Text(
                '$driverName is waiting at your pickup location',
                style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Driver Info Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: AppTheme.primaryColor,
                          backgroundImage: _driver['profilePicture'] != null
                              ? NetworkImage(_driver['profilePicture'])
                              : null,
                          child: _driver['profilePicture'] == null
                              ? Text(
                                  (_driver['name'] ?? 'D')[0],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                driverName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.star,
                                    color: Colors.amber,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_driver['rating'] ?? '-'}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildInfoItem(Icons.directions_car, vehicleModel),
                        if (vehicleColor.isNotEmpty)
                          _buildInfoItem(Icons.palette, vehicleColor),
                        if (vehicleNumber.isNotEmpty)
                          _buildInfoItem(Icons.tag, vehicleNumber),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Location indicator
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on,
                      color: Colors.green.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Check the map to see driver location',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Continue button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showPaymentSelectionModal();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: Text(
                    _promoFullyCovered ? 'Continue' : 'Continue to Payment',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_rideStatus == 'completed') {
      final Map<String, dynamic> completedData = {
        'bookingId': widget.rideId,
        'driver': _driver,
        'fare': _completedFare ?? widget.fare,
        'isScheduled': _isScheduled || widget.isScheduled,
        if (_isPromoRide) 'isPromoRide': true,
        if (_isPromoRide && _promoOriginalFare > 0)
          'originalFare': _promoOriginalFare,
        if (_completedRideData != null) ..._completedRideData!,
      };
      return RideCompleteScreen(rideData: completedData);
    }

    return Scaffold(
      body: Stack(
        children: [
          PlatformMap(
            initialLat: _userLocation.latitude,
            initialLng: _userLocation.longitude,
            markers: _markers,
            polylines: _polylines,
            interactive: true,
          ),

          // Status Panel
          Positioned(bottom: 0, left: 0, right: 0, child: _buildStatusPanel()),

          // Socket disconnect → visible "reconnecting" pill (queued emits
          // flush via emitReliable on reconnect), never a silent freeze.
          const ConnectionStatusBanner(),
        ],
      ),
    );
  }

  Future<void> _handlePayLaterCompletion({
    required double fare,
    double? distance,
    Map<String, dynamic>? rideData,
    bool earlyCompleted = false,
    Map<String, dynamic>? extraRideData,
  }) async {
    if (!mounted) return;

    final method =
        rideData?['paymentMethod'] ?? extraRideData?['paymentMethod'];

    // Payment interactions are now handled at "Driver Arrived" stage (Step 7).
    // So at completion, we just show the summary.

    final Map<String, dynamic> finalRideData = {
      'bookingId': widget.rideId,
      'driver': _driver,
      'fare': fare,
      if (distance != null) 'distance': distance,
      if (rideData != null) ...rideData,
      if (extraRideData != null) ...extraRideData,
      if (earlyCompleted) 'earlyCompleted': true,
      'paymentMethod': method,
      // If cash, it's pending collection. If card, it's considered processed/authorized.
      'paymentStatus': method == 'cash' ? 'pending' : 'completed',
    };

    _showPaymentSuccessScreen(finalRideData);
  }

  void _showPaymentSuccessScreen(Map<String, dynamic> rideData) {
    if (!mounted) return;

    // Status-sequence navigation guard: completed/early-completed events can
    // arrive twice (socket + FCM + pay-later path) — push receipt exactly once.
    if (_didNavigateToReceipt) return;
    _didNavigateToReceipt = true;

    _isAwaitingPaymentConfirmation = false;

    // Correctly identify fare and originalFare from data (supports early completion)
    final double fareValue = (rideData['fare'] as num?)?.toDouble() ??
        (rideData['amount'] as num?)?.toDouble() ??
        widget.fare;
    final double? originalFareValue = (rideData['originalFare'] as num?)?.toDouble();

    final Map<String, dynamic> finalRideData = {
      'bookingId': widget.rideId,
      'driver': _driver,
      'fare': fareValue,
      if (originalFareValue != null) 'originalFare': originalFareValue,
      'isScheduled': _isScheduled || widget.isScheduled,
      ...rideData,
      'paymentMethod': rideData['paymentMethod'] ?? 'payment_link',
    };

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RideCompleteScreen(rideData: finalRideData),
      ),
    );
  }

  void _showPaymentRequiredDialog({required double fare, double? distance}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Payment Required'),
        content: const Text('Please complete payment for your ride.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _handlePayLaterCompletion(fare: fare, distance: distance);
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPanel() {
    // Debug logging removed to prevent log spam

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_rideStatus == 'searching') ...[
            if (_reassignMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.autorenew,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _reassignMessage!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text(
              'Finding Nearby Drivers...',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Searching for drivers near you...'),
            const SizedBox(height: 24),
            _buildLocationRow(
              Icons.my_location,
              'Pickup',
              _pickupAddress.isNotEmpty
                  ? _pickupAddress
                  : (widget.pickup?['address'] ?? 'Current Location'),
            ),
            const SizedBox(height: 16),
            _buildLocationRow(
              Icons.location_on,
              'Dropoff',
              _dropoffAddress.isNotEmpty
                  ? _dropoffAddress
                  : (widget.dropoff?['address'] ?? 'Destination'),
            ),
            const SizedBox(height: 24),
            // Promo banner — shown once ride:promoApplied is received
            if (_isPromoRide)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF22C55E).withOpacity(0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Text('🎁', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Free Ride Applied!',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                          Text(
                            _promoOriginalFare > 0
                                ? 'Original fare £${_promoOriginalFare.toStringAsFixed(2)} — discounted by £4.45'
                                : 'Up to £4.45 discount applied',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      fontFamily: 'Outfit', // Match AppTheme if possible
                    ),
                    children: [
                      if (_isPromoRide && _promoOriginalFare > 0) ...[
                        TextSpan(
                          text: '£${_promoOriginalFare.toStringAsFixed(2)}',
                          style: const TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: Colors.grey,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        const TextSpan(text: ' '),
                        TextSpan(
                          text:
                              '£${(_currentFare ?? widget.fare).toStringAsFixed(2)}',
                          style: const TextStyle(color: Color(0xFF16A34A)),
                        ),
                        const TextSpan(
                          text: ' (Estimated)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ] else
                        TextSpan(
                          text:
                              'Estimated Fare: £${widget.fare.toStringAsFixed(2)}',
                        ),
                    ],
                  ),
                ),
                // Text('Distance: 5.2 mi'), // Mock distance for now
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showCancellationConfirmation(),
                icon: const Icon(Icons.close),
                label: const Text('Cancel Request'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ] else ...[
            // Driver Assigned / In Progress UI

            // Status header
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _rideStatus == 'driver_arrived'
                    ? Colors.green.withValues(alpha: 0.1)
                    : _rideStatus == 'in_progress'
                    ? Colors.blue.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _rideStatus == 'driver_arrived'
                        ? Icons.check_circle
                        : _rideStatus == 'in_progress'
                        ? Icons.directions_car
                        : Icons.navigation,
                    color: _rideStatus == 'driver_arrived'
                        ? Colors.green
                        : _rideStatus == 'in_progress'
                        ? Colors.blue
                        : Colors.orange,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _rideStatus == 'driver_arrived'
                              ? 'Driver has arrived!'
                              : _rideStatus == 'in_progress'
                              ? 'Trip in progress'
                              : 'Driver is on the way',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: _rideStatus == 'driver_arrived'
                                ? Colors.green
                                : _rideStatus == 'in_progress'
                                ? Colors.blue
                                : Colors.orange,
                          ),
                        ),
                        // Show ETA with real traffic data when driver is coming
                        if (_rideStatus == 'accepted') ...[
                          const SizedBox(height: 4),
                          Text(
                            _etaMinutes > 0
                                ? '$_etaMinutes mins away · $_etaText'
                                : _navigationState != null
                                ? '${_navigationState!.distanceText} away · ${_navigationState!.etaText}'
                                : 'Calculating ETA...',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Payment Method Badge
            if (_isPaymentMethodSelected &&
                _selectedPaymentMethodDisplay.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _selectedPaymentMethodDisplay.toLowerCase().contains(
                            'link',
                          )
                          ? Icons.link
                          : _selectedPaymentMethodDisplay
                                .toLowerCase()
                                .contains('card')
                          ? Icons.credit_card
                          : _selectedPaymentMethodDisplay
                                .toLowerCase()
                                .contains('free')
                          ? Icons.card_giftcard
                          : Icons.money,
                      size: 14,
                      color:
                          _selectedPaymentMethodDisplay.toLowerCase().contains(
                            'free',
                          )
                          ? const Color(0xFF16A34A)
                          : Colors.grey[700],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Payment: $_selectedPaymentMethodDisplay',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color:
                            _selectedPaymentMethodDisplay
                                .toLowerCase()
                                .contains('free')
                            ? const Color(0xFF16A34A)
                            : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),

            // No-code boarding — no OTP in the new flow. Once payment is
            // selected, the rider just boards; driver starts without a code.
            if ((_rideStatus == 'accepted' ||
                    _rideStatus == 'driver_arrived') &&
                _isPaymentMethodSelected)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.successColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: AppTheme.successColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _rideStatus == 'driver_arrived'
                              ? 'DRIVER ARRIVED — HOP IN'
                              : 'DRIVER CONFIRMED — NO CODE NEEDED',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'No code needed — your driver starts the trip when you board.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Theme.of(context).primaryColor,
                  backgroundImage: _driver['profilePicture'] != null
                      ? NetworkImage(_driver['profilePicture'])
                      : null,
                  child: _driver['profilePicture'] == null
                      ? Text(
                          (_driver['name'] ?? 'D')[0],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _driver['name'] ?? 'Driver',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text('${_driver['rating'] ?? 5.0}'),
                          const SizedBox(width: 8),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _driver['vehicle']?['model'] ?? 'Car',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.phone,
                      color: Colors.green,
                      size: 20,
                    ),
                  ),
                  onPressed: () {
                    final phone = _driver['phone']?.toString();
                    if (phone != null && phone.isNotEmpty) {
                      _makePhoneCall(phone);
                    }
                  },
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.message,
                      color: Theme.of(context).primaryColor,
                      size: 20,
                    ),
                  ),
                  onPressed: () {
                    final phone = _driver['phone']?.toString();
                    if (phone != null && phone.isNotEmpty) {
                      _launchWhatsApp(phone);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoColumn(
                  'Vehicle',
                  _driver['vehicle']?['model'] ?? 'Car',
                ),
                _buildInfoColumn(
                  'Plate',
                  _driver['vehicle']?['number'] ?? '---',
                ),
                _buildInfoColumn(
                  'Color',
                  _driver['vehicle']?['color'] ?? '---',
                ),
              ],
            ),

            // Cancel button - only show before ride starts (accepted or driver_arrived)
            if (_rideStatus == 'accepted' ||
                _rideStatus == 'driver_arrived') ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _showCancellationConfirmation(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.close, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Cancel Ride'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, String label, String address) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              Text(
                address,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ],
    );
  }

  void _closePaymentLoading() {
    if (_isPaymentLoadingShowing && mounted) {
      _isPaymentLoadingShowing = false;
      try {
        Navigator.of(context, rootNavigator: true).pop();
        debugPrint('💸 [Payment] ✅ Closed loading dialog');
      } catch (e) {
        debugPrint('⚠️ [Payment] Loading dialog pop failed: $e');
      }
    }
  }

  /// Map raw backend/exception text to a user-facing explanation.
  String _friendlyPaymentError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('no auth token') ||
        lower.contains('unauthorized') ||
        lower.contains('401') ||
        lower.contains('token')) {
      return 'Your session expired. Please log out and log back in, then try again.';
    }
    if (lower.contains('already') && lower.contains('payment')) {
      return 'The backend says a payment method is already set for this ride. Pull-to-refresh or restart the app to sync, then continue.';
    }
    if (lower.contains('invalid payment method')) {
      return 'The app sent a payment type the server does not accept. This is an app/backend version mismatch — please update the app.';
    }
    if (lower.contains('not found') ||
        lower.contains('no ride') ||
        lower.contains('cancelled') ||
        lower.contains('expired')) {
      return 'This ride is no longer active on the server (expired or cancelled). Please book again.';
    }
    if (lower.contains('sockethost') ||
        lower.contains('socketexception') ||
        lower.contains('failed host') ||
        lower.contains('connection') ||
        lower.contains('network') ||
        lower.contains('timeout')) {
      return 'Network problem — the request never reached the server. Check your connection and try again.';
    }
    if (lower.contains('no payment link')) {
      return 'The server did not return a payment link. The online-payment provider may be down — try Cash or retry in a moment.';
    }
    return 'The server rejected the payment request. See the server message below.';
  }

  /// Backendfailure dialog: explains WHAT failed and WHY instead of silently
  /// re-showing the same bottom sheet (the old infinite-loop behaviour).
  void _showPaymentErrorDialog({
    required String method,
    required String serverMessage,
  }) {
    if (!mounted) return;
    _paymentRetryCount++;
    final friendly = _friendlyPaymentError(serverMessage);
    final limitReached = _paymentRetryCount >= _maxPaymentRetries;
    debugPrint('❌ [Payment] Showing error dialog (retry $_paymentRetryCount): $serverMessage');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Payment failed'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                friendly,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Method: $method',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Server: $serverMessage',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ride: ${widget.rideId}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (limitReached) ...[
                const SizedBox(height: 12),
                const Text(
                  'Tried several times without success. Please contact support with the ride ID above.',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext); // Close dialog
              _showPaymentSelectionModal(); // Let user pick again
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text(
              'Try Again',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showPaymentSelectionModal() {
    if (!mounted) return;
    if (_isPaymentSheetOpen) {
      debugPrint('⚠️ [Payment] Sheet already open — skipping duplicate show');
      return;
    }
    // Skip the modal entirely if the ride is fully covered by a promo.
    // Also infer it at call-time: if it's a promo ride and fare is 0, treat as fully covered.
    final bool effectivelyFree =
        _promoFullyCovered ||
        (_isPromoRide && _currentFare != null && _currentFare == 0.0);
    if (effectivelyFree) {
      if (!_promoFullyCovered) {
        setState(() => _promoFullyCovered = true);
      }
      _handlePaymentSelection('cash', fromAutoSelect: true);
      return;
    }
    _isPaymentSheetOpen = true;
    _paymentSheetError = null;
    final fareHint = _currentFare ?? widget.fare;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => WillPopScope(
        onWillPop: () async => false,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: 24 + MediaQuery.of(sheetContext).padding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Select Payment Method',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (_isPromoRide) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF22C55E).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text('🎁 ', style: TextStyle(fontSize: 14)),
                        Text(
                          '£4.45 discount applied!',
                          style: TextStyle(
                            color: Color(0xFF16A34A),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (_paymentSheetError != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _paymentSheetError!,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Cash option — close sheet with its own context first,
                // then run selection (avoids popping the wrong route).
                _buildPaymentOption(
                  icon: Icons.money,
                  title: 'Cash',
                  subtitle:
                      'Pay £${fareHint.toStringAsFixed(2)} directly to driver · no fee',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _handlePaymentSelection('cash', fromAutoSelect: true);
                  },
                ),
                const SizedBox(height: 16),
                // Card/Stripe option — clientSecret → Stripe sheet.
                _buildPaymentOption(
                  icon: Icons.credit_card,
                  title: 'Card',
                  subtitle:
                      'Pay £${fareHint.toStringAsFixed(2)} now via Stripe · no fee',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _handlePaymentSelection(
                      'stripe',
                      fromAutoSelect: true,
                    );
                  },
                ),
                const SizedBox(height: 16),
                // Payment Link option - available on both iOS and Android
                _buildPaymentOption(
                  icon: Icons.link,
                  title: 'Payment Link',
                  subtitle:
                      'Pay £${fareHint.toStringAsFixed(2)} via online link · no fee',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _handlePaymentSelection(
                      'payment_link',
                      fromAutoSelect: true,
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      _isPaymentSheetOpen = false;
    });
  }

  void _reopenPaymentSelectionModal() {
    if (!mounted) return;
    scheduleMicrotask(() {
      if (!mounted) return;
      _showPaymentSelectionModal();
    });
  }

  Widget _buildPaymentOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppTheme.primaryColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePaymentSelection(
    String method, {
    bool fromAutoSelect = false,
  }) async {
    // In-flight guard: ignore double-taps while a selection is running.
    if (_isSelectingPayment) {
      debugPrint('⚠️ [Payment] Selection already in flight — ignoring $method');
      return;
    }
    _isSelectingPayment = true;
    try {
      await _runPaymentSelection(method, fromAutoSelect: fromAutoSelect);
    } finally {
      _isSelectingPayment = false;
    }
  }

  Future<void> _runPaymentSelection(
    String method, {
    bool fromAutoSelect = false,
  }) async {
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint(
      '💸 [Payment] ============ PAYMENT SELECTION START ============',
    );
    debugPrint('💸 [Payment] Method selected: $method');
    debugPrint('💸 [Payment] Ride ID: ${widget.rideId}');

    // NOTE: the sheet is already closed by the onTap handler using the
    // sheet's own context. The legacy `if (!fromAutoSelect) pop` path is
    // kept only for callers that show the sheet differently.
    if (!fromAutoSelect) {
      if (_isPaymentSheetOpen && Navigator.canPop(context)) {
        Navigator.pop(context); // Close selection modal
        debugPrint('💸 [Payment] ✅ Closed payment modal');
      }
    }

    // Show loading (tracked so only the dialog is ever popped)
    if (mounted) {
      _isPaymentLoadingShowing = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      debugPrint('💸 [Payment] ✅ Showing loading dialog');
    }

    try {
      debugPrint('💸 [Payment] 📤 Sending request to backend...');
      final response = await _apiService.selectPaymentMethod(
        widget.rideId,
        method,
      );

      debugPrint('💸 [Payment] 📥 Received response from backend');
      debugPrint('💸 [Payment] Response: $response');

      // Keep loading dialog open while payment sheet initializes
      // Will be closed after payment completes or fails

      if (response['success'] == true) {
        debugPrint('💸 [Payment] ✅ Response success = true');
        final data = response['data'];
        debugPrint('💸 [Payment] Data: $data');

        // Handle nested ride structure (data.ride) or flat structure (data)
        final rideData = data['ride'] ?? data;
        debugPrint('💸 [Payment] Ride data: $rideData');

        // NEW: Handle promo fields
        final bool isPromoRide = rideData['isPromoRide'] == true;
        final bool promoFullyCovered = rideData['promoFullyCovered'] == true;
        final double? originalFare = rideData['originalFare'] != null
            ? (rideData['originalFare'] as num).toDouble()
            : null;
        final double? newFare = rideData['amount'] != null
            ? (rideData['amount'] as num).toDouble() /
                  100.0 // assumed amount is in pence/cents
            : null;

        // Infer fully-covered from amount==0 when backend omits promoFullyCovered
        final bool effectiveFullyCovered =
            promoFullyCovered ||
            (isPromoRide &&
                rideData['amount'] != null &&
                (rideData['amount'] as num) == 0);

        if (isPromoRide || effectiveFullyCovered) {
          setState(() {
            _isPromoRide = true;
            _promoFullyCovered = effectiveFullyCovered;
            if (originalFare != null) _promoOriginalFare = originalFare;
            if (newFare != null) _currentFare = newFare;
          });
        }

        if (effectiveFullyCovered) {
          // Skip payment entirely as it's a free ride
          _closePaymentLoading();
          _paymentRetryCount = 0;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎁 Your ride is free! No payment needed.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );

          setState(() {
            _isPaymentMethodSelected = true;
            _selectedPaymentMethodDisplay = 'Free Ride 🎁';
          });
          return;
        }

        if (isPromoRide) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎁 £4.45 discount applied!'),
              backgroundColor: Colors.green,
            ),
          );
        }

        final paymentMethod = rideData['paymentMethod'];
        debugPrint('💸 [Payment] Method from response: $paymentMethod');

        if (paymentMethod == 'stripe') {
          final clientSecret = rideData['clientSecret'];
          debugPrint(
            '💳 [Stripe] Client secret present: ${clientSecret != null}',
          );

          if (clientSecret != null) {
            try {
              // Default fallback: Use Stripe Payment Sheet
              await StripeService.processPayment(clientSecret);

              // Close loading dialog after payment sheet completes
              _closePaymentLoading();
              _paymentRetryCount = 0;

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Payment Successful! You can now board.'),
                  backgroundColor: Colors.green,
                ),
              );
              setState(() {
                _isPaymentMethodSelected = true;
                _selectedPaymentMethodDisplay = Platform.isAndroid
                    ? 'Paid Online'
                    : 'Card';
              });
            } catch (e) {
              debugPrint('❌ [Stripe] Payment failed: $e');

              // Close loading dialog on error
              _closePaymentLoading();

              if (!mounted) return;
              // Stripe failure → sheet reopens with error, ride stays intact.
              setState(() {
                _paymentSheetError =
                    'Card payment failed: ${StripeService.getErrorMessage(e)}';
              });
              _showPaymentErrorDialog(
                method: method,
                serverMessage:
                    'Online payment failed: ${StripeService.getErrorMessage(e)}',
              );
              return;
            }
          } else {
            // Close loading dialog if no client secret — backend issue, explain it.
            _closePaymentLoading();

            if (!mounted) return;
            _showPaymentErrorDialog(
              method: method,
              serverMessage:
                  'Payment setup failed: server returned no client secret. The payment provider may be misconfigured.',
            );
            return;
          }
        } else if (paymentMethod == 'payment_link') {
          final paymentUrl = rideData['paymentUrl'];
          debugPrint('🔗 [Payment Link] URL present: ${paymentUrl != null}');
          if (paymentUrl != null) {
            debugPrint('🔗 [Payment Link] URL: $paymentUrl');
          }

          // Close loading dialog before opening browser / WebView
          _closePaymentLoading();
          if (paymentUrl != null) {
            // ── In-app WebView (same as prebooking) ──────────────────
            debugPrint('✅ [Payment Link] Opening in-app WebView');

            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PaymentWebViewScreen(
                  paymentUrl: paymentUrl,
                  rideId: widget.rideId,
                ),
              ),
            );

            if (result != null && result['success'] == true) {
              debugPrint('✅ [Payment Link] Payment completed successfully');
              _paymentRetryCount = 0;
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Payment successful! You can now board.'),
                  backgroundColor: Colors.green,
                ),
              );
              setState(() {
                _isPaymentMethodSelected = true;
                _selectedPaymentMethodDisplay = 'Payment Link';
              });
            } else {
              // User cancelled/closed WebView (NOT a backend failure):
              // let them pick again, no error dialog needed.
              debugPrint('❌ [Payment Link] Payment cancelled or failed');
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Payment was not completed. Please try again.',
                  ),
                  backgroundColor: Colors.orange,
                ),
              );
              _reopenPaymentSelectionModal();
            }
          } else {
            debugPrint('❌ [Payment Link] URL missing in response');
            if (!mounted) return;
            _showPaymentErrorDialog(
              method: method,
              serverMessage:
                  'No payment link provided by server. The online-payment provider may be down — try Cash.',
            );
          }
        } else {
          // Cash payment
          _closePaymentLoading();
          _paymentRetryCount = 0;

          debugPrint('💵 [Cash] Payment method selected');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cash payment selected. You can now board.'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _isPaymentMethodSelected = true;
            _selectedPaymentMethodDisplay = 'Cash';
          });
        }
      } else {
        debugPrint('❌ [Payment] Response success = false');
        debugPrint('💸 [Payment] Error message: ${response['message']}');

        // Backend rejected the request — explain it, don't loop the sheet.
        _closePaymentLoading();

        if (!mounted) return;
        final serverMessage = (response['message']?.toString() ??
            'Failed to select payment method');
        // Invalid-method 400 → inline error via RideErrorMapper, stay on
        // the sheet so the rider can pick another method (no dead-end).
        if (serverMessage.toLowerCase().contains('invalid payment method')) {
          final info = RideErrorMapper.map(
            serverMessage,
            response['errors'],
          );
          setState(() {
            _paymentSheetError = '${info.title}: ${info.copy}';
          });
          if (mounted) {
            ErrorDisplayHelper.showRideError(
              context,
              serverMessage,
              errors: response['errors'],
              onAction: _reopenPaymentSelectionModal,
            );
          }
          _reopenPaymentSelectionModal();
          return;
        }
        _showPaymentErrorDialog(
          method: method,
          serverMessage: serverMessage,
        );
      }
    } catch (e) {
      debugPrint('❌ [Payment] EXCEPTION CAUGHT: $e');
      debugPrint('💸 [Payment] Stack trace: $e');

      // Close loading dialog on exception
      _closePaymentLoading();

      if (!mounted) return;
      _showPaymentErrorDialog(method: method, serverMessage: 'Error: $e');
      debugPrint('═══════════════════════════════════════════════════════════');
    }
  }
}
