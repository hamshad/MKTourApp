import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/ui_frame.dart';
import '../../core/constants.dart';
import '../../core/api_service.dart';
import '../../core/services/places_service.dart';
import '../../core/services/payment_service.dart';
import '../../core/services/socket_service.dart';
import '../ride/payment_webview_screen.dart';
import '../ride/ride_assigned_screen.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../core/auth_provider.dart';
import '../../core/widgets/platform_map.dart';
import '../../core/widgets/route_map_helpers.dart';
import 'package:latlong2/latlong.dart' as lat_lng;
import 'package:flutter_map/flutter_map.dart' as fmap;
import '../../core/models/vehicle.dart';
import 'widgets/schedule_ride_sheet.dart';

/// Ride Confirmation Screen - Shows ride details before final booking
/// Displays pickup, dropoff, vehicle type, distance, duration, and fare
class RideConfirmationScreen extends StatefulWidget {
  final Map<String, dynamic> pickupLocation;
  final Map<String, dynamic> dropoffLocation;
  final String categorySlug;
  final String categoryName;
  final Map<String, dynamic> fareData;
  final List<dynamic>? polyline; // Added polyline
  final bool isScheduled; // Set to true to enable scheduling flow
  final DateTime? scheduledDateTime; // The scheduled ride time (if prebooked)
  final List<Map<String, dynamic>>? stops; // Intermediate stops (max 3)
  final String? paymentMethod; // Payment method for prebook

  const RideConfirmationScreen({
    super.key,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.categorySlug,
    required this.categoryName,
    required this.fareData,
    this.polyline,
    this.isScheduled = false,
    this.scheduledDateTime,
    this.stops,
    this.paymentMethod,
  });

  @override
  State<RideConfirmationScreen> createState() => _RideConfirmationScreenState();
}

class _RideConfirmationScreenState extends State<RideConfirmationScreen> {
  final ApiService _apiService = ApiService();
  final PlacesService _placesService = PlacesService();
  bool _isLoading = false;
  bool _isFetchingFare = true;
  String? _fareError; // Error message if fare fetch fails
  Map<String, dynamic>? _dynamicFareData;
  PaymentTiming _paymentTiming = PaymentTiming.payLater;
  late String _selectedPaymentMethod;
  // Pending unpaid scheduled ride — set when backend returns a paymentUrl.
  // Used to switch payment method via select-payment instead of duplicate create.
  String? _pendingScheduledRideId;
  // Last time picked in the sheet — reused as sheet initial so cancel keeps it.
  DateTime? _lastScheduledTime;
  bool get _isFixedFare => widget.fareData['is_fixed_fare'] == true;

  // Route polyline points - initialized synchronously from passed data
  late List<lat_lng.LatLng> _routePoints;
  late fmap.LatLngBounds? _routeBounds;

  @override
  void initState() {
    super.initState();
    _selectedPaymentMethod = widget.paymentMethod ?? 'cash';
    // Initialize route synchronously from passed polyline
    _initializeRouteSync();
    // Multi-stop: the passed polyline may predate the stops editor —
    // refetch with waypoints so the map traces pickup → stops → dropoff.
    if (widget.stops?.isNotEmpty == true) {
      _refetchRouteWithStops();
    }
    // Skip the old fare API if we already have promo-aware data or a fixed fare
    final hasPromoData = widget.fareData['promo_applied'] == true;
    final hasValidFare =
        widget.fareData['total_fare'] != null &&
        (widget.fareData['total_fare'] as num) > 0;

    if (_isFixedFare || hasPromoData || hasValidFare) {
      _isFetchingFare = false;
    } else {
      _fetchDirectionsAndFare();
    }

    // Auto-open the schedule sheet if this is a prebook request WITHOUT a pre-selected time
    // If scheduledDateTime is already provided, skip this (user already scheduled)
    if (widget.isScheduled && widget.scheduledDateTime == null) {
      runAfterFrame((_) {
        _showScheduleSheet();
      });
    }
  }

