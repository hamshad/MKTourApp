# iOS Socket Fix Guide - ride:started Event

## Problem
The `ride:started` socket event was working on Android but not on iOS.

## Root Causes Identified

1. **iOS Background Mode Restrictions**
   - iOS suspends network connections when app goes to background
   - No `UIBackgroundModes` were configured

2. **Socket Transport Configuration**
   - Using both 'websocket' and 'polling' transports can cause issues on iOS
   - iOS performs better with websocket-only connections

3. **App Lifecycle Management**
   - No handling for app resume/background transitions
   - Socket not reconnecting when app returns from background

## Changes Made

### 1. Socket Service (`lib/core/services/socket_service.dart`)

#### a. Optimized Transport for iOS
```dart
// Changed from: .setTransports(['websocket', 'polling'])
// To: .setTransports(['websocket']) // Websocket-only for better iOS stability
```

#### b. Added App Lifecycle Observer
```dart
class SocketService with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Reconnect socket if disconnected when app returns to foreground
        if (_socket == null || !_socket!.connected) {
          _attemptReconnection();
        }
        break;
      // ... other states
    }
  }
}
```

#### c. Platform-Specific Timeout
```dart
.setTimeout(isIOS ? 30000 : 20000) // Longer timeout for iOS
```

#### d. Enhanced Logging
- Added platform detection logs
- Added transport type logging
- Added connection status in listener registration

### 2. iOS Info.plist (`ios/Runner/Info.plist`)

Added background modes to allow socket connections:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
    <string>location</string>
</array>
```

### 3. Ride Assigned Screen (`lib/features/ride/ride_assigned_screen.dart`)

Enhanced `ride:started` event handler with:
- Platform detection logging
- Widget mount state verification
- Detailed callback logging
- Error context tracking

## Testing Steps

### On iOS Device/Simulator

1. **Clean Build**
   ```bash
   flutter clean
   cd ios
   pod deintegrate
   pod install
   cd ..
   flutter run
   ```

2. **Test Scenarios**

   **Scenario A: App in Foreground**
   - Accept a ride
   - Have driver start the ride
   - Check console for logs:
     ```
     🚀 [RideAssignedScreen] RIDE STARTED EVENT RECEIVED
     📦 [RideAssignedScreen] Platform: iOS=true, Android=false
     ```

   **Scenario B: App in Background**
   - Accept a ride
   - Put app in background (home button/swipe up)
   - Have driver start the ride
   - Bring app to foreground
   - Check logs for:
     ```
     📱 [SocketService] App resumed - checking socket connection...
     🔄 [SocketService] Socket disconnected, attempting reconnection...
     🟢 [SocketService] Connected to [baseUrl]
     🚀 [RideAssignedScreen] RIDE STARTED EVENT RECEIVED
     ```

   **Scenario C: Network Interruption**
   - Accept a ride
   - Turn airplane mode ON for 5 seconds
   - Turn airplane mode OFF
   - Have driver start the ride
   - Verify reconnection and event reception

3. **Key Logs to Monitor**

   On successful connection:
   ```
   🟢 [SocketService] Connected to [baseUrl]
   🟢 [SocketService] Platform: iOS=true, Android=false
   🟢 [SocketService] Transport: websocket
   ```

   When listener is registered:
   ```
   👂 [SocketService] Listening for: ride:started (iOS=true, Connected=true)
   ```

   When event is received:
   ```
   📨 [SocketService] INCOMING EVENT: ride:started, Data: {...}
   🚀 [RideAssignedScreen] RIDE STARTED EVENT RECEIVED
   ✅ [RideAssignedScreen] Updating UI to in_progress state
   ```

## Debugging Checklist

If `ride:started` still not working on iOS:

- [ ] Check socket connection status: `🟢 [SocketService] Connected`
- [ ] Verify transport type: `Transport: websocket`
- [ ] Confirm listener registered: `👂 [SocketService] Listening for: ride:started`
- [ ] Check wildcard listener catches event: `📨 [SocketService] INCOMING EVENT: ride:started`
- [ ] Verify widget is mounted: `Mounted: true`
- [ ] Check app lifecycle state: Should be `resumed` or `inactive`
- [ ] Confirm backend is sending to correct user ID
- [ ] Verify auth token is valid in socket headers

## Common Issues & Solutions

### Issue 1: Socket not reconnecting after background
**Solution**: The lifecycle observer should handle this now. Check logs for:
```
📱 [SocketService] App resumed - checking socket connection...
```

### Issue 2: Events received but handler not called
**Check**: Widget mount state and ensure socket listener setup happens in `initState` or `didChangeDependencies`

### Issue 3: Backend shows event sent but client doesn't receive
**Check**: 
- User ID match between backend and client
- Socket room joined correctly
- Auth token valid

### Issue 4: Works on first launch but fails after app restart
**Solution**: Clear token and force fresh connection:
```dart
await _socketService.initSocket(forceReconnect: true);
```

## Backend Verification

Ensure backend is emitting correctly:
```javascript
// Backend should log:
[Socket Out] User:6957c70aa0010d89bf99975b | Event: ride:started | Payload: {...}
✅ User 6957c70aa0010d89bf99975b notified that ride has started
```

## Additional Notes

- **Xcode Console**: Use Xcode console for more detailed iOS system logs
- **Network Debugging**: Use Charles Proxy or Proxyman to inspect WebSocket traffic
- **Background Fetch**: Test with Background Fetch capability if implementing background updates
- **Battery Optimization**: iOS may throttle background connections on low battery

## Rollback Plan

If issues persist, revert to polling transport:
```dart
.setTransports(['polling', 'websocket'])
```

This is less efficient but more compatible with iOS restrictions.
