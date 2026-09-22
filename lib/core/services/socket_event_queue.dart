import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Delivery priority: critical user intents flush first (FIFO within tier),
/// best-effort telemetry (location) flushes after.
enum EventPriority { critical, bestEffort }

/// Represents a single queued socket event that needs to be sent/retried.
class QueuedEvent {
  final String id;
  final String event;
  final dynamic data;
  final DateTime createdAt;
  final bool requiresAck;
  final String idempotencyKey;
  final EventPriority priority;
  int attempts;
  static const int maxAttempts = 5;

  /// Critical user intents survive app kill for 2h (server dedupes by
  /// [idempotencyKey] so ack-timeout replays are safe).
  static const Duration criticalExpiry = Duration(hours: 2);

  /// Best-effort telemetry goes stale fast - only the latest matters.
  static const Duration bestEffortExpiry = Duration(minutes: 5);

  QueuedEvent({
    required this.id,
    required this.event,
    required this.data,
    required this.createdAt,
    this.requiresAck = false,
    String? idempotencyKey,
    EventPriority? priority,
    this.attempts = 0,
  })  : idempotencyKey = idempotencyKey ??
            buildIdempotencyKey(
              event,
              data,
              createdAt.millisecondsSinceEpoch,
            ),
        priority = priority ??
            (SocketEventQueue.criticalEvents.contains(event)
                ? EventPriority.critical
                : EventPriority.bestEffort);

  /// `rideId:event:createdAtMs` when the payload carries a ride id, else a
  /// random `local:` key. Stable for a given intent, unique across intents.
  static String buildIdempotencyKey(
    String event,
    dynamic data,
    int createdAtMs,
  ) {
    String? rideId;
    if (data is Map) {
      for (final key in ['rideId', 'ride_id']) {
        final value = data[key];
        if (value != null && value.toString().isNotEmpty) {
          rideId = value.toString();
          break;
        }
      }
    }
    if (rideId != null) return '$rideId:$event:$createdAtMs';
    final rand = math.Random().nextInt(1 << 32);
    return 'local:$event:$createdAtMs:$rand';
  }

  bool get isCritical => priority == EventPriority.critical;

  bool get isExpired {
    final ttl = isCritical ? criticalExpiry : bestEffortExpiry;
    return DateTime.now().difference(createdAt) > ttl;
  }

  bool get hasExceededRetries => attempts >= maxAttempts;

  Map<String, dynamic> toJson() => {
        'id': id,
        'event': event,
        'data': data,
        'createdAt': createdAt.toIso8601String(),
        'requiresAck': requiresAck,
        'attempts': attempts,
        'idempotencyKey': idempotencyKey,
        'priority': priority.name,
      };

  factory QueuedEvent.fromJson(Map<String, dynamic> json) {
    final event = json['event'] as String;
    final createdAt = DateTime.parse(json['createdAt'] as String);
    EventPriority priority = EventPriority.bestEffort;
    final rawPriority = json['priority'] as String?;
    if (rawPriority == EventPriority.critical.name) {
      priority = EventPriority.critical;
    } else if (rawPriority == null) {
      // Back-compat: entries persisted before priority existed.
      priority = SocketEventQueue.criticalEvents.contains(event)
          ? EventPriority.critical
          : EventPriority.bestEffort;
    }
    return QueuedEvent(
      id: json['id'] as String,
      event: event,
      data: json['data'],
      createdAt: createdAt,
      requiresAck: json['requiresAck'] as bool? ?? false,
      attempts: json['attempts'] as int? ?? 0,
      idempotencyKey: json['idempotencyKey'] as String?,
      priority: priority,
    );
  }
}

/// Persistent event queue that survives disconnections and app restarts.
///
/// Responsibilities:
/// - Queue outgoing events when socket is disconnected
/// - Persist queue to SharedPreferences so events survive app restarts
/// - Flush queue when connection is restored (critical-first ordering)
/// - Deduplicate events (e.g., only keep latest location update)
/// - Expire stale events automatically (tiered: 2h critical, 5m best-effort)
/// - Cap persisted queue at 100 events (oldest best-effort evicted first)
///
/// Events are classified:
/// - **Critical**: ride:accept, cancel intents, payment intents,
///   go online/offline, join/leave room, track driver — these MUST be
///   delivered, carry idempotency keys, and survive kill for 2h.
/// - **Best effort**: location updates — only keep the latest one, 5-min TTL.
class SocketEventQueue {
  static const String _storageKey = 'socket_event_queue';

  /// Max persisted events. Oldest best-effort evicted first so a location
  /// storm can never push out a critical user intent.
  static const int maxPersistedEvents = 100;

  /// Critical events that must be delivered (queued, ack-guarded, retried).
  /// Includes the ride:accept + payment passthrough events observed in
  /// SocketService so those user intents are never fire-and-forget.
  static const Set<String> criticalEvents = {
    'user:goOnline',
    'driver:goOnline',
    'driver:goOffline',
    'join:room',
    'leave:room',
    'ride:trackDriver',
    'ride:stopTracking',
    'ride:accept',
    'ride:cancel',
    'payment:excessCashRequested',
    'payment:selected',
    'payment_selected',
  };

  /// Events where only the latest value matters (deduplicated, short TTL).
  static const Set<String> deduplicatedEvents = {'driver:locationUpdate'};

  final List<QueuedEvent> _queue = [];
  bool _isPersisting = false;

