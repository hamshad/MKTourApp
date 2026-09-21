import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'accept_payment_utils.dart';

class PaymentWebViewScreen extends StatefulWidget {
  final String paymentUrl;
  final String rideId;

  const PaymentWebViewScreen({
    super.key,
    required this.paymentUrl,
    required this.rideId,
  });

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String _currentUrl = '';
  bool _paymentFlowCompleted = false;

  /// Exactly-once pop ownership (see [acceptWebViewShouldPop]). The assigned
  /// screen's `payment:authorized` handler races our own success/cancel
  /// detection for this route: whoever closes first wins, the loser stays
  /// silent. Without this, a stale self-close after the authorized pop
  /// ejects RideAssignedScreen to the pick-ride screen.
  bool _didDeliverClose = false;

  /// Our cancel-confirm dialog's context while it is open (null otherwise).
  /// Lets a success detected under the dialog dismiss both routes; a stale
  /// close with no dialog stays silent instead of popping another route.
  BuildContext? _cancelDialogContext;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });
            debugPrint('🌐 [WebView] Page started: $url');

            // Check for success immediately on start in case of failed redirect
            _checkPaymentCompletion(url);
          },
          onPageFinished: (String url) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });
            debugPrint('🌐 [WebView] Page finished: $url');

            // Check if payment is complete
            _checkPaymentCompletion(url);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('❌ [WebView] Error: ${error.description}');
            if (!mounted) return;
            // If it's a domain error but the URL is our success URL, treat it as success
            if (_checkPaymentCompletion(_currentUrl)) return;
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error loading page: ${error.description}'),
                backgroundColor: Colors.red,
              ),
            );
          },
          onNavigationRequest: (NavigationRequest request) {
            debugPrint('🔗 [WebView] Navigation request: ${request.url}');
            if (!mounted) return NavigationDecision.navigate;
            if (_checkPaymentCompletion(request.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  bool _checkPaymentCompletion(String url) {
    if (url.isEmpty || _paymentFlowCompleted) return false;

    final lowerUrl = url.toLowerCase();
    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {}

    final qp = uri?.queryParameters ?? const <String, String>{};
  final path = (uri?.path ?? '').toLowerCase();
    final redirectStatus = (qp['redirect_status'] ?? '').toLowerCase();
    final status = (qp['status'] ?? '').toLowerCase();
    final paymentStatus = (qp['payment_status'] ?? '').toLowerCase();

    final bool isSuccess =
        lowerUrl.contains('mktours.app/payment-success') ||
    lowerUrl.contains('/payment-success') ||
    path.endsWith('/payment-success') ||
        lowerUrl.contains('/payment/success') ||
        lowerUrl.contains('/success') ||
        redirectStatus == 'succeeded' ||
        status == 'success' ||
        status == 'succeeded' ||
        status == 'paid' ||
        paymentStatus == 'paid';

    final bool isCancelled =
        lowerUrl.contains('mktours.app/payment-cancel') ||
    lowerUrl.contains('/payment-cancel') ||
    path.endsWith('/payment-cancel') ||
        lowerUrl.contains('/payment/cancel') ||
        lowerUrl.contains('/cancel') ||
        redirectStatus == 'failed' ||
        redirectStatus == 'canceled' ||
        redirectStatus == 'cancelled' ||
        status == 'failed' ||
        status == 'canceled' ||
        status == 'cancelled';

    if (isSuccess) {
      debugPrint('✅ [WebView] Payment successful detected: $url');
      _paymentFlowCompleted = true;
      _handlePaymentSuccess();
      return true;
    }

    if (isCancelled) {
      debugPrint('❌ [WebView] Payment cancelled detected: $url');
      _paymentFlowCompleted = true;
      _handlePaymentCancelled();
      return true;
    }

    return false;
  }

  void _handlePaymentSuccess() {
    // Close WebView and return success (ownership-checked: stale closes
    // after the `payment:authorized` pop stay silent).
    _closeWebViewOnce(success: true);
  }

  void _handlePaymentCancelled() {
    // Close WebView and let parent screen re-open payment options
    // (ownership-checked, same as success).
    _closeWebViewOnce(success: false);
  }

  /// Exactly-once, ownership-checked close of this WebView route.
  ///
  /// Pops ONLY while our own route is still the top route. When our
  /// cancel-confirm dialog sits on top, the stack is guaranteed to be
  /// `[.., WebView, dialog]` (the authorized close-out never pops under an
  /// open dialog), so both are dismissed. Otherwise a non-current route
  /// means a stale close — the authorized handler already popped us — and
  /// popping then would eject RideAssignedScreen to the pick-ride screen.
  void _closeWebViewOnce({required bool success}) {
    if (!mounted || _didDeliverClose) return;
    final dialogCtx = _cancelDialogContext;
    _cancelDialogContext = null;
    if (dialogCtx != null) {
      _didDeliverClose = true;
      try {
        Navigator.pop(dialogCtx);
      } catch (_) {
        // Dialog already gone — fall through to the WebView pop.
      }
      if (!mounted) return;
      try {
        Navigator.pop(context, {'success': success});
      } catch (_) {
        // WebView already closed out (authorized won) — stay silent.
      }
      return;
    }
    if (!acceptWebViewShouldPop(
      routeIsCurrent: ModalRoute.of(context)?.isCurrent == true,
      closeAlreadyDelivered: _didDeliverClose,
    )) {
      return;
    }
    _didDeliverClose = true;
    Navigator.pop(context, {'success': success});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Payment'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            // Confirm before closing
            showDialog(
              context: context,
              builder: (dialogContext) {
                _cancelDialogContext = dialogContext;
                return AlertDialog(
                  title: const Text('Cancel Payment?'),
                  content: const Text(
                    'Are you sure you want to cancel the payment? You will need to select a payment method again.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Continue Payment'),
                    ),
                    TextButton(
                      onPressed: () {
                        // Dismiss the dialog, then close the WebView through
                        // the ownership-checked path (silent if the
                        // `payment:authorized` handler already closed us).
                        _cancelDialogContext = null;
                        try {
                          Navigator.pop(dialogContext);
                        } catch (_) {
                          // Dialog already gone — still close the WebView.
                        }
                        _handlePaymentCancelled();
                      },
                      child: const Text('Cancel Payment'),
                    ),
                  ],
                );
              },
            ).then((_) {
              // Dialog dismissed by any path (tap-out, Continue) — clear it so
              // a later success close does not touch a dead context.
              _cancelDialogContext = null;
            });
          },
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
