import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'location_service.dart';

/// Service to cache and manage user's location with background updates
class LocationCacheService {
  static final LocationCacheService _instance =
      LocationCacheService._internal();
  factory LocationCacheService() => _instance;
  LocationCacheService._internal();

  final LocationService _locationService = LocationService();

  Position? _cachedPosition;
  DateTime? _lastUpdate;
  bool _isFetching = false;

  /// How long cached location is considered valid (in seconds)
  static const int _cacheValidityDuration = 60; // 1 minute

  /// List of callbacks to notify when location updates
  final List<Function(Position)> _listeners = [];

  /// Get cached position if available and valid
  Position? get cachedPosition {
    if (_cachedPosition == null) return null;

    final now = DateTime.now();
    if (_lastUpdate != null &&
        now.difference(_lastUpdate!).inSeconds < _cacheValidityDuration) {
      return _cachedPosition;
    }

    return null; // Cache expired
  }

  /// Check if currently fetching location
  bool get isFetching => _isFetching;

  /// Add a listener for location updates
  void addListener(Function(Position) callback) {
    _listeners.add(callback);
  }

  /// Remove a listener
  void removeListener(Function(Position) callback) {
    _listeners.remove(callback);
  }

  /// Notify all listeners of location update
  void _notifyListeners(Position position) {
    for (var listener in _listeners) {
      try {
        listener(position);
      } catch (e) {
        debugPrint('Error notifying location listener: $e');
      }
    }
  }

  /// Get location - returns cached if valid, otherwise fetches new
  Future<Position?> getLocation({bool forceRefresh = false}) async {
    // Return cached if valid and not forcing refresh
    if (!forceRefresh && cachedPosition != null) {
      debugPrint('📍 LocationCacheService: Returning cached location');
      return cachedPosition;
    }

    // If already fetching, wait for it
    if (_isFetching) {
      debugPrint('📍 LocationCacheService: Already fetching, waiting...');
      // Wait a bit and return cached or null
      await Future.delayed(const Duration(milliseconds: 500));
      return cachedPosition;
    }

    return await _fetchAndCacheLocation();
  }

  /// Fetch fresh location and cache it
  Future<Position?> _fetchAndCacheLocation() async {
    _isFetching = true;
    debugPrint('📍 LocationCacheService: Fetching fresh location...');

    try {
      // First check and request permissions
      final hasPermission = await _locationService.handleLocationPermission();
      if (!hasPermission) {
        debugPrint('📍 LocationCacheService: Location permission denied');
        _isFetching = false;
        return null;
      }

      // Try to get last known position first (instant)
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          debugPrint('📍 LocationCacheService: Got last known position');
          _updateCache(lastKnown);
          // Still fetch fresh one in background
          _fetchFreshInBackground();
          return lastKnown;
        }
      } catch (e) {
        debugPrint('📍 LocationCacheService: No last known position: $e');
      }

      // Get fresh location
      final position = await _locationService.getCurrentLocation();

      if (position != null) {
        _updateCache(position);
        debugPrint('📍 LocationCacheService: Fresh location cached');
        return position;
      }

      debugPrint('📍 LocationCacheService: getCurrentLocation returned null');
      return null;
    } catch (e) {
      debugPrint('📍 LocationCacheService: Error fetching location: $e');
      return null;
    } finally {
      _isFetching = false;
    }
  }

  /// Fetch fresh location in background without blocking
  void _fetchFreshInBackground() {
    Future.delayed(Duration.zero, () async {
      try {
        final position = await _locationService.getCurrentLocation();
        if (position != null) {
          _updateCache(position);
          debugPrint('📍 LocationCacheService: Background fetch completed');
        }
      } catch (e) {
        debugPrint('📍 LocationCacheService: Background fetch error: $e');
      }
    });
  }

  /// Update cache and notify listeners
  void _updateCache(Position position) {
    _cachedPosition = position;
    _lastUpdate = DateTime.now();
    _notifyListeners(position);
  }

  /// Start background location updates (for active use)
  void startBackgroundUpdates() {
    debugPrint('📍 LocationCacheService: Starting background updates');
    _locationService
        .getPeriodicPositionStream(intervalSeconds: 30)
        .listen(
          (position) {
            _updateCache(position);
            debugPrint('📍 LocationCacheService: Background update received');
          },
          onError: (error) {
            debugPrint(
              '📍 LocationCacheService: Background update error: $error',
            );
          },
        );
  }

  /// Preload location (call this early in app lifecycle)
  Future<void> preloadLocation() async {
    debugPrint('📍 LocationCacheService: Preloading location...');
    await getLocation();
  }

  /// Clear cache
  void clearCache() {
    _cachedPosition = null;
    _lastUpdate = null;
    debugPrint('📍 LocationCacheService: Cache cleared');
  }
}
