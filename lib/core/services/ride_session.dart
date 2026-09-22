// Global cold-start / resume entry for active-ride restore.
//
// Socket deltas are lossy across kills — the authoritative `getRideDetails`
// fetch on launch/resume is the source of truth (Uber pattern). Both the
// rider (`home_screen`) and driver (`driver_home_screen`) cold-start paths
// delegate here so screen-local restore logic cannot drift.
//
// Gap-merge rule: server status always wins; locally-queued user intents
// (pending `SocketService.eventQueue` entries for this ride) are flagged via
// `Restored.preserveIntents` and replay AFTER the merge, never overwritten.

import 'package:flutter/foundation.dart';

import '../api_service.dart';
import 'active_ride_storage.dart';
import 'ride_event_dedupe.dart';
import 'socket_service.dart';

/// Navigation decision produced by [routeForStatus].
///
/// Values are screen-agnostic on purpose — callers map them onto their
/// existing (pixel-identical) navigation targets:
/// - `searching` → rider searching overlay payload (requested/searching/reassigning)
/// - `assigned` → assigned screen (accepted/driver_arrived)
/// - `progress` → trip progress screen (in_progress/at_stop)
/// - `receipt` → fare receipt (completed/cash-pending style terminal states)
abstract class RestoreRoute {
  static const String searching = 'searching';
  static const String assigned = 'assigned';
  static const String progress = 'progress';
  static const String receipt = 'receipt';
}

/// Outcome of [restoreActiveRide] / [resyncActiveRide].
sealed class RestoreOutcome {
  const RestoreOutcome();
}

/// Snapshot reconciled against the server — caller navigates to [route]
/// with [ride]. [preserveIntents] is true when locally-queued user intents
/// exist for this ride and must replay after the merge.
class Restored extends RestoreOutcome {
  final String route;
  final Map<String, dynamic> ride;
  final bool preserveIntents;
  final bool isScheduled;

  const Restored({
    required this.route,
    required this.ride,
    this.preserveIntents = false,
    this.isScheduled = false,
  });
}

/// Snapshot dropped (caller goes home / stays put). [reason] is
/// `stale:<detail>` or `final:<status>` for logging.
class Cleared extends RestoreOutcome {
  final String reason;

  const Cleared(this.reason);
}

/// No snapshot to restore (or fetch failed and the snapshot was kept).
/// Caller stays on the current screen.
class RideNone extends RestoreOutcome {
  const RideNone();
}

/// Pure merge-decision result for [decideRestore] (widget-free, unit-tested).
class RestoreDecision {
  final bool shouldRestore;
  final bool shouldClear;
  final String? route;
  final bool preserveIntents;
  final String? clearReason;

  const RestoreDecision._({
    required this.shouldRestore,
    required this.shouldClear,
    this.route,
    this.preserveIntents = false,
    this.clearReason,
  });

  const RestoreDecision.restored({
    required String route,
    bool preserveIntents = false,
  }) : this._(
         shouldRestore: true,
         shouldClear: false,
         route: route,
         preserveIntents: preserveIntents,
       );

  const RestoreDecision.cleared(String reason)
    : this._(shouldRestore: false, shouldClear: true, clearReason: reason);

  const RestoreDecision.none()
    : this._(shouldRestore: false, shouldClear: false);
}

/// Map a backend ride status to a [RestoreRoute] navigation decision.
/// Scheduled vs instant rides share the same route mapping — only the
/// payload differs, never the destination.
String routeForStatus(String status, {bool isScheduled = false}) {
  final s = status.trim().toLowerCase();
  // isScheduled intentionally does not branch: scheduled rides restore to
  // the identical screens as instant rides (verified by unit tests).
  if (s == 'requested' || s == 'searching' || s == 'reassigning') {
    return RestoreRoute.searching;
  }
  if (s == 'in_progress' || s == 'at_stop') {
    return RestoreRoute.progress;
  }
  if (s == 'completed' ||
      s == 'early_completed' ||
      s == 'cash_pending' ||
      s == 'cash-pending' ||
      s == 'waiting_cash' ||
      s == 'payment_pending') {
    return RestoreRoute.receipt;
  }
  // accepted / driver_arrived / arrived + any unknown non-final status land
  // on the assigned screen (same as the legacy home restore fallthrough).
  return RestoreRoute.assigned;
}

