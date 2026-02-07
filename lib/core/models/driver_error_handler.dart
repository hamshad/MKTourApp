import 'package:flutter/material.dart';
import 'api_error.dart';
import 'error_display_helper.dart';

/// Driver-specific error handling utilities
class DriverErrorHandler {
  /// Handle driver profile status errors
  static void handleProfileStatusError(
    BuildContext context,
    DriverException error,
  ) {
    if (error.isProfileIncomplete()) {
      _showProfileIncompleteDialog(context, error.message);
    } else if (error.isNotApproved()) {
      _showAwaitingApprovalDialog(context);
    } else {
      ErrorDisplayHelper.showErrorSnackbar(context, error.getUserMessage());
    }
  }

  /// Show profile incomplete dialog with action items
  static Future<void> _showProfileIncompleteDialog(
    BuildContext context,
    String message,
  ) async {
    final items = <String>[];

    // Determine what's missing from error message
    if (message.toLowerCase().contains('vehicle image')) {
      items.add('📸 Upload vehicle images');
    }
    if (message.toLowerCase().contains('license')) {
      items.add('📄 Upload license document');
    }
    if (message.toLowerCase().contains('vehicle detail')) {
      items.add('🚗 Complete vehicle details');
    }

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Complete Your Profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To go online, please complete the following:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ...items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item)),
                      ],
                    ),
                  )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Show awaiting approval dialog
  static Future<void> _showAwaitingApprovalDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Account Under Review'),
          content: const Text(
            'Your account is pending admin approval. '
            'We will notify you once your account is approved. '
            'Thank you for your patience!',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Handle vehicle image upload errors
  static void handleImageUploadError(
    BuildContext context,
    DriverException error,
  ) {
    if (error.isMaxImagesExceeded()) {
      ErrorDisplayHelper.showWarningSnackbar(
        context,
        'Maximum 5 images allowed. Please delete some images first.',
      );
    } else if (error.isError('no vehicle images')) {
      ErrorDisplayHelper.showErrorSnackbar(
        context,
        'Please select at least one image to upload.',
      );
    } else {
      ErrorDisplayHelper.showErrorSnackbar(context, error.getUserMessage());
    }
  }

  /// Handle location update errors
  static void handleLocationError(
    BuildContext context,
    DriverException error,
  ) {
    if (error.isError('invalid coordinates')) {
      ErrorDisplayHelper.showErrorSnackbar(
        context,
        'Invalid location. Please check your GPS and try again.',
      );
    } else if (error.isError('driver not found')) {
      ErrorDisplayHelper.showErrorSnackbar(
        context,
        'Driver profile not found. Please re-login.',
      );
    } else {
      ErrorDisplayHelper.showErrorSnackbar(context, error.getUserMessage());
    }
  }

  /// Handle ride acceptance errors
  static void handleRideAcceptanceError(
    BuildContext context,
    DriverException error,
  ) {
    if (error.isError('not available')) {
      ErrorDisplayHelper.showWarningSnackbar(
        context,
        'This ride is no longer available.',
      );
    } else if (error.isError('expired')) {
      ErrorDisplayHelper.showWarningSnackbar(
        context,
        'This ride request has expired.',
      );
    } else if (error.isError('not found')) {
      ErrorDisplayHelper.showErrorSnackbar(
        context,
        'Ride not found.',
      );
    } else {
      ErrorDisplayHelper.showErrorSnackbar(context, error.getUserMessage());
    }
  }

  /// Handle arrive at location errors
  static void handleArriveError(
    BuildContext context,
    DriverException error,
  ) {
    if (error.isError('not close enough')) {
      final distanceDetails = error.getDistanceDetails();
      if (distanceDetails != null) {
        final current = distanceDetails['current'];
        final required = distanceDetails['required'];
        ErrorDisplayHelper.showWarningSnackbar(
          context,
          'You are ${current}m away from pickup. Get within ${required}m.',
        );
      } else {
        ErrorDisplayHelper.showWarningSnackbar(
          context,
          'You are not close enough to the pickup location.',
        );
      }
    } else if (error.isError('invalid coordinates')) {
      ErrorDisplayHelper.showErrorSnackbar(
        context,
        'Invalid location. Please enable GPS.',
      );
    } else {
      ErrorDisplayHelper.showErrorSnackbar(context, error.getUserMessage());
    }
  }

  /// Handle start ride errors
  static void handleStartRideError(
    BuildContext context,
    DriverException error,
  ) {
    if (error.isOtpExpired()) {
      ErrorDisplayHelper.showWarningSnackbar(
        context,
        'OTP expired. A new one has been sent.',
      );
    } else if (error.isError('invalid otp')) {
      final remaining = error.getAttemptsRemaining();
      if (remaining != null) {
        ErrorDisplayHelper.showErrorSnackbar(
          context,
          'Invalid OTP. $remaining attempts remaining.',
        );
      }
    } else if (error.isError('too many failed')) {
      ErrorDisplayHelper.showErrorDialog(
        context: context,
        title: 'Too Many Attempts',
        message: 'You have exceeded the maximum OTP attempts. '
            'Please try again later.',
      );
    } else if (error.isError('must arrive')) {
      ErrorDisplayHelper.showWarningSnackbar(
        context,
        'You must arrive at the pickup location first.',
      );
    } else if (error.isError('payment method')) {
      ErrorDisplayHelper.showWarningSnackbar(
        context,
        'Passenger must select a payment method before ride starts.',
      );
    } else {
      ErrorDisplayHelper.showErrorSnackbar(context, error.getUserMessage());
    }
  }

  /// Handle complete ride errors
  static void handleCompleteRideError(
    BuildContext context,
    DriverException error,
  ) {
    if (error.isError('not close enough')) {
      final distanceDetails = error.getDistanceDetails();
      if (distanceDetails != null) {
        final current = distanceDetails['current'];
        final required = distanceDetails['required'];
        ErrorDisplayHelper.showWarningSnackbar(
          context,
          'You are ${current}m away from dropoff. Get within ${required}m.',
        );
      }
    } else if (error.isError('must be in progress')) {
      ErrorDisplayHelper.showErrorSnackbar(
        context,
        'Ride is not in progress.',
      );
    } else if (error.isError('invalid coordinates')) {
      ErrorDisplayHelper.showErrorSnackbar(
        context,
        'Invalid location. Please enable GPS.',
      );
    } else {
      ErrorDisplayHelper.showErrorSnackbar(context, error.getUserMessage());
    }
  }

  /// Handle cancel ride errors
  static void handleCancelRideError(
    BuildContext context,
    DriverException error,
  ) {
    if (error.isError('already started')) {
      ErrorDisplayHelper.showWarningSnackbar(
        context,
        'Cannot cancel after ride has started. Use "End Ride" instead.',
      );
    } else if (error.isError('not authorized')) {
      ErrorDisplayHelper.showErrorSnackbar(
        context,
        'You cannot cancel this ride.',
      );
    } else {
      ErrorDisplayHelper.showErrorSnackbar(context, error.getUserMessage());
    }
  }
}

/// Helper extension to make error checking easier
extension DriverErrorExtension on ApiError {
  /// Check if this is a driver-specific error
  bool isDriverError() => this is DriverException;

  /// Cast to DriverException if possible
  DriverException? asDriverException() =>
      this is DriverException ? this as DriverException : null;
}
