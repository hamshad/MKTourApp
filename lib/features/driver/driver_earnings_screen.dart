import 'package:flutter/material.dart';

import '../../core/api_service.dart';
import '../../core/models/toll_breakdown.dart';
import '../../core/theme.dart';

/// Driver earnings dashboard — live data from the spec §2.2 summary and
/// §2.3 rides endpoints (phase 21-04, TOLL-06).
///
/// Period tabs map to the API `period` values (Today/Week/Month/All —
/// spec §2.2 dashboard tabs; the API also accepts `yesterday` but no tab
/// exposes it). KPI tiles sit per spec §5: **Tolls Reimbursed** beside
/// Net Earnings, value verbatim from `tollsReimbursedTotal`. Every scalar
/// read is tolerant (never throws) and per-ride toll lines are gated on
/// `tollFee > 0` so legacy rides render exactly as before.
class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

/// Never-throw scalar read: num → double, numeric string → parsed,
/// anything else → 0.0. Mirrors `TollInfo._coerce` style.
double earningsNumOf(dynamic v) =>
    v is num ? v.toDouble() : num.tryParse('$v')?.toDouble() ?? 0.0;

/// `payoutStatus` read — absent / non-map → null (row not rendered).
Map<String, dynamic>? earningsPayoutStatus(Map<String, dynamic>? data) {
  final v = data?['payoutStatus'];
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

/// Rendering gate for the per-ride toll line: shown only when fee > 0.
bool showEarningsTollLine(double tollFee) => tollFee > 0;

/// Month abbreviations for the two date rows (no `intl` dependency —
/// `intl` is not a direct pubspec dependency and importing it would add
/// a new analyzer issue).
const List<String> _monthAbbrevs = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  final ApiService _apiService = ApiService();

  // Spec §2.2 dashboard tabs. `Yesterday` is a valid API value but is
  // intentionally not exposed as a tab (see class docs).
  static const List<String> _periodLabels = [
    'Today',
    'Week',
    'Month',
    'All',
  ];
  static const List<String> _periodValues = [
    'today',
    'week',
    'month',
    'all',
  ];

  int _periodIndex = 1; // Week — spec §2.2 example period
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _summary;
  List<dynamic> _rides = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  String get _period => _periodValues[_periodIndex];

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final summaryRes =
        await _apiService.getDriverEarningsSummary(period: _period);
    final ridesRes = await _apiService.getDriverEarningsRides(period: _period);
    if (!mounted) return;

    final summaryOk = summaryRes['success'] == true;
    final ridesOk = ridesRes['success'] == true;
    if (!summaryOk || !ridesOk) {
      final failing = !summaryOk ? summaryRes : ridesRes;
      setState(() {
        _isLoading = false;
        _error = failing['message']?.toString() ?? 'Could not load earnings.';
      });
      return;
    }

    final summaryData = summaryRes['data'];
    final ridesData = ridesRes['data'];
    final rides = ridesData is Map ? ridesData['rides'] : null;

    setState(() {
      _isLoading = false;
      _summary = summaryData is Map
          ? Map<String, dynamic>.from(summaryData)
          : <String, dynamic>{};
      _rides = rides is List ? List<dynamic>.from(rides) : <dynamic>[];
    });
  }

  void _selectPeriod(int index) {
    if (index == _periodIndex) return;
    setState(() => _periodIndex = index);
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppTheme.errorColor),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Could not load earnings.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _fetch,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final summary = _summary ?? <String, dynamic>{};
    final payout = earningsPayoutStatus(_summary);
    final metrics = summary is Map<String, dynamic> ? (summary['metrics'] as Map<String, dynamic>?) ?? <String, dynamic>{} : <String, dynamic>{};

    return RefreshIndicator(
      onRefresh: _fetch,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Period tabs: Today | Week | Month | All
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < _periodLabels.length; i++)
                    _buildToggleOption(_periodLabels[i], i),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // KPI tiles — spec §5: Tolls Reimbursed beside Net Earnings.
            Row(
              children: [
                Expanded(
                  child: _buildKpiCard(
                    label: 'Net Earnings',
                    value: _money(earningsNumOf(metrics['netEarnings'])),
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildKpiCard(
                    label: 'Tolls Reimbursed',
                    // Absent field → £0.00, never a crash.
                    value: _money(
                        earningsNumOf(metrics['tollsReimbursedTotal'])),
                    color: AppTheme.successColor,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Supporting breakdown rows.
            _buildBreakdownItem(
                'Trips Completed',
                earningsNumOf(metrics['totalRides']).toStringAsFixed(0)),
            _buildBreakdownItem('Online Hours',
                earningsNumOf(metrics['onlineHours'] ?? 0.0).toStringAsFixed(1)),
            _buildBreakdownItem(
                'Gross Fares', _money(earningsNumOf(metrics['grossFare']))),
            _buildBreakdownItem(
                'Platform Deductions', _money(earningsNumOf(metrics['platformFee']))),
            // Total earnings rendered verbatim from the payload.
            _buildBreakdownItem(
                'Total Earnings', _money(earningsNumOf(metrics['netEarnings']))),

            if (payout != null) ...[
              _buildPayoutRow(payout),
            ],

            const SizedBox(height: 24),

            // Itemized rides list (§2.3).
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent Trips',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_rides.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No rides yet',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              )
            else
              ..._rides.map(_buildRideTile),
          ],
        ),
      ),
    );
  }

  String _money(double value) => '£${value.toStringAsFixed(2)}';

  Widget _buildKpiCard({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayoutRow(Map<String, dynamic> payout) {
    final balance = earningsNumOf(payout['unsettledBalance']);
    final dateRaw = payout['nextPayoutDate']?.toString();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next Payout · ${_money(balance)} unsettled',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (dateRaw != null && dateRaw.isNotEmpty)
                  Text(
                    'Expected ${_formatPayoutDate(dateRaw)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatPayoutDate(String iso) {
    try {
      final date = DateTime.parse(iso).toLocal();
      return '${date.day} ${_monthAbbrevs[date.month - 1]} ${date.year}';
    } catch (_) {
      return iso;
    }
  }

  Widget _buildToggleOption(String text, int index) {
    final isSelected = _periodIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _selectPeriod(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBreakdownItem(String label, String amount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: AppTheme.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            amount,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRideTile(dynamic rideRaw) {
    final ride = rideRaw is Map ? Map<String, dynamic>.from(rideRaw) : null;
    if (ride == null) return const SizedBox.shrink();

    final earnings = earningsNumOf(ride['driverEarnings']);
    final toll = TollInfo.fromBreakdown(ride);
    final pickup = ride['pickupAddress']?.toString() ?? 'Unknown pickup';
    final dropoff = ride['dropoffAddress']?.toString() ?? '';
    final timeStr = _formatCompletedAt(ride['completedAt']?.toString());
    final payment = ride['paymentType']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.directions_car,
                color: AppTheme.textSecondary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dropoff.isEmpty ? pickup : '$pickup → $dropoff',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (timeStr.isNotEmpty) timeStr,
                    if (payment.isNotEmpty) _paymentLabel(payment),
                  ].join(' · '),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                // Per-ride toll, gated: absent toll renders the plain row.
                if (showEarningsTollLine(toll.tollFee))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Toll · ${toll.tollName ?? 'Toll'} ${_money(toll.tollFee)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            _money(earnings),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  String _paymentLabel(String payment) {
    if (payment.isEmpty) return payment;
    return payment[0].toUpperCase() + payment.substring(1).toLowerCase();
  }

  String _formatCompletedAt(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final date = DateTime.parse(iso).toLocal();
      final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
      final minute = date.minute.toString().padLeft(2, '0');
      final suffix = date.hour < 12 ? 'AM' : 'PM';
      return '${date.day} ${_monthAbbrevs[date.month - 1]}, '
          '$hour12:$minute $suffix';
    } catch (_) {
      return iso;
    }
  }
}
