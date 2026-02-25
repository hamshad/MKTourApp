import 'package:flutter/material.dart';
import '../../core/api_service.dart';
import '../../core/theme.dart';

/// Full-screen sheet showing the user's Free Ride promo progress.
///
/// Promo rule: Every user's 6th completed ride (i.e. after 5 completed rides)
/// gets a £4.45 discount, valid only within Milton Keynes.
/// One-time use — status is one of: "none" | "eligible" | "claimed".
class PromoStatusScreen extends StatefulWidget {
  const PromoStatusScreen({super.key});

  @override
  State<PromoStatusScreen> createState() => _PromoStatusScreenState();
}

class _PromoStatusScreenState extends State<PromoStatusScreen> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  String? _error;

  // Data from API
  int _completedRides = 0;
  String _promoStatus = 'none'; // "none" | "eligible" | "claimed"
  int _ridesUntilEligible = 5;
  bool _isEligible = false;
  bool _isClaimed = false;
  String _statusMessage = '';

  static const int _totalRidesRequired = 5;
  static const double _promoDiscount = 4.45;

  @override
  void initState() {
    super.initState();
    _loadPromoStatus();
  }

  Future<void> _loadPromoStatus() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _apiService.getPromoStatus();
      if (response['success'] == true && response['data'] != null) {
        final data = response['data'] as Map<String, dynamic>;
        setState(() {
          _completedRides = (data['completedRides'] as num?)?.toInt() ?? 0;
          _promoStatus = data['promoStatus']?.toString() ?? 'none';
          _ridesUntilEligible =
              (data['ridesUntilEligible'] as num?)?.toInt() ?? 0;
          _isEligible = data['isEligible'] == true;
          _isClaimed = data['isClaimed'] == true;
          _statusMessage = data['message']?.toString() ?? '';
        });
      } else {
        setState(() {
          _error = response['message']?.toString() ?? 'Failed to load promo status';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not load promo status. Please try again.';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // The progress fraction (capped at 1.0 once eligible/claimed)
  double get _progressFraction {
    final capped = _completedRides.clamp(0, _totalRidesRequired);
    return capped / _totalRidesRequired;
  }

  Color get _statusColor {
    switch (_promoStatus) {
      case 'eligible':
        return const Color(0xFF22C55E); // green
      case 'claimed':
        return Colors.grey;
      default:
        return AppTheme.primaryColor; // orange
    }
  }

  String get _statusLabel {
    switch (_promoStatus) {
      case 'eligible':
        return 'FREE RIDE READY';
      case 'claimed':
        return 'CLAIMED';
      default:
        return 'IN PROGRESS';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Free Ride Promo',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _loadPromoStatus,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeroCard(),
                        const SizedBox(height: 28),
                        _buildProgressSection(),
                        const SizedBox(height: 28),
                        _buildHowItWorksSection(),
                        const SizedBox(height: 28),
                        _buildDiscountTableSection(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadPromoStatus,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    final cardColor = _isClaimed
        ? Colors.grey[100]!
        : _isEligible
            ? const Color(0xFFD1FAE5) // light green
            : const Color(0xFFFFF7ED); // light orange

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isClaimed
              ? Colors.grey[300]!
              : _isEligible
                  ? const Color(0xFF86EFAC)
                  : const Color(0xFFFDBA74),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _statusColor,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              _statusLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Main headline
          Text(
            _isClaimed
                ? 'Free Ride Used 🎉'
                : _isEligible
                    ? '🎁 Your Free Ride is Ready!'
                    : '🚗 Earn Your Free MK Ride',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            _statusMessage.isNotEmpty
                ? _statusMessage
                : _isClaimed
                    ? 'You have already claimed your free ride. Thank you for riding with MK Tours!'
                    : _isEligible
                        ? 'Book any ride within Milton Keynes to get up to £${_promoDiscount.toStringAsFixed(2)} off!'
                        : 'Complete $_ridesUntilEligible more ride${_ridesUntilEligible == 1 ? '' : 's'} to unlock a free MK ride!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.black.withOpacity(0.6),
              height: 1.4,
            ),
          ),

          if (_isEligible && !_isClaimed) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.local_offer, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Up to £4.45 discount applied automatically',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressSection() {
    final progressPercent =
        (_progressFraction * 100).clamp(0, 100).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your Progress',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _progressFraction,
            minHeight: 14,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(_statusColor),
          ),
        ),
        const SizedBox(height: 10),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$_completedRides / $_totalRidesRequired rides completed',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            Text(
              '$progressPercent%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _statusColor,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Milestone dots
        Row(
          children: List.generate(_totalRidesRequired, (i) {
            final filled = i < _completedRides;
            final isCurrent = i == _completedRides && !_isEligible && !_isClaimed;
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: filled
                            ? _statusColor
                            : isCurrent
                                ? _statusColor.withOpacity(0.2)
                                : Colors.grey[200],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: filled || isCurrent
                              ? _statusColor
                              : Colors.grey[300]!,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: filled
                            ? const Icon(Icons.check, color: Colors.white, size: 18)
                            : Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isCurrent
                                      ? _statusColor
                                      : Colors.grey[500],
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),

        const SizedBox(height: 12),

        Center(
          child: Text(
            _isClaimed
                ? 'Promo used — thank you for riding with MK Tours!'
                : _isEligible
                    ? '5 rides complete — book in Milton Keynes to claim!'
                    : '$_ridesUntilEligible more ride${_ridesUntilEligible == 1 ? '' : 's'} to go!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHowItWorksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How it works',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        _buildStepRow(
          icon: Icons.directions_car,
          color: AppTheme.primaryColor,
          title: 'Complete 5 rides',
          subtitle: 'Any rides of any type count toward your progress.',
        ),
        _buildStepRow(
          icon: Icons.location_on,
          color: Colors.blue,
          title: 'Book within Milton Keynes',
          subtitle:
              'Your 6th ride must be within Milton Keynes to apply the promo.',
        ),
        _buildStepRow(
          icon: Icons.local_offer,
          color: const Color(0xFF22C55E),
          title: 'Up to £4.45 off — automatically',
          subtitle:
              'The discount is applied instantly. Fully free if fare ≤ £4.45, otherwise you pay the remainder.',
        ),
        _buildStepRow(
          icon: Icons.confirmation_number,
          color: Colors.purple,
          title: 'One-time use only',
          subtitle:
              'The promo can only be claimed once per account.',
          isLast: true,
        ),
      ],
    );
  }

  Widget _buildStepRow({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 28,
                color: Colors.grey[200],
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDiscountTableSection() {
    const rows = [
      ('£3.80', '£3.80', '£0.00', true),
      ('£4.45', '£4.45', '£0.00', true),
      ('£10.00', '£4.45', '£5.55', false),
      ('£22.00', '£4.45', '£17.55', false),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Discount Examples',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[200]!),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Fare',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Discount',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'You Pay',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ...rows.asMap().entries.map((entry) {
                final i = entry.key;
                final row = entry.value;
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      color: i.isEven ? Colors.white : Colors.grey[50],
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.$1,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '- ${row.$2}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF22C55E),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (row.$4)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22C55E)
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      row.$3,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF22C55E),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                else
                                  Text(
                                    row.$3,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (i < rows.length - 1)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  ],
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '* The promo applies a fixed £4.45 discount. If the fare is lower, the ride is fully free.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[500],
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
