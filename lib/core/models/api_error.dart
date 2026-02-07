import 'dart:convert';

/// Special error codes returned by backend
class ErrorCode {
  // Driver profile errors
  static const String profileIncomplete = 'PROFILE_INCOMPLETE';
  static const String notApproved = 'NOT_APPROVED';
  
  // Image upload errors
  static const String noImagesUploaded = 'NO_IMAGES_UPLOADED';
  static const String maxImagesExceeded = 'MAX_IMAGES_EXCEEDED';
  
  // Validation errors
  static const String invalidCoordinates = 'INVALID_COORDINATES';
  static const String invalidBoolean = 'INVALID_BOOLEAN';
}

/// Represents an API error response from the backend
class ApiError implements Exception {
  final bool success;
  final String message;
  final dynamic errors;
  final int? statusCode;
  final String? error;

  ApiError({
    required this.success,
    required this.message,
    this.errors,
    this.statusCode,
    this.error,
  });

  /// Parse error from HTTP response body
  factory ApiError.fromJson(Map<String, dynamic> json, [int? statusCode]) {
    return ApiError(
      success: json['success'] ?? false,
      message: json['message'] ?? 'An error occurred',
      errors: json['errors'],
      error: json['error'],
      statusCode: statusCode,
    );
  }

  /// Parse error from response string
  factory ApiError.fromString(String body, int statusCode) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return ApiError.fromJson(json, statusCode);
    } catch (e) {
      return ApiError(
        success: false,
        message: 'An error occurred (HTTP $statusCode)',
        statusCode: statusCode,
      );
    }
  }

  /// Get user-friendly error message
  String getUserMessage() {
    // Return the message if it's set
    if (message.isNotEmpty) {
      return message;
    }
    return 'Something went wrong. Please try again.';
  }

  /// Check if this is a specific error type
  bool isError(String errorMessage) {
    return message.toLowerCase().contains(errorMessage.toLowerCase());
  }

  /// Extract additional error details
  dynamic getErrorDetails(String key) {
    if (errors is Map) {
      return (errors as Map<String, dynamic>)[key];
    }
    return null;
  }

  /// Get distance details (for arrive/complete ride errors)
  Map<String, int>? getDistanceDetails() {
    if (errors is Map) {
      final errorsMap = errors as Map<String, dynamic>;
      if (errorsMap.containsKey('distance') && errorsMap.containsKey('required')) {
        return {
          'current': errorsMap['distance'] as int,
          'required': errorsMap['required'] as int,
        };
      }
    }
    return null;
  }

  /// Get OTP attempts remaining
  int? getAttemptsRemaining() {
    if (errors is Map) {
      final errorsMap = errors as Map<String, dynamic>;
      return errorsMap['attemptsRemaining'] as int?;
    }
    return null;
  }

  /// Check if OTP has expired
  bool isOtpExpired() {
    if (errors is Map) {
      final errorsMap = errors as Map<String, dynamic>;
      return errorsMap['expired'] == true;
    }
    return false;
  }

  /// Check if it's an auth error
  bool isAuthError() {
    return statusCode == 401 ||
        message.toLowerCase().contains('token') ||
        message.toLowerCase().contains('authorization') ||
        message.toLowerCase().contains('not authenticated');
  }

  /// Check if it's a not found error
  bool isNotFoundError() {
    return statusCode == 404 || message.toLowerCase().contains('not found');
  }

  /// Check if it's a server error
  bool isServerError() {
    return statusCode != null && statusCode! >= 500;
  }

  /// Check if it's a network error
  bool isNetworkError() {
    return statusCode == null;
  }

  @override
  String toString() => message;
}

/// Custom exceptions for different error scenarios
class AuthException extends ApiError {
  AuthException({
    required String message,
    dynamic errors,
    int? statusCode,
  }) : super(
    success: false,
    message: message,
    errors: errors,
    statusCode: statusCode,
  );
}

class RideException extends ApiError {
  RideException({
    required String message,
    dynamic errors,
    int? statusCode,
  }) : super(
    success: false,
    message: message,
    errors: errors,
    statusCode: statusCode,
  );
}

class PaymentException extends ApiError {
  PaymentException({
    required String message,
    dynamic errors,
    int? statusCode,
  }) : super(
    success: false,
    message: message,
    errors: errors,
    statusCode: statusCode,
  );
}

class ValidationException extends ApiError {
  ValidationException({
    required String message,
    dynamic errors,
    int? statusCode,
  }) : super(
    success: false,
    message: message,
    errors: errors,
    statusCode: statusCode,
  );
}

class ServerException extends ApiError {
  ServerException({
    required String message,
    int? statusCode,
  }) : super(
    success: false,
    message: message,
    statusCode: statusCode,
  );
}

class DriverException extends ApiError {
  DriverException({
    required String message,
    dynamic errors,
    int? statusCode,
  }) : super(
    success: false,
    message: message,
    errors: errors,
    statusCode: statusCode,
  );

  /// Check if this is a profile incomplete error
  bool isProfileIncomplete() {
    if (errors is Map) {
      final errorsMap = errors as Map<String, dynamic>;
      return errorsMap['code'] == ErrorCode.profileIncomplete;
    }
    return false;
  }

  /// Check if this is a not approved error
  bool isNotApproved() {
    if (errors is Map) {
      final errorsMap = errors as Map<String, dynamic>;
      return errorsMap['code'] == ErrorCode.notApproved;
    }
    return false;
  }

  /// Get the error code if present
  String? getErrorCode() {
    if (errors is Map) {
      final errorsMap = errors as Map<String, dynamic>;
      return errorsMap['code'] as String?;
    }
    return null;
  }

  /// Check if driver is missing specific documents
  bool isMissingVehicleImages() =>
      message.toLowerCase().contains('vehicle image');

  bool isMissingLicense() =>
      message.toLowerCase().contains('license');

  bool isMissingVehicleDetails() =>
      message.toLowerCase().contains('vehicle detail');

  /// Check if image count exceeds limit
  bool isMaxImagesExceeded() =>
      message.toLowerCase().contains('maximum') &&
      message.toLowerCase().contains('image');
}

class NetworkException implements Exception {
  final String message;

  NetworkException([this.message = 'Network error. Please check your connection.']);

  @override
  String toString() => message;
}
