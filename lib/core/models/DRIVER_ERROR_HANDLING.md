# 🚗 Driver-Specific Error Handling Guide

## Overview

This guide covers error handling for driver-specific API endpoints and special error codes that require custom UI handling.

## Driver Exception Class

`DriverException` extends `ApiError` with driver-specific helper methods.

### Methods Available

```dart
// Profile status checks
isProfileIncomplete() → bool
isNotApproved() → bool

// Get error details
getErrorCode() → String?

// Document checks
isMissingVehicleImages() → bool
isMissingLicense() → bool
isMissingVehicleDetails() → bool

// Image validation
isMaxImagesExceeded() → bool
```

### Inherited from ApiError

```dart
getUserMessage() → String
isError(String pattern) → bool
getDistanceDetails() → Map<String, int>?
getAttemptsRemaining() → int?
isOtpExpired() → bool
```

---

## Special Error Codes

### Profile Status Errors

#### PROFILE_INCOMPLETE
```json
{
  "success": false,
  "message": "Please complete your profile by uploading vehicle images, license document, and vehicle details before going online.",
  "errors": {
    "code": "PROFILE_INCOMPLETE"
  }
}
```

**Handling:**
```dart
try {
  await apiService.goOnline();
} on DriverException catch (e) {
  if (e.isProfileIncomplete()) {
    // Show dialog with missing items
    DriverErrorHandler.handleProfileStatusError(context, e);
  }
}
```

**UI:** Shows dialog listing what's missing (images, license, vehicle details)

#### NOT_APPROVED
```json
{
  "success": false,
  "message": "Your account is not approved yet. Please wait for admin approval.",
  "errors": {
    "code": "NOT_APPROVED"
  }
}
```

**Handling:**
```dart
try {
  await apiService.goOnline();
} on DriverException catch (e) {
  if (e.isNotApproved()) {
    // Show awaiting approval dialog
    DriverErrorHandler.handleProfileStatusError(context, e);
  }
}
```

**UI:** Shows non-dismissible dialog explaining account is under review

---

## Driver Endpoint Error Handling

### Profile Endpoints

#### GET /me - Get Profile
```dart
try {
  final response = await apiService.getDriverProfile();
} on DriverException catch (e) {
  if (e.isError('driver not found')) {
    // Navigate to re-login
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }
}
```

#### PATCH /update - Update Profile
```dart
try {
  final response = await apiService.updateDriverProfile(data);
} on DriverException catch (e) {
  ErrorDisplayHelper.showErrorSnackbar(context, e.getUserMessage());
}
```

#### PATCH /status - Go Online/Offline
```dart
try {
  final response = await apiService.updateDriverStatus(true); // true = online
} on DriverException catch (e) {
  DriverErrorHandler.handleProfileStatusError(context, e);
}
```

**Error Cases:**
- `PROFILE_INCOMPLETE` → Show profile completion dialog
- `NOT_APPROVED` → Show pending approval message
- `isOnline must be a boolean` → Validation error

#### PATCH /location - Update Location
```dart
try {
  final response = await apiService.updateDriverLocation(lat, lng);
} on DriverException catch (e) {
  DriverErrorHandler.handleLocationError(context, e);
}
```

**Error Cases:**
- `Invalid coordinates` → "Please enable GPS and try again"
- `Driver not found` → Re-login required

---

### Vehicle Image Endpoints

#### POST /upload-vehicle-images - Append Images
```dart
try {
  final response = await apiService.uploadVehicleImages(imageFiles);
} on DriverException catch (e) {
  DriverErrorHandler.handleImageUploadError(context, e);
}
```

**Error Cases:**
```dart
// No images uploaded
{ "message": "No vehicle images uploaded" }

// Max images exceeded
{ "message": "Cannot upload 3 images. You already have 4 images. Maximum 5 images allowed." }
  → isMaxImagesExceeded() returns true

// Driver not found
{ "message": "Driver not found" }
```

#### POST /replace-vehicle-images - Replace All
```dart
try {
  final response = await apiService.replaceAllVehicleImages(imageFiles);
} on DriverException catch (e) {
  DriverErrorHandler.handleImageUploadError(context, e);
}
```

**Error Cases:**
```dart
// No images uploaded
{ "message": "No vehicle images uploaded" }

// Exceeds maximum
{ "message": "Cannot upload 7 images. Maximum 5 images allowed." }
```

