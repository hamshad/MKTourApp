import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/services/navigation_service.dart';
import '../../core/models/vehicle.dart';

class DriverNavigationPanel extends StatelessWidget {
  final String status;
  final VoidCallback onAction;
  final VoidCallback? onCancel;
  final VoidCallback? onEndEarly;
  final Map<String, dynamic>? rideData;
  final NavigationState? navigationState;
  final bool isLoading;

  /// Free-wait policy label shown after arrival (e.g. "5 min free ·
  /// £0.35/min after"). Backend values via driver home, policy fallback.
  final String? freeWaitLabel;

  /// Multi-stop trip state. Empty for direct trips.
  final List<RideStop> stops;
  final int currentStopIndex;
  final VoidCallback? onStopArrive;
  final VoidCallback? onStopResume;

  /// Running totals (backend values merged after each stop event).
  final int? totalWaitMinutes;
  final double? totalWaitFee;
  final double? farePreview;

  const DriverNavigationPanel({
    super.key,
    required this.status,
    required this.onAction,
    this.onCancel,
    this.onEndEarly,
    this.rideData,
    this.navigationState,
    this.isLoading = false,
    this.freeWaitLabel,
    this.stops = const [],
    this.currentStopIndex = 0,
    this.onStopArrive,
    this.onStopResume,
    this.totalWaitMinutes,
    this.totalWaitFee,
    this.farePreview,
  });

  /// First stop that still needs driving (pending or arrived).
  RideStop? get _activeStop {
    for (final stop in stops) {
      if (!stop.isCompleted) return stop;
    }
    return null;
  }

  int get _completedStopCount =>
      stops.where((stop) => stop.isCompleted).length;

  String get _actionText {
    switch (status) {
      case 'pickup':
        return 'Arrived at Pickup';
      case 'arrived':
        return 'Start Trip';
      case 'at_stop':
        return 'Resume Trip';
      case 'in_progress':
        return 'Complete Trip';
      case 'awaiting_cash_confirmation':
        return 'Confirm Cash Collected';
      case 'awaiting_payment':
      default:
        return 'Waiting for Payment...';
    }
  }

  Color get _actionColor {
    switch (status) {
      case 'in_progress':
        return Colors.red;
      case 'awaiting_cash_confirmation':
        return Colors.green;
      case 'awaiting_payment':
        return Colors.grey;
      default:
        return AppTheme.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          // Drag Handle
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
          const SizedBox(height: 20),

          // Scheduled ride banner
          if (rideData?['isScheduled'] == true) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, color: AppTheme.primaryColor, size: 18),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📅 Scheduled Ride',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      if (rideData?['scheduledPickupTime'] != null)
                        Text(
                          DateFormat('EEE, MMM d @ hh:mm a').format(
                            DateTime.parse(rideData!['scheduledPickupTime']).toLocal(),
                          ),
                          style: const TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Scrollable middle section
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Navigation Instruction
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.turn_right,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Navigating',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              status == 'pickup'
                                  ? (rideData?['pickupLocation']?['address'] ??
                                        'Pickup Location')
                                  : (rideData?['dropoffLocation']?['address'] ??
                                        'Dropoff Location'),
                              style: const TextStyle(
                                fontSize: 16,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w500,
                                overflow: TextOverflow.ellipsis,
                              ),
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Free-wait chip (arrived / at-stop)
                  if (freeWaitLabel != null &&
                      (status == 'arrived' ||
                          status == 'at_stop')) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            color: Colors.green,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              freeWaitLabel!,
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Running totals bar (stops trip: wait + fare preview)
                  if (totalWaitMinutes != null &&
                      (status == 'in_progress' || status == 'at_stop')) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.primaryColor.withOpacity(0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildTotalItem(
                            Icons.timer_outlined,
                            'Wait',
                            '${totalWaitMinutes}m',
                          ),
                          Container(
                            width: 1,
                            height: 32,
                            color: Colors.grey[300],
                          ),
                          _buildTotalItem(
                            Icons.payments_outlined,
                            'Wait fee',
                            '£${(totalWaitFee ?? 0).toStringAsFixed(2)}',
                          ),
                          Container(
                            width: 1,
                            height: 32,
                            color: Colors.grey[300],
                          ),
                          _buildTotalItem(
                            Icons.receipt_long,
                            'Fare',
                            farePreview != null
                                ? '£${farePreview!.toStringAsFixed(2)}'
                                : '—',
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Per-stop execution card
                  if (stops.isNotEmpty &&
                      (status == 'in_progress' ||
                          status == 'at_stop')) ...[
                    _buildStopCard(context),
                    const SizedBox(height: 14),
                  ],

                  // Navigation Info Card (if navigation is active)
                  if (navigationState != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primaryColor.withValues(alpha: 0.1),
                            AppTheme.primaryColor.withValues(alpha: 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildNavInfoItem(
                            Icons.navigation,
                            'Distance',
                            navigationState!.distanceText,
                          ),
                          Container(width: 1, height: 40, color: Colors.grey[300]),
                          _buildNavInfoItem(
                            Icons.schedule,
                            'ETA',
                            navigationState!.etaText,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Passenger / Trip Info Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.white,
                              backgroundImage: rideData?['user']?['profilePicture'] != null
                                  ? NetworkImage(rideData!['user']['profilePicture'])
                                  : null,
                              child: rideData?['user']?['profilePicture'] == null
                                  ? const Icon(Icons.person, color: AppTheme.textSecondary, size: 20)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    rideData?['user']?['name'] ?? 'Passenger',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (rideData?['paymentMethod'] != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        (rideData?['paymentMethod'] ?? '').toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: rideData?['paymentMethod'] == 'cash'
                                              ? Colors.green[700]
                                              : Colors.blue[700],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                _buildActionButton(Icons.phone, () async {
                                  final phone = rideData?['user']?['phone']?.toString();
                                  if (phone != null && phone.isNotEmpty) {
                                    final Uri launchUri = Uri(
                                      scheme: 'tel',
                                      path: phone,
                                    );
                                    if (await canLaunchUrl(launchUri)) {
                                      await launchUrl(launchUri);
                                    }
                                  }
                                }),
                                const SizedBox(width: 8),
                                _buildActionButton(Icons.message, () async {
                                  final phone = rideData?['user']?['phone']?.toString();
                                  if (phone != null && phone.isNotEmpty) {
                                    final cleanNumber = phone.replaceAll(RegExp(r'\D'), '');
                                    final whatsappUrl = Uri.parse("https://wa.me/$cleanNumber");
                                    if (await canLaunchUrl(whatsappUrl)) {
                                      await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
                                    }
                                  }
                                }),
                              ],
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        // Pickup Location
                        Row(
                          children: [
                            Icon(Icons.location_on, size: 14, color: AppTheme.primaryColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Pickup: ${rideData?['pickupLocation']?['address'] ?? 'Loading...'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Dropoff Location
                        Row(
                          children: [
                            const Icon(Icons.flag, size: 14, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Drop-off: ${rideData?['dropoffLocation']?['address'] ?? 'Loading...'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Cancel/End Early Button (secondary action)
          if (status == 'pickup' || status == 'arrived') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
                child: OutlinedButton(
                  onPressed: isLoading ? null : onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.red,
                          ),
                        )
                      : const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.close, color: Colors.red, size: 20),
                              SizedBox(width: 8),
                              Text('Cancel Ride'),
                            ],
                          ),
                        ),
              ),
              ),
            const SizedBox(height: 12),
          ] else if (status == 'in_progress') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
                child: OutlinedButton(
                  onPressed: isLoading ? null : onEndEarly,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.orange,
                          ),
                        )
                      : const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.stop_circle_outlined,
                                color: Colors.orange,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text('End Ride Early'),
                            ],
                          ),
                        ),
                ),
              ),
            const SizedBox(height: 12),
          ],

