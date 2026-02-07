import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../activity/ride_detail_screen.dart';

class _StatusFilter {
  final String label;
  final List<String> statusKeys;

  const _StatusFilter({required this.label, required this.statusKeys});
}

const List<_StatusFilter> _statusFilters = [
  _StatusFilter(label: 'All', statusKeys: []),
  _StatusFilter(label: 'Requested', statusKeys: ['requested']),
  _StatusFilter(label: 'Accepted', statusKeys: ['accepted']),
  _StatusFilter(
    label: 'Driver Arrived',
    statusKeys: ['driver_arrived', 'arrived'],
  ),
  _StatusFilter(
    label: 'In Progress',
    statusKeys: ['in_progress', 'driver_assigned', 'started'],
  ),
  _StatusFilter(label: 'Completed', statusKeys: ['completed']),
  _StatusFilter(label: 'Early Completed', statusKeys: ['early_completed']),
  _StatusFilter(
    label: 'Cancelled (User)',
    statusKeys: ['cancelled_by_user', 'cancelled'],
  ),
  _StatusFilter(
    label: 'Cancelled (Driver)',
    statusKeys: ['cancelled_by_driver', 'cancelled'],
  ),
  _StatusFilter(label: 'Terminated', statusKeys: ['terminated']),
  _StatusFilter(label: 'Expired', statusKeys: ['expired']),
];

const Set<String> _terminalStatuses = {
  'completed',
  'early_completed',
  'cancelled',
  'cancelled_by_user',
  'cancelled_by_driver',
  'expired',
  'terminated',
};

const Map<String, String> _statusDisplayNames = {
  'requested': 'Requested',
  'accepted': 'Accepted',
  'driver_arrived': 'Driver Arrived',
  'arrived': 'Driver Arrived',
  'in_progress': 'In Progress',
  'driver_assigned': 'Driver Assigned',
  'started': 'Ride Started',
  'completed': 'Completed',
  'early_completed': 'Early Completed',
  'cancelled': 'Cancelled',
  'cancelled_by_user': 'Cancelled (User)',
  'cancelled_by_driver': 'Cancelled (Driver)',
  'terminated': 'Terminated',
  'expired': 'Expired',
};

