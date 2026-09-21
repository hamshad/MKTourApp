/// Accept-time payment parsing for the pay-after-accept revert
/// (phase 16-02, revert spec §3 Step 2).
///
/// Pure Dart — no Flutter imports — so `ride:accepted` payload decisions are
/// unit-testable without widgets. The screen calls [AcceptedPayment.parse]
/// once in the `ride:accepted` handler and renders from the result.
library;

/// Paid terminal states: never prompt, even if a `paymentUrl` is present.
bool isPaidPaymentStatus(String? status) {
  final s = (status ?? '').trim().toLowerCase();
  return s == 'authorized' || s == 'succeeded';
}

/// Whether the persistent Pay Now prompt must surface.
///
/// Rules (revert spec §3 Step 2 + §5 Step 3):
/// - scheduled rides never prompt (`requiresPayment` is false there)
/// - `requiresPayment: false` never prompts (cash / already covered)
/// - effective cash method never prompts (pay driver directly)
/// - authorized/succeeded status never prompts even with a URL present
bool shouldShowPayPrompt({
  required bool requiresPayment,
  String? paymentMethod,
  String? paymentStatus,
  required bool isScheduled,
}) {
  if (isScheduled) return false;
  if (!requiresPayment) return false;
  final method = (paymentMethod ?? '').trim().toLowerCase();
  if (method == 'cash') return false;
  if (isPaidPaymentStatus(paymentStatus)) return false;
  return true;
}

/// Whether the "pay in cash" copy shows instead of a prompt.
bool shouldShowCashCopy({
  String? paymentMethod,
  required bool isScheduled,
  String? paymentStatus,
}) {
  if (isScheduled) return false;
  if (isPaidPaymentStatus(paymentStatus)) return false;
  return (paymentMethod ?? '').trim().toLowerCase() == 'cash';
}

/// Format a fare for accept-time copy.
///
/// Backend sends `amount` in minor units (1250 → £12.50) plus `currency`
/// (GBP). Falls back to the decimal `fare` field, then `fallback`.
String formatAcceptFare({
  dynamic amountMinor,
  dynamic fare,
  String? currency,
  double fallback = 0.0,
}) {
  double major;
  if (amountMinor is num) {
    major = amountMinor.toDouble() / 100.0;
  } else if (fare is num) {
    major = fare.toDouble();
  } else {
    major = fallback;
  }
  final symbol = _currencySymbol(currency);
  final fixed = major.toStringAsFixed(2);
  if (symbol.isEmpty) {
    final code = (currency ?? '').trim().toUpperCase();
    return code.isEmpty ? fixed : '$code $fixed';
  }
  return '$symbol$fixed';
}

String _currencySymbol(String? currency) {
  switch ((currency ?? '').trim().toUpperCase()) {
    case 'GBP':
      return '£';
    case 'USD':
      return r'$';
    case 'EUR':
      return '€';
    case 'INR':
      return '₹';
    default:
      return '';
  }
}

/// Parsed `ride:accepted` payment snapshot driving the assigned-screen banner.
class AcceptedPayment {
  final bool requiresPayment;
  final String? paymentUrl;
  final String? paymentStatus;
  final String? paymentMethod;
  final bool isScheduled;
  final String fareLabel;
  final bool showPrompt;
  final bool showCashCopy;

  const AcceptedPayment({
    required this.requiresPayment,
    required this.paymentUrl,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.isScheduled,
    required this.fareLabel,
    required this.showPrompt,
    required this.showCashCopy,
  });

  /// Parse the §3 Step 2 `ride:accepted` payload. Never throws: unknown or
  /// missing shapes degrade to "no prompt" (assignment UI only).
  factory AcceptedPayment.parse(Map<dynamic, dynamic> data, {double fallbackFare = 0.0}) {
    bool requiresPayment = false;
    final raw = data['requiresPayment'];
    if (raw is bool) {
      requiresPayment = raw;
    } else if (raw is num) {
      requiresPayment = raw != 0;
    } else if (raw is String) {
      requiresPayment = raw.trim().toLowerCase() == 'true';
    }

    final url = data['paymentUrl']?.toString();
    final paymentUrl = (url == null || url.trim().isEmpty) ? null : url.trim();
    final paymentStatus = data['paymentStatus']?.toString();
    final paymentMethod = data['paymentMethod']?.toString();
    final isScheduled = data['isScheduled'] == true;

    final fareLabel = formatAcceptFare(
      amountMinor: data['amount'],
      fare: data['fare'],
      currency: data['currency']?.toString(),
      fallback: fallbackFare,
    );

    return AcceptedPayment(
      requiresPayment: requiresPayment,
      paymentUrl: paymentUrl,
      paymentStatus: paymentStatus,
      paymentMethod: paymentMethod,
      isScheduled: isScheduled,
      fareLabel: fareLabel,
      showPrompt: shouldShowPayPrompt(
        requiresPayment: requiresPayment,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        isScheduled: isScheduled,
      ),
      showCashCopy: shouldShowCashCopy(
        paymentMethod: paymentMethod,
        isScheduled: isScheduled,
        paymentStatus: paymentStatus,
      ),
    );
  }
}
