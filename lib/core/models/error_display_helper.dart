import 'package:flutter/material.dart';
import 'api_error.dart';

/// Severity of a mapped ride error — drives snackbar styling:
/// error → red (with retry action slot), info → neutral, success → green.
enum RideErrorSeverity { error, info }

/// Friendly copy + next action for one backend ride error.
///
/// Produced by [RideErrorMapper.map] — the single source of ride error copy.
/// Ride screens must use this instead of inventing per-screen messages.
class RideErrorInfo {
  final String title;
  final String copy;
  final String? actionLabel;
  final RideErrorSeverity severity;

  const RideErrorInfo({
    required this.title,
    required this.copy,
    this.actionLabel,
    this.severity = RideErrorSeverity.error,
  });

  bool get isInfo => severity == RideErrorSeverity.info;
}

/// Maps every backend message in the ride flow doc to friendly copy + action.
///
/// Covers: 100m proximity (pickup + stops, with actual/required distances),
/// wrong-state start/resume, invalid payment method, cancel-after-start,
/// missing reason, rating range, missing lat/lng, unavailable ride,
/// cash-before-complete, and the reassigned (info, not error) path.
class RideErrorMapper {
  static Map<String, dynamic>? _errorsMap(dynamic errors) {
    if (errors is Map<String, dynamic>) return errors;
    if (errors is Map) return Map<String, dynamic>.from(errors);
    return null;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Map a backend ride failure to display copy.
  ///
  /// [message] is the backend `message` string, [errors] the optional
  /// `errors` payload (carries `distance`/`required` for proximity errors).
  static RideErrorInfo map(String message, [dynamic errors]) {
    final lower = message.toLowerCase();
    final details = _errorsMap(errors);
    final distance = _asInt(details?['distance']);
    final required = _asInt(details?['required']) ?? 100;

    // 100m proximity — intermediate stop (name the stop when present).
    if (lower.contains('within 100 meters of stop') ||
        (lower.contains('within 100 meters') && lower.contains('stop #'))) {
      final where = distance != null
          ? "You're ${distance}m away — get within ${required}m"
          : 'Get within ${required}m of the stop';
      return RideErrorInfo(
        title: 'Too far from stop',
        copy: '$where to continue.',
        actionLabel: 'Retry when closer',
      );
    }

    // 100m proximity — pickup.
    if (lower.contains('within 100 meters')) {
      final where = distance != null
          ? "You're ${distance}m away — get within ${required}m"
          : 'Get within ${required}m of the pickup';
      return RideErrorInfo(
        title: 'Too far from pickup',
        copy: '$where to proceed.',
        actionLabel: 'Retry when closer',
      );
    }

    if (lower.contains('must be in driver_arrived state')) {
      return const RideErrorInfo(
        title: 'Not ready to start',
        copy: 'The ride must be in driver-arrived state. '
            'Confirm arrival first, then start the trip.',
        actionLabel: 'Confirm arrival first',
      );
    }

    if (lower.contains('must be at a stop to resume')) {
      return const RideErrorInfo(
        title: 'Not at a stop',
        copy: 'The ride must be at a stop to resume. '
            'Arrive at the stop first.',
        actionLabel: 'Check stop status',
      );
    }

    if (lower.contains('invalid payment method')) {
      return const RideErrorInfo(
        title: 'Payment method not supported',
        copy: 'That payment method is not supported. '
            'Choose cash, card, or payment link.',
        actionLabel: 'Choose another method',
      );
    }

    if (lower.contains('cannot cancel ride after it has started')) {
      return const RideErrorInfo(
        title: 'Too late to cancel',
        copy: 'This ride already started and can no longer be cancelled. '
            'Ask the driver to end the trip early if needed.',
      );
    }

    if (lower.contains('cancellation reason is required')) {
      return const RideErrorInfo(
        title: 'Reason needed',
        copy: 'Please pick a cancellation reason to continue.',
        actionLabel: 'Add a reason',
      );
    }

    if (lower.contains('rating must be between 1 and 5')) {
      return const RideErrorInfo(
        title: 'Invalid rating',
        copy: 'Please choose a rating from 1 to 5 stars.',
        actionLabel: 'Pick 1–5 stars',
      );
    }

    if (lower.contains('latitude and longitude are required')) {
      return const RideErrorInfo(
        title: 'Location missing',
        copy: "We couldn't get your location. "
            'Enable location services and try again.',
        actionLabel: 'Retry',
      );
    }

    if (lower.contains('pickup and dropoff locations are required') ||
        (lower.contains('pickuplon') && lower.contains('required'))) {
      return const RideErrorInfo(
        title: 'Locations missing',
        copy: 'Pickup and dropoff are required to get a fare estimate.',
        actionLabel: 'Enter locations',
      );
    }

    if (lower.contains('ride is not available')) {
      return const RideErrorInfo(
        title: 'Ride unavailable',
        copy: 'This ride is no longer available. Search again to find a driver.',
        actionLabel: 'Search again',
      );
    }

    if (lower.contains('must be completed before confirming cash')) {
      return const RideErrorInfo(
        title: 'Ride not complete yet',
        copy: 'Complete the ride before confirming cash collection.',
      );
    }

    // Reassigned — informational, not an error.
    if (lower.contains('reassigned to other drivers')) {
      return const RideErrorInfo(
        title: 'Finding another driver',
        copy: 'Your driver cancelled — '
            "we're matching you with a nearby driver. Stay on this screen.",
        severity: RideErrorSeverity.info,
      );
    }

    return RideErrorInfo(
      title: 'Something went wrong',
      copy: message.isNotEmpty ? message : 'Please try again.',
      actionLabel: 'Try again',
    );
  }
}

/// Utility class for displaying errors to users
class ErrorDisplayHelper {
  /// Show error dialog
  static Future<void> showErrorDialog({
    required BuildContext context,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            if (actionLabel != null && onAction != null)
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Show error snackbar
  static void showErrorSnackbar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        duration: duration,
        action: action,
      ),
    );
  }

