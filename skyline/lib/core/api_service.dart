import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';

import 'constants/api_constants.dart';

class ApiService {
  final String baseUrl = AppConstants.apiBaseUrl;

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
          await prefs.setString('auth_token', responseData['token']);
        }
        return responseData;
      } else {
        throw Exception('Failed to login: ${response.body}');
      }
    } catch (e) {
      // Return mock success if server is unreachable for demo purposes
      print('API Error: $e. Returning mock success.');
      // Mock token saving
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', 'mock_token_fallback');
      
      return {
        'success': true,
        'token': 'mock_token_fallback',
        'user': {'id': 1, 'firstName': 'Demo', 'lastName': 'User', 'email': email}
      };
    }
  }

  Future<Map<String, dynamic>> signup(String email, String password, String firstName, String lastName) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'firstName': firstName,
          'lastName': lastName
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true && responseData['token'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', responseData['token']);
        }
        return responseData;
      } else {
        throw Exception('Failed to signup: ${response.body}');
      }
    } catch (e) {
      print('API Error: $e. Returning mock success.');
      // Mock token saving
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', 'mock_token_fallback');
      
      return {
        'success': true,
        'token': 'mock_token_fallback',
        'user': {'id': 2, 'firstName': firstName, 'lastName': lastName, 'email': email}
      };
    }
  }

  Future<Map<String, dynamic>> bookRide(Map<String, dynamic> bookingDetails) async {
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
       print('API Error: $e. Returning mock booking.');
       return {
            'success': true,
            'bookingId': "book_mock_${DateTime.now().millisecondsSinceEpoch}",
            'status': "driver_assigned",
            'otp': "1234",  // Add OTP to mock
            'driver': { "name": "Mock Driver", "vehicle": "Mock Car", "plate": "MOCK 123", "rating": 5.0 },
            'eta': "5 mins",
            'fare': 15.50
        };
    }
  }

  Future<Map<String, dynamic>> getRideStatus(String rideId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/ride-status/$rideId'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get status');
      }
    } catch (e) {
      // Mock status for demo
      return {
        'status': 'driver_assigned',
        'location': {'lat': 51.5074, 'lng': -0.1278}
      };
    }
  }
  
  static Future<Map<String, dynamic>> completeRide({
    required String bookingId,
    required int rating,
    required double tip,
    required String feedback,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/complete-ride'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'bookingId': bookingId,
          'rating': rating,
          'tip': tip,
          'feedback': feedback,
        }),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to complete ride');
      }
    } catch (e) {
      print('API Error: $e. Returning mock completion.');
      return {
        'success': true,
        'fare': {
          'base': 2.50,
          'distance': 8.20,
          'time': 2.30,
          'subtotal': 13.00,
          'tip': tip,
          'total': 13.00 + tip,
        },
      };
    }
  }
  Future<Map<String, dynamic>> sendOtp(String phone) async {
    debugPrint('🔵 ------------------------------------------------------------------');
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
        debugPrint('🔵 ------------------------------------------------------------------');
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] sendOtp Failed: ${response.body}');
        debugPrint('🔵 ------------------------------------------------------------------');
        throw Exception('Failed to send OTP: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint('🔵 ------------------------------------------------------------------');
      throw Exception('Failed to send OTP: $e');
    }
  }
  Future<Map<String, dynamic>> checkPhone(String phone, String role) async {
    debugPrint('🔵 ------------------------------------------------------------------');
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
        debugPrint('🔵 ------------------------------------------------------------------');
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] checkPhone Failed: ${response.body}');
        debugPrint('🔵 ------------------------------------------------------------------');
        throw Exception('Failed to check phone: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint('🔵 ------------------------------------------------------------------');
      throw Exception('Failed to check phone: $e');
    }
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String otp,
    required String role,
    String? name, // Made nullable
    Map<String, dynamic>? vehicleDetails,
  }) async {
    debugPrint('🔵 ------------------------------------------------------------------');
    debugPrint('🔵 [ApiService] verifyOtp called');
    
    final Map<String, dynamic> requestBody = {
      'phone': phone,
      'otp': otp,
      'role': role,
    };

    if (name != null) {
      requestBody['name'] = name;
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
            await prefs.setString('auth_token', token);
            debugPrint('✅ [ApiService] Token saved successfully');
          }
        }
        
        debugPrint('🔵 ------------------------------------------------------------------');
        return responseData;
      } else {
        debugPrint('🔴 [ApiService] verifyOtp Failed: ${response.body}');
        debugPrint('🔵 ------------------------------------------------------------------');
        throw Exception('Failed to verify OTP: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint('🔵 ------------------------------------------------------------------');
      throw Exception('Failed to verify OTP: $e');
    }
  }
  Future<Map<String, dynamic>> getUserProfile() async {
    debugPrint('🔵 ------------------------------------------------------------------');
    debugPrint('🔵 [ApiService] getUserProfile called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.userProfile}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      debugPrint('🔵 [Request] Headers: Authorization: Bearer ${token.substring(0, 10)}...');

      final response = await http.get(
        Uri.parse(ApiConstants.userProfile),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] getUserProfile Success');
        debugPrint('🔵 ------------------------------------------------------------------');
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] getUserProfile Failed: ${response.body}');
        debugPrint('🔵 ------------------------------------------------------------------');
        throw Exception('Failed to get user profile: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint('🔵 ------------------------------------------------------------------');
      throw Exception('Failed to get user profile: $e');
    }
  }
  Future<Map<String, dynamic>> createRide(Map<String, dynamic> rideData) async {
    debugPrint('🔵 ------------------------------------------------------------------');
    debugPrint('🔵 [ApiService] createRide called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.createRide}');
    debugPrint('🔵 [Request] Body: $rideData');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

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

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('🟢 [ApiService] createRide Success');
        debugPrint('🔵 ------------------------------------------------------------------');
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] createRide Failed: ${response.body}');
        debugPrint('🔵 ------------------------------------------------------------------');
        throw Exception('Failed to create ride: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint('🔵 ------------------------------------------------------------------');
      throw Exception('Failed to create ride: $e');
    }
  }

  Future<Map<String, dynamic>> getRideDetails(String rideId) async {
    debugPrint('🔵 ------------------------------------------------------------------');
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

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] getRideDetails Success');
        debugPrint('🔵 ------------------------------------------------------------------');
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] getRideDetails Failed: ${response.body}');
        debugPrint('🔵 ------------------------------------------------------------------');
        throw Exception('Failed to get ride details: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint('🔵 ------------------------------------------------------------------');
      throw Exception('Failed to get ride details: $e');
    }
  }
  Future<Map<String, dynamic>> getDriverProfile() async {
    debugPrint('🔵 ------------------------------------------------------------------');
    debugPrint('🔵 [ApiService] getDriverProfile called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.driverProfile}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      debugPrint('🔵 [Request] Headers: Authorization: Bearer ${token.substring(0, 10)}...');

      final response = await http.get(
        Uri.parse(ApiConstants.driverProfile),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] getDriverProfile Success');
        debugPrint('🔵 ------------------------------------------------------------------');
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] getDriverProfile Failed: ${response.body}');
        debugPrint('🔵 ------------------------------------------------------------------');
        throw Exception('Failed to get driver profile: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint('🔵 ------------------------------------------------------------------');
      throw Exception('Failed to get driver profile: $e');
    }
  }

  Future<Map<String, dynamic>> uploadVehicleImages(List<File> images) async {
    debugPrint('🔵 ------------------------------------------------------------------');
    debugPrint('🔵 [ApiService] uploadVehicleImages called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.uploadVehicleImages}');
    debugPrint('🔵 [Request] Image Count: ${images.length}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      var request = http.MultipartRequest('POST', Uri.parse(ApiConstants.uploadVehicleImages));
      request.headers['Authorization'] = 'Bearer $token';

      for (var image in images) {
        request.files.add(await http.MultipartFile.fromPath('vehicleImages', image.path));
      }

      debugPrint('🔵 [Request] Sending multipart request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] uploadVehicleImages Success');
        debugPrint('🔵 ------------------------------------------------------------------');
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] uploadVehicleImages Failed: ${response.body}');
        debugPrint('🔵 ------------------------------------------------------------------');
        throw Exception('Failed to upload vehicle images: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint('🔵 ------------------------------------------------------------------');
      throw Exception('Failed to upload vehicle images: $e');
    }
  }

  Future<Map<String, dynamic>> deleteVehicleImage(String publicId) async {
    debugPrint('🔵 ------------------------------------------------------------------');
    debugPrint('🔵 [ApiService] deleteVehicleImage called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.deleteVehicleImage}');
    debugPrint('🔵 [Request] Public ID: $publicId');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      final uri = Uri.parse(ApiConstants.deleteVehicleImage).replace(queryParameters: {'publicId': publicId});
      
      final response = await http.delete(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] deleteVehicleImage Success');
        debugPrint('🔵 ------------------------------------------------------------------');
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] deleteVehicleImage Failed: ${response.body}');
        debugPrint('🔵 ------------------------------------------------------------------');
        throw Exception('Failed to delete vehicle image: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint('🔵 ------------------------------------------------------------------');
      throw Exception('Failed to delete vehicle image: $e');
    }
  }

  Future<Map<String, dynamic>> uploadDriverLicense(File licenseDocument) async {
    debugPrint('🔵 ------------------------------------------------------------------');
    debugPrint('🔵 [ApiService] uploadDriverLicense called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.uploadLicense}');
    debugPrint('🔵 [Request] File: ${licenseDocument.path}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      var request = http.MultipartRequest('POST', Uri.parse(ApiConstants.uploadLicense));
      request.headers['Authorization'] = 'Bearer $token';
      
      request.files.add(await http.MultipartFile.fromPath('document', licenseDocument.path));

      debugPrint('🔵 [Request] Sending multipart request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] uploadDriverLicense Success');
        debugPrint('🔵 ------------------------------------------------------------------');
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] uploadDriverLicense Failed: ${response.body}');
        debugPrint('🔵 ------------------------------------------------------------------');
        throw Exception('Failed to upload driver license: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint('🔵 ------------------------------------------------------------------');
      throw Exception('Failed to upload driver license: $e');
    }
  }

  Future<Map<String, dynamic>> updateDriverStatus(bool isOnline) async {
    debugPrint('🔵 ------------------------------------------------------------------');
    debugPrint('🔵 [ApiService] updateDriverStatus called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.updateDriverStatus}');
    debugPrint('🔵 [Request] Body: {"isOnline": $isOnline}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      debugPrint('🔵 [Request] Headers: Authorization: Bearer ${token.substring(0, 10)}...');

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

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] updateDriverStatus Success');
        debugPrint('🔵 ------------------------------------------------------------------');
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] updateDriverStatus Failed: ${response.body}');
        debugPrint('🔵 ------------------------------------------------------------------');
        throw Exception('Failed to update driver status: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint('🔵 ------------------------------------------------------------------');
      throw Exception('Failed to update driver status: $e');
    }
  }
  Future<Map<String, dynamic>> updateDriverProfilePicture(File image) async {
    debugPrint('🔵 ------------------------------------------------------------------');
    debugPrint('🔵 [ApiService] updateDriverProfilePicture called');
    debugPrint('🔵 [Request] URL: ${ApiConstants.updateDriver}');
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('No auth token found');
      }

      var request = http.MultipartRequest('PATCH', Uri.parse(ApiConstants.updateDriver));
      request.headers['Authorization'] = 'Bearer $token';
      
      request.files.add(await http.MultipartFile.fromPath('profilePicture', image.path));

      debugPrint('🔵 [Request] Sending multipart request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('🟣 [Response] Status Code: ${response.statusCode}');
      debugPrint('🟣 [Response] Body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] updateDriverProfilePicture Success');
        debugPrint('🔵 ------------------------------------------------------------------');
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] updateDriverProfilePicture Failed: ${response.body}');
        debugPrint('🔵 ------------------------------------------------------------------');
        throw Exception('Failed to update profile picture: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint('🔵 ------------------------------------------------------------------');
      throw Exception('Failed to update profile picture: $e');
    }
  }

  Future<Map<String, dynamic>> updateDriverProfile(Map<String, dynamic> data) async {
    debugPrint('🔵 ------------------------------------------------------------------');
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

      if (response.statusCode == 200) {
        debugPrint('🟢 [ApiService] updateDriverProfile Success');
        debugPrint('🔵 ------------------------------------------------------------------');
        return jsonDecode(response.body);
      } else {
        debugPrint('🔴 [ApiService] updateDriverProfile Failed: ${response.body}');
        debugPrint('🔵 ------------------------------------------------------------------');
        throw Exception('Failed to update driver profile: ${response.body}');
      }
    } catch (e) {
      debugPrint('🟠 [ApiService] Exception caught: $e');
      debugPrint('🔵 ------------------------------------------------------------------');
      throw Exception('Failed to update driver profile: $e');
    }
  }
}
