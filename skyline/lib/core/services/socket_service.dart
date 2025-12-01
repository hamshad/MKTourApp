import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  IO.Socket? _socket;
  bool _isConnected = false;

  factory SocketService() {
    return _instance;
  }

  SocketService._internal();

  bool get isConnected => _isConnected;

  Future<void> initSocket() async {
    if (_socket != null && _socket!.connected) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    if (token == null) {
      debugPrint('⚠️ [SocketService] No token found, skipping connection');
      return;
    }

    debugPrint('🔵 [SocketService] Connecting to ${ApiConstants.baseUrl}...');

    _socket = IO.io(
      ApiConstants.baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .build(),
    );

    _socket!.onConnect((_) {
      _isConnected = true;
      debugPrint('🟢 [SocketService] Connected');
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      debugPrint('🔴 [SocketService] Disconnected');
    });

    _socket!.onConnectError((data) {
      _isConnected = false;
      debugPrint('🔴 [SocketService] Connection Error: $data');
    });

    _socket!.onError((data) {
      debugPrint('🔴 [SocketService] Error: $data');
    });
  }

  void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket = null;
      _isConnected = false;
      debugPrint('🔴 [SocketService] Disconnected manually');
    }
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
}