#### DELETE /delete-vehicle-image - Delete Single Image
```dart
try {
  final response = await apiService.deleteVehicleImage(publicId);
} on DriverException catch (e) {
  if (e.isError('publicid')) {
    ErrorDisplayHelper.showErrorSnackbar(context, 'Missing image ID');
  } else if (e.isError('not found')) {
    ErrorDisplayHelper.showErrorSnackbar(context, 'Image not found');
  }
}
```

---

### License & Document Endpoints

#### POST /upload-license - Upload License Document
```dart
try {
  final response = await apiService.uploadLicenseDocument(file);
} on DriverException catch (e) {
  if (e.isMissingLicense()) {
    ErrorDisplayHelper.showErrorSnackbar(context, 'Please select a license document');
  } else {
    ErrorDisplayHelper.showErrorSnackbar(context, e.getUserMessage());
  }
}
```

---

### Ride Operations

#### POST /accept - Accept Ride
```dart
try {
  final response = await apiService.acceptRide(rideId);
} on DriverException catch (e) {
  DriverErrorHandler.handleRideAcceptanceError(context, e);
}
```

**Error Cases:**
```dart
"Ride is not available" → Not available anymore
"Ride request has expired" → Too late to accept
"Ride not found" → Invalid ride ID
"Driver not found" → Re-login required
```

#### POST /arrive - Arrive at Pickup
```dart
try {
  final response = await apiService.arriveAtPickup(rideId, lat, lng);
} on DriverException catch (e) {
  DriverErrorHandler.handleArriveError(context, e);
}
```

**Error Cases:**
```dart
// Distance error with details
{
  "message": "Driver is not close enough to pickup location",
  "errors": { "distance": 250, "required": 200 }
}
→ getDistanceDetails() returns {current: 250, required: 200}

// Invalid coordinates
"Latitude and longitude are required" → Use GPS fallback

// Wrong ride state
"Ride must be in accepted status" → Ride state changed
```

#### POST /start - Start Ride
```dart
try {
  final response = await apiService.startRide(rideId, otp);
} on DriverException catch (e) {
  DriverErrorHandler.handleStartRideError(context, e);
}
```

**Error Cases:**
```dart
// OTP errors
"OTP is required"
"Invalid OTP" with errors: { "attemptsRemaining": 2 }
  → isError('invalid otp') true
  → getAttemptsRemaining() returns 2

// OTP expired
"OTP expired. New OTP generated." with errors: { "expired": true }
  → isOtpExpired() returns true

// Too many attempts
"Too many failed OTP attempts" → Disable retry for some time

// Location/state errors
"You must arrive at pickup location first"
"User must select payment method before ride can start"
```

#### POST /complete - Complete Ride
```dart
try {
  final response = await apiService.completeRide(rideId, lat, lng);
} on DriverException catch (e) {
  DriverErrorHandler.handleCompleteRideError(context, e);
}
```

**Error Cases:**
```dart
// Distance error
{
  "message": "Driver is not close enough to dropoff location",
  "errors": { "distance": 150, "required": 100 }
}

// Invalid state
"Ride must be in progress to complete"

// Location issues
"Latitude and longitude are required to complete ride"
```

#### POST /cancel/driver - Cancel Ride
```dart
try {
  final response = await apiService.cancelRideByDriver(rideId, reason);
} on DriverException catch (e) {
  DriverErrorHandler.handleCancelRideError(context, e);
}
```

**Error Cases:**
```dart
"Cancellation reason is required" → Validation error
"Not authorized to cancel this ride" → Permission issue
"Cannot cancel ride after it has started. Use "End Ride" instead."
  → isError('already started') true
"Invalid cancellation reason" → Bad reason format
```

#### POST /end-early - End Ride Early
```dart
try {
  final response = await apiService.endRideEarly(rideId, reason, lat, lng);
} on DriverException catch (e) {
  DriverErrorHandler.handleCompleteRideError(context, e);
}
```

**Error Cases:**
```dart
"Latitude and longitude are required"
"Early end reason is required"
"Not authorized to end this ride"
"Ride must be in progress to end early"
```

#### POST /confirm-cash - Confirm Cash Collection
```dart
try {
  final response = await apiService.confirmCashCollection(rideId);
} on DriverException catch (e) {
  if (e.isError('must be completed')) {
    ErrorDisplayHelper.showErrorSnackbar(context, 'Complete ride first');
  } else if (e.isError('not a cash payment')) {
    ErrorDisplayHelper.showErrorSnackbar(context, 'Ride is not cash payment');
  }
}
```

