import 'package:flutter/material.dart';
import '../../core/theme.dart';

class DriverNavigationPanel extends StatelessWidget {
  final String status;
  final VoidCallback onAction;

  const DriverNavigationPanel({
    super.key,
    required this.status,
    required this.onAction,
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
          // Navigation Instruction
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.turn_right, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '200 ft',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      status == 'pickup' ? 'Turn right onto Main St' : 'Turn left onto Broadway',
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          
          // Passenger / Trip Info
          Row(
            children: [
              const CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.surfaceColor,
                child: Icon(Icons.person, color: AppTheme.textSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sarah Jenkins',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      status == 'pickup' || status == 'arrived' 
                          ? 'Pickup: Heathrow Terminal 5' 
                          : 'Drop-off: The Shard',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.phone, color: AppTheme.primaryColor),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.message, color: AppTheme.primaryColor),
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Action Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: _actionColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _actionText,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