/// Pure merge-decision helper (no I/O — unit-tested in
/// `test/ride_session_test.dart`).
///
/// - `snapshotStatus == null` (no snapshot) → [RestoreDecision.none].
/// - [isStale] → cleared (`stale`).
/// - effective status (server wins, snapshot fallback) in
///   [ActiveRideStorage.finalStatuses] → cleared (`final:<status>`).
/// - otherwise → restored with [routeForStatus] + [preserveIntents] echoing
///   [hasPendingIntents] (queued intents replay after merge, never dropped).
RestoreDecision decideRestore({
  String? snapshotStatus,
  String? serverStatus,
  bool isStale = false,
  bool hasPendingIntents = false,
  bool isScheduled = false,
}) {
  if (isStale) return const RestoreDecision.cleared('stale');
  final effective = (serverStatus ?? snapshotStatus)?.trim().toLowerCase();
  if (effective == null || effective.isEmpty) {
    return const RestoreDecision.none();
  }
  if (ActiveRideStorage.finalStatuses.contains(effective)) {
    return RestoreDecision.cleared('final:$effective');
  }
  return RestoreDecision.restored(
    route: routeForStatus(effective, isScheduled: isScheduled),
    preserveIntents: hasPendingIntents,
  );
}

/// Map a rider UI/socket status to the canonical snapshot status persisted
/// in [ActiveRideStorage].
///
/// The rider searching overlay covers `requested`/`searching`/`reassigning`
/// (all route to [RestoreRoute.searching]) but the snapshot stores the
/// backend-canonical `requested` so cold start reconciles 1:1 with
/// `getRideDetails`. `arrived` normalizes to `driver_arrived` and `at_stop`
/// to `in_progress` (identical restore routes). Unknown statuses pass
/// through lower-cased so future backend states still persist verbatim.
String snapshotStatusForRider(String status) {
  final s = status.trim().toLowerCase();
  if (s == 'searching' || s == 'reassigning') return 'requested';
  if (s == 'arrived') return 'driver_arrived';
  if (s == 'at_stop') return 'in_progress';
  return s;
}

/// Map a driver UI status to the backend-canonical snapshot status.
///
/// The driver execution screen persists ITS OWN state names (`pickup` for
/// accepted, `arrived` for driver_arrived); `in_progress`/`at_stop` already
/// match the backend (at_stop stays distinct — the driver wait timer keys
/// off it, unlike the rider side which collapses it). Unknown statuses pass
/// through lower-cased so future states still persist verbatim.
String snapshotStatusForDriver(String status) {
  final s = status.trim().toLowerCase();
  if (s == 'pickup') return 'accepted';
  if (s == 'arrived') return 'driver_arrived';
  if (s == 'driver_arrived') return 'driver_arrived';
  if (s == 'in_progress') return 'in_progress';
  if (s == 'at_stop') return 'at_stop';
  return s;
}

/// Build an optimistic cold-start ride map from a live snapshot + trip blob
/// when the authoritative fetch failed (offline / token race / cold TLS).
/// Server values always win later via the background reconcile — this only
/// keeps the driver on the execution screen instead of a dead home.
///
/// Returns null when there is nothing restorable (no id, no status, or a
/// status in [ActiveRideStorage.finalStatuses]).
Map<String, dynamic>? syntheticRideFromSnapshot({
  required String? rideId,
  required String? snapshotStatus,
  required Map<String, dynamic> blob,
}) {
  if (rideId == null || rideId.isEmpty) return null;
  if (snapshotStatus == null || snapshotStatus.trim().isEmpty) return null;
  final canonical = snapshotStatusForDriver(snapshotStatus);
  if (ActiveRideStorage.finalStatuses.contains(canonical)) return null;
  final stops = blob['stops'];
  return {
    '_id': rideId,
    'status': canonical,
    'stops': stops is List ? stops : [],
    'currentStopIndex': blob['currentStopIndex'] ?? 0,
    'totalWaitMinutes': blob['totalWaitMinutes'] ?? 0,
    'totalWaitFee': blob['totalWaitFee'] ?? 0.0,
    'actualFare': blob['actualFare'] ?? 0.0,
    'paymentMethod': blob['paymentMethod'],
    'paymentStatus': blob['paymentStatus'],
    'optimistic': true,
  };
}

