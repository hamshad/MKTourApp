import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import 'socket_event_queue.dart';

/// Connectivity-aware socket state, exposed alongside the legacy
/// boolean [SocketService.connectionStatus] stream (kept for back-compat).
enum SocketConnectionState { online, reconnecting, offline }

class SocketService with WidgetsBindingObserver {
  static final SocketService _instance = SocketService._internal();
  IO.Socket? _socket;
  bool _isConnected = false;
  bool _isReconnecting = false;
  Timer? _reconnectionTimer;
  Timer? _heartbeatTimer;
  Timer? _pongTimeoutTimer;
  Timer? _flushDebounceTimer;
  int _reconnectionAttempts = 0;
  // Unbounded reconnect: exponential backoff from 3s, capped at 30s, ±20% jitter.
  // The attempt counter only resets on a successful connect — never gives up.
  static const int _reconnectionDelayMs = 3000;
  static const int _maxBackoffDelayMs = 30000;
  static const int _heartbeatIntervalSeconds = 25;
  static const int _ackTimeoutSeconds = 8;
  static const int _pongTimeoutSeconds = 10;
  // Effectively unbounded client-library retries to match our own timer.
  static const int _libReconnectionAttempts = 999999;
  bool _awaitingPong = false;
  String? _currentToken; // Track current token to detect changes
  bool _isAppInBackground = false;

  /// Events protected by the server-ack guard ([_emitWithAckGuard]).
  /// ONLY intents with a server ack contract belong here. Presence / room /
  /// tracking events (goOnline, join:room, trackDriver) are idempotent
  /// broadcasts the server never acks — ack-guarding them re-queues a
  /// duplicate 8s after every successful emit (driver-goonline-storm).
  static const Set<String> ackGuardedEvents = {
    'ride:accept',
    'ride:cancel',
    'payment:excessCashRequested',
    'payment:selected',
    'payment_selected',
  };

  /// Registry of screen-registered listeners, re-attached after every
  /// re-init/connect so screens never go silently deaf when the underlying
  /// socket instance is disposed and recreated.
  final Map<String, List<Function(dynamic)>> _listenerRegistry = {};

  /// Timestamp of last disconnection — screens use this to decide if API sync needed
  DateTime? _lastDisconnectedAt;

  /// The event queue for reliable delivery
  final SocketEventQueue _eventQueue = SocketEventQueue();

  /// Whether the queue is currently being flushed (prevent concurrent flushes)
  bool _isFlushing = false;

  /// Stream controller for connection status changes
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();

  /// Set of rooms the client has joined (for rejoining after reconnection)
  final Set<String> _joinedRooms = {};

  factory SocketService() {
    return _instance;
  }

  SocketService._internal() {
    // Add lifecycle observer for iOS background/foreground handling
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('\u{1f504} [SocketService] App lifecycle state: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground
        _isAppInBackground = false;
        debugPrint(
          '\u{1f4f1} [SocketService] App resumed - checking socket connection...',
        );

        // Reconnect socket if disconnected (especially important for iOS)
        if (_socket == null || !_socket!.connected) {
          debugPrint(
            '\u{1f504} [SocketService] Socket disconnected, attempting reconnection...',
          );
          _attemptReconnection();
        }
        break;

      case AppLifecycleState.paused:
        // App went to background
        _isAppInBackground = true;
        debugPrint('\u{1f4f1} [SocketService] App paused/backgrounded');
        break;

      case AppLifecycleState.inactive:
        debugPrint('\u{1f4f1} [SocketService] App inactive');
        break;

      case AppLifecycleState.detached:
        debugPrint('\u{1f4f1} [SocketService] App detached');
        break;

      case AppLifecycleState.hidden:
        debugPrint('\u{1f4f1} [SocketService] App hidden');
        break;
    }
  }

  bool get isConnected => _isConnected;

  /// Timestamp of the last disconnection event.
  /// Screens can use this to decide whether an API sync is needed after reconnection.
  DateTime? get lastDisconnectedAt => _lastDisconnectedAt;

  /// Duration since last disconnection (null if never disconnected or currently connected without gap).
  Duration? get disconnectionGap {
    if (_lastDisconnectedAt == null) return null;
    return DateTime.now().difference(_lastDisconnectedAt!);
  }

  /// The event queue instance — exposed for monitoring (e.g., queue size stream)
  SocketEventQueue get eventQueue => _eventQueue;

  /// Stream of connection status changes
  Stream<bool> get connectionStatus => _connectionStatusController.stream;

