import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// A service for smoothly animating marker positions between GPS coordinates.
/// This prevents the "jumping" effect when receiving location updates every few seconds.
class MarkerInterpolationService {
  /// Current interpolated position
  LatLng _currentPosition;

  /// Target position to interpolate towards
  LatLng _targetPosition;

  /// Current bearing (direction)
  double _currentBearing = 0.0;

  /// Target bearing
  double _targetBearing = 0.0;

  /// Interpolation timer
  Timer? _interpolationTimer;

  /// Stream controller for position updates
  final StreamController<InterpolatedPosition> _positionController =
      StreamController<InterpolatedPosition>.broadcast();

  /// Duration of interpolation in milliseconds
  final int interpolationDurationMs;

  /// Update interval in milliseconds (60 FPS = ~16ms)
  final int updateIntervalMs;

  /// Progress of current interpolation (0.0 to 1.0)
  double _interpolationProgress = 1.0;

  /// Starting position for current interpolation
  LatLng? _startPosition;
  double? _startBearing;

  /// Constructor
  MarkerInterpolationService({
    required LatLng initialPosition,
    this.interpolationDurationMs = 2000, // 2 seconds default
    this.updateIntervalMs = 16, // ~60 FPS
  }) : _currentPosition = initialPosition,
       _targetPosition = initialPosition;

  /// Stream of interpolated positions
  Stream<InterpolatedPosition> get positionStream => _positionController.stream;

  /// Get current position
  LatLng get currentPosition => _currentPosition;

  /// Get current bearing
  double get currentBearing => _currentBearing;

  /// Update to a new target position (called when GPS update received)
  void updatePosition(LatLng newPosition, {double? bearing}) {
    // Calculate bearing if not provided
    double newBearing =
        bearing ?? _calculateBearing(_currentPosition, newPosition);

    // Start new interpolation from current position
    _startPosition = _currentPosition;
    _startBearing = _currentBearing;
    _targetPosition = newPosition;
    _targetBearing = newBearing;
    _interpolationProgress = 0.0;

    // Start or continue interpolation
    _startInterpolation();

    debugPrint(
      '🚗 [MarkerInterpolation] New target: ${newPosition.latitude}, ${newPosition.longitude}, bearing: $newBearing',
    );
  }

  /// Start the interpolation timer
  void _startInterpolation() {
    // Cancel existing timer if running
    _interpolationTimer?.cancel();

    final int steps = interpolationDurationMs ~/ updateIntervalMs;
    final double progressStep = 1.0 / steps;

    _interpolationTimer = Timer.periodic(
      Duration(milliseconds: updateIntervalMs),
      (timer) {
        _interpolationProgress += progressStep;

        if (_interpolationProgress >= 1.0) {
          _interpolationProgress = 1.0;
          timer.cancel();
        }

        // Use easing function for smoother motion
        final double easedProgress = _easeInOutCubic(_interpolationProgress);

        // Interpolate position
        _currentPosition = _interpolateLatLng(
          _startPosition!,
          _targetPosition,
          easedProgress,
        );

        // Interpolate bearing
        _currentBearing = _interpolateBearing(
          _startBearing!,
          _targetBearing,
          easedProgress,
        );

        // Emit the interpolated position
        if (!_positionController.isClosed) {
          _positionController.add(
            InterpolatedPosition(
              position: _currentPosition,
              bearing: _currentBearing,
              progress: _interpolationProgress,
            ),
          );
        }
      },
    );
  }

  /// Cubic easing function for smoother animation
  double _easeInOutCubic(double t) {
    return t < 0.5
        ? 4 * t * t * t
        : 1 - ((-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2)) / 2;
  }

  /// Linear interpolation between two LatLng positions
  LatLng _interpolateLatLng(LatLng start, LatLng end, double progress) {
    final double lat =
        start.latitude + (end.latitude - start.latitude) * progress;
    final double lng =
        start.longitude + (end.longitude - start.longitude) * progress;
    return LatLng(lat, lng);
  }

  /// Interpolate bearing, handling wrap-around at 360 degrees
  double _interpolateBearing(double start, double end, double progress) {
    // Normalize bearings to 0-360
    start = start % 360;
    end = end % 360;

    // Find shortest path
    double diff = end - start;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    return (start + diff * progress) % 360;
  }

  /// Calculate bearing between two points
  double _calculateBearing(LatLng from, LatLng to) {
    final double fromLat = from.latitude * (3.141592653589793 / 180);
    final double fromLng = from.longitude * (3.141592653589793 / 180);
    final double toLat = to.latitude * (3.141592653589793 / 180);
    final double toLng = to.longitude * (3.141592653589793 / 180);

    final double dLng = toLng - fromLng;

    final double x = _sin(dLng) * _cos(toLat);
    final double y =
        _cos(fromLat) * _sin(toLat) - _sin(fromLat) * _cos(toLat) * _cos(dLng);

    double bearing = _atan2(x, y) * (180 / 3.141592653589793);
    return (bearing + 360) % 360;
  }

  // Math helpers
  double _sin(double x) => x - (x * x * x) / 6 + (x * x * x * x * x) / 120;
  double _cos(double x) => 1 - (x * x) / 2 + (x * x * x * x) / 24;
  double _atan2(double y, double x) {
    // Simplified atan2 - use dart:math in production
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + 3.141592653589793;
    if (x < 0 && y < 0) return _atan(y / x) - 3.141592653589793;
    if (x == 0 && y > 0) return 3.141592653589793 / 2;
    if (x == 0 && y < 0) return -3.141592653589793 / 2;
    return 0;
  }

  double _atan(double x) => x - (x * x * x) / 3 + (x * x * x * x * x) / 5;

  /// Dispose of resources
  void dispose() {
    _interpolationTimer?.cancel();
    _positionController.close();
    debugPrint('🔴 [MarkerInterpolation] Disposed');
  }
}

/// Represents an interpolated position with bearing
class InterpolatedPosition {
  final LatLng position;
  final double bearing;
  final double progress; // 0.0 to 1.0

  const InterpolatedPosition({
    required this.position,
    required this.bearing,
    required this.progress,
  });
}
