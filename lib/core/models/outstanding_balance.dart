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

  const OutstandingBalance({
    required this.rideId,
    required this.amount,
    required this.status,
    required this.message,
    this.paymentUrl,
    this.clientSecret,
    this.isReminder = false,
  });

  bool get isOwed => status == 'balance_due';
  bool get isPaid => status == 'succeeded';
  bool get hasPaymentUrl => paymentUrl != null && paymentUrl!.isNotEmpty;

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

  /// Parse `GET /payments/balance/:rideId` 200 envelope.
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
      );
    }
    return OutstandingBalance(
      rideId: m['rideId']?.toString() ?? fallbackRideId,
      amount: _num(m['excessAmount'] ?? m['outstandingBalance'] ?? m['amount']),
      status: status.isEmpty ? 'balance_due' : status,
      message: m['message']?.toString() ?? 'Outstanding balance. Please complete payment.',
      paymentUrl: m['paymentUrl']?.toString(),
      clientSecret: m['clientSecret']?.toString(),
    );
  }

  /// Parse the 403 block from `POST /rides/create` (payment-flow.md §7).
  static OutstandingBalance? fromForbiddenEnvelope(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (data is! Map) return null;
    final m = Map<String, dynamic>.from(data);
    final rideId = m['rideId']?.toString();
    if (rideId == null || rideId.isEmpty) return null;
    return OutstandingBalance(
      rideId: rideId,
      amount: _num(m['outstandingBalance']),
      status: 'balance_due',
      message: envelope['message']?.toString() ?? 'Please clear your balance before booking a new ride.',
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
    );
  }
}