  /// Initialize route polyline synchronously from passed data
  void _initializeRouteSync() {
    final pickupCoords = widget.pickupLocation['coordinates'] as List;
    final dropoffCoords = widget.dropoffLocation['coordinates'] as List;

    debugPrint('🗺️ RideConfirmationScreen: Initializing route...');
    debugPrint('   → Polyline provided: ${widget.polyline != null}');
    debugPrint('   → Polyline length: ${widget.polyline?.length ?? 0}');

    // If polyline was passed in, use it directly (synchronous)
    if (widget.polyline != null && widget.polyline!.isNotEmpty) {
      final points = <lat_lng.LatLng>[];

      // Debug: Check the first item type
      if (widget.polyline!.isNotEmpty) {
        final firstItem = widget.polyline!.first;
        debugPrint('   → First polyline item type: ${firstItem.runtimeType}');
        debugPrint('   → First polyline item: $firstItem');
      }

      for (var p in widget.polyline!) {
        if (p is lat_lng.LatLng) {
          points.add(p);
        } else if (p is Map) {
          points.add(
            lat_lng.LatLng(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble(),
            ),
          );
        } else {
          // Try to handle other LatLng types (e.g., from latlong2 without prefix)
          try {
            // Access latitude and longitude dynamically
            final lat = (p as dynamic).latitude as double;
            final lng = (p as dynamic).longitude as double;
            points.add(lat_lng.LatLng(lat, lng));
          } catch (e) {
            debugPrint('   ⚠️ Could not convert point: $p (${p.runtimeType})');
          }
        }
      }

      debugPrint('   → Converted points: ${points.length}');

      if (points.isNotEmpty) {
        _routePoints = points;
        _routeBounds = fmap.LatLngBounds.fromPoints(points);
        debugPrint(
          '   → Bounds: SW(${_routeBounds!.southWest.latitude}, ${_routeBounds!.southWest.longitude}) NE(${_routeBounds!.northEast.latitude}, ${_routeBounds!.northEast.longitude})',
        );
        debugPrint(
          '✅ RideConfirmationScreen: Using provided polyline (${points.length} points)',
        );
        return;
      }
    }

    // Fallback: straight line between pickup and dropoff (synchronous)
    debugPrint(
      '⚠️ RideConfirmationScreen: No polyline provided, using straight line',
    );
    _routePoints = [
      lat_lng.LatLng(
        (pickupCoords[1] as num).toDouble(),
        (pickupCoords[0] as num).toDouble(),
      ),
      lat_lng.LatLng(
        (dropoffCoords[1] as num).toDouble(),
        (dropoffCoords[0] as num).toDouble(),
      ),
    ];
    _routeBounds = fmap.LatLngBounds.fromPoints(_routePoints);
  }

  /// Refetch the route with the ride's stops as waypoints so the map
  /// traces pickup → stops → dropoff (same JSON, richer polyline).
  Future<void> _refetchRouteWithStops() async {
    try {
      final pickupCoords = widget.pickupLocation['coordinates'] as List;
      final dropoffCoords = widget.dropoffLocation['coordinates'] as List;
      final directions = await _placesService.getDirections(
        (pickupCoords[1] as num).toDouble(),
        (pickupCoords[0] as num).toDouble(),
        (dropoffCoords[1] as num).toDouble(),
        (dropoffCoords[0] as num).toDouble(),
        stops: widget.stops,
      );
      if (!mounted) return;
      if (directions != null &&
          directions['polyline'] is List &&
          (directions['polyline'] as List).isNotEmpty) {
        final points = (directions['polyline'] as List).map((p) {
          final m = Map<String, dynamic>.from(p as Map);
          return lat_lng.LatLng(
            (m['lat'] as num).toDouble(),
            (m['lng'] as num).toDouble(),
          );
        }).toList();
        setState(() {
          _routePoints = points;
          _routeBounds = fmap.LatLngBounds.fromPoints(points);
        });
        debugPrint(
          '✅ RideConfirmationScreen: Multi-stop route loaded (${points.length} pts, ${widget.stops!.length} stops)',
        );
      }
    } catch (e) {
      debugPrint('⚠️ RideConfirmationScreen: waypoint refetch failed: $e');
    }
  }

