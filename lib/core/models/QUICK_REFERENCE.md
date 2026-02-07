# Error Handling Quick Reference

## 1. Common Error Messages from Backend

### Auth Errors
```
"Phone number is required"
"Invalid phone number format"
"Failed to send OTP. Please try again."
"No token provided. Authorization denied."
"User not found. Authorization denied."
"Invalid token. Authorization denied."
```

### OTP Errors
```
"Phone number and OTP are required"
"Invalid OTP" (with attemptsRemaining: X)
"OTP has expired" (with expired: true)
"Too many failed OTP attempts"
```

### Ride Errors
```
"Pickup and dropoff locations are required"
"Ride is not available"
"Ride not found"
"Ride request has expired"
"Driver is not close enough to pickup location" (with distance, required)
"Ride must be in accepted status"
"You must arrive at pickup location first"
"Cannot cancel ride after it has started"
"Payment method already selected for this ride"
```

## 2. Quick Import Guide

```dart
// In screens/providers that handle errors
import 'package:mk_tour_app/core/models/api_error.dart';
import 'package:mk_tour_app/core/models/error_display_helper.dart';

// Note: api_service.dart already imports these
```

## 3. Basic Error Handling Pattern

```dart
// Pattern 1: Catch specific errors
try {
  final response = await apiService.someMethod();
  if (response['success']) {
    // Handle success
  }
} on AuthException catch (e) {
  // Handle auth error
  ErrorDisplayHelper.showErrorSnackbar(context, e.getUserMessage());
} on RideException catch (e) {
  // Handle ride error
  ErrorDisplayHelper.handleRideError(context, e);
} on ApiError catch (e) {
  // Handle generic API error
  ErrorDisplayHelper.handleApiError(context, e);
} catch (e) {
  // Handle unexpected error
  ErrorDisplayHelper.showErrorSnackbar(context, 'An error occurred');
}
```

## 4. Special Error Cases

### OTP Error with Attempts
```dart
} on ApiError catch (e) {
  if (e.isError('invalid otp')) {
    final remaining = e.getAttemptsRemaining();
    if (remaining != null && remaining > 0) {
      ErrorDisplayHelper.showErrorSnackbar(
        context,
        'Invalid OTP. $remaining attempts remaining.',
      );
    }
  }
}
```

### OTP Expired
```dart
} on ApiError catch (e) {
  if (e.isOtpExpired()) {
    ErrorDisplayHelper.showWarningSnackbar(
      context,
      'OTP expired. A new one has been sent.',
    );
  }
}
```

### Distance Error
```dart
} on RideException catch (e) {
  if (e.isError('not close enough')) {
    final distanceDetails = e.getDistanceDetails();
    if (distanceDetails != null) {
      final current = distanceDetails['current'];
      final required = distanceDetails['required'];
      ErrorDisplayHelper.showWarningSnackbar(
        context,
        'You are ${current}m away. Get within ${required}m.',
      );
    }
  }
}
```

### Auth Token Error
```dart
} on AuthException catch (e) {
  if (e.isAuthError()) {
    // Logout user and redirect to login
    await authProvider.logout();
    Navigator.pushNamed(context, '/login');
  }
}
```

## 5. Error Display Methods

```dart
// Show error dialog
ErrorDisplayHelper.showErrorDialog(
  context: context,
  title: 'Error',
  message: 'Failed to book ride',
);

// Show error snackbar
ErrorDisplayHelper.showErrorSnackbar(context, 'Error occurred');

// Show warning snackbar
ErrorDisplayHelper.showWarningSnackbar(context, 'Warning message');

// Show success snackbar
ErrorDisplayHelper.showSuccessSnackbar(context, 'Success!');

// Auto-handle API error
ErrorDisplayHelper.handleApiError(context, error);

// Show error widget
ErrorDisplayHelper.buildErrorWidget(
  message: 'Failed to load',
  onRetry: () => retry(),
);
```

## 6. Error Checking Methods

```dart
ApiError error = ...;

// Type checks
error.isAuthError()          // true if auth/token error
error.isServerError()        // true if 5xx
error.isNetworkError()       // true if network error
error.isNotFoundError()      // true if 404

// Message checks
error.isError('keyword')     // Case-insensitive substring match
error.isOtpExpired()         // true if OTP expired
error.getUserMessage()       // Get display-friendly message

// Extract details
error.getAttemptsRemaining() // int?
error.getDistanceDetails()   // {current: int, required: int}?
error.getErrorDetails('key') // dynamic
```

## 7. Provider/ViewModel Pattern

```dart
class AuthProvider with ChangeNotifier {
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Future<bool> sendOtp(String phone) async {
    try {
      final response = await _apiService.sendOtp(phone);
      if (response['success']) {
        _errorMessage = null;
        return true;
      }
      return false;
    } on ApiError catch (e) {
      _errorMessage = e.getUserMessage();
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'An unexpected error occurred';
      notifyListeners();
      return false;
    }
  }
}
```

## 8. Error Codes Map

| Code | Type | Meaning | Recoverable |
|------|------|---------|---|
| 400 | ValidationException | Bad input | Yes |
| 401 | AuthException | Invalid token | No* |
| 404 | ApiError | Not found | Yes |
| 500-599 | ServerException | Server error | Yes |
| Network | NetworkException | No connection | Yes |

*Requires re-authentication

## 9. Common Implementation Locations

- **Auth flow**: `lib/features/auth/`
- **Ride booking**: `lib/features/ride_booking/`
- **Ride tracking**: `lib/features/ride_tracking/`
- **Providers**: `lib/core/auth_provider.dart`, etc.
- **Error handling**: `lib/core/models/`

## 10. Testing Error Handling

```dart
void testOtpError() {
  final error = ApiError.fromJson({
    'success': false,
    'message': 'Invalid OTP',
    'errors': {'attemptsRemaining': 2}
  }, 400);

  expect(error.getMessage(), 'Invalid OTP');
  expect(error.getAttemptsRemaining(), 2);
  expect(error.isAuthError(), false);
  expect(error.isError('invalid'), true);
}
```

## 11. Don't Forget

- Always catch `AuthException` before `ApiError`
- Use `getUserMessage()` for displaying to users
- Check specific error details before showing generic message
- Provide retry option for recoverable errors
- Log errors for debugging
- Test with real error responses from backend
- Update API methods gradually, not all at once
- Keep user messages simple and actionable
