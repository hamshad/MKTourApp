import 'package:flutter/material.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import '../../core/theme.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/widgets/platform_map.dart';
import 'dart:async';
import '../../core/api_service.dart';
import 'widgets/vehicle_selection_widget.dart';
import 'package:latlong2/latlong.dart' as latLng;
import '../ride/ride_detail_screen.dart';
import '../ride/ride_assigned_screen.dart';

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
  
  final GeocodingService _geocodingService = GeocodingService();
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = false;
  
  // Map State
  final LatLng _center = const LatLng(51.5074, -0.1278); // Default London
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
    // Auto-focus dropoff field if not in route view
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isRouteView) {
        _dropoffFocus.requestFocus();
      }
    });
    
    _dropoffController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _dropoffFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    final query = _dropoffController.text;
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _isLoading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 800), () async {
      setState(() => _isLoading = true);
      
      final results = await _geocodingService.searchAddress(query);
      
      if (mounted) {
        setState(() {
          _suggestions = results;
          _isLoading = false;
        });
      }
    });
  }

  void _selectDestination(String name, String address, double lat, double lng) {
    setState(() {
      _dropoffController.text = name;
      _dropoffFocus.unfocus();
      _isRouteView = true;
      _suggestions = [];
      
      // Update Markers
      _markers = [
        MapMarker(
          id: 'pickup',
          lat: _center.latitude,
          lng: _center.longitude,
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
          lat: lat,
          lng: lng,
          child: const Icon(Icons.location_on, color: Colors.black, size: 40),
          title: name,
        ),
      ];
      
      // Simple straight line for now (mock path)
      _polylines = [
        _center,
        LatLng(lat, lng),
      ];
      
      // Calculate Bounds
      _mapBounds = fmap.LatLngBounds.fromPoints(_polylines);
    });

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
                color: Colors.black,
                width: 4.0,
              ),
            ] : [],
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

  String _selectedVehicle = 'sedan';
  final ApiService _apiService = ApiService();

  // ... existing methods

  void _handleBookRide() async {
    setState(() => _isLoading = true);

    try {
      // Calculate distance
      final distance = const latLng.Distance().as(
        latLng.LengthUnit.Kilometer,
        latLng.LatLng(_center.latitude, _center.longitude),
        latLng.LatLng(_markers[1].lat, _markers[1].lng),
      );

      final pickupLocation = {
        'coordinates': [_center.longitude, _center.latitude],
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
                    _buildTextField(_pickupController, 'Pickup location', false),
                    const Divider(height: 1),
                    _buildTextField(_dropoffController, 'Where to?', true),
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

  Widget _buildTextField(TextEditingController controller, String hint, bool autoFocus) {
    return TextField(
      controller: controller,
      focusNode: autoFocus ? _dropoffFocus : null,
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
        final name = place['display_name'].toString().split(',')[0];
        final address = place['display_name'].toString();
        // Fix: Ensure we convert to string before parsing to avoid type errors if value is already double
        final lat = double.tryParse(place['lat']?.toString() ?? '0') ?? 0.0;
        final lon = double.tryParse(place['lon']?.toString() ?? '0') ?? 0.0;
        
        return _buildDestinationRow(
          icon: Icons.location_on,
          name: name,
          address: address,
          distance: '', 
          onTap: () => _selectDestination(name, address, lat, lon),
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
               _selectDestination(place['name']!, place['address']!, lat, lng);
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


