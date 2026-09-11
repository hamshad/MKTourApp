import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/api_service.dart';
import '../../core/theme.dart';
import '../../core/models/scheduled_ride.dart';
import '../../core/widgets/platform_map.dart';

/// Dedicated screen for driver scheduled rides.
///
/// Two tabs:
/// - **Requests**: unassigned pool rides the driver can claim.
/// - **Confirmed**: rides the driver has already claimed.
///
/// Cards show a mini map with pickup (green) / dropoff (red) pins,
/// date-wise partitioning, and action buttons.
class DriverScheduledRidesScreen extends StatefulWidget {
  const DriverScheduledRidesScreen({super.key});

  @override
  State<DriverScheduledRidesScreen> createState() =>
      _DriverScheduledRidesScreenState();
}

class _DriverScheduledRidesScreenState
    extends State<DriverScheduledRidesScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;

  // Requests (pool)
  bool _isPoolLoading = true;
  List<ScheduledRide> _poolRides = [];

  // Confirmed (claimed)
  bool _isConfirmedLoading = true;
  List<ScheduledRide> _confirmedRides = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchAll() async {
    await Future.wait([_fetchPool(), _fetchConfirmed()]);
  }

  Future<void> _fetchPool() async {
    setState(() => _isPoolLoading = true);
    try {
      final response = await _apiService.getScheduledPool();
      debugPrint('🟢 [ScheduledRides] Pool response: $response');
      if (response['success'] == true) {
        final data = response['data'];
        if (data is List) {
          for (final item in data) {
            debugPrint('🟢 [ScheduledRides] Pool ride raw: $item');
            debugPrint('🟢 [ScheduledRides] → fare: ${item['fare']}, type: ${item['fare'].runtimeType}');
          }
        }
        _poolRides = data is List
            ? data.map((e) => ScheduledRide.fromJson(e)).toList()
            : [];
        for (final ride in _poolRides) {
          debugPrint('🟢 [ScheduledRides] Parsed pool ride: ${ride.id}, fare=${ride.fare}, pickup=${ride.pickupLocation.address}');
        }
      } else {
        _poolRides = [];
      }
    } catch (_) {
      _poolRides = [];
    }
    if (mounted) setState(() => _isPoolLoading = false);
  }

  Future<void> _fetchConfirmed() async {
    setState(() => _isConfirmedLoading = true);
    try {
      final response = await _apiService.getDriverScheduledRides();
      debugPrint('🟢 [ScheduledRides] Confirmed response: $response');
      if (response['success'] == true) {
        final data = response['data'];
        if (data is List) {
          for (final item in data) {
            debugPrint('🟢 [ScheduledRides] Confirmed ride raw: $item');
            debugPrint('🟢 [ScheduledRides] → fare: ${item['fare']}, type: ${item['fare'].runtimeType}');
          }
        }
        _confirmedRides = data is List
            ? data.map((e) => ScheduledRide.fromJson(e)).toList()
            : [];
        for (final ride in _confirmedRides) {
          debugPrint('🟢 [ScheduledRides] Parsed confirmed: ${ride.id}, fare=${ride.fare}');
        }
      } else {
        _confirmedRides = [];
      }
    } catch (_) {
      _confirmedRides = [];
    }
    if (mounted) setState(() => _isConfirmedLoading = false);
  }

  Future<void> _claimRide(ScheduledRide ride) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Claim Ride'),
        content: Text(
          'Claim scheduled ride from ${ride.pickupLocation.address}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Claim'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Claiming ride...'),
        duration: Duration(seconds: 1),
      ),
    );

    try {
      final result = await _apiService.acceptRide(ride.id);
      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ride claimed successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
          _fetchAll();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to claim ride'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  /// Disabled-state hint for the Go to Pickup button. Null means enabled:
  /// open within 60 min before pickupTime (overdue counts as open — a
  /// day-of driver must never be stuck with a disabled button).
  String? _pickupHint(ScheduledRide ride, DateTime? pickupTime) {
    if (ride.status != 'scheduled' && ride.status != 'accepted') {
      return 'Already in progress — continue from home';
    }
    if (pickupTime == null) return 'Pickup time unavailable';
    final diff = pickupTime.difference(DateTime.now());
    if (diff.inMinutes > 60) {
      final wait = diff.inHours > 0
          ? '${diff.inHours}h ${diff.inMinutes % 60}m'
          : '${diff.inMinutes}m';
      return 'Available $wait before pickup';
    }
    return null;
  }

  /// Enter the unified execution flow via driver home: pop with rideData
  /// (`isScheduled: true` preserved for the driver_home normalisation
  /// contract) so home adopts it into the instant-ride pickup path.
  /// No execution UI is duplicated here — single entry into the existing
  /// unified arrive/start/stops/complete panel.
  void _goToPickup(ScheduledRide ride) {
    final rideData = ride.toJson();
    rideData['isScheduled'] = true;
    Navigator.pop(context, rideData);
  }

  Widget _buildGoToPickupButton(ScheduledRide ride, DateTime? pickupTime) {
    final hint = _pickupHint(ride, pickupTime);
    final enabled = hint == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: enabled ? () => _goToPickup(ride) : null,
            icon: const Icon(Icons.navigation_outlined, size: 18),
            label: Text(
              'Go to Pickup',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[300],
              disabledForegroundColor: Colors.grey[600],
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
        ],
      ],
    );
  }

  void _showCancelDialog(ScheduledRide ride) {
    String? selectedReason;
    bool showReasonError = false;
    bool isLoading = false;
    String? error;

    final reasons = [
      {'value': 'vehicle_breakdown', 'label': 'Vehicle breakdown'},
      {'value': 'safety_concern', 'label': 'Safety concern'},
      {'value': 'personal_emergency', 'label': 'Personal emergency'},
      {'value': 'traffic_too_heavy', 'label': 'Traffic too heavy'},
      {'value': 'other', 'label': 'Other'},
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Cancel Ride'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cancel scheduled ride from ${ride.pickupLocation.address}?',
                ),
                const SizedBox(height: 16),
                Text(
                  'Reason:',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: reasons
                      .map(
                        (r) => ChoiceChip(
                          label: Text(r['label']!),
                          selected: selectedReason == r['value'],
                          onSelected: isLoading
                              ? null
                              : (selected) => setDialogState(() {
                                    selectedReason =
                                        selected ? r['value'] : null;
                                    showReasonError = false;
                                  }),
                        ),
                      )
                      .toList(),
                ),
                if (showReasonError) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Please select a reason',
                    style: TextStyle(color: AppTheme.errorColor, fontSize: 12),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: TextStyle(color: AppTheme.errorColor, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: const Text('Go Back'),
            ),
            ElevatedButton(
              onPressed: isLoading || selectedReason == null
                  ? null
                  : () async {
                      setDialogState(() => isLoading = true);
                      try {
                        final result =
                            await _apiService.cancelScheduledRideDriver(
                          ride.id,
                          reason: selectedReason,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (result['success'] == true) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Ride cancelled'),
                                backgroundColor: AppTheme.successColor,
                              ),
                            );
                            _fetchAll();
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  result['message'] ?? 'Failed to cancel',
                                ),
                                backgroundColor: AppTheme.errorColor,
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: AppTheme.errorColor,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
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
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Scheduled Rides',
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textSecondary,
              labelStyle: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              unselectedLabelStyle: GoogleFonts.outfit(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              dividerColor: Colors.transparent,
              tabs: [
                Tab(text: 'Requests (${_poolRides.length})'),
                Tab(text: 'Confirmed (${_confirmedRides.length})'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRequestsTab(),
          _buildConfirmedTab(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Requests Tab (pool)
  // ---------------------------------------------------------------------------

  Widget _buildRequestsTab() {
    if (_isPoolLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_poolRides.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No requests available',
              style: GoogleFonts.outfit(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check back later for scheduled rides',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    final grouped = _groupByDate(_poolRides);
    return RefreshIndicator(
      onRefresh: _fetchPool,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: grouped.length,
        itemBuilder: (context, sectionIndex) {
          final section = grouped[sectionIndex];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  section.label,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              // Cards
              ...section.rides.map(
                (ride) => _buildRequestCard(ride),
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRequestCard(ScheduledRide ride) {
    final pickupTime = _parsePickupTime(ride.scheduledPickupTime);
    final pickupLat =
        ride.pickupLocation.coordinates != null && ride.pickupLocation.coordinates!.length >= 2
            ? ride.pickupLocation.coordinates![1]
            : null;
    final pickupLng =
        ride.pickupLocation.coordinates != null && ride.pickupLocation.coordinates!.length >= 2
            ? ride.pickupLocation.coordinates![0]
            : null;
    final dropoffLat =
        ride.dropoffLocation.coordinates != null && ride.dropoffLocation.coordinates!.length >= 2
            ? ride.dropoffLocation.coordinates![1]
            : null;
    final dropoffLng =
        ride.dropoffLocation.coordinates != null && ride.dropoffLocation.coordinates!.length >= 2
            ? ride.dropoffLocation.coordinates![0]
            : null;

    final hasCoords =
        pickupLat != null && pickupLng != null && dropoffLat != null && dropoffLng != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mini map
          if (hasCoords)
            _buildMiniMap(
              pickupLat: pickupLat,
              pickupLng: pickupLng,
              dropoffLat: dropoffLat,
              dropoffLng: dropoffLng,
            ),

          // Ride info
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Time + Fare row
                Row(
                  children: [
                    if (pickupTime != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          DateFormat('MMM d, h:mm a').format(pickupTime),
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildCountdownBadge(pickupTime),
                    ],
                    const Spacer(),
                    Text(
                      '£${ride.fare.toStringAsFixed(2)}',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Pickup
                _buildLocationRow(
                  icon: Icons.circle,
                  iconColor: AppTheme.successColor,
                  label: 'Pickup',
                  address: ride.pickupLocation.address,
                ),
                const SizedBox(height: 6),

                // Dropoff
                _buildLocationRow(
                  icon: Icons.location_on,
                  iconColor: AppTheme.errorColor,
                  label: 'Dropoff',
                  address: ride.dropoffLocation.address,
                ),

                // Meta row
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (ride.user != null) ...[
                      Icon(Icons.person_outline, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        (ride.user as Map)['name']?.toString() ?? 'Passenger',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Icon(Icons.directions_car, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      '${ride.distance.toStringAsFixed(1)} mi',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (ride.stops.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.stop_circle, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        '${ride.stops.length} stop${ride.stops.length > 1 ? 's' : ''}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),

                // Claim button
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _claimRide(ride),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(
                      'Claim Ride',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Confirmed Tab
  // ---------------------------------------------------------------------------

  Widget _buildConfirmedTab() {
    if (_isConfirmedLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_confirmedRides.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No confirmed rides',
              style: GoogleFonts.outfit(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Claimed rides will appear here',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    final grouped = _groupByDate(_confirmedRides);
    return RefreshIndicator(
      onRefresh: _fetchConfirmed,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: grouped.length,
        itemBuilder: (context, sectionIndex) {
          final section = grouped[sectionIndex];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  section.label,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ...section.rides.map(
                (ride) => _buildConfirmedCard(ride),
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConfirmedCard(ScheduledRide ride) {
    final pickupTime = _parsePickupTime(ride.scheduledPickupTime);
    final pickupLat =
        ride.pickupLocation.coordinates != null && ride.pickupLocation.coordinates!.length >= 2
            ? ride.pickupLocation.coordinates![1]
            : null;
    final pickupLng =
        ride.pickupLocation.coordinates != null && ride.pickupLocation.coordinates!.length >= 2
            ? ride.pickupLocation.coordinates![0]
            : null;
    final dropoffLat =
        ride.dropoffLocation.coordinates != null && ride.dropoffLocation.coordinates!.length >= 2
            ? ride.dropoffLocation.coordinates![1]
            : null;
    final dropoffLng =
        ride.dropoffLocation.coordinates != null && ride.dropoffLocation.coordinates!.length >= 2
            ? ride.dropoffLocation.coordinates![0]
            : null;

    final hasCoords =
        pickupLat != null && pickupLng != null && dropoffLat != null && dropoffLng != null;

    // Status chip
    final statusColor = _statusColor(ride.status);
    final statusLabel = _statusLabel(ride.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mini map
          if (hasCoords)
            _buildMiniMap(
              pickupLat: pickupLat,
              pickupLng: pickupLng,
              dropoffLat: dropoffLat,
              dropoffLng: dropoffLng,
            ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Time + Status + Fare row
                Row(
                  children: [
                    if (pickupTime != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          DateFormat('MMM d, h:mm a').format(pickupTime),
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildCountdownBadge(pickupTime),
                    ],
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '£${ride.fare.toStringAsFixed(2)}',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Pickup
                _buildLocationRow(
                  icon: Icons.circle,
                  iconColor: AppTheme.successColor,
                  label: 'Pickup',
                  address: ride.pickupLocation.address,
                ),
                const SizedBox(height: 6),

                // Dropoff
                _buildLocationRow(
                  icon: Icons.location_on,
                  iconColor: AppTheme.errorColor,
                  label: 'Dropoff',
                  address: ride.dropoffLocation.address,
                ),

                // Meta
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (ride.user != null) ...[
                      Icon(Icons.person_outline, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        (ride.user as Map)['name']?.toString() ?? 'Passenger',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Icon(Icons.directions_car, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      '${ride.distance.toStringAsFixed(1)} mi',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (ride.stops.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.stop_circle, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        '${ride.stops.length} stop${ride.stops.length > 1 ? 's' : ''}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),

                // Go to Pickup (unified execution entry — always visible,
                // disabled with countdown hint outside the pickup window)
                const SizedBox(height: 12),
                _buildGoToPickupButton(ride, pickupTime),
                const SizedBox(height: 8),
                // Cancel button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showCancelDialog(ride),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: Text(
                      'Cancel Ride',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.errorColor,
                      side: const BorderSide(color: AppTheme.errorColor),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared widgets
  // ---------------------------------------------------------------------------

  Widget _buildMiniMap({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  }) {
    final centerLat = (pickupLat + dropoffLat) / 2;
    final centerLng = (pickupLng + dropoffLng) / 2;

    // Build bounds to fit both markers
    final minLat = pickupLat < dropoffLat ? pickupLat : dropoffLat;
    final maxLat = pickupLat > dropoffLat ? pickupLat : dropoffLat;
    final minLng = pickupLng < dropoffLng ? pickupLng : dropoffLng;
    final maxLng = pickupLng > dropoffLng ? pickupLng : dropoffLng;

    final padding = 0.005; // ~500m padding
    final bounds = LatLngBounds(
      southwest: LatLng(minLat - padding, minLng - padding),
      northeast: LatLng(maxLat + padding, maxLng + padding),
    );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SizedBox(
        height: 130,
        child: Stack(
          children: [
            PlatformMap(
              initialLat: centerLat,
              initialLng: centerLng,
              interactive: false,
              bounds: bounds,
              markers: [
                MapMarker(
                  id: 'pickup',
                  lat: pickupLat,
                  lng: pickupLng,
                  title: 'Pickup',
                  markerColor: AppTheme.successColor,
                ),
                MapMarker(
                  id: 'dropoff',
                  lat: dropoffLat,
                  lng: dropoffLng,
                  title: 'Dropoff',
                  markerColor: AppTheme.errorColor,
                ),
              ],
            ),
            // Gradient overlay at bottom for readability
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 30,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.white.withOpacity(0.9),
                    ],
                  ),
                ),
              ),
            ),
            // Legend dots
            Positioned(
              right: 8,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppTheme.successColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '→',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        color: Colors.grey[500],
                      ),
                    ),
                    const SizedBox(width: 3),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppTheme.errorColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String address,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                address.isNotEmpty ? address : 'Unknown',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownBadge(DateTime pickupTime) {
    final now = DateTime.now();
    final diff = pickupTime.difference(now);
    String text;
    Color bgColor;
    Color textColor;

    if (diff.isNegative) {
      text = 'Overdue';
      bgColor = AppTheme.errorColor.withOpacity(0.1);
      textColor = AppTheme.errorColor;
    } else if (diff.inHours >= 1) {
      text = '${diff.inHours}h ${diff.inMinutes % 60}m';
      bgColor = Colors.blue[50]!;
      textColor = Colors.blue[700]!;
    } else {
      text = '${diff.inMinutes}m';
      bgColor = AppTheme.warningColor.withOpacity(0.15);
      textColor = Colors.orange[800]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  DateTime? _parsePickupTime(String? iso) {
    if (iso == null) return null;
    try {
      return DateTime.parse(iso).toLocal();
    } catch (_) {
      return null;
    }
  }

  List<_DateSection> _groupByDate(List<ScheduledRide> rides) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    // Sort by pickup time
    final sorted = List<ScheduledRide>.from(rides);
    sorted.sort((a, b) {
      final aTime = _parsePickupTime(a.scheduledPickupTime);
      final bTime = _parsePickupTime(b.scheduledPickupTime);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return aTime.compareTo(bTime);
    });

    // Partition by date
    final Map<String, List<ScheduledRide>> groups = {};
    for (final ride in sorted) {
      final pickupTime = _parsePickupTime(ride.scheduledPickupTime);
      String key;
      if (pickupTime == null) {
        key = 'Unknown Date';
      } else {
        final rideDate = DateTime(
          pickupTime.year,
          pickupTime.month,
          pickupTime.day,
        );
        if (rideDate == today) {
          key = 'Today';
        } else if (rideDate == tomorrow) {
          key = 'Tomorrow';
        } else {
          key = DateFormat('EEEE, MMM d').format(pickupTime);
        }
      }
      groups.putIfAbsent(key, () => []).add(ride);
    }

    return groups.entries
        .map((e) => _DateSection(label: e.key, rides: e.value))
        .toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'accepted':
        return Colors.blue;
      case 'arrived':
      case 'driver_arrived':
        return Colors.orange;
      case 'in_progress':
        return AppTheme.primaryColor;
      case 'completed':
      case 'early_completed':
        return AppTheme.successColor;
      case 'cancelled':
      case 'cancelled_by_user':
      case 'cancelled_by_driver':
        return AppTheme.errorColor;
      case 'expired':
        return Colors.grey;
      default:
        return AppTheme.primaryColor;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'scheduled':
        return 'Scheduled';
      case 'accepted':
        return 'Claimed';
      case 'arrived':
      case 'driver_arrived':
        return 'Arrived';
      case 'in_progress':
        return 'In Progress';
      case 'at_stop':
        return 'At Stop';
      case 'completed':
        return 'Completed';
      case 'early_completed':
        return 'Early Complete';
      case 'cancelled':
        return 'Cancelled';
      case 'cancelled_by_user':
        return 'Cancelled by Rider';
      case 'cancelled_by_driver':
        return 'Cancelled by You';
      case 'expired':
        return 'Expired';
      default:
        return status.toUpperCase();
    }
  }
}

class _DateSection {
  final String label;
  final List<ScheduledRide> rides;
  const _DateSection({required this.label, required this.rides});
}
