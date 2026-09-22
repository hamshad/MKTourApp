import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/core/services/active_ride_storage.dart';
import 'package:mktours/core/services/ride_session.dart';

// Widget-free merge-decision tests for the RideSession global restore entry.
// Covers the decision matrix only (decideRestore + routeForStatus +
// driverIdFromRide) — no ApiService/SocketService instances, no sockets.
void main() {
  group('decideRestore: stale / final / none', () {
    test('stale snapshot clears without consulting statuses', () {
      const d = RestoreDecision.cleared('stale');
      expect(d.shouldClear, isTrue);
      expect(d.shouldRestore, isFalse);

      final decision = decideRestore(
        snapshotStatus: 'accepted',
        serverStatus: 'accepted',
        isStale: true,
      );
      expect(decision.shouldClear, isTrue);
      expect(decision.clearReason, 'stale');
      expect(decision.shouldRestore, isFalse);
    });

    test('server final clears even when snapshot was live', () {
      for (final finalStatus in ActiveRideStorage.finalStatuses) {
        final decision = decideRestore(
          snapshotStatus: 'in_progress',
          serverStatus: finalStatus,
        );
        expect(decision.shouldClear, isTrue, reason: finalStatus);
        expect(decision.clearReason, 'final:$finalStatus');
      }
    });

    test('snapshot final with no server fetch clears', () {
      final decision = decideRestore(snapshotStatus: 'cancelled');
      expect(decision.shouldClear, isTrue);
      expect(decision.clearReason, 'final:cancelled');
    });

    test('null snapshot yields none (stay put, retry later)', () {
      final decision = decideRestore();
      expect(decision.shouldClear, isFalse);
      expect(decision.shouldRestore, isFalse);
      expect(decision.route, isNull);
    });
  });

  group('decideRestore: server-wins vs intent-replay', () {
    test('server newer status restores with server route', () {
      final decision = decideRestore(
        snapshotStatus: 'requested',
        serverStatus: 'accepted',
      );
      expect(decision.shouldRestore, isTrue);
      expect(decision.route, RestoreRoute.assigned);
      expect(decision.preserveIntents, isFalse);
    });

    test('snapshot newer with pending intents restores preserving intents', () {
      // Gap merge: queued user intents replay AFTER the merge, never dropped.
      final decision = decideRestore(
        snapshotStatus: 'accepted',
        serverStatus: 'accepted',
        hasPendingIntents: true,
      );
      expect(decision.shouldRestore, isTrue);
      expect(decision.route, RestoreRoute.assigned);
      expect(decision.preserveIntents, isTrue);
    });

    test('server status wins over divergent snapshot status', () {
      final decision = decideRestore(
        snapshotStatus: 'requested',
        serverStatus: 'in_progress',
        hasPendingIntents: true,
      );
      expect(decision.shouldRestore, isTrue);
      expect(decision.route, RestoreRoute.progress);
      // Intents still flagged for post-merge replay.
      expect(decision.preserveIntents, isTrue);
    });

    test('status compare is case-insensitive', () {
      final decision = decideRestore(
        snapshotStatus: 'ACCEPTED',
        serverStatus: 'Driver_Arrived',
      );
      expect(decision.shouldRestore, isTrue);
      expect(decision.route, RestoreRoute.assigned);
    });
  });

  group('routeForStatus: scheduled vs instant parity', () {
    test('searching family maps to searching overlay', () {
      for (final s in ['requested', 'searching', 'reassigning']) {
        expect(routeForStatus(s), RestoreRoute.searching, reason: s);
        expect(
          routeForStatus(s, isScheduled: true),
          RestoreRoute.searching,
          reason: 'scheduled $s',
        );
      }
    });

    test('accepted family maps to assigned', () {
      for (final s in ['accepted', 'driver_arrived', 'arrived']) {
        expect(routeForStatus(s), RestoreRoute.assigned, reason: s);
        expect(
          routeForStatus(s, isScheduled: true),
          RestoreRoute.assigned,
          reason: 'scheduled $s',
        );
      }
    });

    test('trip family maps to progress', () {
      for (final s in ['in_progress', 'at_stop']) {
        expect(routeForStatus(s), RestoreRoute.progress, reason: s);
        expect(
          routeForStatus(s, isScheduled: true),
          RestoreRoute.progress,
          reason: 'scheduled $s',
        );
      }
    });

    test('terminal cash-pending maps to receipt', () {
      for (final s in ['cash_pending', 'waiting_cash', 'payment_pending']) {
        expect(routeForStatus(s), RestoreRoute.receipt, reason: s);
      }
    });

    test('scheduled flag never changes the route', () {
      const statuses = [
        'requested',
        'searching',
        'reassigning',
        'accepted',
        'driver_arrived',
        'arrived',
        'in_progress',
        'at_stop',
      ];
      for (final s in statuses) {
        expect(
          routeForStatus(s, isScheduled: true),
          routeForStatus(s),
          reason: s,
        );
      }
    });
  });

  group('driverIdFromRide', () {
    test('reads driver map _id / id / driverId', () {
      expect(
        driverIdFromRide({
          'driver': {'_id': 'd1'},
        }),
        'd1',
      );
      expect(
        driverIdFromRide({
          'driver': {'id': 'd2'},
        }),
        'd2',
      );
      expect(
        driverIdFromRide({
          'driver': {'driverId': 'd3'},
        }),
        'd3',
      );
    });

    test('falls back to top-level driverId, null when absent', () {
      expect(driverIdFromRide({'driverId': 'd4'}), 'd4');
      expect(driverIdFromRide({'driver': {}, 'status': 'accepted'}), isNull);
      expect(driverIdFromRide({'status': 'accepted'}), isNull);
    });
  });
}
