import 'dart:async';
import 'package:flutter/material.dart';
import '../services/socket_service.dart';
import '../theme.dart';

/// A banner that slides in from the top when the socket connection is lost,
/// and slides out when reconnected.
///
/// Usage: Place this in a Stack at the top of any screen that needs
/// real-time socket connectivity feedback.
///
/// ```dart
/// Stack(
///   children: [
///     // ... your main content ...
///     const ConnectionStatusBanner(),
///   ],
/// )
/// ```
class ConnectionStatusBanner extends StatefulWidget {
  /// Position from top (to account for app bars, safe area, etc.)
  final double topOffset;

  const ConnectionStatusBanner({super.key, this.topOffset = 0});

  @override
  State<ConnectionStatusBanner> createState() => _ConnectionStatusBannerState();
}

class _ConnectionStatusBannerState extends State<ConnectionStatusBanner>
    with SingleTickerProviderStateMixin {
  final SocketService _socketService = SocketService();
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<int>? _queueSub;

  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;

  bool _isDisconnected = false;
  int _pendingEvents = 0;
  bool _showingReconnected = false;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1), // Start above the screen
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _isDisconnected = !_socketService.isConnected;
    if (_isDisconnected) {
      _animController.value = 1.0; // Start visible if already disconnected
    }

    _connectionSub = _socketService.connectionStatus.listen(
      _onConnectionChange,
    );
    _queueSub = _socketService.eventQueue.queueSize.listen((size) {
      if (mounted) setState(() => _pendingEvents = size);
    });
  }

  void _onConnectionChange(bool connected) {
    if (!mounted) return;

    if (!connected && !_isDisconnected) {
      // Just disconnected — show banner
      setState(() {
        _isDisconnected = true;
        _showingReconnected = false;
      });
      _animController.forward();
    } else if (connected && _isDisconnected) {
      // Just reconnected — briefly show "Reconnected" then hide
      setState(() {
        _isDisconnected = false;
        _showingReconnected = true;
      });
      // Keep banner visible for 2 seconds with "Reconnected" message
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _animController.reverse().then((_) {
            if (mounted) {
              setState(() => _showingReconnected = false);
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _queueSub?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.topOffset,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slideAnimation,
        child: Material(
          elevation: 4,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _showingReconnected
                  ? AppTheme.successColor
                  : AppTheme.errorColor.withValues(alpha: 0.95),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  if (_showingReconnected) ...[
                    const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Reconnected',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _pendingEvents > 0
                            ? 'Reconnecting... ($_pendingEvents events queued)'
                            : 'Reconnecting...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