  /// Show warning snackbar
  static void showWarningSnackbar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange.shade600,
        duration: duration,
      ),
    );
  }

  /// Show success snackbar
  static void showSuccessSnackbar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        duration: duration,
      ),
    );
  }

  /// Show API error with user-friendly message
  static void handleApiError(
    BuildContext context,
    Exception error, {
    String? title,
    VoidCallback? onRetry,
    bool showDialog = true,
  }) {
    String message = 'Something went wrong';
    String errorTitle = title ?? 'Error';

    if (error is ApiError) {
      message = error.getUserMessage();

      // Specific error handling based on error type
      if (error.isAuthError()) {
        errorTitle = 'Authentication Error';
      } else if (error.isNetworkError()) {
        errorTitle = 'Network Error';
        message = 'Please check your internet connection';
      } else if (error.isServerError()) {
        errorTitle = 'Server Error';
        message = 'The server is temporarily unavailable. Please try again later.';
      }
    } else if (error is NetworkException) {
      errorTitle = 'Network Error';
      message = error.message;
    }

    if (showDialog) {
      showErrorDialog(
        context: context,
        title: errorTitle,
        message: message,
        actionLabel: onRetry != null ? 'Retry' : null,
        onAction: onRetry,
      );
    } else {
      showErrorSnackbar(context, message);
    }
  }

  /// Show OTP-specific error
  static void handleOtpError(
    BuildContext context,
    ApiError error,
  ) {
    String message = error.getUserMessage();

    if (error.isOtpExpired()) {
      message = 'OTP has expired. A new OTP has been sent.';
      showWarningSnackbar(context, message);
    } else if (error.isError('invalid otp')) {
      final remaining = error.getAttemptsRemaining();
      if (remaining != null && remaining > 0) {
        message = 'Invalid OTP. $remaining attempts remaining.';
      }
      showErrorSnackbar(context, message);
    } else {
      showErrorSnackbar(context, message);
    }
  }

  /// Show distance error (for ride arrive/complete)
  static void handleDistanceError(
    BuildContext context,
    ApiError error,
  ) {
    final distanceDetails = error.getDistanceDetails();
    String message = error.getUserMessage();

    if (distanceDetails != null) {
      final current = distanceDetails['current'] ?? 0;
      final required = distanceDetails['required'] ?? 0;
      message = 'You are ${current}m away from the location. '
          'Please get within ${required}m to proceed.';
    }

    showWarningSnackbar(context, message);
  }

  /// Show a mapped ride error — the one call path for all ride screens.
  ///
  /// Pass the backend `message` + `errors` payload; friendly copy and the
  /// next action come from [RideErrorMapper]. Info results (e.g. reassign)
  /// show neutral; errors show red with a retry action slot.
  static void showRideError(
    BuildContext context,
    String message, {
    dynamic errors,
    VoidCallback? onAction,
  }) {
    final info = RideErrorMapper.map(message, errors);
    if (info.isInfo) {
      showWarningSnackbar(context, '${info.title}: ${info.copy}');
      return;
    }
    showErrorSnackbar(
      context,
      '${info.title}: ${info.copy}',
      action: info.actionLabel == null
          ? null
          : SnackBarAction(
              label: onAction != null ? info.actionLabel! : 'OK',
              onPressed: onAction ?? () {},
            ),
    );
  }

  /// Show ride-specific error
  static void handleRideError(
    BuildContext context,
    Exception error, {
    VoidCallback? onRetry,
  }) {
    if (error is! ApiError) {
      handleApiError(context, error, onRetry: onRetry);
      return;
    }

    final apiError = error;
    // Single path: every ride failure goes through the central mapper.
    showRideError(
      context,
      apiError.message,
      errors: apiError.errors,
      onAction: onRetry,
    );
  }

  /// Build error widget for empty states
  static Widget buildErrorWidget({
    required String message,
    IconData icon = Icons.error_outline,
    VoidCallback? onRetry,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: Colors.red.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.red,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
