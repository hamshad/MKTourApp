# Driver Tracking Implementation Guide

## Overview
This implementation adds real-time driver tracking with accurate ETA calculation using Google's Distance Matrix API with live traffic data.

## Features Implemented

### 1. **Real-Time Driver Tracking**
- Automatically starts when a ride is accepted
- Uses Socket.IO events to track driver location
- Smooth car marker animation on the map
- Stops tracking when ride starts (after OTP verification) or is cancelled

### 2. **Accurate ETA Calculation**
- Uses Google Distance Matrix API with live traffic data
- Updates every 20 seconds for real-time accuracy
- Shows "X mins away" to the passenger
- Calculates route-based travel time (not straight-line distance)

### 3. **Socket Events**
- `ride:trackDriver` - Start tracking driver location
- `ride:stopTracking` - Stop tracking driver location
- `driver:locationChanged` - Receive real-time location updates

---

## How It Works

### 1. **Start Tracking (When Ride is Accepted)**

```dart
// In ride_assigned_screen.dart - ride:accepted event handler
if (_currentDriverId != null) {
  // Start tracking driver location in real-time
  _socketService.startTrackingDriver(_currentDriverId!);
  
  // Start periodic ETA updates with real traffic data
  _startETAUpdates();
}
```

**Socket emission:**
```dart
socket.emit('ride:trackDriver', {'driverId': driverId});
```

### 2. **Listen for Location Updates**

```dart
_socketService.on('driver:locationChanged', (data) {
  var location = data['location'];
  var lat = location['coordinates'][1]; // Latitude is at index 1
  var lng = location['coordinates'][0]; // Longitude is at index 0

  // Update map marker with smooth animation
  final newPosition = LatLng(lat, lng);
  _markerInterpolation!.updatePosition(newPosition);
  
  // Navigation route updates automatically
  _updateNavigationRoute();
});
```

### 3. **Calculate ETA with Real Traffic**

```dart
Future<void> _calculateETA() async {
  // Use Distance Matrix API to get real-time travel time with traffic
  final result = await _placesService.getDistanceAndFare(
    originLat: _driverLocation!.latitude,
    originLng: _driverLocation!.longitude,
    destLat: _pickupLocation.latitude,
    destLng: _pickupLocation.longitude,
    categorySlug: 'car_4_seater',
  );

  if (result != null) {
    final durationSeconds = result['duration_seconds'];
    setState(() {
      _etaMinutes = (durationSeconds / 60).ceil();
      _etaText = result['duration_text'];
    });
  }
}
```

**Update frequency:** Every 20 seconds (balance between accuracy and API costs)

### 4. **Stop Tracking (When Ride Starts)**

```dart
// In ride_assigned_screen.dart - ride:started event handler
if (_currentDriverId != null) {
  _socketService.stopTrackingDriver(_currentDriverId!);
}
_stopETAUpdates();
```

**Socket emission:**
```dart
socket.emit('ride:stopTracking', {'driverId': driverId});
```

---

## API Integration

### Distance Matrix API Call
```dart
GET /api/v1/maps/distance-time?
    origin=DRIVER_LAT,DRIVER_LNG&
    destination=USER_LAT,USER_LNG&
    categorySlug=car_4_seater
```

**Response:**
```json
{
  "success": true,
  "data": {
    "distance_meters": 5280,
    "distance_text": "5.3 km",
    "duration_seconds": 420,
    "duration_text": "7 mins",
    "total_fare": 12.50
  }
}
```

---

## UI Display

The ETA is displayed in the ride status card:

```dart
Text(
  _etaMinutes > 0 
    ? '$_etaMinutes mins away · $_etaText'
    : 'Calculating ETA...',
  style: TextStyle(
    fontSize: 13,
    color: Colors.orange[700],
    fontWeight: FontWeight.w500,
  ),
)
```

**Example output:** "7 mins away · 7 mins"

---

## Socket Service Methods

### New Methods Added to `SocketService`

#### Start Tracking
```dart
void startTrackingDriver(String driverId) {
  emit('ride:trackDriver', {'driverId': driverId});
  debugPrint('🎯 Started tracking driver: $driverId');
}
```

