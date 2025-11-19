import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class DestinationBottomSheet extends StatelessWidget {
  final Function(String) onDestinationSelected;

  const DestinationBottomSheet({
    super.key,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 24),
          Text(
            'Where are you going?',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => onDestinationSelected(''),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppTheme.textSecondary),
                  const SizedBox(width: 12),
                  Text(
                    'Search destination',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Recent/Saved Places
          _buildPlaceItem(
            context,
            icon: Icons.home_filled,
            title: 'Home',
            subtitle: '221B Baker Street',
            onTap: () => onDestinationSelected('Home'),
          ),
          const Divider(height: 32),
          _buildPlaceItem(
            context,
            icon: Icons.work,
            title: 'Work',
            subtitle: 'The Shard, London',
            onTap: () => onDestinationSelected('Work'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppTheme.textPrimary, size: 20),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
