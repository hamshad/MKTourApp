/// Outstanding balance value object (payment-flow.md §1 Step 6, §3, §7).
///
/// Cash + payment_link only: a Stripe `clientSecret` may be present in the
/// payload but is surfaced, never presented (no Payment Sheet in this app).
class OutstandingBalance {
  final String rideId;
  final double amount;
  final String status;
  final String message;
  final String? paymentUrl;
  final String? clientSecret;
  final bool isReminder;
  final bool accountSuspended;
  final bool allowCash;

  const OutstandingBalance({
    required this.rideId,
    required this.amount,
    required this.status,
    required this.message,
    this.paymentUrl,
    this.clientSecret,
    this.isReminder = false,
    this.accountSuspended = false,
    this.allowCash = true,
  });

  bool get isOwed => status == 'balance_due';
  bool get isPaid => status == 'succeeded';
  bool get hasPaymentUrl => paymentUrl != null && paymentUrl!.isNotEmpty;
  bool get isSuspended => accountSuspended && !allowCash;

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

  static bool _flag(dynamic v, {required bool fallback}) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return fallback;
  }

  /// Parse `GET /payments/balance/:rideId` 200 envelope.
  /// Also accepts nested `data.payment.paymentUrl` shape from new backend.
  static OutstandingBalance? fromBalanceEnvelope(
    Map<String, dynamic> envelope,
    String fallbackRideId,
  ) {
    var data = envelope['data'];
    // Tolerate a list envelope (first entry wins) — some backends wrap it.
    if (data is List && data.isNotEmpty) data = data.first;
    if (data is! Map) return null;
    final m = Map<String, dynamic>.from(data);
    final status = m['status']?.toString() ?? '';
    if (status == 'succeeded') {
      return OutstandingBalance(
        rideId: m['rideId']?.toString() ?? fallbackRideId,
        amount: 0,
        status: status,
        message: m['message']?.toString() ?? 'Balance already paid.',
        accountSuspended: false,
        allowCash: true,
      );
    }
    // paymentUrl may be nested under data.payment.paymentUrl (new backend shape)
    final nestedPayment = m['payment'];
    final String? paymentUrl = (nestedPayment is Map
        ? nestedPayment['paymentUrl']?.toString()
        : null) ??
        m['paymentUrl']?.toString();
    return OutstandingBalance(
      rideId: m['rideId']?.toString() ?? fallbackRideId,
      amount: _num(m['excessAmount'] ?? m['outstandingBalance'] ?? m['amount']),
      status: status.isEmpty ? 'balance_due' : status,
      message: m['message']?.toString() ?? 'Outstanding balance. Please complete payment.',
      paymentUrl: paymentUrl,
      clientSecret: m['clientSecret']?.toString(),
      accountSuspended: _flag(m['accountSuspended'], fallback: false),
      allowCash: _flag(m['allowCash'], fallback: true),
    );
  }

  /// Parse `POST /payments/balance/:rideId/select-method` response envelope.
  ///
  /// Tolerates flat `paymentUrl` AND nested `data.payment.paymentUrl`,
  /// amount keys `excessAmount ?? outstandingBalance ?? amount`, a flat
  /// envelope with keys at top level (no `data` wrapper), and a list
  /// envelope (first entry wins). Cash selections carry no `paymentUrl`
  /// (null); `payment_link` selections carry one. `succeeded` status
  /// parses as paid with zero amount. Mirrors `fromBalanceEnvelope`.
  static OutstandingBalance? fromSelectMethodEnvelope(
    Map<String, dynamic> envelope,
    String fallbackRideId,
  ) {
    var data = envelope['data'];
    // Tolerate a list envelope (first entry wins).
    if (data is List && data.isNotEmpty) data = data.first;
    late final Map<String, dynamic> m;
    if (data is Map) {
      m = Map<String, dynamic>.from(data);
    } else if (data == null) {
      // Tolerate a flat envelope with keys at top level (no `data` wrapper).
      m = Map<String, dynamic>.from(envelope)..remove('success');
    } else {
      return null;
    }
    final status =
        m['status']?.toString() ?? envelope['status']?.toString() ?? '';
    if (status == 'succeeded') {
      return OutstandingBalance(
        rideId:
            m['rideId']?.toString() ??
            envelope['rideId']?.toString() ??
            fallbackRideId,
        amount: 0,
        status: status,
        message:
            m['message']?.toString() ??
            envelope['message']?.toString() ??
            'Balance already paid.',
      );
    }
    // paymentUrl may be nested under data.payment.paymentUrl.
    final nestedPayment = m['payment'];
    final String? paymentUrl = (nestedPayment is Map
            ? nestedPayment['paymentUrl']?.toString()
            : null) ??
        m['paymentUrl']?.toString() ??
        envelope['paymentUrl']?.toString();
    final rideId =
        m['rideId']?.toString() ??
        envelope['rideId']?.toString() ??
        fallbackRideId;
    final hasAmount = m.containsKey('excessAmount') ||
        m.containsKey('outstandingBalance') ||
        m.containsKey('amount');
    if ((rideId.isEmpty && fallbackRideId.isEmpty) &&
        !hasAmount &&
        paymentUrl == null &&
        status.isEmpty) {
      return null;
    }
    return OutstandingBalance(
      rideId: rideId.isEmpty ? fallbackRideId : rideId,
      amount: _num(
        m['excessAmount'] ?? m['outstandingBalance'] ?? m['amount'],
      ),
      status: status.isEmpty ? 'balance_due' : status,
      message: m['message']?.toString() ??
          envelope['message']?.toString() ??
          'Outstanding balance. Please complete payment.',
      paymentUrl: paymentUrl,
      clientSecret:
          m['clientSecret']?.toString() ?? envelope['clientSecret']?.toString(),
    );
  }

  /// Parse the 403 block from `POST /rides/create` (payment-flow.md §7).
  /// Accepts excessAmount fallback and copies paymentUrl when present.
  static OutstandingBalance? fromForbiddenEnvelope(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (data is! Map) return null;
    final m = Map<String, dynamic>.from(data);
    final rideId = m['rideId']?.toString();
    if (rideId == null || rideId.isEmpty) return null;
    return OutstandingBalance(
      rideId: rideId,
      amount: _num(m['outstandingBalance'] ?? m['excessAmount']),
      status: 'balance_due',
      message: envelope['message']?.toString() ?? 'Please clear your balance before booking a new ride.',
      paymentUrl: m['paymentUrl']?.toString(),
    );
  }

  /// Parse `payment:balanceDue` socket / `balance_due_reminder` FCM payload.
  static OutstandingBalance fromBalanceDueEvent(Map<String, dynamic> event) {
    return OutstandingBalance(
      rideId: (event['rideId'] ?? event['bookingId'] ?? '').toString(),
      amount: _num(event['excessAmount'] ?? event['amount']),
      status: 'balance_due',
      message: event['message']?.toString() ?? 'You have an outstanding balance. Please complete your payment.',
      paymentUrl: event['paymentUrl']?.toString(),
      clientSecret: event['clientSecret']?.toString(),
      isReminder: event['isReminder'] == true,
      accountSuspended: _flag(event['accountSuspended'], fallback: false),
      allowCash: _flag(event['allowCash'], fallback: true),
    );
  }
}
