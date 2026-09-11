import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/models/scheduled_ride.dart';
import '../../core/services/payment_service.dart';
import '../../core/services/socket_service.dart';
import '../../core/widgets/custom_snackbar.dart';
import '../ride/payment_webview_screen.dart';
import '../ride/ride_progress_screen.dart';
import '../activity/ride_detail_screen.dart';

/// Screen showing the user's scheduled (pre-booked) rides with cancel option.
class ScheduledRidesScreen extends StatefulWidget {
  const ScheduledRidesScreen({super.key});

  @override
  State<ScheduledRidesScreen> createState() => _ScheduledRidesScreenState();
}

class _ScheduledRidesScreenState extends State<ScheduledRidesScreen> {
  List<ScheduledRide> _rides = [];
  bool _isLoading = true;
  final SocketService _socketService = SocketService();

  @override
  void initState() {
    super.initState();
    _fetchScheduledRides();
    // Quietly refresh the visible card when a driver accepts one of these
    // rides — no toast here, Home already toasted via its own listener.
    _socketService.on('ride:accepted', _onRideAccepted);
    // Same id-match pattern for driver-cancel: drop the cancelled driver
    // from the open Upcoming list without manual refresh. Home owns the
    // banner; this screen stays silent.
    _socketService.on(
      'ride:scheduledDriverCancelled',
      _onScheduledDriverCancelled,
    );
  }

  /// Socket `ride:accepted` handler: refresh in place when the accepted ride
  /// is one of the visible scheduled rides.
  void _onRideAccepted(dynamic data) {
    final acceptedId = data is Map
        ? (data['rideId'] ?? data['_id'])?.toString()
        : null;
    if (acceptedId == null || acceptedId.isEmpty || !mounted) return;
    final isVisible = _rides.any((r) => r.id == acceptedId);
    if (isVisible) _refreshSilently();
  }

  /// Socket `ride:scheduledDriverCancelled` handler: refresh in place when
  /// the cancelled ride is one of the visible scheduled rides, so the card
  /// reverts to unassigned without manual refresh. No toast, no navigation.
  void _onScheduledDriverCancelled(dynamic data) {
    final cancelledId = data is Map
        ? (data['rideId'] ?? data['_id'] ?? data['bookingId'])?.toString()
        : null;
    if (cancelledId == null || cancelledId.isEmpty || !mounted) return;
    final isVisible = _rides.any((r) => r.id == cancelledId);
    if (isVisible) _refreshSilently();
  }

  /// Refresh list data without toggling the full-screen loader, so the card
  /// updates in place while the user watches.
  Future<void> _refreshSilently() async {
    final rawRides = await PaymentService.getScheduledRides();
    if (mounted) {
      setState(() {
        _rides = rawRides
            .map((r) => ScheduledRide.fromJson(r))
            .toList();
      });
      _checkLiveHandoff();
    }
  }

  @override
  void dispose() {
    _socketService.off('ride:accepted');
    _socketService.off('ride:scheduledDriverCancelled');
    super.dispose();
  }

  Future<void> _fetchScheduledRides() async {
    setState(() => _isLoading = true);
    final rawRides = await PaymentService.getScheduledRides();
    if (mounted) {
      setState(() {
        _rides = rawRides
            .map((r) => ScheduledRide.fromJson(r))
            .toList();
        _isLoading = false;
      });
      _checkLiveHandoff();
    }
  }

