import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import 'socket_event_queue.dart';

class SocketService with WidgetsBindingObserver {
  static final SocketService _instance = SocketService._internal();
  IO.Socket? _socket;
  bool _isConnected = false;
  bool _isReconnecting = false;
  Timer? _reconnectionTimer;
  Timer? _heartbeatTimer;
  Timer? _flushDebounceTimer;
  int _reconnectionAttempts = 0;
  static const int _maxReconnectionAttempts = 10;
  static const int _reconnectionDelayMs = 3000;
  static const int _heartbeatIntervalSeconds = 25;
  String? _currentToken; // Track current token to detect changes
  bool _isAppInBackground = false;

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
          .setReconnectionAttempts(_maxReconnectionAttempts)
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

      // Flush any queued events that accumulated while disconnected
      _flushQueue();

      // Start heartbeat monitoring
      _startHeartbeat();
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      _lastDisconnectedAt = DateTime.now();
      _heartbeatTimer?.cancel();

      if (!_connectionStatusController.isClosed) {
        _connectionStatusController.add(false);
      }

      debugPrint('\u{1f534} [SocketService] Disconnected');

      // Start reconnection attempts
      _attemptReconnection();
    });

    _socket!.onConnectError((data) {
      _isConnected = false;
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

  /// Start a periodic heartbeat ping to detect silent disconnections.
  /// If the socket is silently dead (no pong), we force a reconnection.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: _heartbeatIntervalSeconds),
      (_) {
        if (_socket != null && _socket!.connected) {
          // Socket.IO has built-in ping/pong, but we verify connectivity
          // by checking the socket's connected state. If the engine is
          // disconnected but the flag wasn't updated, force reconnect.
          try {
            final transport = _socket?.io.engine?.transport;
            if (transport == null) {
              debugPrint(
                '\u{1f49b} [SocketService] Heartbeat: transport is null, forcing reconnect',
              );
              _isConnected = false;
              _lastDisconnectedAt = DateTime.now();
              if (!_connectionStatusController.isClosed) {
                _connectionStatusController.add(false);
              }
              _attemptReconnection();
            }
          } catch (_) {
            // Transport check failed — likely disconnected
          }
        }
      },
    );
  }

  // ── Reliable Emit ────────────────────────────────────────────────────────

  /// Emit an event reliably. If the socket is connected, emit immediately.
  /// If disconnected, queue the event for delivery when connection is restored.
  ///
  /// Use this for ALL critical events (ride status, go online/offline, rooms).
  /// For best-effort events (location), this still queues but deduplicates.
  void emitReliable(String event, dynamic data) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit(event, data);
      debugPrint('\u{1f4e4} [SocketService] Emitted: $event, Data: $data');
    } else {
      // Queue for later delivery
      _eventQueue.enqueue(event, data);
      debugPrint(
        '\u{1f4e5} [SocketService] Queued (offline): $event (${_eventQueue.pendingCount} pending)',
      );
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
        _socket!.emit(event.event, event.data);
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

  /// Attempt to reconnect with exponential backoff
  void _attemptReconnection() {
    if (_isReconnecting || _isConnected) return;

    _isReconnecting = true;
    _reconnectionAttempts++;

    if (_reconnectionAttempts > _maxReconnectionAttempts) {
      debugPrint('\u{1f534} [SocketService] Max reconnection attempts reached');
      _isReconnecting = false;
      return;
    }

    // Exponential backoff: delay increases with each attempt
    final delay = _reconnectionDelayMs * _reconnectionAttempts;
    debugPrint(
      '\u{1f504} [SocketService] Attempting reconnection #$_reconnectionAttempts in ${delay}ms...',
    );

    _reconnectionTimer?.cancel();
    _reconnectionTimer = Timer(Duration(milliseconds: delay), () async {
      if (!_isConnected) {
        debugPrint('\u{1f504} [SocketService] Reconnecting...');
        _socket?.connect();
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

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void disconnect() {
    _reconnectionTimer?.cancel();
    _heartbeatTimer?.cancel();
    _flushDebounceTimer?.cancel();
    _joinedRooms.clear();
    _currentToken = null; // Clear token to force fresh connection next time

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
    _flushDebounceTimer?.cancel();
    _connectionStatusController.close();
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

  void on(String event, Function(dynamic) handler) {
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

  void off(String event) {
    if (_socket != null) {
      _socket!.off(event);
      debugPrint('\u{1f507} [SocketService] Stopped listening for: $event');
    }
  }

  /// Check if a handler is registered for an event
  bool hasListeners(String event) {
    return _socket?.hasListeners(event) ?? false;
  }
}