---

## Usage Patterns

### Pattern 1: Simple Error Display
```dart
try {
  await apiService.doSomething();
} on DriverException catch (e) {
  ErrorDisplayHelper.showErrorSnackbar(context, e.getUserMessage());
}
```

### Pattern 2: Status-Based Handling
```dart
try {
  await apiService.goOnline();
} on DriverException catch (e) {
  if (e.isProfileIncomplete()) {
    showProfileDialog();
  } else if (e.isNotApproved()) {
    showAwaitingApprovalDialog();
  } else {
    showErrorSnackbar(e.getUserMessage());
  }
}
```

### Pattern 3: Using Specific Handlers
```dart
try {
  await apiService.arriveAtPickup(rideId, lat, lng);
} on DriverException catch (e) {
  DriverErrorHandler.handleArriveError(context, e);
}
```

### Pattern 4: Message Pattern Matching
```dart
try {
  await apiService.someMethod();
} on DriverException catch (e) {
  if (e.isError('pattern')) {
    // Handle specific message pattern
  } else if (e.isError('another pattern')) {
    // Handle another pattern
  } else {
    // Generic handling
  }
}
```

---

## Error Code Reference

| Code | Message | Action | UI |
|------|---------|--------|-----|
| PROFILE_INCOMPLETE | Missing profile items | Show items needed | Dialog |
| NOT_APPROVED | Awaiting approval | Show pending message | Dialog |
| (none) | Driver not found | Re-login | Navigation |
| (none) | Invalid coordinates | Enable GPS | Snackbar |
| (none) | Not close enough | Show distance needed | Snackbar |
| (none) | Invalid OTP | Show attempts | Snackbar |
| (none) | OTP expired | New OTP sent | Snackbar |
| (none) | Max images exceeded | Delete old images | Snackbar |
| (none) | Ride not available | Show unavailable | Snackbar |
| (none) | Can't cancel started | Use end ride | Snackbar |

---

## UI/UX Guidelines

### Dialog vs Snackbar
- **Dialog**: Critical actions (profile incomplete, not approved, confirm cash)
- **Snackbar**: Warnings & info (OTP expired, ride unavailable, distance)

### Color Coding
- **Error (Red)**: Action required, operation failed
- **Warning (Orange)**: Attention needed, retry possible
- **Info (Blue)**: Operational information

### Recovery Actions
- **OTP Expired**: Offer resend immediately
- **Profile Incomplete**: Link to completion screen
- **Not Approved**: Show support contact info
- **Distance Error**: Offer continue button
- **Ride Unavailable**: Refresh ride list

---

## Testing Error Scenarios

```dart
// Test profile incomplete
void testProfileIncomplete() {
  final error = DriverException(
    message: 'Please complete your profile...',
    errors: {'code': 'PROFILE_INCOMPLETE'},
    statusCode: 403,
  );
  expect(error.isProfileIncomplete(), true);
}

// Test not approved
void testNotApproved() {
  final error = DriverException(
    message: 'Your account is not approved yet...',
    errors: {'code': 'NOT_APPROVED'},
    statusCode: 403,
  );
  expect(error.isNotApproved(), true);
}

// Test distance error
void testDistanceError() {
  final error = DriverException(
    message: 'Driver is not close enough...',
    errors: {'distance': 250, 'required': 200},
    statusCode: 400,
  );
  final details = error.getDistanceDetails();
  expect(details?['current'], 250);
  expect(details?['required'], 200);
}
```

---

## Best Practices

1. **Always use DriverErrorHandler for driver endpoints** - Provides consistent UX
2. **Check error codes before messages** - More reliable than string matching
3. **Show specific messages** - Don't use generic "Something went wrong"
4. **Offer recovery actions** - Resend OTP, complete profile, refresh list
5. **Use appropriate UI elements** - Dialog for critical, snackbar for info
6. **Log all errors** - Track patterns in analytics
7. **Test all error paths** - Edge cases matter for UX

---

## Summary

Driver error handling includes:
- ✅ Profile status errors (incomplete, not approved)
- ✅ Image upload validation
- ✅ Location & GPS errors
- ✅ Ride operation errors
- ✅ OTP verification
- ✅ Authorization checks
- ✅ Special UI handling for critical cases

All errors are properly parsed, classified, and ready for display!