  /// Stream controller to notify when queue state changes
  final StreamController<int> _queueSizeController =
      StreamController<int>.broadcast();

  /// Stream of queue size changes
  Stream<int> get queueSize => _queueSizeController.stream;

  /// Current number of pending events
  int get pendingCount => _queue.length;

  /// Add an event to the queue.
  ///
  /// If the event is a deduplicated type (like location updates),
  /// it replaces any existing event of the same type.
  void enqueue(String event, dynamic data, {bool requiresAck = false}) {
    // Auto-classify: critical events always require ack
    final isCritical = criticalEvents.contains(event);
    final shouldAck = requiresAck || isCritical;

    // For deduplicated events, remove any existing event of the same type
    if (deduplicatedEvents.contains(event)) {
      _queue.removeWhere((e) => e.event == event);
    }

    final now = DateTime.now();
    final queuedEvent = QueuedEvent(
      id: '${event}_${now.millisecondsSinceEpoch}',
      event: event,
      data: data,
      createdAt: now,
      requiresAck: shouldAck,
      attempts: 0,
    );

    _queue.add(queuedEvent);
    _evictOverflow();
    _notifyQueueChange();
    _persistQueue();

    debugPrint(
      '📥 [EventQueue] Queued: $event (${_queue.length} pending, ack=$shouldAck, key=${queuedEvent.idempotencyKey})',
    );
  }

  /// Enforce the persisted cap: evict oldest best-effort first, oldest
  /// overall only when the queue holds nothing but critical intents.
  void _evictOverflow() {
    while (_queue.length > maxPersistedEvents) {
      final oldestBestEffort = _queue.indexWhere((e) => !e.isCritical);
      if (oldestBestEffort != -1) {
        _queue.removeAt(oldestBestEffort);
      } else {
        _queue.removeAt(0);
      }
    }
  }

  /// Remove expired and over-retried events from the queue.
  void purgeStale() {
    final before = _queue.length;
    _queue.removeWhere((e) => e.isExpired || e.hasExceededRetries);
    final removed = before - _queue.length;

    if (removed > 0) {
      debugPrint('🗑️ [EventQueue] Purged $removed stale events');
      _notifyQueueChange();
      _persistQueue();
    }
  }

  /// Get all pending events, critical-first then FIFO within each tier.
  /// Purges stale events first.
  List<QueuedEvent> drain() {
    purgeStale();
    final indexed = _queue.asMap().entries.toList();
    indexed.sort((a, b) {
      final aCrit = a.value.isCritical ? 0 : 1;
      final bCrit = b.value.isCritical ? 0 : 1;
      if (aCrit != bCrit) return aCrit.compareTo(bCrit);
      return a.key.compareTo(b.key);
    });
    final events = indexed.map((e) => e.value).toList();
    _queue.clear();
    _notifyQueueChange();
    _persistQueue();

    debugPrint('📤 [EventQueue] Drained ${events.length} events for sending');
    return events;
  }

  /// Re-queue an event that failed to send (increments attempt counter).
  /// Attempt counts persist to disk, so a kill + reopen resumes counting
  /// instead of resetting the retry budget (no infinite storm).
  void requeue(QueuedEvent event) {
    event.attempts++;
    if (!event.hasExceededRetries && !event.isExpired) {
      _queue.add(event);
      _evictOverflow();
      _notifyQueueChange();
      _persistQueue();
      debugPrint(
        '🔄 [EventQueue] Re-queued: ${event.event} (attempt ${event.attempts}/${QueuedEvent.maxAttempts})',
      );
    } else {
      debugPrint(
        '❌ [EventQueue] Dropped: ${event.event} (expired=${event.isExpired}, retries=${event.attempts})',
      );
    }
  }

  /// Remove a specific event from the queue (e.g., after successful ack).
  void remove(String eventId) {
    _queue.removeWhere((e) => e.id == eventId);
    _notifyQueueChange();
    _persistQueue();
  }

  /// Clear the entire queue.
  void clear() {
    _queue.clear();
    _notifyQueueChange();
    _persistQueue();
    debugPrint('🧹 [EventQueue] Queue cleared');
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  /// Load persisted queue from SharedPreferences.
  Future<void> loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;

      final List<dynamic> decoded = jsonDecode(raw);
      _queue.clear();
      for (final item in decoded) {
        try {
          final event = QueuedEvent.fromJson(item as Map<String, dynamic>);
          if (!event.isExpired && !event.hasExceededRetries) {
            _queue.add(event);
          }
        } catch (e) {
          debugPrint('⚠️ [EventQueue] Skipped malformed event: $e');
        }
      }

      _notifyQueueChange();
      debugPrint('💾 [EventQueue] Loaded ${_queue.length} events from disk');
    } catch (e) {
      debugPrint('❌ [EventQueue] Failed to load from disk: $e');
    }
  }

  /// Persist queue to SharedPreferences.
  Future<void> _persistQueue() async {
    if (_isPersisting) return;
    _isPersisting = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_queue.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('❌ [EventQueue] Failed to persist: $e');
    } finally {
      _isPersisting = false;
    }
  }

  void _notifyQueueChange() {
    if (!_queueSizeController.isClosed) {
      _queueSizeController.add(_queue.length);
    }
  }

  /// Dispose of resources.
  void dispose() {
    _queueSizeController.close();
  }
}
