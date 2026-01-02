import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'places_service.dart';

/// Service to manage navigation routes and turn-by-turn directions
class NavigationService {
  final PlacesService _placesService = PlacesService();
  
  /// Current route polyline points
  List<LatLng> _currentRoute = [];
  
  /// Current navigation state
  NavigationState? _currentState;
  
  /// Stream controller for route updates
  final _routeUpdateController = StreamController<NavigationState>.broadcast();
  
  /// Stream of route updates
  Stream<NavigationState> get routeUpdates => _routeUpdateController.stream;
  
  /// Get current route
  List<LatLng> get currentRoute => _currentRoute;
  
  /// Get current navigation state
  NavigationState? get currentState => _currentState;
  
  /// Fetch navigation route from origin to destination
  Future<NavigationState?> fetchRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      debugPrint('🧭 NavigationService: Fetching route from ($originLat, $originLng) to ($destLat, $destLng)');
      
      final directions = await _placesService.getDirections(
        originLat,
        originLng,
        destLat,
        destLng,
      );
      
      if (directions == null) {
        debugPrint('❌ NavigationService: Failed to fetch directions');
        return null;
      }
      
      // Convert polyline points to LatLng
      final polylinePoints = (directions['polyline'] as List)
          .map((point) => LatLng(point['lat'], point['lng']))
          .toList();
      
      _currentRoute = polylinePoints;
      
      // Create navigation state
      _currentState = NavigationState(
        polyline: polylinePoints,
        distanceMeters: directions['distance_meters'],
        distanceText: directions['distance_text'],
        durationSeconds: directions['duration_seconds'],
        durationText: directions['duration_text'],
        startAddress: directions['start_address'],
        endAddress: directions['end_address'],
        bearing: _calculateInitialBearing(
          LatLng(originLat, originLng),
          polylinePoints.isNotEmpty ? polylinePoints.first : LatLng(destLat, destLng),
        ),
      );
      
      debugPrint('✅ NavigationService: Route fetched - ${_currentState!.distanceText}, ${_currentState!.durationText}');
      
      // Notify listeners
      _routeUpdateController.add(_currentState!);
      
      return _currentState;
    } catch (e) {
      debugPrint('❌ NavigationService: Error fetching route: $e');
      return null;
    }
  }
  
  /// Update route based on new current location (for real-time navigation)
  Future<NavigationState?> updateRoute({
    required double currentLat,
    required double currentLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      debugPrint('🧭 NavigationService: Updating route from current position');
      
      // Check if we need to recalculate route (if deviated significantly)
      if (_shouldRecalculateRoute(currentLat, currentLng)) {
        return await fetchRoute(
          originLat: currentLat,
          originLng: currentLng,
          destLat: destLat,
          destLng: destLng,
        );
      }
      
      // Otherwise, just update bearing and remaining distance
      if (_currentState != null && _currentRoute.isNotEmpty) {
        final currentPos = LatLng(currentLat, currentLng);
        final nextPoint = _findNearestPointOnRoute(currentPos);
        
        final updatedState = NavigationState(
          polyline: _currentRoute,
          distanceMeters: _currentState!.distanceMeters,
          distanceText: _currentState!.distanceText,
          durationSeconds: _currentState!.durationSeconds,
          durationText: _currentState!.durationText,
          startAddress: _currentState!.startAddress,
          endAddress: _currentState!.endAddress,
          bearing: _calculateBearing(currentPos, nextPoint),
          currentInstruction: _getCurrentInstruction(currentPos),
        );
        
        _currentState = updatedState;
        _routeUpdateController.add(updatedState);
        
        return updatedState;
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ NavigationService: Error updating route: $e');
      return null;
    }
  }
  
  /// Calculate bearing between two points (in degrees)
  double _calculateBearing(LatLng start, LatLng end) {
    final lat1 = _degreesToRadians(start.latitude);
    final lat2 = _degreesToRadians(end.latitude);
    final dLng = _degreesToRadians(end.longitude - start.longitude);
    
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    
    final bearing = math.atan2(y, x);
    
    // Convert to degrees and normalize to 0-360
    return (_radiansToDegrees(bearing) + 360) % 360;
  }
  
  /// Calculate initial bearing
  double _calculateInitialBearing(LatLng start, LatLng end) {
    return _calculateBearing(start, end);
  }
  
  /// Check if route should be recalculated based on deviation
  bool _shouldRecalculateRoute(double currentLat, double currentLng) {
    if (_currentRoute.isEmpty) return true;
    
    final currentPos = LatLng(currentLat, currentLng);
    final nearestPoint = _findNearestPointOnRoute(currentPos);
    final distance = _calculateDistance(currentPos, nearestPoint);
    
    // Recalculate if more than 100 meters off route
    return distance > 100;
  }
  
  /// Find nearest point on current route
  LatLng _findNearestPointOnRoute(LatLng position) {
    if (_currentRoute.isEmpty) return position;
    
    double minDistance = double.infinity;
    LatLng nearestPoint = _currentRoute.first;
    
    for (final point in _currentRoute) {
      final distance = _calculateDistance(position, point);
      if (distance < minDistance) {
        minDistance = distance;
        nearestPoint = point;
      }
    }
    
    return nearestPoint;
  }
  
  /// Calculate distance between two points (in meters)
  double _calculateDistance(LatLng start, LatLng end) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, start, end);
  }
  
  /// Get current navigation instruction
  String _getCurrentInstruction(LatLng currentPos) {
    // This is a simplified version
    // In production, you'd parse the directions steps from Google API
    if (_currentRoute.isEmpty) return 'Navigate to destination';
    
    final nextPoint = _findNearestPointOnRoute(currentPos);
    final distance = _calculateDistance(currentPos, nextPoint);
    
    if (distance < 50) {
      return 'Continue straight';
    } else if (distance < 200) {
      return 'In ${distance.toInt()}m, continue';
    } else {
      return 'Follow the route';
    }
  }
  
  /// Convert degrees to radians
  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }
  
  /// Convert radians to degrees
  double _radiansToDegrees(double radians) {
    return radians * 180.0 / math.pi;
  }
  
  /// Get detailed address from coordinates
  Future<String> getDetailedAddress(double lat, double lng) async {
    try {
      final address = await _placesService.getAddressFromLatLng(lat, lng);
      return address ?? 'Unknown location';
    } catch (e) {
      debugPrint('❌ NavigationService: Error getting address: $e');
      return 'Unknown location';
    }
  }
  
  /// Clear current route
  void clearRoute() {
    _currentRoute = [];
    _currentState = null;
    debugPrint('🧭 NavigationService: Route cleared');
  }
  
  /// Dispose resources
  void dispose() {
    _routeUpdateController.close();
  }
}

/// Navigation state containing route and metadata
class NavigationState {
  final List<LatLng> polyline;
  final int distanceMeters;
  final String distanceText;
  final int durationSeconds;
  final String durationText;
  final String startAddress;
  final String endAddress;
  final double bearing;
  final String? currentInstruction;
  
  NavigationState({
    required this.polyline,
    required this.distanceMeters,
    required this.distanceText,
    required this.durationSeconds,
    required this.durationText,
    required this.startAddress,
    required this.endAddress,
    required this.bearing,
    this.currentInstruction,
  });
  
  /// Get ETA text
  String get etaText {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) {
      return '$minutes min';
    } else {
      final hours = (minutes / 60).floor();
      final remainingMinutes = minutes % 60;
      return '${hours}h ${remainingMinutes}m';
    }
  }
}
