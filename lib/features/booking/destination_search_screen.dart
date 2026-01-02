import 'package:flutter/material.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import '../../core/theme.dart';
import '../../core/services/places_service.dart';
import '../../core/config/api_config.dart';
import '../../core/widgets/platform_map.dart';
import 'dart:async';
import '../../core/api_service.dart';
import 'widgets/vehicle_selection_widget.dart';
import 'package:latlong2/latlong.dart' as lat_lng;
import '../ride/ride_assigned_screen.dart';
import '../../core/services/location_service.dart';

class DestinationSearchScreen extends StatefulWidget {
  const DestinationSearchScreen({super.key});

  @override
  State<DestinationSearchScreen> createState() => _DestinationSearchScreenState();
}

class _DestinationSearchScreenState extends State<DestinationSearchScreen> {
  final TextEditingController _pickupController = TextEditingController(text: "Current Location");
  final TextEditingController _dropoffController = TextEditingController();
  final FocusNode _dropoffFocus = FocusNode();
  final PanelController _panelController = PanelController();
  
  final PlacesService _placesService = PlacesService();
  final LocationService _locationService = LocationService();
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = false;
  
  // Session token for Places API billing optimization
  String? _sessionToken;
  
  // Map State
  LatLng _center = const LatLng(51.5074, -0.1278); // Default London
  LatLng? _pickupLocation;
  String _pickupAddress = "Current Location";
  
  // Route Info
  String? _routeDistance;
  String? _routeDuration;
  
  // Search Focus
  bool _isPickupFocused = false;
  List<MapMarker> _markers = [];
  List<LatLng> _polylines = [];
  fmap.LatLngBounds? _mapBounds;
  bool _isRouteView = false;

  final List<Map<String, String>> _savedPlaces = [
    {'icon': '🏠', 'title': 'Home', 'subtitle': 'Add home', 'type': 'add'},
    {'icon': '💼', 'title': 'Work', 'subtitle': 'Add work', 'type': 'add'},
  ];
  
