import 'package:flutter/material.dart';

import '../../core/models/coupon.dart';
import '../../core/services/coupon_service.dart';
import '../../core/theme.dart';
import 'loyalty_badge.dart';

/// Loyalty Tiers (coupons spec P4): GET /coupons/tiers — progress bar
/// of completed rides vs the next tier's target, plus every tier's perks.
class LoyaltyTiersScreen extends StatefulWidget {
  const LoyaltyTiersScreen({super.key});

  @override
  State<LoyaltyTiersScreen> createState() => _LoyaltyTiersScreenState();
}

class _LoyaltyTiersScreenState extends State<LoyaltyTiersScreen> {
  LoyaltyTiers? _tiers;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tiers = await CouponService.fetchTiers();
      if (!mounted) return;
      setState(() {
        _tiers = tiers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Loyalty Tiers',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppTheme.errorColor),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final tiers = _tiers!;
    final sorted = tiers.sortedTiers;
    final next = tiers.nextTier;
    final currentRule = tiers.currentTierRule;
    final currentTier = tiers.userTier;

    // Progress: rides toward the next tier; at max tier show full bar.
    double progress = 1.0;
    String progressLabel;
    if (next != null) {
      final target = next.value.minRides;
      final done = tiers.completedRidesCount;
      progress = target <= 0 ? 1.0 : (done / target).clamp(0.0, 1.0);
      progressLabel = '$done / $target rides to ${loyaltyTierLabel(next.key)}';
    } else {
      progressLabel =
          '${tiers.completedRidesCount} completed — top tier reached!';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current tier card + progress bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: loyaltyTierColor(currentTier).withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: loyaltyTierColor(currentTier).withOpacity(0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.military_tech,
                      size: 28,
                      color: loyaltyTierColor(currentTier),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        currentTier.isEmpty
                            ? 'No tier yet'
                            : '${loyaltyTierLabel(currentTier)} Tier',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: loyaltyTierColor(currentTier),
                        ),
                      ),
                    ),
                    LoyaltyBadge(
                      tier: currentTier,
                      completedRides: tiers.completedRidesCount,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: Colors.white,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      loyaltyTierColor(currentTier),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  progressLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (currentRule != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Your perk: ${couponDiscountLabel(currentRule.discountType, currentRule.discountValue)}'
                    '${currentRule.maxDiscountAmount > 0 ? ' off (max £${currentRule.maxDiscountAmount.toStringAsFixed(2)})' : ''} per ride',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'All Tiers',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in sorted) _buildTierCard(entry, tiers),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildTierCard(
    MapEntry<String, LoyaltyTierRule> entry,
    LoyaltyTiers tiers,
  ) {
    final key = entry.key;
    final rule = entry.value;
    final isCurrent = key == tiers.userTier;
    final isUnlocked = rule.minRides <= tiers.completedRidesCount;
    final color = loyaltyTierColor(key);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCurrent ? color.withOpacity(0.06) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent ? color : AppTheme.borderColor,
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isUnlocked ? Icons.military_tech : Icons.lock_outline,
              color: isUnlocked ? color : AppTheme.textSecondary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      loyaltyTierLabel(key),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isCurrent ? color : AppTheme.textPrimary,
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'YOU',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${rule.minRides}+ rides · '
                  '${couponDiscountLabel(rule.discountType, rule.discountValue)} off'
                  '${rule.maxDiscountAmount > 0 ? ' (max £${rule.maxDiscountAmount.toStringAsFixed(2)})' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (!isUnlocked)
            Text(
              '${(rule.minRides - tiers.completedRidesCount).clamp(0, 9999)} to go',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            )
          else
            Icon(Icons.check_circle, size: 20, color: color),
        ],
      ),
    );
  }
}
