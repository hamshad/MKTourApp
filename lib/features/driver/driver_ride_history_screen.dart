import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/api_service.dart';
import '../../core/theme.dart';

class DriverRideHistoryScreen extends StatefulWidget {
  const DriverRideHistoryScreen({super.key});

  @override
  State<DriverRideHistoryScreen> createState() => _DriverRideHistoryScreenState();
}

class _DriverRideHistoryScreenState extends State<DriverRideHistoryScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;
  bool _isLoading = true;
  List<dynamic> _rides = [];
  List<dynamic> _scheduledRides = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchAllRides();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchAllRides() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _fetchRideHistory(),
      _fetchScheduledRides(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchRideHistory() async {
    try {
      final response = await _apiService.getDriverRides();
      if (response['success'] == true) {
        _rides = response['data'] as List<dynamic>;
      }
    } catch (_) {}
  }

  Future<void> _fetchScheduledRides() async {
    try {
      final response = await _apiService.getDriverScheduledRides();
      if (response['success'] == true) {
        _scheduledRides = response['data'] as List<dynamic>;
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride History'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppTheme.primaryColor,
          tabs: const [
            Tab(text: 'History'),
            Tab(text: 'Scheduled'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRideList(_rides, false),
                _buildRideList(_scheduledRides, true),
              ],
            ),
    );
  }

  Widget _buildRideList(List<dynamic> rides, bool isScheduled) {
    if (rides.isEmpty) {
      return Center(
        child: Text(
          isScheduled ? 'No scheduled rides' : 'No previous rides',
          style: GoogleFonts.outfit(color: Colors.grey),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchAllRides,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: rides.length,
        itemBuilder: (context, index) {
          final ride = rides[index];
          final status = (ride['status'] ?? 'completed').toString();
          final isCancelled = status.contains('cancelled');
          final pickupAddr =
              ride['pickupLocation']?['address'] ?? 'Unknown Pickup';
          final createdAt = ride['createdAt']?.toString();
          final pickupTime = ride['pickupTime']?.toString();
          final timeStr = isScheduled
              ? _formatDateTime(pickupTime)
              : _formatDateTime(createdAt);

          return GestureDetector(
            onTap: () {
              Navigator.pushNamed(
                context,
                '/driver-ride-detail',
                arguments: ride,
              );
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isScheduled
                          ? Colors.blue.withOpacity(0.1)
                          : (isCancelled
                              ? Colors.red.withOpacity(0.1)
                              : AppTheme.primaryColor.withOpacity(0.1)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      isScheduled ? Icons.calendar_today : Icons.history,
                      color: isScheduled
                          ? Colors.blue
                          : (isCancelled ? Colors.red : AppTheme.primaryColor),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pickupAddr,
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isScheduled ? 'Pickup: $timeStr' : timeStr,
                          style: GoogleFonts.outfit(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '£${(ride['fare'] ?? 0.0).toStringAsFixed(2)}',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: isScheduled
                              ? Colors.blue
                              : (isCancelled ? Colors.red : AppTheme.primaryColor),
                        ),
                      ),
                      Text(
                        _statusLabel(status),
                        style: GoogleFonts.outfit(
                          color: _statusColor(status),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--:--';
    try {
      final date = DateTime.parse(isoString).toLocal();
      return DateFormat('hh:mm a').format(date);
    } catch (_) {
      return '--:--';
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'Completed';
      case 'early_completed':
      case 'earlycompleted':
        return 'Ended Early';
      case 'scheduled':
        return 'Scheduled';
      case 'cancelled_by_user':
        return 'Cancelled by User';
      case 'cancelled_by_driver':
        return 'Cancelled by Driver';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'early_completed':
      case 'earlycompleted':
        return Colors.orange;
      case 'scheduled':
        return Colors.blue;
      case 'cancelled_by_user':
      case 'cancelled_by_driver':
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }
}
