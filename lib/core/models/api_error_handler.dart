import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_error.dart';

/// Utility class for handling API responses and errors
class ApiErrorHandler {
  /// Handle HTTP response and throw appropriate exception
  static void handleResponse({
    required http.Response response,
    required String endpoint,
  }) {
    // Check for success status codes
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return; // No error
    }

    // Parse error from response
    final apiError = ApiError.fromString(response.body, response.statusCode);

    // Log error
    _logError(endpoint, response.statusCode, apiError.message);

    // Throw appropriate exception based on status code and error type
    _throwException(apiError, endpoint);
  }

  /// Handle HTTP response and return parsed response
  static Map<String, dynamic> parseResponse(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw ServerException(
        message: 'Invalid response format',
        statusCode: response.statusCode,
      );
    }
  }

  /// Helper to throw appropriate exception
  static void _throwException(ApiError error, String endpoint) {
    // Auth errors
    if (error.isAuthError()) {
      throw AuthException(
        message: error.message,
        errors: error.errors,
        statusCode: error.statusCode,
      );
    }

    // Check endpoint type to throw appropriate exception
    if (endpoint.contains('/rides/')) {
      throw RideException(
        message: error.message,
        errors: error.errors,
        statusCode: error.statusCode,
      );
    } else if (endpoint.contains('/payments/')) {
      throw PaymentException(
        message: error.message,
        errors: error.errors,
        statusCode: error.statusCode,
      );
    } else if (endpoint.contains('/auth/')) {
      throw AuthException(
        message: error.message,
        errors: error.errors,
        statusCode: error.statusCode,
      );
    }

    // Default: throw as ApiError
    throw error;
  }

  /// Log error for debugging
  static void _logError(String endpoint, int statusCode, String message) {
    print('🔴 API Error [$statusCode] $endpoint: $message');
  }

  /// Get user-friendly message from error (for UI display)
  static String getUserMessage(Exception error) {
    if (error is ApiError) {
      return error.getUserMessage();
    } else if (error is NetworkException) {
      return error.message;
    }
    return 'Something went wrong. Please try again.';
  }

  /// Check if error is recoverable (user can retry)
  static bool isRecoverable(Exception error) {
    if (error is ApiError) {
      // Network errors and server errors are recoverable
      if (error.isNetworkError() || error.isServerError()) {
        return true;
      }
      // Some validation errors might be recoverable (user can fix input)
      if (error.statusCode == 400) {
        return true;
      }
      return false;
    }
    return true;
  }

  /// Check if error requires logout
  static bool requiresLogout(Exception error) {
    if (error is AuthException) {
      return error.message.contains('token') ||
          error.message.contains('authorization') ||
          error.message.contains('User not found');
    }
    return false;
  }
}
