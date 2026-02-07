# 🚗 Driver Error Handling - Quick Reference

## Import

```dart
import 'package:mk_tour_app/core/models/api_error.dart';
import 'package:mk_tour_app/core/models/driver_error_handler.dart';
import 'package:mk_tour_app/core/models/error_display_helper.dart';
```

---

## Special Error Codes

```dart
// Check for special codes
if (error.getErrorCode() == 'PROFILE_INCOMPLETE') {
  // Show profile completion dialog
}

if (error.getErrorCode() == 'NOT_APPROVED') {
  // Show pending approval message
}
```

---

## Driver Exception Methods

```dart
DriverException error = ...;

// Profile status
error.isProfileIncomplete()        // PROFILE_INCOMPLETE code
error.isNotApproved()              // NOT_APPROVED code
error.getErrorCode()               // Get the error code string

// Document checks
error.isMissingVehicleImages()    // Check vehicle images missing
error.isMissingLicense()          // Check license missing
error.isMissingVehicleDetails()   // Check vehicle details missing

// Image validation
error.isMaxImagesExceeded()       // Max 5 images limit

// Inherited from ApiError
error.getDistanceDetails()         // {current, required}
error.getAttemptsRemaining()       // OTP attempts left
error.isOtpExpired()              // OTP expired status
error.isError('text')             // Pattern match in message
```

---

## Handler Methods

### Profile Status
```dart
// Handles both PROFILE_INCOMPLETE and NOT_APPROVED
DriverErrorHandler.handleProfileStatusError(context, error);

// Shows:
// - INCOMPLETE: Dialog with missing items list
// - NOT_APPROVED: Non-dismissible pending dialog
```

### Location
```dart
DriverErrorHandler.handleLocationError(context, error);

// Handles:
// - Invalid coordinates → "Enable GPS"
// - Driver not found → "Re-login"
```

### Image Upload
```dart
DriverErrorHandler.handleImageUploadError(context, error);

// Handles:
// - Max exceeded → "Delete old images first"
// - No images → "Select at least one image"
```

### Ride Acceptance
```dart
DriverErrorHandler.handleRideAcceptanceError(context, error);

// Handles:
// - Not available
// - Expired
// - Not found
```

### Arrive at Pickup
```dart
DriverErrorHandler.handleArriveError(context, error);

// Handles:
// - Distance with details → Shows current vs required
// - Invalid coordinates → "Enable GPS"
// - Wrong state
```

### Start Ride
```dart
DriverErrorHandler.handleStartRideError(context, error);

// Handles:
// - OTP expired → "New OTP sent"
// - Invalid OTP → "X attempts remaining"
// - Too many attempts → "Try again later"
// - Must arrive first
// - Payment not selected
```

### Complete Ride
```dart
DriverErrorHandler.handleCompleteRideError(context, error);

// Handles:
// - Not close enough → Shows distance needed
// - Wrong state
// - Invalid coordinates
```

### Cancel Ride
```dart
DriverErrorHandler.handleCancelRideError(context, error);

// Handles:
// - Already started → "Use End Ride"
// - Not authorized
// - Invalid reason
```

---

## Common Patterns

### Pattern 1: Go Online with Profile Check
```dart
try {
  await _apiService.updateDriverStatus(true);
} on DriverException catch (e) {
  if (e.isProfileIncomplete()) {
    DriverErrorHandler.handleProfileStatusError(context, e);
  } else if (e.isNotApproved()) {
    DriverErrorHandler.handleProfileStatusError(context, e);
  } else {
    ErrorDisplayHelper.showErrorSnackbar(context, e.getUserMessage());
  }
}
```

### Pattern 2: Upload Images with Validation
```dart
try {
  await _apiService.uploadVehicleImages(files);
  ErrorDisplayHelper.showSuccessSnackbar(context, 'Images uploaded');
} on DriverException catch (e) {
  DriverErrorHandler.handleImageUploadError(context, e);
}
```

### Pattern 3: Accept Ride
```dart
try {
  await _apiService.acceptRide(rideId);
  setState(() => _rideAccepted = true);
} on DriverException catch (e) {
  DriverErrorHandler.handleRideAcceptanceError(context, e);
}
```

### Pattern 4: Arrive at Location
```dart
try {
  await _apiService.arriveAtPickup(rideId, lat, lng);
  _showArrivedNotification();
} on DriverException catch (e) {
  DriverErrorHandler.handleArriveError(context, e);
}
```

### Pattern 5: Start Ride with OTP
```dart
try {
  await _apiService.startRide(rideId, otpCode);
  Navigator.pushReplacementNamed(context, '/ride-progress');
} on DriverException catch (e) {
  DriverErrorHandler.handleStartRideError(context, e);
}
```

