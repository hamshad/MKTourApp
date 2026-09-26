import 'package:flutter/material.dart';
import 'dart:async';
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

  /// Driver-cash-confirm signal inside a `payment:succeeded` message.
  ///
  /// Matches the backend cash round-trip copy ("Cash payment confirmed by
  /// driver! Your ride is fully settled."). A generic capture ("Payment
  /// succeeded") carries no cash keyword, so the base-fare guard in the
  /// succeeded handler is unaffected.
  @visibleForTesting
  static bool isCashConfirmMessage(String? message) {
    if (message == null || message.trim().isEmpty) return false;
    final lower = message.toLowerCase();
    return lower.contains('cash') &&
        (lower.contains('confirm') || lower.contains('settled'));
  }

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

  /// WebView reported a successful redirect this session — the gateway has
  /// confirmed payment even when the balance re-fetch still lags the Stripe
  /// webhook (or the backend never re-emits `payment:succeeded`).
  bool _webPaid = false;

  /// Confirm re-fetch attempts when a success signal (socket event or
  /// WebView redirect) says we're settled but the balance endpoint still
  /// reports `balance_due` — bridges the webhook→DB lag instead of parking
  /// the sheet open on the first stale read.
  static const int _confirmAttempts = 4;
  static const Duration _confirmDelay = Duration(milliseconds: 1500);

  StreamSubscription<bool>? _connectionSub;
  // Stored listener identities — scoped off() removes ONLY these (the
  // singleton socket is shared; a global off from another screen's
  // dispose/re-register would otherwise deafen this open sheet).
  late final void Function(dynamic) _succeededListener = _onPaymentSucceeded;
  late final void Function(dynamic) _confirmedListener =
      _onExcessCashConfirmed;

  @override
  void initState() {
    super.initState();
    _balance = widget.balance;
    _registerSocketListeners();
    // Reconnect survival: a force-reconnect replaces the socket object
    // (dropping all handlers) and home's reconnect-restore wipes foreign
    // handlers — re-register ours on every (re)connect, scoped-off first so
    // a non-destructive reconnect can't double-register.
    _connectionSub = _socketService.connectionStatus.listen((isConnected) {
      if (isConnected && mounted && !_settled) {
        debugPrint(
          '🔄 [ExcessSettlementSheet] Reconnected — re-registering socket listeners',
        );
        _registerSocketListeners();
      }
    });
  }

  void _registerSocketListeners() {
    _socketService.off('payment:succeeded', _succeededListener);
    _socketService.off('payment:excessCashConfirmed', _confirmedListener);
    _socketService.on('payment:succeeded', _succeededListener);
    _socketService.onExcessCashConfirmed(_confirmedListener);
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _socketService.off('payment:succeeded', _succeededListener);
    _socketService.off('payment:excessCashConfirmed', _confirmedListener);
    super.dispose();
  }

  void _onPaymentSucceeded(dynamic data) {
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final id = (map['rideId'] ?? map['bookingId'] ?? map['_id'])?.toString();
    debugPrint(
      '💰 [ExcessSettlementSheet] payment:succeeded eventRide=$id sheetRide=${widget.rideId} step=$_step settled=$_settled',
    );
    if (id != null && id != widget.rideId) {
      debugPrint(
        '⏭️ [ExcessSettlementSheet] Ignoring succeeded for other ride',
      );
      return;
    }
    if (!RideEventDedupe.shouldHandleEvent(
      source: 'socket',
      type: 'payment_succeeded_settlement',
      data: map,
    )) {
      debugPrint(
        '🔁 [ExcessSettlementSheet] Duplicate succeeded swallowed by dedupe',
      );
      return;
    }
    if (!mounted || _settled) {
      debugPrint(
        '⏭️ [ExcessSettlementSheet] Skipping succeeded (mounted=$mounted settled=$_settled)',
      );
      return;
    }
    // Never pop on the event alone — a succeeded event can also fire for a
    // mid-trip base-fare capture (different amount). Re-fetch authoritatively;
    // pop only when the balance is really gone.
    //
    // Exception: a succeeded carrying a driver-cash-confirm message ("Cash
    // payment confirmed by driver! Your ride is fully settled.") IS our
    // settlement — the backend emits `payment:succeeded` (not
    // `payment:excessCashConfirmed`) for the driver cash round-trip, and the
    // cash handoff is out-of-band so the re-fetch can still show the old
    // balance_due (race/stale). Pass the driver copy through and let
    // [_refresh] close on the backend's word even if the re-fetch lags.
    // The [_settled] guard keeps this exactly-once across a co-fired
    // `payment:excessCashConfirmed`.
    //
    // Additional fix: if the user is in the waitingCash step (selected cash
    // payment), any payment:succeeded for this ride is our cash confirmation
    // — the backend may not send the cash-specific message, so we also
    // trust the event when in waitingCash step.
    final rawMessage = map['message']?.toString().trim();
    final isWaitingCash = _step == _SettlementStep.waitingCash;
    final cashSettledFallback =
        isWaitingCash || ExcessSettlementSheet.isCashConfirmMessage(rawMessage);
    final successMessage =
        (rawMessage != null && rawMessage.isNotEmpty) ? rawMessage : null;
    _refresh(
      fromEvent: true,
      successMessage: successMessage,
      cashSettledFallback: cashSettledFallback,
    );
  }

  /// Driver confirmed cash receipt (confirmed event).
  ///
  /// Mirrors [_onPaymentSucceeded]: rideId-match → dedupe (distinct
  /// `payment_excess_cash_confirmed` key) → settled guard → authoritative
  /// [_refresh(fromEvent: true)]. Never pops on the event alone; a co-fired
  /// `payment:succeeded` hits the same [_settled] guard and no-ops.
  /// The event's non-empty `message` ("Driver confirmed cash receipt ...
  /// Thank you!") is passed through as the success snackbar copy.
  void _onExcessCashConfirmed(dynamic data) {
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final id = (map['rideId'] ?? map['bookingId'] ?? map['_id'])?.toString();
    if (id != null && id != widget.rideId) return;
    if (!RideEventDedupe.shouldHandleEvent(
      source: 'socket',
      type: 'payment_excess_cash_confirmed',
      data: map,
    )) {
      return;
    }
    if (!mounted || _settled) return;
    final rawMessage = map['message']?.toString().trim();
    final successMessage =
        (rawMessage != null && rawMessage.isNotEmpty) ? rawMessage : null;
    _refresh(fromEvent: true, successMessage: successMessage);
  }

  /// Re-fetch the balance (mirrors OutstandingBalanceScreen._refresh).
  ///
  /// When [fromEvent] is true (a socket event or the WebView redirect said
  /// we're settled), a 404 (nothing owed) also pops — combined with the
  /// signal, cleared is the likely reading. [successMessage] overrides the
  /// default settled copy (used for the confirmed event's thank-you
  /// message); displayed verbatim.
  ///
  /// [cashSettledFallback] covers the driver-cash round-trip arriving as
  /// `payment:succeeded`: the cash handoff leaves no payment record, so the
  /// re-fetch can still return the stale balance_due. The backend's
  /// "fully settled" word is authoritative — close anyway (first attempt).
  /// Exactly-once via [_settled] (a co-fired `payment:excessCashConfirmed`
  /// no-ops).
  ///
  /// Confirm-signal refreshes retry up to [_confirmAttempts] times
  /// ([_confirmDelay] apart): the balance endpoint resolves only after the
  /// Stripe webhook, so the FIRST post-payment read commonly still says
  /// `balance_due`. A single stale read used to park the sheet open forever.
  /// After retries, a WebView-confirmed payment ([_webPaid]) closes the
  /// sheet anyway — the gateway redirect is the payment proof. Without
  /// [_webPaid] (e.g. a late base-fare capture event) the sheet still stays
  /// open on the fresh amount, preserving the base-capture guard.
  ///
  /// Concurrent triggers (socket event + WebView result) each run their own
  /// pipeline — the calls are idempotent GETs and [_settled] keeps the
  /// close-out exactly-once.
  Future<void> _refresh(
      {bool fromEvent = false,
      String? successMessage,
      bool cashSettledFallback = false}) async {
    if (_settled) return;
    final settledCopy =
        successMessage ?? 'Excess paid successfully! Your ride is fully settled.';
    setState(() => _isRefreshing = true);
    try {
      final maxAttempts = fromEvent ? _confirmAttempts : 1;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        if (!mounted || _settled) return;
        if (attempt > 1) {
          await Future<void>.delayed(_confirmDelay);
          if (!mounted || _settled) return;
        }
        final res = await _apiService.getPaymentBalance(widget.rideId);
        if (!mounted || _settled) return;
        final status = res['data'] is Map
            ? (res['data'] as Map)['status']?.toString()
            : null;
        debugPrint(
          '💰 [ExcessSettlementSheet] refresh#$attempt success=${res['success']} '
          'status=$status fallback=$cashSettledFallback event=$fromEvent '
          'webPaid=$_webPaid attempt=$attempt/$maxAttempts',
        );
        if (res['success'] == true && status == 'succeeded') {
          _closeSettled(settledCopy);
          return;
        }
        final parsed = res['success'] == true
            ? OutstandingBalance.fromBalanceEnvelope(res, widget.rideId)
            : null;
        if (parsed == null) {
          if (fromEvent) {
            // Signal said settled + API has nothing owed → genuinely cleared.
            _closeSettled(settledCopy);
            return;
          }
          CustomSnackbar.show(
            context,
            message: res['message']?.toString() ?? 'No outstanding balance found.',
            type: SnackbarType.info,
          );
          return;
        }
        if (cashSettledFallback) {
          // Backend said "fully settled" for the cash handoff but the
          // re-fetch still shows the stale balance — trust the event.
          _closeSettled(settledCopy);
          return;
        }
        if (!parsed.isOwed) {
          // Not `balance_due` anymore (e.g. `paid`/`completed` variants) →
          // the balance endpoint itself says we're cleared.
          _closeSettled(settledCopy);
          return;
        }
        // Still owed — retry while attempts remain (webhook lag).
        if (attempt < maxAttempts) continue;
        if (_webPaid) {
          // Gateway confirmed the payment in our WebView; the backend
          // flip is lagging (or its emission never came). Close rather
          // than park the sheet open forever.
          debugPrint(
            '✅ [ExcessSettlementSheet] WebView-confirmed payment, closing despite stale balance',
          );
          _closeSettled(settledCopy);
          return;
        }
        // Event-driven check found the balance still owed — stay open with
        // the fresh amount (e.g. a mid-trip base capture, not our payment).
        debugPrint(
          '⏳ [ExcessSettlementSheet] Balance still owed after '
          '$maxAttempts checks, staying open',
        );
        setState(() => _balance = parsed);
        return;
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  /// Exactly-once settled close-out: success snackbar + pop with result.
  void _closeSettled(String message) {
    if (!mounted || _settled) return;
    CustomSnackbar.show(
      context,
      message: message,
      type: SnackbarType.success,
    );
    _settled = true;
    Navigator.pop(context, {'success': true});
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
        // WebView success is the gateway's word — record it before the
        // authoritative re-fetch so a lagging backend can't park the sheet
        // open (see [_webPaid]). fromEvent:true so a post-paid 404 means
        // "balance gone → pop with success" and stale reads get retried.
        _webPaid = true;
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
              // Confirm-pipeline activity (event/WebView-triggered re-fetch
              // retries) — visible on the choice step too, so a socket
              // success refresh doesn't look like a dead sheet.
              if (_isRefreshing)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
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
