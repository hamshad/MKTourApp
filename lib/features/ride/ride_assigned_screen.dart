import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
import '../../core/services/socket_service.dart';
import '../../core/api_service.dart';
import '../../core/services/navigation_service.dart';
import '../../core/services/places_service.dart';
import '../../core/services/marker_interpolation_service.dart';
import '../../core/services/payment_service.dart';
import '../../core/services/stripe_service.dart';
import '../../core/widgets/platform_map.dart';
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

  const RideAssignedScreen({
    super.key,
    required this.rideId,
    this.pickup,
    this.dropoff,
    this.fare = 15.50,
    this.driver,
    this.paymentTiming,
    this.clientSecret,
  });

  @override
  State<RideAssignedScreen> createState() => _RideAssignedScreenState();
}

class _RideAssignedScreenState extends State<RideAssignedScreen> {
  final SocketService _socketService = SocketService();
  final ApiService _apiService = ApiService();
  final NavigationService _navigationService = NavigationService();
  final PlacesService _placesService = PlacesService();
  String _rideStatus = 'searching';

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
  String _otp = '';
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

  // Cancellation state
  bool _isCancelling = false;
  bool _isProcessingPayment = false;
  bool _isAwaitingPaymentConfirmation = false;
  Map<String, dynamic>? _pendingPaymentRideData;
  bool _isPaymentMethodSelected = false;
  String _selectedPaymentMethodDisplay = '';

  @override
  void initState() {
    super.initState();
    _initializeLocations();
    _setupInitialState();
    _setupSocketListeners();
    _setupConnectionListener();
    _fetchDetailedAddresses();
    _setupNavigationListener();
  }

  void _setupInitialState() {
    debugPrint('🚀 [RideAssignedScreen] Setting up initial state...');
    debugPrint('🚀 [RideAssignedScreen] widget.driver: ${widget.driver}');

    if (widget.driver != null) {
      debugPrint('✅ [RideAssignedScreen] Initial driver data provided');
      _rideStatus = 'accepted';
      _driver = widget.driver!;

      // Try multiple possible OTP field names from initial data
      _otp =
          widget.driver!['otp']?.toString() ??
          widget.driver!['verificationOTP']?.toString() ??
          widget.driver!['verification_otp']?.toString() ??
          '';

      debugPrint('🔐 [RideAssignedScreen] Initial OTP: "$_otp"');
      debugPrint('👤 [RideAssignedScreen] Initial driver: $_driver');

      // Extract driver ID and join their location room
      _currentDriverId =
          _driver['_id']?.toString() ?? _driver['id']?.toString();
      if (_currentDriverId != null) {
        _socketService.joinDriverRoom(_currentDriverId!);
        debugPrint(
          '🚗 [RideAssignedScreen] Joined driver room: driver:$_currentDriverId',
        );
      }

      if (_driver['location'] != null) {
        final coords = _driver['location']['coordinates'];
        debugPrint('📍 [RideAssignedScreen] Initial driver location: $coords');
        _driverLocation = latlong2.LatLng(coords[1], coords[0]);

        // Initialize marker interpolation with driver's initial position
        _initMarkerInterpolation(latlong2.LatLng(coords[1], coords[0]));
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
        setState(() {
          _driverLocation = latlong2.LatLng(
            interpolated.position.latitude,
            interpolated.position.longitude,
          );
          _updateMarkers();
        });
      }
    });