  final List<Map<String, String>> _recentPlaces = [
    {'icon': '✈️', 'name': 'Heathrow Terminal 5', 'address': 'Longford TW6, UK', 'distance': '15 mi', 'lat': '51.4700', 'lng': '-0.4543'},
    {'icon': '🏢', 'name': 'The Shard', 'address': 'London Bridge, SE1', 'distance': '2 mi', 'lat': '51.5045', 'lng': '-0.0865'},
    {'icon': '🚉', 'name': 'King\'s Cross Station', 'address': 'Kings Cross, N1', 'distance': '3 mi', 'lat': '51.5310', 'lng': '-0.1260'},
  ];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    
    // Auto-focus dropoff field if not in route view
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isRouteView) {
        _dropoffFocus.requestFocus();
      }
    });
    
    _dropoffController.addListener(() => _onSearchChanged(_dropoffController.text));
    _pickupController.addListener(() => _onSearchChanged(_pickupController.text));
  }

  Future<void> _getCurrentLocation() async {
    final position = await _locationService.getCurrentLocation();
    if (position != null) {
      setState(() {
        _center = LatLng(position.latitude, position.longitude);
        _pickupLocation = _center;
        
        // Update pickup marker if exists
        if (_markers.isNotEmpty && _markers[0].id == 'pickup') {
          _markers[0] = MapMarker(
            id: 'pickup',
            lat: _center.latitude,
            lng: _center.longitude,
            child: _markers[0].child,
            title: 'Pickup',
          );
        }
      });
      
      // Reverse geocode to get address
      try {
        final address = await _placesService.getAddressFromLatLng(position.latitude, position.longitude);
        if (address != null) {
           setState(() {
             _pickupAddress = address.split(',')[0];
             if (_pickupController.text == "Current Location") {
                _pickupController.text = _pickupAddress;
             }
           });
        }
      } catch (e) {
        debugPrint("Error reverse geocoding: $e");
      }
    }
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _dropoffFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _isLoading = false;
      });
      return;
    }

    // Generate session token when user starts typing (if not already set)
    if (_sessionToken == null) {
      _sessionToken = ApiConfig.generateSessionToken();
      debugPrint('🔍 DestinationSearchScreen._onSearchChanged - Generated new session token: $_sessionToken');
    }

    _debounce = Timer(const Duration(milliseconds: 800), () async {
      debugPrint('🔍 DestinationSearchScreen._onSearchChanged - Searching for: "$query"');
      setState(() => _isLoading = true);
      
      final results = await _placesService.searchPlaces(query, sessionToken: _sessionToken);
      
      debugPrint('🔍 DestinationSearchScreen._onSearchChanged - Found ${results.length} results');
      
      if (mounted) {
        setState(() {
          _suggestions = results;
          _isLoading = false;
        });
      }
    });
  }

  void _selectLocation(String placeId, String name, String description) async {
    debugPrint('📍 DestinationSearchScreen._selectLocation - Fetching details for: $name');
    debugPrint('📍 DestinationSearchScreen._selectLocation - Place ID: $placeId');
    debugPrint('📍 DestinationSearchScreen._selectLocation - Session Token: $_sessionToken');
    
    // Fetch place details to get coordinates (uses same session token to close billing cycle)
    final placeDetails = await _placesService.getPlaceDetails(placeId, sessionToken: _sessionToken);
    
    // Clear session token after place selection (closes billing cycle)
    debugPrint('📍 DestinationSearchScreen._selectLocation - Clearing session token after place selection');
    _sessionToken = null;
    
    if (placeDetails == null) {
      debugPrint('❌ DestinationSearchScreen._selectLocation - Failed to get place details for: $name');
      return;
    }
    
    final lat = placeDetails['lat'];
    final lng = placeDetails['lng'];
    final address = placeDetails['formatted_address'];
    debugPrint('📍 DestinationSearchScreen._selectLocation - Selected place: $name');
    debugPrint('📍 DestinationSearchScreen._selectLocation - Address: $address');
    debugPrint('📍 DestinationSearchScreen._selectLocation - Coordinates: ($lat, $lng)');
    
    setState(() {
      if (_isPickupFocused) {
        _pickupController.text = name;
        _pickupLocation = LatLng(lat, lng);
        _center = _pickupLocation!; // Center map on new pickup
        _isPickupFocused = false;
        _dropoffFocus.requestFocus(); // Move to dropoff
      } else {
        _dropoffController.text = name;
        _dropoffFocus.unfocus();
        _isRouteView = true;
      }
      
      _suggestions = [];
      
      // If both selected, show route
      if (_pickupLocation != null && _dropoffController.text.isNotEmpty) {
         _updateRouteView(lat, lng);
      }
    });
  }

  void _updateRouteView(double dropLat, double dropLng) async {
      if (_pickupLocation == null) return;
      
      setState(() {
        // Update Markers
        _markers = [
          MapMarker(
            id: 'pickup',
            lat: _pickupLocation!.latitude,
            lng: _pickupLocation!.longitude,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.my_location, color: Colors.white, size: 16),
            ),
            title: 'Pickup',
          ),
          MapMarker(
            id: 'dropoff',
            lat: dropLat,
            lng: dropLng,
            child: const Icon(Icons.location_on, color: Colors.black, size: 40),
            title: _dropoffController.text,
          ),
        ];
      });
      
      // Fetch real route from Directions API
      debugPrint('🗺️ Fetching route from Directions API...');
      final directions = await _placesService.getDirections(
        _pickupLocation!.latitude,
        _pickupLocation!.longitude,
        dropLat,
        dropLng,
      );
      
      if (directions != null && mounted) {
        final polylinePoints = directions['polyline'] as List<Map<String, double>>;
        
        setState(() {
          // Convert polyline points to LatLng
          _polylines = polylinePoints.map((point) {
            return LatLng(point['lat']!, point['lng']!);
          }).toList();
          
          // Calculate Bounds
          if (_polylines.isNotEmpty) {
            _mapBounds = fmap.LatLngBounds.fromPoints(_polylines);
          }
          
          // Store route info for display
          _routeDistance = directions['distance_text'];
          _routeDuration = directions['duration_text'];
          debugPrint('✅ Route loaded: $_routeDistance, ETA: $_routeDuration');
        });
      } else if (mounted) {
        // Fallback to straight line if API fails
        setState(() {
          _polylines = [
            _pickupLocation!,
            LatLng(dropLat, dropLng),
          ];
          _mapBounds = fmap.LatLngBounds.fromPoints(_polylines);
        });
      }

      // Minimize panel to show map
      _panelController.animatePanelToPosition(0.15); // Show bottom summary
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background Map
          PlatformMap(
            initialLat: _center.latitude,
            initialLng: _center.longitude,
            markers: _markers,
            polylines: _polylines.isNotEmpty ? [
              MapPolyline(
                id: 'route',
                points: _polylines,
                color: AppTheme.primaryColor, // Coral/Orange theme color
                width: 4.0,
              ),
            ] : [],
            bounds: _mapBounds,
            onTap: (lat, lng) {},
          ),
          
          // Route Info Card (shown when route is displayed)
          if (_isRouteView && _routeDistance != null && _routeDuration != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.route,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _routeDistance!,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          Text(
                            'Estimated time: $_routeDuration',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.verified,
                      color: AppTheme.successColor,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          
          // Back Button (Always visible)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // Sliding Panel
          SlidingUpPanel(
            controller: _panelController,
            minHeight: MediaQuery.of(context).size.height * 0.25,
            maxHeight: MediaQuery.of(context).size.height * 0.9,
            defaultPanelState: PanelState.OPEN,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            panel: _buildPanelContent(),
            body: null, // Map is behind
          ),
        ],
      ),
    );
  }

  String _selectedVehicle = 'sedan';
  final ApiService _apiService = ApiService();

  // ... existing methods

  void _handleBookRide() async {
    setState(() => _isLoading = true);

    try {
      // Calculate distance
      final distance = const lat_lng.Distance().as(
        lat_lng.LengthUnit.Kilometer,
        lat_lng.LatLng(_center.latitude, _center.longitude),
        lat_lng.LatLng(_markers[1].lat, _markers[1].lng),
      );

      final pickupLocation = {
        'coordinates': [_pickupLocation?.longitude ?? _center.longitude, _pickupLocation?.latitude ?? _center.latitude],
        'address': _pickupController.text,
      };

      final dropoffLocation = {
        'coordinates': [_markers[1].lng, _markers[1].lat],
        'address': _dropoffController.text,
      };

      final rideData = {
        'pickupLocation': pickupLocation,
        'dropoffLocation': dropoffLocation,
        'vehicleType': _selectedVehicle,
        'distance': distance,
      };

      debugPrint('🚀 Booking Ride with Data: $rideData');

      final response = await _apiService.createRide(rideData);

      if (mounted) {
        setState(() => _isLoading = false);
        // Navigate to Ride Detail Screen
        // Navigate to Ride Assigned Screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => RideAssignedScreen(
              rideId: response['data']['_id'],
              pickup: pickupLocation,
              dropoff: dropoffLocation,
              fare: (response['data']['fare'] ?? 15.50).toDouble(),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to book ride: $e')),
        );
      }
    }
  }

  Widget _buildPanelContent() {
    if (_isRouteView) {
      return VehicleSelectionWidget(
        onVehicleSelected: (vehicle) {
          setState(() => _selectedVehicle = vehicle);
        },
        onBookRide: _handleBookRide,
        isLoading: _isLoading,
        pickupLat: _pickupLocation?.latitude ?? _center.latitude,
        pickupLng: _pickupLocation?.longitude ?? _center.longitude,
        dropoffLat: _markers.length > 1 ? _markers[1].lat : null,
        dropoffLng: _markers.length > 1 ? _markers[1].lng : null,
      );
    }

    return Column(
      children: [
        // ... existing search content

        // Drag Handle
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header (Plan your ride)
        if (!_isRouteView)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Plan your ride',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),

        // Input Section
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            children: [
              Column(
                children: [
                  const Icon(Icons.circle, size: 12, color: Colors.black),
                  Container(
                    width: 2,
                    height: 40,
                    color: Colors.grey[300],
                  ),
                  const Icon(Icons.square, size: 12, color: Colors.black),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _buildTextField(_pickupController, 'Pickup location', false, onTap: () {
                      setState(() => _isPickupFocused = true);
                    }),
                    const Divider(height: 1),
                    _buildTextField(_dropoffController, 'Where to?', true, onTap: () {
                       setState(() => _isPickupFocused = false);
                    }),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.add, color: Colors.black),
                  onPressed: () {},
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Suggestions List
        Expanded(
          child: _suggestions.isNotEmpty
              ? _buildSearchResults()
              : _buildDefaultContent(),
        ),
      ],
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, bool autoFocus, {VoidCallback? onTap}) {
    return TextField(
      controller: controller,
      focusNode: autoFocus ? _dropoffFocus : null,
      onTap: onTap,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w500),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
  }

  Widget _buildSearchResults() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _suggestions.length,
      separatorBuilder: (context, index) => Divider(
        color: AppTheme.borderColor,
        height: 1,
      ),
      itemBuilder: (context, index) {
        final place = _suggestions[index];
        final placeId = place['place_id'];
        final name = place['main_text'];
        final secondaryText = place['secondary_text'];
        
        return _buildDestinationRow(
          icon: Icons.location_on,
          name: name,
          address: secondaryText,
          distance: '', 
          onTap: () => _selectLocation(placeId, name, place['description']),
        );
      },
    );
  }
  
  Widget _buildDefaultContent() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Saved Places
        ..._savedPlaces.map((place) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildSavedPlaceRow(
            icon: place['icon'] == '🏠' ? Icons.home : Icons.work,
            title: place['title']!,
            subtitle: place['subtitle']!,
            onTap: () {},
          ),
        )),
        
        const SizedBox(height: 8),
        
        // Recent Places
        const Text(
          'Recent',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        
        const SizedBox(height: 16),
        
        ..._recentPlaces.map((place) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildDestinationRow(
            icon: Icons.history,
            name: place['name']!,
            address: place['address']!,
            distance: place['distance']!,
            onTap: () {
               final lat = double.tryParse(place['lat'] ?? '51.5074') ?? 51.5074;
               final lng = double.tryParse(place['lng'] ?? '-0.1278') ?? -0.1278;
               
               // Directly set location for recent places (no API lookup needed)
               setState(() {
                 if (_isPickupFocused) {
                   _pickupController.text = place['name']!;
                   _pickupLocation = LatLng(lat, lng);
                   _center = _pickupLocation!;
                   _isPickupFocused = false;
                   _dropoffFocus.requestFocus();
                 } else {
                   _dropoffController.text = place['name']!;
                   _dropoffFocus.unfocus();
                   _isRouteView = true;
                 }
                 
                 _suggestions = [];
                 
                 // If both selected, show route
                 if (_pickupLocation != null && _dropoffController.text.isNotEmpty) {
                    _updateRouteView(lat, lng);
                 }
               });
            },
          ),
        )),
      ],
    );
  }
  
  Widget _buildSavedPlaceRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.black, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDestinationRow({
    required IconData icon,
    required String name,
    required String address,
    required String distance,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.black, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    address,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (distance.isNotEmpty)
              Text(
                distance,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
      ),
    );
  }
}


