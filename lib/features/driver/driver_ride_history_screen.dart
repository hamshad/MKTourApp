import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/api_service.dart';
import '../../core/theme.dart';
import '../../core/services/payment_service.dart';
import '../../core/models/error_display_helper.dart';
import '../../core/widgets/custom_snackbar.dart';

class DriverRideHistoryScreen extends StatefulWidget {
  const DriverRideHistoryScreen({super.key});

  @override
  State<DriverRideHistoryScreen> createState() =>
      _DriverRideHistoryScreenState();
}

class _DriverRideHistoryScreenState extends State<DriverRideHistoryScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;

  // History state
  bool _isHistoryLoading = true;
  List<dynamic> _rides = [];

  // Scheduled rides state
  bool _isScheduledLoading = true;
  List<dynamic> _scheduledRides = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchAllRides();
    _fetchScheduledRides();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchAllRides() async {
    setState(() => _isHistoryLoading = true);
    try {
      final response = await _apiService.getDriverRides();
      if (response['success'] == true) {
        _rides = response['data'] as List<dynamic>;
      }
    } catch (_) {}
    if (mounted) setState(() => _isHistoryLoading = false);
  }

  Future<void> _fetchScheduledRides() async {
    setState(() => _isScheduledLoading = true);
    try {
      final response = await _apiService.getDriverScheduledRides();
      if (response['success'] == true) {
        _scheduledRides = response['data'] as List<dynamic>;
      }
    } catch (_) {}
    if (mounted) setState(() => _isScheduledLoading = false);
  }

  Future<void> _refreshAll() async {
    await Future.wait([_fetchAllRides(), _fetchScheduledRides()]);
  }

  void _showCancelDialog(Map<String, dynamic> ride) {
    String? selectedReason;
    bool showReasonError = false;
    bool sheetLoading = false;
    String? sheetError;

    final reasons = [
      {'value': 'rider_no_show', 'label': 'Rider no-show'},
      {'value': 'rider_unreachable', 'label': 'Rider unreachable'},
      {'value': 'safety_concern', 'label': 'Safety concern'},
      {'value': 'vehicle_breakdown', 'label': 'Vehicle breakdown'},
      {'value': 'vehicle_issue', 'label': 'Vehicle issue'},
      {'value': 'driver_no_show', 'label': "Can't make it"},
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cancel Scheduled Ride'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select a reason for cancellation:'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: reasons
                      .map(
                        (reason) => ChoiceChip(
                          label: Text(reason['label']!),
                          selected: selectedReason == reason['value'],
                          onSelected: sheetLoading
                              ? null
                              : (selected) => setDialogState(() {
                                    selectedReason =
                                        selected ? reason['value'] : null;
                                    showReasonError = false;
                                  }),
                        ),
                      )
                      .toList(),
                ),
                if (showReasonError) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Please select a reason to continue.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
                if (sheetError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    sheetError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sheetLoading ? null : () => Navigator.pop(context),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: sheetLoading
                  ? null
                  : () async {
                      if (selectedReason == null) {
                        setDialogState(() => showReasonError = true);
                        return;
                      }
                      setDialogState(() {
                        sheetLoading = true;
                        sheetError = null;
                      });
                      try {
                        final response =
                            await PaymentService.cancelScheduledRideDriver(
                          ride['_id']?.toString() ?? '',
                          selectedReason!,
                        );
                        if (!mounted) return;
                        if (response['success'] == true) {
                          Navigator.pop(context);
                          CustomSnackbar.show(
                            context,
                            message:
                                response['message'] ?? 'Ride cancelled',
                            type: SnackbarType.info,
                          );
                          _fetchScheduledRides();
                        } else {
                          final info = RideErrorMapper.map(
                            response['message']?.toString() ??
                                'Failed to cancel',
                            response['errors'],
                          );
                          setDialogState(() {
                            sheetLoading = false;
                            sheetError = '${info.title}: ${info.copy}';
                          });
                        }
                      } catch (e) {
                        setDialogState(() {
                          sheetLoading = false;
                          sheetError = 'Error cancelling ride: $e';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: sheetLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Cancel Ride'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Rides'),
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
      body: TabBarView(
        controller: _tabController,
        children: [
          // History tab
          _isHistoryLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildRideList(_rides),
          // Scheduled tab
          _isScheduledLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildScheduledList(_scheduledRides),
        ],
      ),
    );
  }

  Widget _buildRideList(List<dynamic> rides) {
    if (rides.isEmpty) {
      return Center(
        child: Text(
          'No previous rides',
          style: GoogleFonts.outfit(color: Colors.grey),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshAll,
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
                      color: isCancelled ? Colors.red : AppTheme.primaryColor,
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
                          color:
                              isCancelled ? Colors.red : AppTheme.primaryColor,
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

  Widget _buildScheduledList(List<dynamic> rides) {
    if (rides.isEmpty) {
      return Center(
        child: Text(
          'No scheduled rides',
          style: GoogleFonts.outfit(color: Colors.grey),
        ),
      );
    }

    // Partition into upcoming (within 24h) and later
    final now = DateTime.now();
    final upcoming = <dynamic>[];
    final later = <dynamic>[];

    for (final ride in rides) {
      final pickupTimeStr = ride['scheduledPickupTime']?.toString();
      if (pickupTimeStr == null) {
        later.add(ride);
        continue;
      }
      try {
        final pickupTime = DateTime.parse(pickupTimeStr).toLocal();
        final diff = pickupTime.difference(now);
        if (diff.inHours < 24 && !diff.isNegative) {
          upcoming.add(ride);
        } else {
          later.add(ride);
        }
      } catch (_) {
        later.add(ride);
      }
    }

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (upcoming.isNotEmpty) ...[
            Text(
              'Upcoming (next 24h)',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...upcoming.map((ride) => _buildScheduledTile(ride)),
            const SizedBox(height: 20),
          ],
          if (later.isNotEmpty) ...[
            Text(
              'Later',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...later.map((ride) => _buildScheduledTile(ride)),
          ],
        ],
      ),
    );
  }

  Widget _buildScheduledTile(dynamic ride) {
    final pickupAddr =
        ride['pickupLocation']?['address'] ?? 'Unknown Pickup';
    final dropoffAddr = ride['dropoffLocation']?['address'] ?? '';
    final fare = (ride['fare'] as num?)?.toDouble() ?? 0.0;
    final pickupTimeStr = ride['scheduledPickupTime']?.toString();

    String countdown = '';
    if (pickupTimeStr != null) {
      try {
        final pickupTime = DateTime.parse(pickupTimeStr).toLocal();
        final diff = pickupTime.difference(DateTime.now());
        if (diff.isNegative) {
          countdown = 'Overdue';
        } else if (diff.inHours > 24) {
          countdown = '${diff.inDays}d ${diff.inHours % 24}h';
        } else if (diff.inHours > 0) {
          countdown = '${diff.inHours}h ${diff.inMinutes % 60}m';
        } else {
          countdown = '${diff.inMinutes}m';
        }
      } catch (_) {}
    }

    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/driver-ride-detail',
          arguments: ride,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.calendar_month,
                    color: AppTheme.primaryColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pickupAddr,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (dropoffAddr.isNotEmpty)
                        Text(
                          '→ $dropoffAddr',
                          style: GoogleFonts.outfit(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Text(
                  '£${fare.toStringAsFixed(2)}',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (pickupTimeStr != null) ...[
                  Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    _formatScheduledTime(pickupTimeStr),
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const Spacer(),
                ] else
                  const Spacer(),
                if (countdown.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: countdown == 'Overdue'
                          ? Colors.red[50]
                          : Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      countdown,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: countdown == 'Overdue'
                            ? Colors.red[700]
                            : Colors.blue[700],
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _showCancelDialog(ride as Map<String, dynamic>),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.red[700],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
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

  String _formatScheduledTime(String isoString) {
    try {
      final date = DateTime.parse(isoString).toLocal();
      return DateFormat('EEE, MMM d @ hh:mm a').format(date);
    } catch (_) {
      return isoString;
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
