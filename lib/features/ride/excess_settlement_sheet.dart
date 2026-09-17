import 'package:flutter/material.dart';
import '../../core/api_service.dart';
import '../../core/models/outstanding_balance.dart';
import '../../core/models/error_display_helper.dart';
import '../../core/services/ride_event_dedupe.dart';
import '../../core/services/socket_service.dart';
import '../../core/widgets/custom_snackbar.dart';
import 'payment_webview_screen.dart';

/// Stage 2 live-settlement bottom-sheet content (INTEGRATION-GUIDE.md §1A).
///
/// Shown ON TOP of the trip receipt when an excess balance is owed:
/// method choice (Cash + Online), cash waiting state with escape hatches,
/// online WebView flow, and `payment:succeeded` close-out that pops only
/// after an authoritative re-fetch confirms the balance cleared.
///
/// Startup [OutstandingBalanceScreen] stays online-only — no cash UI there.
enum _SettlementStep { choice, waitingCash }

class ExcessSettlementSheet extends StatefulWidget {
  final String rideId;
  final OutstandingBalance balance;

  const ExcessSettlementSheet({
    super.key,
    required this.rideId,
    required this.balance,
  });

  @override
  State<ExcessSettlementSheet> createState() => _ExcessSettlementSheetState();
}

class _ExcessSettlementSheetState extends State<ExcessSettlementSheet> {
  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService();
  late OutstandingBalance _balance;
  _SettlementStep _step = _SettlementStep.choice;
  bool _isBusy = false;
  bool _isRefreshing = false;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _balance = widget.balance;
    _socketService.on('payment:succeeded', _onPaymentSucceeded);
  }

  @override
  void dispose() {
    _socketService.off('payment:succeeded');
    super.dispose();
  }

  void _onPaymentSucceeded(dynamic data) {
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final id = (map['rideId'] ?? map['bookingId'] ?? map['_id'])?.toString();
    if (id != null && id != widget.rideId) return;
    if (!RideEventDedupe.shouldHandleEvent(
      source: 'socket',
      type: 'payment_succeeded_settlement',
      data: map,
    )) {
      return;
    }
    if (!mounted || _settled) return;
    // Never pop on the event alone — a succeeded event can also fire for a
    // mid-trip base-fare capture (different amount). Re-fetch authoritatively;
    // pop only when the balance is really gone.
    _refresh(fromEvent: true);
  }

  /// Re-fetch the balance (mirrors OutstandingBalanceScreen._refresh).
  ///
  /// When [fromEvent] is true (a socket just told us something settled), a
  /// 404 (nothing owed) also pops — combined with the event, cleared is the
  /// likely reading.
  Future<void> _refresh({bool fromEvent = false}) async {
    if (_settled) return;
    setState(() => _isRefreshing = true);
    try {
      final res = await _apiService.getPaymentBalance(widget.rideId);
      if (!mounted || _settled) return;
      final status = res['data'] is Map
          ? (res['data'] as Map)['status']?.toString()
          : null;
      if (res['success'] == true && status == 'succeeded') {
        CustomSnackbar.show(
          context,
          message: 'Excess paid successfully! Your ride is fully settled.',
          type: SnackbarType.success,
        );
        _settled = true;
        Navigator.pop(context, {'success': true});
        return;
      }
      final parsed = res['success'] == true
          ? OutstandingBalance.fromBalanceEnvelope(res, widget.rideId)
          : null;
      if (parsed != null) {
        // Event-driven check found the balance still owed — stay open with
        // the fresh amount (e.g. a mid-trip base capture, not our payment).
        setState(() => _balance = parsed);
      } else if (fromEvent) {
        // Event said settled + API has nothing owed → genuinely cleared.
        CustomSnackbar.show(
          context,
          message: 'Excess paid successfully! Your ride is fully settled.',
          type: SnackbarType.success,
        );
        _settled = true;
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

  Future<void> _selectCash() async {
    setState(() => _isBusy = true);
    try {
      final res = await _apiService.selectBalanceMethod(widget.rideId, 'cash');
      if (!mounted) return;
      if (res['success'] == true) {
        setState(() => _step = _SettlementStep.waitingCash);
      } else {
        ErrorDisplayHelper.showRideError(
          context,
          res['message']?.toString() ?? 'Failed to select cash payment.',
          errors: res['errors'],
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _selectOnline() async {
    setState(() => _isBusy = true);
    try {
      final res =
          await _apiService.selectBalanceMethod(widget.rideId, 'payment_link');
      if (!mounted) return;
      if (res['success'] != true) {
        ErrorDisplayHelper.showRideError(
          context,
          res['message']?.toString() ?? 'Failed to start online payment.',
          errors: res['errors'],
        );
        return;
      }
      final parsed =
          OutstandingBalance.fromSelectMethodEnvelope(res, widget.rideId);
      final url = parsed?.paymentUrl;
      if (url == null || url.isEmpty) {
        ErrorDisplayHelper.showRideError(
          context,
          'No payment link available yet. Try cash or check again.',
          errors: res['errors'],
        );
        return;
      }
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PaymentWebViewScreen(paymentUrl: url, rideId: widget.rideId),
        ),
      );
      if (!mounted) return;
      if (result is Map && result['success'] == true) {
        // WebView success is optimistic — backend confirms via
        // payment:succeeded. Refresh authoritatively; fromEvent:true so a
        // post-paid 404 means "balance gone → pop with success".
        await _refresh(fromEvent: true);
      } else {
        CustomSnackbar.show(
          context,
          message: 'Payment was not completed. Please try again.',
          type: SnackbarType.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (_step == _SettlementStep.waitingCash)
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Back to payment options',
                    onPressed: _isBusy
                        ? null
                        : () => setState(
                              () => _step = _SettlementStep.choice,
                            ),
                  ),
                Expanded(
                  child: Text(
                    'Excess balance: £${_balance.amount.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (_step == _SettlementStep.waitingCash)
                  const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _step == _SettlementStep.waitingCash
                  ? 'Waiting for driver to confirm cash receipt…'
                  : _balance.message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (_step == _SettlementStep.choice) ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isBusy ? null : _selectCash,
                  icon: _isBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.payments_outlined),
                  label: const Text('Pay Cash to Driver'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _isBusy ? null : _selectOnline,
                  icon: const Icon(Icons.link_outlined),
                  label: const Text('Pay Online'),
                ),
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.hourglass_top_outlined,
                      color: Colors.orange.shade700,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Hand £${_balance.amount.toStringAsFixed(2)} cash to your driver — this screen updates automatically.',
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  // Switching back to online re-calls select-method with
                  // payment_link — per contract the backend fires
                  // excessCashCancelled driver-side to close their modal.
                  onPressed: _isBusy ? null : _selectOnline,
                  icon: const Icon(Icons.link_outlined),
                  label: const Text('Switch to Online'),
                ),
              ),
              const SizedBox(height: 8),
              if (_isRefreshing)
                const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
