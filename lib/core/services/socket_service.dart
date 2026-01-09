import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  IO.Socket? _socket;
  bool _isConnected = false;
  bool _isReconnecting = false;
  Timer? _reconnectionTimer;
  int _reconnectionAttempts = 0;
  static const int _maxReconnectionAttempts = 10;
  static const int _reconnectionDelayMs = 3000;

  /// Stream controller for connection status changes
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();

  /// Set of rooms the client has joined (for rejoining after reconnection)
  final Set<String> _joinedRooms = {};

  factory SocketService() {
    return _instance;
  }

  SocketService._internal();

  bool get isConnected => _isConnected;

  /// Stream of connection status changes
  Stream<bool> get connectionStatus => _connectionStatusController.stream;

  Future<void> initSocket() async {
    if (_socket != null && _socket!.connected) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    if (token == null) {
      debugPrint('⚠️ [SocketService] No token found, skipping connection');
      return;
    }

    debugPrint(
      '🔵 [SocketService] Connecting to ${ApiConstants.baseUrl} with token: ${token.substring(0, 10)}...',
    );

    _socket = IO.io(
      ApiConstants.socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect() // Disable auto connect to control when it connects
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      _isConnected = true;
      _isReconnecting = false;
      _reconnectionAttempts = 0;
      _reconnectionTimer?.cancel();

      if (!_connectionStatusController.isClosed) {
        _connectionStatusController.add(true);
      }

      debugPrint('🟢 [SocketService] Connected to ${ApiConstants.baseUrl}');

      // Rejoin all rooms after reconnection
      _rejoinRooms();
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;

      if (!_connectionStatusController.isClosed) {
        _connectionStatusController.add(false);
      }

      debugPrint('🔴 [SocketService] Disconnected');

      // Start reconnection attempts
      _attemptReconnection();
    });

    _socket!.onConnectError((data) {
      _isConnected = false;
      debugPrint('🔴 [SocketService] Connection Error: $data');

      // Start reconnection attempts
      _attemptReconnection();
    });

    _socket!.onError((data) {
      debugPrint('🔴 [SocketService] Error: $data');
    });

    _socket!.on('connect_timeout', (data) {
      debugPrint('🔴 [SocketService] Connection Timeout: $data');
      _attemptReconnection();
    });

    // Listen for driver status confirmation
    _socket!.on('driver:status', (data) {
      debugPrint('📩 [SocketService] Received driver:status: $data');
    });

    // Listen for location update confirmation
    _socket!.on('driver:locationUpdated', (data) {
      debugPrint('📩 [SocketService] Received driver:locationUpdated: $data');
    });

    // Listen for room join confirmation
    _socket!.on('room:joined', (data) {
      debugPrint('📩 [SocketService] Room joined: $data');
    });

    // Wildcard listener to debug ALL incoming events
    _socket!.onAny((event, data) {
      debugPrint('📨 [SocketService] INCOMING EVENT: $event, Data: $data');
    });
  }

  /// Attempt to reconnect with exponential backoff
  void _attemptReconnection() {
    if (_isReconnecting || _isConnected) return;

    _isReconnecting = true;
    _reconnectionAttempts++;

    if (_reconnectionAttempts > _maxReconnectionAttempts) {
      debugPrint('🔴 [SocketService] Max reconnection attempts reached');
      _isReconnecting = false;
      return;
    }

    // Exponential backoff: delay increases with each attempt
    final delay = _reconnectionDelayMs * _reconnectionAttempts;
    debugPrint(
      '🔄 [SocketService] Attempting reconnection #$_reconnectionAttempts in ${delay}ms...',
    );

    _reconnectionTimer?.cancel();
    _reconnectionTimer = Timer(Duration(milliseconds: delay), () async {
      if (!_isConnected) {
        debugPrint('🔄 [SocketService] Reconnecting...');
        _socket?.connect();
      }
      _isReconnecting = false;
    });
  }

  /// Rejoin all rooms after reconnection
  void _rejoinRooms() {
    if (_joinedRooms.isEmpty) return;

    debugPrint('🔄 [SocketService] Rejoining ${_joinedRooms.length} rooms...');
    for (final room in _joinedRooms) {
      emit('join:room', {'room': room});
      debugPrint('🔄 [SocketService] Rejoined room: $room');
    }
  }

  /// Join a specific room (e.g., driver:${driverId} to receive location updates)
  void joinRoom(String roomName) {
    if (roomName.isEmpty) {
      debugPrint('⚠️ [SocketService] Cannot join room: empty room name');
      return;
    }

    _joinedRooms.add(roomName);
    emit('join:room', {'room': roomName});
    debugPrint('🏠 [SocketService] Joining room: $roomName');
  }

  /// Leave a specific room
  void leaveRoom(String roomName) {
    if (roomName.isEmpty) return;

    _joinedRooms.remove(roomName);
    emit('leave:room', {'room': roomName});
    debugPrint('🚪 [SocketService] Left room: $roomName');
  }

  /// Join the driver's location room to receive real-time location updates
  void joinDriverRoom(String driverId) {
    if (driverId.isEmpty) {
      debugPrint('⚠️ [SocketService] Cannot join driver room: empty driverId');
      return;
    }

    final roomName = 'driver:$driverId';
    joinRoom(roomName);
    debugPrint('🚗 [SocketService] Joined driver location room: $roomName');
  }

  /// Leave the driver's location room
  void leaveDriverRoom(String driverId) {
    if (driverId.isEmpty) return;

    final roomName = 'driver:$driverId';
    leaveRoom(roomName);
    debugPrint('🚗 [SocketService] Left driver location room: $roomName');
  }

  /// Emit user:goOnline to register user for receiving ride updates
  void emitUserOnline(String userId) {
    if (userId.isEmpty) {
      debugPrint('⚠️ [SocketService] Cannot emit user:goOnline: empty userId');
      return;
    }
    emit('user:goOnline', {'userId': userId});
    debugPrint('👤 [SocketService] User online: $userId');
  }

  /// Emit driver:goOnline to register driver for receiving ride requests
  void emitDriverOnline(String driverId) {
    if (driverId.isEmpty) {
      debugPrint(
        '⚠️ [SocketService] Cannot emit driver:goOnline: empty driverId',
      );
      return;
    }
    emit('driver:goOnline', {'driverId': driverId});
    debugPrint('🚗 [SocketService] Driver online: $driverId');
  }

  /// Emit driver:goOffline when driver goes offline
  void emitDriverOffline(String driverId) {
    if (driverId.isEmpty) return;
    emit('driver:goOffline', {'driverId': driverId});
    debugPrint('🚗 [SocketService] Driver offline: $driverId');
  }

  /// Emit driver:locationUpdate for real-time location tracking
  void emitDriverLocationUpdate({
    required String driverId,
    required double latitude,
    required double longitude,
  }) {
    if (driverId.isEmpty) return;
    emit('driver:locationUpdate', {
      'driverId': driverId,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  void disconnect() {
    _reconnectionTimer?.cancel();
    _joinedRooms.clear();

    if (_socket != null) {
      _socket!.disconnect();
      _socket = null;
      _isConnected = false;
      debugPrint('🔴 [SocketService] Disconnected manually');
    }
  }

  /// Dispose of resources
  void dispose() {
    _reconnectionTimer?.cancel();
    _connectionStatusController.close();
    disconnect();
  }

  void emit(String event, dynamic data) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit(event, data);
      debugPrint('📤 [SocketService] Emitted: $event, Data: $data');
    } else {
      debugPrint('⚠️ [SocketService] Cannot emit $event, socket not connected');
    }
  }

  void on(String event, Function(dynamic) handler) {
    if (_socket != null) {
      _socket!.on(event, handler);
      debugPrint('👂 [SocketService] Listening for: $event');
    }
  }

  void off(String event) {
    if (_socket != null) {
      _socket!.off(event);
      debugPrint('🔇 [SocketService] Stopped listening for: $event');
    }
  }

  /// Check if a handler is registered for an event
  bool hasListeners(String event) {
    return _socket?.hasListeners(event) ?? false;
  }
}
