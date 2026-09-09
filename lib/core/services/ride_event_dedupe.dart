import 'package:flutter/foundation.dart';

/// Single shared guard against FCM + socket delivering the same ride event
/// twice (duplicate banners, double navigation, repeated dialogs).
///
/// Both transports call [shouldHandle] before acting on an event. The first
/// caller within the window wins; the second sees `false` and skips. Keyed
/// on event type + ride id with a ~5s window, so genuinely new events for
/// the same ride still flow through.
class RideEventDedupe {
  static final Map<String, DateTime> _handledAt = {};

  /// Dedupe window — both transports for one backend state change arrive
  /// within a couple of seconds of each other.
  static const window = Duration(seconds: 5);

  /// Returns true the first time a (type, rideId) pair is seen within
  /// [window]; false for repeats. [source] is 'fcm' or 'socket', used only
  /// for logging.
  static bool shouldHandle({
    required String source,
    required String type,
    String? rideId,
  }) {
    final now = DateTime.now();
    _handledAt.removeWhere((_, at) => now.difference(at) > window);
    final key = '$type:${rideId ?? ''}';
    final last = _handledAt[key];
    if (last != null && now.difference(last) <= window) {
      debugPrint(
        '🔁 [RideEventDedupe] Duplicate $type (ride=$rideId) from $source — skipping',
      );
      return false;
    }
    _handledAt[key] = now;
    return true;
  }

  /// Convenience overload that pulls the event type + ride id out of either
  /// an [FcmNotificationData]-shaped map or a raw socket payload map.
  /// Socket payloads use varying keys (`rideId`, `bookingId`, `_id`, `id`).
  static bool shouldHandleEvent({
    required String source,
    required String type,
    dynamic data,
  }) {
    String? rideId;
    if (data is Map) {
      for (final key in ['rideId', 'bookingId', '_id', 'id']) {
        final value = data[key]?.toString();
        if (value != null && value.isNotEmpty) {
          rideId = value;
          break;
        }
      }
    }
    return shouldHandle(source: source, type: type, rideId: rideId);
  }

  @visibleForTesting
  static void resetForTests() => _handledAt.clear();
}
