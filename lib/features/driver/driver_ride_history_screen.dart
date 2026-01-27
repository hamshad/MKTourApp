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

class _DriverRideHistoryScreenState extends State<DriverRideHistoryScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  List<dynamic> _rides = [];

  @override
  void initState() {
    super.initState();
    _fetchRideHistory();
  }

  Future<void> _fetchRideHistory() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.getDriverRides();
      if (response['success'] == true) {
        setState(() {
          _rides = response['data'] as List<dynamic>;
        });
      }
    } catch (_) {
      // no-op
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride History'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rides.isEmpty
              ? Center(
                  child: Text(
                    'No rides yet',
                    style: GoogleFonts.outfit(color: Colors.grey),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchRideHistory,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _rides.length,
                    itemBuilder: (context, index) {
                      final ride = _rides[index];
                      final status = (ride['status'] ?? 'completed').toString();
                      final isCancelled = status.contains('cancelled');
                      final pickupAddr =
                          ride['pickupLocation']?['address'] ?? 'Unknown Pickup';
                      final createdAt = ride['createdAt']?.toString();
                      final timeStr = _formatDateTime(createdAt);

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
                                  color: isCancelled
                                      ? Colors.red.withOpacity(0.1)
                                      : AppTheme.primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  Icons.history,
                                  color: isCancelled
                                      ? Colors.red
                                      : AppTheme.primaryColor,
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
                                      timeStr,
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
                                      color: isCancelled
                                          ? Colors.red
                                          : AppTheme.primaryColor,
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
      case 'cancelled_by_user':
      case 'cancelled_by_driver':
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }
}
