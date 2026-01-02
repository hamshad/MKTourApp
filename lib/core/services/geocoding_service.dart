import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class GeocodingService {
  static const String _baseUrl = 'https://nominatim.openstreetmap.org';
  // Nominatim requires a User-Agent to identify the application
  static const Map<String, String> _headers = {
    'User-Agent': 'SkylineApp/1.0 (com.mktours.app)',
  };

  /// Get address from latitude and longitude (Reverse Geocoding)
  Future<String?> getAddressFromLatLng(double lat, double lng) async {
    try {
      final url = Uri.parse(
          '$_baseUrl/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1');
      
      debugPrint('📍 GeocodingService: Fetching address for $lat, $lng');
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Construct a readable address
        final address = data['display_name'] as String?;
        debugPrint('📍 GeocodingService: Found address: $address');
        return address;
      } else {
        debugPrint('❌ GeocodingService: Failed to fetch address. Status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ GeocodingService: Error fetching address: $e');
      return null;
    }
  }

  /// Search for an address (Forward Geocoding)
  Future<List<Map<String, dynamic>>> searchAddress(String query) async {
    if (query.isEmpty) return [];

    try {
      final url = Uri.parse(
          '$_baseUrl/search?q=${Uri.encodeComponent(query)}&format=json&addressdetails=1&limit=5');
      
      debugPrint('📍 GeocodingService: Searching for "$query"');
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        debugPrint('📍 GeocodingService: Found ${data.length} results');
        
        return data.map((item) => {
          'display_name': item['display_name'],
          'lat': double.parse(item['lat']),
          'lon': double.parse(item['lon']),
          'type': item['type'],
        }).toList();
      } else {
        debugPrint('❌ GeocodingService: Failed to search address. Status: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('❌ GeocodingService: Error searching address: $e');
      return [];
    }
  }
}
