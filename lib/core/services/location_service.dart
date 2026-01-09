import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class LocationService {
  /// Timer for periodic location updates
  Timer? _periodicUpdateTimer;

  /// Stream controller for periodic updates
  StreamController<Position>? _periodicStreamController;

  Future<bool> handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      debugPrint('Location services are disabled.');
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        debugPrint('Location permissions are denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      debugPrint(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
      return false;
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    return true;
  }

  Future<Position?> getCurrentLocation() async {
    final hasPermission = await handleLocationPermission();
    if (!hasPermission) return null;

    try {
      return await Geolocator.getCurrentPosition();
    } catch (e) {
      debugPrint('Error getting current location: $e');
      return null;
    }
  }

  /// Standard position stream based on distance filter
  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    );
  }

  /// Get a position stream that updates at regular intervals (recommended 3-5 seconds for ride tracking).
  /// This ensures location updates are sent even when the driver is stationary or moving slowly.
  ///
  /// [intervalSeconds] - How often to emit location updates (default: 4 seconds)
  Stream<Position> getPeriodicPositionStream({int intervalSeconds = 4}) {
    _periodicStreamController?.close();
    _periodicUpdateTimer?.cancel();

    _periodicStreamController = StreamController<Position>.broadcast(
      onCancel: () {
        _periodicUpdateTimer?.cancel();
        debugPrint('📍 [LocationService] Periodic stream cancelled');
      },
    );

    // Immediately get and emit current position
    _emitCurrentPosition();

    // Set up periodic timer
    _periodicUpdateTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => _emitCurrentPosition(),
    );

    debugPrint(
      '📍 [LocationService] Started periodic location updates every ${intervalSeconds}s',
    );

    return _periodicStreamController!.stream;
  }

  /// Helper to emit current position to the periodic stream
  Future<void> _emitCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (_periodicStreamController != null &&
          !_periodicStreamController!.isClosed) {
        _periodicStreamController!.add(position);
      }
    } catch (e) {
      debugPrint('📍 [LocationService] Error getting position: $e');
    }
  }

  /// High-accuracy position stream for active rides (combines distance and time-based updates)
  /// Updates on movement (5m) OR every [intervalSeconds] seconds, whichever comes first.
  Stream<Position> getRideTrackingStream({int intervalSeconds = 3}) {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // More sensitive: update every 5 meters
        intervalDuration: Duration(
          seconds: intervalSeconds,
        ), // Also update at intervals
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText:
              "MK Tours is tracking your location for the current ride",
          notificationTitle: "Active Ride",
          enableWakeLock: true, // Keep device awake during ride
        ),
      ),
    );
  }

  /// Dispose of resources
  void dispose() {
    _periodicUpdateTimer?.cancel();
    _periodicStreamController?.close();
  }
}
