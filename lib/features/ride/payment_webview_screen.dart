import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });
            debugPrint('🌐 [WebView] Page started: $url');
            
            // Check for success immediately on start in case of failed redirect
            _checkPaymentCompletion(url);
          },
          onPageFinished: (String url) {
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
    if (url.isEmpty) return false;
    
    // Stripe Checkout success URLs for mktours
    if (url.contains('mktours.app/payment-success') || 
        url.contains('success') || 
        url.contains('payment/success')) {
      debugPrint('✅ [WebView] Payment successful detected: $url');
      _handlePaymentSuccess();
      return true;
    } else if (url.contains('mktours.app/payment-cancel') || 
               url.contains('cancel') || 
               url.contains('payment/cancel')) {
      debugPrint('❌ [WebView] Payment cancelled detected: $url');
      _handlePaymentCancelled();
      return true;
    }
    return false;
  }

  void _handlePaymentSuccess() {
    // Close WebView and return success
    Navigator.pop(context, {'success': true});
  }

  void _handlePaymentCancelled() {
    // Show dialog to user
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Payment Cancelled'),
        content: const Text('Your payment was cancelled. Would you like to try again?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context, {'success': false}); // Close WebView
            },
            child: const Text('Go Back'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              // Reload the payment page
              _controller.loadRequest(Uri.parse(widget.paymentUrl));
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
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
              builder: (context) => AlertDialog(
                title: const Text('Cancel Payment?'),
                content: const Text(
                  'Are you sure you want to cancel the payment? You will need to select a payment method again.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Continue Payment'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context); // Close dialog
                      Navigator.pop(context, {'success': false}); // Close WebView
                    },
                    child: const Text('Cancel Payment'),
                  ),
                ],
              ),
            );
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
