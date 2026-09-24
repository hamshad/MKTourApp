import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/services/socket_service.dart';
import 'package:mktours/core/widgets/connection_banner.dart';
import 'package:mktours/core/widgets/active_ride_back_guard.dart';

// Widget tests pinning the connection UX contract:
// live renders nothing (pixel-identical healthy UI), reconnecting renders
// nothing (transient self-heal, no nag), offline shows retry that fires
// exactly once (2s debounce).
void main() {
  group('ConnectionBanner states', () {
    testWidgets('live renders nothing (zero layout shift)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConnectionBanner(
              forcedState: SocketConnectionState.online,
            ),
          ),
        ),
      );

      expect(find.textContaining('Reconnecting'), findsNothing);
      expect(find.textContaining('No connection'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.textContaining('Last updated'), findsNothing);
    });

    testWidgets('reconnecting renders nothing (no idle nag)', (tester) async {
      final disconnectedAt =
          DateTime.now().subtract(const Duration(seconds: 45));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConnectionBanner(
              forcedState: SocketConnectionState.reconnecting,
              lastDisconnectedAt: disconnectedAt,
            ),
          ),
        ),
      );

      expect(
        find.text('Reconnecting… showing last known'),
        findsNothing,
      );
      expect(find.textContaining('Last updated'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('offline shows retry and tap fires handler once', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConnectionBanner(
              forcedState: SocketConnectionState.offline,
              lastDisconnectedAt:
                  DateTime.now().subtract(const Duration(seconds: 65)),
              onRetry: () => calls++,
            ),
          ),
        ),
      );

      expect(
        find.text('No connection — actions will send when reconnected'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('double-tap retry within 2s is ignored', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConnectionBanner(
              forcedState: SocketConnectionState.offline,
              onRetry: () => calls++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(calls, 1);
    });
  });

  group('stale helpers', () {
    test('isRideDataStale flags gaps past 30s', () {
      expect(
        isRideDataStale(DateTime.now().subtract(const Duration(seconds: 31))),
        isTrue,
      );
      expect(
        isRideDataStale(DateTime.now().subtract(const Duration(seconds: 10))),
        isFalse,
      );
      expect(isRideDataStale(null), isTrue);
    });

    test('formatLastUpdated renders age copy', () {
      expect(
        formatLastUpdated(const Duration(seconds: 45)),
        'Last updated 45s ago',
      );
      expect(
        formatLastUpdated(const Duration(minutes: 2)),
        'Last updated 2m ago',
      );
    });

    testWidgets('StaleDataChip shows timestamped age', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaleDataChip(
              lastUpdated:
                  DateTime.now().subtract(const Duration(seconds: 50)),
            ),
          ),
        ),
      );

      expect(find.textContaining('Last updated'), findsOneWidget);
    });
  });

  group('active ride back guard', () {
    const message =
        'Your ride is still active. Stay here to track your driver.';

    testWidgets('system back stays on active ride and explains why', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ActiveRideBackGuard(
                      message:
                          'Your ride is still active. Stay here to track your driver.',
                      child: Scaffold(body: Center(child: Text('tracking'))),
                    ),
                  ),
                ),
                child: const Text('booking'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('booking'));
      await tester.pumpAndSettle();
      expect(find.text('tracking'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('tracking'), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      expect(find.text('booking'), findsNothing);
    });

    testWidgets('disabled guard allows terminal route to pop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ActiveRideBackGuard(
                      enabled: false,
                      child: Scaffold(body: Center(child: Text('receipt'))),
                    ),
                  ),
                ),
                child: const Text('booking'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('booking'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('receipt'))).pop();
      await tester.pumpAndSettle();

      expect(find.text('booking'), findsOneWidget);
      expect(find.text('receipt'), findsNothing);
    });

    testWidgets('active guard allows terminal pushReplacement', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ActiveRideBackGuard(
                      child: Scaffold(body: Center(child: Text('tracking'))),
                    ),
                  ),
                ),
                child: const Text('booking'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('booking'));
      await tester.pumpAndSettle();
      final trackingContext = tester.element(find.text('tracking'));
      Navigator.of(trackingContext).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Center(child: Text('receipt'))),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('receipt'), findsOneWidget);
      expect(find.text('tracking'), findsNothing);
    });
  });
}
