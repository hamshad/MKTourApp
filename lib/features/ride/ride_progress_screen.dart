import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme.dart';
import '../../core/widgets/platform_map.dart';
import '../../core/services/socket_service.dart';
import '../../core/services/navigation_service.dart';
import '../../core/services/places_service.dart';

class RideProgressScreen extends StatefulWidget {
  const RideProgressScreen({super.key});

  @override
  State<RideProgressScreen> createState() => _RideProgressScreenState();
}

class _RideProgressScreenState extends State<RideProgressScreen> {
  String _status = 'Finding your driver...';
  double _progress = 0.2;
  
  // Live Tracking
  final SocketService _socketService = SocketService();
  final NavigationService _navigationService = NavigationService();
  final PlacesService _placesService = PlacesService();
  LatLng _driverLocation = const LatLng(51.5074, -0.1278); // Default fallback
  LatLng _userLocation = const LatLng(51.5085, -0.1260); // Default user loc
  LatLng _dropoffLocation = const LatLng(51.5100, -0.1250); // Default dropoff
  
  // Navigation
  NavigationState? _navigationState;
  List<MapPolyline> _polylines = [];
  String _dropoffAddress = 'Destination';
  double _bearing = 0.0;
  double _tilt = 45.0; // Navigation tilt
  
  @override
  void initState() {
    super.initState();
    _initSocketListener();
    _fetchDetailedAddress();
    _setupNavigation();
  }
  
  void _initSocketListener() {
    _socketService.initSocket();
    
    // Listen for driver location updates
    _socketService.on('driver:locationUpdate', (data) {
       debugPrint('📍 [RideProgressScreen] Driver location update: $data');
       if (data != null && data['latitude'] != null && data['longitude'] != null && mounted) {
          setState(() {
             _driverLocation = LatLng(
               double.parse(data['latitude'].toString()), 
               double.parse(data['longitude'].toString())
             );
          });
       }
    });

    // Listen for ride status updates
    _socketService.on('ride:statusUpdate', (data) {
       if (mounted) {
          final newStatus = data['status'];
          setState(() {
             if (newStatus == 'accepted') {
                _status = 'Driver is on the way';
                _progress = 0.4;
             } else if (newStatus == 'arrived') {
                _status = 'Driver has arrived';
                _progress = 0.6;
             } else if (newStatus == 'in_progress') {
                _status = 'Heading to destination';
                _progress = 0.8;
             } else if (newStatus == 'completed') {
                _status = 'You have arrived!';
                _progress = 1.0;
             }
          });
       }
    });
  }
  
  /// Fetch detailed address for dropoff location
  Future<void> _fetchDetailedAddress() async {
    final address = await _placesService.getAddressFromLatLng(
      _dropoffLocation.latitude,
      _dropoffLocation.longitude,
    );
    if (mounted) {
      setState(() {
        _dropoffAddress = address ?? 'Destination';
      });
    }
  }
  
  /// Setup navigation
  Future<void> _setupNavigation() async {
    // Listen to navigation updates
    _navigationService.routeUpdates.listen((state) {
      if (mounted) {
        setState(() {
          _navigationState = state;
          _bearing = state.bearing;
          _updatePolylines();
        });
      }
    });
    
    // Fetch initial route
    await _fetchNavigationRoute();
  }
  
  /// Fetch navigation route from current location to dropoff
  Future<void> _fetchNavigationRoute() async {
    await _navigationService.fetchRoute(
      originLat: _driverLocation.latitude,
      originLng: _driverLocation.longitude,
      destLat: _dropoffLocation.latitude,
      destLng: _dropoffLocation.longitude,
    );
  }
  
  /// Update navigation route in real-time
  Future<void> _updateNavigationRoute() async {
    await _navigationService.updateRoute(
      currentLat: _driverLocation.latitude,
      currentLng: _driverLocation.longitude,
      destLat: _dropoffLocation.latitude,
      destLng: _dropoffLocation.longitude,
    );
  }
  
  /// Update polylines with navigation route
  void _updatePolylines() {
    if (_navigationState != null && _navigationState!.polyline.isNotEmpty) {
      _polylines = [
        MapPolyline(
          id: 'navigation_route',
          points: _navigationState!.polyline,
          color: AppTheme.primaryColor,
          width: 5.0,
        ),
      ];
    }
  }

  @override
  void dispose() {
    _socketService.off('driver:locationUpdate');
    _socketService.off('ride:statusUpdate');
    _navigationService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map
          PlatformMap(
            initialLat: _driverLocation.latitude,
            initialLng: _driverLocation.longitude,
            bearing: _bearing,
            tilt: _tilt,
            markers: [
              MapMarker(
                id: 'driver',
                lat: _driverLocation.latitude,
                lng: _driverLocation.longitude,
                child: const Icon(Icons.directions_car, color: AppTheme.primaryColor, size: 40),
                title: 'Driver',
              ),
              MapMarker(
                id: 'user',
                lat: _userLocation.latitude,
                lng: _userLocation.longitude,
                child: const Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
                title: 'You',
              ),
              MapMarker(
                id: 'dropoff',
                lat: _dropoffLocation.latitude,
                lng: _dropoffLocation.longitude,
                child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                title: 'Destination',
              ),
            ],
            polylines: _polylines,
          ),
          
          // Back Button
          Positioned(
            top: 40,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          
          // Status Panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Status
                  Text(
                    _status,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Colors.grey[100],
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                  ),
                  const SizedBox(height: 16),
                  
                  // Route Info
                  if (_navigationState != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.navigation, color: AppTheme.primaryColor, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                _navigationState!.distanceText,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Icon(Icons.schedule, color: AppTheme.primaryColor, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                _navigationState!.etaText,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  
                  // Driver Info
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: AppTheme.surfaceColor,
                        child: Icon(Icons.person, size: 28, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Michael',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Row(
                            children: [
                              const Text(
                                'Toyota Prius • ABC 123',
                                style: TextStyle(color: AppTheme.textSecondary),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.star, size: 12, color: Colors.amber),
                                    SizedBox(width: 2),
                                    Text(
                                      '4.9',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                      Column(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.phone, color: AppTheme.primaryColor),
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: const Icon(Icons.message, color: AppTheme.primaryColor),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {},
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Cancel Ride',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.grey[100],
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Share Status',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
