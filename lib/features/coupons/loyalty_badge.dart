import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Loyalty tier display helpers shared by Account, Wallet and Tiers
/// screens. Tier names arrive lowercase from the backend
/// (`bronze|silver|gold|platinum`); unknown names fall back to neutral.
Color loyaltyTierColor(String tier) {
  switch (tier.toLowerCase()) {
    case 'bronze':
      return const Color(0xFFCD7F32);
    case 'silver':
      return const Color(0xFF9AA0A6);
    case 'gold':
      return const Color(0xFFF4B400);
    case 'platinum':
      return const Color(0xFF5F6368);
    default:
      return AppTheme.primaryColor;
  }
}

String loyaltyTierLabel(String tier) {
  if (tier.isEmpty) return '';
  return tier[0].toUpperCase() + tier.substring(1).toLowerCase();
}

/// Compact badge chip: tier dot + name (+ optional rides count).
class LoyaltyBadge extends StatelessWidget {
  final String tier;
  final int? completedRides;

  const LoyaltyBadge({
    super.key,
    required this.tier,
    this.completedRides,
  });

  @override
  Widget build(BuildContext context) {
    if (tier.isEmpty) return const SizedBox.shrink();
    final color = loyaltyTierColor(tier);
    final label = loyaltyTierLabel(tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.military_tech, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            completedRides != null
                ? '$label · $completedRides rides'
                : label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
