import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../core/api_service.dart';
import '../../core/services/payment_service.dart';
import '../../core/models/outstanding_balance.dart';
import '../ride/outstanding_balance_screen.dart';
import '../ride/payment_webview_screen.dart';
import 'widgets/stops_editor_widget.dart';
import 'widgets/schedule_ride_sheet.dart';

class ConfirmBookingScreen extends StatefulWidget {
  const ConfirmBookingScreen({super.key});

  @override
  State<ConfirmBookingScreen> createState() => _ConfirmBookingScreenState();
}

class _ConfirmBookingScreenState extends State<ConfirmBookingScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  final TextEditingController _notesController = TextEditingController();
  PaymentTiming _paymentTiming = PaymentTiming.payLater;
  // Mandatory upfront method selector (11-02): 'cash' or 'payment_link'.
  String _selectedPaymentMethod = 'cash';
  List<Map<String, dynamic>> _stops = [];
  // Pending unpaid scheduled ride — switch payment via select-payment, no duplicate create.
  String? _pendingScheduledRideId;
  // Last time picked in the sheet — reused as sheet initial so cancel keeps it.
  DateTime? _lastScheduledTime;

  Future<void> _confirmBooking(
    Map<String, dynamic> vehicle,
    Map<String, dynamic> destination,
    Map<String, dynamic>? pickup,
  ) async {
    setState(() => _isLoading = true);

    try {
      // Prepare location data
      final pickupLocation = pickup != null
          ? {
              'coordinates': [
                pickup['lng'] ?? -0.1278,
                pickup['lat'] ?? 51.5074,
              ],
              'address':
                  pickup['name'] ?? pickup['address'] ?? 'Current Location',
            }
          : {
              'coordinates': [-0.1278, 51.5074],
              'address': 'Current Location',
            };

      final dropoffLocation = {
        'coordinates': [
          destination['lng'] ?? -0.1240,
          destination['lat'] ?? 51.5100,
        ],
        'address':
            destination['name'] ?? destination['address'] ?? 'Destination',
      };

      // Use PaymentService for Stripe payment flow
      final result = await PaymentService.bookRideWithPayment(
        context: context,
        pickupLocation: pickupLocation,
        dropoffLocation: dropoffLocation,
        vehicleCategorySlug: vehicle['categorySlug'] ?? 'sedan',
        distance: (vehicle['distance'] as num?)?.toDouble() ?? 5.0,
        fare: (vehicle['basePrice'] as num?)?.toDouble() ?? 15.0,
        paymentMethod: _selectedPaymentMethod,
        paymentTiming: _paymentTiming,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
        stops: _stops.isNotEmpty ? _stops : null,
      );

      setState(() => _isLoading = false);

      if (result.success && mounted) {
        // Upfront contract (11-02): link opens WebView immediately, cash
        // goes straight to the success dialog (this screen uses dialogs,
        // not a RideAssigned push — preserved).
        final dataMethod =
            result.data?['paymentMethod']?.toString() ?? _selectedPaymentMethod;
        final isLink = dataMethod == 'payment_link' ||
            _selectedPaymentMethod == 'payment_link';
        if (isLink) {
          final paymentUrl = result.data?['paymentUrl']?.toString();
          if (paymentUrl == null || paymentUrl.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Payment link missing. Please try again or choose Cash.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }
          final rideId =
              result.data!['_id']?.toString() ??
              result.data!['rideId']?.toString() ??
              '';
          final webViewResult = await Navigator.of(context)
              .push<Map<String, dynamic>>(
                MaterialPageRoute(
                  builder: (_) => PaymentWebViewScreen(
                    paymentUrl: paymentUrl,
                    rideId: rideId,
                  ),
                ),
              );
          if (!mounted) return;
          if (webViewResult?['success'] == true) {
            _showSuccessDialog(
              result.message ?? 'Booking confirmed!',
              result.data,
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Payment cancelled. Your booking is not confirmed yet.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        // Show success message
        _showSuccessDialog(result.message ?? 'Booking confirmed!', result.data);
      } else if (!result.success && mounted) {
        // 403 outstanding-balance block (payment-flow.md §7): redirect to
        // the balance screen instead of a dead-end error dialog.
        if (result.isBalanceBlocked) {
          _openBalanceBlocked(
            rideId: result.data?['rideId']?.toString(),
            amount: (result.data?['outstandingBalance'] as num?)?.toDouble(),
            message: result.error,
          );
        } else if (result.data?['missingPaymentMethod'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please choose a payment method (Online or Cash).',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          _showErrorDialog(result.error ?? 'Payment failed');
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        _showErrorDialog(e.toString());
      }
    }
  }

  /// Handle scheduled ride creation and payment routing.
  ///
  /// Flow: ScheduleSheet → API → paymentUrl → WebView, or noUrl → success.
  /// Cancel returns user to payment selection without duplicate create.
  Future<void> _handleScheduleRide(
    SchedulePayload payload,
    Map<String, dynamic> vehicle,
    Map<String, dynamic> destination,
    Map<String, dynamic>? pickup,
  ) async {
    setState(() => _isLoading = true);

    try {
      final pickupLocation = pickup != null
          ? {
              'coordinates': [
                pickup['lng'] ?? -0.1278,
                pickup['lat'] ?? 51.5074,
              ],
              'address':
                  pickup['name'] ?? pickup['address'] ?? 'Current Location',
            }
          : {
              'coordinates': [-0.1278, 51.5074],
              'address': 'Current Location',
            };

      final dropoffLocation = {
        'coordinates': [
          destination['lng'] ?? -0.1240,
          destination['lat'] ?? 51.5100,
        ],
        'address':
            destination['name'] ?? destination['address'] ?? 'Destination',
      };

      final result = await PaymentService.bookRideWithPayment(
        context: context,
        pickupLocation: pickupLocation,
        dropoffLocation: dropoffLocation,
        vehicleCategorySlug: vehicle['categorySlug'] ?? 'sedan',
        distance: (vehicle['distance'] as num?)?.toDouble() ?? 5.0,
        fare: (vehicle['basePrice'] as num?)?.toDouble() ?? 15.0,
        paymentTiming: PaymentTiming.payNow,
        scheduledAt: DateTime.parse(payload.pickupTime),
        notes: payload.note,
        stops: payload.stops.isNotEmpty ? payload.stops : null,
        paymentMethod: payload.paymentMethod,
      );

      if (!mounted) return;

      if (result.success && result.data != null) {
        final rideId =
            result.data!['_id']?.toString() ??
            result.data!['rideId']?.toString() ??
            '';

        // Route payment: paymentUrl → WebView, else show success
        final paymentUrl = result.data!['paymentUrl']?.toString();
        if (paymentUrl != null && paymentUrl.isNotEmpty) {
          _pendingScheduledRideId = rideId;
          await _handleScheduledPayment(
            rideId: rideId,
            paymentUrl: paymentUrl,
            vehicle: vehicle,
            destination: destination,
            pickup: pickup,
          );
        } else {
          _pendingScheduledRideId = null;
          setState(() => _isLoading = false);
          _showSuccessDialog(
            result.message ?? 'Scheduled ride created!',
            result.data,
            isScheduled: true,
          );
        }
      } else {
        setState(() => _isLoading = false);
        if (result.isBalanceBlocked) {
          _openBalanceBlocked(
            rideId: result.data?['rideId']?.toString(),
            amount: (result.data?['outstandingBalance'] as num?)?.toDouble(),
            message: result.error,
          );
        } else {
          _showErrorDialog(result.error ?? 'Failed to create scheduled ride');
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        _showErrorDialog(e.toString());
      }
    }
  }

  /// Open Payment WebView for scheduled full payment. On success show confirmation;
  /// on cancel return user to payment selection (no duplicate ride create).
  Future<void> _handleScheduledPayment({
    required String rideId,
    required String paymentUrl,
    Map<String, dynamic>? vehicle,
    Map<String, dynamic>? destination,
    Map<String, dynamic>? pickup,
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

      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          _pendingScheduledRideId = null;
          _showSuccessDialog(
            'Scheduled ride confirmed! Payment completed.',
            {'_id': rideId, 'success': true},
            isScheduled: true,
          );
        } else {
          // Cancelled — back to schedule sheet so user can pick another option
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Payment cancelled. Your booking is not confirmed yet.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          if (vehicle != null && destination != null) {
            _showScheduleSheet(vehicle, destination, pickup);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ _handleScheduledPayment: Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Switch payment method on existing unpaid scheduled ride
  /// instead of creating a duplicate ride.
  Future<void> _switchScheduledPayment(
    String rideId,
    SchedulePayload payload,
    Map<String, dynamic> vehicle,
    Map<String, dynamic> destination,
    Map<String, dynamic>? pickup,
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
        if (url != null && url.isNotEmpty) {
          await _handleScheduledPayment(
            rideId: rideId,
            paymentUrl: url,
            vehicle: vehicle,
            destination: destination,
            pickup: pickup,
          );
        } else {
          _pendingScheduledRideId = null;
          setState(() => _isLoading = false);
          _showSuccessDialog(
            'Scheduled ride confirmed! Payment completed.',
            {'_id': rideId, 'success': true},
            isScheduled: true,
          );
        }
      } else {
        // Backend rejected switch — cancel stale unpaid ride, then fresh create
        await _apiService.cancelScheduledRideUser(
          rideId,
          reason: 'Payment method changed',
        );
        _pendingScheduledRideId = null;
        _handleScheduleRide(payload, vehicle, destination, pickup);
      }
    } catch (_) {
      _pendingScheduledRideId = null;
      if (mounted) {
        await _apiService.cancelScheduledRideUser(
          rideId,
          reason: 'Payment method changed',
        );
        _handleScheduleRide(payload, vehicle, destination, pickup);
      }
    }
  }

  /// 403 outstanding-balance block (payment-flow.md §7): fetch the live
  /// balance and open the balance screen. Falls back to the known amount
  /// when the re-fetch has no link yet. When the block carries no rideId,
  /// resolves it via the global balance endpoint before giving up.
  Future<void> _openBalanceBlocked({
    String? rideId,
    double? amount,
    String? message,
  }) async {
    if (rideId == null || rideId.isEmpty) {
      try {
        final global = await _apiService.getGlobalPaymentBalance();
        final resolved = global['success'] == true
            ? OutstandingBalance.fromBalanceEnvelope(global, '')
            : null;
        if (resolved != null &&
            resolved.isOwed &&
            resolved.rideId.isNotEmpty) {
          rideId = resolved.rideId;
          amount ??= resolved.amount;
        }
      } catch (_) {}
    }
    if (rideId == null || rideId.isEmpty) {
      _showErrorDialog(message ?? 'Please clear your balance before booking.');
      return;
    }
    OutstandingBalance balance = OutstandingBalance(
      rideId: rideId,
      amount: amount ?? 0,
      status: 'balance_due',
      message: message ?? 'Please clear your balance before booking a new ride.',
    );
    try {
      final res = await _apiService.getPaymentBalance(rideId);
      final parsed = res['success'] == true
          ? OutstandingBalance.fromBalanceEnvelope(res, rideId)
          : null;
      if (parsed != null) balance = parsed;
    } catch (_) {}
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OutstandingBalanceScreen(balance: balance),
      ),
    );
  }

  // Compact ride-hail payment row (11.1 parity): single tappable row,
  // expands inline to Online / Cash. Writes [_selectedPaymentMethod].
  bool _isPaymentExpanded = false;

  String get _selectedPaymentLabel =>
      _selectedPaymentMethod == 'payment_link' ? 'Online' : 'Cash';

  IconData get _selectedPaymentIcon =>
      _selectedPaymentMethod == 'payment_link'
          ? Icons.credit_card
          : Icons.money;

  /// Mandatory upfront payment selector (11-02): Online (Card via Link)
  /// vs Cash. File-local compact segmented widget (no shared extract).
  Widget _buildPaymentMethodSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () =>
                setState(() => _isPaymentExpanded = !_isPaymentExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Icon(
                    _selectedPaymentIcon,
                    size: 18,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedPaymentLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    _selectedPaymentMethod == 'payment_link'
                        ? 'Card via Link'
                        : 'Pay driver',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _isPaymentExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right,
                      color: Colors.grey[500],
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isPaymentExpanded) ...[
            Divider(height: 1, color: Colors.grey[200]),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: _buildPaymentMethodOption(
                      icon: Icons.credit_card,
                      label: 'Online',
                      value: 'payment_link',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildPaymentMethodOption(
                      icon: Icons.money,
                      label: 'Cash',
                      value: 'cash',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentMethodOption({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final isSelected = _selectedPaymentMethod == value;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedPaymentMethod = value;
        _isPaymentExpanded = false;
        _paymentTiming =
            value == 'payment_link' ? PaymentTiming.payNow : PaymentTiming.payLater;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey[200]!,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppTheme.primaryColor : Colors.grey[600],
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w500,
                  color:
                      isSelected ? AppTheme.primaryColor : Colors.grey[700],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessDialog(
    String message,
    Map<String, dynamic>? rideData, {
    bool isScheduled = false,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Success'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (isScheduled) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/home',
                  (route) => false,
                );
                return;
              }
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/ride-assigned',
                (route) => false,
                arguments: rideData ?? {'success': true},
              );
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Payment Failed'),
          ],
        ),
        content: Text(error),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  /// Open schedule sheet, then create scheduled ride on confirm.
  void _showScheduleSheet(
    Map<String, dynamic> vehicle,
    Map<String, dynamic> destination,
    Map<String, dynamic>? pickup,
  ) {
    final now = DateTime.now();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ScheduleRideSheet(
        initialDateTime: _lastScheduledTime ??
            now.add(
              AppConstants.isDev
                  ? const Duration(minutes: 5)
                  : const Duration(hours: 2),
            ),
        stops: _stops,
        onSchedule: (SchedulePayload payload) {
          _lastScheduledTime =
              DateTime.parse(payload.pickupTime).toLocal();
          // Payment switched after cancel → update existing ride, no duplicate
          if (_pendingScheduledRideId != null) {
            _switchScheduledPayment(
              _pendingScheduledRideId!,
              payload,
              vehicle,
              destination,
              pickup,
            );
            return;
          }
          _handleScheduleRide(payload, vehicle, destination, pickup);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final vehicle = args?['vehicle'];
    final destinationArg = args?['destination'];

    final Map<String, dynamic> destination;
    if (destinationArg is Map<String, dynamic>) {
      destination = destinationArg;
    } else if (destinationArg is String) {
      destination = {'name': destinationArg, 'address': ''};
    } else {
      destination = {'name': 'Unknown destination', 'address': ''};
    }

    if (vehicle == null) {
      return const Scaffold(
        body: Center(child: Text('Error: Missing booking details')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Confirm Booking',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Map Snapshot (Mock)
          SizedBox(
            height: 200,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: const LatLng(51.5085, -0.1260),
                initialZoom: 14.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.mokshasolutions.mktours',
                ),
                MarkerLayer(
                  markers: [
                    const Marker(
                      point: LatLng(51.5074, -0.1278),
                      width: 20,
                      height: 20,
                      child: Icon(Icons.my_location, color: Colors.blue),
                    ),
                    const Marker(
                      point: LatLng(51.5100, -0.1240),
                      width: 30,
                      height: 30,
                      child: Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 30,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Trip Details
                  Row(
                    children: [
                      Column(
                        children: [
                          const Icon(
                            Icons.my_location,
                            color: Colors.blue,
                            size: 16,
                          ),
                          Container(
                            height: 24,
                            width: 2,
                            color: Colors.grey[300],
                          ),
                          const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 16,
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Current Location',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              destination['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Intermediate stops (max 3) — passed into fare +
                  // createRide so stops are priced and visible in-trip.
                  StopsEditorWidget(
                    onChanged: (stops) {
                      setState(() => _stops = stops);
                    },
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Vehicle Info
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.local_taxi,
                          color: AppTheme.primaryColor,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vehicle['name'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            '12:05 PM drop-off',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        '£${vehicle['basePrice']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Notes
                  TextField(
                    controller: _notesController,
                    decoration: InputDecoration(
                      hintText: 'Add a note for driver...',
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.edit_note),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Payment Info Box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'You will pay the driver via cash or payment link when the ride is completed.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Outstanding-balance transparency (Phase 15): backend
                  // total is authoritative — display the split only, never
                  // recompute. Tolerant num-or-string read, default 0 so
                  // legacy callers passing basePrice-only maps render
                  // pixel-identical to today.
                  Builder(
                    builder: (context) {
                      final raw = vehicle['outstanding_balance'] ??
                          vehicle['outstandingBalance'] ??
                          vehicle['excessAmount'] ??
                          0;
                      final balance = raw is num
                          ? raw.toDouble()
                          : double.tryParse('$raw') ?? 0.0;
                      if (balance <= 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.amber.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 18,
                                color: Colors.amber.shade800,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Includes £${balance.toStringAsFixed(2)} unpaid balance from a previous ride',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.amber.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // Mandatory payment selector (11-02) — above Confirm.
                  _buildPaymentMethodSelector(),
                ],
              ),
            ),
          ),

          // Compact bottom-sheet action card (11.1 parity): one full-width
          // Confirm CTA with price + Schedule as a small text-button.
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading
                            ? null
                            : () => _confirmBooking(
                                vehicle,
                                destination,
                                args?['pickup'],
                              ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Confirm Booking • £${((vehicle['basePrice'] as num?)?.toDouble() ?? 15.0).toStringAsFixed(2)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    SizedBox(
                      height: 32,
                      child: TextButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () => _showScheduleSheet(
                                vehicle, destination, args?['pickup']),
                        icon: const Icon(
                          Icons.calendar_month,
                          size: 14,
                        ),
                        label: const Text(
                          'Schedule for Later',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
    );
  }
}
