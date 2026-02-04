// DRIVER TRACKING IMPLEMENTATION - KEY CODE SNIPPETS
// ====================================================

// 1. START TRACKING WHEN RIDE IS ACCEPTED
// ========================================

// In ride_assigned_screen.dart - ride:accepted event handler
_socketService.on('ride:accepted', (data) {
  setState(() {
    _rideStatus = 'accepted';
    _driver = data['driver'] ?? {};
    _currentDriverId = _driver['_id']?.toString() ?? _driver['id']?.toString();
    
    if (_currentDriverId != null) {
      // Join driver's location room
      _socketService.joinDriverRoom(_currentDriverId!);
      
      // START TRACKING: Emit ride:trackDriver
      _socketService.startTrackingDriver(_currentDriverId!);
      
      // Start periodic ETA updates with real traffic data
      _startETAUpdates();
    }
    
    if (data['driver']?['location'] != null) {
      final coords = data['driver']['location']['coordinates'];
      _driverLocation = LatLng(coords[1], coords[0]);
      _fetchNavigationRoute();
    }
  });
});

// 2. LISTEN FOR LOCATION UPDATES
// ===============================

_socketService.on('driver:locationChanged', (data) {
  if (!mounted) return;
  
  if (data['location']?['coordinates'] != null) {
    final coords = data['location']['coordinates'];
    var lat = coords[1]; // Latitude is at index 1
    var lng = coords[0]; // Longitude is at index 0
    
    final newPosition = LatLng(lat, lng);
    
    // Update car marker with smooth animation
    _markerInterpolation!.updatePosition(newPosition);
    
    // Update navigation route in real-time
    if (_rideStatus != 'driver_arrived') {
      _updateNavigationRoute();
    }
  }
});

// 3. CALCULATE ETA WITH REAL TRAFFIC DATA
// ========================================

Future<void> _calculateETA() async {
  if (_driverLocation == null || _rideStatus != 'accepted') return;

  try {
    // Use Distance Matrix API to get real-time travel time with traffic
    final result = await _placesService.getDistanceAndFare(
      originLat: _driverLocation!.latitude,
      originLng: _driverLocation!.longitude,
      destLat: _pickupLocation.latitude,
      destLng: _pickupLocation.longitude,
      categorySlug: 'car_4_seater',
    );

    if (result != null && mounted) {
      final durationSeconds = result['duration_seconds'] as int? ?? 0;
      final durationText = result['duration_text'] as String? ?? '';
      
      setState(() {
        _etaMinutes = (durationSeconds / 60).ceil();
        _etaText = durationText;
      });
      
      debugPrint('🕐 ETA updated: $_etaText ($_etaMinutes mins)');
    }
  } catch (e) {
    debugPrint('⚠️ Error calculating ETA: $e');
  }
}

// 4. PERIODIC ETA UPDATES (Every 20 seconds)
// ===========================================

void _startETAUpdates() {
  _etaTimer?.cancel();
  
  // Calculate immediately
  _calculateETA();
  
  // Update every 20 seconds (balance between accuracy and API costs)
  _etaTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
    if (_rideStatus == 'accepted' && _driverLocation != null) {
      _calculateETA();
    } else {
      timer.cancel();
    }
  });
}

void _stopETAUpdates() {
  _etaTimer?.cancel();
  _etaTimer = null;
}

// 5. STOP TRACKING WHEN RIDE STARTS
// ==================================

_socketService.on('ride:started', (data) {
  if (!mounted) return;
  
  // STOP TRACKING: Emit ride:stopTracking
  if (_currentDriverId != null) {
    _socketService.stopTrackingDriver(_currentDriverId!);
  }
  
  // Stop ETA updates (no longer needed)
  _stopETAUpdates();
  
  setState(() {
    _rideStatus = 'in_progress';
    _updateMarkers();
    _fetchNavigationRoute(); // Switch to navigation to dropoff
  });
});

// 6. CLEANUP ON DISPOSE
// ======================

@override
void dispose() {
  // Stop ETA updates
  _stopETAUpdates();
  
  // Stop tracking and leave driver room
  if (_currentDriverId != null) {
    _socketService.stopTrackingDriver(_currentDriverId!);
    _socketService.leaveDriverRoom(_currentDriverId!);
  }
  
  // Clean up other subscriptions
  _interpolationSubscription?.cancel();
  _markerInterpolation?.dispose();
  _connectionSubscription?.cancel();
  
  super.dispose();
}

// 7. UI DISPLAY
// =============

// Show ETA with traffic data
if (_rideStatus == 'accepted') ...[
  Text(
    _etaMinutes > 0 
      ? '$_etaMinutes mins away · $_etaText'
      : 'Calculating ETA...',
    style: TextStyle(
      fontSize: 13,
      color: Colors.orange[700],
      fontWeight: FontWeight.w500,
    ),
  ),
]

// ====================================================
// SOCKET SERVICE METHODS (socket_service.dart)
// ====================================================

/// Start tracking driver location in real-time
void startTrackingDriver(String driverId) {
  if (driverId.isEmpty) return;
  emit('ride:trackDriver', {'driverId': driverId});
  debugPrint('🎯 Started tracking driver: $driverId');
}

/// Stop tracking driver location
void stopTrackingDriver(String driverId) {
  if (driverId.isEmpty) return;
  emit('ride:stopTracking', {'driverId': driverId});
  debugPrint('🛑 Stopped tracking driver: $driverId');
}

// ====================================================
// SUMMARY OF SOCKET EVENTS
// ====================================================

/*
CLIENT TO SERVER:
- ride:trackDriver { driverId: string }  // Start tracking
- ride:stopTracking { driverId: string } // Stop tracking

SERVER TO CLIENT:
- driver:locationChanged { 
    location: { 
      coordinates: [lng, lat] 
    } 
  }
*/