  Future<void> _fetchDirectionsAndFare() async {
    debugPrint('🚀 RideConfirmationScreen: Initializing fare fetch...');
    setState(() {
      _isFetchingFare = true;
      _fareError = null; // Clear any previous error
    });

    try {
      final pickupLat = widget.pickupLocation['coordinates'][1];
      final pickupLng = widget.pickupLocation['coordinates'][0];
      final dropoffLat = widget.dropoffLocation['coordinates'][1];
      final dropoffLng = widget.dropoffLocation['coordinates'][0];

      final result = await _placesService.getDistanceAndFare(
        originLat: pickupLat,
        originLng: pickupLng,
        destLat: dropoffLat,
        destLng: dropoffLng,
        categorySlug: widget.categorySlug,
      );

      if (mounted && result != null) {
        setState(() {
          _dynamicFareData = result;
          _isFetchingFare = false;
          _fareError = null;
        });
        debugPrint(
          '✅ RideConfirmationScreen: Dynamic fare fetched: £${_dynamicFareData!['total_fare']}',
        );
      } else if (mounted) {
        setState(() {
          _isFetchingFare = false;
          _fareError =
              'Unable to calculate fare for this route. Please try a different location.';
        });
        debugPrint(
          '❌ RideConfirmationScreen: Fare API returned null - cannot proceed',
        );
      }
    } catch (e) {
      debugPrint('❌ RideConfirmationScreen: Error fetching fare: $e');
      if (mounted) {
        setState(() {
          _isFetchingFare = false;
          _fareError =
              'Failed to calculate fare. Please check your connection and try again.';
        });
      }
    }
  }

  /// Retry fetching fare after an error
  void _retryFetchFare() {
    _fetchDirectionsAndFare();
  }

