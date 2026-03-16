import 'package:flutter/material.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:geolocator/geolocator.dart';
import '../../core/theme.dart';
import '../../core/services/places_service.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/config/api_config.dart';
import '../../core/widgets/platform_map.dart';
import '../../core/services/location_cache_service.dart';
import 'dart:async';
import 'widgets/vehicle_selection_widget.dart';
import 'widgets/schedule_ride_sheet.dart';
import 'ride_confirmation_screen.dart';

class DestinationSearchScreen extends StatefulWidget {
  const DestinationSearchScreen({super.key});

  @override
  State<DestinationSearchScreen> createState() =>
      _DestinationSearchScreenState();
}

class _DestinationSearchScreenState extends State<DestinationSearchScreen> {
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropoffController = TextEditingController();
  final FocusNode _pickupFocus = FocusNode();
  final FocusNode _dropoffFocus = FocusNode();
  final PanelController _panelController = PanelController();

  final PlacesService _placesService = PlacesService();
  final GeocodingService _geocodingService = GeocodingService();
  final LocationCacheService _locationCache = LocationCacheService();
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = false;

  // Session token for Places API billing optimization
  String? _sessionToken;

  // Map State
  LatLng _center = const LatLng(51.5074, -0.1278); // Default London
  LatLng? _pickupLocation;
  String _pickupAddress = "";
  String? _pickupPlaceId; // Store Google Places ID for airport detection
  bool _isPickupLocationReady = false; // Track if pickup location is ready

  // Route Info
  String? _routeDistance;
  double? _routeDistanceValue;
  String? _routeDuration;

  // Search Focus
  bool _isPickupFocused = false;
  List<MapMarker> _markers = [];
  LatLng? _dropoffLocation;
  String _dropoffAddress = ""; // Store full dropoff address for API
  String? _dropoffPlaceId; // Store Google Places ID for airport detection
  List<LatLng> _polylines = [];
  fmap.LatLngBounds? _mapBounds;
  bool _isRouteView = false;

  final List<Map<String, String>> _savedPlaces = [
    // {'icon': '🏠', 'title': 'Home', 'subtitle': 'Add home', 'type': 'add'},
    // {'icon': '💼', 'title': 'Work', 'subtitle': 'Add work', 'type': 'add'},
  ];

  final List<Map<String, String>> _recentPlaces = [
    {
      'icon': '✈️',
      'name': 'Heathrow Terminal 5',
      'address': 'Longford TW6, UK',
      'distance': '15 mi',
      'lat': '51.4700',
      'lng': '-0.4543',
    },
    {
      'icon': '🏢',
      'name': 'The Shard',
      'address': 'London Bridge, SE1',
      'distance': '2 mi',
      'lat': '51.5045',
      'lng': '-0.0865',
    },
    {
      'icon': '🚉',
      'name': 'King\'s Cross Station',
      'address': 'Kings Cross, N1',
      'distance': '3 mi',
      'lat': '51.5310',
      'lng': '-0.1260',
    },
  ];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();

