import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mktours/core/services/socket_event_queue.dart';

/// Transport queue contract (phase 19-01): dedupe, idempotency keys, tiered
/// expiry, attempt-bounded requeue, critical-first drain, persistence.
///
/// Widget-free by design: socket_io_client needs a live server, so only the
/// queue (the unit-testable half of the transport) is pinned here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Fire-and-forget _persistQueue completes on the event loop.
  Future<void> settle() => Future.delayed(const Duration(milliseconds: 50));

  group('dedupe', () {
    test('location updates collapse to the latest payload', () {
      final queue = SocketEventQueue();
      queue.enqueue('driver:locationUpdate',
          {'driverId': 'd1', 'latitude': 1.0, 'longitude': 1.0});
      queue.enqueue('driver:locationUpdate',
          {'driverId': 'd1', 'latitude': 2.0, 'longitude': 2.0});

      expect(queue.pendingCount, 1);
      final drained = queue.drain();
      expect(drained.single.data['latitude'], 2.0);
      queue.dispose();
    });

    test('critical events are never deduped', () {
      final queue = SocketEventQueue();
      queue.enqueue('ride:accept', {'rideId': 'r1'});
      queue.enqueue('ride:accept', {'rideId': 'r2'});

      expect(queue.pendingCount, 2);
      queue.dispose();
    });
  });

  group('idempotency keys', () {
    test('critical events carry non-empty keys containing the event name', () {
      final queue = SocketEventQueue();
      queue.enqueue('ride:accept', {'rideId': 'r1'});

      final drained = queue.drain();
      expect(drained.single.idempotencyKey, isNotEmpty);
      expect(drained.single.idempotencyKey, contains('ride:accept'));
      queue.dispose();
    });

    test('key format is rideId:event:createdAtMs when payload has rideId',
        () {
      final queue = SocketEventQueue();
      queue.enqueue('ride:accept', {'rideId': 'ride-42'});

      final drained = queue.drain();
      final parts = drained.single.idempotencyKey.split(':');
      expect(parts[0], 'ride-42');
      expect(parts[1], 'ride');
      expect(int.tryParse(parts.last), isNotNull);
      queue.dispose();
    });

    test('key is random local key when payload has no rideId', () {
      final queue = SocketEventQueue();
      queue.enqueue('driver:goOnline', {'driverId': 'd1'});
      queue.enqueue('driver:goOnline', {'driverId': 'd1'});

      final drained = queue.drain();
      expect(drained, hasLength(2));
      expect(drained[0].idempotencyKey, startsWith('local:'));
      expect(drained[0].idempotencyKey, isNot(drained[1].idempotencyKey));
      queue.dispose();
    });
  });

  group('tiered expiry', () {
    test('fresh critical intent survives purgeStale', () {
      final queue = SocketEventQueue();
      queue.enqueue('ride:accept', {'rideId': 'r1'});
      queue.purgeStale();

      expect(queue.pendingCount, 1);
      queue.dispose();
    });

    test('critical TTL is 2h, best-effort TTL is 5min', () {
      final oldCritical = QueuedEvent(
        id: 'a',
        event: 'ride:accept',
        data: {'rideId': 'r1'},
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      );
      final youngCritical = QueuedEvent(
        id: 'b',
        event: 'ride:accept',
        data: {'rideId': 'r1'},
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      final oldLocation = QueuedEvent(
        id: 'c',
        event: 'driver:locationUpdate',
        data: const {},
        createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
      );
      final youngLocation = QueuedEvent(
        id: 'd',
        event: 'driver:locationUpdate',
        data: const {},
        createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      expect(oldCritical.isExpired, isTrue);
      expect(youngCritical.isExpired, isFalse);
      expect(oldLocation.isExpired, isTrue);
      expect(youngLocation.isExpired, isFalse);
    });
  });

  group('requeue', () {
    test('increments attempts and drops after max', () {
      final queue = SocketEventQueue();
      queue.enqueue('ride:accept', {'rideId': 'r1'});
      var event = queue.drain().single;

      for (var i = 1; i <= QueuedEvent.maxAttempts; i++) {
        queue.requeue(event);
        expect(event.attempts, i);
        if (i < QueuedEvent.maxAttempts) {
          expect(queue.pendingCount, 1);
          event = queue.drain().single;
        }
      }
      // 5th requeue hits the cap and is dropped.
      expect(queue.pendingCount, 0);
      queue.dispose();
    });
  });

  group('drain ordering', () {
    test('critical intents come out before best-effort, FIFO within tier',
        () {
      final queue = SocketEventQueue();
      queue.enqueue(
          'driver:locationUpdate', {'driverId': 'd1', 'latitude': 1.0});
      queue.enqueue('ride:accept', {'rideId': 'r1'});
      queue.enqueue('driver:goOnline', {'driverId': 'd1'});

      final drained = queue.drain();
      expect(drained.map((e) => e.event), [
        'ride:accept',
        'driver:goOnline',
        'driver:locationUpdate',
      ]);
      queue.dispose();
    });
  });

  group('persistence', () {
    test('round-trip via SharedPreferences keeps order and keys', () async {
      final queue = SocketEventQueue();
      queue.enqueue('ride:accept', {'rideId': 'r1'});
      queue.enqueue('driver:goOnline', {'driverId': 'd1'});
      await settle();

      final restored = SocketEventQueue();
      await restored.loadFromDisk();

      expect(restored.pendingCount, 2);
      final drained = restored.drain();
      // Critical-first: accept drains before goOnline.
      expect(drained[0].event, 'ride:accept');
      expect(drained[0].idempotencyKey, contains('r1'));
      expect(drained[0].idempotencyKey, contains('ride:accept'));
      queue.dispose();
      restored.dispose();
    });

    test('loadFromDisk filters expired, over-retried, and malformed entries',
        () async {
      final now = DateTime.now();
      final valid = QueuedEvent(
        id: 'valid',
        event: 'ride:accept',
        data: {'rideId': 'r1'},
        createdAt: now,
      );
      final expired = QueuedEvent(
        id: 'expired',
        event: 'ride:accept',
        data: {'rideId': 'r2'},
        createdAt: now.subtract(const Duration(hours: 3)),
      );
      final exhausted = QueuedEvent(
        id: 'exhausted',
        event: 'ride:accept',
        data: {'rideId': 'r3'},
        createdAt: now,
        attempts: QueuedEvent.maxAttempts,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'socket_event_queue',
        jsonEncode([
          valid.toJson(),
          expired.toJson(),
          exhausted.toJson(),
          {'bogus': 'malformed-entry'},
        ]),
      );

      final restored = SocketEventQueue();
      await restored.loadFromDisk();

      expect(restored.pendingCount, 1);
      expect(restored.drain().single.id, 'valid');
      restored.dispose();
    });
  });

  group('capacity', () {
    test('cap of 100 evicts oldest best-effort first, keeps critical',
        () {
      final queue = SocketEventQueue();
      for (var i = 0; i < 100; i++) {
        queue.enqueue('test:beacon:$i', {'seq': i});
      }
      queue.enqueue('ride:accept', {'rideId': 'r-keep'});

      expect(queue.pendingCount, SocketEventQueue.maxPersistedEvents);
      final drained = queue.drain();
      expect(drained.where((e) => e.event == 'ride:accept'), hasLength(1));
      // Oldest best-effort was evicted to make room.
      expect(drained.any((e) => e.event == 'test:beacon:0'), isFalse);
      expect(drained.any((e) => e.event == 'test:beacon:99'), isTrue);
      queue.dispose();
    });
  });

  group('ack classification', () {
    test('critical events require ack, location does not', () {
      final queue = SocketEventQueue();
      queue.enqueue('ride:accept', {'rideId': 'r1'});
      queue.enqueue(
          'driver:locationUpdate', {'driverId': 'd1', 'latitude': 1.0});

      final drained = queue.drain();
      final accept =
          drained.firstWhere((e) => e.event == 'ride:accept');
      final location =
          drained.firstWhere((e) => e.event == 'driver:locationUpdate');
      expect(accept.requiresAck, isTrue);
      expect(location.requiresAck, isFalse);
      queue.dispose();
    });
  });
}