  void _showScheduleSheet() {
    // Preserve last picked time across webview cancel; fall back to
    // pre-set time, otherwise default to minimum lead time
    // (5 min dev, 2 hours prod).
    final initialTime = _lastScheduledTime ??
        widget.scheduledDateTime ??
        DateTime.now().add(
          AppConstants.isDev
              ? const Duration(minutes: 5)
              : const Duration(hours: 2),
        );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ScheduleRideSheet(
        initialDateTime: initialTime,
        onSchedule: (SchedulePayload payload) {
          _selectedPaymentMethod = payload.paymentMethod;
          _lastScheduledTime =
              DateTime.parse(payload.pickupTime).toLocal();
          // Payment switched after a cancelled webview → update existing ride
          if (_pendingScheduledRideId != null) {
            _switchScheduledPayment(_pendingScheduledRideId!, payload);
            return;
          }
          _processBooking(
            PaymentTiming.payNow,
            scheduledAt: DateTime.parse(payload.pickupTime),
            notes: payload.note,
            paymentMethod: payload.paymentMethod,
          );
        },
      ),
    );
  }

  Map<String, dynamic> get _currentFareData =>
      _dynamicFareData ?? widget.fareData;

  String get _pickupAddress =>
      widget.pickupLocation['address'] ?? 'Pickup Location';
  String get _dropoffAddress =>
      widget.dropoffLocation['address'] ?? 'Dropoff Location';

  double get _fare =>
      (_currentFareData['total_fare'] != null &&
          _currentFareData['total_fare'] is num)
      ? (_currentFareData['total_fare'] as num).toDouble()
      : 0.0;

  String get _distanceText => _currentFareData['distance_text'] ?? '';
  String get _durationText => _currentFareData['duration_text'] ?? '';
  int get _durationSeconds => _currentFareData['duration_seconds'] ?? 0;

  String get _estimatedArrival {
    final now = DateTime.now();
    final arrival = now.add(Duration(seconds: _durationSeconds));
    return DateFormat('h:mm a').format(arrival);
  }

  Future<void> _confirmRide() async {
    // Proceed with Pay Later (Auth now, charge later) by default
    _processBooking(PaymentTiming.payLater);

    /* Original Pay Now / Pay Later selection logic - Commented for future iteration
    // Show payment choice popup
    final PaymentTiming?
    selectedTiming = await showModalBottomSheet<PaymentTiming>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
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
              const Text(
                'Choose Payment Option',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 24),

              // Pay Now Option
              _buildPopupOption(
                context,
                title: 'Pay Now',
                subtitle:
                    'Pay £${_fare.toStringAsFixed(2)} immediately via Stripe',
                icon: Icons.flash_on,
                color: Colors.orange,
                value: PaymentTiming.payNow,
              ),

              const SizedBox(height: 12),

              // Pay Later Option
              _buildPopupOption(
                context,
                title: 'Pay After Ride',
                subtitle: 'Authorize card now, charge after completion',
                icon: Icons.schedule,
                color: Colors.blue,
                value: PaymentTiming.payLater,
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: Text(
                  'Your payment is securely processed by Stripe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selectedTiming != null) {
      _processBooking(selectedTiming);
    }
    */
  }

  Future<void> _confirmPrebook() async {
    // Time + payment already chosen on previous sheet → confirm directly.
    // A pending unpaid ride exists after webview cancel → switch method on it.
    if (widget.scheduledDateTime != null) {
      if (_pendingScheduledRideId != null) {
        _switchScheduledPayment(
          _pendingScheduledRideId!,
          SchedulePayload(
            pickupTime: widget.scheduledDateTime!.toUtc().toIso8601String(),
            paymentMethod: _selectedPaymentMethod,
          ),
        );
        return;
      }
      _processBooking(
        PaymentTiming.payNow,
        scheduledAt: widget.scheduledDateTime,
        notes: '',
        paymentMethod: _selectedPaymentMethod,
      );
      return;
    }
    _showScheduleSheet();
  }

  /* Commented out for now - used in _confirmRide's bottom sheet
  Widget _buildPopupOption(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required PaymentTiming value,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(context, value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[200]!),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
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
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
  */

  Future<void> _processBooking(
    PaymentTiming timing, {
    DateTime? scheduledAt,
    String? notes,
    String? paymentMethod,
  }) async {
    debugPrint(
      '🚀 RideConfirmationScreen: Processing booking with timing: $timing',
    );
    setState(() {
      _paymentTiming = timing;
      _isLoading = true;
    });

    try {
      final distanceMiles =
          _currentFareData['distance_miles'] ??
          ((_currentFareData['distance_meters'] ?? 0) * 0.000621371);

      // Use PaymentService to handle both API call and Stripe payment sheet
      final result = await PaymentService.bookRideWithPayment(
        context: context,
        pickupLocation: widget.pickupLocation,
        dropoffLocation: widget.dropoffLocation,
        vehicleCategorySlug: widget.categorySlug,
        distance: (distanceMiles as num).toDouble(),
        fare: _fare,
        paymentTiming: timing,
        scheduledAt: scheduledAt,
        notes: notes,
        stops: widget.stops?.isNotEmpty == true ? widget.stops : null,
        paymentMethod: paymentMethod,
      );

      if (mounted) {
        if (result.success && result.data != null) {
          final rideId =
              result.data!['_id']?.toString() ??
              result.data!['rideId']?.toString() ??
              '';

          debugPrint('✅ [RideConfirmationScreen] Ride created: $rideId');

          if (scheduledAt != null) {
            // Cash (no paymentUrl) → confirm directly.
            // Payment Link → open webview first; mark scheduled only after success.
            final paymentUrl = result.data!['paymentUrl']?.toString();
            if (paymentUrl != null && paymentUrl.isNotEmpty) {
              _pendingScheduledRideId = rideId;
              await _handleScheduledPayment(
                rideId: rideId,
                paymentUrl: paymentUrl,
                scheduledAt: scheduledAt,
              );
            } else {
              _pendingScheduledRideId = null;
              Provider.of<AuthProvider>(context, listen: false).markRideAsScheduled(rideId);
              setState(() => _isLoading = false);
              _showPreBookingSuccess(rideId, scheduledAt);
            }
            return;
          }

          debugPrint(
            '🚀 [RideConfirmationScreen] Navigating directly to RideAssignedScreen',
          );

          // Navigate DIRECTLY to RideAssignedScreen
          // The screen will show "searching for driver" state and handle socket events there
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => RideAssignedScreen(
                rideId: rideId,
                driver: null, // No driver yet - will come via socket
                pickup: widget.pickupLocation,
                dropoff: widget.dropoffLocation,
                fare: _fare,
                paymentTiming: timing == PaymentTiming.payNow
                    ? 'pay_now'
                    : 'pay_later',
                clientSecret: result.data!['clientSecret']?.toString(),
                stops: widget.stops,
              ),
            ),
          );
        } else {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'Failed to book ride'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ RideConfirmationScreen: Error scaling booking: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating booking: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleScheduledPayment({
    required String rideId,
    required String paymentUrl,
    required DateTime scheduledAt,
  }) async {
    try {
      final webViewResult = await Navigator.of(context)
          .push<Map<String, dynamic>>(
            MaterialPageRoute(
              builder: (_) =>
                  PaymentWebViewScreen(paymentUrl: paymentUrl, rideId: rideId),
            ),
          );

      final success = webViewResult?['success'] == true;

      if (success) {
        // Payment successful — mark scheduled and show success
        if (mounted) {
          _pendingScheduledRideId = null;
          Provider.of<AuthProvider>(context, listen: false).markRideAsScheduled(rideId);
          setState(() => _isLoading = false);
          _showPreBookingSuccess(rideId, scheduledAt);
        }
      } else {
        // Cancelled — back to schedule sheet so user can pick another option
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Payment cancelled. Your booking is not confirmed yet.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          _showScheduleSheet();
        }
      }
    } catch (e) {
      debugPrint('❌ _handleScheduledPayment: Error: $e');
    }
  }

  /// Switch payment method on an existing unpaid scheduled ride
  /// (after webview cancel) instead of creating a duplicate ride.
  Future<void> _switchScheduledPayment(
    String rideId,
    SchedulePayload payload,
  ) async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.selectPaymentMethod(
        rideId,
        payload.paymentMethod,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        final data = res['data'];
        final ride = data is Map ? (data['ride'] ?? data) : null;
        final url = ride is Map ? ride['paymentUrl']?.toString() : null;
        final scheduledAt = DateTime.parse(payload.pickupTime);
        if (url != null && url.isNotEmpty) {
          await _handleScheduledPayment(
            rideId: rideId,
            paymentUrl: url,
            scheduledAt: scheduledAt,
          );
        } else {
          _pendingScheduledRideId = null;
          Provider.of<AuthProvider>(context, listen: false)
              .markRideAsScheduled(rideId);
          setState(() => _isLoading = false);
          _showPreBookingSuccess(rideId, scheduledAt);
        }
      } else {
        // Backend rejected switch — cancel stale unpaid ride, then fresh create
        await _apiService.cancelScheduledRideUser(
          rideId,
          reason: 'Payment method changed',
        );
        _pendingScheduledRideId = null;
        _processBooking(
          PaymentTiming.payNow,
          scheduledAt: DateTime.parse(payload.pickupTime),
          notes: payload.note,
          paymentMethod: payload.paymentMethod,
        );
      }
    } catch (_) {
      // Network error — cancel stale unpaid ride, then fresh create
      await _apiService.cancelScheduledRideUser(
        rideId,
        reason: 'Payment method changed',
      );
      _pendingScheduledRideId = null;
      if (mounted) {
        _processBooking(
          PaymentTiming.payNow,
          scheduledAt: DateTime.parse(payload.pickupTime),
          notes: payload.note,
          paymentMethod: payload.paymentMethod,
        );
      }
    }
  }

  void _showPreBookingSuccess(String rideId, DateTime scheduledAt) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Column(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 64),
            SizedBox(height: 16),
            Text('Ride Scheduled!', textAlign: TextAlign.center),
          ],
        ),
        content: Text(
          'Your ride for ${DateFormat('MMM dd, h:mm a').format(scheduledAt)} has been confirmed. A driver will be assigned closer to the time.',
          textAlign: TextAlign.center,
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                // Close dialog and pop back to home screen
                // Pop dialog
                Navigator.of(context).pop();
                // Pop RideConfirmationScreen
                Navigator.of(context).pop();
                // Pop Destination Search / Airport Selection screen
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Back to Home',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Confirm Ride',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Map Snapshot
                  _buildMapSnapshot(),

                  const SizedBox(height: 16),

                  // Route Card
                  _buildRouteCard(),

                  const SizedBox(height: 16),

                  // Scheduled Ride Details (if applicable)
                  if (widget.scheduledDateTime != null) ...[
                    _buildScheduledRideCard(),
                    const SizedBox(height: 16),
                  ],

                  // Vehicle Card
                  _buildVehicleCard(),

                  const SizedBox(height: 16),

                  // Trip Details Card
                  _buildTripDetailsCard(),
                ],
              ),
            ),
          ),

          // Bottom Confirm Button
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildRouteCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          // Pickup
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PICKUP',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _pickupAddress,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Dotted line
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Row(
              children: [
                Column(
                  children: List.generate(
                    3,
                    (index) => Container(
                      width: 2,
                      height: 6,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: Colors.grey[300],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Intermediate stops (visible in fare + trip)
          if (widget.stops?.isNotEmpty == true)
            ...widget.stops!.asMap().entries.map((entry) {
              final i = entry.key;
              final stop = entry.value;
              return Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          stop['address']?.toString() ?? 'Stop ${i + 1}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: Row(
                      children: [
                        Column(
                          children: List.generate(
                            3,
                            (index) => Container(
                              width: 2,
                              height: 6,
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              color: Colors.grey[300],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),

          // Dropoff
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DROP-OFF',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _dropoffAddress,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build a static map snapshot showing the route from pickup to dropoff
  Widget _buildMapSnapshot() {
    final pickupCoords = widget.pickupLocation['coordinates'] as List;
    final dropoffCoords = widget.dropoffLocation['coordinates'] as List;

    debugPrint('🗺️ RideConfirmationScreen: Building static map snapshot');
    debugPrint('   → Route points: ${_routePoints.length}');

    final markers = [
      MapMarker(
        id: 'pickup',
        lat: pickupCoords[1],
        lng: pickupCoords[0],
        title: 'Pickup',
        markerColor: Colors.green, // Green marker for pickup
      ),
      // Numbered intermediate stops (Uber/Bolt style).
      ...RouteMapHelpers.stopMarkers(widget.stops ?? const []),
      MapMarker(
        id: 'dropoff',
        lat: dropoffCoords[1],
        lng: dropoffCoords[0],
        title: 'Dropoff',
        markerColor: Colors.red, // Red marker for dropoff
      ),
    ];

    return Container(
      height: 200, // Slightly taller for better visibility
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: PlatformMap(
          initialLat: pickupCoords[1],
          initialLng: pickupCoords[0],
          markers: markers,
          polylines: _routePoints.isNotEmpty
              ? RouteMapHelpers.routePolylines(
                  _routePoints,
                  color: AppTheme.primaryColor,
                )
              : [],
          bounds: _routeBounds,
          interactive: false,
        ),
      ),
    );
  }

  Widget _buildScheduledRideCard() {
    final formattedTime = widget.scheduledDateTime != null
        ? DateFormat('h:mm a').format(widget.scheduledDateTime!)
        : '';
    final formattedDate = widget.scheduledDateTime != null
        ? DateFormat('MMM d, yyyy').format(widget.scheduledDateTime!)
        : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                color: AppTheme.primaryColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Scheduled Ride',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Payment required to confirm',
                      style: TextStyle(fontSize: 12, color: AppTheme.primaryColor, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Departure Time',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formattedTime,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 40, color: Colors.grey[300]),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Date',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard() {
    IconData vehicleIcon;
    final slug = widget.categorySlug.toLowerCase();
    if (slug.contains('suv')) {
      vehicleIcon = Icons.directions_car_filled;
    } else if (slug.contains('hatchback')) {
      vehicleIcon = Icons.car_rental;
    } else if (slug.contains('van') || slug.contains('bus')) {
      vehicleIcon = Icons.airport_shuttle;
    } else {
      vehicleIcon = Icons.directions_car;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(vehicleIcon, size: 32, color: AppTheme.primaryColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.categoryName == widget.categorySlug ||
                          widget.categoryName == 'Unknown'
                      ? VehicleCategory.formatSlug(widget.categorySlug)
                      : widget.categoryName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                _isFetchingFare
                    ? Container(
                        margin: const EdgeInsets.only(top: 4),
                        width: 100,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      )
                    : Text(
                        'Estimated arrival: $_estimatedArrival',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trip Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            Icons.straighten,
            'Distance',
            _isFetchingFare ? '...' : _distanceText,
          ),
          const Divider(height: 24),
          _buildDetailRow(
            Icons.access_time,
            'Duration',
            _isFetchingFare ? '...' : _durationText,
          ),
          const Divider(height: 24),
          _buildDetailRow(
            Icons.schedule,
            'ETA',
            _isFetchingFare ? '...' : _estimatedArrival,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    // Check if there's a fare error
    final hasError = _fareError != null;

    return Container(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Error Message (if any)
            if (hasError) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.red.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _fareError!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Fare Row (only show if no error)
            if (!hasError)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Fare',
                    style: TextStyle(fontSize: 16, color: AppTheme.textPrimary),
                  ),
                  _isFetchingFare
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryColor,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (_currentFareData['promo_applied'] == true &&
                                _currentFareData['original_fare'] != null) ...[
                              Text(
                                '£${(_currentFareData['original_fare'] as num).toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _fare == 0
                                        ? 'FREE'
                                        : '£${_fare.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: _fare == 0
                                          ? AppTheme.successColor
                                          : AppTheme.primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.card_giftcard,
                                    size: 20,
                                    color: AppTheme.successColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '-£${(_currentFareData['discount'] as num? ?? 0).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.successColor,
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              Text(
                                '£${_fare.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                ],
              ),

            if (!hasError) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Note: Final fare may vary based on actual distance traveled (e.g. if the ride ends early).',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Button Row
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: hasError
                      ? ElevatedButton.icon(
                          onPressed: _isFetchingFare ? null : _retryFetchFare,
                          icon: _isFetchingFare
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _isFetchingFare ? 'Retrying...' : 'Retry',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        )
                      : ElevatedButton(
                          onPressed: (_isLoading || _isFetchingFare)
                              ? null
                              : (widget.isScheduled &&
                                    widget.scheduledDateTime != null)
                              ? _confirmPrebook
                              : _confirmRide,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
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
                                    // Change button text based on whether it's a prebooked ride
                                    (widget.isScheduled &&
                                            widget.scheduledDateTime != null)
                                        ? 'Confirm Prebook'
                                        : 'Confirm Ride',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                        ),
                ),
                // Only show "Schedule for Later" button if NOT a prebooked ride
                if (!hasError &&
                    !(widget.isScheduled &&
                        widget.scheduledDateTime != null)) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: (_isLoading || _isFetchingFare)
                          ? null
                          : _showScheduleSheet,
                      icon: const Icon(Icons.calendar_month),
                      label: const Text(
                        'Prebook',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                        side: const BorderSide(color: Colors.blue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
