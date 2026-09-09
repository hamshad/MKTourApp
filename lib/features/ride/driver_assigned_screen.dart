import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/theme.dart';
import '../../core/api_service.dart';
import '../../core/services/socket_service.dart';
import '../../core/widgets/custom_snackbar.dart';

class DriverAssignedScreen extends StatefulWidget {
  final Map<String, dynamic> bookingData;

  /// Fired when the rider taps "Select payment to begin" after driver
  /// arrival. Wired to the payment sheet (03-02) by the caller — the screen
  /// keeps working when no callback is provided.
  final VoidCallback? onSelectPayment;

  const DriverAssignedScreen({
    super.key,
    required this.bookingData,
    this.onSelectPayment,
  });

  @override
  State<DriverAssignedScreen> createState() => _DriverAssignedScreenState();
}

class _DriverAssignedScreenState extends State<DriverAssignedScreen> {
  Timer? _statusTimer;
  String _currentStatus = 'driver_assigned';
  String _statusText = 'Driver is on the way';
  int _eta = 5;
  final SocketService _socketService = SocketService();

  /// Set while the backend auto-reassigns after a driver cancel —
  /// rider stays in flow with a calm banner, no panic dialog.
  int _reassignmentCount = 0;
  String? _reassignMessage;

  @override
  void initState() {
    super.initState();
    print('🚕 DRIVER ASSIGNED: Screen loaded');
    print(
      '🚕 DRIVER ASSIGNED: Driver = ${widget.bookingData['driver']?['name']}',
    );
    _initSocketAndListeners();
    _startStatusPolling();
  }

  Future<void> _initSocketAndListeners() async {
    await _socketService.initSocket();
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    final rideId = widget.bookingData['bookingId'] ?? widget.bookingData['_id'];
    if (rideId == null) return;

    // Listen for driver status updates via socket
    _socketService.on('ride:statusUpdate', (data) {
      if (!mounted) return;
      if (data['rideId'] == rideId) {
        _updateStatus(data['status']);
      }
    });

    // Listen for driver cancellation
    _socketService.on('ride:cancelledByDriver', (data) {
      if (!mounted) return;
      if (data['rideId'] == rideId) {
        _handleDriverCancellation(data);
      }
    });

    // Backend auto-reassign channel (driver cancelled pre-pickup, ride alive)
    _socketService.onDriverReassigning((data) {
      if (!mounted) return;
      final Map<String, dynamic> typed = data is Map<String, dynamic>
          ? data
          : data is Map
              ? Map<String, dynamic>.from(data)
              : <String, dynamic>{};
      final dataRideId = typed['rideId'] ?? typed['_id'];
      if (dataRideId == null || dataRideId.toString() == rideId?.toString()) {
        _handleDriverReassigning(typed);
      }
    });

    // Listen for early completion (adjusted fare)
    _socketService.on('ride:earlyCompleted', (data) {
      if (!mounted) return;
      if (data['rideId'] == rideId) {
        _handleEarlyCompletion(data);
      }
    });
  }

  void _updateStatus(String status) {
    if (!mounted) return;
    setState(() {
      _currentStatus = status;
      switch (_currentStatus) {
        case 'driver_assigned':
        case 'accepted':
          _statusText = 'Driver is on the way';
          _eta = 5;
          break;
        case 'driver_arrived':
          _statusText = 'Driver has arrived';
          _eta = 0;
          break;
        case 'in_progress':
          _statusText = 'Trip in progress';
          _eta = 12; // In a real app, this would be dynamic
          break;
        case 'completed':
          _statusText = 'Trip completed';
          _eta = 0;
          _showRideCompletionScreen();
          break;
      }
    });
  }

  /// Driver cancelled pre-pickup but the backend reassigned the ride
  /// (`reassigned: true`) — stay in flow with a calm banner, no panic.
  void _handleDriverReassigning(Map<String, dynamic> data) {
    final nested = data['data'];
    final reassigned = data['reassigned'] == true ||
        (nested is Map && nested['reassigned'] == true);
    if (!reassigned) {
      _handleDriverCancellation(data);
      return;
    }
    final count = data['reassignmentCount'] ??
        (nested is Map ? nested['reassignmentCount'] : null);
    if (!mounted) return;
    setState(() {
      _reassignmentCount =
          (count is num) ? count.toInt() : _reassignmentCount + 1;
      _reassignMessage = data['message']?.toString() ??
          'Your driver had to cancel. Finding you another driver…';
      _currentStatus = 'driver_assigned';
      _statusText = 'Finding you another driver…';
    });
    CustomSnackbar.show(
      context,
      message: _reassignMessage!,
      type: SnackbarType.info,
    );
  }