    // Auto-focus dropoff field if not in route view and pickup is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isRouteView && _isPickupLocationReady) {
        _dropoffFocus.requestFocus();
      }
    });

    _dropoffController.addListener(() {
      if (_dropoffFocus.hasFocus) {
        _onSearchChanged(_dropoffController.text);
      }
    });
    _pickupController.addListener(() {
      if (_pickupFocus.hasFocus) {
        _onSearchChanged(_pickupController.text);
      }
    });
  }

  Future<void> _getCurrentLocation() async {
    // Try to get cached location first (instant)
    final cachedPosition = _locationCache.cachedPosition;
    if (cachedPosition != null) {
      debugPrint('📍 DestinationSearchScreen: Using cached location');
      await _processLocation(cachedPosition);
      return;
    }

    // Fetch fresh location
    debugPrint('📍 DestinationSearchScreen: Fetching fresh location');
    final position = await _locationCache.getLocation();

    if (position != null) {
      await _processLocation(position);
    } else {
      // Failed to get location
      if (mounted) {
        setState(() {
          _pickupController.text = "Unable to get location";
          _isPickupLocationReady = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Unable to get your location. Please check permissions and try again.',
            ),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _getCurrentLocation,
            ),
          ),
        );
      }
    }
  }

  Future<void> _processLocation(Position position) async {
    if (!mounted) return;

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

    // Reverse geocode to get address - this is critical for proper address display
    try {
      // Try backend API first
      String? address = await _placesService.getAddressFromLatLng(
        position.latitude,
        position.longitude,
      );

      // If backend fails, try Nominatim (OpenStreetMap) as fallback
      if (address == null || address.isEmpty) {
        debugPrint(
          '📍 DestinationSearchScreen: Backend geocoding failed, trying Nominatim...',
        );
        address = await _geocodingService.getAddressFromLatLng(
          position.latitude,
          position.longitude,
        );
      }

      if (address != null && address.isNotEmpty && mounted) {
        setState(() {
          // Store the full address for the API
          _pickupAddress = address!;

          // Show a shorter version in the text field (first part before comma)
          final shortAddress = address.split(',')[0];
          _pickupController.text = shortAddress;
          _isPickupLocationReady = true; // Mark as ready
        });
        debugPrint(
          '📍 DestinationSearchScreen: Geocoded current location to: $address',
        );
      } else if (mounted) {
        debugPrint('⚠️ DestinationSearchScreen: All geocoding methods failed');
        // Use coordinates as fallback but mark as ready
        setState(() {
          _pickupAddress =
              "Lat: ${position.latitude.toStringAsFixed(4)}, Lng: ${position.longitude.toStringAsFixed(4)}";
          _pickupController.text = "Current location";
          _isPickupLocationReady = true;
        });
      }
    } catch (e) {
      debugPrint("❌ DestinationSearchScreen: Error reverse geocoding: $e");
      if (mounted) {
        setState(() {
          _pickupAddress =
              "Lat: ${position.latitude.toStringAsFixed(4)}, Lng: ${position.longitude.toStringAsFixed(4)}";
          _pickupController.text = "Current location";
          _isPickupLocationReady = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _pickupFocus.dispose();
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
      debugPrint(
        '🔍 DestinationSearchScreen._onSearchChanged - Generated new session token: $_sessionToken',
      );
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      debugPrint(
        '🔍 DestinationSearchScreen._onSearchChanged - Searching for: "$query"',
      );
      setState(() => _isLoading = true);

      final results = await _placesService.searchPlaces(
        query,
        sessionToken: _sessionToken,
        lat: _center.latitude,
        lng: _center.longitude,
      );

      debugPrint(
        '🔍 DestinationSearchScreen._onSearchChanged - Found ${results.length} results',
      );
      debugPrint(
        '🔍 DestinationSearchScreen._onSearchChanged - Results: $results',
      );

      if (mounted) {
        setState(() {
          _suggestions = results;
          _isLoading = false;
        });
      }
    });
  }

  void _selectLocation(String placeId, String name, String description) async {
    debugPrint(
      '📍 DestinationSearchScreen._selectLocation - Fetching details for: $name',
    );
    debugPrint(
      '📍 DestinationSearchScreen._selectLocation - Place ID: $placeId',
    );
    debugPrint(
      '📍 DestinationSearchScreen._selectLocation - Session Token: $_sessionToken',
    );

    // Fetch place details to get coordinates (uses same session token to close billing cycle)
    final placeDetails = await _placesService.getPlaceDetails(
      placeId,
      sessionToken: _sessionToken,
    );

    // Clear session token after place selection (closes billing cycle)
    debugPrint(
      '📍 DestinationSearchScreen._selectLocation - Clearing session token after place selection',
    );
    _sessionToken = null;

    if (placeDetails == null) {
      debugPrint(
        '❌ DestinationSearchScreen._selectLocation - Failed to get place details for: $name',
      );
      return;
    }

    final lat = placeDetails['lat'];
    final lng = placeDetails['lng'];
    final address = placeDetails['formatted_address'];
    final placeIdFromDetails =
        placeDetails['place_id']; // Get placeId from response
    debugPrint('📍 Selected place: $name');
    debugPrint('📍 Address: $address');
    debugPrint('📍 Coordinates: ($lat, $lng)');
    debugPrint('📍 Place ID: $placeIdFromDetails');

    setState(() {
      if (_isPickupFocused) {
        _pickupController.text = name;
        _pickupLocation = LatLng(lat, lng);
        // Store the full formatted address for the API
        _pickupAddress = address ?? name;
        _pickupPlaceId =
            placeIdFromDetails ??
            placeId; // Store placeId for airport detection
        _center = _pickupLocation!; // Center map on new pickup
        _isPickupFocused = false;
        _dropoffFocus.requestFocus(); // Move to dropoff
      } else {
        _dropoffController.text = name;
        _dropoffLocation = LatLng(lat, lng);
        // Store the full formatted address for the API
        _dropoffAddress = address ?? name;
        _dropoffPlaceId =
            placeIdFromDetails ??
            placeId; // Store placeId for airport detection
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
    debugPrint('🗺️ ─────────────────────────────────────────────');
    debugPrint('🗺️ DestinationSearchScreen._updateRouteView()');
    debugPrint('🗺️ Fetching route from Directions API...');
    final directions = await _placesService.getDirections(
      _pickupLocation!.latitude,
      _pickupLocation!.longitude,
      dropLat,
      dropLng,
    );

    if (directions != null &&
        directions['polyline'] != null &&
        (directions['polyline'] as List).isNotEmpty &&
        mounted) {
      final polylinePoints =
          directions['polyline'] as List<Map<String, double>>;

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
        _routeDistanceValue = directions['distance_miles'] is num
            ? (directions['distance_miles'] as num).toDouble()
            : 0.0;
        _routeDuration = directions['duration_text'];
        debugPrint('✅ Route loaded: $_routeDistance, ETA: $_routeDuration');
      });
    } else if (mounted) {
      debugPrint(
        '⚠️ DestinationSearchScreen: Directions API failed or returned empty polyline, using straight-line fallback',
      );
      // Fallback to straight line if API fails
      setState(() {
        final dropLocation = LatLng(dropLat, dropLng);
        _polylines = [_pickupLocation!, dropLocation];
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
            polylines: _polylines.isNotEmpty
                ? [
                    MapPolyline(
                      id: 'route',
                      points: _polylines,
                      color: Colors.blue.withOpacity(
                        0.8,
                      ), // Using a high-contrast blue
                      width: 6.0,
                    ),
                  ]
                : [],
            bounds: _mapBounds,
            onTap: (lat, lng) {},
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

  // ... existing methods

  /// Navigate to confirmation screen with selected vehicle and fare data
  Future<void> _handleSelectVehicle(
    String categorySlug,
    String categoryName,
    Map<String, dynamic> fareData,
  ) async {
    // Don't proceed if pickup location is not ready
    if (!_isPickupLocationReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait while we fetch your location'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    debugPrint('🚗 DestinationSearchScreen: Vehicle selected');
    debugPrint('   → Category: $categorySlug');
    debugPrint('   → Name: $categoryName');
    debugPrint('   → Fare: £${fareData['total_fare']}');

    // Get the actual pickup coordinates
    final pickupLat = _pickupLocation?.latitude ?? _center.latitude;
    final pickupLng = _pickupLocation?.longitude ?? _center.longitude;

    // Determine the actual pickup address - prefer the geocoded address
    String actualPickupAddress = _pickupAddress;

    // If pickup address is empty or starts with "Lat:",
    // try to fetch the actual address from coordinates
    if (_pickupAddress.isEmpty || _pickupAddress.startsWith("Lat:")) {
      debugPrint(
        '📍 DestinationSearchScreen: Fetching actual pickup address...',
      );

      // Try backend API first
      String? fetchedAddress = await _placesService.getAddressFromLatLng(
        pickupLat,
        pickupLng,
      );

      // If backend fails, try Nominatim (OpenStreetMap) as fallback
      if (fetchedAddress == null || fetchedAddress.isEmpty) {
        debugPrint(
          '📍 DestinationSearchScreen: Backend geocoding failed, trying Nominatim...',
        );
        fetchedAddress = await _geocodingService.getAddressFromLatLng(
          pickupLat,
          pickupLng,
        );
      }

      if (fetchedAddress != null && fetchedAddress.isNotEmpty) {
        actualPickupAddress = fetchedAddress;
        // Also update the stored address for future use
        _pickupAddress = fetchedAddress;
        debugPrint(
          '📍 DestinationSearchScreen: Fetched address: $actualPickupAddress',
        );
      } else {
        // If all geocoding fails, use the text from the controller if it's a real address
        if (_pickupController.text.isNotEmpty &&
            !_pickupController.text.startsWith("Lat:")) {
          actualPickupAddress = _pickupController.text;
        } else {
          // Last resort - just use "Pickup Location" as a generic label
          // The coordinates are still stored separately
          actualPickupAddress = "Pickup Location";
          debugPrint(
            '⚠️ DestinationSearchScreen: All geocoding failed, using generic label',
          );
        }
      }
    } else if (_pickupController.text.isNotEmpty &&
        !_pickupController.text.startsWith("Lat:")) {
      // User manually entered/selected a pickup address - use the full stored address
      // but prefer _pickupAddress if it has the full formatted address
      if (_pickupAddress.length > _pickupController.text.length) {
        actualPickupAddress = _pickupAddress;
      } else {
        actualPickupAddress = _pickupController.text;
      }
    }

    debugPrint(
      '📍 DestinationSearchScreen: Final pickup address: $actualPickupAddress',
    );

    final pickupLocation = {
      'coordinates': [pickupLng, pickupLat],
      'address': actualPickupAddress,
      if (_pickupPlaceId != null)
        'placeId': _pickupPlaceId, // Include placeId for airport detection
    };

    // Get the actual dropoff coordinates and address
    final dropoffLat = _dropoffLocation?.latitude ?? _center.latitude;
    final dropoffLng = _dropoffLocation?.longitude ?? _center.longitude;

    // Use the stored dropoff address (from place selection), fallback to controller text
    String actualDropoffAddress = _dropoffAddress.isNotEmpty
        ? _dropoffAddress
        : _dropoffController.text;

    // If dropoff address is still empty, try to get it from coordinates
    if (actualDropoffAddress.isEmpty && _dropoffLocation != null) {
      final fetchedAddress = await _placesService.getAddressFromLatLng(
        dropoffLat,
        dropoffLng,
      );
      if (fetchedAddress != null && fetchedAddress.isNotEmpty) {
        actualDropoffAddress = fetchedAddress;
      }
    }

    final dropoffLocation = {
      'coordinates': [dropoffLng, dropoffLat],
      'address': actualDropoffAddress,
      if (_dropoffPlaceId != null)
        'placeId': _dropoffPlaceId, // Include placeId for airport detection
    };

    debugPrint('📍 DestinationSearchScreen: Pickup: $actualPickupAddress');
    debugPrint('📍 DestinationSearchScreen: Dropoff: $actualDropoffAddress');

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RideConfirmationScreen(
          pickupLocation: pickupLocation,
          dropoffLocation: dropoffLocation,
          categorySlug: categorySlug,
          categoryName: categoryName,
          fareData: fareData,
          polyline: _polylines, // Pass the drawn polyline
        ),
      ),
    );

    if (result != null && result is Map && result['status'] == 'searching') {
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    }
  }

  Future<void> _handlePrebookVehicle(
    String categorySlug,
    String categoryName,
    Map<String, dynamic> fareData,
  ) async {
    // Don't proceed if pickup location is not ready
    if (!_isPickupLocationReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait while we fetch your location'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    debugPrint('🚗 DestinationScreens: Prebook vehicle selected');
    debugPrint('   → Category: $categorySlug');
    debugPrint('   → Name: $categoryName');
    debugPrint('   → Fare: £${fareData['total_fare']}');

    // Get the actual pickup coordinates
    final pickupLat = _pickupLocation?.latitude ?? _center.latitude;
    final pickupLng = _pickupLocation?.longitude ?? _center.longitude;

    // Determine the actual pickup address - prefer the geocoded address
    String actualPickupAddress = _pickupAddress;

    // If pickup address is empty or starts with "Lat:",
    // try to fetch the actual address from coordinates
    if (_pickupAddress.isEmpty || _pickupAddress.startsWith("Lat:")) {
      debugPrint(
        '📍 DestinationSearchScreen: Fetching actual pickup address...',
      );

      // Try backend API first
      String? fetchedAddress = await _placesService.getAddressFromLatLng(
        pickupLat,
        pickupLng,
      );

      // If backend fails, try Nominatim (OpenStreetMap) as fallback
      if (fetchedAddress == null || fetchedAddress.isEmpty) {
        debugPrint(
          '📍 DestinationSearchScreen: Backend geocoding failed, trying Nominatim...',
        );
        fetchedAddress = await _geocodingService.getAddressFromLatLng(
          pickupLat,
          pickupLng,
        );
      }

      if (fetchedAddress != null && fetchedAddress.isNotEmpty) {
        actualPickupAddress = fetchedAddress;
        // Also update the stored address for future use
        _pickupAddress = fetchedAddress;
        debugPrint(
          '📍 DestinationSearchScreen: Fetched address: $actualPickupAddress',
        );
      } else {
        // If all geocoding fails, use the text from the controller if it's a real address
        if (_pickupController.text.isNotEmpty &&
            !_pickupController.text.startsWith("Lat:")) {
          actualPickupAddress = _pickupController.text;
        } else {
          // Last resort - just use "Pickup Location" as a generic label
          // The coordinates are still stored separately
          actualPickupAddress = "Pickup Location";
          debugPrint(
            '⚠️ DestinationSearchScreen: All geocoding failed, using generic label',
          );
        }
      }
    } else if (_pickupController.text.isNotEmpty &&
        !_pickupController.text.startsWith("Lat:")) {
      // User manually entered/selected a pickup address - use the full stored address
      // but prefer _pickupAddress if it has the full formatted address
      if (_pickupAddress.length > _pickupController.text.length) {
        actualPickupAddress = _pickupAddress;
      } else {
        actualPickupAddress = _pickupController.text;
      }
    }

    debugPrint(
      '📍 DestinationSearchScreen: Final pickup address: $actualPickupAddress',
    );

    final pickupLocation = {
      'coordinates': [pickupLng, pickupLat],
      'address': actualPickupAddress,
      if (_pickupPlaceId != null)
        'placeId': _pickupPlaceId, // Include placeId for airport detection
    };

    // Get the actual dropoff coordinates and address
    final dropoffLat = _dropoffLocation?.latitude ?? _center.latitude;
    final dropoffLng = _dropoffLocation?.longitude ?? _center.longitude;

    // Use the stored dropoff address (from place selection), fallback to controller text
    String actualDropoffAddress = _dropoffAddress.isNotEmpty
        ? _dropoffAddress
        : _dropoffController.text;

    // If dropoff address is still empty, try to get it from coordinates
    if (actualDropoffAddress.isEmpty && _dropoffLocation != null) {
      final fetchedAddress = await _placesService.getAddressFromLatLng(
        dropoffLat,
        dropoffLng,
      );
      if (fetchedAddress != null && fetchedAddress.isNotEmpty) {
        actualDropoffAddress = fetchedAddress;
      }
    }

    final dropoffLocation = {
      'coordinates': [dropoffLng, dropoffLat],
      'address': actualDropoffAddress,
      if (_dropoffPlaceId != null)
        'placeId': _dropoffPlaceId, // Include placeId for airport detection
    };

    debugPrint('📍 DestinationSearchScreen: Pickup: $actualPickupAddress');
    debugPrint('📍 DestinationSearchScreen: Dropoff: $actualDropoffAddress');

    // Show the schedule sheet FIRST (before navigating to RideConfirmationScreen)
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ScheduleRideSheet(
        initialDateTime: DateTime.now().add(const Duration(minutes: 30)),
        onSchedule: (selectedDateTime, notes) async {
          // User selected a time, now navigate to RideConfirmationScreen with the scheduled time
          if (!mounted) return;

          debugPrint(
            '📅 DestinationSearchScreen: Prebook scheduled for: $selectedDateTime',
          );

          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RideConfirmationScreen(
                pickupLocation: pickupLocation,
                dropoffLocation: dropoffLocation,
                categorySlug: categorySlug,
                categoryName: categoryName,
                fareData: fareData,
                polyline: _polylines, // Pass the drawn polyline
                isScheduled: true, // Mark as scheduled
                scheduledDateTime: selectedDateTime, // Pass the selected time
              ),
            ),
          );

          if (result != null && result is Map && result['status'] == 'searching') {
            if (mounted) {
              Navigator.of(context).pop(result);
            }
          }
        },
      ),
    );
  }

  Widget _buildPanelContent() {
    if (_isRouteView) {
      return VehicleSelectionWidget(
        onVehicleSelected: (vehicle) {
          debugPrint('🚗 DestinationSearchScreen: Vehicle tapped: $vehicle');
        },
        onSelectVehicle: _handleSelectVehicle,
        onPrebookVehicle: _handlePrebookVehicle,
        isLoading: _isLoading,
        pickupLat: _pickupLocation?.latitude ?? _center.latitude,
        pickupLng: _pickupLocation?.longitude ?? _center.longitude,
        dropoffLat: _markers.length > 1 ? _markers[1].lat : null,
        dropoffLng: _markers.length > 1 ? _markers[1].lng : null,
        distance: _routeDistanceValue,
        durationText: _routeDuration,
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
                  Container(width: 2, height: 40, color: Colors.grey[300]),
                  const Icon(Icons.square, size: 12, color: Colors.black),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _buildTextField(
                      _pickupController,
                      'Pickup location',
                      false,
                      onTap: () {
                        setState(() => _isPickupFocused = true);
                      },
                    ),
                    const Divider(height: 1),
                    _buildTextField(
                      _dropoffController,
                      'Where to?',
                      true,
                      onTap: () {
                        setState(() => _isPickupFocused = false);
                      },
                    ),
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

  Widget _buildTextField(
    TextEditingController controller,
    String hint,
    bool isDropoff, {
    VoidCallback? onTap,
  }) {
    // Show loading indicator for pickup if not ready and not dropoff
    final showLoading =
        !isDropoff && !_isPickupLocationReady && controller.text.isEmpty;

    return TextField(
      controller: controller,
      focusNode: isDropoff ? _dropoffFocus : _pickupFocus,
      enabled: isDropoff
          ? _isPickupLocationReady
          : true, // Disable dropoff until pickup is ready
      onTap: onTap,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.grey[500],
          fontWeight: FontWeight.w500,
        ),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        prefixIcon: showLoading
            ? const Padding(
                padding: EdgeInsets.all(12.0),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
  }

  Widget _buildSearchResults() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _suggestions.length,
      separatorBuilder: (context, index) =>
          Divider(color: AppTheme.borderColor, height: 1),
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
        ..._savedPlaces.map(
          (place) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildSavedPlaceRow(
              icon: place['icon'] == '🏠' ? Icons.home : Icons.work,
              title: place['title']!,
              subtitle: place['subtitle']!,
              onTap: () {},
            ),
          ),
        ),
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
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (distance.isNotEmpty)
              Text(
                distance,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
          ],
        ),
      ),
    );
  }
}
