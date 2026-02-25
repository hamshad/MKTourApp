import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a single queued socket event that needs to be sent/retried.
class QueuedEvent {
  final String id;
  final String event;
  final dynamic data;
  final DateTime createdAt;
  final bool requiresAck;
  int attempts;
  static const int maxAttempts = 5;

  QueuedEvent({
    required this.id,
    required this.event,
    required this.data,
    required this.createdAt,
    this.requiresAck = false,
    this.attempts = 0,
  });

  bool get isExpired {
    // Events older than 5 minutes are considered stale
    return DateTime.now().difference(createdAt).inMinutes > 5;
  }

  bool get hasExceededRetries => attempts >= maxAttempts;

  Map<String, dynamic> toJson() => {
    'id': id,
    'event': event,
    'data': data,
    'createdAt': createdAt.toIso8601String(),
    'requiresAck': requiresAck,
    'attempts': attempts,
  };

  factory QueuedEvent.fromJson(Map<String, dynamic> json) => QueuedEvent(
    id: json['id'] as String,
    event: json['event'] as String,
    data: json['data'],
    createdAt: DateTime.parse(json['createdAt'] as String),
    requiresAck: json['requiresAck'] as bool? ?? false,
    attempts: json['attempts'] as int? ?? 0,
  );
}

/// Persistent event queue that survives disconnections and app restarts.
///
/// Responsibilities:
/// - Queue outgoing events when socket is disconnected
/// - Persist queue to SharedPreferences so events survive app restarts
/// - Flush queue when connection is restored
/// - Deduplicate events (e.g., only keep latest location update)
/// - Expire stale events automatically
///
/// Events are classified:
/// - **Critical**: ride status changes, go online/offline, join room — these MUST be delivered
/// - **Best effort**: location updates — only keep the latest one, discard older ones
class SocketEventQueue {
  static const String _storageKey = 'socket_event_queue';

  /// Critical events that must be delivered (queued and retried)
  static const Set<String> criticalEvents = {
    'user:goOnline',
    'driver:goOnline',
    'driver:goOffline',
    'join:room',
    'leave:room',
    'ride:trackDriver',
    'ride:stopTracking',
  };

  /// Events where only the latest value matters (deduplicated)
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

    final queuedEvent = QueuedEvent(
      id: '${event}_${DateTime.now().millisecondsSinceEpoch}',
      event: event,
      data: data,
      createdAt: DateTime.now(),
      requiresAck: shouldAck,
      attempts: 0,
    );

    _queue.add(queuedEvent);
    _notifyQueueChange();
    _persistQueue();

    debugPrint(
      '📥 [EventQueue] Queued: $event (${_queue.length} pending, ack=$shouldAck)',
    );
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

  /// Get all pending events (ordered by creation time).
  /// Purges stale events first.
  List<QueuedEvent> drain() {
    purgeStale();
    final events = List<QueuedEvent>.from(_queue);
    _queue.clear();
    _notifyQueueChange();
    _persistQueue();

    debugPrint('📤 [EventQueue] Drained ${events.length} events for sending');
    return events;
  }

  /// Re-queue an event that failed to send (increments attempt counter).
  void requeue(QueuedEvent event) {
    event.attempts++;
    if (!event.hasExceededRetries && !event.isExpired) {
      _queue.add(event);
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
