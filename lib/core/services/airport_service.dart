import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../constants/api_constants.dart';
import '../models/airport.dart';

/// Service for managing airport-related API calls
class AirportService {
  /// Get all active airports
  Future<List<Airport>> getActiveAirports() async {
    try {
      final headers = await ApiConfig.getAuthHeaders();
      final url = Uri.parse(ApiConstants.airports);

      debugPrint('✈️ ─────────────────────────────────────────────');
      debugPrint('✈️ AirportService.getActiveAirports()');
      debugPrint('✈️ [Request] URL: $url');

      final response = await http.get(url, headers: headers);
      debugPrint('✈️ [Response] Status Code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        debugPrint('✈️ [Response] Body: ${response.body}');

        if (responseData['success'] == true) {
          final List<dynamic> data = responseData['data'] ?? [];
          final airports = data
              .map((json) => Airport.fromJson(json as Map<String, dynamic>))
              .where((airport) => airport.isActive)
              .toList();

          debugPrint(
            '🟢 AirportService.getActiveAirports() Success: Found ${airports.length} airports',
          );
          debugPrint('✈️ ─────────────────────────────────────────────');
          return airports;
        } else {
          debugPrint(
            '⚠️ AirportService.getActiveAirports() - API error: ${responseData['message']}',
          );
          debugPrint('✈️ ─────────────────────────────────────────────');
          return [];
        }
      } else {
        debugPrint(
          '❌ AirportService.getActiveAirports() - HTTP Error: ${response.statusCode}',
        );
        debugPrint('❌ Response: ${response.body}');
        debugPrint('✈️ ─────────────────────────────────────────────');
        return [];
      }
    } catch (e, stackTrace) {
      debugPrint('❌ AirportService.getActiveAirports() - Exception: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      debugPrint('✈️ ─────────────────────────────────────────────');
      return [];
    }
  }

  /// Get fixed price for a specific airport and vehicle category
  Future<double?> getAirportPrice(
    String placeId,
    String vehicleCategory,
  ) async {
    try {
      final headers = await ApiConfig.getAuthHeaders();
      final url = Uri.parse(
        '${ApiConstants.getAirportPrice(placeId)}?vehicleCategory=$vehicleCategory',
      );

      debugPrint('✈️ ─────────────────────────────────────────────');
      debugPrint('✈️ AirportService.getAirportPrice()');
      debugPrint('✈️ [Request] URL: $url');
      debugPrint('✈️ [Request] PlaceId: $placeId');
      debugPrint('✈️ [Request] Vehicle: $vehicleCategory');

      final response = await http.get(url, headers: headers);
      debugPrint('✈️ [Response] Status Code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        debugPrint('✈️ [Response] Body: ${response.body}');

        if (responseData['success'] == true) {
          final fixedPrice = responseData['data']['fixedPrice'];
          final price = (fixedPrice is int)
              ? fixedPrice.toDouble()
              : (fixedPrice as num).toDouble();

          debugPrint(
            '🟢 AirportService.getAirportPrice() Success: £$price',
          );
          debugPrint('✈️ ─────────────────────────────────────────────');
          return price;
        }
      } else if (response.statusCode == 404) {
        debugPrint('ℹ️ AirportService.getAirportPrice() - Not an airport');
        debugPrint('✈️ ─────────────────────────────────────────────');
        return null;
      }

      debugPrint('⚠️ AirportService.getAirportPrice() - Failed');
      debugPrint('✈️ ─────────────────────────────────────────────');
      return null;
    } catch (e) {
      debugPrint('❌ AirportService.getAirportPrice() - Exception: $e');
      debugPrint('✈️ ─────────────────────────────────────────────');
      return null;
    }
  }
}
