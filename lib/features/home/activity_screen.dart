import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../activity/ride_detail_screen.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  bool _isInit = true;
  bool _isLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      _fetchRideHistory();
      _isInit = false;
    }
  }

  Future<void> _fetchRideHistory({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    await Provider.of<AuthProvider>(context, listen: false).fetchRideHistory(forceRefresh: forceRefresh);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

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
              Tab(text: 'Current'),
              Tab(text: 'Completed'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildActivityList(context, isCompleted: false),
            _buildActivityList(context, isCompleted: true),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityList(BuildContext context, {required bool isCompleted}) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (_isLoading && authProvider.rideHistory.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        // Filter rides based on status
        final allRides = authProvider.rideHistory;
        final rides = allRides.where((ride) {
          final status = (ride['status'] as String?)?.toLowerCase() ?? '';
          if (isCompleted) {
            return status == 'completed' || status == 'cancelled';
          } else {
            return status == 'pending' || 
                   status == 'accepted' || 
                   status == 'started' || 
                   status == 'driver_assigned';
          }
        }).toList();

        if (rides.isEmpty) {
           return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isCompleted ? Icons.history : Icons.directions_car,
                  size: 64,
                  color: AppTheme.textSecondary.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  isCompleted ? 'No completed rides' : 'No current rides',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => _fetchRideHistory(forceRefresh: true),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rides.length,
            separatorBuilder: (context, index) => const Divider(height: 32),
            itemBuilder: (context, index) {
              final ride = rides[index];
              final pickup = ride['pickupLocation']?['address'] ?? 'Unknown Pickup';
              final dropoff = ride['dropoffLocation']?['address'] ?? 'Unknown Dropoff';
              final price = ride['fare'] != null ? '£${ride['fare']}' : '£0.00';
              final status = ride['status'] ?? 'Unknown';
              final dateStr = ride['createdAt'];
              String formattedDate = 'Unknown Date';
              
              if (dateStr != null) {
                try {
                  final date = DateTime.parse(dateStr).toLocal();
                  formattedDate = DateFormat('MMM d, h:mm a').format(date);
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
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      case 'accepted':
      case 'driver_assigned':
        return Colors.blue;
      case 'started':
        return Colors.purple;
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
              status.toUpperCase(),
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
