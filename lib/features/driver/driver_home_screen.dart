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
import '../../core/services/socket_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/navigation_service.dart';
import '../../core/widgets/connection_status_banner.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/audio_service.dart';

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
  LatLng _currentLocation = const LatLng(51.5085, -0.1260); // Fallback
  bool _isMapLoading = true;
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

  // Track if socket listeners are set up to re-register after reconnection
  bool _socketListenersSetup = false;

  // Store driverId to use in dispose without accessing context
  String? _driverId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDriver();
    _initLocation();
    _setupConnectionListener();
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

  void _initLocation() async {
    _fetchRideHistory(); // Added history fetch
    debugPrint("📍 _initLocation called in DriverHomeScreen");
    final position = await _locationService.getCurrentLocation();
    if (position != null && mounted) {
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _isMapLoading = false;
      });
      // Start updates if already online or needed
      if (_status == 'online') {
        _emitLocationUpdate(position.latitude, position.longitude);
      }
    } else {
      // Handle failure or timeout - maybe show fallback or retry?
      // For now, just stop loading to show fallback
      if (mounted) setState(() => _isMapLoading = false);
    }
  }

  Future<void> _initDriver() async {
    await _ensureUserLoaded();
    if (mounted) {
      await _initSocketAndListeners();
    }
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
    _connectionSubscription?.cancel();

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

  void _startLocationUpdates() async {
    _positionStreamSubscription?.cancel();

    // Get initial location
    final position = await _locationService.getCurrentLocation();
    if (position != null && mounted) {
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
      _emitLocationUpdate(position.latitude, position.longitude);
    }

    // Use ride tracking stream for active rides (more frequent updates)
    // or periodic stream for online status
    final bool isActiveRide =
        _status == 'in_progress' || _status == 'pickup' || _status == 'arrived';

    if (isActiveRide) {
      // Use high-frequency tracking for active rides (every 3 seconds, 5m distance filter)
      _positionStreamSubscription = _locationService
          .getRideTrackingStream(intervalSeconds: 3)
          .listen(_handlePositionUpdate);

      debugPrint(
        '📍 [DriverHomeScreen] Started ride tracking stream (3s interval)',
      );
    } else {
      // Use periodic updates when just online (every 4 seconds)
      _positionStreamSubscription = _locationService
          .getPeriodicPositionStream(intervalSeconds: 4)
          .listen(_handlePositionUpdate);

      debugPrint(
        '📍 [DriverHomeScreen] Started periodic location stream (4s interval)',
      );
    }
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

      final bool isNavigationMode =
          _status == 'pickup' ||
          _status == 'arrived' ||
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

  /// Fetch navigation route based on current status
  Future<void> _fetchNavigationRoute() async {
    if (_rideData == null) return;

    LatLng destination;

    if (_status == 'pickup' || _status == 'arrived') {
      // Navigate to pickup
      final coords = _rideData!['pickupLocation']?['coordinates'] ?? [0.0, 0.0];
      destination = LatLng(coords[1], coords[0]);
    } else if (_status == 'in_progress') {
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
    } else if (_status == 'in_progress') {
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

  void _emitLocationUpdate(double lat, double lng) {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
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
        debugPrint('🔔 [DriverHomeScreen] Triggering _handleNewRideRequest');
        _handleNewRideRequest(data);
      } else {
        debugPrint(
          '🔔 [DriverHomeScreen] Received request but widget not mounted',
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
        });
        CustomSnackbar.show(
          context,
          message: 'Ride request expired.',
          type: SnackbarType.info,
        );
      }
    });
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

      setState(() {
        _status = 'request';
        _currentRideId = data['rideId'] ?? data['_id']; // Store ride ID
        _rideData = data;
      });

      // Show notification
      CustomSnackbar.show(
        context,
        message: 'New Ride Request! 🚗',
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

    setState(() => _isLoading = true);

    try {
      if (_status == 'request') {
        // Accept Ride
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
          setState(() {
            _status = 'arrived';
            if (response['data'] != null) {
              final newData = response['data'] as Map<String, dynamic>;
              _rideData = {...?_rideData, ...newData};
            }
          });
          CustomSnackbar.show(
            context,
            message: 'You have arrived!',
            type: SnackbarType.success,
          );
        } else {
          String errorMessage = response['message'] ?? 'Failed to arrive';
          if (response['errors'] != null &&
              response['errors']['distance'] != null) {
            errorMessage =
                'You are ${response['errors']['distance'].toInt()}m away. Must be within ${response['errors']['required']}m.';
          }
          CustomSnackbar.show(
            context,
            message: errorMessage,
            type: SnackbarType.error,
          );
        }
      } else if (_status == 'arrived') {
        _showOtpDialog();
      } else if (_status == 'in_progress') {
        // Complete Ride
        final pos = _currentLocation;
        final response = await _apiService.completeRide(
          _currentRideId!,
          pos.latitude,
          pos.longitude,
        );
        if (response['success'] == true) {
          final paymentMethod = _rideData?['paymentMethod'];
          final rideResult = response['data'] as Map<String, dynamic>? ?? {};
          final bool isPromoFreeRide = rideResult['isPromoRide'] == true &&
              (rideResult['fare'] is num
                  ? (rideResult['fare'] as num).toDouble()
                  : 0.0) ==
                  0.0;

          if (paymentMethod == 'cash' && isPromoFreeRide) {
            // Fully discounted promo ride — no cash to collect, auto-finalize
            final confirmResponse =
                await _apiService.confirmCashCollection(_currentRideId!);
            if (confirmResponse['success'] == true) {
              setState(() {
                _status = 'online';
                _currentRideId = null;
                _rideData = null;
                _clearNavigationUi();
              });
              _fetchRideHistory();
              CustomSnackbar.show(
                context,
                message:
                    'Promotional ride complete — no cash to collect.',
                type: SnackbarType.success,
              );
            } else {
              CustomSnackbar.show(
                context,
                message:
                    'Failed to finalize: ${confirmResponse['message']}',
                type: SnackbarType.error,
              );
            }
          } else if (paymentMethod == 'cash') {
            setState(() {
              _status = 'awaiting_cash_confirmation';
            });
            CustomSnackbar.show(
              context,
              message: 'Ride completed. Collect cash from passenger.',
              type: SnackbarType.warning,
            );
          } else {
            setState(() {
              _status = 'online';
              _currentRideId = null;
              _rideData = null;
              _clearNavigationUi();
            });
            _fetchRideHistory();
            CustomSnackbar.show(
              context,
              message: 'Ride completed successfully.',
              type: SnackbarType.success,
            );
          }
        } else {
          CustomSnackbar.show(
            context,
            message: 'Failed to complete: ${response['message']}',
            type: SnackbarType.error,
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
          });
          _fetchRideHistory();
        } else {
          CustomSnackbar.show(
            context,
            message: 'Failed to confirm cash: ${response['message']}',
            type: SnackbarType.error,
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

  /// Show cancellation reason picker and cancel the ride
  void _showCancellationReasonDialog() {
    String? selectedReason;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cancel Ride'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select a reason for cancellation:'),
              const SizedBox(height: 16),
              _buildCancellationReasonOption(
                'rider_no_show',
                'Rider No Show',
                selectedReason,
                (value) => setDialogState(() => selectedReason = value),
              ),
              _buildCancellationReasonOption(
                'rider_unreachable',
                'Rider Unreachable',
                selectedReason,
                (value) => setDialogState(() => selectedReason = value),
              ),
              _buildCancellationReasonOption(
                'safety_concern',
                'Safety Concern',
                selectedReason,
                (value) => setDialogState(() => selectedReason = value),
              ),
              _buildCancellationReasonOption(
                'vehicle_issue',
                'Vehicle Issue',
                selectedReason,
                (value) => setDialogState(() => selectedReason = value),
              ),
              _buildCancellationReasonOption(
                'driver_no_show',
                'Cannot Make It',
                selectedReason,
                (value) => setDialogState(() => selectedReason = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: selectedReason != null
                  ? () {
                      Navigator.pop(context);
                      _cancelRideByDriver(selectedReason!);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const FittedBox(
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

  Widget _buildCancellationReasonOption(
    String value,
    String label,
    String? selectedValue,
    ValueChanged<String?> onChanged,
  ) {
    return RadioListTile<String>(
      title: Text(label),
      value: value,
      groupValue: selectedValue,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  /// Cancel ride by driver with a reason
  Future<void> _cancelRideByDriver(String reason) async {
    if (_currentRideId == null) return;

    setState(() => _isLoading = true);
    try {
      final response = await _apiService.cancelRideByDriver(
        _currentRideId!,
        reason: reason,
      );

      setState(() {
        _status = 'online';
        _currentRideId = null;
        _rideData = null;
      });

      if (response['success'] == true) {
        CustomSnackbar.show(
          context,
          message: 'Ride cancelled. User will receive full refund.',
          type: SnackbarType.success,
        );
      } else {
        CustomSnackbar.show(
          context,
          message: response['message'] ?? 'Failed to cancel ride',
          type: SnackbarType.error,
        );
      }
    } catch (e) {
      debugPrint('Error cancelling ride: $e');
      CustomSnackbar.show(
        context,
        message: 'Error cancelling ride',
        type: SnackbarType.error,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Show end ride early dialog with reason selection
  void _showEndRideEarlyDialog() {
    String? selectedReason;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('End Ride Early'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The fare will be adjusted based on actual distance traveled.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const Text('Select a reason:'),
              const SizedBox(height: 8),
              _buildCancellationReasonOption(
                'user_requested',
                'User Requested',
                selectedReason,
                (value) => setDialogState(() => selectedReason = value),
              ),
              _buildCancellationReasonOption(
                'wrong_destination',
                'Wrong Destination',
                selectedReason,
                (value) => setDialogState(() => selectedReason = value),
              ),
              _buildCancellationReasonOption(
                'rider_misbehavior',
                'Rider Misbehavior',
                selectedReason,
                (value) => setDialogState(() => selectedReason = value),
              ),
              _buildCancellationReasonOption(
                'safety_concern',
                'Safety Concern',
                selectedReason,
                (value) => setDialogState(() => selectedReason = value),
              ),
              _buildCancellationReasonOption(
                'vehicle_issue',
                'Vehicle Issue',
                selectedReason,
                (value) => setDialogState(() => selectedReason = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: selectedReason != null
                  ? () {
                      Navigator.pop(context);
                      _endRideEarly(selectedReason!);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const FittedBox(
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

  /// End the ride early with adjusted fare
  Future<void> _endRideEarly(String reason) async {
    if (_currentRideId == null) return;

    setState(() => _isLoading = true);
    try {
      final response = await _apiService.endRideEarly(
        _currentRideId!,
        latitude: _currentLocation.latitude,
        longitude: _currentLocation.longitude,
        reason: reason,
      );

      if (response['success'] == true) {
        final adjustedFare = response['data']?['adjustedFare'] ?? 0.0;

        final paymentMethod = _rideData?['paymentMethod'];

        if (paymentMethod == 'cash') {
          setState(() {
            _status = 'awaiting_cash_confirmation';
          });
          CustomSnackbar.show(
            context,
            message:
                'Ride ended early (£${adjustedFare.toStringAsFixed(2)}). Collect cash from passenger.',
            type: SnackbarType.warning,
          );
        } else {
          setState(() {
            _status = 'online';
            _currentRideId = null;
            _rideData = null;
            _clearNavigationUi();
          });
          _fetchRideHistory();
          CustomSnackbar.show(
            context,
            message:
                'Ride completed successfully (£${adjustedFare.toStringAsFixed(2)}).',
            type: SnackbarType.success,
          );
          // payment:succeeded socket will finalize
        }
      } else {
        CustomSnackbar.show(
          context,
          message: response['message'] ?? 'Failed to end ride',
          type: SnackbarType.error,
        );
      }
    } catch (e) {
      debugPrint('Error ending ride early: $e');
      CustomSnackbar.show(
        context,
        message: 'Error ending ride',
        type: SnackbarType.error,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showOtpDialog() {
    final TextEditingController otpController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Enter OTP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ask passenger for the 4-digit PIN'),
            const SizedBox(height: 16),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: const InputDecoration(
                hintText: '0000',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (otpController.text.length == 4) {
                _verifyAndStartRide(otpController.text);
              } else {
                CustomSnackbar.show(
                  context,
                  message: 'Please enter a 4-digit OTP',
                  type: SnackbarType.error,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Verify & Start',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyAndStartRide(String otp) async {
    // Mock OTP verification for now
    // In real app, verify OTP with backend or check against ride data

    Navigator.pop(context); // Close dialog
    setState(() => _isLoading = true);

    try {
      final response = await _apiService.startRide(_currentRideId!, otp);
      if (response['success'] == true) {
        setState(() {
          _status = 'in_progress';
          if (response['data'] != null) {
            final newData = response['data'] as Map<String, dynamic>;
            _rideData = {...?_rideData, ...newData};
          }
        });
        CustomSnackbar.show(
          context,
          message: 'OTP Verified! Trip Started.',
          type: SnackbarType.success,
        );
        // Fetch navigation route to dropoff
        _fetchNavigationRoute();
      } else {
        CustomSnackbar.show(
          context,
          message: 'Failed to start ride: ${response['message']}',
          type: SnackbarType.error,
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

          // Connection status banner — shows when socket is disconnected
          const ConnectionStatusBanner(),
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
        return 280; // Taller for request details
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

    bool isNavigationMode =
        _status == 'pickup' || _status == 'in_progress' || _status == 'arrived';

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
        _status == 'in_progress' ||
        _status == 'awaiting_payment' ||
        _status == 'awaiting_cash_confirmation') {
      return DriverNavigationPanel(
        status: _status,
        rideData: _rideData,
        onAction: _handleRideAction,
        onCancel: _showCancellationReasonDialog,
        onEndEarly: _showEndRideEarlyDialog,
        navigationState: _navigationState,
        isLoading: _isLoading,
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
