// Example: How to Update API Calls with Proper Error Handling
// This file shows patterns to follow when updating API methods in api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models/api_error.dart';

/// EXAMPLE 1: Auth Endpoint - Send OTP
/// 
/// Before:
/// ```dart
/// Future<Map<String, dynamic>> sendOtp(String phone) async {
///   try {
///     final response = await http.post(
///       Uri.parse(ApiConstants.sendOtp),
///       headers: {'Content-Type': 'application/json'},
///       body: jsonEncode({'phone': phone}),
///     );
///     if (response.statusCode == 200) {
///       return jsonDecode(response.body);
///     } else {
///       throw Exception('Failed to send OTP: ${response.body}');
///     }
///   } catch (e) {
///     rethrow;
///   }
/// }
/// ```
///
/// After:
/// ```dart
/// Future<Map<String, dynamic>> sendOtp(String phone) async {
///   try {
///     final response = await http.post(
///       Uri.parse(ApiConstants.sendOtp),
///       headers: {'Content-Type': 'application/json'},
///       body: jsonEncode({'phone': phone}),
///     );
///     
///     _handleResponse(response: response, endpoint: ApiConstants.sendOtp);
///     return _parseResponse(response, ApiConstants.sendOtp);
///   } catch (e) {
///     debugPrint('🔴 API Error (sendOtp): $e');
///     rethrow;
///   }
/// }
/// ```

/// EXAMPLE 2: Ride Endpoint - Create Ride
/// 
/// Before:
/// ```dart
/// Future<Map<String, dynamic>> createRide(Map<String, dynamic> rideData) async {
///   try {
///     final token = await _getToken();
///     final response = await http.post(
///       Uri.parse('${ApiConstants.baseUrl}/rides/create'),
///       headers: {
///         'Content-Type': 'application/json',
///         'Authorization': 'Bearer $token',
///       },
///       body: jsonEncode(rideData),
///     );
///     if (response.statusCode == 200) {
///       return jsonDecode(response.body);
///     } else {
///       throw Exception('Failed to create ride');
///     }
///   } catch (e) {
///     rethrow;
///   }
/// }
/// ```
///
/// After:
/// ```dart
/// Future<Map<String, dynamic>> createRide(
///   Map<String, dynamic> rideData,
/// ) async {
///   try {
///     final token = await _getToken();
///     final response = await http.post(
///       Uri.parse('${ApiConstants.baseUrl}/rides/create'),
///       headers: {
///         'Content-Type': 'application/json',
///         'Authorization': 'Bearer $token',
///       },
///       body: jsonEncode(rideData),
///     );
///     
///     _handleResponse(
///       response: response,
///       endpoint: '${ApiConstants.baseUrl}/rides/create',
///     );
///     return _parseResponse(response, '${ApiConstants.baseUrl}/rides/create');
///   } catch (e) {
///     debugPrint('🔴 API Error (createRide): $e');
///     rethrow;
///   }
/// }
/// ```

/// EXAMPLE 3: Ride Endpoint - Arrive at Location
/// 
/// This handles the special case with distance details
///
/// ```dart
/// Future<Map<String, dynamic>> arriveAtPickup(
///   String rideId,
///   double latitude,
///   double longitude,
/// ) async {
///   try {
///     final token = await _getToken();
///     final endpoint = '${ApiConstants.baseUrl}/rides/$rideId/arrive';
///     
///     final response = await http.post(
///       Uri.parse(endpoint),
///       headers: {
///         'Content-Type': 'application/json',
///         'Authorization': 'Bearer $token',
///       },
///       body: jsonEncode({
///         'latitude': latitude,
///         'longitude': longitude,
///       }),
///     );
///     
///     _handleResponse(response: response, endpoint: endpoint);
///     return _parseResponse(response, endpoint);
///   } catch (e) {
///     debugPrint('🔴 API Error (arriveAtPickup): $e');
///     rethrow;
///   }
/// }
/// ```