### Pattern 6: Complete Ride
```dart
try {
  await _apiService.completeRide(rideId, lat, lng);
  ErrorDisplayHelper.showSuccessSnackbar(context, 'Ride completed');
  Navigator.pop(context);
} on DriverException catch (e) {
  DriverErrorHandler.handleCompleteRideError(context, e);
}
```

---

## Error Code Reference

| Code | Handler | UI |
|------|---------|-----|
| PROFILE_INCOMPLETE | handleProfileStatusError | Dialog with items |
| NOT_APPROVED | handleProfileStatusError | Pending approval |
| (distance error) | handleArriveError | Distance warning |
| (invalid OTP) | handleStartRideError | Attempts remaining |
| (OTP expired) | handleStartRideError | New OTP sent |
| (max images) | handleImageUploadError | Delete images first |
| (ride unavailable) | handleRideAcceptanceError | Not available |

---

## Checking Specific Errors

```dart
// Check error message contains pattern
if (error.isError('not close enough')) {
  // Handle distance error
}

if (error.isError('invalid otp')) {
  final remaining = error.getAttemptsRemaining();
}

if (error.isError('otp expired')) {
  // New OTP sent
}

if (error.isError('already started')) {
  // Use End Ride instead
}

if (error.isError('driver not found')) {
  // Re-login required
}
```

---

## UI Display Quick Ref

```dart
// Simple error
ErrorDisplayHelper.showErrorSnackbar(context, 'Message');

// Warning (orange background)
ErrorDisplayHelper.showWarningSnackbar(context, 'Message');

// Success (green background)
ErrorDisplayHelper.showSuccessSnackbar(context, 'Message');

// Dialog
ErrorDisplayHelper.showErrorDialog(
  context: context,
  title: 'Title',
  message: 'Message',
  actionLabel: 'Retry',
  onAction: () => retry(),
);
```

---

## Special Cases

### Profile Incomplete → Complete Profile
```dart
if (error.isProfileIncomplete()) {
  // Show which items are missing
  if (error.isMissingVehicleImages()) { /* */ }
  if (error.isMissingLicense()) { /* */ }
  if (error.isMissingVehicleDetails()) { /* */ }
  
  // Navigate to profile completion
  Navigator.pushNamed(context, '/complete-profile');
}
```

### Not Approved → Show Patience Message
```dart
if (error.isNotApproved()) {
  showDialog(
    // Show non-dismissible dialog
    // Option to contact support
    // Check approval status later
  );
}
```

### Distance Error → Show Specific Meters
```dart
final details = error.getDistanceDetails();
if (details != null) {
  final current = details['current'];  // 250
  final required = details['required']; // 200
  // "Get within ${required - current}m"
}
```

### OTP Attempts → Show Remaining
```dart
final remaining = error.getAttemptsRemaining();
if (remaining != null) {
  if (remaining == 0) {
    // Try again in X minutes
  } else {
    // "X attempts remaining"
  }
}
```

---

## Error Sources by Handler

| Handler | Used For |
|---------|----------|
| handleProfileStatusError | PATCH /status |
| handleLocationError | PATCH /location |
| handleImageUploadError | POST/DELETE vehicle images |
| handleRideAcceptanceError | POST /rides/:id/accept |
| handleArriveError | POST /rides/:id/arrive |
| handleStartRideError | POST /rides/:id/start |
| handleCompleteRideError | POST /rides/:id/complete |
| handleCancelRideError | POST /rides/:id/cancel/driver |

---

## Type Casting

```dart
// Check if error is driver-specific
if (error.isDriverError()) {
  final driverError = error.asDriverException();
  if (driverError?.isProfileIncomplete() == true) {
    // Handle profile incomplete
  }
}

// Cast directly (with null check)
if (error is DriverException) {
  if (error.isProfileIncomplete()) {
    // Handle
  }
}
```

---

## Common Messages

```dart
"Driver not found" → Re-login required
"Invalid coordinates" → Enable GPS
"Not close enough" → Move closer (with distance)
"Invalid OTP" → Try again (with attempts)
"OTP expired" → New OTP sent
"Already started" → Use End Ride instead
"Not authorized" → Permission denied
"Maximum 5 images" → Delete and retry
"Profile incomplete" → Show items needed
"Not approved yet" → Pending admin approval
```

---

## Testing Helpers

```dart
// Create test error
final error = DriverException(
  message: 'Please complete your profile...',
  errors: {'code': 'PROFILE_INCOMPLETE'},
  statusCode: 403,
);

// Test
assert(error.isProfileIncomplete());
assert(error.getErrorCode() == 'PROFILE_INCOMPLETE');
```

---

## Summary Checklist

✅ Import driver error handler
✅ Check for special codes (PROFILE_INCOMPLETE, NOT_APPROVED)
✅ Use specific handler methods
✅ Handle distance errors with details
✅ Show OTP attempts remaining
✅ Offer recovery actions
✅ Test all error paths
✅ Monitor error patterns

**Ready to handle all driver errors!** 🚗
