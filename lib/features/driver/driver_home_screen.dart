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
import 'package:geolocator/geolocator.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
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

  // Connection status subscription for reconnection handling
  StreamSubscription<bool>? _connectionSubscription;

  // Last emitted location timestamp to throttle updates
  DateTime? _lastEmitTime;
  static const int _minEmitIntervalMs = 3000; // Minimum 3 seconds between emits

  @override
  void initState() {
    super.initState();
    _initDriver();
    _initLocation();
    _setupConnectionListener();
  }

  /// Listen for socket reconnection and re-emit driver online status
  void _setupConnectionListener() {
    _connectionSubscription = _socketService.connectionStatus.listen((
      isConnected,
    ) {
      if (isConnected && _status != 'offline') {
        debugPrint(
          '🔄 [DriverHomeScreen] Reconnected, re-emitting driver status',
        );
        _emitDriverOnline();
      }
    });
  }

  void _initLocation() async {
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
    // Clean up socket listeners
    _socketService.off('ride:newRequest');
    _socketService.off('ride:reminder');
    _socketService.off('ride:longRunning');
    _socketService.off('ride:cancelled');
    _socketService.off('driver:status');
    _socketService.off('driver:locationUpdated');

    // Clean up streams
    _positionStreamSubscription?.cancel();
    _connectionSubscription?.cancel();

    // Clean up services
    _navigationService.dispose();
    _locationService.dispose();

    // Emit driver offline when disposing (if was online)
    if (_status != 'offline') {
      final user = Provider.of<AuthProvider>(context, listen: false).user;
      final driverId = user?['_id'] ?? user?['id'] ?? user?['userId'];
      if (driverId != null) {
        _socketService.emitDriverOffline(driverId);
      }
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
      if (mounted) {
        setState(() {
          _navigationState = state;
          _updateNavigationPolylines();
        });
      }
    });
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

    // Listen for driver status confirmation
    _socketService.on('driver:status', (data) {
      debugPrint('📩 [DriverHomeScreen] Driver status: $data');
      if (mounted && data['status'] == 'online') {
        // Successfully went online
      }
    });

    // Listen for location update confirmation
    _socketService.on('driver:locationUpdated', (data) {
      // Location update confirmed by server
    });

    // Listen for new ride requests
    _socketService.on('ride:newRequest', (data) {
      debugPrint('🔔 [DriverHomeScreen] New Ride Request Received: $data');
      if (mounted) {
        _handleNewRideRequest(data);
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
        final cancellationFee = data['cancellationFee'] ?? 0.0;
        setState(() {
          _status = 'online';
          _currentRideId = null;
          _rideData = null;
        });

        final message = cancellationFee > 0
            ? 'User cancelled the ride.\nYou received £${cancellationFee.toStringAsFixed(2)} compensation.'
            : 'User cancelled the ride.';

        CustomSnackbar.show(context, message: message, type: SnackbarType.info);
      }
    });
  }

  void _handleNewRideRequest(dynamic data) {
    // Only show request if driver is online and available
    if (_status == 'online') {
      setState(() {
        _status = 'request';
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
        if (mounted) {
          CustomSnackbar.show(
            context,
            message: 'Failed to update status: ${response['message']}',
            type: SnackbarType.error,
          );
        }
        debugPrint('🔴 [DriverHomeScreen] Failed to update status');
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.show(
          context,
          message: 'Error updating status: $e',
          type: SnackbarType.error,
        );
      }
      debugPrint('🔴 [DriverHomeScreen] Error updating status: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
          setState(() => _status = 'pickup');
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
          setState(() => _status = 'arrived');
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
        final response = await _apiService.completeRide(_currentRideId!);
        if (response['success'] == true) {
          setState(() => _status = 'complete');
          // Reset to online after short delay
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() {
                _status = 'online';
                _currentRideId = null;
              });
            }
          });
        } else {
          CustomSnackbar.show(
            context,
            message: 'Failed to complete: ${response['message']}',
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

  Future<void> _declineRide() async {
    if (_currentRideId == null) return;

    setState(() => _isLoading = true);
    try {
      final response = await _apiService.cancelRide(_currentRideId!);
      // Even if it fails, we reset UI to online to avoid getting stuck
      setState(() {
        _status = 'online';
        _currentRideId = null;
      });

      if (response['success'] == true) {
        CustomSnackbar.show(
          context,
          message: 'Ride Declined',
          type: SnackbarType.info,
        );
      }
    } catch (e) {
      debugPrint('Error declining ride: $e');
      setState(() {
        _status = 'online';
        _currentRideId = null;
      });
    } finally {
      setState(() => _isLoading = false);
    }
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
              child: const Text('Cancel Ride'),
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
              child: const Text('End Ride'),
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
        final actualDistance = response['data']?['actualDistance'] ?? 0.0;

        setState(() {
          _status = 'complete';
        });

        // Show result dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Ride Ended'),
            content: Text(
              'Adjusted fare: £${adjustedFare.toStringAsFixed(2)}\n'
              'Distance traveled: ${actualDistance.toStringAsFixed(1)} km',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _status = 'online';
                    _currentRideId = null;
                    _rideData = null;
                  });
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
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
            child: const Text('Verify & Start'),
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
        setState(() => _status = 'in_progress');
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
      body: SlidingUpPanel(
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
                    GestureDetector(
                      onTap: () =>
                          Navigator.pushNamed(context, '/driver-earnings'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.account_balance_wallet,
                              color: AppTheme.primaryColor,
                            ),
                            SizedBox(width: 8),
                            Text(
                              '£142.50',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

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
                    const Text(
                      'You earned £14.50',
                      style: TextStyle(
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
      );
    } else {
      return DriverNavigationPanel(
        status: _status,
        rideData: _rideData,
        onAction: _handleRideAction,
        onCancel: _showCancellationReasonDialog,
        onEndEarly: _showEndRideEarlyDialog,
        navigationState: _navigationState,
      );
    }
  }

  Widget _buildOfflineOnlineContent() {
    return Column(
      children: [
        const SizedBox(height: 12),
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

        // Go Online Button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: GestureDetector(
            onTap: _toggleOnline,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 60,
              decoration: BoxDecoration(
                color: _status == 'online' ? Colors.red : AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color:
                        (_status == 'online'
                                ? Colors.red
                                : AppTheme.primaryColor)
                            .withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _status == 'online' ? 'GO OFFLINE' : 'GO ONLINE',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 32),

        // Stats / Recent Activity
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            physics: const BouncingScrollPhysics(),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Today\'s Summary',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/driver-activity'),
                    child: const Text('See All'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildStatCard('Trips', '12', Icons.directions_car),
                  const SizedBox(width: 16),
                  _buildStatCard('Hours', '4.5', Icons.access_time),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Recent Activity',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildActivityItem('Heathrow Drop-off', '£24.50', '10:30 AM'),
              _buildActivityItem('City Center Ride', '£12.20', '09:15 AM'),
              _buildActivityItem('Morning Commute', '£8.50', '08:45 AM'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppTheme.textSecondary),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(String title, String amount, String time) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.history, color: AppTheme.textPrimary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  time,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