  void _handleDriverCancellation(Map<String, dynamic> data) {
    // Reassigned path keeps the rider in flow — handled above.
    final nested = data['data'];
    final reassigned = data['reassigned'] == true ||
        (nested is Map && nested['reassigned'] == true);
    if (reassigned) {
      _handleDriverReassigning(
        data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data),
      );
      return;
    }
    final refundStatus =
        data['refundStatus']?.toString() ?? 'processing';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Ride Cancelled'),
        content: Text(
          'The driver had to cancel the ride. A full refund is $refundStatus.',
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
            child: const Text('Return Home'),
          ),
        ],
      ),
    );
  }

  void _handleEarlyCompletion(Map<String, dynamic> data) {
    // Show adjusted fare message and move to completion screen
    CustomSnackbar.show(
      context,
      message: 'Ride ended early. Fare adjusted based on distance.',
      type: SnackbarType.info,
    );

    Navigator.pushReplacementNamed(
      context,
      '/ride-complete',
      arguments: {
        'bookingId': widget.bookingData['bookingId'],
        'driver': widget.bookingData['driver'],
        'fare': data['adjustedFare'],
        'distance': data['actualDistance'],
        'status': 'early_completion',
      },
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _socketService.off('ride:statusUpdate');
    _socketService.off('ride:cancelledByDriver');
    _socketService.off('ride:earlyCompleted');
    _socketService.offDriverReassigning();
    super.dispose();
  }

  void _startStatusPolling() {
    final apiService = ApiService();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final status = await apiService.getRideStatus(
          widget.bookingData['bookingId'] ?? 'unknown',
        );
        if (mounted) {
          _updateStatus(status['status'] ?? 'driver_assigned');
          if (_currentStatus == 'completed') {
            timer.cancel();
          }
        }
      } catch (e) {
        // Continue polling even on error
      }
    });
  }

  void _showRideCompletionScreen() {
    Navigator.pushReplacementNamed(
      context,
      '/ride-complete',
      arguments: {
        'bookingId': widget.bookingData['bookingId'],
        'driver': widget.bookingData['driver'],
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.bookingData['driver'] ?? {};

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      _statusText,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // Map placeholder (would show driver location)
            Expanded(
              child: Container(
                color: AppTheme.surfaceColor,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.local_taxi,
                        size: 80,
                        color: AppTheme.primaryColor.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Map view',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom section with driver info and trip actions
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 20),

                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.borderColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Reassign banner — driver cancelled, matching continues.
                  if (_reassignmentCount > 0 && _reassignMessage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.autorenew,
                              color: Colors.blue.shade700,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Finding you another driver…',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue.shade800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Attempt $_reassignmentCount. Stay on this screen.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (_reassignmentCount > 0) const SizedBox(height: 16),

                  // Driver-arrived → payment selection CTA (sheet from 03-02
                  // via callback; falls back to an info note when absent).
                  if (_currentStatus == 'driver_arrived')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (widget.onSelectPayment != null) {
                              widget.onSelectPayment!();
                            } else {
                              CustomSnackbar.show(
                                context,
                                message:
                                    'Driver has arrived — select a payment method to begin.',
                                type: SnackbarType.info,
                              );
                            }
                          },
                          icon: const Icon(Icons.payments_outlined, size: 20),
                          label: const Text('Select payment to begin'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ),

                  if (_currentStatus == 'driver_arrived')
                    const SizedBox(height: 16),

                  // Driver Card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: Row(
                        children: [
                          // Driver photo
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: AppTheme.surfaceColor,
                            child: Icon(
                              Icons.person,
                              color: AppTheme.textSecondary,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Driver details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  driver['name'] ?? 'Driver',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.star,
                                      size: 16,
                                      color: Colors.amber[700],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      (driver['rating'] ?? '-').toString(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppTheme.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Vehicle details
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                driver['vehicle'] ?? 'Vehicle',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                driver['plate'] ?? 'ABC 123',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ETA Display
                  if (_eta > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 20,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'ETA: $_eta min',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.phone, size: 20),
                            label: const Text('Call'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.message, size: 20),
                            label: const Text('Message'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Cancel ride
                  TextButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Cancel ride?'),
                          content: const Text(
                            'Are you sure you want to cancel this ride?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('No'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context); // Close dialog
                                // Navigate to home screen instead of double pop
                                Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  '/home',
                                  (route) => false,
                                );
                              },
                              child: Text(
                                'Yes, cancel',
                                style: TextStyle(color: AppTheme.errorColor),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Cancel ride',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
