import 'package:flutter/material.dart';
import '../../core/theme.dart';

class DriverNavigationPanel extends StatelessWidget {
  final String status;
  final VoidCallback onAction;
  final Map<String, dynamic>? rideData;

  const DriverNavigationPanel({
    super.key,
    required this.status,
    required this.onAction,
    this.rideData,
  });

  String get _actionText {
    switch (status) {
      case 'pickup':
        return 'Arrived at Pickup';
      case 'arrived':
        return 'Start Trip';
      case 'in_progress':
        return 'Complete Trip';
      default:
        return 'Action';
    }
  }

  Color get _actionColor {
    switch (status) {
      case 'in_progress':
        return Colors.red;
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
                child: const Icon(Icons.turn_right, color: Colors.white, size: 32),
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
                          ? (rideData?['pickupLocation']?['address'] ?? 'Pickup Location')
                          : (rideData?['dropoffLocation']?['address'] ?? 'Dropoff Location'),
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
          
          // Passenger / Trip Info Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white,
                  backgroundImage: rideData?['user']?['profilePicture'] != null 
                      ? NetworkImage(rideData!['user']['profilePicture']) 
                      : null,
                  child: rideData?['user']?['profilePicture'] == null 
                      ? const Icon(Icons.person, color: AppTheme.textSecondary) 
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
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            status == 'pickup' || status == 'arrived' ? Icons.location_on : Icons.flag,
                            size: 14,
                            color: status == 'pickup' || status == 'arrived' ? AppTheme.primaryColor : Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              status == 'pickup' || status == 'arrived' 
                                  ? 'Pickup: ${rideData?['pickupLocation']?['address'] ?? 'Unknown'}' 
                                  : 'Drop-off: ${rideData?['dropoffLocation']?['address'] ?? 'Unknown'}',
                              style: TextStyle(
                                fontSize: 13,
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
                Row(
                  children: [
                    _buildActionButton(Icons.phone, () {}),
                    const SizedBox(width: 8),
                    _buildActionButton(Icons.message, () {}),
                  ],
                ),
              ],
            ),
          ),
          
          const Spacer(),
          
          // Main Action Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: _actionColor,
                elevation: 8,
                shadowColor: _actionColor.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                _actionText.toUpperCase(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
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
}