/// EXAMPLE 4: Error Handling in Provider/Screen
/// 
/// In auth_provider.dart or screens:
///
/// ```dart
/// Future<bool> sendOtp(String phone) async {
///   try {
///     final response = await _apiService.sendOtp(phone);
///     if (response['success']) {
///       _otpSent = true;
///       notifyListeners();
///       return true;
///     }
///     return false;
///   } on AuthException catch (e) {
///     _errorMessage = e.getUserMessage();
///     debugPrint('Auth error: $_errorMessage');
///     notifyListeners();
///     return false;
///   } on ApiError catch (e) {
///     _errorMessage = e.getUserMessage();
///     debugPrint('API error: $_errorMessage');
///     notifyListeners();
///     return false;
///   } catch (e) {
///     _errorMessage = 'An unexpected error occurred';
///     notifyListeners();
///     return false;
///   }
/// }
/// ```

/// EXAMPLE 5: Error Handling in UI Screen
/// 
/// In a widget:
///
/// ```dart
/// Future<void> _verifyOtp() async {
///   try {
///     final response = await _apiService.verifyOtp(
///       phone: _phoneController.text,
///       otp: _otpController.text,
///       role: 'user',
///     );
///
///     if (response['success']) {
///       // Navigate to next screen
///       Navigator.pushNamed(context, '/home');
///     }
///   } on ApiError catch (e) {
///     // Handle OTP-specific errors
///     if (e.isOtpExpired()) {
///       ErrorDisplayHelper.showWarningSnackbar(
///         context,
///         'OTP expired. A new one has been sent to your phone.',
///       );
///       _resetOtpForm();
///     } else {
///       final attempts = e.getAttemptsRemaining();
///       if (attempts != null && attempts > 0) {
///         ErrorDisplayHelper.showErrorSnackbar(
///           context,
///           'Invalid OTP. $attempts attempts remaining.',
///         );
///       } else {
///         ErrorDisplayHelper.showErrorDialog(
///           context: context,
///           title: 'Verification Failed',
///           message: e.getUserMessage(),
///           actionLabel: 'Resend OTP',
///           onAction: () => _resendOtp(),
///         );
///       }
///     }
///   } catch (e) {
///     ErrorDisplayHelper.showErrorSnackbar(
///       context,
///       'An unexpected error occurred. Please try again.',
///     );
///   }
/// }
/// ```

/// EXAMPLE 6: Ride Operation with Distance Check
/// 
/// ```dart
/// Future<void> _completeRide() async {
///   try {
///     final response = await _apiService.completeRide(
///       rideId: _ride.id,
///       latitude: _location.latitude,
///       longitude: _location.longitude,
///     );
///
///     if (response['success']) {
///       ErrorDisplayHelper.showSuccessSnackbar(
///         context,
///         'Ride completed successfully',
///       );
///       Navigator.pop(context);
///     }
///   } on RideException catch (e) {
///     // Special handling for distance errors
///     if (e.isError('not close enough')) {
///       final distanceDetails = e.getDistanceDetails();
///       if (distanceDetails != null) {
///         final current = distanceDetails['current'];
///         final required = distanceDetails['required'];
///         ErrorDisplayHelper.showWarningSnackbar(
///           context,
///           'You are ${current}m away. Get within ${required}m to complete.',
///         );
///       } else {
///         ErrorDisplayHelper.showWarningSnackbar(context, e.getUserMessage());
///       }
///     } else {
///       ErrorDisplayHelper.handleRideError(context, e);
///     }
///   } catch (e) {
///     ErrorDisplayHelper.showErrorSnackbar(
///       context,
///       'Failed to complete ride',
///     );
///   }
/// }
/// ```

// NOTE: The actual implementation of these examples should be done
// in lib/core/api_service.dart and the screens that use these methods.
// This file is just for reference and documentation.
