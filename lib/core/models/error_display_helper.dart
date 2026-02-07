import 'package:flutter/material.dart';
import 'api_error.dart';

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

  /// Show ride-specific error
  static void handleRideError(
    BuildContext context,
    Exception error,
  ) {
    if (error is! RideException) {
      handleApiError(context, error as ApiError);
      return;
    }

    final apiError = error as ApiError;
    String message = apiError.getUserMessage();

    // Handle specific ride errors
    if (apiError.isError('distance')) {
      handleDistanceError(context, apiError);
    } else if (apiError.isError('expired')) {
      showWarningSnackbar(context, message);
    } else if (apiError.isError('not authorized')) {
      showErrorSnackbar(context, message);
    } else {
      showErrorSnackbar(context, message);
    }
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