#### Stop Tracking
```dart
void stopTrackingDriver(String driverId) {
  emit('ride:stopTracking', {'driverId': driverId});
  debugPrint('🛑 Stopped tracking driver: $driverId');
}
```

---

## Lifecycle Management

### When Tracking Starts:
1. User searches for a ride
2. Driver accepts the ride
3. `ride:accepted` event is received
4. App joins driver's location room: `driver:$driverId`
5. App emits `ride:trackDriver`
6. ETA timer starts (updates every 20s)

### When Tracking Stops:
1. Driver enters OTP and starts ride
2. `ride:started` event is received
3. App emits `ride:stopTracking`
4. ETA timer is cancelled
5. App leaves driver's location room

### Cleanup (On Screen Dispose):
```dart
@override
void dispose() {
  // Stop ETA updates
  _stopETAUpdates();
  
  // Stop tracking and leave driver room
  if (_currentDriverId != null) {
    _socketService.stopTrackingDriver(_currentDriverId!);
    _socketService.leaveDriverRoom(_currentDriverId!);
  }
  
  super.dispose();
}
```

---

## Best Practices

### 1. **API Cost Optimization**
- Update ETA every 20 seconds (not every location update)
- Stop updates when driver arrives or ride starts
- Use backend Distance Matrix API (secure and cost-controlled)

### 2. **Smooth User Experience**
- Use marker interpolation for smooth car animation
- Show "Calculating..." while ETA loads
- Fallback to navigation service ETA if Distance Matrix fails

### 3. **Error Handling**
```dart
try {
  final result = await _placesService.getDistanceAndFare(...);
  if (result != null && mounted) {
    // Update ETA
  }
} catch (e) {
  debugPrint('⚠️ Error calculating ETA: $e');
  // Continue with existing ETA or show fallback
}
```

### 4. **State Management**
- Only calculate ETA when `_rideStatus == 'accepted'`
- Check `mounted` before calling `setState`
- Cancel timers in dispose

---

## Testing Checklist

- [ ] Ride acceptance triggers tracking start
- [ ] ETA updates every 20 seconds with traffic data
- [ ] "X mins away" displays correctly in UI
- [ ] Car marker moves smoothly on map
- [ ] Tracking stops when ride starts
- [ ] Tracking stops when ride is cancelled
- [ ] ETA timer is cleaned up on screen dispose
- [ ] No memory leaks from timers or subscriptions

---

## Production Considerations

⚠️ **Important:** Distance Matrix API is called from the Flutter app but should eventually be moved to backend for:
- Better cost control and rate limiting
- Enhanced security
- Caching frequently requested routes
- Protection against API abuse

**Current setup:** Demo-grade (uses backend proxy but still client-initiated)
**Production recommendation:** Backend should proactively calculate ETA server-side

---

## Files Modified

1. **lib/core/services/socket_service.dart**
   - Added `startTrackingDriver()` method
   - Added `stopTrackingDriver()` method

2. **lib/features/ride/ride_assigned_screen.dart**
   - Added ETA calculation with Distance Matrix API
   - Added periodic ETA timer (20s interval)
   - Integrated tracking start/stop lifecycle
   - Updated UI to show traffic-based ETA

---

## Debug Logs

When testing, look for these console logs:

```
🎯 [SocketService] Started tracking driver: 123456
⏱️ [RideAssignedScreen] Started ETA updates (every 20s)
🕐 [RideAssignedScreen] Calculating ETA with traffic data...
🕐 [RideAssignedScreen] ETA updated: 7 mins (7 mins)
📍 [RideAssignedScreen] Driver Location Updated: {...}
🛑 [SocketService] Stopped tracking driver: 123456
⏱️ [RideAssignedScreen] Stopped ETA updates
```

---

## Summary

✅ **Implemented:**
- Real-time driver tracking with `ride:trackDriver` and `ride:stopTracking` events
- Accurate ETA calculation using Distance Matrix API with live traffic
- Periodic ETA updates every 20 seconds
- Smooth car marker animation
- Proper cleanup and lifecycle management

🎯 **Result:** Passengers now see accurate "X mins away" based on real traffic conditions, updating in real-time as the driver approaches!
