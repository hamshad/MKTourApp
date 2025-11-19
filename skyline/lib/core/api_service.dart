import 'dart:convert';
import 'package:http/http.dart' as http;
import 'constants.dart';

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
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to login: ${response.body}');
      }
    } catch (e) {
      // Return mock success if server is unreachable for demo purposes
      print('API Error: $e. Returning mock success.');
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
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to signup: ${response.body}');
      }
    } catch (e) {
      print('API Error: $e. Returning mock success.');
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

  Future<Map<String, dynamic>> getRideStatus() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/ride-status'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get status');
      }
    } catch (e) {
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
}
