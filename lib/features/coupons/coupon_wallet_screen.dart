import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/coupon.dart';
import '../../core/services/coupon_service.dart';
import '../../core/theme.dart';

/// My Coupons / Wallet (coupons spec P3): active / used / expired tabs
/// backed by GET /coupons/wallet?status=&page=&limit=.
class CouponWalletScreen extends StatefulWidget {
  const CouponWalletScreen({
    super.key,
    /// When true, tapping a coupon returns its code via Navigator.pop()
    /// (used by ride confirmation screen for auto-fill).
    this.selectMode = false,
  });

  final bool selectMode;

  @override
  State<CouponWalletScreen> createState() => _CouponWalletScreenState();
}

class _CouponWalletScreenState extends State<CouponWalletScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const List<(String, String)> _tabs = [
    ('active', 'Active'),
    ('used', 'Used'),
    ('expired', 'Expired'),
  ];

  final Map<String, List<CouponWalletItem>> _itemsByStatus = {
    'active': [],
    'used': [],
    'expired': [],
  };
  final Map<String, CouponPagination> _pagination = {};
  final Map<String, int> _page = {'active': 1, 'used': 1, 'expired': 1};
  final Map<String, bool> _loading = {'active': false, 'used': false, 'expired': false};
  final Map<String, bool> _loadingMore = {'active': false, 'used': false, 'expired': false};
  final Map<String, String?> _error = {'active': null, 'used': null, 'expired': null};

  String get _status => _tabs[_tabController.index].$1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _load(_status, refresh: true);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final status = _status;
    if (_itemsByStatus[status]!.isEmpty && _error[status] == null) {
      _load(status, refresh: true);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load(String status, {bool refresh = false}) async {
    if (_loading[status] == true) return;
    final currentItems = _itemsByStatus[status]!;
    if (!refresh && _loadingMore[status] == true) return;
    if (!refresh) {
      final pagination = _pagination[status];
      if (pagination != null && !pagination.hasNextPage) return;
      _loadingMore[status] = true;
    } else {
      _loading[status] = true;
      _page[status] = 1;
      _error[status] = null;
    }
    setState(() {});

    try {
      final wallet = await CouponService.fetchWallet(
        status: status,
        page: _page[status]!,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        if (refresh) {
          _itemsByStatus[status] = wallet.coupons;
        } else {
          _itemsByStatus[status] = [...currentItems, ...wallet.coupons];
        }
        _pagination[status] = wallet.pagination;
        
        if (wallet.pagination.hasNextPage) {
          _page[status] = _page[status]! + 1;
        }
        _loading[status] = false;
        _loadingMore[status] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error[status] = e.toString();
        _loading[status] = false;
        _loadingMore[status] = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'My Coupons',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primaryColor,
          tabs: _tabs.map((t) => Tab(text: t.$2)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((t) => _buildList(t.$1)).toList(),
      ),
    );
  }

  Widget _buildList(String status) {
    if (_loading[status] == true) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error[status];
    if (error != null && _itemsByStatus[status]!.isEmpty) {
      return _buildError(error, status);
    }
    final items = _itemsByStatus[status]!;
    if (items.isEmpty) {
      return _buildEmpty(status);
    }
    return RefreshIndicator(
      onRefresh: () => _load(status, refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >=
              notification.metrics.maxScrollExtent - 200) {
            _load(status);
          }
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length + (_loadingMore[status] == true ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index >= items.length) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return _CouponCard(item: items[index], selectMode: widget.selectMode);
          },
        ),
      ),
    );
  }

  Widget _buildEmpty(String status) {
    final copy = switch (status) {
      'used' => 'No used coupons yet',
      'expired' => 'No expired coupons',
      _ => 'No active coupons yet — check back soon!',
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.confirmation_number_outlined,
            size: 56,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 12),
          Text(
            copy,
            style: const TextStyle(fontSize: 15, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _load(status, refresh: true),
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message, String status) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppTheme.errorColor),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _load(status, refresh: true),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _CouponCard extends StatelessWidget {
  final CouponWalletItem item;
  final bool selectMode;

  const _CouponCard({
    required this.item,
    this.selectMode = false,
  });

  Color get _statusColor {
    switch (item.status) {
      case 'active':
        return AppTheme.successColor;
      case 'used':
        return AppTheme.textSecondary;
      case 'expired':
        return AppTheme.errorColor;
      default:
        return AppTheme.textSecondary;
    }
  }

  String get _discountLabel =>
      couponDiscountLabel(item.campaign.discountType, item.campaign.discountValue);

  String _formatDate(DateTime? date) {
    if (date == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final campaign = item.campaign;
    final isSelectable = selectMode && item.status == 'active';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelectable ? AppTheme.primaryColor : AppTheme.borderColor,
          width: isSelectable ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: isSelectable
            ? () => Navigator.pop(context, item.code)
            : null,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _discountLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    campaign.name.isNotEmpty ? campaign.name : 'Coupon',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _statusColor,
                    ),
                  ),
                ),
              ],
            ),
            if (campaign.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                campaign.description,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                // Code
                if (isSelectable) ...[
                  Text(
                    'Tap to select',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const Spacer(),
                ] else ...[
                  // Code + copy
                  GestureDetector(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: item.code));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Copied ${item.code}'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.code,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.copy,
                          size: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Min fare £${campaign.minFare.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (campaign.maxDiscountAmount > 0) ...[
                  const SizedBox(width: 12),
                  Text(
                    'Max off £${campaign.maxDiscountAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
                const Spacer(),
                if (item.maxUses > 0)
                  Text(
                    item.isFullyUsed
                        ? 'Used'
                        : 'Uses ${item.usedCount}/${item.maxUses}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: item.isFullyUsed
                          ? AppTheme.errorColor
                          : AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
