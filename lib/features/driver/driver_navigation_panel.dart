import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/services/navigation_service.dart';

class DriverNavigationPanel extends StatelessWidget {
  final String status;
  final VoidCallback onAction;
  final VoidCallback? onCancel;
  final VoidCallback? onEndEarly;
  final Map<String, dynamic>? rideData;
  final NavigationState? navigationState;

  const DriverNavigationPanel({
    super.key,
    required this.status,
    required this.onAction,
    this.onCancel,
    this.onEndEarly,
    this.rideData,
    this.navigationState,
  });

  String get _actionText {
    switch (status) {
      case 'pickup':
        return 'Arrived at Pickup';
      case 'arrived':
        return 'Start Trip';
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
        mainAxisSize: MainAxisSize.min,
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

          // Navigation Info Card (if navigation is active)
          if (navigationState != null)
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

          if (navigationState != null) const SizedBox(height: 16),

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

          const Spacer(),

          // Cancel/End Early Button (secondary action)
          if (status == 'pickup' || status == 'arrived') ...[
            // Cancel button before ride starts
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.close, color: Colors.red, size: 20),
                label: const Text('Cancel Ride'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ] else if (status == 'in_progress') ...[
            // End ride early button during ride
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: onEndEarly,
                icon: const Icon(
                  Icons.stop_circle_outlined,
                  color: Colors.orange,
                  size: 20,
                ),
                label: const Text('End Ride Early'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  side: const BorderSide(color: Colors.orange),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Main Action Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: status == 'awaiting_payment' ? null : onAction, // Disable if just waiting
              style: ElevatedButton.styleFrom(
                backgroundColor: _actionColor,
                elevation: 8,
                shadowColor: _actionColor.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _actionText.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
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
