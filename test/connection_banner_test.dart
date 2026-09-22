import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/services/socket_service.dart';
import 'package:mktours/core/widgets/connection_banner.dart';

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
}
