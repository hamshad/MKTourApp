import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/services/payment_service.dart';
import '../../core/services/socket_service.dart';
import '../../core/widgets/custom_snackbar.dart';
import '../ride/payment_webview_screen.dart';

/// Screen showing the user's scheduled (pre-booked) rides with cancel option.
class ScheduledRidesScreen extends StatefulWidget {
  const ScheduledRidesScreen({super.key});

  @override
  State<ScheduledRidesScreen> createState() => _ScheduledRidesScreenState();
}

class _ScheduledRidesScreenState extends State<ScheduledRidesScreen> {
  List<Map<String, dynamic>> _rides = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchScheduledRides();
  }

  Future<void> _fetchScheduledRides() async {
    setState(() => _isLoading = true);
    final rides = await PaymentService.getScheduledRides();
    if (mounted) {
      setState(() {
        _rides = rides;
        _isLoading = false;
      });
    }
  }

  void _showCancelDialog(Map<String, dynamic> ride) {
    final rideId = ride['_id']?.toString() ?? '';
    final deposit = ride['depositAmount'] ?? 0;
    final depositStr = '£${(deposit is num ? deposit : 0).toStringAsFixed(2)}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
              _cancelRide(rideId);
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

  Future<void> _payDeposit(Map<String, dynamic> ride) async {
    final rideId = ride['_id']?.toString() ?? '';

    // Prefer paymentUrl from depositPayment sub-object, fall back to root
    String? paymentUrl =
        (ride['depositPayment'] as Map<String, dynamic>?)?['paymentUrl']
            ?.toString();
    paymentUrl ??= ride['paymentUrl']?.toString();

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
              PaymentWebViewScreen(paymentUrl: paymentUrl!, rideId: rideId),
        ),
      );
      // Refresh regardless of WebView outcome — socket will update status if paid
      if (mounted) _fetchScheduledRides();
    } finally {
      socketService.off('ride:depositConfirmed');
    }
  }

  Future<void> _cancelRide(String rideId) async {
    try {
      final response = await PaymentService.cancelScheduledRideUser(rideId);

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
        CustomSnackbar.show(
          context,
          message: response['message'] ?? 'Failed to cancel ride',
          type: SnackbarType.error,
        );
      }
    } catch (e) {
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

  Widget _buildRideCard(Map<String, dynamic> ride) {
    final pickup = ride['pickupLocation']?['address'] ?? 'Unknown Pickup';
    final dropoff = ride['dropoffLocation']?['address'] ?? 'Unknown Dropoff';
    final fare = (ride['fare'] as num?)?.toDouble() ?? 0;
    final deposit = (ride['depositAmount'] as num?)?.toDouble() ?? 0;
    final depositStatus = ride['depositStatus'] ?? 'pending';
    final status = ride['status'] ?? 'scheduled';
    final driverName = (ride['driver'] as Map<String, dynamic>?)?['name'] ?? '';

    String scheduledTimeStr = '';
    if (ride['scheduledPickupTime'] != null) {
      try {
        final dt = DateTime.parse(ride['scheduledPickupTime']).toLocal();
        scheduledTimeStr = DateFormat('EEE, MMM dd · h:mm a').format(dt);
      } catch (_) {}
    }

    return Container(
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
                _buildStatusBadge(status, depositStatus),
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
                    const SizedBox(width: 10),
                    _infoChip('Deposit', '£${deposit.toStringAsFixed(2)}'),
                    if (driverName.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      _infoChip('Driver', driverName),
                    ],
                  ],
                ),
                if (ride['preBookingNote'] != null &&
                    (ride['preBookingNote'] as String).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.note, size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ride['preBookingNote'],
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Action buttons
          if (status == 'awaiting_deposit') ...[
            // Padding(
            //   padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            //   child: SizedBox(
            //     width: double.infinity,
            //     child: ElevatedButton.icon(
            //       onPressed: () => _payDeposit(ride),
            //       icon: const Icon(Icons.payment, size: 18, color: Colors.white),
            //       label: const Text('Pay Deposit',
            //           style: TextStyle(color: Colors.white)),
            //       style: ElevatedButton.styleFrom(
            //         backgroundColor: AppTheme.primaryColor,
            //         shape: RoundedRectangleBorder(
            //             borderRadius: BorderRadius.circular(10)),
            //       ),
            //     ),
            //   ),
            // ),
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
            ),
          ] else if (status == 'scheduled' || status == 'requested')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
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
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status, String depositStatus) {
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
        label = 'Confirmed ✓';
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
