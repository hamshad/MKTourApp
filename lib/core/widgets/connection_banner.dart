import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_service.dart';
import '../services/ride_session.dart';
import '../services/socket_service.dart';

/// Stale threshold: driver position / ETA older than this is dimmed +
/// timestamped, never animated as live (19-03 must-have).
const Duration kStaleThreshold = Duration(seconds: 30);

/// True when [lastUpdate] is older than [threshold] (or never set).
bool isRideDataStale(DateTime? lastUpdate,
    {Duration threshold = kStaleThreshold, DateTime? now}) {
  if (lastUpdate == null) return true;
  return (now ?? DateTime.now()).difference(lastUpdate) > threshold;
}

/// "Last updated 45s ago" / "Last updated 2m ago".
String formatLastUpdated(Duration gap) {
  if (gap.inSeconds < 60) return 'Last updated ${gap.inSeconds}s ago';
  final m = gap.inMinutes;
  if (m < 60) return 'Last updated ${m}m ago';
  return 'Last updated ${gap.inHours}h ago';
}

/// Queued-intent copy shown when an offline tap is accepted for later send.
const String kQueuedIntentCopy = 'Will send when reconnected';

/// Offline action guard: keeps action buttons enabled offline, shows the
/// queued-intent toast, queues via `emitReliable`, and never double-fires.
///
/// Returns false when the same rideId+action is already queued/in-flight
/// (caller must keep the button disabled in that case).
/// Shows "[queued-intent copy]" toast on the queuing path.
Future<bool> guardOfflineAction({
  required BuildContext context,
  required SocketService socket,
  required String rideId,
  required String action,
  required String event,
  required dynamic data,
  String queuedCopy = kQueuedIntentCopy,
}) async {
  final key = '$event:$rideId';
  if (socket.eventQueue.hasPending(event, rideId)) {
    return false;
  }
  if (_OfflineActionDebounce.isDebounced(key)) {
    return false;
  }
  _OfflineActionDebounce.mark(key);
  final online = socket.isConnected;
  socket.emitReliable(event, data);
  if (!online && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$action — $queuedCopy'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  return true;
}

class _OfflineActionDebounce {
  static final Map<String, DateTime> _lastTap = {};
  static const Duration window = Duration(seconds: 2);

  static bool isDebounced(String key) {
    final last = _lastTap[key];
    if (last == null) return false;
    return DateTime.now().difference(last) < window;
  }

  static void mark(String key) => _lastTap[key] = DateTime.now();
}

/// Small dimmed chip labeling stale data with its age.
class StaleDataChip extends StatelessWidget {
  final DateTime? lastUpdated;
  final DateTime? nowForTest;

  const StaleDataChip({super.key, this.lastUpdated, this.nowForTest});

  @override
  Widget build(BuildContext context) {
    final base = lastUpdated ?? DateTime.now();
    final gap = (nowForTest ?? DateTime.now()).difference(base);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            formatLastUpdated(gap.isNegative ? Duration.zero : gap),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

/// Uber-style connection pill mounted as an overlay above the map.
///
/// - `live` → renders nothing (zero layout shift, pixel-identical healthy UI)
/// - `reconnecting` → renders nothing (transient self-heal, no UX nag)
/// - `offline` → grey "No connection — actions will send when reconnected"
///   + Retry button (`initSocket(forceReconnect: true)` + `resyncActiveRide`)
///
/// Pass [forcedState] in widget tests to pin states without a socket.
class ConnectionBanner extends StatefulWidget {
  final SocketConnectionState? forcedState;
  final DateTime? lastDisconnectedAt;
  final VoidCallback? onRetry;
  final String? rideId;
  final bool showRetry;

  const ConnectionBanner({
    super.key,
    this.forcedState,
    this.lastDisconnectedAt,
    this.onRetry,
    this.rideId,
    this.showRetry = true,
  });

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  Timer? _tick;
  DateTime? _retryLastTap;

  @override
  void initState() {
    super.initState();
    // Ticks the "Xs ago" label once per second while visible (offline only —
    // reconnecting renders nothing).
    if (widget.forcedState != null &&
        widget.forcedState == SocketConnectionState.offline) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Retry tap with a 2s debounce: a second tap within the window is
  /// ignored so reconnects never double-fire (covers both the default
  /// socket retry and injected test handlers).
  void _onRetryTap() {
    final now = DateTime.now();
    if (_retryLastTap != null &&
        now.difference(_retryLastTap!) < const Duration(seconds: 2)) {
      return;
    }
    _retryLastTap = now;
    final handler = widget.onRetry;
    if (handler != null) {
      handler();
    } else {
      unawaited(_defaultRetry());
    }
  }

  Future<void> _defaultRetry() async {
    final socket = SocketService();
    await socket.initSocket(forceReconnect: true);
    try {
      await resyncActiveRide(
        api: ApiService(),
        socket: socket,
        rideId: widget.rideId,
      );
    } catch (_) {
      // Resync is best-effort here; the socket reconnect is the retry.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.forcedState != null) {
      return _buildForState(
        context,
        widget.forcedState!,
        widget.lastDisconnectedAt,
      );
    }
    return StreamBuilder<SocketConnectionState>(
      stream: SocketService().connectionState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? SocketConnectionState.online;
        if (state != SocketConnectionState.offline) {
          return const SizedBox.shrink();
        }
        return _buildForState(
          context,
          state,
          SocketService().lastDisconnectedAt,
        );
      },
    );
  }

  Widget _buildForState(
    BuildContext context,
    SocketConnectionState state,
    DateTime? lastDisconnectedAt,
  ) {
    if (state != SocketConnectionState.offline) {
      return const SizedBox.shrink();
    }
    final base = lastDisconnectedAt ?? DateTime.now();
    final gap = DateTime.now().difference(base);
    final age = formatLastUpdated(gap.isNegative ? Duration.zero : gap);
    return SafeArea(
      bottom: false,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F2F4),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFC9CDD3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No connection — actions will send when reconnected',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                  Text(
                    age,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.showRetry) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: _onRetryTap,
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
