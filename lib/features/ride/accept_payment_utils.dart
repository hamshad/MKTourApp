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

/// Booking-time choice is final (strip-post-accept directive, supersedes
/// revert-spec §4 Error 1 for the normal-ride post-accept path): the assigned
/// screen never offers Online<->Cash switching after accept. No method sheet,
/// no switch affordance. `ApiService.selectPaymentMethod` + the
/// booking-screen scheduled-switch call sites stay for scheduled deposit
/// switching; this flag pins the normal post-accept policy only.
const bool postAcceptPaymentSwitchAllowed = false;

/// Whether the checkout WebView must auto-open for an unpaid link ride.
///
/// - `isLiveEvent: true` (live `ride:accepted` socket event) + prompt snapshot
///   with a URL + not authorized + no WebView already open → true: the rider
///   pays immediately with zero taps through sheets/banners.
/// - Cold-start / rehydrate restores (`isLiveEvent: false`) → false:
///   auto-popping a WebView over a restored screen is riskier, so those paths
///   show the single one-tap Pay Now banner instead (which opens the WebView
///   directly, never a sheet).
/// - Cash / scheduled / paid / authorized / URL-less snapshots → false. The
///   URL-less link case falls back to the Pay Now banner (snackbar if the link
///   still isn't ready), and the sheet never appears.
bool shouldAutoOpenLinkWebView({
  required bool isLiveEvent,
  required AcceptedPayment payment,
  required bool paymentAuthorized,
  required bool webViewOpen,
}) {
  if (!isLiveEvent) return false;
  if (paymentAuthorized) return false;
  if (webViewOpen) return false;
  if (!payment.showPrompt) return false;
  final url = payment.paymentUrl;
  if (url == null || url.isEmpty) return false;
  return true;
}
/// Pop-ownership policy for the accept-time checkout WebView close-out.
///
/// Two closers race for one WebView: the WebView's own success/cancel
/// detection ([PaymentWebViewScreen]) and the assigned screen's
/// `payment:authorized` socket handler. Exactly one of them may pop.
///
/// A closer pops ONLY when its close has not already been delivered AND its
/// route is still the top route. A stale closer (own route already popped —
/// e.g. the authorized event won the race) must stay silent: popping then
/// would eject whatever is on top, which is RideAssignedScreen itself
/// (rider dumped to the pick-ride screen — the 40187f3-class regression).
bool acceptWebViewShouldPop({
  required bool routeIsCurrent,
  required bool closeAlreadyDelivered,
}) {
  if (closeAlreadyDelivered) return false;
  if (!routeIsCurrent) return false;
  return true;
}

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