    debugPrint('🚗 [RideAssignedScreen] Marker interpolation initialized');
  }

  void _setupConnectionListener() {
    _connectionSubscription = _socketService.connectionStatus.listen((
      isConnected,
    ) {
      if (isConnected && _currentDriverId != null) {
        debugPrint(
          '🔄 [RideAssignedScreen] Reconnected, rejoining driver room',
        );
        _socketService.joinDriverRoom(_currentDriverId!);
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
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    debugPrint('🔌 [RideAssignedScreen] Initializing socket listeners...');

    await _socketService.initSocket();

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

    _socketService.on('ride:accepted', (data) {
      if (mounted) {
        debugPrint('═══════════════════════════════════════════════════════');
        debugPrint('✅ [RideAssignedScreen] RIDE ACCEPTED EVENT RECEIVED');
        debugPrint('═══════════════════════════════════════════════════════');
        debugPrint('📦 [RideAssignedScreen] Full data: $data');
        debugPrint('📦 [RideAssignedScreen] Data type: ${data.runtimeType}');

        // Log individual fields for debugging
        debugPrint('🔑 [RideAssignedScreen] rideId: ${data['rideId']}');
        debugPrint('🔑 [RideAssignedScreen] status: ${data['status']}');
        debugPrint('🔑 [RideAssignedScreen] otp field: ${data['otp']}');
        debugPrint(
          '🔑 [RideAssignedScreen] verificationOTP field: ${data['verificationOTP']}',
        );
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
          debugPrint(
            '🚗 [RideAssignedScreen] Vehicle: ${driverData['vehicle']}',
          );
          debugPrint(
            '📍 [RideAssignedScreen] Driver location: ${driverData['location']}',
          );
        } else {
          debugPrint('⚠️ [RideAssignedScreen] Driver data is NULL!');
        }

        setState(() {
          _rideStatus = 'accepted';
          _driver = data['driver'] ?? {};

          // Try multiple possible OTP field names
          _otp =
              data['otp']?.toString() ??
              data['verificationOTP']?.toString() ??
              data['verification_otp']?.toString() ??
              data['code']?.toString() ??
              '';

          debugPrint('🔐 [RideAssignedScreen] Extracted OTP: "$_otp"');
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
          } else {
            debugPrint('⚠️ [RideAssignedScreen] Driver location is NULL');
          }
          _updateMarkers();
        });

        debugPrint('═══════════════════════════════════════════════════════');
        debugPrint(
          '✅ [RideAssignedScreen] State updated - Status: $_rideStatus, OTP: $_otp',
        );
        debugPrint('═══════════════════════════════════════════════════════');
      }
    });

    _socketService.on('driver:locationChanged', (data) {
      debugPrint('📍 [RideAssignedScreen] Driver Location Updated: $data');

      // Handle location updates based on ride status:
      // - driver_assigned/accepted: Car moving toward pickup
      // - driver_arrived: Car stationary at pickup (still update position for accuracy)
      // - in_progress: Car moving toward destination
      if (mounted &&
          (_rideStatus == 'accepted' ||
              _rideStatus == 'driver_arrived' ||
              _rideStatus == 'in_progress')) {
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
      if (mounted) {
        debugPrint('🚀 [RideAssignedScreen] Ride Started: $data');
        setState(() {
          _rideStatus = 'in_progress';
          _updateMarkers();
          // Switch to navigation from current to dropoff
          _fetchNavigationRoute();
        });
      }
    });

    _socketService.on('ride:completed', (data) {
      if (!mounted) return;
      debugPrint('🏁 [RideAssignedScreen] Ride Completed: $data');

      final timing = widget.paymentTiming ?? data['paymentTiming']?.toString();
      final bool isPayLater = timing == 'pay_later';
      final completedFare = (data['fare'] as num?)?.toDouble() ?? widget.fare;
      final completedDistance = (data['distance'] as num?)?.toDouble();

      if (isPayLater) {
        _handlePayLaterCompletion(
          fare: completedFare,
          distance: completedDistance,
          rideData: data is Map<String, dynamic> ? data : null,
        );
        return;
      }

      setState(() {
        _rideStatus = 'completed';
      });
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
      if (!mounted) return;

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

      _showPaymentSuccessScreen(mergedRideData);
    });

    _socketService.on('ride:driverArrived', (data) {
      if (mounted) {
        debugPrint('🚖 [RideAssignedScreen] Driver Arrived: $data');
        setState(() {
          _rideStatus = 'driver_arrived';
          // Set driver position to pickup location (driver is at pickup)
          _driverLocation = _pickupLocation;
          // Clear navigation polyline - car is stationary
          _polylines = [];
          _updateMarkers();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver has arrived! Please select payment method.'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 4),
          ),
        );
        _showPaymentSelectionModal();
      }
    });

    _socketService.on('ride:otpExpired', (data) {
      if (mounted) {
        debugPrint('🔄 [RideAssignedScreen] OTP Expired: $data');
        setState(() {
          _otp = data['newOTP'] ?? _otp;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New OTP: $_otp'),
            backgroundColor: Colors.blue,
          ),
        );
      }
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
                          'paymentMethod':
                              data['paymentMethod'], // Pass payment method
                          'paymentStatus':
                              'pending', // Assume pending if early complete + cash
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

    setState(() {
      _markers = newMarkers;
    });
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
              content: Text('Ride cancelled. Full refund processed.'),
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
    // Clean up marker interpolation
    _interpolationSubscription?.cancel();
    _markerInterpolation?.dispose();

    // Clean up connection listener
    _connectionSubscription?.cancel();

    // Leave driver room if we were tracking one
    if (_currentDriverId != null) {
      _socketService.leaveDriverRoom(_currentDriverId!);
    }

    // Clean up socket listeners
    _socketService.off('driver:locationChanged');
    _socketService.off('ride:started');
    _socketService.off('ride:completed');
    _socketService.off('ride:driverArrived');
    _socketService.off('ride:otpExpired');
    _socketService.off('ride:cancelledByDriver');
    _socketService.off('ride:earlyCompleted');
    _socketService.off('payment:succeeded');
    _socketService.off('payment:authorized');
    _socketService.off('payment:failed');
    _socketService.off('ride:longRunning');

    // Clean up navigation
    _navigationService.dispose();

    debugPrint('🔴 [RideAssignedScreen] Disposed');
    super.dispose();
  }

  void _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
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

  @override
  Widget build(BuildContext context) {
    if (_rideStatus == 'completed') {
      return RideCompleteScreen(
        rideData: {
          'bookingId': widget.rideId,
          'driver': _driver,
          'fare': widget.fare,
        },
      );
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

    _isAwaitingPaymentConfirmation = false;

    final Map<String, dynamic> finalRideData = {
      'bookingId': widget.rideId,
      'driver': _driver,
      'fare': widget.fare,
      ...rideData,
      'paymentMethod': rideData['paymentMethod'] ?? 'Cash',
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
    // Debug logging for UI rendering
    debugPrint('🎨 [RideAssignedScreen] Building status panel');
    debugPrint('🎨 [RideAssignedScreen] Current status: $_rideStatus');
    debugPrint(
      '🎨 [RideAssignedScreen] OTP value: "$_otp" (isEmpty: ${_otp.isEmpty})',
    );
    debugPrint('🎨 [RideAssignedScreen] Driver data: $_driver');

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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Estimated Fare: £${widget.fare.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
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
                ],
              ),
            ),

            // Payment Method Badge
            if (_isPaymentMethodSelected && _selectedPaymentMethodDisplay.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _selectedPaymentMethodDisplay.toLowerCase().contains('link')
                          ? Icons.link
                          : _selectedPaymentMethodDisplay.toLowerCase().contains('card')
                              ? Icons.credit_card
                              : Icons.money,
                      size: 14,
                      color: Colors.grey[700],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Payment: $_selectedPaymentMethodDisplay',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),

            // OTP Display - Show prominently when driver accepted or arrived AND payment is selected
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
                  color: AppTheme.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.accentColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          color: AppTheme.accentColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'YOUR RIDE OTP',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _otp.isNotEmpty ? _otp : '------',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: _otp.isNotEmpty
                            ? AppTheme.accentColor
                            : Colors.grey,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _otp.isNotEmpty
                          ? 'Share this code with your driver when boarding'
                          : 'Waiting for OTP...',
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

  void _showPaymentSelectionModal() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
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
                const SizedBox(height: 24),
                _buildPaymentOption(
                  icon: Icons.money,
                  title: 'Cash',
                  subtitle: 'Pay directly to driver',
                  onTap: () => _handlePaymentSelection('cash'),
                ),
                const SizedBox(height: 16),
                _buildPaymentOption(
                  icon: Icons.link,
                  title: 'Payment Link',
                  subtitle: 'Pay via online link',
                  onTap: () => _handlePaymentSelection('payment_link'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
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

  Future<void> _handlePaymentSelection(String method) async {
    Navigator.pop(context); // Close selection modal

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    debugPrint('💸 [Payment] Selecting: $method');
    try {
      final response = await _apiService.selectPaymentMethod(
        widget.rideId,
        method,
      );

      // Close loading
      Navigator.pop(context);

      if (response['success'] == true) {
        final data = response['data'];
        
        // Handle nested ride structure (data.ride) or flat structure (data)
        final rideData = data['ride'] ?? data;
        final paymentMethod = rideData['paymentMethod'];
        
        debugPrint('💸 [Payment] Method from response: $paymentMethod');

        if (paymentMethod == 'stripe') {
          final clientSecret = rideData['clientSecret'];
          debugPrint('💳 [Stripe] Client secret present: ${clientSecret != null}');
          
          if (clientSecret != null) {
            await StripeService.processPayment(clientSecret);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Payment Successful! Share OTP with driver.'),
                backgroundColor: Colors.green,
              ),
            );
            setState(() {
              _isPaymentMethodSelected = true;
              _selectedPaymentMethodDisplay = 'Card';
            });
          }
        } else if (paymentMethod == 'payment_link') {
          final paymentUrl = rideData['paymentUrl'];
          debugPrint('🔗 [Payment Link] URL present: ${paymentUrl != null}');
          if (paymentUrl != null) {
            debugPrint('🔗 [Payment Link] URL: $paymentUrl');
          }

          if (paymentUrl != null) {
            debugPrint('✅ [Payment Link] Opening in-app WebView');
            
            // Navigate to WebView screen
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PaymentWebViewScreen(
                  paymentUrl: paymentUrl,
                  rideId: widget.rideId,
                ),
              ),
            );

            // Handle result from WebView
            if (result != null && result['success'] == true) {
              debugPrint('✅ [Payment Link] Payment completed successfully');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Payment successful! Share OTP with driver.'),
                  backgroundColor: Colors.green,
                ),
              );
              setState(() {
                _isPaymentMethodSelected = true;
                _selectedPaymentMethodDisplay = 'Payment Link';
              });
            } else {
              debugPrint('❌ [Payment Link] Payment cancelled or failed');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Payment was not completed. Please try again.'),
                  backgroundColor: Colors.orange,
                ),
              );
              // Re-show payment selection modal
              _showPaymentSelectionModal();
            }
          } else {
            debugPrint('❌ [Payment Link] URL missing in response');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No payment link provided by server.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } else {
          debugPrint('💵 [Cash] Payment method selected');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cash payment selected. Share OTP with driver.'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _isPaymentMethodSelected = true;
            _selectedPaymentMethodDisplay = 'Cash';
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response['message'] ?? 'Failed to select payment method',
            ),
          ),
        );
        _showPaymentSelectionModal(); // Re-show on API fail
      }
    } catch (e) {
      if (Navigator.canPop(context))
        Navigator.pop(context); // Ensure loading is closed
      debugPrint('❌ [Payment] Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      _showPaymentSelectionModal(); // Re-show on error
    }
  }
}