          // Main Action Button
          Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
              onPressed: (status == 'awaiting_payment' || isLoading) ? null : onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: _actionColor,
                elevation: 8,
                shadowColor: _actionColor.withOpacity(0.4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _actionText.toUpperCase(),
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
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// Current-stop execution card: arrive at the stop, then resume.
  Widget _buildStopCard(BuildContext context) {
    final active = _activeStop;
    final stopLabel = active != null
        ? 'Stop #${active.stopOrder == 0 ? currentStopIndex + 1 : active.stopOrder}'
        : 'All stops done';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == 'at_stop'
              ? Colors.orange.withOpacity(0.5)
              : AppTheme.primaryColor.withOpacity(0.3),
          width: status == 'at_stop' ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: status == 'at_stop'
                      ? Colors.orange.withOpacity(0.12)
                      : AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  status == 'at_stop'
                      ? Icons.pause_circle_filled
                      : Icons.location_on,
                  color: status == 'at_stop'
                      ? Colors.orange[800]
                      : AppTheme.primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stopLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (active != null && active.address.isNotEmpty)
                      Text(
                        active.address,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Text(
                '$_completedStopCount/${stops.length} done',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          // Live wait timer once arrived at the stop.
          if (status == 'at_stop' && active != null) ...[
            const SizedBox(height: 10),
            _StopWaitChip(arrivedAt: active.arrivedAt),
          ],
          // Per-leg completed fee once known.
          if (active != null &&
              active.isCompleted &&
              active.waitFee > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Leg wait fee £${active.waitFee.toStringAsFixed(2)} added to total',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (status == 'at_stop')
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: isLoading ? null : onStopResume,
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text('Resume trip'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          else if (active != null)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: isLoading ? null : onStopArrive,
                icon: const Icon(Icons.flag, size: 20),
                label: Text('Arrive at $stopLabel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTotalItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 18),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: IconButton(
        icon: Icon(icon, color: AppTheme.primaryColor, size: 20),
        onPressed: onTap,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildNavInfoItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 24),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Live wait timer chip for the at-stop state.
///
/// Ticks every 30s from the backend `arrivedAt`; the fee preview uses
/// [WaitFeePolicy] (backend-computed `waitFee` stays authoritative).
class _StopWaitChip extends StatefulWidget {
  final String? arrivedAt;

  const _StopWaitChip({this.arrivedAt});

  @override
  State<_StopWaitChip> createState() => _StopWaitChipState();
}

class _StopWaitChipState extends State<_StopWaitChip> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _elapsedMinutes {
    if (widget.arrivedAt == null) return 0;
    try {
      final arrived = DateTime.parse(widget.arrivedAt!).toLocal();
      final elapsed = DateTime.now().difference(arrived).inMinutes;
      return elapsed < 0 ? 0 : elapsed;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _elapsedMinutes;
    final preview = WaitFeePolicy.feeFor(elapsed);
    final text = preview > 0
        ? 'Waiting ${elapsed}m · £${preview.toStringAsFixed(2)} so far'
        : 'Waiting ${elapsed}m · within ${WaitFeePolicy.freeMinutes} min free';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_bottom, color: Colors.orange[800], size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.orange[800],
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