String _formatStatusLabel(String status) {
  final normalized = status.toLowerCase();
  if (normalized.isEmpty) {
    return 'Unknown';
  }
  final predefLabel = _statusDisplayNames[normalized];
  if (predefLabel != null) return predefLabel;

  return normalized
      .split('_')
      .where((segment) => segment.isNotEmpty)
      .map((segment) => '${segment[0].toUpperCase()}${segment.substring(1)}')
      .join(' ');
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  bool _isInit = true;
  bool _isLoading = false;
  String _selectedFilter = 'All';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      debugPrint('📋 ActivityScreen: Initializing, fetching ride history...');
      _fetchRideHistory();
      _isInit = false;
    }
  }

  Future<void> _fetchRideHistory({bool forceRefresh = false}) async {
    debugPrint(
      '📋 ActivityScreen: _fetchRideHistory called (forceRefresh: $forceRefresh)',
    );
    setState(() => _isLoading = true);
    await Provider.of<AuthProvider>(
      context,
      listen: false,
    ).fetchRideHistory(forceRefresh: forceRefresh);

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  _StatusFilter get _activeStatusFilter => _statusFilters.firstWhere(
    (filter) => filter.label == _selectedFilter,
    orElse: () => _statusFilters.first,
  );

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            'Activity',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          bottom: const TabBar(
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primaryColor,
            tabs: [
              Tab(text: 'Ongoing'),
              Tab(text: 'All'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildActivityList(context, filterType: 'ongoing'),
            _buildActivityList(context, filterType: 'all'),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityList(
    BuildContext context, {
    required String filterType,
  }) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (_isLoading && authProvider.rideHistory.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final allRidesFromSource = authProvider.rideHistory;
        final selectedStatuses = _activeStatusFilter.statusKeys;

        // Filter rides based on tab
        List<dynamic> rides;
        if (filterType == 'ongoing') {
          rides = allRidesFromSource.where((ride) {
            final status = (ride['status'] as String?)?.toLowerCase() ?? '';
            // Ongoing includes everything that is NOT terminal
            return !_terminalStatuses.contains(status);
          }).toList();
        } else {
          // All Tab - apply chip filter
          rides = allRidesFromSource.where((ride) {
            final status = (ride['status'] as String?)?.toLowerCase() ?? '';
            if (selectedStatuses.isEmpty) return true;
            return selectedStatuses.contains(status);
          }).toList();
        }

        return Column(
          children: [
            if (filterType == 'all') _buildFilterBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _fetchRideHistory(forceRefresh: true),
                child: rides.isEmpty
                    ? _buildEmptyState(filterType)
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: rides.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 32),
                        itemBuilder: (context, index) {
                          final ride = rides[index];
                          final pickup =
                              ride['pickupLocation']?['address'] ??
                              'Unknown Pickup';
                          final dropoff =
                              ride['dropoffLocation']?['address'] ??
                              'Unknown Dropoff';
                          final price = ride['fare'] != null
                              ? '£${ride['fare']}'
                              : '£0.00';
                          final status = ride['status'] ?? 'Unknown';
                          final dateStr = ride['createdAt'];
                          String formattedDate = 'Unknown Date';

                          if (dateStr != null) {
                            try {
                              final date = DateTime.parse(dateStr).toLocal();
                              formattedDate = DateFormat(
                                'MMM d, h:mm a',
                              ).format(date);
                            } catch (e) {
                              formattedDate = dateStr;
                            }
                          }

                          return _buildActivityItem(
                            context,
                            date: formattedDate,
                            destination: dropoff,
                            price: price,
                            status: status.toString(),
                            rideData: ride,
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _statusFilters.length,
        itemBuilder: (context, index) {
          final filter = _statusFilters[index];
          final isSelected = _selectedFilter == filter.label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(filter.label),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedFilter = filter.label;
                });
              },
              selectedColor: AppTheme.primaryColor.withValues(alpha: 0.1),
              checkmarkColor: AppTheme.primaryColor,
              labelStyle: TextStyle(
                color: isSelected ? AppTheme.primaryColor : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              backgroundColor: Colors.grey[100],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? AppTheme.primaryColor
                      : Colors.transparent,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String filterType) {
    IconData emptyIcon;
    String emptyMessage;

    if (filterType == 'ongoing') {
      emptyIcon = Icons.directions_car;
      emptyMessage = 'No ongoing rides';
    } else {
      emptyIcon = Icons.history;
      emptyMessage = _selectedFilter == 'All'
          ? 'No ride history yet'
          : 'No $_selectedFilter rides';
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  emptyIcon,
                  size: 64,
                  color: AppTheme.textSecondary.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  emptyMessage,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'early_completed':
        return Colors.lightGreen;
      case 'cancelled':
      case 'cancelled_by_user':
      case 'cancelled_by_driver':
        return Colors.red;
      case 'expired':
        return Colors.orange;
      case 'terminated':
        return Colors.red.shade900;
      case 'requested':
        return Colors.blue;
      case 'accepted':
        return Colors.orangeAccent;
      case 'driver_arrived':
        return Colors.deepOrange;
      case 'in_progress':
      case 'driver_assigned':
      case 'started':
        return Colors.blue;
      case 'arrived':
        return Colors.teal;
      case 'pending':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  Widget _buildActivityItem(
    BuildContext context, {
    required String date,
    required String destination,
    required String price,
    required String status,
    required Map<String, dynamic> rideData,
  }) {
    final statusColor = _getStatusColor(status);
    final displayStatus = _formatStatusLabel(status);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RideDetailScreen(
              rideId: rideData['_id'] ?? '',
              initialData: rideData,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_taxi, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  destination,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  date,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  price,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              displayStatus.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
