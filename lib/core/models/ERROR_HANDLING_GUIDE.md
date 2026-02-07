# API Error Handling Guide

This document explains how to use the error handling system in the Flutter app.

## Structure

### 1. **ApiError** (`api_error.dart`)
Base error class that parses backend error responses:
- `message`: User-friendly error message
- `errors`: Additional error details (distance, attempts, etc.)
- `statusCode`: HTTP status code
- `error`: Backend error details

### 2. **ApiErrorHandler** (`api_error_handler.dart`)
Utility for processing HTTP responses and throwing appropriate exceptions.

### 3. **ErrorDisplayHelper** (`error_display_helper.dart`)
Utility for displaying errors to users in the UI.

### 4. **Exception Classes**
- `AuthException`: Authentication/authorization errors
- `RideException`: Ride operation errors
- `PaymentException`: Payment operation errors
- `ValidationException`: Input validation errors
- `ServerException`: Server errors
- `NetworkException`: Network errors

## Usage Examples

### Basic API Call with Error Handling

```dart
try {
  final response = await _apiService.sendOtp(phoneNumber);
  if (response['success']) {
    // Handle success
  }
} on AuthException catch (e) {
  ErrorDisplayHelper.showErrorSnackbar(
    context,
    e.getUserMessage(),
  );
} on ApiError catch (e) {
  ErrorDisplayHelper.handleApiError(context, e);
} catch (e) {
  ErrorDisplayHelper.showErrorSnackbar(
    context,
    'An unexpected error occurred',
  );
}
```

### Handling OTP Errors

```dart
try {
  final response = await _apiService.verifyOtp(
    phone: phone,
    otp: otp,
    role: role,
  );
} on ApiError catch (e) {
  if (e.isOtpExpired()) {
    ErrorDisplayHelper.showWarningSnackbar(
      context,
      'OTP expired. A new one has been sent.',
    );
  } else {
    final remaining = e.getAttemptsRemaining();
    if (remaining != null) {
      ErrorDisplayHelper.showErrorSnackbar(
        context,
        'Invalid OTP. $remaining attempts remaining.',
      );
    }
  }
}
```

### Handling Ride Errors with Distance

```dart
try {
  final response = await _apiService.arriveAtPickup(rideId, lat, lng);
} on RideException catch (e) {
  final distanceDetails = e.getDistanceDetails();
  if (distanceDetails != null) {
    final current = distanceDetails['current'];
    final required = distanceDetails['required'];
    ErrorDisplayHelper.showWarningSnackbar(
      context,
      'You are ${current}m away. Get within ${required}m to proceed.',
    );
  }
}
```

### Error Display Options

```dart
// Show as error snackbar
ErrorDisplayHelper.showErrorSnackbar(context, message);

// Show as warning snackbar
ErrorDisplayHelper.showWarningSnackbar(context, message);

// Show as success snackbar
ErrorDisplayHelper.showSuccessSnackbar(context, message);

// Show as dialog
ErrorDisplayHelper.showErrorDialog(
  context: context,
  title: 'Error',
  message: message,
  actionLabel: 'Retry',
  onAction: () => retry(),
);

// Auto-handle API error
ErrorDisplayHelper.handleApiError(
  context,
  error,
  title: 'Failed to Send OTP',
  onRetry: () => resendOtp(),
);

// Build error widget for empty states
ErrorDisplayHelper.buildErrorWidget(
  message: 'Failed to load rides',
  onRetry: () => fetchRides(),
);
```

## Backend Error Response Formats

### Authentication Errors
```json
{
  "success": false,
  "message": "Invalid phone number format",
  "errors": null
}
```

### Ride Operation Errors with Details
```json
{
  "success": false,
  "message": "Driver is not close enough to pickup location",
  "errors": {
    "distance": 250,
    "required": 200
  }
}
```

### OTP Errors
```json
{
  "success": false,
  "message": "Invalid OTP",
  "errors": {
    "attemptsRemaining": 2
  }
}
```

```json
{
  "success": false,
  "message": "OTP expired. New OTP generated.",
  "errors": {
    "expired": true
  }
}
```

## Error Checking Methods

```dart
ApiError error = ...;

// Check error type
error.isAuthError()        // Checks if auth/token error
error.isNotFoundError()    // Checks if 404
error.isServerError()      // Checks if 5xx
error.isNetworkError()     // Checks if network issue

// Check error message
error.isError('message')   // Case-insensitive substring match

// Extract details
error.getDistanceDetails()      // Returns {current, required}
error.getAttemptsRemaining()    // Returns int?
error.isOtpExpired()            // Returns bool
error.getErrorDetails('key')    // Get specific error field
```

## Common Error Patterns

### Phone Validation
- "Phone number is required"
- "Invalid phone number format"

### OTP Handling
- "OTP is required"
- "Invalid OTP" (with attemptsRemaining)
- "OTP has expired" (with expired: true)
- "Too many failed OTP attempts"

### Ride Operations
- "Pickup and dropoff locations are required"
- "Ride is not available"
- "Ride has expired"
- "Driver is not close enough to location" (with distance details)
- "Cannot cancel ride after it has started"
- "Payment method can only be selected after driver arrives"

### Payment
- "Invalid payment method. Must be \"cash\" or \"payment_link\""
- "Payment already authorized"

### Authorization
- "No token provided. Authorization denied."
- "User not found. Authorization denied."
- "Invalid token. Authorization denied."

## Migration from Old Error Handling

### Old Way
```dart
try {
  final response = await api.sendOtp(phone);
  if (response.statusCode == 200) {
    // handle
  } else {
    throw Exception('Failed');
  }
} catch (e) {
  print(e);
}
```

### New Way
```dart
try {
  final response = await api.sendOtp(phone);
  if (response['success']) {
    // handle
  }
} on AuthException catch (e) {
  ErrorDisplayHelper.showErrorSnackbar(context, e.getUserMessage());
} on ApiError catch (e) {
  ErrorDisplayHelper.handleApiError(context, e);
}
```

## Best Practices

1. **Always catch specific exceptions first** - Catch `AuthException` before `ApiError`
2. **Use error display helpers** - Don't use basic print/showDialog, use the helpers
3. **Check error details** - Use methods like `getDistanceDetails()` before displaying
4. **Log for debugging** - The API service automatically logs errors
5. **Provide retry options** - For recoverable errors, offer retry
6. **Handle auth errors specially** - Logout user if needed
7. **Show appropriate UI messages** - Use `.getUserMessage()` for user-friendly text

## Testing Error Handling

```dart
// Test with mock errors
void testOtpError() {
  final error = ApiError.fromJson({
    'success': false,
    'message': 'Invalid OTP',
    'errors': {'attemptsRemaining': 2}
  }, 400);

  expect(error.getUserMessage(), 'Invalid OTP');
  expect(error.getAttemptsRemaining(), 2);
}
```
