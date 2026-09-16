import 'package:flutter/material.dart';
import '../../core/api_service.dart';
import '../../core/models/outstanding_balance.dart';
import '../../core/services/socket_service.dart';
import '../../core/widgets/custom_snackbar.dart';
import 'payment_webview_screen.dart';

/// Outstanding-balance payment screen (payment-flow.md §1 Steps 5-6, §3).
///
/// Cash + payment_link only — no Stripe Payment Sheet:
/// - payment_link: opens [PaymentWebViewScreen] with the link `paymentUrl`.
/// - cash: shows the amount owed; receipt updates via
///   `payment:cashCollected` / `payment:succeeded`.
/// Dismisses itself on `payment:succeeded` for this ride.
class OutstandingBalanceScreen extends StatefulWidget {
  final OutstandingBalance balance;

  const OutstandingBalanceScreen({super.key, required this.balance});

  @override
  State<OutstandingBalanceScreen> createState() =>
      _OutstandingBalanceScreenState();
}

class _OutstandingBalanceScreenState extends State<OutstandingBalanceScreen> {
  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService();
  late OutstandingBalance _balance;
  bool _isRefreshing = false;
  bool _isOpeningLink = false;

  @override
  void initState() {
    super.initState();
    _balance = widget.balance;
    _socketService.on('payment:succeeded', _onPaymentSucceeded);
    _socketService.on('payment:cashCollected', _onCashCollected);
  }

  @override
  void dispose() {
    _socketService.off('payment:succeeded');
    _socketService.off('payment:cashCollected');
    super.dispose();
  }

  void _onPaymentSucceeded(dynamic data) {
    final id = data is Map
        ? (data['rideId'] ?? data['bookingId'] ?? data['_id'])?.toString()
        : null;
    if (id != null && id != _balance.rideId) return;
    if (!mounted) return;
    // A succeeded event is NOT proof this balance cleared — the backend
    // also emits it for mid-trip base-fare captures (different amount).
    // Re-fetch authoritatively; pop only when the balance is really gone.
    _refresh(fromEvent: true);
  }

  void _onCashCollected(dynamic data) {
    final id = data is Map
        ? (data['rideId'] ?? data['bookingId'] ?? data['_id'])?.toString()
        : null;
    if (id != null && id != _balance.rideId) return;
    if (!mounted) return;
    _refresh(fromEvent: true);
  }

  /// Re-fetch the balance (payment-flow.md §1 Step 6 fallback).
  ///
  /// When [fromEvent] is true (a socket just told us something settled),
  /// a 404 (nothing owed) also pops — combined with the event, cleared is
  /// the likely reading. Manual refresh keeps the informational message.
  Future<void> _refresh({bool fromEvent = false}) async {
    setState(() => _isRefreshing = true);
    try {
      final res = await _apiService.getPaymentBalance(_balance.rideId);
      if (!mounted) return;
      final status = res['data'] is Map
          ? (res['data'] as Map)['status']?.toString()
          : null;
      if (res['success'] == true && status == 'succeeded') {
        CustomSnackbar.show(
          context,
          message: 'Balance already paid.',
          type: SnackbarType.success,
        );
        Navigator.pop(context, {'success': true});
        return;
      }
      final parsed = res['success'] == true
          ? OutstandingBalance.fromBalanceEnvelope(res, _balance.rideId)
          : null;
      if (parsed != null) {
        // Event-driven check found the balance still owed — stay open with
        // the fresh amount (e.g. a mid-trip base capture, not our payment).
        setState(() => _balance = parsed);
      } else if (fromEvent) {
        // Event said settled + API has nothing owed → genuinely cleared.
        CustomSnackbar.show(
          context,
          message: 'Balance paid successfully! Your ride is fully settled.',
          type: SnackbarType.success,
        );
        Navigator.pop(context, {'success': true});
        return;
      } else {
        CustomSnackbar.show(
          context,
          message: res['message']?.toString() ?? 'No outstanding balance found.',
          type: SnackbarType.info,
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _openPaymentLink() async {
    var url = _balance.paymentUrl;
    // Fallback: re-fetch in case the link arrived after the socket event.
    if (url == null || url.isEmpty) {
      setState(() => _isOpeningLink = true);
      try {
        final res = await _apiService.getPaymentBalance(_balance.rideId);
        final parsed = res['success'] == true
            ? OutstandingBalance.fromBalanceEnvelope(res, _balance.rideId)
            : null;
      if (parsed != null && parsed.isPaid) {
        CustomSnackbar.show(
          context,
          message: 'Balance paid successfully! Your ride is fully settled.',
          type: SnackbarType.success,
        );
        Navigator.pop(context, {'success': true});
        return;
      }
      if (parsed != null) {
          setState(() => _balance = parsed);
          url = parsed.paymentUrl;
        }
      } finally {
        if (mounted) setState(() => _isOpeningLink = false);
      }
    }
    if (!mounted) return;
    if (url == null || url.isEmpty) {
      CustomSnackbar.show(
        context,
        message: 'No payment link available yet. Try cash or pull to refresh.',
        type: SnackbarType.warning,
      );
      return;
    }
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PaymentWebViewScreen(paymentUrl: url!, rideId: _balance.rideId),
      ),
    );
    if (!mounted) return;
    if (result is Map && result['success'] == true) {
      // WebView success is optimistic — backend confirms via
      // payment:succeeded which pops this screen. Refresh to check.
      await _refresh();
    } else {
      CustomSnackbar.show(
        context,
        message: 'Payment was not completed. Please try again.',
        type: SnackbarType.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Outstanding Balance')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 48,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '£${_balance.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _balance.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.orange.shade800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isOpeningLink ? null : _openPaymentLink,
                  icon: _isOpeningLink
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.link_outlined),
                  label: const Text('Pay via Payment Link'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _isRefreshing ? null : _refresh,
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Check again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
