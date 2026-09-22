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

  group('snapshotStatusForRider: save-path canonicalization', () {
    test('searching overlay family persists as backend-canonical requested', () {
      // Regression pin for the rider kill-on-searching dead-end (19-03):
      // the searching entries must persist a restorable snapshot, and the
      // snapshot must carry `requested` so cold start reconciles 1:1 with
      // getRideDetails and routes back to the searching overlay.
      for (final s in ['requested', 'searching', 'reassigning']) {
        final snap = snapshotStatusForRider(s);
        expect(snap, 'requested', reason: s);
        expect(routeForStatus(snap), RestoreRoute.searching, reason: s);
      }
    });

    test('post-searching transitions persist their restore route', () {
      expect(snapshotStatusForRider('accepted'), 'accepted');
      expect(
        routeForStatus(snapshotStatusForRider('accepted')),
        RestoreRoute.assigned,
      );
      expect(snapshotStatusForRider('driver_arrived'), 'driver_arrived');
      expect(snapshotStatusForRider('arrived'), 'driver_arrived');
      expect(snapshotStatusForRider('in_progress'), 'in_progress');
      expect(snapshotStatusForRider('at_stop'), 'in_progress');
      expect(
        routeForStatus(snapshotStatusForRider('at_stop')),
        RestoreRoute.progress,
      );
    });

    test('unknown statuses pass through lower-cased and trimmed', () {
      expect(snapshotStatusForRider('  Accepted '), 'accepted');
      expect(snapshotStatusForRider('CASH_PENDING'), 'cash_pending');
    });
  });

  group('snapshotStatusForDriver: save-path canonicalization', () {
    test('driver UI states persist as backend-canonical statuses', () {
      // The driver screen stores its own state names (pickup/arrived);
      // the snapshot must carry backend-canonical values so cold start
      // reconciles 1:1 with getRideDetails.
      expect(snapshotStatusForDriver('pickup'), 'accepted');
      expect(snapshotStatusForDriver('arrived'), 'driver_arrived');
      expect(snapshotStatusForDriver('driver_arrived'), 'driver_arrived');
      expect(snapshotStatusForDriver('in_progress'), 'in_progress');
    });

    test('at_stop stays distinct (driver wait timer keys off it)', () {
      // Unlike the rider side (which collapses at_stop → in_progress),
      // the driver must keep at_stop so the wait timer restores.
      expect(snapshotStatusForDriver('at_stop'), 'at_stop');
      expect(routeForStatus(snapshotStatusForDriver('at_stop')),
          RestoreRoute.progress);
    });

    test('unknown statuses pass through lower-cased and trimmed', () {
      expect(snapshotStatusForDriver('  Pickup '), 'accepted');
      expect(snapshotStatusForDriver('CASH_PENDING'), 'cash_pending');
    });
  });

  group('syntheticRideFromSnapshot: optimistic cold-start ride', () {
    Map<String, dynamic> blob() => {
          'stops': [
            {'label': 'A'},
            {'label': 'B'},
          ],
          'totalWaitMinutes': 7,
          'totalWaitFee': 3.5,
          'actualFare': 12.0,
          'paymentMethod': 'cash',
          'paymentStatus': 'pending',
          'currentStopIndex': 1,
        };

    test('driver UI snapshot rebuilds canonical ride with blob', () {
      final ride = syntheticRideFromSnapshot(
        rideId: 'r1',
        snapshotStatus: 'at_stop',
        blob: blob(),
      );
      expect(ride, isNotNull);
      expect(ride!['status'], 'at_stop');
      expect(ride['currentStopIndex'], 1);
      expect(ride['totalWaitMinutes'], 7);
      expect((ride['stops'] as List).length, 2);
      expect(ride['optimistic'], isTrue);
    });

    test('pickup UI snapshot canonicalizes to accepted', () {
      final ride = syntheticRideFromSnapshot(
        rideId: 'r1',
        snapshotStatus: 'pickup',
        blob: blob(),
      );
      expect(ride, isNotNull);
      expect(ride!['status'], 'accepted');
    });

    test('null id / status / final status yield null (no optimistic)', () {
      expect(
        syntheticRideFromSnapshot(
            rideId: null, snapshotStatus: 'in_progress', blob: blob()),
        isNull,
      );
      expect(
        syntheticRideFromSnapshot(rideId: 'r1', snapshotStatus: null, blob: blob()),
        isNull,
      );
      expect(
        syntheticRideFromSnapshot(
            rideId: 'r1', snapshotStatus: 'completed', blob: blob()),
        isNull,
      );
    });
  });

  group('decideRestore: driver snapshot shapes', () {
    test('driver UI snapshot reconciles via server-wins status', () {
      // Driver persists UI names (pickup); the server status decides.
      final decision = decideRestore(
        snapshotStatus: 'pickup',
        serverStatus: 'accepted',
      );
      expect(decision.shouldRestore, isTrue);
      expect(decision.route, RestoreRoute.assigned);
    });

    test('driver at_stop snapshot + server at_stop restores progress', () {
      final decision = decideRestore(
        snapshotStatus: 'at_stop',
        serverStatus: 'at_stop',
      );
      expect(decision.shouldRestore, isTrue);
      expect(decision.route, RestoreRoute.progress);
    });
  });
}