  /// Connectivity-aware connection state (online | reconnecting | offline).
  /// The boolean [connectionStatus] stream is kept for back-compat.
  final StreamController<SocketConnectionState> _connectionStateController =
      StreamController<SocketConnectionState>.broadcast();

  /// Stream of connectivity-aware connection state changes.
  Stream<SocketConnectionState> get connectionState =>
      _connectionStateController.stream;

  void _emitState(SocketConnectionState state) {
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  Future<void> initSocket({bool forceReconnect = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    // Load any persisted queued events from disk
    await _eventQueue.loadFromDisk();

    // Check if token has changed (user switched accounts/roles)
    final tokenChanged = _currentToken != null && _currentToken != token;

    if (tokenChanged) {
      debugPrint(
        '\u{1f504} [SocketService] Token changed! Old: ${_currentToken?.substring(0, 10)}, New: ${token?.substring(0, 10)}',
      );
      debugPrint(
        '\u{1f504} [SocketService] Forcing reconnect with new credentials...',
      );
      forceReconnect = true;
    }

    // If already connected with same token and not forcing reconnect, skip
    if (_socket != null &&
        _socket!.connected &&
        !forceReconnect &&
        !tokenChanged) {
      debugPrint(
        '\u{2705} [SocketService] Socket already connected, skipping init',
      );
      // Still flush any pending queued events
      _flushQueue();
      return;
    }

    // Disconnect existing socket if forcing reconnect or token changed
    if ((_socket != null && forceReconnect) || tokenChanged) {
      debugPrint(
        '\u{26a0}\u{fe0f} [SocketService] Disposing existing socket (forceReconnect=$forceReconnect, tokenChanged=$tokenChanged)',
      );
      try {
        _socket!.dispose();
      } catch (e) {
        // Ignore error if already disposed
      }
      _socket = null;
      _joinedRooms
          .clear(); // Clear rooms when reconnecting with new credentials
    }

    // Ensure we don't have a stale disconnected socket
    if (_socket != null) {
      debugPrint(
        '\u{26a0}\u{fe0f} [SocketService] Disposing stale socket before re-init',
      );
      try {
        _socket!.dispose();
      } catch (e) {
        // Ignore error if already disposed
      }
      _socket = null;
    }

    if (token == null) {
      debugPrint(
        '\u{26a0}\u{fe0f} [SocketService] No token found, skipping connection',
      );
      debugPrint(
        '\u{26a0}\u{fe0f} [SocketService] Platform: Android=${io.Platform.isAndroid}, iOS=${io.Platform.isIOS}',
      );
      return;
    }

    // Log platform-specific info
    debugPrint(
      '\u{1f4f1} [SocketService] Platform: Android=${io.Platform.isAndroid}, iOS=${io.Platform.isIOS}',
    );
    if (io.Platform.isAndroid) {
      debugPrint(
        '\u{1f916} [SocketService] Android detected - ensuring network permissions...',
      );
    }

    // Store current token for change detection
    _currentToken = token;

    debugPrint(
      '\u{1f535} [SocketService] Connecting to ${ApiConstants.baseUrl} with token: ${token.substring(0, 10)}...',
    );

    // iOS-specific socket configuration
    final bool isIOS = io.Platform.isIOS;

    _socket = IO.io(
      ApiConstants.socketUrl,
      IO.OptionBuilder()
          .setTransports([
            'websocket',
          ]) // Websocket-only for better iOS stability
          .setTimeout(isIOS ? 30000 : 20000) // Longer timeout for iOS
          .enableForceNew()
          .enableReconnection()
          .setReconnectionAttempts(_libReconnectionAttempts)
          .setReconnectionDelay(_reconnectionDelayMs)
          .disableAutoConnect() // Disable auto connect to control when it connects
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .setAuth({'token': token})
          .build(),
    );

    debugPrint(
      '\u{1f50c} [SocketService] Socket instance created, initiating connection...',
    );
    debugPrint(
      '\u{1f50c} [SocketService] Platform: ${defaultTargetPlatform.toString()}',
    );
    _socket!.connect();
    debugPrint(
      '\u{1f50c} [SocketService] Connect() called, waiting for onConnect callback...',
    );

    _socket!.onConnect((_) {
      _isConnected = true;
      _isReconnecting = false;
      _reconnectionAttempts = 0;
      _reconnectionTimer?.cancel();
      _emitState(SocketConnectionState.online);

      if (!_connectionStatusController.isClosed) {
        _connectionStatusController.add(true);
      }

      debugPrint(
        '\u{1f7e2} [SocketService] Connected to ${ApiConstants.baseUrl}',
      );
      debugPrint(
        '\u{1f7e2} [SocketService] Platform: iOS=${io.Platform.isIOS}, Android=${io.Platform.isAndroid}',
      );
      debugPrint(
        '\u{1f7e2} [SocketService] Transport: ${_socket?.io.engine?.transport?.name ?? "unknown"}',
      );

      // Rejoin all rooms after reconnection
      _rejoinRooms();

      // Re-attach every screen-registered listener (socket was recreated)
      _reattachListeners();

      // Flush any queued events that accumulated while disconnected
      _flushQueue();

      // Start heartbeat monitoring
      _startHeartbeat();
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      _lastDisconnectedAt = DateTime.now();
      _heartbeatTimer?.cancel();
      _pongTimeoutTimer?.cancel();
      _awaitingPong = false;
      _emitState(SocketConnectionState.reconnecting);

      if (!_connectionStatusController.isClosed) {
        _connectionStatusController.add(false);
      }

      debugPrint('\u{1f534} [SocketService] Disconnected');

      // Start reconnection attempts
      _attemptReconnection();
    });

    _socket!.onConnectError((data) {
      _isConnected = false;
      _emitState(SocketConnectionState.reconnecting);
      debugPrint('\u{1f534} [SocketService] Connection Error: $data');

      // Start reconnection attempts
      _attemptReconnection();
    });

    _socket!.onError((data) {
      debugPrint('\u{1f534} [SocketService] Error: $data');
    });

    _socket!.on('connect_timeout', (data) {
      debugPrint('\u{1f534} [SocketService] Connection Timeout: $data');
      _attemptReconnection();
    });

    // Listen for driver status confirmation
    _socket!.on('driver:status', (data) {
      debugPrint('\u{1f4e9} [SocketService] Received driver:status: $data');
    });

    // Listen for location update - matching the event name 'driver:locationChanged' seen in logs
    _socket!.on('driver:locationChanged', (data) {
      debugPrint(
        '\u{1f4e9} [SocketService] Received driver:locationChanged: $data',
      );
    });

    // Listen for location update confirmation
    _socket!.on('driver:locationUpdated', (data) {
      debugPrint(
        '\u{1f4e9} [SocketService] Received driver:locationUpdated: $data',
      );
    });

    // Pong response for the real ping/pong heartbeat (_startHeartbeat).
    _socket!.on('pong', (_) {
      _awaitingPong = false;
      _pongTimeoutTimer?.cancel();
    });

    // Listen for room join confirmation
    _socket!.on('room:joined', (data) {
      debugPrint('\u{1f3e0} [SocketService] Room joined: $data');
    });

    // Wildcard listener to debug ALL incoming events
    _socket!.onAny((event, data) {
      debugPrint(
        '\u{1f4e8} [SocketService] INCOMING EVENT: $event, Data: $data',
      );
    });
  }

  // ── Heartbeat ──────────────────────────────────────────────────────────────

  /// Start a real ping/pong heartbeat to detect silent disconnections.
  /// Every [_heartbeatIntervalSeconds] we `emit('ping')` and expect a `pong`
  /// within [_pongTimeoutSeconds]. A missed app-level pong is advisory only
  /// (no server pong contract — never force a reconnect on it); a null
  /// transport or failed ping emit still forces one. The `pong` handler is
  /// registered in [initSocket].
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _awaitingPong = false;
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: _heartbeatIntervalSeconds),
      (_) {
        if (_socket != null && _socket!.connected) {
          try {
            final transport = _socket?.io.engine?.transport;
            if (transport == null) {
              _forceReconnect('transport is null');
              return;
            }
          } catch (_) {
            // Transport check failed - fall through to the ping probe,
            // whose missed pong will force the reconnect.
          }
          _awaitingPong = true;
          try {
            _socket!.emit('ping', {
              'ts': DateTime.now().millisecondsSinceEpoch,
            });
          } catch (_) {
            _forceReconnect('ping emit failed');
            return;
          }
          _pongTimeoutTimer?.cancel();
          _pongTimeoutTimer = Timer(
            const Duration(seconds: _pongTimeoutSeconds),
            () {
              if (_awaitingPong) {
                // Advisory only: the backend has no custom 'pong' handler
                // contract, so a missed app-level pong must NOT kill a
                // healthy socket (that self-inflicted reconnect re-flushes
                // the queue + replays goOnline every heartbeat cycle).
                // Real death is still caught by engine.io keepalive via
                // onDisconnect. Just clear the flag and log.
                _awaitingPong = false;
                debugPrint(
                  '[SocketService] Heartbeat: no app-level pong (advisory, keeping connection)',
                );
              }
            },
          );
        }
      },
    );
  }

  /// Mark the connection dead and kick the (unbounded) reconnection loop.
  void _forceReconnect(String reason) {
    debugPrint('[SocketService] Heartbeat: $reason, forcing reconnect');
    _isConnected = false;
    _lastDisconnectedAt = DateTime.now();
    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.add(false);
    }
    _emitState(SocketConnectionState.reconnecting);
    try {
      _socket?.disconnect();
    } catch (_) {
      // Socket already dead - the reconnection timer handles the rest.
    }
    _attemptReconnection();
  }

  // ── Reliable Emit ────────────────────────────────────────────────────────

  /// Emit an event reliably. If the socket is connected, emit immediately.
  /// If disconnected, queue the event for delivery when connection is restored.
  ///
  /// Use this for ALL critical events (ride status, go online/offline, rooms).
  /// For best-effort events (location), this still queues but deduplicates.
  void emitReliable(String event, dynamic data) {
    if (_socket != null && _socket!.connected) {
      if (ackGuardedEvents.contains(event)) {
        _emitWithAckGuard(event, data);
      } else {
        _socket!.emit(event, data);
      }
      debugPrint('[SocketService] Emitted: $event, Data: $data');
    } else {
      // Queue for later delivery
      _eventQueue.enqueue(event, data);
      debugPrint(
        '[SocketService] Queued (offline): $event (${_eventQueue.pendingCount} pending)',
      );
    }
  }

  /// Emit a critical event once with a server-ack guard: if no ack arrives
  /// within [_ackTimeoutSeconds], the event is enqueued for retry on the
  /// next flush. Idempotency keys (see [SocketEventQueue]) make a
  /// send-but-no-ack duplicate safe to replay.
  void _emitWithAckGuard(String event, dynamic data) {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      _eventQueue.enqueue(event, data);
      return;
    }
    var settled = false;
    Timer? ackTimer;
    void requeueOnce() {
      if (settled) return;
      settled = true;
      ackTimer?.cancel();
      debugPrint('[SocketService] Ack timeout, re-queuing: $event');
      _eventQueue.enqueue(event, data);
    }

    ackTimer = Timer(const Duration(seconds: _ackTimeoutSeconds), requeueOnce);
    try {
      socket.emitWithAck(
        event,
        data,
        ack: (_) {
          if (settled) return;
          settled = true;
          ackTimer?.cancel();
        },
      );
    } catch (_) {
      requeueOnce();
    }
  }

  /// Flush all queued events. Called automatically on reconnection.
  /// Uses a debounce to avoid multiple flushes firing simultaneously.
  void _flushQueue() {
    _flushDebounceTimer?.cancel();
    _flushDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _doFlushQueue();
    });
  }

  Future<void> _doFlushQueue() async {
    if (_isFlushing) return;
    if (!_isConnected || _socket == null || !_socket!.connected) return;
    if (_eventQueue.pendingCount == 0) return;

    _isFlushing = true;
    debugPrint(
      '\u{1f4e4} [SocketService] Flushing ${_eventQueue.pendingCount} queued events...',
    );

    final events = _eventQueue.drain();
    for (final event in events) {
      if (_socket != null && _socket!.connected) {
        if (ackGuardedEvents.contains(event.event)) {
          _emitWithAckGuard(event.event, event.data);
        } else {
          _socket!.emit(event.event, event.data);
        }
        debugPrint(
          '\u{1f4e4} [SocketService] Flushed: ${event.event} (attempt ${event.attempts + 1})',
        );
        // Small delay between emits to avoid overwhelming the server
        await Future.delayed(const Duration(milliseconds: 50));
      } else {
        // Connection lost mid-flush — re-queue remaining
        debugPrint(
          '\u{26a0}\u{fe0f} [SocketService] Connection lost mid-flush, re-queuing: ${event.event}',
        );
        _eventQueue.requeue(event);
      }
    }

    _isFlushing = false;
    debugPrint('\u{2705} [SocketService] Queue flush complete');
  }

  // ── Reconnection ──────────────────────────────────────────────────────────

  /// Attempt to reconnect forever with capped exponential backoff plus
  /// jitter. The counter resets only on a successful connect - there is no
  /// give-up path: a killed app on poor network keeps retrying.
  void _attemptReconnection() {
    if (_isReconnecting || _isConnected) return;

    _isReconnecting = true;
    _reconnectionAttempts++;
    _emitState(SocketConnectionState.reconnecting);

    // Exponential backoff from 3s, capped at 30s, with +/-20% jitter.
    // Shift is clamped so the counter can grow unboundedly without overflow.
    final shift = (_reconnectionAttempts - 1).clamp(0, 4);
    var delayMs = _reconnectionDelayMs * (1 << shift);
    if (delayMs > _maxBackoffDelayMs) delayMs = _maxBackoffDelayMs;
    final jitter = 0.8 + math.Random().nextDouble() * 0.4;
    delayMs = (delayMs * jitter).round();
    debugPrint(
      '[SocketService] Reconnect attempt #$_reconnectionAttempts in ${delayMs}ms...',
    );

    _reconnectionTimer?.cancel();
    _reconnectionTimer = Timer(Duration(milliseconds: delayMs), () async {
      if (!_isConnected) {
        debugPrint('[SocketService] Reconnecting...');
        try {
          _socket?.connect();
        } catch (_) {
          // connect() threw - schedule the next attempt below.
        }
        // If connect did not succeed, onConnectError/onDisconnect will fire
        // and re-arm this loop; if neither fires, re-arm directly so a
        // silently swallowed failure still retries.
        Future.delayed(const Duration(seconds: 5), () {
          _isReconnecting = false;
          if (!_isConnected) _attemptReconnection();
        });
        return;
      }
      _isReconnecting = false;
    });
  }

  /// Rejoin all rooms after reconnection
  void _rejoinRooms() {
    if (_joinedRooms.isEmpty) return;

    debugPrint(
      '\u{1f504} [SocketService] Rejoining ${_joinedRooms.length} rooms...',
    );
    for (final room in _joinedRooms) {
      // Use direct emit here (not emitReliable) since we are already connected
      emit('join:room', {'room': room});
      debugPrint('\u{1f504} [SocketService] Rejoined room: $room');
    }
  }

  // ── Room Management ────────────────────────────────────────────────────────

  /// Join a specific room (e.g., driver:${driverId} to receive location updates)
  void joinRoom(String roomName) {
    if (roomName.isEmpty) {
      debugPrint(
        '\u{26a0}\u{fe0f} [SocketService] Cannot join room: empty room name',
      );
      return;
    }

    _joinedRooms.add(roomName);
    emitReliable('join:room', {'room': roomName});
    debugPrint('\u{1f3e0} [SocketService] Joining room: $roomName');
  }

  /// Leave a specific room
  void leaveRoom(String roomName) {
    if (roomName.isEmpty) return;

    _joinedRooms.remove(roomName);
    emitReliable('leave:room', {'room': roomName});
    debugPrint('\u{1f6aa} [SocketService] Left room: $roomName');
  }

  /// Join the driver's location room to receive real-time location updates
  void joinDriverRoom(String driverId) {
    if (driverId.isEmpty) {
      debugPrint(
        '\u{26a0}\u{fe0f} [SocketService] Cannot join driver room: empty driverId',
      );
      return;
    }

    final roomName = 'driver:$driverId';
    joinRoom(roomName);
    debugPrint(
      '\u{1f697} [SocketService] Joined driver location room: $roomName',
    );
  }

  /// Leave the driver's location room
  void leaveDriverRoom(String driverId) {
    if (driverId.isEmpty) return;

    final roomName = 'driver:$driverId';
    leaveRoom(roomName);
    debugPrint(
      '\u{1f697} [SocketService] Left driver location room: $roomName',
    );
  }

  // ── Convenience Emitters ────────────────────────────────────────────────────
  // All now use emitReliable for guaranteed delivery.

  /// Emit user:goOnline to register user for receiving ride updates
  void emitUserOnline(String userId) {
    if (userId.isEmpty) {
      debugPrint(
        '\u{26a0}\u{fe0f} [SocketService] Cannot emit user:goOnline: empty userId',
      );
      return;
    }
    emitReliable('user:goOnline', {'userId': userId});
    debugPrint('\u{1f464} [SocketService] User online: $userId');
  }

  /// Emit driver:goOnline to register driver for receiving ride requests
  void emitDriverOnline(String driverId) {
    if (driverId.isEmpty) {
      debugPrint(
        '\u{26a0}\u{fe0f} [SocketService] Cannot emit driver:goOnline: empty driverId',
      );
      return;
    }
    emitReliable('driver:goOnline', {'driverId': driverId});
    debugPrint('\u{1f697} [SocketService] Driver online: $driverId');
  }

  /// Emit driver:goOffline when driver goes offline
  void emitDriverOffline(String driverId) {
    if (driverId.isEmpty) return;
    emitReliable('driver:goOffline', {'driverId': driverId});
    debugPrint('\u{1f697} [SocketService] Driver offline: $driverId');
  }

  /// Emit driver:locationUpdate for real-time location tracking.
  /// This is a best-effort event — only the latest location matters,
  /// so the queue deduplicates older location updates automatically.
  void emitDriverLocationUpdate({
    required String driverId,
    required double latitude,
    required double longitude,
  }) {
    if (driverId.isEmpty) return;
    emitReliable('driver:locationUpdate', {
      'driverId': driverId,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  /// Start tracking driver location in real-time
  /// Call this when passenger receives ride:accepted event
  void startTrackingDriver(String driverId) {
    if (driverId.isEmpty) {
      debugPrint(
        '\u{26a0}\u{fe0f} [SocketService] Cannot start tracking: empty driverId',
      );
      return;
    }
    emitReliable('ride:trackDriver', {'driverId': driverId});
    debugPrint('\u{1f3af} [SocketService] Started tracking driver: $driverId');
  }

  /// Stop tracking driver location
  /// Call this when ride starts (after OTP verification) or if ride is cancelled
  void stopTrackingDriver(String driverId) {
    if (driverId.isEmpty) {
      debugPrint(
        '\u{26a0}\u{fe0f} [SocketService] Cannot stop tracking: empty driverId',
      );
      return;
    }
    emitReliable('ride:stopTracking', {'driverId': driverId});
    debugPrint('\u{1f6d1} [SocketService] Stopped tracking driver: $driverId');
  }

  /// Emit ride:accept to accept a ride request
  void emitRideAccept(String rideId) {
    if (rideId.isEmpty) return;
    emitReliable('ride:accept', {'rideId': rideId});
    debugPrint('🔗 [SocketService] Ride accepted: $rideId');
  }

  // ── Ride-flow event subscriptions (new backend flow) ───────────────────────
  // Thin passthroughs over on()/off() so ride UI observes at_stop, resume,
  // reassign, and payment states without scattering raw event strings.
  // No internal subscriptions are created here — the UI owns its handlers.
  // Uses the existing on/off + emitReliable patterns only.

  /// Stop arrival: backend sets status to `at_stop` with `currentStopIndex`
  /// + `stops[]` (see `POST /rides/:id/stop/arrive`).
  void onStopUpdate(void Function(dynamic) handler) {
    on('ride:stopArrived', handler);
    on('ride:at_stop', handler);
  }

  void offStopUpdate() {
    off('ride:stopArrived');
    off('ride:at_stop');
  }

  /// Trip resume: backend flips status back to `in_progress` with
  /// `totalWaitMinutes`/`totalWaitFee` (see `POST /rides/:id/stop/resume`).
  void onTripResumed(void Function(dynamic) handler) {
    on('ride:tripResumed', handler);
    on('ride:resumed', handler);
  }

  void offTripResumed() {
    off('ride:tripResumed');
    off('ride:resumed');
  }

  /// Driver reassign: backend emits `ride_driver_reassigning` with the ride
  /// back in `requested` status + `reassigned: true` flag.
  void onDriverReassigning(void Function(dynamic) handler) {
    on('ride:driverReassigning', handler);
    on('ride_driver_reassigning', handler);
  }

  void offDriverReassigning() {
    off('ride:driverReassigning');
    off('ride_driver_reassigning');
  }

  /// Payment method selected by the passenger (`paymentMethod` + status).
  void onPaymentSelected(void Function(dynamic) handler) {
    on('payment:selected', handler);
    on('payment_selected', handler);
  }

  void offPaymentSelected() {
    off('payment:selected');
    off('payment_selected');
  }

  /// Cash collection confirmed. Passthrough only — `ride_complete_screen`
  /// already owns the `payment:cashCollected` subscription; nothing is
  /// subscribed internally here so the event is never double-handled.
  void onCashCollected(void Function(dynamic) handler) {
    on('payment:cashCollected', handler);
  }

  void offCashCollected() {
    off('payment:cashCollected');
  }

  /// Excess owed after trip end (payment-flow.md §1 Outcome B, §4).
  /// Payload: {rideId, excessAmount, paymentUrl?, clientSecret?, isReminder}.
  void onPaymentBalanceDue(void Function(dynamic) handler) {
    on('payment:balanceDue', handler);
  }

  void offPaymentBalanceDue() {
    off('payment:balanceDue');
  }

  /// Payment fully settled (payment-flow.md §1 Outcome A, §4).
  /// Payload: {rideId, amount, message}.
  void onPaymentSucceeded(void Function(dynamic) handler) {
    on('payment:succeeded', handler);
  }

  void offPaymentSucceeded() {
    off('payment:succeeded');
  }

  /// Payment failure with retry hint (payment-flow.md §4).
  void onPaymentFailed(void Function(dynamic) handler) {
    on('payment:failed', handler);
  }

  void offPaymentFailed() {
    off('payment:failed');
  }

  /// Rider requested to pay excess balance in cash (INTEGRATION-GUIDE.md §2A).
  /// Driver shows "Collect Cash £X" modal. Payload: {rideId, excessAmount}.
  void onExcessCashRequested(void Function(dynamic) handler) {
    on('payment:excessCashRequested', handler);
  }

  void offExcessCashRequested() {
    off('payment:excessCashRequested');
  }

  /// Rider switched back to online payment; driver auto-closes the cash
  /// confirmation modal (INTEGRATION-GUIDE.md §2C).
  void onExcessCashCancelled(void Function(dynamic) handler) {
    on('payment:excessCashCancelled', handler);
  }

  void offExcessCashCancelled() {
    off('payment:excessCashCancelled');
  }

  /// Driver confirmed cash receipt (Phase 14 INTEGRATION-GUIDE.md §2).
  /// Payload: {rideId, excessAmount, message}.
  void onExcessCashConfirmed(void Function(dynamic) handler) {
    on('payment:excessCashConfirmed', handler);
  }

  void offExcessCashConfirmed() {
    off('payment:excessCashConfirmed');
  }

  // ── Back-to-back dispatch passthroughs (driver-multirequest.md §3) ────────
  // Thin on()/off() pairs only — zero internal subscriptions, so reconnects
  // re-attach via the listener registry with no double-handling. Screens that
  // subscribe raw today (home_screen, ride_assigned_screen on 'ride:accepted')
  // are untouched; these named helpers are additive.
  //
  // No existing named 'ride:accepted' passthrough exists (verified: only raw
  // string subscriptions), so onRideAcceptedEvent/offRideAcceptedEvent is new.

  /// Incoming B2B request near the driver's dropoff vicinity (§3.1).
  /// Payload carries `isBackToBack: true` when queueable behind active trip.
  void onB2bRequest(void Function(dynamic) handler) {
    on('ride:newRequest', handler);
  }

  void offB2bRequest() {
    off('ride:newRequest');
  }

  /// Queued trip promoted to active when trip A completes (§3.1).
  /// Payload: full next-ride details + pickup location (see NextTripActivation).
  void onNextTripActivated(void Function(dynamic) handler) {
    on('ride:nextTripActivated', handler);
  }

  void offNextTripActivated() {
    off('ride:nextTripActivated');
  }

  /// Queued ride cancelled by rider B while driver is on trip A (§3.1).
  /// Payload: {rideId, cancelledBy}.
  void onQueuedCancelled(void Function(dynamic) handler) {
    on('ride:cancelled', handler);
  }

  void offQueuedCancelled() {
    off('ride:cancelled');
  }

  /// Driver finished trip A and heads to rider B (§3.2).
  /// Payload: {rideId, status, message}.
  void onDriverEnRoute(void Function(dynamic) handler) {
    on('ride:driverEnRoute', handler);
  }

  void offDriverEnRoute() {
    off('ride:driverEnRoute');
  }

  /// Real-time ETA updates (§3.2).
  /// Payload: {rideId, duration, distance}.
  void onEtaUpdate(void Function(dynamic) handler) {
    on('ride:etaUpdate', handler);
  }

  void offEtaUpdate() {
    off('ride:etaUpdate');
  }

  /// Driver-accepted assignment (§3.2, full driver profile + vehicle).
  /// Additive helper only — existing raw 'ride:accepted' subscribers keep
  /// working; nothing here subscribes internally.
  void onRideAcceptedEvent(void Function(dynamic) handler) {
    on('ride:accepted', handler);
  }

  void offRideAcceptedEvent() {
    off('ride:accepted');
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void disconnect() {
    _reconnectionTimer?.cancel();
    _heartbeatTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _awaitingPong = false;
    _flushDebounceTimer?.cancel();
    _joinedRooms.clear();
    _listenerRegistry.clear();
    _currentToken = null; // Clear token to force fresh connection next time
    _isReconnecting = false;
    _emitState(SocketConnectionState.offline);

    if (_socket != null) {
      _socket!.disconnect();
      _socket = null;
      _isConnected = false;
      debugPrint('\u{1f534} [SocketService] Disconnected manually');
    }
  }

  /// Dispose of resources
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectionTimer?.cancel();
    _heartbeatTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _flushDebounceTimer?.cancel();
    _connectionStatusController.close();
    _connectionStateController.close();
    _eventQueue.dispose();
    disconnect();
  }

  // ── Raw Emit/Listen (backwards-compatible) ─────────────────────────────────

  /// Raw emit — sends immediately if connected, drops silently if not.
  /// **Prefer [emitReliable] for all critical events.**
  /// This is kept for backwards compatibility and for internal use (e.g., room rejoining).
  void emit(String event, dynamic data) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit(event, data);
      debugPrint('\u{1f4e4} [SocketService] Emitted: $event, Data: $data');
    } else {
      debugPrint(
        '\u{26a0}\u{fe0f} [SocketService] Cannot emit $event, socket not connected',
      );
    }
  }

  /// Register [handler] for [event] and record it in the listener
  /// registry so it survives socket re-init via [_reattachListeners].
  /// Registering while the socket is null no longer silently deafens the
  /// caller - the handler is still recorded and attached on next connect.
  /// Identical closures are deduped so reconnects never double-fire.
  void on(String event, Function(dynamic) handler) {
    final handlers = _listenerRegistry.putIfAbsent(event, () => []);
    if (!handlers.contains(handler)) {
      handlers.add(handler);
    }
    if (_socket != null) {
      _socket!.on(event, handler);
      debugPrint(
        '\u{1f442} [SocketService] Listening for: $event (iOS=${io.Platform.isIOS}, Connected=${_socket!.connected})',
      );
    } else {
      debugPrint(
        '\u{26a0}\u{fe0f} [SocketService] Cannot listen for $event, socket is null',
      );
    }
  }

  /// Remove listener(s) for [event]. With [handler], only that exact
  /// closure is removed (pass the same instance given to [on]); without it,
  /// ALL handlers for the event are removed. Prefer the scoped form —
  /// screens share the singleton socket, and a global off in one screen's
  /// dispose/re-register silently deafens other mounted screens (e.g. an
  /// open settlement sheet losing `payment:succeeded` on home reconnect).
  void off(String event, [Function(dynamic)? handler]) {
    if (handler != null) {
      _listenerRegistry[event]?.remove(handler);
      if (_listenerRegistry[event]?.isEmpty ?? false) {
        _listenerRegistry.remove(event);
      }
      _socket?.off(event, handler);
      debugPrint('[SocketService] Removed scoped listener for: $event');
    } else {
      // Bare off(event) keeps its legacy global behavior, but that deafens
      // sibling screens sharing this singleton - name the caller so the
      // offender is visible in logs and migrate it to off(event, handler).
      _listenerRegistry.remove(event);
      _socket?.off(event);
      final caller = _offCaller();
      debugPrint(
        '[SocketService] WARNING: global off($event) removed ALL handlers. '
        'Caller: $caller. Prefer off(event, handler).',
      );
    }
  }

  /// Re-register every recorded listener on the current socket. Called after
  /// each re-init/connect because disposing the socket wipes its handlers.
  void _reattachListeners() {
    final socket = _socket;
    if (socket == null) return;
    var count = 0;
    _listenerRegistry.forEach((event, handlers) {
      for (final handler in List<Function(dynamic)>.from(handlers)) {
        try {
          socket.off(event, handler);
        } catch (_) {
          // Handler was never attached - attach below regardless.
        }
        socket.on(event, handler);
        count++;
      }
    });
    if (count > 0) {
      debugPrint('[SocketService] Re-attached $count registered listeners');
    }
  }

  /// Best-effort caller identification for the bare-off warning: first
  /// stack frame outside this service file.
  String _offCaller() {
    try {
      final lines = StackTrace.current.toString().split('\n');
      for (final line in lines) {
        if (!line.contains('socket_service.dart') &&
            !line.contains('_offCaller') &&
            line.trim().isNotEmpty) {
          return line.trim();
        }
      }
    } catch (_) {
      // Fall through to unknown.
    }
    return 'unknown';
  }

  /// Check if a handler is registered for an event
  bool hasListeners(String event) {
    return _socket?.hasListeners(event) ?? false;
  }
}
