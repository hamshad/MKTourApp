import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/features/ride/accept_payment_utils.dart';

/// Accept-time checkout WebView close-out regression tests.
///
/// Regression: when the payment WebView closed after paying via payment link,
/// the rider was ejected from the driver-on-way tracking screen to the
/// pick-ride screen (pre-40187f3 symptom, recurred on the ce18cfb auto-open
/// path).
///
/// Root cause: two closers race for one WebView — the WebView's own
/// success/cancel detection and the assigned screen's `payment:authorized`
/// handler. 40187f3 guarded only the assigned-side closer (tracked route +
/// `isCurrent`). The WebView-side self-close stayed a bare `Navigator.pop`,
/// so when `payment:authorized` won the race (server webhook beat the client
/// redirect), the WebView's in-flight success callback popped whatever was
/// on top — RideAssignedScreen itself.
///
/// Fix: pop-ownership policy ([acceptWebViewShouldPop]) — exactly one closer
/// pops, and only while its own route is still on top. Stale closers stay
/// silent, so the assigned screen route is never popped.
void main() {
  group('acceptWebViewShouldPop policy', () {
    test('pops when own route is current and no close delivered', () {
      expect(
        acceptWebViewShouldPop(
          routeIsCurrent: true,
          closeAlreadyDelivered: false,
        ),
        isTrue,
      );
    });

    test('stale close stays silent when route no longer current', () {
      // Authorized handler already popped the WebView: popping now would
      // eject RideAssignedScreen to the pick-ride screen.
      expect(
        acceptWebViewShouldPop(
          routeIsCurrent: false,
          closeAlreadyDelivered: false,
        ),
        isFalse,
      );
    });

    test('second closer stays silent after close delivered', () {
      expect(
        acceptWebViewShouldPop(
          routeIsCurrent: true,
          closeAlreadyDelivered: true,
        ),
        isFalse,
      );
    });

    test('no pop when neither current nor fresh', () {
      expect(
        acceptWebViewShouldPop(
          routeIsCurrent: false,
          closeAlreadyDelivered: true,
        ),
        isFalse,
      );
    });
  });

  group('close-out interleavings deliver exactly one pop', () {
    /// Minimal simulator of the two closers sharing [acceptWebViewShouldPop].
    /// Returns the number of pops performed; the WebView route stops being
    /// current after the first pop.
    int simulate({required List<String> order}) {
      var pops = 0;
      var webViewCurrent = true;
      var closeDelivered = false;

      bool closer() {
        final shouldPop = acceptWebViewShouldPop(
          routeIsCurrent: webViewCurrent,
          closeAlreadyDelivered: closeDelivered,
        );
        if (shouldPop) {
          pops += 1;
          closeDelivered = true;
          webViewCurrent = false;
        }
        return shouldPop;
      }

      for (final event in order) {
        if (event == 'self' || event == 'authorized') {
          closer();
        }
      }
      return pops;
    }

    test('self-close then authorized → exactly one pop', () {
      expect(simulate(order: ['self', 'authorized']), 1);
    });

    test('authorized then stale self-close → exactly one pop', () {
      // The regression ordering: server webhook beats client redirect.
      expect(simulate(order: ['authorized', 'self']), 1);
    });

    test('duplicate authorized events → exactly one pop', () {
      expect(simulate(order: ['authorized', 'authorized']), 1);
    });

    test('duplicate self-closes → exactly one pop', () {
      expect(simulate(order: ['self', 'self']), 1);
    });

    test('cancel after authorized → no additional pop', () {
      expect(simulate(order: ['authorized', 'self']), 1);
    });
  });

  // Navigator-level tests with stub pages wired like the real screens:
  // _PickRideStub = booking stack below (must never resurface);
  // _TrackingStub = RideAssignedScreen close-out wiring (tracked route,
  // authorized handler pops only while current, stale cancel stays silent);
  // _CheckoutStub = PaymentWebViewScreen guarded self-close.
  group('assigned screen is never popped by WebView close-out', () {
    testWidgets('stale self-close after authorized pop stays silent',
        (tester) async {
      Route? capturedCheckoutRoute;
      await tester.pumpWidget(
        MaterialApp(
          home: _PickRideStub(
            openTracking: (context) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _TrackingStub(
                    onCheckoutRoute: (route) => capturedCheckoutRoute = route,
                  ),
                ),
              );
            },
          ),
        ),
      );
      expect(find.text('pick-ride'), findsOneWidget);

      // Rider books → tracking screen.
      await tester.tap(find.text('go-tracking'));
      await tester.pumpAndSettle();
      expect(find.text('tracking'), findsOneWidget);

      // Driver accepts → WebView auto-opens on top of tracking.
      await tester.tap(find.text('open-checkout'));
      await tester.pumpAndSettle();
      expect(find.text('checkout'), findsOneWidget);

      // payment:authorized wins the race → handler pops the checkout.
      // (Triggered from the checkout stub: in production the socket event
      // reaches tracking state while the checkout covers it.)
      await tester.tap(find.text('fire-authorized-while-open'));
      await tester.pumpAndSettle();
      expect(find.text('tracking-authorized'), findsOneWidget);
      expect(find.text('checkout'), findsNothing);
      expect(capturedCheckoutRoute, isNotNull);
      expect(capturedCheckoutRoute!.isCurrent, isFalse);

      // The WebView's in-flight success callback fires late (stale closer).
      // The real screen evaluates the same policy with its now-defunct
      // route: must stay silent.
      final staleShouldPop = acceptWebViewShouldPop(
        routeIsCurrent: capturedCheckoutRoute!.isCurrent,
        closeAlreadyDelivered: false,
      );
      expect(staleShouldPop, isFalse);

      // No pop performed → tracking intact, pick-ride never revealed.
      await tester.pumpAndSettle();
      expect(find.text('tracking-authorized'), findsOneWidget);
      expect(find.text('pick-ride'), findsNothing);

      // Sensitivity control: the OLD bare-pop behavior (one raw extra pop)
      // WOULD eject to pick-ride — proving this test detects the bug.
      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('pick-ride'), findsOneWidget);
    });

    testWidgets('fresh self-close pops checkout, tracking stays',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _PickRideStub(
            openTracking: (context) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _TrackingStub()),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('go-tracking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open-checkout'));
      await tester.pumpAndSettle();

      // Normal ordering: client redirect beats the socket event.
      await tester.tap(find.text('checkout-success'));
      await tester.pumpAndSettle();
      expect(find.text('tracking-authorized'), findsOneWidget);
      expect(find.text('pick-ride'), findsNothing);
    });

    testWidgets('duplicate authorized events pop at most once',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _PickRideStub(
            openTracking: (context) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _TrackingStub()),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('go-tracking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open-checkout'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('fire-authorized-while-open'));
      await tester.pumpAndSettle();
      // Second delivery for the same payment: nothing left to pop.
      await tester.tap(find.text('fire-authorized'));
      await tester.pumpAndSettle();
      expect(find.text('tracking-authorized'), findsOneWidget);
      expect(find.text('pick-ride'), findsNothing);
    });

    testWidgets('cancel close keeps tracking, never ejects', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _PickRideStub(
            openTracking: (context) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _TrackingStub()),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('go-tracking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open-checkout'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('checkout-cancel'));
      await tester.pumpAndSettle();
      expect(find.text('tracking'), findsOneWidget);
      expect(find.text('pick-ride'), findsNothing);
    });
  });
}