/// Extract the driver id from a `getRideDetails` ride payload.
/// Tolerates `driver` as map (`_id`/`id`/`driverId`) or a top-level id field.
String? driverIdFromRide(Map<String, dynamic> ride) {
  final driver = ride['driver'];
  if (driver is Map) {
    for (final key in ['_id', 'id', 'driverId']) {
      final v = driver[key]?.toString();
      if (v != null && v.isNotEmpty) return v;
    }
  }
  for (final key in ['driverId', 'driver_id']) {
    final v = ride[key]?.toString();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

/// Read a numeric field tolerantly (num or numeric string).
double _numOrZero(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

int _intOrZero(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// Persist the server payload's trip blob so driver mid-trip state
/// (stops/wait/fare/payment/stop index) restores with parity to the rider.
Future<void> _persistTripBlob(Map<String, dynamic> ride) async {
  final stops = ride['stops'];
  await ActiveRideStorage.saveTripState(
    stops: stops is List ? List<dynamic>.from(stops) : null,
    totalWaitMinutes: ride.containsKey('totalWaitMinutes')
        ? _intOrZero(ride['totalWaitMinutes'])
        : null,
    totalWaitFee: ride.containsKey('totalWaitFee')
        ? _numOrZero(ride['totalWaitFee'])
        : null,
    actualFare: ride.containsKey('actualFare')
        ? _numOrZero(ride['actualFare'])
        : null,
    paymentMethod: ride['paymentMethod']?.toString(),
    paymentStatus: ride['paymentStatus']?.toString(),
    currentStopIndex: ride.containsKey('currentStopIndex')
        ? _intOrZero(ride['currentStopIndex'])
        : null,
    scheduledPickupTime: ride['scheduledPickupTime']?.toString(),
    scheduledStatus: ride['scheduledStatus']?.toString(),
    scheduledPaymentMethod: ride['scheduledPaymentMethod']?.toString(),
  );
}

/// Shared fetch + merge core. Returns the reconciled ride map, or null when
/// there is nothing to apply (no snapshot / fetch failure / cleared).
/// [navigate] selects restore (navigation decision) vs resync (no nav) logging.
Future<Map<String, dynamic>?> _fetchAndMerge({
  required ApiService api,
  required SocketService socket,
  required String rideId,
  required String? snapshotStatus,
  required bool forNavigation,
}) async {
  Map<String, dynamic> response;
  try {
    response = await api.getRideDetails(rideId);
  } catch (e) {
    // Network/auth failure: keep the snapshot for a later retry — never
    // wipe local state on a transient error.
    debugPrint('⚠️ [RideSession] getRideDetails failed, keeping snapshot: $e');
    return null;
  }
  if (response['success'] != true) {
    debugPrint('⚠️ [RideSession] getRideDetails !success, keeping snapshot');
    return null;
  }
  final raw = response['data'];
  final rideRaw = raw is Map ? (raw['ride'] ?? raw) : null;
  if (rideRaw is! Map) {
    debugPrint('⚠️ [RideSession] getRideDetails missing ride, keeping snapshot');
    return null;
  }
  final ride = Map<String, dynamic>.from(rideRaw);
  final serverStatus = (ride['status'] ?? '').toString().toLowerCase();

  if (ActiveRideStorage.finalStatuses.contains(serverStatus)) {
    debugPrint('🧹 [RideSession] Server final ($serverStatus) — clearing');
    await ActiveRideStorage.clear();
    return null;
  }

  // 5s FCM+socket dedupe window: when the snapshot already carries this exact
  // status applied within the window, the socket path handled it — skip the
  // write, keep rooms/tracking refresh below.
  final lastEventAt = await ActiveRideStorage.getLastEventAt();
  if (snapshotStatus != null &&
      snapshotStatus.toLowerCase() == serverStatus &&
      lastEventAt != null &&
      DateTime.now().difference(lastEventAt) <= RideEventDedupe.window) {
    debugPrint(
      '🔁 [RideSession] Status $serverStatus already applied via socket — merge no-op',
    );
  } else {
    // Server wins: authoritative status + trip blob overwrite the snapshot.
    await ActiveRideStorage.updateStatus(serverStatus);
    await _persistTripBlob(ride);
    await ActiveRideStorage.setLastEventAt(DateTime.now());
  }

  // Room rejoin + driver-tracking restart (kill wipes SocketService._joinedRooms).
  socket.joinRoom('ride:$rideId');
  final trackingStatuses = {'accepted', 'driver_arrived', 'arrived'};
  if (trackingStatuses.contains(serverStatus)) {
    final driverId = driverIdFromRide(ride);
    if (driverId != null && driverId.isNotEmpty) {
      socket.joinDriverRoom(driverId);
      socket.startTrackingDriver(driverId);
    }
  }
  return ride;
}

/// Cold-start entry: reads the versioned snapshot, drops it when stale
/// (>24h via [ActiveRideStorage.staleAfter]) or final, else reconciles
/// against `getRideDetails` and returns a navigation decision.
///
/// Never throws — fetch failures keep the snapshot and yield [RideNone].
Future<RestoreOutcome> restoreActiveRide({
  required ApiService api,
  required SocketService socket,
}) async {
  final rideId = await ActiveRideStorage.getRideId();
  if (rideId == null || rideId.isEmpty) return const RideNone();

  if (await ActiveRideStorage.isStale()) {
    debugPrint('🧹 [RideSession] Snapshot stale — clearing');
    await ActiveRideStorage.clear();
    return const Cleared('stale');
  }

  final snapshotStatus = await ActiveRideStorage.getStatus();
  final snapshotLower = snapshotStatus?.toLowerCase();
  if (snapshotLower != null &&
      ActiveRideStorage.finalStatuses.contains(snapshotLower)) {
    debugPrint('🧹 [RideSession] Snapshot final ($snapshotLower) — clearing');
    await ActiveRideStorage.clear();
    return Cleared('final:$snapshotLower');
  }

  final ride = await _fetchAndMerge(
    api: api,
    socket: socket,
    rideId: rideId,
    snapshotStatus: snapshotStatus,
    forNavigation: true,
  );
  if (ride == null) {
    // Null here means cleared-on-server-final or kept-on-failure. Re-read:
    // cleared snapshots report Cleared, kept ones report none (retry later).
    final stillThere = await ActiveRideStorage.getRideId();
    if (stillThere == null) {
      final serverHint = snapshotLower ?? 'unknown';
      return Cleared('final:$serverHint');
    }
    return const RideNone();
  }

  final serverStatus = (ride['status'] ?? '').toString().toLowerCase();
  final hasPending = socket.eventQueue.pendingCount > 0;
  final decision = decideRestore(
    snapshotStatus: snapshotStatus,
    serverStatus: serverStatus,
    hasPendingIntents: hasPending,
    isScheduled: ride['isScheduled'] == true,
  );
  if (decision.shouldClear) {
    await ActiveRideStorage.clear();
    return Cleared(decision.clearReason ?? 'final:$serverStatus');
  }
  if (!decision.shouldRestore) return const RideNone();
  return Restored(
    route: decision.route!,
    ride: ride,
    preserveIntents: decision.preserveIntents,
    isScheduled: ride['isScheduled'] == true,
  );
}

/// Lightweight re-sync for foreground resume + FCM tap: same authoritative
/// fetch + merge as [restoreActiveRide], but never navigates and never
/// clears on stale (a resume is not a cold start — the snapshot may simply
/// predate [staleAfter] while the ride is live; the server fetch decides).
///
/// When [rideId] is omitted the snapshot rideId is used. Returns the
/// reconciled ride map, or null when nothing was applied.
Future<Map<String, dynamic>?> resyncActiveRide({
  required ApiService api,
  required SocketService socket,
  String? rideId,
}) async {
  final id = rideId ?? await ActiveRideStorage.getRideId();
  if (id == null || id.isEmpty) return null;
  final snapshotStatus = await ActiveRideStorage.getStatus();
  final ride = await _fetchAndMerge(
    api: api,
    socket: socket,
    rideId: id,
    snapshotStatus: snapshotStatus,
    forNavigation: false,
  );
  if (ride == null) return null;
  final serverStatus = (ride['status'] ?? '').toString().toLowerCase();
  debugPrint('🔄 [RideSession] Resynced $id → $serverStatus (no navigation)');
  return ride;
}
