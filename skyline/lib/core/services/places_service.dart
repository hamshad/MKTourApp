import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';

/// Google Places API Service for geocoding and place search
class PlacesService {
  static final String _apiKey = ApiConfig.placesApiKey;
  static const String _placesBaseUrl = 'https://maps.googleapis.com/maps/api/place';
  static const String _geocodingBaseUrl = 'https://maps.googleapis.com/maps/api/geocode';

  /// Search for places using autocomplete
  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    if (query.isEmpty) return [];

    try {
      final url = Uri.parse(
        '$_placesBaseUrl/autocomplete/json?input=${Uri.encodeComponent(query)}&key=$_apiKey',
      );

      debugPrint('📍 PlacesService: Searching for "$query"');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK') {
          final List<dynamic> predictions = data['predictions'] ?? [];
          debugPrint('📍 PlacesService: Found ${predictions.length} results');
          
          return predictions.map((prediction) => {
            'place_id': prediction['place_id'],
            'description': prediction['description'],
            'main_text': prediction['structured_formatting']['main_text'],
            'secondary_text': prediction['structured_formatting']['secondary_text'] ?? '',
          }).toList();
        } else {
          debugPrint('⚠️ PlacesService: API returned status: ${data['status']}');
          if (data['error_message'] != null) {
            debugPrint('⚠️ Error Message: ${data['error_message']}');
          }
          return [];
        }
      } else {
        debugPrint('❌ PlacesService: Failed to search places. Status: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('❌ PlacesService: Error searching places: $e');
      return [];
    }
  }

  /// Get place details including coordinates from place ID
  Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    try {
      final url = Uri.parse(
        '$_placesBaseUrl/details/json?place_id=$placeId&fields=geometry,formatted_address,name&key=$_apiKey',
      );

      debugPrint('📍 PlacesService: Fetching details for place ID: $placeId');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK') {
          final result = data['result'];
          final location = result['geometry']['location'];
          
          debugPrint('📍 PlacesService: Found location: ${location['lat']}, ${location['lng']}');
          
          return {
            'name': result['name'],
            'formatted_address': result['formatted_address'],
            'lat': location['lat'],
            'lng': location['lng'],
          };
        } else {
          debugPrint('⚠️ PlacesService: API returned status: ${data['status']}');
          return null;
        }
      } else {
        debugPrint('❌ PlacesService: Failed to fetch place details. Status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ PlacesService: Error fetching place details: $e');
      return null;
    }
  }

  /// Get address from latitude and longitude (Reverse Geocoding)
  Future<String?> getAddressFromLatLng(double lat, double lng) async {
    try {
      final url = Uri.parse(
        '$_geocodingBaseUrl/json?latlng=$lat,$lng&key=$_apiKey',
      );

      debugPrint('📍 PlacesService: Reverse geocoding for $lat, $lng');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final address = data['results'][0]['formatted_address'] as String;
          debugPrint('📍 PlacesService: Found address: $address');
          return address;
        } else {
          debugPrint('⚠️ PlacesService: API returned status: ${data['status']}');
          return null;
        }
      } else {
        debugPrint('❌ PlacesService: Failed to reverse geocode. Status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ PlacesService: Error reverse geocoding: $e');
      return null;
    }
  }

  /// Get route directions from origin to destination
  /// ⚠️ PRODUCTION WARNING: This should be called from backend in production
  /// For demo purposes only - move to backend before launch
  Future<Map<String, dynamic>?> getDirections(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?origin=$originLat,$originLng&destination=$destLat,$destLng&key=$_apiKey',
      );

      debugPrint('📍 PlacesService: Getting directions from ($originLat, $originLng) to ($destLat, $destLng)');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final leg = route['legs'][0];
          
          // Decode polyline points for drawing route on map
          final polylinePoints = _decodePolyline(route['overview_polyline']['points']);
          
          debugPrint('📍 PlacesService: Route found - ${leg['distance']['text']}, ${leg['duration']['text']}');
          
          return {
            'polyline': polylinePoints,
            'distance_meters': leg['distance']['value'],
            'distance_text': leg['distance']['text'],
            'duration_seconds': leg['duration']['value'],
            'duration_text': leg['duration']['text'],
            'start_address': leg['start_address'],
            'end_address': leg['end_address'],
          };
        } else {
          debugPrint('⚠️ PlacesService: Directions API returned status: ${data['status']}');
          return null;
        }
      } else {
        debugPrint('❌ PlacesService: Failed to get directions. Status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ PlacesService: Error getting directions: $e');
      return null;
    }
  }

  /// Get distance and duration using Distance Matrix API
  /// ⚠️ PRODUCTION WARNING: This MUST be called from backend in production
  /// NEVER calculate pricing on client side - security risk!
  /// For demo purposes only - move to backend before launch
  Future<Map<String, dynamic>?> getDistanceMatrix(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/distancematrix/json?origins=$originLat,$originLng&destinations=$destLat,$destLng&key=$_apiKey',
      );

      debugPrint('📍 PlacesService: Getting distance matrix');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['rows'].isNotEmpty) {
          final element = data['rows'][0]['elements'][0];
          
          if (element['status'] == 'OK') {
            debugPrint('📍 PlacesService: Distance Matrix - ${element['distance']['text']}, ${element['duration']['text']}');
            
            return {
              'distance_meters': element['distance']['value'],
              'distance_text': element['distance']['text'],
              'duration_seconds': element['duration']['value'],
              'duration_text': element['duration']['text'],
            };
          }
        }
        
        debugPrint('⚠️ PlacesService: Distance Matrix API returned status: ${data['status']}');
        return null;
      } else {
        debugPrint('❌ PlacesService: Failed to get distance matrix. Status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ PlacesService: Error getting distance matrix: $e');
      return null;
    }
  }

  /// Decode polyline string into list of LatLng coordinates
  List<Map<String, double>> _decodePolyline(String encoded) {
    List<Map<String, double>> points = [];
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

      points.add({
        'lat': lat / 1E5,
        'lng': lng / 1E5,
      });
    }

    return points;
  }
}
