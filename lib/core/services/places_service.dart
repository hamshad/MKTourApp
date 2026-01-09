import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../constants/api_constants.dart';

/// Places API Service using backend proxy for secure API key management
/// All requests go through your backend which handles Google API calls
class PlacesService {
  /// Search for places using autocomplete
  /// Uses session token for billing optimization
  Future<List<Map<String, dynamic>>> searchPlaces(
    String query, {
    String? sessionToken,
  }) async {
    if (query.isEmpty) return [];

    try {
      final token = sessionToken ?? ApiConfig.sessionToken;
      final headers = await ApiConfig.getAuthHeaders();

      final url = Uri.parse(
        '${ApiConstants.getSuggestions}?input=${Uri.encodeComponent(query)}&sessionToken=$token',
      );

      debugPrint('🔍 ─────────────────────────────────────────────');
      debugPrint('🔍 PlacesService.searchPlaces()');
      debugPrint('🔍 [Request] URL: $url');
      debugPrint('🔍 [Request] Query: "$query"');
      debugPrint('🔍 [Request] Session Token: $token');

      final response = await http.get(url, headers: headers);

      debugPrint('🔍 [Response] Status Code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint(
          '🔍 [Response] Body: ${response.body.length > 500 ? '${response.body.substring(0, 500)}...' : response.body}',
        );

        if (data['success'] == true || data['status'] == 'OK') {
          // Backend returns 'data' array with suggestions
          final List<dynamic> predictions =
              data['data'] ?? data['predictions'] ?? data['suggestions'] ?? [];
          debugPrint(
            '🟢 PlacesService.searchPlaces() Success: Found ${predictions.length} results',
          );
          debugPrint('🔵 ─────────────────────────────────────────────');

          return predictions
              .map(
                (prediction) => {
                  'place_id': prediction['place_id'] ?? '',
                  'description': prediction['description'] ?? '',
                  'main_text':
                      prediction['main_text'] ??
                      prediction['structured_formatting']?['main_text'] ??
                      prediction['description'] ??
                      '',
                  'secondary_text':
                      prediction['secondary_text'] ??
                      prediction['structured_formatting']?['secondary_text'] ??
                      '',
                },
              )
              .toList()
              .cast<Map<String, dynamic>>();
        } else {
          debugPrint(
            '🔴 PlacesService.searchPlaces() Failed: ${data['status'] ?? data['message']}',
          );
          debugPrint('🔵 ─────────────────────────────────────────────');
          return [];
        }
      } else {
        debugPrint(
          '🔴 PlacesService.searchPlaces() Failed: HTTP ${response.statusCode}',
        );
        debugPrint('🔴 [Response] Body: ${response.body}');
        debugPrint('🔵 ─────────────────────────────────────────────');
        return [];
      }
    } catch (e) {
      debugPrint('🔴 PlacesService.searchPlaces() Error: $e');
      debugPrint('🔵 ─────────────────────────────────────────────');
      return [];
    }
  }

  /// Get place details including coordinates from place ID
  /// Uses same session token to close billing cycle
  Future<Map<String, dynamic>?> getPlaceDetails(
    String placeId, {
    String? sessionToken,
  }) async {
    try {
      final token = sessionToken ?? ApiConfig.sessionToken;
      final headers = await ApiConfig.getAuthHeaders();

      final url = Uri.parse(
        '${ApiConstants.placeDetails}?placeId=$placeId&sessionToken=$token',
      );

      debugPrint('📍 ─────────────────────────────────────────────');
      debugPrint('📍 PlacesService.getPlaceDetails()');
      debugPrint('📍 [Request] URL: $url');
      debugPrint('📍 [Request] Place ID: $placeId');
      debugPrint('📍 [Request] Session Token: $token');

      final response = await http.get(url, headers: headers);
      debugPrint(
        '📍 [Response] Status Code: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        debugPrint(
          '📍 [Response] Body: ${response.body}',
        );

        if (responseData['success'] == true) {
          // Backend returns data object with lat, lng, formatted_address, name
          final data = responseData['data'] ?? responseData;

          debugPrint(
            '📍 PlacesService.getPlaceDetails - Found location: ${data['lat']}, ${data['lng']}',
          );
          debugPrint(
            '📍 PlacesService.getPlaceDetails - Address: ${data['formatted_address']}',
          );

          // Clear session token after successful place selection (closes billing cycle)
          ApiConfig.clearSessionToken();

          return {
            'name': data['name'] ?? '',
            'formatted_address': data['formatted_address'] ?? '',
            'lat': data['lat'] is double
                ? data['lat']
                : double.tryParse(data['lat']?.toString() ?? '0') ?? 0.0,
            'lng': data['lng'] is double
                ? data['lng']
                : double.tryParse(data['lng']?.toString() ?? '0') ?? 0.0,
          };
        } else {
          debugPrint(
            '⚠️ PlacesService.getPlaceDetails - API error: ${responseData['message']}',
          );
          debugPrint(
            '⚠️ PlacesService.getPlaceDetails - Full response: ${response.body}',
          );
          return null;
        }
      } else {
        debugPrint(
          '❌ PlacesService.getPlaceDetails - HTTP Error: ${response.statusCode}',
        );
        debugPrint(
          '❌ PlacesService.getPlaceDetails - Response: ${response.body}',
        );
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ PlacesService.getPlaceDetails - Exception: $e');
      debugPrint('❌ PlacesService.getPlaceDetails - Stack trace: $stackTrace');
      return null;
    }
  }

  /// Get address from latitude and longitude (Reverse Geocoding)
  Future<String?> getAddressFromLatLng(double lat, double lng) async {
    debugPrint('📍 PlacesService.getAddressFromLatLng - Starting request');
    debugPrint(
      '📍 PlacesService.getAddressFromLatLng - Coordinates: ($lat, $lng)',
    );

    try {
      final headers = await ApiConfig.getAuthHeaders();

      final url = Uri.parse('${ApiConstants.reverseGeocode}?lat=$lat&lng=$lng');

      debugPrint('📍 PlacesService.getAddressFromLatLng - URL: $url');
      final response = await http.get(url, headers: headers);
      debugPrint(
        '📍 PlacesService.getAddressFromLatLng - Response Status: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint(
          '📍 PlacesService.getAddressFromLatLng - Response Body: ${response.body}',
        );

        if (data['success'] == true || data['status'] == 'OK') {
          final address =
              data['formatted_address'] ??
              data['results']?[0]?['formatted_address'] ??
              data['address'];
          debugPrint(
            '📍 PlacesService.getAddressFromLatLng - Found address: $address',
          );
          return address;
        } else {
          debugPrint(
            '⚠️ PlacesService.getAddressFromLatLng - API error: ${data['status'] ?? data['message']}',
          );
          return null;
        }
      } else {
        debugPrint(
          '❌ PlacesService.getAddressFromLatLng - HTTP Error: ${response.statusCode}',
        );
        debugPrint(
          '❌ PlacesService.getAddressFromLatLng - Response: ${response.body}',
        );
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ PlacesService.getAddressFromLatLng - Exception: $e');
      debugPrint(
        '❌ PlacesService.getAddressFromLatLng - Stack trace: $stackTrace',
      );
      return null;
    }
  }

  /// Get route directions from origin to destination
  Future<Map<String, dynamic>?> getDirections(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) async {
    debugPrint('📍 PlacesService.getDirections - Starting request');
    debugPrint(
      '📍 PlacesService.getDirections - Origin: ($originLat, $originLng)',
    );
    debugPrint(
      '📍 PlacesService.getDirections - Destination: ($destLat, $destLng)',
    );

    try {
      final headers = await ApiConfig.getAuthHeaders();

      final url = Uri.parse(
        '${ApiConstants.getDirections}?origin=$originLat,$originLng&destination=$destLat,$destLng',
      );

      debugPrint('🗺️ ─────────────────────────────────────────────');
      debugPrint('🗺️ PlacesService.getDirections()');
      debugPrint('🗺️ [Request] URL: $url');
      debugPrint('🗺️ [Request] Origin: ($originLat, $originLng)');
      debugPrint('🗺️ [Request] Destination: ($destLat, $destLng)');

      final response = await http.get(url, headers: headers);
      debugPrint(
        '🗺️ [Response] Status Code: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint(
          '📍 PlacesService.getDirections - Response Body: ${response.body}',
        );

        if (data['success'] == true || data['status'] == 'OK') {
          // Backend returns polyline_points as encoded string
          final polylineString =
              data['polyline_points'] ??
              data['routes']?[0]?['overview_polyline']?['points'] ??
              '';

          // Decode polyline points for drawing route on map
          final polylinePoints = _decodePolyline(polylineString);

          final leg = data['routes']?[0]?['legs']?[0] ?? data;

          debugPrint(
            '📍 PlacesService.getDirections - Distance: ${leg['distance_text'] ?? leg['distance']?['text']}',
          );
          debugPrint(
            '📍 PlacesService.getDirections - Duration: ${leg['duration_text'] ?? leg['duration']?['text']}',
          );
          debugPrint(
            '📍 PlacesService.getDirections - Polyline points decoded: ${polylinePoints.length}',
          );

          return {
            'polyline': polylinePoints,
            'distance_meters':
                leg['distance_meters'] ?? leg['distance']?['value'] ?? 0,
            'distance_text':
                leg['distance_text'] ?? leg['distance']?['text'] ?? '',
            'duration_seconds':
                leg['duration_seconds'] ?? leg['duration']?['value'] ?? 0,
            'duration_text':
                leg['duration_text'] ?? leg['duration']?['text'] ?? '',
            'start_address': leg['start_address'] ?? '',
            'end_address': leg['end_address'] ?? '',
          };
        } else {
          debugPrint(
            '⚠️ PlacesService.getDirections - API error: ${data['status'] ?? data['message']}',
          );
          debugPrint(
            '⚠️ PlacesService.getDirections - Full response: ${response.body}',
          );
          return null;
        }
      } else {
        debugPrint(
          '❌ PlacesService.getDirections - HTTP Error: ${response.statusCode}',
        );
        debugPrint(
          '❌ PlacesService.getDirections - Response: ${response.body}',
        );
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ PlacesService.getDirections - Exception: $e');
      debugPrint('❌ PlacesService.getDirections - Stack trace: $stackTrace');
      return null;
    }
  }

  /// Get distance, duration and fare using backend Distance Matrix API
  /// This returns the actual fare calculated by the backend (secure pricing)
  /// vehicleType: 'sedan', 'suv', 'hatchback', 'van'
  Future<Map<String, dynamic>?> getDistanceAndFare({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    required String vehicleType,
  }) async {
    debugPrint('📍 PlacesService.getDistanceAndFare - Starting request');
    debugPrint(
      '📍 PlacesService.getDistanceAndFare - Origin: ($originLat, $originLng)',
    );
    debugPrint(
      '📍 PlacesService.getDistanceAndFare - Destination: ($destLat, $destLng)',
    );
    debugPrint(
      '📍 PlacesService.getDistanceAndFare - Vehicle Type: $vehicleType',
    );

    try {
      final headers = await ApiConfig.getAuthHeaders();

      final url = Uri.parse(
        '${ApiConstants.getDistanceTime}?origin=$originLat,$originLng&destination=$destLat,$destLng&vehicleType=$vehicleType',
      );

      debugPrint('📍 PlacesService.getDistanceAndFare - URL: $url');
      final response = await http.get(url, headers: headers);
      debugPrint(
        '📍 PlacesService.getDistanceAndFare - Response Status: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        debugPrint(
          '📍 PlacesService.getDistanceAndFare - Response Body: ${response.body}',
        );

        if (responseData['success'] == true) {
          // Backend returns data object with distance, duration, fare
          final data = responseData['data'] ?? responseData;

          debugPrint(
            '📍 PlacesService.getDistanceAndFare - Distance: ${data['distance_text']}',
          );
          debugPrint(
            '📍 PlacesService.getDistanceAndFare - Duration: ${data['duration_text']}',
          );
          debugPrint(
            '📍 PlacesService.getDistanceAndFare - Total Fare: £${data['total_fare']}',
          );

          return {
            'distance_meters': data['distance_meters'] ?? 0,
            'distance_text': data['distance_text'] ?? '',
            'duration_seconds': data['duration_seconds'] ?? 0,
            'duration_text': data['duration_text'] ?? '',
            'total_fare': (data['total_fare'] is int)
                ? (data['total_fare'] as int).toDouble()
                : (data['total_fare'] ?? 0.0),
            'currency': data['currency'] ?? 'GBP',
            'vehicle_type': vehicleType,
          };
        } else {
          debugPrint(
            '⚠️ PlacesService.getDistanceAndFare - API error: ${responseData['message']}',
          );
          debugPrint(
            '⚠️ PlacesService.getDistanceAndFare - Full response: ${response.body}',
          );
          return null;
        }
      } else {
        debugPrint(
          '❌ PlacesService.getDistanceAndFare - HTTP Error: ${response.statusCode}',
        );
        debugPrint(
          '❌ PlacesService.getDistanceAndFare - Response: ${response.body}',
        );
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ PlacesService.getDistanceAndFare - Exception: $e');
      debugPrint(
        '❌ PlacesService.getDistanceAndFare - Stack trace: $stackTrace',
      );
      return null;
    }
  }

  /// Legacy method for backwards compatibility
  /// @deprecated Use getDistanceAndFare instead for fare calculation
  Future<Map<String, dynamic>?> getDistanceMatrix(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) async {
    return getDistanceAndFare(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
      vehicleType: 'sedan',
    );
  }

  /// Decode polyline string into list of LatLng coordinates
  List<Map<String, double>> _decodePolyline(String encoded) {
    List<Map<String, double>> points = [];
    if (encoded.isEmpty) return points;

    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add({'lat': lat / 1E5, 'lng': lng / 1E5});
    }

    return points;
  }
}