  /// If any scheduled ride has status that's live and pickup time has passed,
  /// redirect to ride-progress screen.
  void _checkLiveHandoff() {
    final now = DateTime.now();
    for (final ride in _rides) {
      final isLiveStatus = ride.status == 'in_progress' ||
          ride.status == 'driver_arrived' ||
          ride.status == 'accepted';
      if (!isLiveStatus || ride.scheduledPickupTime == null) continue;

      try {
        final pickupTime = DateTime.parse(ride.scheduledPickupTime!).toLocal();
        if (now.isAfter(pickupTime) && mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => RideProgressScreen(
                rideId: ride.id,
                driver: ride.driver,
              ),
            ),
          );
          return;
        }
      } catch (_) {}
    }
  }

  void _showCancelDialog(ScheduledRide ride) {
    final depositStr = '£${ride.depositAmount.toStringAsFixed(2)}';
    String? selectedReason;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Cancel Scheduled Ride?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Cancellation policy:'),
              const SizedBox(height: 12),
              _policyRow(
                Icons.check_circle,
                Colors.green,
                'Within 4 hours of booking — free cancel',
              ),
              const SizedBox(height: 6),
              _policyRow(
                Icons.check_circle,
                Colors.green,
                'Pickup ≥ 2 hours away — free cancel',
              ),
              const SizedBox(height: 6),
              _policyRow(
                Icons.cancel,
                Colors.red,
                'Otherwise — deposit $depositStr forfeited',
              ),
              const SizedBox(height: 16),
              const Text(
                'Reason (optional):',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _reasonChip('Plan changed', selectedReason, (v) {
                    setDialogState(() => selectedReason = v);
                  }),
                  _reasonChip('Found alternative', selectedReason, (v) {
                    setDialogState(() => selectedReason = v);
                  }),
                  _reasonChip('No longer needed', selectedReason, (v) {
                    setDialogState(() => selectedReason = v);
                  }),
                  _reasonChip('Emergency', selectedReason, (v) {
                    setDialogState(() => selectedReason = v);
                  }),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Keep Ride'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _cancelRide(ride, reason: selectedReason);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Cancel Ride',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reasonChip(String label, String? selected, ValueChanged<String> onTap) {
    final isSelected = selected == label;
    return GestureDetector(
      onTap: () => onTap(isSelected ? '' : label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.1)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isSelected ? AppTheme.primaryColor : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  Widget _policyRow(IconData icon, Color color, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    );
  }

  // ignore: unused_element
  Future<void> _payDeposit(ScheduledRide ride) async {
    final rideId = ride.id;
    final paymentUrl = ride.payment.paymentUrl;

    if (paymentUrl == null || paymentUrl.isEmpty) {
      CustomSnackbar.show(
        context,
        message: 'Payment link not available. Please contact support.',
        type: SnackbarType.error,
      );
      return;
    }

    final socketService = SocketService();

    void onDepositConfirmed(dynamic data) {
      final confirmedId = data is Map
          ? (data['rideId'] ?? data['_id'])?.toString()
          : null;
      if (confirmedId == rideId) {
        if (mounted) {
          CustomSnackbar.show(
            context,
            message: data['message'] ?? 'Deposit paid! Your ride is confirmed.',
            type: SnackbarType.success,
          );
          _fetchScheduledRides();
        }
      }
    }

    socketService.on('ride:depositConfirmed', onDepositConfirmed);

    try {
      await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) =>
              PaymentWebViewScreen(paymentUrl: paymentUrl, rideId: rideId),
        ),
      );
      // Refresh regardless of WebView outcome — socket will update status if paid
      if (mounted) _fetchScheduledRides();
    } finally {
      socketService.off('ride:depositConfirmed');
    }
  }

  Future<void> _cancelRide(ScheduledRide ride, {String? reason}) async {
    final rideId = ride.id;

    // Optimistic UI — update status immediately
    setState(() {
      _rides = _rides.map((r) {
        if (r.id == rideId) {
          return ScheduledRide(
            id: r.id,
            pickupLocation: r.pickupLocation,
            dropoffLocation: r.dropoffLocation,
            stops: r.stops,
            vehicleCategorySlug: r.vehicleCategorySlug,
            fare: r.fare,
            status: 'cancelling',
            isScheduled: r.isScheduled,
            scheduledPickupTime: r.scheduledPickupTime,
            driver: r.driver,
            user: r.user,
            depositAmount: r.depositAmount,
            distance: r.distance,
            payment: r.payment,
          );
        }
        return r;
      }).toList();
    });

    try {
      final response = await PaymentService.cancelScheduledRideUser(
        rideId,
        reason: reason,
      );

      if (!mounted) return;

      final data = response['data'] as Map<String, dynamic>? ?? {};
      final refunded = data['depositRefunded'] == true;

      if (response['success'] == true) {
        CustomSnackbar.show(
          context,
          message: refunded
              ? 'Ride cancelled. Your deposit will be refunded.'
              : 'Ride cancelled. Your deposit has been forfeited as a cancellation fee.',
          type: refunded ? SnackbarType.success : SnackbarType.warning,
        );
        _fetchScheduledRides();
      } else {
        // Revert optimistic update on failure
        _fetchScheduledRides();
        CustomSnackbar.show(
          context,
          message: response['message'] ?? 'Failed to cancel ride',
          type: SnackbarType.error,
        );
      }
    } catch (e) {
      // Revert optimistic update on error
      _fetchScheduledRides();
      if (mounted) {
        CustomSnackbar.show(
          context,
          message: e.toString().replaceAll('Exception: ', ''),
          type: SnackbarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Scheduled Rides',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchScheduledRides,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _rides.isEmpty
            ? _buildEmpty()
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _rides.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) => _buildRideCard(_rides[index]),
              ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No scheduled rides',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
          Text(
            'Schedule a ride from the booking screen',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildRideCard(ScheduledRide ride) {
    final pickup = ride.pickupLocation.address.isNotEmpty
        ? ride.pickupLocation.address
        : 'Unknown Pickup';
    final dropoff = ride.dropoffLocation.address.isNotEmpty
        ? ride.dropoffLocation.address
        : 'Unknown Dropoff';
    final fare = ride.fare;
    final status = ride.status;
    final driverName = ride.driver is Map
        ? (ride.driver['name'] ?? '').toString()
        : '';
    final stopsCount = ride.stops.length;

    String scheduledTimeStr = '';
    if (ride.scheduledPickupTime != null) {
      try {
        final dt = DateTime.parse(ride.scheduledPickupTime!).toLocal();
        scheduledTimeStr = DateFormat('EEE, MMM dd · h:mm a').format(dt);
      } catch (_) {}
    }

    // Check if ride is live (status became active after scheduled time)
    final now = DateTime.now();
    bool isLive = false;
    if (ride.scheduledPickupTime != null) {
      try {
        final pickupTime = DateTime.parse(ride.scheduledPickupTime!).toLocal();
        final isLiveStatus = status == 'in_progress' ||
            status == 'driver_arrived' ||
            status == 'accepted';
        isLive = isLiveStatus && now.isAfter(pickupTime);
      } catch (_) {}
    }

    return GestureDetector(
      onTap: isLive
          ? () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RideProgressScreen(
                    rideId: ride.id,
                    driver: ride.driver,
                  ),
                ),
              );
            }
          : () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RideDetailScreen(
                    rideId: ride.id,
                    initialData: ride.toJson(),
                  ),
                ),
              );
            },
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  size: 18,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    scheduledTimeStr.isNotEmpty
                        ? scheduledTimeStr
                        : 'Scheduled',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                if (isLive) _buildLiveBadge(),
                _buildStatusBadge(status),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Route
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: Colors.grey[300],
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pickup,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            dropoff,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Fare row
                Row(
                  children: [
                    _infoChip('Fare', '£${fare.toStringAsFixed(2)}'),
                    if (stopsCount > 0) ...[
                      const SizedBox(width: 10),
                      _infoChip('Stops', '$stopsCount'),
                    ],
                    if (driverName.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      _infoChip('Driver', driverName),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Action buttons
          if (status == 'cancelling')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: null,
                  icon: const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  label: const Text(
                    'Cancelling...',
                    style: TextStyle(color: Colors.grey),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.grey),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            )
          else if (status == 'awaiting_deposit')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showCancelDialog(ride),
                  icon: const Icon(Icons.close, size: 18, color: Colors.red),
                  label: const Text(
                    'Cancel Booking',
                    style: TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            )
          else if (status == 'scheduled' || status == 'requested')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showCancelDialog(ride),
                  icon: const Icon(Icons.close, size: 18, color: Colors.red),
                  label: const Text(
                    'Cancel Ride',
                    style: TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }

  Widget _buildLiveBadge() {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'LIVE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case 'awaiting_deposit':
        bgColor = Colors.orange[50]!;
        textColor = Colors.orange[800]!;
        label = 'Pay Deposit';
        break;
      case 'scheduled':
        bgColor = Colors.green[50]!;
        textColor = Colors.green[800]!;
        label = 'Confirmed';
        break;
      case 'requested':
        bgColor = Colors.blue[50]!;
        textColor = Colors.blue[800]!;
        label = 'Finding Driver...';
        break;
      case 'accepted':
        bgColor = Colors.teal[50]!;
        textColor = Colors.teal[800]!;
        label = 'Driver Assigned';
        break;
      case 'driver_arrived':
        bgColor = Colors.purple[50]!;
        textColor = Colors.purple[800]!;
        label = 'Driver Arrived';
        break;
      case 'in_progress':
        bgColor = Colors.indigo[50]!;
        textColor = Colors.indigo[800]!;
        label = 'In Progress';
        break;
      case 'cancelling':
        bgColor = Colors.orange[50]!;
        textColor = Colors.orange[800]!;
        label = 'Cancelling...';
        break;
      case 'cancelled':
        bgColor = Colors.red[50]!;
        textColor = Colors.red[800]!;
        label = 'Cancelled';
        break;
      default:
        bgColor = Colors.grey[100]!;
        textColor = Colors.grey[700]!;
        label = status.replaceAll('_', ' ').toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
      ),
    );
  }
}
