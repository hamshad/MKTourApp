import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mktours/core/api_service.dart';
import 'package:mktours/core/services/active_ride_storage.dart';
import 'package:mktours/core/services/ride_session.dart';
import 'package:mktours/core/services/socket_service.dart';

// Regression tests for driver-state-not-persisting: drive the REAL
// restoreActiveRide with a driver snapshot + canned server payloads.
// Pins: live driver snapshots restore when the fetch succeeds; a failed
// fetch keeps the snapshot and yields none (the driver screen then falls
// back to the optimistic snapshot+blob restore).
class FakeApi extends ApiService {
  Map<String, dynamic>? payload;
  bool throwOnFetch = false;

  @override
  Future<Map<String, dynamic>> getRideDetails(String rideId) async {
    if (throwOnFetch) throw Exception('No auth token found');
    return payload ?? {'success': false};
  }
}

Map<String, dynamic> serverRide(String status) => {
      'success': true,
      'data': {
        'ride': {
          '_id': 'ride123',
          'status': status,
          'stops': [
            {'label': 'Stop A'},
            {'label': 'Stop B'},
          ],
          'currentStopIndex': 1,
          'totalWaitMinutes': 7,
          'totalWaitFee': 3.5,
        },
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeApi api;
  late SocketService socket;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = FakeApi();
    socket = SocketService();
    socket.eventQueue.drain();
  });

  test('driver in_progress snapshot + server in_progress restores progress',
      () async {
    await ActiveRideStorage.save(
        rideId: 'ride123', role: 'driver', status: 'in_progress');
    api.payload = serverRide('in_progress');

    final outcome = await restoreActiveRide(api: api, socket: socket);

    expect(outcome, isA<Restored>());
    expect((outcome as Restored).route, RestoreRoute.progress);
  });

  test('driver at_stop snapshot + server at_stop restores progress', () async {
    await ActiveRideStorage.save(
        rideId: 'ride123', role: 'driver', status: 'at_stop');
    api.payload = serverRide('at_stop');

    final outcome = await restoreActiveRide(api: api, socket: socket);

    expect(outcome, isA<Restored>());
    expect((outcome as Restored).route, RestoreRoute.progress);
  });

  test('driver pickup(UI) snapshot + server accepted restores assigned',
      () async {
    await ActiveRideStorage.save(
        rideId: 'ride123', role: 'driver', status: 'pickup');
    api.payload = serverRide('accepted');

    final outcome = await restoreActiveRide(api: api, socket: socket);

    expect(outcome, isA<Restored>());
    expect((outcome as Restored).route, RestoreRoute.assigned);
  });

  test('fetch failure keeps snapshot and yields none (home)', () async {
    await ActiveRideStorage.save(
        rideId: 'ride123', role: 'driver', status: 'in_progress');
    api.throwOnFetch = true;

    final outcome = await restoreActiveRide(api: api, socket: socket);

    expect(outcome, isA<RideNone>());
    // Snapshot kept for retry.
    expect(await ActiveRideStorage.getRideId(), 'ride123');
  });
}
