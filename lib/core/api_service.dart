import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants/api_constants.dart';
// ignore: unused_import
import 'models/api_error.dart';

class ApiService {
  final String baseUrl = ApiConstants.baseUrl;

  static const String _prefsAuthTokenKey = 'auth_token';
  static const String _prefsAuthRoleKey = 'auth_role';
  static const String _prefsDriverProfileStatusKey = 'driver_profile_status';

  // Callback to trigger logout when 401 is detected
  static Function()? onUnauthorized;

  /// Check if response is 401 with invalid token message and trigger logout
  Future<bool> _checkUnauthorized(http.Response response) async {
    if (response.statusCode == 401) {
      try {
        final responseData = jsonDecode(response.body);
        final message = responseData['message']?.toString() ?? '';
        
        if (message.toLowerCase().contains('invalid token') ||
            message.toLowerCase().contains('authorization denied') ||
            message.toLowerCase().contains('expired token')) {
          debugPrint('🔴 [ApiService] 401 Unauthorized detected: $message');
          debugPrint('🔴 [ApiService] Triggering logout and FCM token cleanup...');
          
          // Trigger logout callback (which will clear FCM token)
          if (onUnauthorized != null) {
            onUnauthorized!();
          }
          
          return true;
        }
      } catch (e) {
        debugPrint('🔴 [ApiService] Error parsing 401 response: $e');
      }
    }
    return false;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true && responseData['token'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefsAuthTokenKey, responseData['token']);
          // Email/password flow is for passenger/user.
          await prefs.setString(_prefsAuthRoleKey, 'user');
        }
        return responseData;
      } else {
        throw Exception('Failed to login: ${response.body}');
      }
    } catch (e) {
      debugPrint('🔴 API Error (login): $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> signup(
    String email,
    String password,
    String firstName,
    String lastName,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'firstName': firstName,
          'lastName': lastName,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true && responseData['token'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefsAuthTokenKey, responseData['token']);
          // Email/password flow is for passenger/user.
          await prefs.setString(_prefsAuthRoleKey, 'user');
        }
        return responseData;
      } else {
        throw Exception('Failed to signup: ${response.body}');
      }
    } catch (e) {
      debugPrint('🔴 API Error (signup): $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> deleteUserAccount() async {
    try {
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      debugPrint('🔵 [ApiService] deleteUserAccount called');
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_prefsAuthTokenKey);
      if (token == null) throw Exception('No auth token found');

      debugPrint(
        '🔵 [ApiService] Request URL: ${ApiConstants.deleteUserAccount}',
      );
      debugPrint(
        '🔵 [ApiService] Authorization: Bearer ${token.substring(0, token.length > 8 ? 8 : token.length)}***',
      );

      final response = await http.delete(
        Uri.parse(ApiConstants.deleteUserAccount),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('🟣 [ApiService] Response Status: ${response.statusCode}');
      debugPrint('🟣 [ApiService] Response Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] deleteUserAccount Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] deleteUserAccount Failed');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to delete user account: ${response.body}');
      }
    } catch (e) {
      debugPrint('🔴 API Error (deleteUserAccount): $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>> deleteDriverAccount() async {
    try {
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      debugPrint('🔵 [ApiService] deleteDriverAccount called');
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_prefsAuthTokenKey);
      if (token == null) throw Exception('No auth token found');

      debugPrint(
        '🔵 [ApiService] Request URL: ${ApiConstants.deleteDriverAccount}',
      );
      debugPrint(
        '🔵 [ApiService] Authorization: Bearer ${token.substring(0, token.length > 8 ? 8 : token.length)}***',
      );

      final response = await http.delete(
        Uri.parse(ApiConstants.deleteDriverAccount),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('🟣 [ApiService] Response Status: ${response.statusCode}');
      debugPrint('🟣 [ApiService] Response Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] deleteDriverAccount Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] deleteDriverAccount Failed');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to delete driver account: ${response.body}');
      }
    } catch (e) {
      debugPrint('🔴 API Error (deleteDriverAccount): $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>> bookRide(
    Map<String, dynamic> bookingDetails,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/book'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(bookingDetails),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to book ride');
      }
    } catch (e) {
      debugPrint('🔴 API Error (bookRide): $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getRideStatus(String rideId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/ride-status/$rideId'),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get status');
      }
    } catch (e) {
      debugPrint('🔴 API Error (getRideStatus): $e');
      rethrow;
    }
  }

  // Removed conflicting static completeRide method
  Future<Map<String, dynamic>> sendOtp(String phone) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] sendOtp called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.sendOtp}');
    debugPrint('🔵 [Request] Body: {"phone": "$phone"}');

    try {
      final response = await http.post(
        Uri.parse(ApiConstants.sendOtp),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] sendOtp Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] sendOtp Failed: ${response.body}');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to send OTP: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to send OTP: $e');
    }
  }

  Future<Map<String, dynamic>> checkPhone(String phone, String role) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] checkPhone called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.baseUrl}/auth/check-phone');
    debugPrint('🔵 [Request] Body: {"phone": "$phone", "role": "$role"}');

    try {
      // Note: Using a direct URL construction here as ApiConstants might not have checkPhone yet
      // Ideally, add checkPhone to ApiConstants
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/auth/check-phone'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'role': role}),
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] checkPhone Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] checkPhone Failed: ${response.body}');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to check phone: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to check phone: $e');
    }
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String otp,
    required String role,
    String? name, // Made nullable
    Map<String, dynamic>? vehicleDetails,
    String? fcmToken, // NEW: FCM token from Firebase Messaging
  }) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] verifyOtp called');

    final Map<String, dynamic> requestBody = {
      'phone': phone,
      'otp': otp,
      'role': role,
    };

    if (name != null) {
      requestBody['name'] = name;
    }

    if (fcmToken != null && fcmToken.isNotEmpty) {
      requestBody['fcmToken'] = fcmToken;
      debugPrint('🔔 [ApiService] Including FCM token in OTP verification');
    }

    if (role == 'driver' && vehicleDetails != null) {
      requestBody['vehicle'] = vehicleDetails;
    }

    debugPrint('🔵 [Request] URL: ${ApiConstants.verifyOtp}');
    debugPrint('🔵 [Request] Body: $requestBody');

    try {
      final response = await http.post(
        Uri.parse(ApiConstants.verifyOtp),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        debugPrint('🟢 [ApiService] verifyOtp Success');

        if (responseData['success'] == true && responseData['data'] != null) {
          final token = responseData['data']['token'];
          if (token != null) {
            debugPrint('💾 [ApiService] Saving token to SharedPreferences...');
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_prefsAuthTokenKey, token);
            await prefs.setString(_prefsAuthRoleKey, role);

            // New backend behavior: drivers get profileStatus embedded in login response.
            if (role == 'driver') {
              final profileStatus = responseData['data']['profileStatus'];
              if (profileStatus != null) {
                await prefs.setString(
                  _prefsDriverProfileStatusKey,
                  jsonEncode(profileStatus),
                );
              }
            }
            debugPrint('✅ [ApiService] Token saved successfully');
          }
        }

        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return responseData;
      } else {
        debugPrint('🔴 [ApiService] verifyOtp Failed: ${response.body}');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to verify OTP: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to verify OTP: $e');
    }
  }

  /// Fetch latest driver profile completion/verification status.
  /// Recommended usage: app reopen/refresh after uploads/polling.
  Future<Map<String, dynamic>> getDriverProfileStatus() async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] getDriverProfileStatus called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.driverProfileStatus}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_prefsAuthTokenKey);

      if (token == null) {
        throw Exception('No auth token found');
      }

      final response = await http.get(
        Uri.parse(ApiConstants.driverProfileStatus),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        // Cache for offline/fast restore.
        final data = responseData['data'];
        if (data != null) {
          // Endpoint may return { data: profileStatus } or { data: { profileStatus: ... } }
          final profileStatus = (data is Map && data['profileStatus'] != null)
              ? data['profileStatus']
              : data;
          await prefs.setString(
            _prefsDriverProfileStatusKey,
            jsonEncode(profileStatus),
          );
        }

        debugPrint('🟢 [ApiService] getDriverProfileStatus Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return responseData;
      }

      debugPrint(
        '🔴 [ApiService] getDriverProfileStatus Failed: ${response.body}',
      );
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to get driver profile status: ${response.body}');
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to get driver profile status: $e');
    }
  }

  Future<Map<String, dynamic>> getUserProfile() async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] getUserProfile called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.userProfile}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_prefsAuthTokenKey);

      if (token == null) {
        throw Exception('No auth token found');
      }

      debugPrint(
        '🔵 [Request] Headers: Authorization: Bearer ${token.substring(0, 10)}...',
      );

      final response = await http.get(
        Uri.parse(ApiConstants.userProfile),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] getUserProfile Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] getUserProfile Failed: ${response.body}');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to get user profile: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to get user profile: $e');
    }
  }

  Future<Map<String, dynamic>> updateUserProfile({
    required String name,
    required String email,
    File? profilePicture,
  }) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] updateUserProfile called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.updateUser}');
    debugPrint('🔵 [Request] Name: $name, Email: $email');
    if (profilePicture != null) {
      debugPrint('🔵 [Request] Profile Picture: ${profilePicture.path}');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_prefsAuthTokenKey);

      if (token == null) {
        throw Exception('No auth token found');
      }

      var request = http.MultipartRequest(
        'PATCH',
        Uri.parse(ApiConstants.updateUser),
      );
      request.headers['Authorization'] = 'Bearer $token';

      request.fields['name'] = name;
      request.fields['email'] = email;

      if (profilePicture != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'profilePicture',
            profilePicture.path,
          ),
        );
      }

      debugPrint('🔵 [Request] Sending multipart request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] updateUserProfile Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint(
          '🔴 [ApiService] updateUserProfile Failed: ${response.body}',
        );
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to update user profile: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to update user profile: $e');
    }
  }

  Future<Map<String, dynamic>> createRide(Map<String, dynamic> rideData) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] createRide called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.createRide}');
    debugPrint('🔵 [Request] Body: $rideData');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.post(
        Uri.parse(ApiConstants.createRide),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(rideData),
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 201) {
        debugPrint('🟢 [ApiService] createRide Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] createRide Failed: ${response.statusCode}');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return {'success': false, 'message': 'Failed to create ride request'};
      }
    } catch (e) {
      debugPrint('🔴 [ApiService] createRide Error: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      return {'success': false, 'message': 'Error creating ride request: $e'};
    }
  }

  Future<Map<String, dynamic>> acceptRide(String rideId) async {
    return await _postRequest(ApiConstants.acceptRide(rideId), {});
  }

  Future<Map<String, dynamic>> arriveAtPickup(
    String rideId,
    double lat,
    double lng,
  ) async {
    return await _postRequest(ApiConstants.arriveAtPickup(rideId), {
      'latitude': lat,
      'longitude': lng,
    });
  }

  Future<Map<String, dynamic>> startRide(String rideId, String otp) async {
    return await _postRequest(ApiConstants.startRide(rideId), {'otp': otp});
  }

  Future<Map<String, dynamic>> completeRide(
    String rideId,
    double latitude,
    double longitude,
  ) async {
    return await _postRequest(ApiConstants.completeRide(rideId), {
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  Future<Map<String, dynamic>> cancelRide(
    String rideId, {
    String? reason,
  }) async {
    return await _postRequest(ApiConstants.cancelRide(rideId), {
      if (reason != null) 'reason': reason,
    });
  }

  /// User cancels ride before it starts
  /// Returns cancellation fee info and refund status
  /// - Within grace period (< 2 min after acceptance): Full refund
  /// - After grace period: 20% cancellation fee
  Future<Map<String, dynamic>> cancelRideByUser(String rideId) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] cancelRideByUser called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.cancelRideByUser(rideId)}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      final response = await http.post(
        Uri.parse(ApiConstants.cancelRideByUser(rideId)),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({}),
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] cancelRideByUser Success');
        return responseData;
      } else if (response.statusCode == 400) {
        // Ride already started or other validation error
        debugPrint(
          '🔴 [ApiService] cancelRideByUser Failed: ${responseData['message']}',
        );
        return {
          'success': false,
          'message': responseData['message'] ?? 'Cannot cancel ride',
          'error': responseData['error'] ?? 'Bad Request',
        };
      } else if (response.statusCode == 403) {
        debugPrint('🔴 [ApiService] cancelRideByUser Forbidden');
        return {
          'success': false,
          'message':
              responseData['message'] ?? 'Not authorized to cancel this ride',
          'error': 'Forbidden',
        };
      } else {
        debugPrint('🔴 [ApiService] cancelRideByUser Failed');
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to cancel ride',
        };
      }
    } catch (e) {
      debugPrint('🔴 [ApiService] cancelRideByUser Error: $e');
      return {'success': false, 'message': 'Error cancelling ride: $e'};
    }
  }

  /// Driver cancels ride before it starts
  /// Requires a reason from valid options:
  /// - rider_no_show, safety_concern, rider_unreachable, vehicle_issue, driver_no_show
  Future<Map<String, dynamic>> cancelRideByDriver(
    String rideId, {
    required String reason,
  }) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] cancelRideByDriver called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.cancelRideByDriver(rideId)}');
    debugPrint('🔵 [Request] Body: {reason: $reason}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      final response = await http.post(
        Uri.parse(ApiConstants.cancelRideByDriver(rideId)),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'reason': reason}),
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] cancelRideByDriver Success');
        return responseData;
      } else if (response.statusCode == 400) {
        debugPrint(
          '🔴 [ApiService] cancelRideByDriver Failed: ${responseData['message']}',
        );
        return {
          'success': false,
          'message': responseData['message'] ?? 'Cannot cancel ride',
          'error': responseData['error'] ?? 'Bad Request',
        };
      } else {
        debugPrint('🔴 [ApiService] cancelRideByDriver Failed');
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to cancel ride',
        };
      }
    } catch (e) {
      debugPrint('🔴 [ApiService] cancelRideByDriver Error: $e');
      return {'success': false, 'message': 'Error cancelling ride: $e'};
    }
  }

  /// Driver ends ride early during an in-progress ride
  /// Returns adjusted fare based on actual distance traveled
  /// Valid reasons: user_requested, rider_misbehavior, safety_concern, wrong_destination, vehicle_issue
  ///
  /// Backend API: PATCH /api/v1/rides/{rideId}/end-early
  /// Request body: { driverLat, driverLon, earlyEndReason }
  /// Response: { status, actualDistance, fare, paymentStatus }
  Future<Map<String, dynamic>> endRideEarly(
    String rideId, {
    required double latitude,
    required double longitude,
    required String reason,
  }) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] endRideEarly called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.endRideEarly(rideId)}');
    debugPrint(
      '🔵 [Request] Body: {driverLat: $latitude, driverLon: $longitude, earlyEndReason: $reason}',
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      // Use PATCH method and match backend API field names
      final response = await http.patch(
        Uri.parse(ApiConstants.endRideEarly(rideId)),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'driverLat': latitude,
          'driverLon': longitude,
          'earlyEndReason':
              reason, // Matches: user_requested, safety_concern, etc.
        }),
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] endRideEarly Success');
        // Response contains: { status, actualDistance, fare, paymentStatus }
        return responseData;
      } else if (response.statusCode == 400) {
        debugPrint(
          '🔴 [ApiService] endRideEarly Failed: ${responseData['message']}',
        );
        return {
          'success': false,
          'message': responseData['message'] ?? 'Cannot end ride early',
          'error': responseData['error'] ?? 'Bad Request',
        };
      } else {
        debugPrint('🔴 [ApiService] endRideEarly Failed');
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to end ride early',
        };
      }
    } catch (e) {
      debugPrint('🔴 [ApiService] endRideEarly Error: $e');
      return {'success': false, 'message': 'Error ending ride early: $e'};
    }
  }

  Future<Map<String, dynamic>> rateRide({
    required String bookingId,
    required int rating,
    required String feedback,
    double? tip, // Kept as optional but not sent in body
  }) async {
    // Using the endpoint specified by the user: POST /rides/{rideId}/rate
    // Body strictly as requested: { "rating": 5, "feedback": "..." }
    return await _postRequest('$baseUrl/rides/$bookingId/rate', {
      'rating': rating,
      'feedback': feedback,
    });
  }

  Future<Map<String, dynamic>> selectPaymentMethod(
    String rideId,
    String paymentMethod,
  ) async {
    return await _postRequest(ApiConstants.selectPaymentMethod(rideId), {
      'paymentMethod': paymentMethod,
    });
  }

  Future<Map<String, dynamic>> confirmCashCollection(String rideId) async {
    return await _postRequest(ApiConstants.confirmCash(rideId), {});
  }

  Future<Map<String, dynamic>> _postRequest(
    String url,
    Map<String, dynamic> body,
  ) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] POST Request');
    debugPrint('🔵 [Request] URL: $url');
    debugPrint('🔵 [Request] Body: $body');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] Request Failed: ${response.body}');
        try {
          // Try to decode the error body to return specific error messages
          return jsonDecode(response.body);
        } catch (e) {
          // If decoding fails, return generic error
          return {
            'success': false,
            'message': 'Request failed: ${response.statusCode}',
          };
        }
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  Future<Map<String, dynamic>> getRideDetails(String rideId) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] getRideDetails called');
    final url = ApiConstants.getRideDetails(rideId);
    debugPrint('🔵 [Request] URL: $url');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] getRideDetails Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] getRideDetails Failed: ${response.body}');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to get ride details: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to get ride details: $e');
    }
  }

  Future<Map<String, dynamic>> getDriverProfile() async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] getDriverProfile called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.driverProfile}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      debugPrint(
        '🔵 [Request] Headers: Authorization: Bearer ${token.substring(0, 10)}...',
      );

      final response = await http.get(
        Uri.parse(ApiConstants.driverProfile),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] getDriverProfile Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] getDriverProfile Failed: ${response.body}');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to get driver profile: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to get driver profile: $e');
    }
  }

  Future<Map<String, dynamic>> uploadVehicleImages(List<File> images) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] uploadVehicleImages called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.uploadVehicleImages}');
    debugPrint('🔵 [Request] Image Count: ${images.length}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiConstants.uploadVehicleImages),
      );
      request.headers['Authorization'] = 'Bearer $token';

      for (var image in images) {
        request.files.add(
          await http.MultipartFile.fromPath('vehicleImages', image.path),
        );
      }

      debugPrint('🔵 [Request] Sending multipart request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] uploadVehicleImages Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint(
          '🔴 [ApiService] uploadVehicleImages Failed: ${response.body}',
        );
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to upload vehicle images: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to upload vehicle images: $e');
    }
  }

  Future<Map<String, dynamic>> deleteVehicleImage(String publicId) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] deleteVehicleImage called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.deleteVehicleImage}');
    debugPrint('🔵 [Request] Public ID: $publicId');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      final uri = Uri.parse(
        ApiConstants.deleteVehicleImage,
      ).replace(queryParameters: {'publicId': publicId});

      final response = await http.delete(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] deleteVehicleImage Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint(
          '🔴 [ApiService] deleteVehicleImage Failed: ${response.body}',
        );
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to delete vehicle image: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to delete vehicle image: $e');
    }
  }

  Future<Map<String, dynamic>> uploadDriverLicense(File licenseDocument) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] uploadDriverLicense called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.uploadLicense}');
    debugPrint('🔵 [Request] File: ${licenseDocument.path}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiConstants.uploadLicense),
      );
      request.headers['Authorization'] = 'Bearer $token';

      // Get the file extension and determine the correct MIME type
      final filePath = licenseDocument.path;
      final fileName = filePath.split('/').last;
      final extension = fileName.split('.').last.toLowerCase();

      String contentType;
      switch (extension) {
        case 'pdf':
          contentType = 'application/pdf';
          break;
        case 'doc':
          contentType = 'application/msword';
          break;
        case 'docx':
          contentType =
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
          break;
        default:
          contentType = 'application/octet-stream';
      }

      debugPrint('🔵 [Request] File name: $fileName');
      debugPrint('🔵 [Request] Extension: $extension');
      debugPrint('🔵 [Request] Content-Type: $contentType');

      request.files.add(
        await http.MultipartFile.fromPath(
          'document',
          licenseDocument.path,
          filename: fileName,
          contentType: MediaType.parse(contentType),
        ),
      );

      debugPrint('🔵 [Request] Sending multipart request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] uploadDriverLicense Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint(
          '🔴 [ApiService] uploadDriverLicense Failed: ${response.body}',
        );
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to upload driver license: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to upload driver license: $e');
    }
  }

  Future<Map<String, dynamic>> updateDriverLicense(File licenseDocument) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] updateDriverLicense called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.updateLicense}');
    debugPrint('🔵 [Request] File: ${licenseDocument.path}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      var request = http.MultipartRequest(
        'PUT',
        Uri.parse(ApiConstants.updateLicense),
      );
      request.headers['Authorization'] = 'Bearer $token';

      // Get the file extension and determine the correct MIME type
      final filePath = licenseDocument.path;
      final fileName = filePath.split('/').last;
      final extension = fileName.split('.').last.toLowerCase();

      String contentType;
      switch (extension) {
        case 'pdf':
          contentType = 'application/pdf';
          break;
        case 'doc':
          contentType = 'application/msword';
          break;
        case 'docx':
          contentType =
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
          break;
        default:
          contentType = 'application/octet-stream';
      }

      debugPrint('🔵 [Request] File name: $fileName');
      debugPrint('🔵 [Request] Extension: $extension');
      debugPrint('🔵 [Request] Content-Type: $contentType');

      request.files.add(
        await http.MultipartFile.fromPath(
          'document',
          licenseDocument.path,
          filename: fileName,
          contentType: MediaType.parse(contentType),
        ),
      );

      debugPrint('🔵 [Request] Sending multipart request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] updateDriverLicense Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint(
          '🔴 [ApiService] updateDriverLicense Failed: ${response.body}',
        );
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to update driver license: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to update driver license: $e');
    }
  }

  Future<Map<String, dynamic>> deleteDriverLicense() async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] deleteDriverLicense called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.deleteLicense}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      final response = await http.delete(
        Uri.parse(ApiConstants.deleteLicense),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] deleteDriverLicense Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint(
          '🔴 [ApiService] deleteDriverLicense Failed: ${response.body}',
        );
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to delete driver license: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to delete driver license: $e');
    }
  }

  /// Generic Document Upload/Update for Sections 1 & 2
  /// Uses the new standardized API endpoint: POST /api/v1/drivers/documents/:type
  /// Supports: licenseFront, licenseBack, privateHireLicence, roadTax, mot, insurance
  Future<Map<String, dynamic>> uploadDocument(
    String documentType,
    File document,
  ) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] uploadDocument called');
    debugPrint('🔵 [Request] Document Type: $documentType');
    debugPrint('🔵 [Request] URL: ${ApiConstants.uploadDocument(documentType)}');
    debugPrint('🔵 [Request] File: ${document.path}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiConstants.uploadDocument(documentType)),
      );
      request.headers['Authorization'] = 'Bearer $token';

      // Get the file extension and determine the correct MIME type
      final filePath = document.path;
      final fileName = filePath.split('/').last;
      final extension = fileName.split('.').last.toLowerCase();

      String contentType;
      switch (extension) {
        case 'pdf':
          contentType = 'application/pdf';
          break;
        case 'doc':
          contentType = 'application/msword';
          break;
        case 'docx':
          contentType =
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
          break;
        case 'jpg':
        case 'jpeg':
          contentType = 'image/jpeg';
          break;
        case 'png':
          contentType = 'image/png';
          break;
        case 'heic':
          contentType = 'image/heic';
          break;
        default:
          contentType = 'application/octet-stream';
      }

      debugPrint('🔵 [Request] File name: $fileName');
      debugPrint('🔵 [Request] Extension: $extension');
      debugPrint('🔵 [Request] Content-Type: $contentType');

      request.files.add(
        await http.MultipartFile.fromPath(
          'document',
          document.path,
          filename: fileName,
          contentType: MediaType.parse(contentType),
        ),
      );

      debugPrint('🔵 [Request] Sending multipart request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] uploadDocument Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint(
          '🔴 [ApiService] uploadDocument Failed: ${response.body}',
        );
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to upload document: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to upload document: $e');
    }
  }

  /// Delete a specific document
  /// DELETE /api/v1/drivers/documents/:type
  Future<Map<String, dynamic>> deleteDocument(String documentType) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] deleteDocument called');
    debugPrint('🔵 [Request] Document Type: $documentType');
    debugPrint('🔵 [Request] URL: ${ApiConstants.deleteDocument(documentType)}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      final response = await http.delete(
        Uri.parse(ApiConstants.deleteDocument(documentType)),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] deleteDocument Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint(
          '🔴 [ApiService] deleteDocument Failed: ${response.body}',
        );
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to delete document: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to delete document: $e');
    }
  }

  /// Update driver's location (called after login or periodically)
  Future<Map<String, dynamic>> updateDriverLocation({
    required double latitude,
    required double longitude,
  }) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] updateDriverLocation called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.updateDriverLocation}');
    debugPrint(
      '🔵 [Request] Body: {"latitude": $latitude, "longitude": $longitude}',
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      debugPrint(
        '🔵 [Request] Headers: Authorization: Bearer ${token.substring(0, 10)}...',
      );

      final response = await http.patch(
        Uri.parse(ApiConstants.updateDriverLocation),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] Driver location updated successfully');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint(
          '🔴 [ApiService] Failed to update driver location: ${response.body}',
        );
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return {'success': false, 'message': 'Failed to update location'};
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception updating driver location: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      return {'success': false, 'message': 'Error updating location: $e'};
    }
  }

  Future<Map<String, dynamic>> updateDriverStatus(bool isOnline) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] updateDriverStatus called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.updateDriverStatus}');
    debugPrint('🔵 [Request] Body: {"isOnline": $isOnline}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      debugPrint(
        '🔵 [Request] Headers: Authorization: Bearer ${token.substring(0, 10)}...',
      );

      final response = await http.patch(
        Uri.parse(ApiConstants.updateDriverStatus),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'isOnline': isOnline}),
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] updateDriverStatus Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint(
          '🔴 [ApiService] updateDriverStatus Failed: ${response.body}',
        );
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        // Return the error response instead of throwing, so caller can handle error codes
        try {
          final errorResponse = jsonDecode(response.body);
          return errorResponse;
        } catch (e) {
          // If response body is not valid JSON, return a structured error
          return {
            'success': false,
            'message': 'Failed to update driver status',
            'statusCode': response.statusCode,
          };
        }
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      // Return error instead of throwing for better error handling
      return {
        'success': false,
        'message': 'Error updating driver status: $e',
      };
    }
  }

  Future<Map<String, dynamic>> updateDriverProfilePicture(File image) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] updateDriverProfilePicture called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.updateDriver}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      var request = http.MultipartRequest(
        'PATCH',
        Uri.parse(ApiConstants.updateDriver),
      );
      request.headers['Authorization'] = 'Bearer $token';

      request.files.add(
        await http.MultipartFile.fromPath('profilePicture', image.path),
      );

      debugPrint('🔵 [Request] Sending multipart request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] updateDriverProfilePicture Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint(
          '🔴 [ApiService] updateDriverProfilePicture Failed: ${response.body}',
        );
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to update profile picture: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to update profile picture: $e');
    }
  }

  Future<Map<String, dynamic>> updateDriverProfile(
    Map<String, dynamic> data,
  ) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] updateDriverProfile called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.updateDriver}');
    debugPrint('🔵 [Request] Body: $data');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      final response = await http.patch(
        Uri.parse(ApiConstants.updateDriver),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(data),
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] updateDriverProfile Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint(
          '🔴 [ApiService] updateDriverProfile Failed: ${response.body}',
        );
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to update driver profile: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to update driver profile: $e');
    }
  }

  Future<Map<String, dynamic>> getRideHistory() async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] getRideHistory called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.rideHistory}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      debugPrint(
        '🔵 [Request] Headers: Authorization: Bearer ${token.substring(0, 10)}...',
      );

      final response = await http.get(
        Uri.parse(ApiConstants.rideHistory),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] getRideHistory Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] getRideHistory Failed: ${response.body}');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to get ride history: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      rethrow;
    }
  }

  /// Fetch the current user's promo (free ride) status.
  /// Returns completedRides, promoStatus ("none" | "eligible" | "claimed"),
  /// ridesUntilEligible, isEligible, isClaimed, and a human‑readable message.
  Future<Map<String, dynamic>> getPromoStatus() async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] getPromoStatus called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.promoStatus}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_prefsAuthTokenKey);

      if (token == null) {
        throw Exception('No auth token found');
      }

      final response = await http.get(
        Uri.parse(ApiConstants.promoStatus),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');

      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] getPromoStatus Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] getPromoStatus Failed: ${response.body}');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return {'success': false, 'message': 'Failed to get promo status'};
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] getPromoStatus Exception: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      return {'success': false, 'message': 'Error fetching promo status: $e'};
    }
  }

  Future<Map<String, dynamic>> getDriverRides() async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] getDriverRides called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.driverRides}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_prefsAuthTokenKey);

      if (token == null) {
        throw Exception('No auth token found');
      }

      final response = await http.get(
        Uri.parse(ApiConstants.driverRides),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // Check for 401 unauthorized
      await _checkUnauthorized(response);

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] getDriverRides Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] getDriverRides Failed: ${response.body}');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to get ride history: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to get ride history: $e');
    }
  }

  /// Update FCM token for user profile (Option 2 - dedicated endpoint)
  Future<Map<String, dynamic>> updateUserFcmToken(String? fcmToken) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] updateUserFcmToken called');
    debugPrint('🔵 [Request] URL: $baseUrl/users/fcm-token');
    
    if (fcmToken == null) {
      debugPrint('🔵 [Request] FCM Token: null (clearing token)');
    } else {
      debugPrint(
        '🔵 [Request] FCM Token: ${fcmToken.substring(0, fcmToken.length > 20 ? 20 : fcmToken.length)}...',
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_prefsAuthTokenKey);

      if (token == null) {
        throw Exception('No auth token found');
      }

      final response = await http.patch(
        Uri.parse('$baseUrl/users/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'fcmToken': fcmToken}),
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // NOTE: No 401 check here - this is called during logout, don't trigger another logout

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] updateUserFcmToken Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint(
          '🔴 [ApiService] updateUserFcmToken Failed: ${response.body}',
        );
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to update FCM token: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to update FCM token: $e');
    }
  }

  /// Update FCM token for driver profile (Option 2 - dedicated endpoint)
  Future<Map<String, dynamic>> updateDriverFcmToken(String? fcmToken) async {
    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [ApiService] updateDriverFcmToken called');
    debugPrint('🔵 [Request] URL: $baseUrl/drivers/fcm-token');
    
    if (fcmToken == null) {
      debugPrint('🔵 [Request] FCM Token: null (clearing token)');
    } else {
      debugPrint(
        '🔵 [Request] FCM Token: ${fcmToken.substring(0, fcmToken.length > 20 ? 20 : fcmToken.length)}...',
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_prefsAuthTokenKey);

      if (token == null) {
        throw Exception('No auth token found');
      }

      final response = await http.patch(
        Uri.parse('$baseUrl/drivers/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'fcmToken': fcmToken}),
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');
      
      // NOTE: No 401 check here - this is called during logout, don't trigger another logout

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] updateDriverFcmToken Success');
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        return jsonDecode(response.body);
      } else {
        debugPrint(
          '🔴 [ApiService] updateDriverFcmToken Failed: ${response.body}',
        );
        debugPrint(
          '🔵 ------------------------------------------------------------------',
        );
        throw Exception('Failed to update FCM token: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint(
        '🔵 ------------------------------------------------------------------',
      );
      throw Exception('Failed to update FCM token: $e');
    }
  }
}