class _PickRideStub extends StatelessWidget {
  final void Function(BuildContext context) openTracking;

  const _PickRideStub({required this.openTracking});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('pick-ride'),
            TextButton(
              onPressed: () => openTracking(context),
              child: const Text('go-tracking'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackingStub extends StatefulWidget {
  final void Function(Route route)? onCheckoutRoute;

  const _TrackingStub({this.onCheckoutRoute});

  @override
  State<_TrackingStub> createState() => _TrackingStubState();
}

class _TrackingStubState extends State<_TrackingStub> {
  // Mirrors RideAssignedScreen: tracked route + open flag + authorized flag.
  Route? _webViewRoute;
  bool _webViewOpen = false;
  bool _authorized = false;
  String _note = '';

  Future<void> _openCheckout() async {
    if (_webViewOpen) return;
    _webViewOpen = true;
    final route = MaterialPageRoute(
      // The authorized trigger rides on the checkout stub: production
      // delivers the socket event to tracking state while covered.
      builder: (_) => _CheckoutStub(
        onAuthorizedEvent: _fireAuthorized,
      ),
    );
    _webViewRoute = route;
    widget.onCheckoutRoute?.call(route);
    try {
      final result = await Navigator.push(context, route);
      if (!mounted) return;
      // Mirrors the assigned awaiter: success flips to authorized unless the
      // event already did; a stale cancel after authorize stays silent.
      if (result is Map && result['success'] == true) {
        if (_authorized) return;
        setState(() => _authorized = true);
      } else {
        if (_authorized) return;
        setState(() => _note = 'not completed');
      }
    } finally {
      _webViewRoute = null;
      _webViewOpen = false;
    }
  }

  bool _didDeliverClose = false;

  void _fireAuthorized() {
    // Mirrors the payment:authorized handler: tracked route, only while
    // current. (Shares _didDeliverClose so the two closers stay exactly-one
    // across orderings, like the real screens' flag + route clearing.)
    setState(() => _authorized = true);
    final route = _webViewRoute;
    if (acceptWebViewShouldPop(
      routeIsCurrent: route?.isCurrent == true,
      closeAlreadyDelivered: _didDeliverClose,
    )) {
      _didDeliverClose = true;
      Navigator.of(context).pop({'success': true});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_authorized ? 'tracking-authorized' : 'tracking'),
            if (_note.isNotEmpty) Text(_note),
            TextButton(
              onPressed: _openCheckout,
              child: const Text('open-checkout'),
            ),
            TextButton(
              onPressed: _fireAuthorized,
              child: const Text('fire-authorized'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutStub extends StatefulWidget {
  final void Function() onAuthorizedEvent;

  const _CheckoutStub({required this.onAuthorizedEvent});

  @override
  State<_CheckoutStub> createState() => _CheckoutStubState();
}

class _CheckoutStubState extends State<_CheckoutStub> {
  bool _didDeliverClose = false;

  void _selfClose(bool success) {
    // Mirrors PaymentWebViewScreen._closeWebViewOnce (no-dialog branch):
    // pop only while our own route is still on top, exactly once.
    if (!mounted || _didDeliverClose) return;
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
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('checkout'),
            TextButton(
              onPressed: () => _selfClose(true),
              child: const Text('checkout-success'),
            ),
            TextButton(
              onPressed: () => _selfClose(false),
              child: const Text('checkout-cancel'),
            ),
            TextButton(
              onPressed: widget.onAuthorizedEvent,
              child: const Text('fire-authorized-while-open'),
            ),
          ],
        ),
      ),
    );
  }
}
